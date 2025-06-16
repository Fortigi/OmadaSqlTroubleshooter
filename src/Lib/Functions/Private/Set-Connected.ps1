function Set-Connected {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $true
        $Script:MainWindowForm.Elements.CheckboxMyCreatedQueries.IsEnabled = $true
        $Script:MainWindowForm.Elements.CheckboxMyUpdatedQueries.IsEnabled = $true
        $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $true
        $Script:MainWindowForm.Elements.ButtonNewQuery.IsEnabled = $true
        $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $true
        $Script:MainWindowForm.Elements.TextBlockConnectionStatus | Set-TextBlockText -Text "Connected"
        $Script:MainWindowForm.Elements.ButtonConnect | Set-ButtonContent -Content "Dis_connect"
        $Script:MainWindowForm.Elements.TextBlockUrl.Text = ([System.Uri]::new($Script:MainWindowForm.Elements.TextBoxUrl.Text)).Authority

        if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 1 -or ($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1 -and $null -ne $Script:ReconnectStatus -and $Script:ReconnectStatus -ge 2) {
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
        $Script:ConnectionStatus = $true
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
