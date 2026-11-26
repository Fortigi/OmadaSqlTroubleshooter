function Update-SqlHistorySelection {
    <#
    .SYNOPSIS
        Shows the history version the selection is in: its old and new value, the diff and its
        details, and enables Restore.

    .DESCRIPTION
        The version list selects as the result grid does (rows, cells, ranges), but one version is
        shown and restored at a time. So the panes follow the selection while it is in a single row
        (Get-SqlHistorySelectedItem) and are cleared - with Restore disabled - when it is in none or
        in several.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Elements = $Script:SqlHistoryForm.Elements
    $Private:Item = Get-SqlHistorySelectedItem

    $Private:UId = if ($null -ne $Private:Item) { Get-SqlHistoryQueryUId -DoId ([string]$Private:Item.DoId) } else { "" }
    $Private:Elements.DataGridHistoryDetails.ItemsSource = @(ConvertTo-HistoryDetailList -Item $Private:Item -UId $Private:UId)
    Update-DataGridColumnWidth -Grid $Private:Elements.DataGridHistoryDetails
    # Restore and the two exports of the selection act on one version.
    foreach ($Private:Name in @("ButtonRestoreQuery", "ButtonExportSelectedQuery", "ButtonExportSelectedDiff")) {
        $Private:Button = $Private:Elements.$Private:Name
        if ($null -ne $Private:Button) {
            $Private:Button.IsEnabled = $null -ne $Private:Item
        }
    }

    if ($null -eq $Private:Item) {
        Set-SqlRichText -RichTextBox $Private:Elements.RichTextBoxOldValue -Text ""
        Set-SqlRichText -RichTextBox $Private:Elements.RichTextBoxNewValue -Text ""
        $Private:Elements.RichTextBoxOldDiff.Document.Blocks.Clear()
        $Private:Elements.RichTextBoxNewDiff.Document.Blocks.Clear()
        return
    }

    Set-SqlRichText -RichTextBox $Private:Elements.RichTextBoxOldValue -Text $Private:Item.OldValue
    Set-SqlRichText -RichTextBox $Private:Elements.RichTextBoxNewValue -Text $Private:Item.NewValue
    Invoke-GenerateDiffView -OldValue $Private:Item.OldValue -NewValue $Private:Item.NewValue

    "Selected history item: {0} - {1}" -f (Format-OmadaHistoryDate -Value $Private:Item.ChangeDate), $Private:Item.ChangedBy | Write-LogOutput -LogType DEBUG
}

function Get-SqlHistorySelectedItem {
    <#
    .SYNOPSIS
        The history version the selection is in, or $null when it is in none or in several.

    .OUTPUTS
        The history item, or $null.
    #>
    [CmdletBinding()]
    param()

    $Private:Rows = @(Get-DataGridSelectedRow -Grid $Script:SqlHistoryForm.Elements.DataGridHistory)
    if ($Private:Rows.Count -ne 1) {
        return $null
    }
    return $Private:Rows[0]
}

function ConvertTo-HistoryDetailList {
    <#
    .SYNOPSIS
        A history version's details as Property / Value rows, for the Details tab's grid.

    .DESCRIPTION
        An unreadable change date is $null (issue #95); Format-OmadaHistoryDate renders it, so it
        is never a method call on $null.

    .PARAMETER Item
        The history version, or $null for none (no rows).

    .PARAMETER UId
        The query's UId (Get-SqlHistoryQueryUId).

    .OUTPUTS
        [PSCustomObject[]] @{ Property; Value }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Item,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$UId
    )

    if ($null -eq $Item) {
        return
    }

    [PSCustomObject]@{ Property = "Query DoId"; Value = [string]$Item.DoId }
    [PSCustomObject]@{ Property = "Query UId"; Value = $UId }
    [PSCustomObject]@{ Property = "Query name"; Value = [string]$Item.SqlObjectName }
    [PSCustomObject]@{ Property = "Changed by"; Value = [string]$Item.ChangedBy }
    [PSCustomObject]@{ Property = "Change date"; Value = Format-OmadaHistoryDate -Value $Item.ChangeDate }
}
