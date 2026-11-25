function Open-SqlQueryInTab {
    <#
    .SYNOPSIS
        Shows a saved query in a tab: the tab that already holds it, or a new one.

    .DESCRIPTION
        Used by the query manager and its detail view. A query that is already open in a tab is not
        opened twice - that tab is selected, so its unsaved edits stay where they are. Otherwise a new
        tab is opened with the active tab's connection (New-TabConfigFromTab) and the query selected;
        it shares the active tab's connection pool, so a connected tab connects it without signing in
        again, and the query's text is loaded as for any selection.

        -RestoreText puts an older version of the query (from its history) in the editor as an unsaved
        change. In a tab that already holds the query it is pushed straight in. In a new tab it waits
        on the tab (PendingRestoreText) until the saved text has been loaded, and replaces it then - see
        Resolve-EditorLoadText - so the load cannot overwrite it.

    .PARAMETER DoId
        The query.

    .PARAMETER DisplayName
        Its name.

    .PARAMETER RestoreText
        An older version to put in the editor instead of the saved text.

    .OUTPUTS
        The tab session, or $null when no tab could be opened.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$RestoreText
    )

    $Private:Restore = $PSBoundParameters.ContainsKey("RestoreText") -and $null -ne $RestoreText

    $Private:Existing = $Script:Tabs | Where-Object { [string]$_.AppConfig.CurrentSqlQuery.DoId -eq $DoId } | Select-Object -First 1
    if ($null -ne $Private:Existing) {
        "Query {0} is already open in tab '{1}'; selecting it." -f $DoId, $Private:Existing.DisplayName | Write-LogOutput -LogType DEBUG
        (Get-TabControlSessions).SelectedItem = $Private:Existing.TabItem
        Set-ActiveTabContext -TabSession $Private:Existing
        if ($Private:Restore) {
            Push-ToEditor -ScriptToExecute ("window.setEditorValue({0});" -f (ConvertTo-JavaScriptLiteral -Value $RestoreText))
            Set-TabEditorText -TabSession $Private:Existing -Text $RestoreText
            $Private:Existing.IsDirty = $true
            Update-TabHeaderTitle -TabSession $Private:Existing
        }
        return $Private:Existing
    }

    $Private:Source = Get-ActiveTabSession
    if ($null -eq $Private:Source) {
        "There is no tab to take the connection from; open a tab and connect first." | Write-LogOutput -LogType WARNING
        return $null
    }

    $Private:Query = [PSCustomObject]@{ DoId = $DoId; DisplayName = $DisplayName; FullName = "{0} - {1}" -f $DisplayName, $DoId }
    $Private:Config = New-TabConfigFromTab -SourceTab $Private:Source -CurrentSqlQuery $Private:Query
    $Private:Connected = Get-TabConnectionStatus -TabSession $Private:Source

    $Private:Tab = New-TabSession -RestoreFrom $Private:Config -AutoConnect:$Private:Connected
    if ($null -ne $Private:Tab -and $Private:Restore) {
        $Private:Tab | Add-Member -NotePropertyName "PendingRestoreText" -NotePropertyValue $RestoreText -Force
    }
    return $Private:Tab
}
