function Save-QueryResultToFile {
    <#
    .SYNOPSIS
        Prompts for a file location and saves a QueryResult-shaped object to it.

    .DESCRIPTION
        Shows the save file dialog (JSON/CSV/XML/text) and writes the given QueryResult-shaped object
        (a "d.rows" wrapper, matching $Script:RunTimeData.QueryResult) to the chosen file and format.
        Used both for saving the full query result and, via Get-DataGridSelectedQueryResult, for saving only
        the currently selected DataGrid cells.

    .PARAMETER QueryResult
        A QueryResult-shaped object (PSCustomObject with a "d.rows" property) to save.

    .EXAMPLE
        Save-QueryResultToFile -QueryResult $Script:RunTimeData.QueryResult

    .EXAMPLE
        Save-QueryResultToFile -QueryResult (Get-DataGridSelectedQueryResult)

    .NOTES
    #>

    [CmdLetBinding()]
    param (
        [parameter(Mandatory = $true)]
        [PSCustomObject]$QueryResult,
        [switch]$IsSelection
    )

    try {
        $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog

        $SaveFileDialogFilterList = @{
            1 = @{
                Name      = "JavaScript Object Notation (JSON) file (*.json)"
                Extension = "*.json"
            }
            2 = @{
                Name      = "Comma-separated values (CSV) file (*.csv)"
                Extension = "*.csv"
            }
            3 = @{
                Name      = "Common Language Infrastructure (CLI) XML file (*.xml)"
                Extension = "*.xml"
            }
            4 = @{
                Name      = "Normal text file (*.txt)"
                Extension = "*.txt"
            }
            5 = @{
                Name      = "All types (*.*)"
                Extension = "*.*"
            }
        }

        $DefaultFilterIndex = 1
        if ($null -ne $Script:AppGlobalConfig.LastExtensionIndex -and $Script:AppGlobalConfig.LastExtensionIndex -gt 0 -and $Script:AppGlobalConfig.LastExtensionIndex -ne $DefaultFilterIndex) {
            $DefaultFilterIndex = $Script:AppGlobalConfig.LastExtensionIndex
        }
        $SaveFileDialogFilterString = ("{0}|{1}" -f $($SaveFileDialogFilterList.[int32]$($DefaultFilterIndex))['Name'], $($SaveFileDialogFilterList.[int32]$($DefaultFilterIndex))['Extension']), (($SaveFileDialogFilterList.GetEnumerator() | Where-Object { $_.Name -ne $DefaultFilterIndex } | Sort-Object Name | ForEach-Object {
                    $Item = $_.Value
                    "{0}|{1}" -f $Item.Name, $Item.Extension
                }) -join "|") -join "|"
        $SaveFileDialog.Filter = $SaveFileDialogFilterString
        $SaveFileDialog.Title = "Save Output File"
        if (![string]::IsNullOrWhiteSpace($Script:AppGlobalConfig.LastOutputFolder)) {
            $SaveFileDialog.InitialDirectory = $Script:AppGlobalConfig.LastOutputFolder
        }
        if ([string]::IsNullOrWhiteSpace($Script:AppGlobalConfig.LastOutputFolder)) {
            1 | Set-ConfigProperty -Property "LastExtensionIndex"
        }
        $DefaultExt = $SaveFileDialogFilterList.[int32]$DefaultFilterIndex.Extension
        if ($DefaultFilterIndex -eq 5) {
            $DefaultExt = ".json"
        }

        $SaveFileDialog.DefaultExt = $DefaultExt
        $InvalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
        $CustomInvalidChars = @( ":", '"', "<", ">", "|", "[", "]", "{", "}", "?", "*", "&", "$", "#", "@", "!", '`', "'", ";", ",", "=", "+", "~", " " )
        $InvalidFileNameChars = $InvalidFileNameChars + $CustomInvalidChars | Select-Object -Unique
        $SaveFileDisplayName = $Script:MainForm.Elements.TextBoxDisplayName.Text
        if (![string]::IsNullOrWhiteSpace($SaveFileDisplayName)) {
            $SaveFileDisplayName = ($SaveFileDisplayName.ToCharArray() | ForEach-Object {
                    if ($InvalidFileNameChars -contains $_) {
                        "_"
                    }
                    else {
                        $_
                    }
                }) -join ""
        }
        else {
            $SaveFileDisplayName = "Output"
        }

        $SelectionSuffix = if ($IsSelection) { "_Selection" } else { "" }

        $FilterIndex = if ($null -ne $Script:AppGlobalConfig.LastExtensionIndex -and $Script:AppGlobalConfig.LastExtensionIndex -gt 0) { [int]$Script:AppGlobalConfig.LastExtensionIndex } else { [int]$DefaultFilterIndex }
        $SelectedExtension = $SaveFileDialogFilterList[$FilterIndex].Extension.Replace("*", "")

        $SaveFileDialog.FileName = "SqlQuery_{0}_{1}_{2}_{3}_Output{4}{5}" -f $Script:AppConfig.CurrentSqlQuery.DoId, $SaveFileDisplayName, $Script:AppConfig.CurrentDataConnection.DisplayName, [system.uri]::New($Script:AppConfig.BaseUrl).Host, $SelectionSuffix, $SelectedExtension
        $ExistingFiles = Get-ChildItem -Path $SaveFileDialog.InitialDirectory -Filter $SaveFileDialog.FileName -File -ErrorAction SilentlyContinue
        $Count = 1
        while ($null -ne $ExistingFiles -and $ExistingFiles.Count -gt 0) {
            $SaveFileDialog.FileName = "SqlQuery_{0}_{1}_{2}_{3}_Output{4}({5}){6}" -f $Script:AppConfig.CurrentSqlQuery.DoId, $SaveFileDisplayName, $Script:AppConfig.CurrentDataConnection.DisplayName, [system.uri]::New($Script:AppConfig.BaseUrl).Host, $SelectionSuffix, $Count, $SelectedExtension
            $ExistingFiles = Get-ChildItem -Path $SaveFileDialog.InitialDirectory -Filter $SaveFileDialog.FileName -File -ErrorAction SilentlyContinue
            $Count++
        }

        # See Suspend-WebViewCompletionPolling.ps1 - ShowDialog() pumps this thread's messages
        # while blocked, which could let the WebView2 completion poll timer fire reentrantly.
        Suspend-WebViewCompletionPolling
        try {
            $SaveFileDialogResult = $SaveFileDialog.ShowDialog()
        }
        finally {
            Resume-WebViewCompletionPolling
        }
        if ($SaveFileDialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
            $Script:RunTimeConfig.OutputFileName = $SaveFileDialog.FileName
            "Save outputfile: {0}" -f $Script:RunTimeConfig.OutputFileName | Write-LogOutput

            if ($null -eq $Script:RunTimeConfig.OutputFileName) {
                return
            }

            # The format dispatch itself lives in Export-QueryResultFile, which touches no dialog,
            # form or config state and is therefore covered by tests/Export-QueryResultFile.Tests.ps1.
            Export-QueryResultFile -QueryResult $QueryResult -Path $Script:RunTimeConfig.OutputFileName

            "Output file saved!" | Write-LogOutput -LogType DEBUG
            Split-Path $Script:RunTimeConfig.OutputFileName | Set-ConfigProperty -Property "LastOutputFolder"
            $SavedExt = [System.IO.Path]::GetExtension($Script:RunTimeConfig.OutputFileName)
            $SaveFileDialogFilterList.GetEnumerator() | ForEach-Object {
                $Item = $_.Value
                if ($Item.Extension -like "*$SavedExt") {
                    $ItemIndex = $_.Name
                    $ItemIndex | Set-ConfigProperty -Property "LastExtensionIndex"
                }
            }
            $Script:MainForm.Elements.ButtonOpenOutputFile.IsEnabled = $true
        }
        else {
            "File was not saved!" | Write-LogOutput -LogType DEBUG
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
