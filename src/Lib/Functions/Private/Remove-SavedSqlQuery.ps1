function Remove-SavedSqlQuery {
    <#
    .SYNOPSIS
        Deletes the active tab's saved query from the tenant, after confirmation.

    .DESCRIPTION
        The query's text is NOT thrown away with it. The tab keeps the editor as it is and becomes an
        ad-hoc query with unsaved changes, so a mistaken delete costs one Save to undo, and closing
        the tab or the application still asks about it (and keeps it in the draft cache meanwhile).

        Omada deletes data objects softly - they are marked Deleted, which is also how this
        application's own temporary query objects are removed and later undeleted - but this
        application offers no undelete for user queries; the confirmation says the query is deleted.

        Needs the Delete right on the OData auth element; a refusal is reported with the tenant's
        message and nothing changes locally.

        Without -DoId it deletes the active tab's selected query (the toolbar's Delete); the query
        manager passes the query it has selected. Every tab that holds the query is turned into an
        ad-hoc query, whichever tab is active.

    .PARAMETER DoId
        The query to delete. Omitted: the active tab's selected query.

    .PARAMETER DisplayName
        That query's name.

    .OUTPUTS
        [bool] $true when the query was deleted.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3})" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber)))

        $Private:Query = if ([string]::IsNullOrWhiteSpace($DoId)) { Get-SelectedSavedQuery -Action "delete" } else { [PSCustomObject]@{ DoId = $DoId; DisplayName = $DisplayName } }
        if ($null -eq $Private:Query) {
            return $false
        }

        $Private:Choice = Open-ChoiceForm -Title "Delete query" -Message ("Delete query '{0}' from Omada?`n`nWhere it is open, its text stays in the editor as an unsaved ad-hoc query." -f $Private:Query.DisplayName) -LeftButtonText "Delete" -RightButtonText "Cancel"
        if ($Private:Choice -ne $true) {
            return $false
        }

        "Delete query {0} ('{1}')" -f $Private:Query.DoId, $Private:Query.DisplayName | Write-LogOutput
        $Private:Response = Invoke-SavedQueryRequest -Request (New-OmadaQueryRequest -Kind "DeleteQuery" -Context @{
                BaseUrl       = $Script:AppConfig.BaseUrl
                TempQueryDoId = $Private:Query.DoId
            })

        if (-not $Private:Response.Succeeded) {
            "Deleting query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:Response.Message | Write-ContainedErrorLog
            return $false
        }

        Complete-SqlQueryRemoval -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName
        "Query '{0}' deleted." -f $Private:Query.DisplayName | Write-LogOutput
        return $true
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        return $false
    }
}

function Complete-SqlQueryRemoval {
    <#
    .SYNOPSIS
        After a query was deleted: every tab holding it becomes an ad-hoc query that keeps its text,
        and the query leaves every query list of the connection pool.

    .DESCRIPTION
        Each holding tab is made active for the change (Convert-TabToAdHocQuery works on the active
        tab's state, and clearing its selection raises a handler that reads the active tab), and the
        tab that was active is made active again afterwards. With every holding tab already detached,
        no list still has the query selected, so Update-QueryInConnectedPoolTabs removes it everywhere.

    .PARAMETER DoId
        The deleted query.

    .PARAMETER DisplayName
        Its name, kept as each tab's proposed name: the tab keeps its name, and saving it again
        suggests the same one.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [string]$DisplayName
    )

    Clear-RecentSqlQueryObject -DoId $DoId

    $Private:Previous = Get-ActiveTabSession
    try {
        foreach ($Private:Tab in @($Script:Tabs | Where-Object { $null -ne $_ -and [string]$_.AppConfig.CurrentSqlQuery.DoId -eq $DoId })) {
            Set-ActiveTabContext -TabSession $Private:Tab
            Convert-TabToAdHocQuery -TabSession $Private:Tab -DisplayName $DisplayName
        }
    }
    finally {
        if ($null -ne $Private:Previous -and $Script:ActiveTabId -ne $Private:Previous.Id) {
            Set-ActiveTabContext -TabSession $Private:Previous
        }
    }

    Update-QueryInConnectedPoolTabs -DoId $DoId -Remove
    Update-SavedQueryCommandState
}

function Convert-TabToAdHocQuery {
    <#
    .SYNOPSIS
        Turns the active tab, whose saved query was deleted, into an unsaved ad-hoc query.

    .DESCRIPTION
        The tab's own state - dirty, DraftText set to what the editor shows, the old name proposed -
        is set BEFORE the selection is cleared, because clearing it raises SelectionChanged, whose
        handler synchronises the draft cache from the tab: by then the tab must already describe the
        unsaved ad-hoc query it now is.

    .PARAMETER TabSession
        The tab, made active by the caller.

    .PARAMETER DisplayName
        The deleted query's name.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession,

        [string]$DisplayName
    )

    $TabSession.IsDirty = $true
    $TabSession | Add-Member -NotePropertyName "DraftText" -NotePropertyValue $TabSession.EditorText -Force
    $TabSession | Add-Member -NotePropertyName "ProposedQueryName" -NotePropertyValue $DisplayName -Force

    Clear-TabSavedQuerySelection -TabSession $TabSession

    Update-TabHeaderTitle -TabSession $TabSession
    Sync-AdHocQueryDraft -TabSession $TabSession
}
