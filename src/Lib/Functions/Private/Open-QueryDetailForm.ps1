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

    $Private:History = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "QueryHistory" -Context $Private:Context)
    if (-not $Private:History.Succeeded) {
        "Reading the history of query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:History.Message | Write-ContainedErrorLog
    }

    $Private:Entry = @(ConvertTo-QueryHistoryEntry -Row @($Private:History.Result.d.Rows))
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
        Greys out the query details' buttons that need the live query object while it is deleted: it
        cannot be opened, renamed, or found in Omada or through OData until it is restored (in the
        query manager). Its properties, SQL and history - and the history window - stay available.

    .PARAMETER Deleted
        The query is deleted.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [bool]$Deleted
    )

    foreach ($Private:Name in @("ButtonOpenQueryDetail", "ButtonOpenQueryDetailInTab", "ButtonRenameQueryDetail", "ButtonOpenQueryDetailInOmada", "ButtonOpenQueryDetailOData")) {
        $Private:Button = $Script:QueryDetailForm.Elements.$Private:Name
        if ($null -ne $Private:Button) {
            $Private:Button.IsEnabled = -not $Deleted
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
