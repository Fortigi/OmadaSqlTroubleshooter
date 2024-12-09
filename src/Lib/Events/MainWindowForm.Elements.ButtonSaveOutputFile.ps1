$Script:MainWindowForm.Elements.ButtonSaveOutputFile.Add_Click({
    $_ | Show-EventInfo

    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Filter = "Json files (*.json) | *.json | Csv files (*.csv) | *.csv | CliXml files (*.xml) | *.xml | Text files (*.txt) | *.txt | All files (*.*) | *.*"
    $SaveFileDialog.Title = "Save Output File"
    if (![string]::IsNullOrWhiteSpace($Script:AppConfig.LastOutputFolder)) {
        $SaveFileDialog.InitialDirectory = $Script:AppConfig.LastOutputFolder
    }
    if ([string]::IsNullOrWhiteSpace($Script:AppConfig.LastOutputFolder)) {
        ".json" | Invoke-ConfigSetting -Property "LastExtension"
    }
    $SaveFileDialog.DefaultExt = $Script:AppConfig.LastExtension
    $InvalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
    $SaveFileDisplayName = $Script:MainWindowForm.Elements.TextBoxDisplayName.Text
    if (![string]::IsNullOrWhiteSpace($SaveFileDisplayName)) {
        $SaveFileDisplayName = ($SaveFileDisplayName.ToCharArray() | ForEach-Object {
                if ($InvalidFileNameChars -contains $_) {
                    "_"
                }
                $_
            }) -Join ""
    }
    else {
        $SaveFileDisplayName = "Output"
    }
    $SaveFileDialog.FileName = "SqlQuery_{0}_{1}_{2}_{3}_Output{4}" -f $Script:AppConfig.CurrentSqlQuery.DoId, $SaveFileDisplayName, $Script:AppConfig.CurrentDataConnection.DisplayName, [system.uri]::New($Script:AppConfig.BaseUrl).Host, $Script:AppConfig.LastExtension
    if ($SaveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Script:OutputFileName = $SaveFileDialog.FileName
        "Save outputfile: {0}" -f $Script:OutputFileName | Write-LogOutput

        if ($Null -eq $Script:OutputFileName) {
            return
        }
        elseif ($Script:OutputFileName -like "*.json") {
            $Script:QueryResult | ConvertTo-Json -Depth 15 | Set-Content $Script:OutputFileName -Encoding UTF8
        }
        elseif ($Script:OutputFileName -like "*.csv") {
            $Script:QueryResult.d.rows | Export-Csv -Path $Script:OutputFileName -Delimiter ";" -NoTypeInformation -Encoding UTF8
        }
        elseif ($Script:OutputFileName -like "*.xml") {
            $Script:QueryResult | Export-Clixml -Path $Script:OutputFileName -Depth 15
        }
        else {
        ($Script:QueryResult.d.rows | Format-Table -AutoSize | Out-String -Width 10000000).Trim() | Set-Content $Script:OutputFileName -Encoding UTF8
        }

        "Output file saved!" | Write-LogOutput -LogType DEBUG
        Split-Path $Script:OutputFileName | Invoke-ConfigSetting -Property "LastOutputFolder"
        [System.IO.Path]::GetExtension($Script:OutputFileName) | Invoke-ConfigSetting -Property "LastExtension"
        $Script:MainWindowForm.Elements.ButtonOpenOutputFile.IsEnabled = $True
    }
    else {
        "File was not saved!" | Write-LogOutput -LogType DEBUG
    }
})
