function Update-DataConnectionList {
    PARAM(
        [switch]$NotShowPopupWindow
    )

    try {

        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        "Retrieve data connections" | Write-LogOutput -LogType DEBUG
        $SqlQueryViewContents = Get-SqlTroubleShooterView
        if ($null -ne $SqlQueryViewContents) {
            $QueryUrl = "{0}/dataobjdlg.aspx?DOID={1}" -f $Script:AppConfig.BaseUrl, $SqlQueryViewContents[0].$SqlQueryDoIdAttribute
            $Body = $null
            $Method = "GET"
            $Result = Invoke-OmadaPSWebRequestWrapper

            if ($null -eq $Result) {
                "Failed to retrieve data connections! Data connection cannot be changed!" | Write-LogOutput -LogType WARNING
                $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.IsEnabled = $False
                $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $false
            }
            else {
                if (!$NotShowPopupWindow) {
                    $UpdateDataConnectionsWindow = Show-PopupWindow -Message "Updating Data Connections..."
                }

                $SelectedDataConnection = $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content
                "Stored current selected data connection (if not empty): {0}" -f $SelectedDataConnection | Write-LogOutput -LogType DEBUG
                $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Clear()

                if ($null -ne $Result) {

                    #                     #Option 1: Retrieve databases using the OIES UID
                    #                     $RegexPattern = '<option(?:\s+selected="selected")?\s+value="(\d+)"\s+data-doid="(\d+)"\s+data-uid="([a-fA-F0-9\-]{36})">(OISES)<\/option>'
                    #                     [regex]::Matches($Result, $RegexPattern)|Out-Null
                    #                     $SqlQuery = "SELECT DisplayName,ID
                    # FROM tblDataObject
                    # WHERE DataObjectTypeID IN (
                    #     SELECT DataObjectTypeID
                    #     FROM tblDataObject
                    #     WHERE ID =  '{0}'
                    # )
                    # " -f $Matches[3].Value

                    # Get-SqlQueryObject -
                    $SetInitialConnection = $true
                    $Result -split "`r`n" | ForEach-Object {
                        $Options = [regex]::Matches($Result, '<option.*?value="(\d+).*?data-uid="(.*?)".*?>(.*?)</option>')
                        foreach ($Match in $Options) {
                            $DataConnectionDisplayName = "{0} - {1}" -f $Match.Groups[3].Value, $Match.Groups[1].Value
                            if ($DataConnectionDisplayName -notin $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Content) {
                                "Add data connection {0}" -f $DataConnectionDisplayName | Write-LogOutput -LogType DEBUG
                                $ComboBoxDataConnectionItem = New-Object System.Windows.Controls.ComboBoxItem
                                $ComboBoxDataConnectionItem.Content = $DataConnectionDisplayName
                                $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Add($ComboBoxDataConnectionItem) | Out-Null
                                if ($null -ne $SelectedDataConnection -and $SelectedDataConnection -eq $DataConnectionDisplayName) {
                                    "Set connection {0} as selected data connection" -f $DataConnectionDisplayName | Write-LogOutput -LogType DEBUG
                                    $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem = $ComboBoxDataConnectionItem
                                    $SetInitialConnection = $false
                                }
                            }
                        }
                    }
                    if ($SetInitialConnection) {
                        "Set initial data connection to OISES" | Write-LogOutput -LogType DEBUG
                        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem = $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Where-Object {$_.Content -like "OISES -*"}
                    }
                    $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $true
                    $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.IsEnabled = $True
                    $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $true
                }
                "{0} data connections processed!" -f ($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count | Write-LogOutput

                if ($null -ne $UpdateDataConnectionsWindow) {
                    $UpdateDataConnectionsWindow.Close()
                }
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
