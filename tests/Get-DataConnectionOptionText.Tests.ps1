#Requires -Version 7.0
# The data connection dropdown accessor. It has two modes and the difference between them is whether
# it is allowed to talk to the tenant, so both are pinned here.
#
# The refreshing mode exists for the execute path (issue #152): a query naming a perfectly valid
# database must not be rejected as unresolvable purely because it ran before the list had loaded.
#
# -NoRefresh exists for everything issue #158 added. The schema validation pass reads the list on
# every idle tick, and the schema tree and the editor's name list are pushed from request
# completions on the UI thread - a synchronous refresh in any of those is either a request per
# keystroke or a frozen window.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    # Get-UnresolvedDatabaseMessage, in the same file as the function under test, resolves the
    # dropdown entries through the shared parser. Dot-sourced so this harness is complete on its own
    # rather than relying on another test file having loaded it first - which is exactly how a
    # missing dot-source passed locally and failed in CI earlier in this branch.
    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-SqlStatementTarget.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    # The synchronous refresh pair. Counted rather than performed: whether they ran is the whole
    # question.
    $script:RefreshCalls = 0

    function Get-DataConnectionPageInline {
        $script:RefreshCalls++
        return [PSCustomObject]@{ Html = "<option value=`"1001572`" data-uid=`"u`">OISES</option>"; HasRows = $true }
    }

    function Complete-DataConnectionListUpdate {
        param($DataObjectHtml, [switch]$HasRows, [switch]$NotShowPopupWindow)
        # What the real one does, as far as this function can observe: it fills the dropdown.
        $Item = [PSCustomObject]@{ Content = "OISES - 1001572" }
        $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items.Add($Item) | Out-Null
    }

    function script:Initialize-DropdownState {
        param([string[]]$Content)

        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Entry in $Content) {
            $Items.Add([PSCustomObject]@{ Content = $Entry }) | Out-Null
        }

        $Script:MainForm = @{
            Elements = @{
                ComboBoxSelectDataConnection = [PSCustomObject]@{ Items = $Items }
            }
        }
        $script:RefreshCalls = 0
    }
}

Describe 'Get-DataConnectionOptionText' {
    # Assigned, never wrapped in @(). The function returns its array through the ", $array" idiom so
    # that an empty or single-entry result survives the pipeline; wrapping the CALL in @() nests the
    # array one level and every assertion below would be about a one-element array of arrays.

    It 'returns the dropdown entries' {
        Initialize-DropdownState -Content @("OISES - 1001572", "Reporting - 1001999")

        $Option = Get-DataConnectionOptionText

        $Option | Should -Be @("OISES - 1001572", "Reporting - 1001999")
        $script:RefreshCalls | Should -Be 0
    }

    It 'refreshes synchronously when the list is empty' {
        Initialize-DropdownState -Content @()

        $Option = Get-DataConnectionOptionText

        $Option | Should -Be @("OISES - 1001572")
        $script:RefreshCalls | Should -Be 1
    }

    It 'treats a list of blanks as empty' {
        Initialize-DropdownState -Content @("", " ")

        Get-DataConnectionOptionText | Out-Null

        $script:RefreshCalls | Should -Be 1
    }

    Context '-NoRefresh' {
        It 'returns an empty list rather than refreshing it' {
            # THE assertion behind issue #158's "the validation pass makes no request". Without the
            # switch this is one authenticated round trip per idle tick on a tab whose list has not
            # loaded.
            Initialize-DropdownState -Content @()

            $Option = Get-DataConnectionOptionText -NoRefresh

            $Option.Count | Should -Be 0
            $script:RefreshCalls | Should -Be 0
        }

        It 'still returns the entries when the list is populated' {
            Initialize-DropdownState -Content @("OISES - 1001572")

            $Option = Get-DataConnectionOptionText -NoRefresh

            $Option | Should -Be @("OISES - 1001572")
            $script:RefreshCalls | Should -Be 0
        }
    }
}
