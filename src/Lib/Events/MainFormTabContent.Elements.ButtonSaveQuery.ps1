$Script:MainForm.Elements.ButtonSaveQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $false

            if (!(Test-ConnectionRequirements) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
            }
            elseif ([string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxDisplayName.Text)) {
                # The query is saved under the Display name, so it must not be empty.
                "The Display name cannot be empty. Enter a name before saving the query." | Write-LogOutput -LogType WARNING
                $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
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
