#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1")
    . (Join-Path $Script:QmPrivatePath "Open-QueryDetailForm.ps1")
    . (Join-Path $Script:QmPrivatePath "Rename-SqlQuery.ps1")

    $script:Errors = [System.Collections.Generic.List[string]]::new()
    function Write-ContainedErrorLog { param([Parameter(ValueFromPipeline = $true)][string]$Message, $ErrorObject) process { $script:Errors.Add($Message) } }
    function Invoke-SavedQueryRequest { param($Request) }
    function Update-DataGridColumnWidth { param($Grid, $Item) }
    # The highlighted view is a RichTextBox; its stand-in keeps the text it was given.
    function Set-SqlRichText { param($RichTextBox, $Text) $RichTextBox.Text = $Text }
}

Describe 'Get-QueryDetailOwnership' -Tag 'Unit' {
    It 'Should use the ownership the query manager read' {
        $Script:QueryManagerForm = [PSCustomObject]@{ Ownership = @{ "1" = "x" } }
        (Get-QueryDetailOwnership)["1"] | Should -Be "x"
    }

    It 'Should give none when the query manager has no ownership table' {
        $Script:QueryManagerForm = [PSCustomObject]@{ Ownership = "not a table" }
        (Get-QueryDetailOwnership).Count | Should -Be 0
    }

    It 'Should give none without a query manager' {
        $Script:QueryManagerForm = $null
        (Get-QueryDetailOwnership).Count | Should -Be 0
    }
}

Describe 'Update-QueryDetailForm' -Tag 'Unit' {
    BeforeEach {
        $script:Errors.Clear()
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://t" }
        $Script:QueryDetailForm = [PSCustomObject]@{
            Query      = [PSCustomObject]@{ DoId = "10521"; DisplayName = "Old name" }
            Definition = [PSCustomObject]@{ Title = "" }
            Elements   = [PSCustomObject]@{
                TextBlockQueryTitle     = [PSCustomObject]@{ Text = "" }
                DataGridQueryProperties = [PSCustomObject]@{ ItemsSource = $null }
                RichTextBoxQueryText        = [PSCustomObject]@{ Text = "" }
                DataGridQueryHistory    = [PSCustomObject]@{ ItemsSource = $null }
            }
        }
        Mock Invoke-SavedQueryRequest {
            if ($Request.Method -eq "GET") { [PSCustomObject]@{ Succeeded = $true; Result = (Get-QmFixture "odata.queryobject.json") } }
            else { [PSCustomObject]@{ Succeeded = $true; Result = (Get-QmFixture "asmx.paging.history.json") } }
        }
    }

    It 'Should read the object and its history for the query it shows' {
        Update-QueryDetailForm

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like "*C_P_SQLTROUBLESHOOTING(10521)" }
        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Body.dataTypeArgs.dataObjectId -eq "10521" }
    }

    It 'Should show the name, the fields, the SQL and the history' {
        Update-QueryDetailForm

        $Script:QueryDetailForm.Query.DisplayName | Should -Be "Data object overview"
        $Script:QueryDetailForm.Definition.Title | Should -Be "Query details - Data object overview"
        $Script:QueryDetailForm.Elements.TextBlockQueryTitle.Text | Should -Be "Data object overview  (10521)"
        $Script:QueryDetailForm.Elements.RichTextBoxQueryText.Text | Should -Match "FROM dbo.tblDataObject"
        @($Script:QueryDetailForm.Elements.DataGridQueryProperties.ItemsSource | ForEach-Object Property) | Should -Contain "Created by"
        @($Script:QueryDetailForm.Elements.DataGridQueryHistory.ItemsSource).Count | Should -Be 2
    }

    It 'Should still show the history, and report, when the object cannot be read' {
        Mock Invoke-SavedQueryRequest {
            if ($Request.Method -eq "GET") { [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = "404" } }
            else { [PSCustomObject]@{ Succeeded = $true; Result = (Get-QmFixture "asmx.paging.history.json") } }
        }

        Update-QueryDetailForm

        $script:Errors[0] | Should -Match "Reading query 'Old name' failed: 404"
        $Script:QueryDetailForm.Query.DisplayName | Should -Be "Old name"
        @($Script:QueryDetailForm.Elements.DataGridQueryHistory.ItemsSource).Count | Should -Be 2
        $Script:QueryDetailForm.Elements.RichTextBoxQueryText.Text | Should -Be ""
    }

    It 'Should still show the object, and report, when its history cannot be read' {
        Mock Invoke-SavedQueryRequest {
            if ($Request.Method -eq "GET") { [PSCustomObject]@{ Succeeded = $true; Result = (Get-QmFixture "odata.queryobject.json") } }
            else { [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = "500" } }
        }

        Update-QueryDetailForm

        $script:Errors[0] | Should -Match "Reading the history of query 'Old name' failed: 500"
        @($Script:QueryDetailForm.Elements.DataGridQueryHistory.ItemsSource).Count | Should -Be 0
        $Script:QueryDetailForm.Elements.RichTextBoxQueryText.Text | Should -Match "SELECT"
    }
}
