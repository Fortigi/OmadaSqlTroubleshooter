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

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3})" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber)))

        $Private:Query = Get-SelectedSavedQuery -Action "delete"
        if ($null -eq $Private:Query) {
            return
        }

        $Private:Choice = Open-ChoiceForm -Title "Delete query" -Message ("Delete query '{0}' from Omada?`n`nThe text stays in the editor as an unsaved ad-hoc query." -f $Private:Query.DisplayName) -LeftButtonText "Delete" -RightButtonText "Cancel"
        if ($Private:Choice -ne $true) {
            return
        }

        "Delete query {0} ('{1}')" -f $Private:Query.DoId, $Private:Query.DisplayName | Write-LogOutput
        $Private:Response = Invoke-SavedQueryRequest -Request (New-OmadaQueryRequest -Kind "DeleteQuery" -Context @{
                BaseUrl       = $Script:AppConfig.BaseUrl
                TempQueryDoId = $Private:Query.DoId
            })

        if (-not $Private:Response.Succeeded) {
            "Deleting query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:Response.Message | Write-ContainedErrorLog
            return
        }

        Complete-SqlQueryRemoval -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName
        "Query '{0}' deleted." -f $Private:Query.DisplayName | Write-LogOutput
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Complete-SqlQueryRemoval {
    <#
    .SYNOPSIS
        Turns the active tab into an ad-hoc query after its saved query was deleted, and drops the
        query from every tab sharing the connection pool.

    .DESCRIPTION
        Order matters. The tab is made ad-hoc - selection cleared, dirty, DraftText set to what the
        editor shows - BEFORE the dropdown entry is removed, because removing the selected entry
        raises SelectionChanged, whose handler synchronises the draft cache: by then the tab must
        already describe the unsaved ad-hoc query it now is, or the handler would see a stale state.

    .PARAMETER DoId
        The deleted query.

    .PARAMETER DisplayName
        Its name, kept in the Display name box so saving it again suggests the same name.

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

    $Script:AppConfig.CurrentSqlQuery = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
    $Script:RunTimeData.CurrentSqlQuery.DoId = $null
    $Script:RunTimeData.CurrentSqlQuery.DisplayName = $null
    $Script:RunTimeData.CurrentSqlQuery.FullName = $null
    $Script:RunTimeData.CurrentQueryText = $null

    $Private:Tab = Get-ActiveTabSession
    if ($null -ne $Private:Tab) {
        $Private:Tab.AppConfig = $Script:AppConfig
        $Private:Tab.IsDirty = $true
        $Private:Tab | Add-Member -NotePropertyName "DraftText" -NotePropertyValue $Private:Tab.EditorText -Force
    }

    $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $null
    $Script:MainForm.Elements.ComboBoxSelectQuery.Text = ""
    $Script:MainForm.Elements.TextBoxDisplayName.Text = $DisplayName

    Update-QueryInConnectedPoolTabs -DoId $DoId -Remove
    Update-SavedQueryCommandState

    if ($null -ne $Private:Tab) {
        Update-TabHeaderTitle -TabSession $Private:Tab
        Sync-AdHocQueryDraft -TabSession $Private:Tab
    }
}
