#Requires -Version 7.0
# The SQL schema request as a worker chain: fetch the schema, and build the editor's JSON and the
# validation index there instead of on the UI thread when it lands (about two seconds per connect on a
# cloud PC).
#
# What is asserted: the values it builds are exactly the ones the UI thread would have built; a failure
# is reported as one; a builder that fails costs only its own value; and the chain really runs in a
# runspace that has nothing but the files the chain table lists.

BeforeAll {
    $script:PrivatePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $script:PrivatePath -ChildPath "ConvertTo-SqlSchemaEditorModel.ps1")
    . (Join-Path $script:PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")
    . (Join-Path $script:PrivatePath -ChildPath "Invoke-OmadaSqlSchemaPipeline.ps1")
    . (Join-Path $script:PrivatePath -ChildPath "Get-OmadaPipelineWorkerFunction.ps1")

    # Deliberately NO Write-LogOutput here: the chain runs in a worker that has none, so calling it would
    # fail these tests the way it would fail in the worker.

    function Invoke-OmadaRequestCore {
        param([hashtable]$Parameters)
        $script:CoreParameters = $Parameters
        return $script:CoreOutcome
    }

    function script:New-SchemaResponse {
        $Private:Payload = [PSCustomObject]@{}
        $Private:Payload | Add-Member -NotePropertyName "dbo.tblCustomer" -NotePropertyValue @("Id int NOT NULL", "Name nvarchar(50)")
        $Private:Payload | Add-Member -NotePropertyName "stage.tblOrder" -NotePropertyValue @("Id int")
        return [PSCustomObject]@{ d = $Private:Payload }
    }

    function script:Get-CodeOnly {
        param([string]$Path)
        $Private:Tokens = $null
        $Private:Errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Private:Tokens, [ref]$Private:Errors)
        return (($Private:Tokens | Where-Object { $_.Kind -ne "Comment" }).Text -join " ")
    }
}

Describe "Invoke-OmadaSqlSchemaPipeline - a schema that was retrieved" {

    BeforeEach {
        $script:Response = New-SchemaResponse
        $script:CoreOutcome = @{ Result = $script:Response; ErrorRecord = $null }
        $script:Outcome = Invoke-OmadaSqlSchemaPipeline -Context @{ Parameters = @{ Uri = "https://tenant.example/webservice/SyntaxHighlighting.asmx/GetSqlSchema"; Method = "POST" } }
    }

    It "sends the request it was given" {
        $script:CoreParameters.Uri | Should -BeLike "*GetSqlSchema"
        $script:CoreParameters.Method | Should -Be "POST"
    }

    It "marks itself, and carries the response" {
        $script:Outcome.IsSqlSchemaPipeline | Should -BeTrue
        [object]::ReferenceEquals($script:Outcome.Result, $script:Response) | Should -BeTrue
        $script:Outcome.ErrorRecord | Should -BeNullOrEmpty
    }

    It "builds the editor JSON the UI thread would have built" {
        $script:Outcome.EditorJson | Should -BeExactly (ConvertTo-SqlSchemaEditorModel -SchemaResponse $script:Response | ConvertTo-Json -Depth 5 -Compress)
    }

    It "builds the validation index the UI thread would have built" {
        @($script:Outcome.SchemaModel.Table.Keys | Sort-Object) | Should -Be @("dbo.tblCustomer", "stage.tblOrder")
        $script:Outcome.SchemaModel.Table["dbo.tblCustomer"].Column["Id"] | Should -BeExactly "int NOT NULL"
    }

    It "records the response for the UI thread to log, without formatting it" {
        $Private:Entry = @($script:Outcome.Log | Where-Object { $_.Format -eq "Result: {0}" })
        $Private:Entry.Count | Should -Be 1
        $Private:Entry[0].Level | Should -Be "VERBOSE"
        [object]::ReferenceEquals($Private:Entry[0].Redact, $script:Response) | Should -BeTrue
    }
}

Describe "Invoke-OmadaSqlSchemaPipeline - a request that failed" {

    It "reports the failure and builds nothing" {
        $Private:Failure = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("500"), "x", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
        $script:CoreOutcome = @{ Result = $null; ErrorRecord = $Private:Failure }

        $Private:Outcome = Invoke-OmadaSqlSchemaPipeline -Context @{ Parameters = @{} }

        [object]::ReferenceEquals($Private:Outcome.ErrorRecord, $Private:Failure) | Should -BeTrue
        $Private:Outcome.Result | Should -BeNullOrEmpty
        $Private:Outcome.EditorJson | Should -BeNullOrEmpty
        $Private:Outcome.SchemaModel | Should -BeNullOrEmpty
    }

    It "builds nothing for a response without a payload" {
        $script:CoreOutcome = @{ Result = [PSCustomObject]@{ d = $null }; ErrorRecord = $null }

        $Private:Outcome = Invoke-OmadaSqlSchemaPipeline -Context @{ Parameters = @{} }

        $Private:Outcome.ErrorRecord | Should -BeNullOrEmpty
        $Private:Outcome.EditorJson | Should -BeNullOrEmpty
        $Private:Outcome.SchemaModel | Should -BeNullOrEmpty
    }
}

Describe "Invoke-OmadaSqlSchemaPipeline - a builder that fails" {
    # The derived values are an optimisation: one that cannot be built is left to the UI thread.

    BeforeEach {
        $script:CoreOutcome = @{ Result = (New-SchemaResponse); ErrorRecord = $null }
    }

    It "still returns the response and the index when the editor model fails" {
        Mock ConvertTo-SqlSchemaEditorModel { throw "boom" }

        $Private:Outcome = Invoke-OmadaSqlSchemaPipeline -Context @{ Parameters = @{} }

        $Private:Outcome.Result | Should -Not -BeNullOrEmpty
        $Private:Outcome.EditorJson | Should -BeNullOrEmpty
        $Private:Outcome.SchemaModel | Should -Not -BeNullOrEmpty
        @($Private:Outcome.Log | Where-Object { $_.Text -like "*editor model could not be built*" }).Count | Should -Be 1
    }

    It "still returns the response and the JSON when the index fails" {
        Mock Get-SqlSchemaModel { throw "boom" }

        $Private:Outcome = Invoke-OmadaSqlSchemaPipeline -Context @{ Parameters = @{} }

        $Private:Outcome.EditorJson | Should -Not -BeNullOrEmpty
        $Private:Outcome.SchemaModel | Should -BeNullOrEmpty
    }
}

Describe "Invoke-OmadaSqlSchemaPipeline - it is a worker chain" {

    It "is registered with every file it needs, so the build ships them" {
        $Script:OmadaWorkerChainFile["Invoke-OmadaSqlSchemaPipeline"] | Should -Be @("ConvertTo-SqlSchemaEditorModel.ps1", "Get-SqlSchemaModel.ps1", "Invoke-OmadaSqlSchemaPipeline.ps1")
        Get-OmadaWorkerRuntimeFile | Should -Contain "Invoke-OmadaSqlSchemaPipeline.ps1"
    }

    It "passes the dispatch's pre-flight check" {
        Test-OmadaPipelineWorkerChain -PipelineFunction "Invoke-OmadaSqlSchemaPipeline" -PipelineFiles $Script:OmadaWorkerChainFile["Invoke-OmadaSqlSchemaPipeline"] | Should -BeTrue
    }

    It "reads no module state, writes no log and touches no WPF" {
        $Private:Code = Get-CodeOnly -Path (Join-Path $script:PrivatePath "Invoke-OmadaSqlSchemaPipeline.ps1")

        $Private:Code | Should -Not -Match '\$Script:'
        $Private:Code | Should -Not -Match 'Write-LogOutput'
        $Private:Code | Should -Not -Match 'System\.Windows'
    }

    It "runs in a fresh runspace that has only the chain's files" {
        # What the worker actually does: dot-source the listed files, nothing else, and call the chain.
        $Private:Shell = [powershell]::Create()
        try {
            [void]$Private:Shell.AddScript({
                    param($PrivateFolder, $Files)
                    foreach ($File in $Files) {
                        . (Join-Path $PrivateFolder $File)
                    }

                    function Invoke-OmadaRequestCore {
                        param([hashtable]$Parameters)
                        $Payload = [PSCustomObject]@{}
                        $Payload | Add-Member -NotePropertyName "dbo.tblCustomer" -NotePropertyValue @("Id int")
                        return @{ Result = [PSCustomObject]@{ d = $Payload }; ErrorRecord = $null }
                    }

                    Invoke-OmadaSqlSchemaPipeline -Context @{ Parameters = @{} }
                }).AddArgument($script:PrivatePath).AddArgument($Script:OmadaWorkerChainFile["Invoke-OmadaSqlSchemaPipeline"])

            $Private:Outcome = @($Private:Shell.Invoke())[0]

            $Private:Shell.HadErrors | Should -BeFalse
            $Private:Outcome.EditorJson | Should -BeLike "*tblCustomer*"
            $Private:Outcome.SchemaModel.Table.ContainsKey("dbo.tblCustomer") | Should -BeTrue
        }
        finally {
            $Private:Shell.Dispose()
        }
    }
}
