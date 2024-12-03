    $Script:MainWindowForm.Elements.ButtonReset.Add_Click({
            $_ | Show-EventInfo
            $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonOpenOutputFile.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $False
            $Script:MainWindowForm.Elements.TextBoxURL.Text = ""
            $Script:MainWindowForm.Elements.TextBoxURL.IsEnabled = $True
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $Null
            $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $False
            $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = ""
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
            $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $False
            "Reset" | Write-LogOutput
        })
