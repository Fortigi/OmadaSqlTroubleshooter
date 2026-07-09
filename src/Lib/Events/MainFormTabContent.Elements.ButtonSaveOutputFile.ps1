$Script:MainForm.Elements.ButtonSaveOutputFile.Add_Click({
        try {
            $_ | Show-EventInfo
            Save-QueryResultToFile -QueryResult $Script:RunTimeData.QueryResult
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#    $Script:MainForm.Elements.ButtonSaveOutputFileText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonSaveOutputFile"
#    }))

#$Script:MainForm.Elements.ButtonSaveOutputFileImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonSaveOutputFile"
#    }))
