function Update-ApplicationTitle {
    <#
    .SYNOPSIS
    Refreshes the application window title so it always mirrors the active tab.

    .DESCRIPTION
    Builds "<AppName> (<Version>) - <query name>[*] - <data connection> - <tenant> [- No connection]".
    The part after the app name/version is exactly the active tab's header text (built by
    Update-TabHeaderTitle), so the title stays in the same format as the tab and never drifts. Falls
    back to just the app name/version when there is no active tab. Call this on tab switches and
    whenever the active tab's header is rebuilt - that is what keeps the title bar live instead of
    only updating on connect/disconnect.
    #>
    [CmdLetBinding()]
    param()
    try {
        if ($null -eq $Script:MainForm -or $null -eq $Script:MainForm.Definition) {
            return
        }

        $Base = $Script:RunTimeConfig.ApplicationTitle

        $ActiveTab = Get-ActiveTabSession
        $HeaderText = $null
        if ($null -ne $ActiveTab -and $null -ne $ActiveTab.TabItem -and $null -ne $ActiveTab.TabItem.Header) {
            $HeaderText = [string]$ActiveTab.TabItem.Header.Children[0].Text
        }

        if ([string]::IsNullOrWhiteSpace($HeaderText)) {
            $Script:MainForm.Definition.Title = $Base
        }
        else {
            $Script:MainForm.Definition.Title = "{0} - {1}" -f $Base, $HeaderText
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
