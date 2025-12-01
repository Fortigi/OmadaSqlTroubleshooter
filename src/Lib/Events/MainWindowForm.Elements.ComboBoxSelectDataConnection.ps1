$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Add_DropDownOpened({
        try {
            $_ | Show-EventInfo

            # if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 0) {
            #     Update-DataConnectionList
            # }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })


$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Add_SelectionChanged({
        try {
            $_ | Show-EventInfo

            $PsCallStack = Get-PSCallStack

            if (-not $PsCallStack[1].Command -eq "Update-DataConnectionList" -and ($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 0) {
                Update-DataConnectionList
            }

            if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content) -and $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -ne " - " -and $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -ne " - 0") {
                $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content | Set-ConfigProperty -Property "CurrentDataConnection"
                $Script:MainWindowForm.Elements.TextBlockStatusBarDatabaseName | Set-TextBlockText -Text $Script:AppConfig.CurrentDataConnection.DisplayName

                if (Test-SqlSchemaWindowOpen) {
                    Get-SqlSchemaObject
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

