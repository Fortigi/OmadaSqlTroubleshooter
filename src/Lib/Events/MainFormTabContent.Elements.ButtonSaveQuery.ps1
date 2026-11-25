$Script:MainForm.Elements.ButtonSaveQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $false

            if (!(Test-ConnectionRequirements)) {
                "Omada Url not set, cannot save the query!" | Write-LogOutput -LogType WARNING
            }
            elseif (Test-AdHocQuery -QueryDoId $Script:AppConfig.CurrentSqlQuery.DoId) {
                # No saved query behind the editor: saving it creates one, under a name asked for.
                Save-QueryAsNew
            }
            else {
                "Save query" | Write-LogOutput
                Invoke-SaveEditorValue
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })


#$Script:MainForm.Elements.ButtonSaveQueryText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonSaveQuery"
#    }))

#$Script:MainForm.Elements.ButtonSaveQueryImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonSaveQuery"
#    }))
