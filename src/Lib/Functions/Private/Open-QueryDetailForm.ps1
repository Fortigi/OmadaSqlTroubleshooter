function Open-QueryDetailForm {
    <#
    .SYNOPSIS
        Opens the details of one query object: its fields, its SQL and its history.

    .DESCRIPTION
        Opened from the query manager (double-click, or Details). Read-only except for the name: the
        SQL is edited in a tab (Open in tab), and the history window for this query compares and
        restores versions (Compare / restore).

    .PARAMETER DoId
        The query.

    .PARAMETER DisplayName
        Its name.

    .PARAMETER Owner
        The window to open on top of.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        $Owner
    )

    try {
        $Script:QueryDetailForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\QueryDetailForm.xaml")
        $Script:QueryDetailForm | Add-Member -NotePropertyName "Query" -NotePropertyValue ([PSCustomObject]@{ DoId = $DoId; DisplayName = $DisplayName }) -Force
        if ($null -ne $Owner) {
            $Script:QueryDetailForm.Definition.Owner = $Owner
        }

        Import-EventObjects -ClassName "QueryDetailForm"
        Update-QueryDetailForm

        $Script:QueryDetailForm.State = "Open"
        [void]$Script:QueryDetailForm.Definition.ShowDialog()
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
    finally {
        if ($null -ne $Script:QueryDetailForm) {
            $Script:QueryDetailForm.State = "Closed"
        }
    }
}

function Update-QueryDetailForm {
    <#
    .SYNOPSIS
        Reads the detail window's query and its history from the tenant and shows them.

    .DESCRIPTION
        Two requests: the object itself (every field OData returns, its text and data connection) and
        its history. The history is shown even when the object could not be read, and the other way
        round - one failing is no reason to show nothing.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Query = $Script:QueryDetailForm.Query
    $Private:Context = @{ BaseUrl = $Script:AppConfig.BaseUrl; QueryDoId = $Private:Query.DoId }

    $Private:Object = Get-QueryDetailObject -DoId $Private:Query.DoId -Context $Private:Context
    if (-not $Private:Object.Succeeded) {
        "Reading query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:Object.Message | Write-ContainedErrorLog
    }
    $Private:Deleted = [string]$Private:Object.Result.Deleted -eq "True"
    $Private:Query | Add-Member -NotePropertyName "Deleted" -NotePropertyValue $Private:Deleted -Force

    # The tenant's history service answers 500 for a deleted object, so a deleted query's history is
    # not asked for; it is there again once the query is restored.
    $Private:Entry = @()
    if ($Private:Deleted) {
        "Query '{0}' is deleted; its history is available once it is restored." -f $Private:Query.DisplayName | Write-LogOutput -LogType DEBUG
    }
    else {
        $Private:History = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "QueryHistory" -Context $Private:Context)
        if (-not $Private:History.Succeeded) {
            "Reading the history of query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:History.Message | Write-ContainedErrorLog
        }
        $Private:Entry = @(ConvertTo-QueryHistoryEntry -Row @($Private:History.Result.d.Rows))
    }
    $Private:Name = Get-SavedQueryDisplayName -Result $Private:Object.Result -FallbackName $Private:Query.DisplayName
    $Private:Query.DisplayName = $Private:Name
    # Handed to the history window, whose Details tab shows it (Invoke-QueryDetailHistory).
    $Private:Query | Add-Member -NotePropertyName "UId" -NotePropertyValue ([string]$Private:Object.Result.UId) -Force

    $Private:Suffix = if ($Private:Deleted) { " - deleted" } else { "" }
    $Script:QueryDetailForm.Definition.Title = "Query details - {0}{1}" -f $Private:Name, $Private:Suffix
    $Script:QueryDetailForm.Elements.TextBlockQueryTitle.Text = "{0}  ({1}){2}" -f $Private:Name, $Private:Query.DoId, $Private:Suffix
    Update-QueryDetailCommandState -Deleted $Private:Deleted
    $Script:QueryDetailForm.Elements.DataGridQueryProperties.ItemsSource = @(ConvertTo-QueryPropertyList -Query $Private:Object.Result -Ownership (Get-QueryDetailOwnership) -HistoryEntry $Private:Entry)
    Set-SqlRichText -RichTextBox $Script:QueryDetailForm.Elements.RichTextBoxQueryText -Text ([string]$Private:Object.Result.C_QUERY)
    $Script:QueryDetailForm.Elements.DataGridQueryHistory.ItemsSource = $Private:Entry
    Update-DataGridColumnWidth -Grid $Script:QueryDetailForm.Elements.DataGridQueryProperties
    Update-DataGridColumnWidth -Grid $Script:QueryDetailForm.Elements.DataGridQueryHistory
}

function Get-QueryDetailObject {
    <#
    .SYNOPSIS
        The query object the details show: read from OData, or - for a deleted query, which OData does
        not return by id - the one the query manager's list already holds.

    .DESCRIPTION
        The query manager reads its list with deleted queries included (DeletedStatus=Both), so a
        deleted query's fields and SQL are already there; asking OData for it by id only fails. A query
        that is not deleted is read afresh, as before, so the details show its current state.

    .PARAMETER DoId
        The query.

    .PARAMETER Context
        The request context (BaseUrl, QueryDoId).

    .OUTPUTS
        [PSCustomObject] @{ Succeeded; Result; Message }, as Invoke-SavedQueryRequest gives.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $Private:Listed = $null
    if ($null -ne $Script:QueryManagerForm) {
        $Private:Listed = @($Script:QueryManagerForm.Queries | Where-Object { $null -ne $_ -and [string]$_.Id -eq $DoId }) | Select-Object -First 1
    }
    if ($null -ne $Private:Listed -and [string]$Private:Listed.Deleted -eq "True") {
        return [PSCustomObject]@{ Succeeded = $true; Result = $Private:Listed; Message = $null }
    }

    return Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "QueryObject" -Context $Context)
}

function Update-QueryDetailCommandState {
    <#
    .SYNOPSIS
        Enables the query details' buttons that fit the query's state, and greys out the rest.

    .DESCRIPTION
          not deleted   everything but Restore
          deleted       Restore only. A deleted query cannot be opened, renamed or deleted again, its
                        page and OData record cannot be found, and the tenant has no history for it
                        (the history window would have nothing to show). Its properties and SQL stay
                        on screen.

    .PARAMETER Deleted
        The query is deleted.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [bool]$Deleted
    )

    $Private:WhenLive = @("ButtonOpenQueryDetail", "ButtonOpenQueryDetailInTab", "ButtonRenameQueryDetail", "ButtonDeleteQueryDetail", "ButtonShowQueryDetailHistory", "ButtonOpenQueryDetailInOmada", "ButtonOpenQueryDetailOData")
    foreach ($Private:Name in @($Private:WhenLive + "ButtonRestoreQueryDetail")) {
        $Private:Button = $Script:QueryDetailForm.Elements.$Private:Name
        if ($null -ne $Private:Button) {
            $Private:Button.IsEnabled = ($Private:Name -in $Private:WhenLive) -ne $Deleted
        }
    }
}

function Get-QueryDetailOwnership {
    <#
    .SYNOPSIS
        Who created and last changed the queries, as the query manager behind the details read it
        (Get-QueryManagerOwnership): the details do not ask the tenant's view again.

    .OUTPUTS
        [hashtable], empty when the manager has none.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($null -ne $Script:QueryManagerForm -and $Script:QueryManagerForm.Ownership -is [hashtable]) {
        return $Script:QueryManagerForm.Ownership
    }
    return @{}
}

function Invoke-QueryDetailStateChange {
    <#
    .SYNOPSIS
        The query details' Delete and Restore: deletes or restores the query, then shows it as it is
        now - its buttons following its new state.

    .DESCRIPTION
        Remove-SavedSqlQuery (which asks first, and turns the tabs holding the query into ad-hoc
        queries) or Restore-SqlQueryObject (which asks first when another query has taken its name).

        When it happened, the query manager behind the details reads its list again before the details
        are read: the details take a deleted query from that list (Get-QueryDetailObject), so a list
        that still says "not deleted" would send them to OData for a query it no longer returns, and
        one that still says "deleted" would show a restored query as deleted.

    .PARAMETER Action
        Delete or Restore.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Delete", "Restore")]
        [string]$Action
    )

    $Private:Query = $Script:QueryDetailForm.Query
    $Private:Done = if ($Action -eq "Delete") {
        Remove-SavedSqlQuery -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName
    }
    else {
        Restore-SqlQueryObject -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName
    }
    # The last thing each gives back is its answer; compared on its own, so anything written before it
    # cannot turn the comparison into a filter.
    if ((@($Private:Done) | Select-Object -Last 1) -ne $true) {
        return
    }

    if ($null -ne $Script:QueryManagerForm -and $null -ne $Script:QueryManagerForm.Elements) {
        Update-QueryManagerList -Refresh
    }
    Update-QueryDetailForm
}
