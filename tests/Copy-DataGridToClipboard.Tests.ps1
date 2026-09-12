#Requires -Version 7.0
# Acceptance criterion 11 of issue #103: with ArrayCopyUseColumnSchema = $false, the output is
# byte-identical to the pre-#103 behaviour.
#
# Format-SniffedArrayLiteral is the old logic, lifted out of Copy-DataGridToClipboard unchanged. The
# expectations below are hard-coded from the original implementation rather than derived from the
# new one, so that a well-meaning "fix" to the legacy path fails here instead of quietly changing
# what the escape hatch escapes to.
#
# Copy-DataGridToClipboard itself is not exercised: what is left in it after the #103 split is
# DataGridCellInfo construction and Clipboard::SetText, neither of which resolves in a headless
# session. Everything with a decision in it now lives in the functions that are tested.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    # Dot-sourcing the file defines Format-SniffedArrayLiteral alongside Copy-DataGridToClipboard.
    # Copy-DataGridToClipboard is never invoked here, so its WPF dependencies are never resolved.
    . (Join-Path $PrivatePath -ChildPath "Copy-DataGridToClipboard.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }
}

Describe "Format-SniffedArrayLiteral - the pre-#103 behaviour, kept as the escape hatch" {

    Context "SqlArray" {
        It "emits unquoted values when every rendered cell is an integer" {
            Format-SniffedArrayLiteral -CellValue @("900", "901") -OutputFormat "SqlArray" |
                Should -BeExactly "(`r`n    900,`r`n    901`r`n)"
        }

        It "emits quoted values when any rendered cell is not an integer" {
            Format-SniffedArrayLiteral -CellValue @("900", "IDG-900") -OutputFormat "SqlArray" |
                Should -BeExactly "(`r`n    '900',`r`n    'IDG-900'`r`n)"
        }

        It "still doubles a single quote" {
            Format-SniffedArrayLiteral -CellValue @("O'Brien") -OutputFormat "SqlArray" |
                Should -BeExactly "(`r`n    'O''Brien'`r`n)"
        }

        It "accepts a negative integer as an integer, as it always did" {
            Format-SniffedArrayLiteral -CellValue @("-42") -OutputFormat "SqlArray" |
                Should -BeExactly "(`r`n    -42`r`n)"
        }
    }

    Context "PowerShellArray" {
        It "emits a single-line array when every rendered cell is an integer" {
            Format-SniffedArrayLiteral -CellValue @("900", "901") -OutputFormat "PowerShellArray" |
                Should -BeExactly "@(900, 901)"
        }

        It "emits a multi-line quoted array otherwise" {
            Format-SniffedArrayLiteral -CellValue @("900", "IDG-900") -OutputFormat "PowerShellArray" |
                Should -BeExactly "@(`r`n    '900',`r`n    'IDG-900'`r`n)"
        }
    }

    Context "The failure modes it is kept in spite of" {
        It "still turns the code 007 into 7 - which is why it is not the default any more" {
            # This is not a bug report against the escape hatch; it is the documented old behaviour.
            # Asserting it here is what proves the ArrayCopyUseColumnSchema = $false path really is
            # the old path and not a re-derivation of it.
            Format-SniffedArrayLiteral -CellValue @("007") -OutputFormat "SqlArray" |
                Should -BeExactly "(`r`n    007`r`n)"
        }

        It "still re-types every integer in the selection when one cell is not numeric" {
            Format-SniffedArrayLiteral -CellValue @("900", "901", "IDG-900") -OutputFormat "SqlArray" |
                Should -Match "'900'"
        }
    }
}
