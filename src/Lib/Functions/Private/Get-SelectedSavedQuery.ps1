function Get-SelectedSavedQuery {
    <#
    .SYNOPSIS
        The saved query the active tab has selected, for an action that needs one (rename, delete).

    .DESCRIPTION
        Refuses - with a warning naming the reason, and $null - when the tab is not connected or holds
        an ad-hoc query, so each action states the same preconditions the same way.

        The name is the one last loaded from the tenant (RunTimeData.CurrentSqlQuery), falling back to
        the selection's own, not the Display name box: that box holds whatever the user has typed into
        it since, which is not the query's name until it is saved.

    .PARAMETER Action
        What the user tried to do, for the warning ("rename", "delete").

    .OUTPUTS
        [PSCustomObject] @{ DoId; DisplayName }, or $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    if (-not $Script:ConnectionStatus) {
        "Connect to Omada to {0} a query." -f $Action | Write-LogOutput -LogType WARNING
        return $null
    }

    $Private:DoId = $Script:AppConfig.CurrentSqlQuery.DoId
    if (Test-AdHocQuery -QueryDoId $Private:DoId) {
        "Select a saved query to {0}. An ad-hoc query is not stored in Omada." -f $Action | Write-LogOutput -LogType WARNING
        return $null
    }

    $Private:Name = $Script:RunTimeData.CurrentSqlQuery.DisplayName
    if ([string]::IsNullOrWhiteSpace($Private:Name)) {
        $Private:Name = $Script:AppConfig.CurrentSqlQuery.DisplayName
    }

    return [PSCustomObject]@{
        DoId        = [string]$Private:DoId
        DisplayName = [string]$Private:Name
    }
}
