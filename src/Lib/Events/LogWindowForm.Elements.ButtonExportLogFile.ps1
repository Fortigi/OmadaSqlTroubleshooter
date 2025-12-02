$Script:LogWindowForm.Elements.ButtonExportLogFile.Add_Click({
        $_ | Show-EventInfo
        $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $SaveFileDialog.Filter = "Log files (*.log) | *.log | All files (*.*) | *.*"
        "Dialog Filter: {0}" -f $SaveFileDialog.Filter | Write-LogOutput -LogType DEBUG
        $SaveFileDialog.Title = "Save Log File"
        "Dialog Title: {0}" -f $SaveFileDialog.Title | Write-LogOutput -LogType DEBUG
        $SaveFileDialog.FileName = "OmadaSqlTroubleShooter.log"
        "Dialog Initial FileName: {0}" -f $SaveFileDialog.FileName | Write-LogOutput -LogType DEBUG
        if ($SaveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            if ($null -eq $SaveFileDialog.FileName) {
                return
            }
            else {
                $Script:RunTimeConfig.Logging.AppLogObject | Set-Content $SaveFileDialog.FileName -Encoding UTF8
                "File saved to: {0}" -f $SaveFileDialog.FileName | Write-LogOutput -LogType DEBUG

            }
        }
        else {
            "File was not saved!" | Write-LogOutput -LogType DEBUG
        }
    })
