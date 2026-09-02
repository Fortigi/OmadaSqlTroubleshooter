BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $Script:RepositoryRoot -ChildPath 'src\Lib\Functions\Private\Move-SqlDiagnosticToSelection.ps1')

    # Shaped exactly as Get-SqlSyntaxDiagnostic emits, so a change to that shape breaks this too.
    function New-TestDiagnostic {
        param(
            [int]$Line,
            [int]$Column,
            [int]$EndLine,
            [int]$EndColumn
        )

        return [PSCustomObject][Ordered]@{
            Line      = $Line
            Column    = $Column
            EndLine   = $EndLine
            EndColumn = $EndColumn
            Severity  = 'Error'
            Message   = "Incorrect syntax near ','."
            Source    = 'T-SQL syntax'
        }
    }
}

Describe 'Move-SqlDiagnosticToSelection' -Tag 'Unit' {

    Context 'When the selection starts at the top left' {

        It 'Should leave the positions untouched' {
            # Line 1, column 1 is both "no selection" and "a selection starting at the top", and
            # neither may move anything.
            $Diagnostic = New-TestDiagnostic -Line 1 -Column 9 -EndLine 1 -EndColumn 13
            $Moved = @(Move-SqlDiagnosticToSelection -Diagnostic $Diagnostic -StartLine 1 -StartColumn 1)

            $Moved.Count | Should -Be 1
            $Moved[0].Line | Should -Be 1
            $Moved[0].Column | Should -Be 9
            $Moved[0].EndLine | Should -Be 1
            $Moved[0].EndColumn | Should -Be 13
        }
    }

    Context 'When the selection starts further down the document' {

        It 'Should shift every line by the distance to the top of the selection' {
            # The bug this exists for: a selection starting on model line 10 made the parser call
            # its first line 1, and the marker landed nine lines too high.
            $Diagnostic = New-TestDiagnostic -Line 1 -Column 8 -EndLine 1 -EndColumn 12
            $Moved = @(Move-SqlDiagnosticToSelection -Diagnostic $Diagnostic -StartLine 10 -StartColumn 1)

            $Moved[0].Line | Should -Be 10
            $Moved[0].EndLine | Should -Be 10
        }

        It 'Should shift the column only on the first line of the selection' {
            # A selection can start mid-line, but every line after the first starts at column 1 in
            # the model as well as in the selection, so only line 1 takes the column shift.
            $First = New-TestDiagnostic -Line 1 -Column 3 -EndLine 1 -EndColumn 7
            $Second = New-TestDiagnostic -Line 2 -Column 3 -EndLine 2 -EndColumn 7

            $Moved = @(Move-SqlDiagnosticToSelection -Diagnostic @($First, $Second) -StartLine 5 -StartColumn 20)

            $Moved[0].Line | Should -Be 5
            $Moved[0].Column | Should -Be 22
            $Moved[0].EndColumn | Should -Be 26

            $Moved[1].Line | Should -Be 6
            $Moved[1].Column | Should -Be 3 -Because 'the second line of the selection starts at column 1 in the model too'
            $Moved[1].EndColumn | Should -Be 7
        }

        It 'Should shift a diagnostic that spans out of the first line on the end line only' {
            $Diagnostic = New-TestDiagnostic -Line 1 -Column 4 -EndLine 2 -EndColumn 6
            $Moved = @(Move-SqlDiagnosticToSelection -Diagnostic $Diagnostic -StartLine 3 -StartColumn 10)

            $Moved[0].Line | Should -Be 3
            $Moved[0].Column | Should -Be 13
            $Moved[0].EndLine | Should -Be 4
            $Moved[0].EndColumn | Should -Be 6 -Because 'the end sits on a line that starts at column 1 in the model'
        }

        It 'Should preserve every field it does not move' {
            $Diagnostic = New-TestDiagnostic -Line 1 -Column 1 -EndLine 1 -EndColumn 2
            $Moved = @(Move-SqlDiagnosticToSelection -Diagnostic $Diagnostic -StartLine 4 -StartColumn 2)

            $Moved[0].Severity | Should -Be 'Error'
            $Moved[0].Message | Should -Be "Incorrect syntax near ','."
            $Moved[0].Source | Should -Be 'T-SQL syntax'
        }

        It 'Should keep the diagnostics in the order it was given them' {
            $Diagnostic = @(
                (New-TestDiagnostic -Line 1 -Column 1 -EndLine 1 -EndColumn 2)
                (New-TestDiagnostic -Line 3 -Column 1 -EndLine 3 -EndColumn 2)
                (New-TestDiagnostic -Line 2 -Column 1 -EndLine 2 -EndColumn 2)
            )

            $Moved = @(Move-SqlDiagnosticToSelection -Diagnostic $Diagnostic -StartLine 2 -StartColumn 1)

            @($Moved | ForEach-Object { $_.Line }) | Should -Be @(2, 4, 3)
        }
    }

    Context 'When there is nothing to move' {

        It 'Should return an empty collection for no diagnostics' {
            @(Move-SqlDiagnosticToSelection -Diagnostic @() -StartLine 7 -StartColumn 3).Count | Should -Be 0
        }

        It 'Should return an empty collection for null' {
            @(Move-SqlDiagnosticToSelection -Diagnostic $null -StartLine 7 -StartColumn 3).Count | Should -Be 0
        }

        It 'Should drop null entries rather than emitting a malformed marker' {
            $Diagnostic = @((New-TestDiagnostic -Line 1 -Column 1 -EndLine 1 -EndColumn 2), $null)
            @(Move-SqlDiagnosticToSelection -Diagnostic $Diagnostic -StartLine 2 -StartColumn 1).Count | Should -Be 1
        }
    }
}
