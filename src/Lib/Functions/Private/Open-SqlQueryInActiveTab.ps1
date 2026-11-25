function Open-SqlQueryInActiveTab {
    <#
    .SYNOPSIS
        Shows a saved query in the active tab, in place of what that tab holds.

    .DESCRIPTION
        The query manager's and the query details' Open. Open in new tab (Open-SqlQueryInTab) keeps
        the active tab as it is; this replaces its query, so:

          - A query that is already open in a tab is not opened twice: that tab is selected, exactly
            as Open in new tab does, so its unsaved edits stay where they are.
          - The active tab must be connected: selecting a query reads it from the tenant.
          - Unsaved changes in the active tab - a selected query or an ad-hoc query, never an empty
            editor - are offered to be saved first (Save / Don't save / Cancel), as for New.

        The query is then selected in the tab's query list, which loads it exactly as picking it
        there does (the list's SelectionChanged handler). A query the list does not show - hidden by
        an "Only my queries" filter, or newer than the list - is added to it first.

    .PARAMETER DoId
        The query.

    .PARAMETER DisplayName
        Its name.

    .OUTPUTS
        The tab session that now shows the query, or $null when it was not opened (no tab, not
        connected, or cancelled at the save prompt).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName
    )

    if ($null -ne ($Script:Tabs | Where-Object { [string]$_.AppConfig.CurrentSqlQuery.DoId -eq $DoId } | Select-Object -First 1)) {
        return Open-SqlQueryInTab -DoId $DoId -DisplayName $DisplayName
    }

    $Private:Tab = Get-ActiveTabSession
    if ($null -eq $Private:Tab) {
        "There is no tab to open query '{0}' in; use Open in new tab." -f $DisplayName | Write-LogOutput -LogType WARNING
        return $null
    }

    if (-not (Get-TabConnectionStatus -TabSession $Private:Tab)) {
        "Tab '{0}' is not connected. Connect it first to open query '{1}' in it, or use Open in new tab." -f (Get-TabName -TabSession $Private:Tab), $DisplayName | Write-LogOutput -LogType WARNING
        return $null
    }

    $Private:Kind = Resolve-QuerySavePrompt -QueryDoId $Script:AppConfig.CurrentSqlQuery.DoId -EditorText (Get-TabEditorText -TabSession $Private:Tab) -IsDirty ([bool]$Private:Tab.IsDirty) -Connected $true
    if ($Private:Kind -ne "None" -and (Request-TabQuerySave -TabSession $Private:Tab -Kind $Private:Kind -OpenQuery) -eq "Cancel") {
        "Opening query {0} cancelled at the save prompt." -f $DoId | Write-LogOutput -LogType DEBUG
        return $null
    }

    # Whatever was there was saved or given up on; the load marks the tab clean once the query is in.
    $Private:Tab.IsDirty = $false
    $Private:Tab | Add-Member -NotePropertyName "DraftText" -NotePropertyValue $null -Force

    Select-TabQueryListItem -DoId $DoId -DisplayName $DisplayName
    "Query {0} opened in tab '{1}'." -f $DoId, (Get-TabName -TabSession $Private:Tab) | Write-LogOutput -LogType DEBUG
    return $Private:Tab
}

function Select-TabQueryListItem {
    <#
    .SYNOPSIS
        Selects a query in the active tab's query list, adding it when the list does not show it.

    .DESCRIPTION
        The list's items read "<DisplayName> - <DoId>" (Update-QueryList). An item is matched on the
        id at the end, so a list that still shows an older name is not given a second item for the
        same query.

    .PARAMETER DoId
        The query.

    .PARAMETER DisplayName
        Its name.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName
    )

    $Private:List = $Script:MainForm.Elements.ComboBoxSelectQuery
    $Private:Suffix = " - {0}" -f $DoId
    $Private:Item = @($Private:List.Items) | Where-Object { ([string]$_.Content).EndsWith($Private:Suffix) } | Select-Object -First 1

    if ($null -eq $Private:Item) {
        $Private:Item = New-QueryListItem -Content ("{0}{1}" -f $DisplayName, $Private:Suffix)
        $null = $Private:List.Items.Add($Private:Item)
    }

    $Private:List.SelectedItem = $Private:Item
}

function New-QueryListItem {
    <#
    .SYNOPSIS
        A query list item, as Update-QueryList makes them.

    .OUTPUTS
        [System.Windows.Controls.ComboBoxItem]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $Private:Item = New-Object System.Windows.Controls.ComboBoxItem
    $Private:Item.Content = $Content
    return $Private:Item
}
