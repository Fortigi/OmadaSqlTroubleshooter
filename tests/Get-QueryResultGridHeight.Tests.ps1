#Requires -Version 7.0
# The sizing rule for the Results pane's stacked grids (issue #151), on its own.
#
# This is the half of the layout work that a headless lane CAN prove. Get-QueryResultGridHeight is
# deliberately pure - an equal share, floored - so the RULE is asserted here, in CI, while the
# measuring half (what a row and a column header actually come out as, and whether the pane then
# scrolls) needs a real WPF layout pass and lives in the STA suite.
#
# Four acceptance criteria of issue #151 are decided by this arithmetic:
#
#   "Two results share the pane height equally"                                 -> equal share
#   "every result shows five rows plus its header and the Results pane scrolls"  -> the floor, and
#                                                                                  the sum exceeding
#                                                                                  the viewport
#   "One result fills the pane with no outer scrollbar"                          -> share == viewport
#
# The floor used throughout is 107.3, which is not an invented number: it is what a DataGridRow
# (17.05) and a DataGridColumnHeadersPresenter (22.05) actually measured to in an STA host, for the
# Consolas grid this pane uses - 22.05 + 5 * 17.05.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Update-QueryResultStackLayout.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType
        )
        process { }
    }

    # The measured floor for one Consolas result grid: header 22.05 + five rows at 17.05.
    $Script:MeasuredFloor = 107.3
}

Describe 'Get-QueryResultGridHeight' -Tag 'Unit' {

    Context 'When the results fit' {

        It 'gives two results an equal share of the pane' {
            # "Two results share the pane height equally."
            Get-QueryResultGridHeight -ViewportHeight 400 -ResultCount 2 -FloorHeight $Script:MeasuredFloor |
                Should -Be 200
        }

        It 'gives a single result the whole viewport' {
            # "One result fills the pane with no outer scrollbar" - the height IS the viewport, so the
            # content cannot exceed it and the outer ScrollViewer (Auto) shows nothing.
            Get-QueryResultGridHeight -ViewportHeight 400 -ResultCount 1 -FloorHeight $Script:MeasuredFloor |
                Should -Be 400
        }

        It 'divides equally for three results that still clear the floor' {
            Get-QueryResultGridHeight -ViewportHeight 600 -ResultCount 3 -FloorHeight $Script:MeasuredFloor |
                Should -Be 200
        }

        It 'never returns less than the share when the share is the larger' {
            $Private:Height = Get-QueryResultGridHeight -ViewportHeight 1000 -ResultCount 2 -FloorHeight $Script:MeasuredFloor
            $Private:Height | Should -BeGreaterThan $Script:MeasuredFloor
        }
    }

    Context 'When the equal share would drop below five rows' {

        It 'falls back to the floor rather than shrinking further' {
            # 400 / 5 = 80, which is less than 107.3: every result still shows its header and five rows.
            Get-QueryResultGridHeight -ViewportHeight 400 -ResultCount 5 -FloorHeight $Script:MeasuredFloor |
                Should -Be $Script:MeasuredFloor
        }

        It 'makes the stack taller than the pane, which is what makes the pane scroll' {
            # The fourth criterion needs no code of its own: once the floor wins, the sum of the heights
            # exceeds the viewport and the pane's ScrollViewer scrolls. Asserted as arithmetic here and
            # as a real ComputedVerticalScrollBarVisibility in the STA suite.
            $Private:Viewport = 400
            $Private:Count = 5
            $Private:Height = Get-QueryResultGridHeight -ViewportHeight $Private:Viewport -ResultCount $Private:Count -FloorHeight $Script:MeasuredFloor

            ($Private:Height * $Private:Count) | Should -BeGreaterThan $Private:Viewport
        }

        It 'keeps every result the same height, however many there are' {
            # A rule, not a per-result accident: two results of the same statement count must not come
            # out different heights.
            $Private:First = Get-QueryResultGridHeight -ViewportHeight 300 -ResultCount 8 -FloorHeight $Script:MeasuredFloor
            $Private:Second = Get-QueryResultGridHeight -ViewportHeight 300 -ResultCount 8 -FloorHeight $Script:MeasuredFloor

            $Private:First | Should -Be $Private:Second
            $Private:First | Should -Be $Script:MeasuredFloor
        }

        It 'treats a share exactly equal to the floor as the share' {
            # The boundary. 536.5 / 5 = 107.3 exactly, so neither branch should produce anything else.
            Get-QueryResultGridHeight -ViewportHeight 536.5 -ResultCount 5 -FloorHeight $Script:MeasuredFloor |
                Should -Be $Script:MeasuredFloor
        }
    }

    Context 'When there is nothing usable to size against' {

        It 'returns nothing to size for no results' {
            Get-QueryResultGridHeight -ViewportHeight 400 -ResultCount 0 -FloorHeight $Script:MeasuredFloor |
                Should -Be 0
        }

        It 'returns nothing to size for a negative count' {
            Get-QueryResultGridHeight -ViewportHeight 400 -ResultCount -1 -FloorHeight $Script:MeasuredFloor |
                Should -Be 0
        }

        It 'falls back to the floor when the viewport has not been measured yet' {
            # A grid sized to 0 is an invisible result. The first layout pass after binding genuinely
            # has no viewport yet, so the floor is the honest answer and the next pass widens it.
            Get-QueryResultGridHeight -ViewportHeight 0 -ResultCount 2 -FloorHeight $Script:MeasuredFloor |
                Should -Be $Script:MeasuredFloor
        }

        It 'falls back to the floor for an unarranged viewport reported as NaN' {
            Get-QueryResultGridHeight -ViewportHeight ([double]::NaN) -ResultCount 2 -FloorHeight $Script:MeasuredFloor |
                Should -Be $Script:MeasuredFloor
        }

        It 'falls back to the floor for a negative viewport' {
            Get-QueryResultGridHeight -ViewportHeight -50 -ResultCount 2 -FloorHeight $Script:MeasuredFloor |
                Should -Be $Script:MeasuredFloor
        }
    }
}
