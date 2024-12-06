$Script:MainWindowForm.Elements.ButtonNewQuery.Add_Click({
    $_ | Show-EventInfo
    $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $False
    $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $False
    try {
        if (!(Test-ConnectionRequirements)) {
            "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
        }
        else {

            if ($Script:MainWindowForm.Elements.ButtonNewQuery.Text -eq "Delete") {
                "Delete query query" | Write-LogOutput
            }
            else {

                "Save query new query" | Write-LogOutput

                Invoke-SaveQuery -NewQuery
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
})
