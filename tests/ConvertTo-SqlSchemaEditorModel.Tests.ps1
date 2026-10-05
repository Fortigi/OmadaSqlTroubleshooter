#Requires -Version 7.0
# Issue #158 extracted the editor's schema model out of Complete-SqlSchemaRetrieval so that a
# database other than the active one is normalised by exactly the same code. These tests pin the
# normalisation rules, which are the ones the completion list and the validation index both depend on
# agreeing about: a disagreement between them would mean the editor completing a table the
# validation pass then warns about, or the other way round.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SqlSchemaEditorModel.ps1")

    function New-SchemaResponse {
        param([hashtable]$Table)

        $Payload = [PSCustomObject]@{}
        foreach ($Key in $Table.Keys) {
            $Payload | Add-Member -MemberType NoteProperty -Name $Key -Value $Table[$Key]
        }

        return [PSCustomObject]@{ d = $Payload }
    }
}

Describe "ConvertTo-SqlSchemaEditorModel" {
    It "groups tables under their schema" {
        $Model = ConvertTo-SqlSchemaEditorModel -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.tblObject" = @("Id int")
                "dbo.tblValue"  = @("Id int")
                "cag.ObjectTable" = @("Id int")
            })

        @($Model.Keys | Sort-Object) | Should -Be @("cag", "dbo")
        @($Model["dbo"].Keys | Sort-Object) | Should -Be @("tblObject", "tblValue")
    }

    It "splits a column entry into name and type" {
        $Model = ConvertTo-SqlSchemaEditorModel -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.tblObject" = @("DisplayName nvarchar(50)")
            })

        $Model["dbo"]["tblObject"][0].n | Should -Be "DisplayName"
        $Model["dbo"]["tblObject"][0].t | Should -Be "nvarchar(50)"
    }

    It "keeps a type that contains spaces intact" {
        # The remainder after the FIRST run of whitespace is the type, all of it. Splitting on every
        # space would report the type as "nvarchar(50)" and silently drop "NOT NULL".
        $Model = ConvertTo-SqlSchemaEditorModel -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.tblObject" = @("DisplayName nvarchar(50) NOT NULL")
            })

        $Model["dbo"]["tblObject"][0].t | Should -Be "nvarchar(50) NOT NULL"
    }

    It "gives a column with no type an empty type rather than dropping it" {
        $Model = ConvertTo-SqlSchemaEditorModel -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.tblObject" = @("Id")
            })

        $Model["dbo"]["tblObject"][0].n | Should -Be "Id"
        $Model["dbo"]["tblObject"][0].t | Should -Be ""
    }

    It "splits the property name on the FIRST dot, so a dotted table name survives" {
        # The schema name is always in front; a table may legitimately contain a dot. Splitting on
        # the last dot would file "dbo.my.table" under schema "dbo.my".
        $Model = ConvertTo-SqlSchemaEditorModel -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.my.table" = @("Id int")
            })

        $Model.ContainsKey("dbo") | Should -BeTrue
        $Model["dbo"].ContainsKey("my.table") | Should -BeTrue
    }

    It "serialises a single-column table as a JSON array" {
        # The editor's normalizeColumn only maps arrays, so a lone object would give that table no
        # columns at all - and a one-column table is not rare.
        $Model = ConvertTo-SqlSchemaEditorModel -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.tblOne" = @("Id int")
            })

        $Json = $Model | ConvertTo-Json -Depth 5
        $Json | Should -Match '"tblOne"\s*:\s*\['
    }

    It "returns an empty model for a null response" {
        $Model = ConvertTo-SqlSchemaEditorModel -SchemaResponse $null

        # An empty hashtable, not $null: the caller serialises whatever comes back, and $null would
        # push "setSchema(null)". Asserted through Count and the type, because an empty collection is
        # itself "empty" to -BeNullOrEmpty.
        $Model | Should -BeOfType [hashtable]
        $Model.Count | Should -Be 0
    }

    It "returns an empty model for an ErrorRecord" {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("boom"), "OmadaSchemaFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        (ConvertTo-SqlSchemaEditorModel -SchemaResponse $ErrorRecord).Count | Should -Be 0
    }

    It "returns an empty model for a response with no payload" {
        (ConvertTo-SqlSchemaEditorModel -SchemaResponse ([PSCustomObject]@{ d = $null })).Count | Should -Be 0
    }

    It "serialises an empty model as {} rather than as null" {
        # What tells the editor "this database has nothing", instead of leaving it showing the
        # previous database's completions.
        (ConvertTo-SqlSchemaEditorModel -SchemaResponse $null | ConvertTo-Json -Depth 5) | Should -Be "{}"
    }
}
