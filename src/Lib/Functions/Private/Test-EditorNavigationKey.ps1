function Test-EditorNavigationKey {
    <#
    .SYNOPSIS
    Returns whether a key is one that WPF's TabControl claims for its own first/last-tab navigation
    and must therefore be kept away from it, so the editor can use it instead.

    .DESCRIPTION
    WPF's TabControl.OnKeyDown moves the selection to the FIRST tab on Home and to the LAST tab on
    End. It switches on the key alone, so every modifier combination triggers it - Home, Shift+Home
    (select to line start), Ctrl+Home (jump to the document start), and the End equivalents.

    A WPF TextBox never triggers this because it handles Home/End itself and marks the event handled,
    so the key never bubbles as far as the TabControl. The WebView2 hosting the Monaco editor does
    not: the key surfaces as an unhandled routed event, reaches the TabControl and switches tab. To
    make it worse, WebView2 only forwards the key to the web content when the WPF routed event comes
    back unhandled - so once the TabControl claims it, the caret does not move either.

    See Initialize-OmadaSqltroubleShooter (class handler) and MainForm.Definition (the matching reset)
    for how this is used to stop the TabControl without withholding the key from Monaco.

    Takes the key as its [System.Windows.Input.Key] name (what .ToString() yields, e.g. "Home").
    Working with names rather than the WPF enum type keeps this testable without PresentationCore.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$KeyName
    )

    if ([string]::IsNullOrWhiteSpace($KeyName)) {
        return $false
    }

    return ($KeyName.Trim() -in @("Home", "End"))
}
