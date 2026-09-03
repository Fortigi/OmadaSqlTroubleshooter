#Requires -Version 7.0
# Every URL and body the execute path sends, asserted directly (issue #40, C1-5).
#
# Before this function existed, "which URL does saving a query use, and when is the body empty?"
# could only be answered by running the app against a tenant - the rules were interleaved with
# logging, $Script: reads and WPF. Being pure is what makes them testable, and being ONE definition
# is what stops the UI-thread path and the background pipeline drifting apart.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "New-OmadaQueryRequest.ps1")

    $script:Base = "https://tenant.omada.cloud"

    function script:New-SaveContext {
        param(
            $QueryText = "SELECT 1",
            $CurrentQueryText = "SELECT 1",
            $SavedQueryText = "SELECT 1",
            $DisplayName = "TestQuery",
            $CurrentDisplayName = "TestQuery",
            $DataConnectionDoId = "42"
        )
        return @{
            BaseUrl            = $script:Base
            QueryDoId          = 100
            QueryText          = $QueryText
            CurrentQueryText   = $CurrentQueryText
            SavedQueryText     = $SavedQueryText
            DisplayName        = $DisplayName
            CurrentDisplayName = $CurrentDisplayName
            DataConnectionDoId = $DataConnectionDoId
        }
    }
}

Describe "New-OmadaQueryRequest -Kind SaveExistingQuery" {
    It "returns null when neither the text nor the name has changed" {
        # The "No changes detected! Saving not needed." branch, which must stay a NON-request: it is
        # what keeps an execute from writing to the tenant every single time.
        New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context (New-SaveContext) | Should -BeNullOrEmpty
    }

    It "sends the query text when the editor differs from what this session last saved" {
        $Request = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context (New-SaveContext -QueryText "SELECT 2" -SavedQueryText "SELECT 2")

        $Request.Method | Should -Be "PUT"
        $Request.Uri | Should -Be "$script:Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING(100)"
        $Request.Body["C_QUERY"] | Should -Be "SELECT 2"
    }

    It "sends the query text when the editor differs from what the SERVER holds" {
        # Both comparisons matter: another tab (or another person) can have changed the stored query
        # since this session last saved it.
        $Request = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context (New-SaveContext -SavedQueryText "SELECT 999")

        $Request.Body["C_QUERY"] | Should -Be "SELECT 1"
    }

    It "carries the data connection alongside a changed query text" {
        $Request = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context (New-SaveContext -QueryText "SELECT 2" -SavedQueryText "SELECT 2")

        $Request.Body["C_SQLTROUBLESHOOTING_DATACONNECTION"].Id | Should -Be "42"
    }

    It "omits the data connection when none is selected" {
        $Request = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context (New-SaveContext -QueryText "SELECT 2" -SavedQueryText "SELECT 2" -DataConnectionDoId $null)

        $Request.Body.ContainsKey("C_SQLTROUBLESHOOTING_DATACONNECTION") | Should -BeFalse
    }

    It "sends only the name when just the Display name changed" {
        $Request = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context (New-SaveContext -DisplayName "RenamedQuery")

        $Request.Body["NAME"] | Should -Be "RenamedQuery"
        $Request.Body.ContainsKey("C_QUERY") | Should -BeFalse
    }

    It "sends both when both changed" {
        $Request = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context (New-SaveContext -QueryText "SELECT 2" -SavedQueryText "SELECT 2" -DisplayName "RenamedQuery")

        $Request.Body["C_QUERY"] | Should -Be "SELECT 2"
        $Request.Body["NAME"] | Should -Be "RenamedQuery"
    }
}

Describe "New-OmadaQueryRequest -Kind ExecuteQuery" {
    It "posts GetPagingData for the target id" {
        $Request = New-OmadaQueryRequest -Kind "ExecuteQuery" -Context @{ BaseUrl = $script:Base; TargetQueryDoId = 555 }

        $Request.Method | Should -Be "POST"
        $Request.Uri | Should -Be "$script:Base/webservice/jQGridPopulationWebService.asmx/GetPagingData"
        $Request.Body["dataType"] | Should -Be "SqlDataProducer"
        $Request.Body["dataTypeArgs"]["targetId"] | Should -Be 555
        $Request.Body["rows"] | Should -Be 100000
    }
}

Describe "New-OmadaQueryRequest -Kind TempQuery*" {
    It "probes for the temporary object including deleted ones" {
        # DeletedStatus=Both is essential: the temporary object is soft-deleted after every run, so
        # the one being looked for is normally in the deleted set. Without it every execute-selection
        # run would create a new object instead of reusing the one shared name.
        $Request = New-OmadaQueryRequest -Kind "TempQueryProbe" -Context @{ BaseUrl = $script:Base; TempName = "TMP_abc" }

        $Request.Method | Should -Be "GET"
        $Request.Uri | Should -Match "DeletedStatus=Both"
        $Request.Uri | Should -Match "NAME eq 'TMP_abc'"
        $Request.Body | Should -BeNullOrEmpty
    }

    It "undeletes with a pre-serialized JSON body" {
        # This ASMX endpoint takes a JSON string, unlike the OData endpoints which take the object.
        $Request = New-OmadaQueryRequest -Kind "TempQueryUndelete" -Context @{ BaseUrl = $script:Base; TempQueryDoId = 777 }

        $Request.Method | Should -Be "POST"
        $Request.Uri | Should -Be "$script:Base/WebService/DataObjectWebService.asmx/UndeleteDataObject"
        $Request.Body | Should -BeOfType [string]
        ($Request.Body | ConvertFrom-Json).id | Should -Be 777
    }

    It "PUTs onto a recovered temporary object" {
        $Request = New-OmadaQueryRequest -Kind "TempQueryUpsert" -Context @{
            BaseUrl = $script:Base; TempName = "TMP_abc"; SelectionText = "SELECT TOP 1 *"; TempQueryDoId = 777
        }

        $Request.Method | Should -Be "PUT"
        $Request.Uri | Should -Be "$script:Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING(777)"
        $Request.Body["C_QUERY"] | Should -Be "SELECT TOP 1 *"
        $Request.Body["NAME"] | Should -Be "TMP_abc"
    }

    It "POSTs a new temporary object when there is none to recover" {
        $Request = New-OmadaQueryRequest -Kind "TempQueryUpsert" -Context @{
            BaseUrl = $script:Base; TempName = "TMP_abc"; SelectionText = "SELECT TOP 1 *"; TempQueryDoId = $null
        }

        $Request.Method | Should -Be "POST"
        $Request.Uri | Should -Be "$script:Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING"
    }
}

Describe "New-OmadaQueryRequest -Kind DeleteQuery" {
    It "deletes by id" {
        $Request = New-OmadaQueryRequest -Kind "DeleteQuery" -Context @{ BaseUrl = $script:Base; TempQueryDoId = 777 }

        $Request.Method | Should -Be "DELETE"
        $Request.Uri | Should -Be "$script:Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING(777)"
        $Request.Body | Should -BeNullOrEmpty
    }
}

Describe "New-OmadaQueryRequest is runspace-safe" {
    It "runs in a bare runspace with none of this module's state or functions" {
        # It is executed inside a worker by Invoke-OmadaExecutePipeline, so a $Script: read or a call
        # to a private function added here later would break every background execute with a
        # CommandNotFoundException that no ordinary unit test would catch.
        $Shell = [powershell]::Create()
        try {
            [void]$Shell.AddScript({
                    param($Path)
                    . $Path
                    return (New-OmadaQueryRequest -Kind "DeleteQuery" -Context @{ BaseUrl = "https://x"; TempQueryDoId = 1 }).Method
                }).AddArgument((Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private\New-OmadaQueryRequest.ps1"))

            $Output = $Shell.Invoke()

            $Shell.Streams.Error | Should -BeNullOrEmpty
            $Output[0] | Should -Be "DELETE"
        }
        finally {
            $Shell.Dispose()
        }
    }
}
