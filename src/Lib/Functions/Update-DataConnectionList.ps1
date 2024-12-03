function Update-DataConnectionList {

    try {
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
                $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $true
                if ($null -ne $Result) {
                    $Result -split "`r`n" | ForEach-Object {
                        $Options = [regex]::Matches($Result, '<option.*?value="(\d+).*?data-uid="(.*?)".*?>(.*?)</option>')
                        foreach ($Match in $Options) {
                            $DataConnectionDisplayName = "{0} - {1}" -f $Match.Groups[3].Value, $Match.Groups[1].Value
                            if ($DataConnectionDisplayName -notin $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items) {
                                "Add data connection {0}" -f $DataConnectionDisplayName | Write-LogOutput -LogType DEBUG
                                $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Add($DataConnectionDisplayName) | Out-Null
                            }
                        }
                    }
                }
                "{0} data connections processed!" -f ($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count | Write-LogOutput
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
