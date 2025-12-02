$Script:SqlHistoryWindowForm.Elements.DataGridHistory.Add_SelectedCellsChanged({
        param (
            $Sender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo

            $SelectedItem = $Sender.SelectedItem

            if ($null -eq $SelectedItem) {
                # Clear all content when no selection
                $Script:SqlHistoryWindowForm.Elements.TextBoxOldValue.Text = ""
                $Script:SqlHistoryWindowForm.Elements.TextBoxNewValue.Text = ""
                $Script:SqlHistoryWindowForm.Elements.TextBoxDoId.Text = ""
                $Script:SqlHistoryWindowForm.Elements.TextBoxObjectName.Text = ""
                $Script:SqlHistoryWindowForm.Elements.TextBoxChangedBy.Text = ""
                $Script:SqlHistoryWindowForm.Elements.TextBoxChangeType.Text = ""
                $Script:SqlHistoryWindowForm.Elements.TextBoxChangeDate.Text = ""
                $Script:SqlHistoryWindowForm.Elements.RichTextBoxOldDiff.Document.Blocks.Clear()
                $Script:SqlHistoryWindowForm.Elements.RichTextBoxNewDiff.Document.Blocks.Clear()
                $Script:SqlHistoryWindowForm.Elements.ButtonRestoreQuery.IsEnabled = $false
                $Script:SqlHistoryWindowForm.Elements.ButtonShowDiff.IsEnabled = $false
                return
            }

            # Populate content from selected history item
            $Script:SqlHistoryWindowForm.Elements.TextBoxOldValue.Text = $SelectedItem.OldValue
            $Script:SqlHistoryWindowForm.Elements.TextBoxNewValue.Text = $SelectedItem.NewValue
            $Script:SqlHistoryWindowForm.Elements.TextBoxDoId.Text = $SelectedItem.DoId
            $Script:SqlHistoryWindowForm.Elements.TextBoxObjectName.Text = $SelectedItem.SqlObjectName
            $Script:SqlHistoryWindowForm.Elements.TextBoxChangedBy.Text = $SelectedItem.ChangedBy
            $Script:SqlHistoryWindowForm.Elements.TextBoxChangeType.Text = $SelectedItem.ChangeType
            $Script:SqlHistoryWindowForm.Elements.TextBoxChangeDate.Text = $SelectedItem.ChangeDate.ToString("yyyy-MM-dd HH:mm:ss")

            # Enable buttons
            $Script:SqlHistoryWindowForm.Elements.ButtonRestoreQuery.IsEnabled = $true
            $Script:SqlHistoryWindowForm.Elements.ButtonShowDiff.IsEnabled = $true

            # Generate diff view
            Invoke-GenerateDiffView -OldValue $SelectedItem.OldValue -NewValue $SelectedItem.NewValue

            "Selected history item: {0} - {1}" -f $SelectedItem.ChangeDate, $SelectedItem.ChangedBy | Write-LogOutput -LogType DEBUG
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }

    })
