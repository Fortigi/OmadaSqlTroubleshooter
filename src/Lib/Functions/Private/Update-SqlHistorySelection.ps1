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

    $Private:Elements.DataGridHistoryDetails.ItemsSource = @(ConvertTo-HistoryDetailList -Item $Private:Item)
    $Private:Elements.ButtonRestoreQuery.IsEnabled = $null -ne $Private:Item

    if ($null -eq $Private:Item) {
        $Private:Elements.TextBoxOldValue.Text = ""
        $Private:Elements.TextBoxNewValue.Text = ""
        $Private:Elements.RichTextBoxOldDiff.Document.Blocks.Clear()
        $Private:Elements.RichTextBoxNewDiff.Document.Blocks.Clear()
        return
    }

    $Private:Elements.TextBoxOldValue.Text = $Private:Item.OldValue
    $Private:Elements.TextBoxNewValue.Text = $Private:Item.NewValue
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

    .OUTPUTS
        [PSCustomObject[]] @{ Property; Value }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Item
    )

    if ($null -eq $Item) {
        return
    }

    [PSCustomObject]@{ Property = "Query DoId"; Value = [string]$Item.DoId }
    [PSCustomObject]@{ Property = "Query name"; Value = [string]$Item.SqlObjectName }
    [PSCustomObject]@{ Property = "Changed by"; Value = [string]$Item.ChangedBy }
    [PSCustomObject]@{ Property = "Change date"; Value = Format-OmadaHistoryDate -Value $Item.ChangeDate }
}
