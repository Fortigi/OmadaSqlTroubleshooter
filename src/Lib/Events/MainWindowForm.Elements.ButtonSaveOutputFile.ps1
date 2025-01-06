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
        $Script:RunTimeConfig.OutputFileName = $SaveFileDialog.FileName
        "Save outputfile: {0}" -f $Script:RunTimeConfig.OutputFileName | Write-LogOutput

        if ($Null -eq $Script:RunTimeConfig.OutputFileName) {
            return
        }
        elseif ($Script:RunTimeConfig.OutputFileName -like "*.json") {
            $Script:RunTimeData.QueryResult | ConvertTo-Json -Depth 15 | Set-Content $Script:RunTimeConfig.OutputFileName -Encoding UTF8
        }
        elseif ($Script:RunTimeConfig.OutputFileName -like "*.csv") {
            $Script:RunTimeData.QueryResult.d.rows | Export-Csv -Path $Script:RunTimeConfig.OutputFileName -Delimiter ";" -NoTypeInformation -Encoding UTF8
        }
        elseif ($Script:RunTimeConfig.OutputFileName -like "*.xml") {
            $Script:RunTimeData.QueryResult | Export-Clixml -Path $Script:RunTimeConfig.OutputFileName -Depth 15
        }
        else {
        ($Script:RunTimeData.QueryResult.d.rows | Format-Table -AutoSize | Out-String -Width 10000000).Trim() | Set-Content $Script:RunTimeConfig.OutputFileName -Encoding UTF8
        }

        "Output file saved!" | Write-LogOutput -LogType DEBUG
        Split-Path $Script:RunTimeConfig.OutputFileName | Invoke-ConfigSetting -Property "LastOutputFolder"
        [System.IO.Path]::GetExtension($Script:RunTimeConfig.OutputFileName) | Invoke-ConfigSetting -Property "LastExtension"
        $Script:MainWindowForm.Elements.ButtonOpenOutputFile.IsEnabled = $True
    }
    else {
        "File was not saved!" | Write-LogOutput -LogType DEBUG
    }
})
