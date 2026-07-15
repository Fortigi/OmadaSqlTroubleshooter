$Script:MainForm.Elements.ComboBoxSelectDataConnection.Add_DropDownOpened({
        try {
            $_ | Show-EventInfo

            # if (($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 0) {
            #     Update-DataConnectionList
            # }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })


$Script:MainForm.Elements.ComboBoxSelectDataConnection.Add_SelectionChanged({
        try {
            $_ | Show-EventInfo

            $PsCallStack = Get-PSCallStack

            if (-not $PsCallStack[1].Command -eq "Update-DataConnectionList" -and ($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 0) {
                Update-DataConnectionList
            }

            if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content) -and $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -ne " - " -and $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -ne " - 0") {
                $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content | Set-ConfigProperty -Property "CurrentDataConnection"
                $Script:MainForm.Elements.TextBlockStatusBarDatabaseName | Set-TextBlockText -Text $Script:AppConfig.CurrentDataConnection.DisplayName

                # Always retrieve the schema - not just when the schema window is open. The data
                # connection determines the schema, and the editor's IntelliSense needs it to offer
                # tables/columns for THIS database. Get-SqlSchemaObject serves the per-pool +
                # per-database cache, so switching back to a connection already seen costs no
                # round-trip, and it updates the schema window only when that window exists.
                Get-SqlSchemaObject
            }

            # The selected data connection is the "<Connection>" part of the tab header.
            $ActiveTab = Get-ActiveTabSession
            if ($null -ne $ActiveTab) {
                Update-TabHeaderTitle -TabSession $ActiveTab
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

