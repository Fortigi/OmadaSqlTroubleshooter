#Requires -Version 7.0
# Tests for the grid-to-schema resolution of issue #103.
#
# The grid is stubbed with plain objects rather than real WPF controls: Get-DataGridSelectionSchema
# only reads Column, Header, SortMemberPath and DisplayIndex, and a headless CI session cannot
# resolve every System.Windows type. This is the same approach Update-SqlSchemaTreeFilter.Tests.ps1
# takes for the schema tree.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
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

    Context "The schema resolution seam" {
        It "reports a null SqlType, because priority 1 is not delivered yet" {
            # Downstream code already reads and honours SqlType. Asserting it is null here is what
            # makes the seam visible: when the schema lookup lands, this is the test that changes.
            $Grid = New-GridStub -Column @{ Header = "Id"; SortMemberPath = "Id"; DisplayIndex = 0 }
            @(Get-DataGridSelectionSchema -DataGrid $Grid)[0].SqlType | Should -BeNullOrEmpty
        }
    }
}
