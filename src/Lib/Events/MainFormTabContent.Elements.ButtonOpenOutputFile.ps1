$Script:MainForm.Elements.ButtonOpenOutputFile.Add_Click({
        try {
            $_ | Show-EventInfo
            "Open outputfile: {0}" -f $Script:RunTimeConfig.OutputFileName | Write-LogOutput
            & $Script:RunTimeConfig.OutputFileName

        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#    $Script:MainForm.Elements.ButtonOpenOutputFileText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonOpenOutputFile"
#    }))

#$Script:MainForm.Elements.ButtonOpenOutputFileImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonOpenOutputFile"
#    }))
