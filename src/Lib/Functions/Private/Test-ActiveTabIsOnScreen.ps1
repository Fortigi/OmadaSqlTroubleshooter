function Test-ActiveTabIsOnScreen {
    <#
    .SYNOPSIS
    Whether the tab the current work belongs to is the one the user is actually looking at.

    .DESCRIPTION
    Two different notions of "current tab" exist, and the difference is the whole point of this
    function.

    $Script:ActiveTabId is the tab the code is currently acting FOR. The completion poll timer steps
    into the owning tab before invoking a completion and restores afterwards, so during a background
    query's completion it names that query's tab - which is what makes log lines and dialog titles
    attribute correctly.

    The tab control's SelectedItem is the tab on SCREEN. It changes only when the user switches tabs.

    When a background query fails, the first says "tab A" while the second may well say "tab B". That
    is exactly when a modal must not appear: it would interrupt work on tab B to report something
    about tab A that the user cannot even see.

    .OUTPUTS
    [bool] $true when the acting tab is the visible one, or when the question cannot be answered - a
    message is better shown once too often than swallowed.
    #>
    [CmdLetBinding()]
    [OutputType([bool])]
    param()

    try {
        $Private:Active = Get-ActiveTabSession
        if ($null -eq $Private:Active) {
            # No tab context at all: not a tab-scoped situation, so nothing to defer.
            return $true
        }

        $Private:Selected = (Get-TabControlSessions).SelectedItem
        if ($null -eq $Private:Selected) {
            return $true
        }

        return ($Private:Active.TabItem -eq $Private:Selected)
    }
    catch {
        # Deliberately fails towards showing the message. Holding one back because this check threw
        # would lose it until the user happened to switch tabs, which is the worse failure.
        return $true
    }
}
