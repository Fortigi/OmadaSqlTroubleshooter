$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Add_DropDownOpened({
    $_ | Show-EventInfo
    try {
        if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 0) {
            Update-DataConnectionList
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
})
