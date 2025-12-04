$Script:SqlHistoryForm.Elements.DataGridHistory.Add_SelectedCellsChanged({
        param (
            $Sender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo
            $SelectedItem = $Sender.SelectedItem

            if ($null -eq $SelectedItem) {
                $Script:SqlHistoryForm.Elements.TextBoxOldValue.Text = ""
                $Script:SqlHistoryForm.Elements.TextBoxNewValue.Text = ""
                $Script:SqlHistoryForm.Elements.TextBoxDoId.Text = ""
                $Script:SqlHistoryForm.Elements.TextBoxObjectName.Text = ""
                $Script:SqlHistoryForm.Elements.TextBoxChangedBy.Text = ""
                $Script:SqlHistoryForm.Elements.TextBoxChangeDate.Text = ""
                $Script:SqlHistoryForm.Elements.RichTextBoxOldDiff.Document.Blocks.Clear()
                $Script:SqlHistoryForm.Elements.RichTextBoxNewDiff.Document.Blocks.Clear()
                $Script:SqlHistoryForm.Elements.ButtonRestoreQuery.IsEnabled = $false
                return
            }

            $Script:SqlHistoryForm.Elements.TextBoxOldValue.Text = $SelectedItem.OldValue
            $Script:SqlHistoryForm.Elements.TextBoxNewValue.Text = $SelectedItem.NewValue
            $Script:SqlHistoryForm.Elements.TextBoxDoId.Text = $SelectedItem.DoId
            $Script:SqlHistoryForm.Elements.TextBoxObjectName.Text = $SelectedItem.SqlObjectName
            $Script:SqlHistoryForm.Elements.TextBoxChangedBy.Text = $SelectedItem.ChangedBy
            $Script:SqlHistoryForm.Elements.TextBoxChangeDate.Text = $SelectedItem.ChangeDate.ToString("yyyy-MM-dd HH:mm:ss")

            $Script:SqlHistoryForm.Elements.ButtonRestoreQuery.IsEnabled = $true

            Invoke-GenerateDiffView -OldValue $SelectedItem.OldValue -NewValue $SelectedItem.NewValue

            "Selected history item: {0} - {1}" -f $SelectedItem.ChangeDate, $SelectedItem.ChangedBy | Write-LogOutput -LogType DEBUG
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }

    })
