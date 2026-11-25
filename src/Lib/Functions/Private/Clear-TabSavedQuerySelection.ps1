function Clear-TabSavedQuerySelection {
    <#
    .SYNOPSIS
        Detaches the active tab from its saved query, so the tab holds an ad-hoc query.

    .DESCRIPTION
        Shared by New (Clear-TabQuery) and Delete (Complete-SqlQueryRemoval): the selected query is
        forgotten in the tab's config and run-time state, and the dropdown selection is cleared.

        Clearing the selection raises the dropdown's SelectionChanged, whose handler synchronises the
        ad-hoc draft cache from the tab. So the caller sets the tab's own state (dirty flag, draft
        text) BEFORE calling this, and the handler sees the tab as it is meant to end up.

        Must run with the tab active (Set-ActiveTabContext): it works on $Script:AppConfig,
        $Script:RunTimeData and $Script:MainForm.Elements.

    .PARAMETER TabSession
        The active tab, whose AppConfig reference is kept in step. $null is allowed.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession
    )

    $Script:AppConfig.CurrentSqlQuery = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
    $Script:RunTimeData.CurrentSqlQuery.DoId = $null
    $Script:RunTimeData.CurrentSqlQuery.DisplayName = $null
    $Script:RunTimeData.CurrentSqlQuery.FullName = $null
    $Script:RunTimeData.CurrentQueryText = $null

    if ($null -ne $TabSession) {
        $TabSession.AppConfig = $Script:AppConfig
    }

    $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $null
    $Script:MainForm.Elements.ComboBoxSelectQuery.Text = ""
}
