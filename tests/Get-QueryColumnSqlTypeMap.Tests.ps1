#Requires -Version 7.0
# Tests for priority 1 of issue #103's type resolution - the seam issue #120 found unimplemented.
#
# The schema is a real Get-SqlSchemaModel index built from the same response shape
# SyntaxHighlighting.asmx/GetSqlSchema returns, and the queries are parsed by the real pinned
# ScriptDom. Both are what the application uses, so a test that passes here is a claim about the
# application rather than about a stub.
#
# The table is called IDENTITY in the issue's repro, and IDENTITY is a T-SQL RESERVED WORD: written
# bare it is a parse error, so the map comes back empty. That is not a quirk of the test, it is the
# behaviour - a query that does not parse yields no declared types - and it has a test of its own.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptFragment.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentDescendant.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaDiagnostic.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-QueryColumnSqlTypeMap.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    $Script:LoggedMessage = [System.Collections.Generic.List[object]]::new()

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process {
            $Script:LoggedMessage.Add([PSCustomObject]@{ Message = [string]$Message; LogType = $LogType })
        }
    }

    function New-SchemaModel {
        <#
            The GetSqlSchema response shape: one property per "schema.table", each an array of
            "ColumnName DataType" strings.
        #>
        param(
            [hashtable]$Table
        )

        $Payload = [PSCustomObject]@{}
        foreach ($Name in $Table.Keys) {
            $Payload | Add-Member -MemberType NoteProperty -Name $Name -Value @($Table[$Name])
        }

        return Get-SqlSchemaModel -SchemaResponse ([PSCustomObject]@{ d = $Payload })
    }

    function New-IdentitySchemaModel {
        return New-SchemaModel -Table @{
            "dbo.tblIdentity"   = @("Id int", "Number nvarchar(50)", "DisplayName nvarchar(255)", "CreateTime datetime", "Deleted bit", "ParentID int", "UID uniqueidentifier")
            "dbo.tblResource"   = @("Id int", "ResourceKey nvarchar(128)")
            "audit.tblIdentity" = @("Id bigint", "Note nvarchar(max)")
            "dbo.IDENTITY"      = @("Id int", "Number nvarchar(50)")
        }
    }

    $Script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath
}

Describe "Get-QueryColumnSqlTypeMap" {

    BeforeEach {
        $Script:LoggedMessage.Clear()
    }

    Context "Nothing to resolve against" {
        It "returns an empty map without a schema" {
            (Get-QueryColumnSqlTypeMap -SqlText "SELECT Id FROM dbo.tblIdentity" -SchemaModel $null).Count | Should -Be 0
        }

        It "returns an empty map for an empty query" {
            (Get-QueryColumnSqlTypeMap -SqlText "" -SchemaModel (New-IdentitySchemaModel)).Count | Should -Be 0
        }
    }

    Context "Resolving a declared type" {
        It "types the columns of the one table the query names" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            $Map = Get-QueryColumnSqlTypeMap -SqlText "SELECT TOP 10 Id, Number FROM dbo.tblIdentity" -SchemaModel (New-IdentitySchemaModel)

            $Map["Id"] | Should -BeExactly "int"
            $Map["Number"] | Should -BeExactly "nvarchar(50)"
            $Map["Deleted"] | Should -BeExactly "bit"
        }

        It "resolves a one-part name owned by dbo" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT Id FROM tblIdentity" -SchemaModel (New-IdentitySchemaModel))["Id"] | Should -BeExactly "int"
        }

        It "resolves the issue's own repro when the reserved name is delimited" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT TOP 10 Id, Number FROM [IDENTITY]" -SchemaModel (New-IdentitySchemaModel))["Id"] | Should -BeExactly "int"
        }

        It "matches the column name case-insensitively, as SQL Server resolves identifiers" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT Id FROM dbo.tblIdentity" -SchemaModel (New-IdentitySchemaModel))["iD"] | Should -BeExactly "int"
        }
    }

    Context "Refusing to guess" {
        It "returns an empty map for a query that does not parse" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            # IDENTITY is a reserved word, so this is a syntax error rather than a table reference.
            (Get-QueryColumnSqlTypeMap -SqlText "SELECT Id FROM dbo.IDENTITY" -SchemaModel (New-IdentitySchemaModel)).Count | Should -Be 0
        }

        It "drops a column two joined tables declare with different types" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            $Map = Get-QueryColumnSqlTypeMap -SqlText "SELECT i.Id, l.Note FROM dbo.tblIdentity i JOIN audit.tblIdentity l ON l.Id = i.Id" -SchemaModel (New-IdentitySchemaModel)

            $Map.ContainsKey("Id") | Should -BeFalse -Because "dbo.tblIdentity.Id is int and audit.tblIdentity.Id is bigint"
            $Map["Note"] | Should -BeExactly "nvarchar(max)"
        }

        It "keeps a column two tables declare identically" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT i.Id FROM dbo.tblIdentity i JOIN dbo.tblResource r ON r.Id = i.Id" -SchemaModel (New-IdentitySchemaModel))["Id"] | Should -BeExactly "int"
        }

        It "never types an alias from the table column it shadows" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            $Map = Get-QueryColumnSqlTypeMap -SqlText "SELECT COUNT(*) AS Id, Number FROM dbo.tblIdentity GROUP BY Number" -SchemaModel (New-IdentitySchemaModel)

            $Map.ContainsKey("Id") | Should -BeFalse
            $Map["Number"] | Should -BeExactly "nvarchar(50)"
        }

        It "keeps a column aliased to its own name" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT i.Id AS Id FROM dbo.tblIdentity i" -SchemaModel (New-IdentitySchemaModel))["Id"] | Should -BeExactly "int"
        }

        It "does not resolve a CTE that shares a table's name" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            $Sql = "WITH tblIdentity AS (SELECT '007' AS Code) SELECT Code FROM tblIdentity"
            (Get-QueryColumnSqlTypeMap -SqlText $Sql -SchemaModel (New-IdentitySchemaModel)).Count | Should -Be 0
        }

        It "does not resolve a temporary table" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT Id FROM #tblIdentity" -SchemaModel (New-IdentitySchemaModel)).Count | Should -Be 0
        }

        It "does not resolve a three-part name" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT Id FROM OtherDb.dbo.tblIdentity" -SchemaModel (New-IdentitySchemaModel)).Count | Should -Be 0
        }

        It "returns an empty map for a table the schema does not know" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            (Get-QueryColumnSqlTypeMap -SqlText "SELECT Id FROM dbo.tblNoSuchTable" -SchemaModel (New-IdentitySchemaModel)).Count | Should -Be 0
        }
    }

    Context "The binding path the grid actually uses" {
        # Complete-ExecuteQueryResult re-binds a response WPF cannot bind through
        # Invoke-SanitizeJsonKeys, which replaces every character outside [A-Za-z0-9_-] with an
        # underscore. The grid column is then keyed by the sanitised name, so a map keyed only by the
        # declared name would never answer for it - and, worse, an alias dropped only under its
        # declared name could let a sanitised column inherit a type that is not its own.
        It "answers under the sanitised binding name as well as the declared one" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            # A "#" rather than a space: GetSqlSchema returns each column as "ColumnName DataType",
            # so a column name containing a SPACE cannot be represented in that response at all and
            # never reaches this function. Every other character the sanitiser replaces does.
            $Model = New-SchemaModel -Table @{ "dbo.tblOrder" = @("Order#Date datetime", "Id int") }
            $Map = Get-QueryColumnSqlTypeMap -SqlText "SELECT [Order#Date], Id FROM dbo.tblOrder" -SchemaModel $Model

            $Map["Order#Date"] | Should -BeExactly "datetime"
            $Map["Order_Date"] | Should -BeExactly "datetime" -Because "that is the name the grid binds it under"
        }

        It "drops an alias under its sanitised name too, so it cannot inherit another column's type" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            $Model = New-SchemaModel -Table @{ "dbo.tblOrder" = @("Total_Count int", "Id int") }
            $Map = Get-QueryColumnSqlTypeMap -SqlText "SELECT COUNT(*) AS [Total Count], Id FROM dbo.tblOrder GROUP BY Id" -SchemaModel $Model

            $Map.ContainsKey("Total Count") | Should -BeFalse
            $Map.ContainsKey("Total_Count") | Should -BeFalse -Because "the aliased column binds under exactly that name"
            $Map["Id"] | Should -BeExactly "int"
        }

        It "drops a name two differently spelled columns sanitise onto with different types" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            $Model = New-SchemaModel -Table @{ "dbo.tblOrder" = @("Order#Date datetime", "Order.Date int") }
            $Map = Get-QueryColumnSqlTypeMap -SqlText "SELECT * FROM dbo.tblOrder" -SchemaModel $Model

            $Map.ContainsKey("Order_Date") | Should -BeFalse
            $Map["Order#Date"] | Should -BeExactly "datetime" -Because "the declared spelling is still unambiguous"
        }
    }

    Context "Privacy - issue #103 section 6" {
        It "logs counts and never an identifier" {
            if ($null -eq $Script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
                return
            }

            Get-QueryColumnSqlTypeMap -SqlText "SELECT Id, Number FROM dbo.tblIdentity" -SchemaModel (New-IdentitySchemaModel) | Out-Null

            foreach ($Entry in $Script:LoggedMessage) {
                $Entry.Message | Should -Not -Match "tblIdentity|Number|nvarchar"
            }
        }
    }
}
