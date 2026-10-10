#Requires -Version 7.0
# The index the schema validation pass resolves identifiers against (issue #61).
#
# Rewritten as a single pass for speed - 0.2 s instead of 0.7 s for a 565-table database on the UI
# thread - so these cases pin what it must still produce: the same three lookups, the same splitting
# rules as the editor model, and "no schema" rather than an empty one.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")

    $script:LogCount = 0
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog)
        process { $script:LogCount++ }
    }

    function script:New-SchemaResponse {
        param([System.Collections.Specialized.OrderedDictionary]$Table)

        $Private:Payload = [PSCustomObject]@{}
        foreach ($Private:Key in $Table.Keys) {
            $Private:Payload | Add-Member -NotePropertyName $Private:Key -NotePropertyValue $Table[$Private:Key]
        }

        return [PSCustomObject]@{ d = $Private:Payload }
    }
}

Describe "Get-SqlSchemaModel" {

    It "indexes every table under its full name, its schema and its table name" {
        $Model = Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{
                    "dbo.tblObject" = @("Id int")
                    "cag.tblObject" = @("Id int")
                    "dbo.tblValue"  = @("Id int")
                }))

        @($Model.Table.Keys | Sort-Object) | Should -Be @("cag.tblObject", "dbo.tblObject", "dbo.tblValue")
        @($Model.BySchema["dbo"].Keys | Sort-Object) | Should -Be @("tblObject", "tblValue")
        @($Model.ByTableName["tblObject"]).Count | Should -Be 2
    }

    It "splits a column entry on the first run of whitespace and keeps the rest as the type" {
        $Model = Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{
                    "dbo.tblObject" = @("DisplayName   nvarchar(50) NOT NULL", "Id")
                }))

        $Model.Table["dbo.tblObject"].Column["DisplayName"] | Should -BeExactly "nvarchar(50) NOT NULL"
        $Model.Table["dbo.tblObject"].Column["Id"] | Should -BeExactly ""
    }

    It "splits the table name on the first dot only" {
        $Model = Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.my.table" = @("Id int") }))

        $Model.BySchema["dbo"].ContainsKey("my.table") | Should -BeTrue
    }

    It "skips blank column entries" {
        $Model = Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tblObject" = @("Id int", "", "   ") }))

        @($Model.Table["dbo.tblObject"].Column.Keys) | Should -Be @("Id")
    }

    It "matches names case-insensitively, as SQL Server does" {
        $Model = Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tblObject" = @("DisplayName nvarchar(50)") }))

        $Model.BySchema["DBO"]["TBLOBJECT"].Column["displayname"] | Should -BeExactly "nvarchar(50)"
    }

    It "answers no schema for a name without a table part" {
        Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "nodot" = @("Id int") })) | Should -BeNullOrEmpty
    }

    It "answers no schema for a payload that is not an object" {
        # A string payload has a Length property, which is not a table.
        Get-SqlSchemaModel -SchemaResponse ([PSCustomObject]@{ d = "not a schema" }) | Should -BeNullOrEmpty
    }

    It "logs the table count, and nothing with -NoLog, which the background worker uses" {
        # A worker has no Write-LogOutput: calling it there would throw and cost the index.
        $script:LogCount = 0
        Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tblObject" = @("Id int") })) | Out-Null
        $script:LogCount | Should -Be 1

        $script:LogCount = 0
        $Model = Get-SqlSchemaModel -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tblObject" = @("Id int") })) -NoLog
        $script:LogCount | Should -Be 0
        $Model.Table.ContainsKey("dbo.tblObject") | Should -BeTrue
    }

    It "answers no schema for null, an ErrorRecord, or no payload" {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("boom"), "OmadaSchemaFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        Get-SqlSchemaModel -SchemaResponse $null | Should -BeNullOrEmpty
        Get-SqlSchemaModel -SchemaResponse $ErrorRecord | Should -BeNullOrEmpty
        Get-SqlSchemaModel -SchemaResponse ([PSCustomObject]@{ d = $null }) | Should -BeNullOrEmpty
    }
}
