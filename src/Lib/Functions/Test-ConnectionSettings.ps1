function Test-ConnectionSettings {

    try {
        if ([string]::IsNullOrEmpty($Script:MainWindowForm.Elements.TextBoxURL.Text) -or $null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $False
            $Script:MainWindowForm.Elements.TextBlockConnectionStatus.Text = "Disconnected"
            $Script:MainWindowForm.Elements.TextBlockUrl.Text = "-"
        }
        else {
            if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth" -and
            ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text) -or [string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password))) {
                $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $False
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
                $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $False
                $Script:MainWindowForm.Elements.TextBlockConnectionStatus.Text = "Disconnected"
                $Script:MainWindowForm.Elements.TextBlockUrl.Text = "-"
            }
            else {
                Update-QueryList
                $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $true
                $Script:MainWindowForm.Elements.TextBlockConnectionStatus.Text = "Connected"
                $Script:MainWindowForm.Elements.TextBlockUrl.Text = ([System.Uri]::new($Script:MainWindowForm.Elements.TextBoxUrl.Text)).Authority
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
