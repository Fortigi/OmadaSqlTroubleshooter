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

    $Private:Object = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "QueryObject" -Context $Private:Context)
    if (-not $Private:Object.Succeeded) {
        "Reading query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:Object.Message | Write-ContainedErrorLog
    }

    $Private:History = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "QueryHistory" -Context $Private:Context)
    if (-not $Private:History.Succeeded) {
        "Reading the history of query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:History.Message | Write-ContainedErrorLog
    }

    $Private:Entry = @(ConvertTo-QueryHistoryEntry -Row @($Private:History.Result.d.Rows))
    $Private:Name = Get-SavedQueryDisplayName -Result $Private:Object.Result -FallbackName $Private:Query.DisplayName
    $Private:Query.DisplayName = $Private:Name

    $Script:QueryDetailForm.Definition.Title = "Query details - {0}" -f $Private:Name
    $Script:QueryDetailForm.Elements.TextBlockQueryTitle.Text = "{0}  ({1})" -f $Private:Name, $Private:Query.DoId
    $Script:QueryDetailForm.Elements.DataGridQueryProperties.ItemsSource = @(ConvertTo-QueryPropertyList -Query $Private:Object.Result -HistoryEntry $Private:Entry)
    $Script:QueryDetailForm.Elements.TextBoxQueryText.Text = [string]$Private:Object.Result.C_QUERY
    $Script:QueryDetailForm.Elements.DataGridQueryHistory.ItemsSource = $Private:Entry
}
