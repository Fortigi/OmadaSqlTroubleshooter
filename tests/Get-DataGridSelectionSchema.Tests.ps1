#Requires -Version 7.0
# Tests for the grid-to-schema resolution of issue #103.
#
# The grid is stubbed with plain objects rather than real WPF controls: Get-DataGridSelectionSchema
# only reads Column, Header, SortMemberPath and DisplayIndex, and a headless CI session cannot
# resolve every System.Windows type. This is the same approach Update-SqlSchemaTreeFilter.Tests.ps1
# takes for the schema tree.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Resolve-StrictBoolean.ps1")
    . (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Get-QueryResultValueKind.ps1")
    . (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Get-DataGridSelectionSchema.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function New-GridStub {
        <#
            Builds a grid whose selected cells cover the supplied columns. Each column definition is
            a hashtable of Header, SortMemberPath and DisplayIndex.
        #>
        param(
            [hashtable[]]$Column
        )

        $ColumnObject = @($Column | ForEach-Object { [PSCustomObject]$_ })
        $SelectedCell = @($ColumnObject | ForEach-Object { [PSCustomObject]@{ Column = $_; Item = "row" } })

        return [PSCustomObject]@{
            SelectedCells = $SelectedCell
            Items         = @("row")
        }
    }
}

Describe "Get-DataGridSelectionSchema" {

    Context "Nothing selected" {
        It "returns an empty result for a grid with no selected cells" {
            $Grid = [PSCustomObject]@{ SelectedCells = @(); Items = @() }
            @(Get-DataGridSelectionSchema -DataGrid $Grid).Count | Should -Be 0
        }

        It "returns an empty result for a null grid" {
            @(Get-DataGridSelectionSchema -DataGrid $null).Count | Should -Be 0
        }

        It "honours an explicit null instead of falling back to the query result grid" {
            # Without this, the assertion above passes for the wrong reason: $Script:MainForm is
            # simply unset in a test session, so the fallback also yields nothing. With a real grid
            # present, an explicit -DataGrid $null must still mean "no grid" - an omitted parameter
            # is what asks for the default, and the two are indistinguishable from the value alone.
            $Script:MainForm = [PSCustomObject]@{
                Elements = [PSCustomObject]@{
                    DataGridQueryResult = New-GridStub -Column @{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 }
                }
            }

            try {
                @(Get-DataGridSelectionSchema -DataGrid $null).Count | Should -Be 0
                @(Get-DataGridSelectionSchema).Count | Should -Be 1 -Because "an omitted parameter is what selects the default grid"
            }
            finally {
                $Script:MainForm = $null
            }
        }
    }

    Context "The property name comes from the binding path, not the header" {
        It "prefers SortMemberPath" {
            # Headers pass through Invoke-SanitizeJsonKeys and the grid's header escaping, so a
            # header is not reliably the name of the property it displays. Reading the row by the
            # header would return $null for exactly the columns the sanitizer had to rename.
            $Grid = New-GridStub -Column @{ Header = "Order Number"; SortMemberPath = "Order_Number"; DisplayIndex = 0 }
            $Schema = @(Get-DataGridSelectionSchema -DataGrid $Grid)

            $Schema[0].Header | Should -BeExactly "Order Number"
            $Schema[0].PropertyName | Should -BeExactly "Order_Number"
        }

        It "falls back to the header when the column has no binding path" {
            $Grid = New-GridStub -Column @{ Header = "Id"; SortMemberPath = ""; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid)[0].PropertyName | Should -BeExactly "Id"
        }

        It "falls back to the header when the binding path is whitespace" {
            $Grid = New-GridStub -Column @{ Header = "Id"; SortMemberPath = "   "; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid)[0].PropertyName | Should -BeExactly "Id"
        }
    }

    Context "Ordering and de-duplication" {
        It "returns columns in display order, not selection order" {
            $Grid = New-GridStub -Column @(
                @{ Header = "Number"; SortMemberPath = "Number"; DisplayIndex = 2 },
                @{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 },
                @{ Header = "Deleted"; SortMemberPath = "Deleted"; DisplayIndex = 1 }
            )

            @(Get-DataGridSelectionSchema -DataGrid $Grid | ForEach-Object { $_.Header }) | Should -Be @("Id", "Deleted", "Number")
        }

        It "lists a column once however many of its cells are selected" {
            $Column = [PSCustomObject]@{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 }
            $Grid = [PSCustomObject]@{
                SelectedCells = @(
                    [PSCustomObject]@{ Column = $Column; Item = "r1" },
                    [PSCustomObject]@{ Column = $Column; Item = "r2" },
                    [PSCustomObject]@{ Column = $Column; Item = "r3" }
                )
                Items         = @("r1", "r2", "r3")
            }

            @(Get-DataGridSelectionSchema -DataGrid $Grid).Count | Should -Be 1
        }
    }

    Context "The schema resolution - priority 1, delivered by issue #120" {
        It "takes the declared type from the map, keyed by the binding path" {
            $Grid = New-GridStub -Column @{ Header = "Identifier"; SortMemberPath = "Id"; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid -SqlTypeMap @{ Id = "int" })[0].SqlType | Should -BeExactly "int"
        }

        It "does not key the map by the header, which is not reliably the name of anything" {
            # A header has been through Invoke-SanitizeJsonKeys and the grid's own escaping. Typing a
            # column from it would resolve the wrong column whenever the two differ.
            $Grid = New-GridStub -Column @{ Header = "Identifier"; SortMemberPath = "Id"; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid -SqlTypeMap @{ Identifier = "int" })[0].SqlType | Should -BeNullOrEmpty
        }

        It "leaves a column the map does not answer for untyped" {
            $Grid = New-GridStub -Column @{ Header = "Total"; SortMemberPath = "Total"; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid -SqlTypeMap @{ Id = "int" })[0].SqlType | Should -BeNullOrEmpty
        }

        It "treats an explicit null map as 'resolve nothing' rather than falling back" {
            $Grid = New-GridStub -Column @{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid -SqlTypeMap $null)[0].SqlType | Should -BeNullOrEmpty
        }

        It "resolves the map itself when the parameter is omitted" {
            function Get-ActiveQueryColumnSqlTypeMap { return @{ Id = "bigint" } }

            try {
                $Grid = New-GridStub -Column @{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 }
                @(Get-DataGridSelectionSchema -DataGrid $Grid)[0].SqlType | Should -BeExactly "bigint"
            }
            finally {
                Remove-Item -Path "Function:\Get-ActiveQueryColumnSqlTypeMap" -ErrorAction SilentlyContinue
            }
        }

        It "still produces a schema when the declared types cannot be resolved at all" {
            # Nothing about typing may cost the user their copy: no declared type is the state every
            # copy was in before issue #120, and it still produces correct output.
            $Grid = New-GridStub -Column @{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid)[0].PropertyName | Should -BeExactly "Id"
        }
    }

    Context "The untyped-response switch" {
        It "allows value promotion when every bound cell is a string" {
            $Grid = New-GridStub -Column @{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 }
            $Grid.Items = @('{ "Id": "900", "Number": "IDG-900" }' | ConvertFrom-Json)

            @(Get-DataGridSelectionSchema -DataGrid $Grid -SqlTypeMap @{})[0].AllowValuePromotion | Should -BeTrue
        }

        It "refuses value promotion when the response typed anything" {
            $Grid = New-GridStub -Column @{ Header = "Number"; SortMemberPath = "Number"; DisplayIndex = 0 }
            $Grid.Items = @('{ "Id": 900, "Number": "12345" }' | ConvertFrom-Json)

            @(Get-DataGridSelectionSchema -DataGrid $Grid -SqlTypeMap @{})[0].AllowValuePromotion | Should -BeFalse -Because "a typed response makes a JSON string evidence that the column is textual"
        }
    }
}
