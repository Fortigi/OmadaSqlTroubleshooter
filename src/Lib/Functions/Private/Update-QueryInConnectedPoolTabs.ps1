function Update-QueryInConnectedPoolTabs {
    <#
    .SYNOPSIS
        Applies a rename or a delete of a saved query to every connected tab that shares the active
        tab's connection pool, the active tab included.

    .DESCRIPTION
        The counterpart of Add-QueryToConnectedPoolTabs, for the same reason: tabs on one tenant and
        account share a query list, and without this the other tabs keep showing the old name, or a
        query that no longer exists, until each of them refreshes from the server.

        For each pool member the per-tab cache (QueryListCache.QueryList) and the query dropdown are
        updated. A dropdown entry is matched by its DoId suffix (" - <DoId>"), the format Update-QueryList
        writes, so the old name does not need to be known.

          Rename  The entry's Content changes in place. Where the entry is selected, the editable
                  ComboBox's Text is set as well, because WPF does not refresh it from a changed
                  Content. Neither raises SelectionChanged, so no editor is reloaded and no unsaved
                  edit is lost.
          Remove  The entry is removed - except in a tab other than the active one where it is
                  selected. Removing a selected entry raises SelectionChanged, whose handler acts on the
                  ACTIVE tab's controls, so it would reload the wrong editor. That tab keeps its entry
                  until it refreshes; executing it there reports that the query no longer exists. The
                  active tab is handled by the caller (Complete-SqlQueryRemoval).

    .PARAMETER DoId
        The query that was renamed or deleted.

    .PARAMETER DisplayName
        The new name (rename only).

    .PARAMETER Remove
        The query was deleted.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [switch]$Remove
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        foreach ($Private:Tab in @(Get-ConnectedPoolTab)) {
            $Private:Tab.RunTimeData.QueryListCache.QueryList = @(Update-CachedQueryList -QueryList $Private:Tab.RunTimeData.QueryListCache.QueryList -DoId $DoId -DisplayName $DisplayName -Remove:$Remove)

            $Private:ComboBox = $Private:Tab.Elements.ComboBoxSelectQuery
            if ($null -eq $Private:ComboBox) {
                continue
            }

            $Private:IsActiveTab = $Private:Tab.Id -eq $Script:ActiveTabId
            foreach ($Private:Item in @($Private:ComboBox.Items | Where-Object { (Get-QueryListItemDoId -Content $_.Content) -eq $DoId })) {
                Update-QueryListItem -ComboBox $Private:ComboBox -Item $Private:Item -DoId $DoId -DisplayName $DisplayName -Remove:$Remove -IsActiveTab:$Private:IsActiveTab
            }
        }
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Update-QueryListItem {
    <#
    .SYNOPSIS
        Renames or removes one query dropdown entry; see Update-QueryInConnectedPoolTabs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ComboBox,

        [Parameter(Mandatory = $true)]
        $Item,

        [string]$DoId,

        [string]$DisplayName,

        [switch]$Remove,

        [switch]$IsActiveTab
    )

    $Private:IsSelected = $ComboBox.SelectedItem -eq $Item

    if (-not $Remove) {
        $Item.Content = "{0} - {1}" -f $DisplayName, $DoId
        if ($Private:IsSelected) {
            $ComboBox.Text = $Item.Content
        }
        return
    }

    if ($Private:IsSelected -and -not $IsActiveTab) {
        "Deleted query {0} stays listed in a background tab where it is selected, until that tab refreshes." -f $DoId | Write-LogOutput -LogType DEBUG
        return
    }

    $ComboBox.Items.Remove($Item)
}

function Get-ConnectedPoolTab {
    <#
    .SYNOPSIS
        The connected tabs sharing the active tab's connection pool, the active tab included.

    .DESCRIPTION
        Same membership rule as Add-QueryToConnectedPoolTabs: the active tab's connection state is the
        live $Script:ConnectionStatus, every other tab's is what it last stored.

    .OUTPUTS
        The tab sessions.
    #>
    [CmdletBinding()]
    param()

    $Private:ActiveTab = Get-ActiveTabSession
    if ($null -eq $Private:ActiveTab) {
        return
    }

    $Private:ActiveIdentity = Get-TabConnectionIdentity -TabSession $Private:ActiveTab
    if ($null -eq $Private:ActiveIdentity -or $Private:ActiveIdentity.IsEmpty -or [string]::IsNullOrWhiteSpace($Private:ActiveIdentity.Key)) {
        $Private:ActiveTab
        return
    }

    foreach ($Private:Tab in $Script:Tabs) {
        $Private:Connected = if ($Private:Tab.Id -eq $Script:ActiveTabId) { [bool]$Script:ConnectionStatus } else { [bool]$Private:Tab.ConnectionStatus }
        if (-not $Private:Connected) {
            continue
        }

        $Private:Identity = Get-TabConnectionIdentity -TabSession $Private:Tab
        if ($null -ne $Private:Identity -and $Private:Identity.Key -eq $Private:ActiveIdentity.Key) {
            $Private:Tab
        }
    }
}
