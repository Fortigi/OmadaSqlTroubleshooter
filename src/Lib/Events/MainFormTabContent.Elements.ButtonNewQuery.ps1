$Script:MainForm.Elements.ButtonNewQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainForm.Elements.ButtonNewQuery.IsEnabled = $false

            if (!(Test-ConnectionRequirements)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
                Set-SqlConnectionState -Status $false
            }
            else {

                if ($Script:MainForm.Elements.ButtonNewQuery.Text -eq "Delete") {
                    "Delete query query" | Write-LogOutput
                }
                elseif ([string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxDisplayName.Text)) {
                    # A new query is saved under the Display name, so it must not be empty.
                    "The Display name cannot be empty. Enter a name before saving the query." | Write-LogOutput -LogType WARNING
                    $Script:MainForm.Elements.ButtonNewQuery.IsEnabled = $true
                }
                else {

                    "Save query new query" | Write-LogOutput

                    Invoke-SaveEditorValue -NewQuery
                }
            }
        }
        catch {
            Set-SqlConnectionState -Status $false
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

##    $Script:MainForm.Elements.ButtonNewQueryText.Add_MouseLeftButtonDown({
##        Invoke-ButtonClick -ButtonName "ButtonNewQuery"
##    })

##$Script:MainForm.Elements.ButtonNewQueryImage.Add_MouseLeftButtonDown({
##        Invoke-ButtonClick -ButtonName "ButtonNewQuery"
##    })
