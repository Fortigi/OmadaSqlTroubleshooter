function Get-TabConnectionStatus {
    <#
    .SYNOPSIS
        Whether a tab is connected.

    .DESCRIPTION
        The active tab's live state is $Script:ConnectionStatus; a tab stores its own copy only when it
        stops being active (Set-ActiveTabContext), so for the active tab that copy can be stale.

    .PARAMETER TabSession
        The tab.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )

    if ($TabSession.Id -eq $Script:ActiveTabId) {
        return [bool]$Script:ConnectionStatus
    }

    return [bool]$TabSession.ConnectionStatus
}
