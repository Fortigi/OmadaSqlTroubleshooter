function Test-ConnectionSettings {

    try {
        if ([string]::IsNullOrEmpty($Script:MainWindowForm.Elements.TextBoxURL.Text) -or $null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonNewQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.TextBlockConnectionStatus | Set-TextBlockText -Text "Disconnected"
            $Script:MainWindowForm.Elements.TextBlockUrl | Set-TextBlockText -Text "-"
            $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $False
            $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $null
        }
        else {
            if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth" -and
            ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text) -or [string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password))) {
                $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $False
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
                $Script:MainWindowForm.Elements.CheckboxMyQueries.IsEnabled = $False
                $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $False
                $Script:MainWindowForm.Elements.ButtonNewQuery.IsEnabled = $False
                $Script:MainWindowForm.Elements.TextBlockConnectionStatus | Set-TextBlockText -Text "Disconnected"
                $Script:MainWindowForm.Elements.TextBlockUrl | Set-TextBlockText -Text "-"
                $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $False
                $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $null
            }
            else {
                $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.CheckboxMyQueries.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonNewQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $true
                $Script:MainWindowForm.Elements.TextBlockConnectionStatus | Set-TextBlockText -Text "Connected"
                $Script:MainWindowForm.Elements.TextBlockUrl.Text = ([System.Uri]::new($Script:MainWindowForm.Elements.TextBoxUrl.Text)).Authority

                if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 1 -or ($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1) {
                    if ($null -ne $Script:MainWindowForm -and $Script:MainWindowForm.Definition -and $Script:MainWindowForm.Definition.IsVisible) {
                        $ConnectingWindow = Show-PopupWindow -Message "Connecting to Omada..."
                    }
                    if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 1) {
                        Update-DataConnectionList -NotShowPopupWindow
                    }
                    if (($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1) {
                        Update-QueryList -NotShowPopupWindow
                    }
                    if ($null -ne $ConnectingWindow) {
                        $ConnectingWindow.Close()
                    }
                }
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
