$Script:MainForm.Elements.ButtonResultOutputMode.Add_Click({
        try {
            $_ | Show-EventInfo
            "Switch results between grid and text" | Write-LogOutput -LogType DEBUG
            Set-TabResultOutputMode -TabSession (Get-ActiveTabSession) -Toggle
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
