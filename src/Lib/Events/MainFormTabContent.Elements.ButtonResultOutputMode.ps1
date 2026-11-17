$Script:MainForm.Elements.ButtonResultOutputMode.Add_Click({
        try {
            $_ | Show-EventInfo
            "Switch results between grid and text" | Write-LogOutput -LogType DEBUG
            Set-TabResultOutputMode -TabSession (Get-ActiveTabSession) -Toggle
        }
        catch {
            # Write-ContainedErrorLog, not Write-LogOutput -LogType ERROR: the latter ends in a
            # terminating Write-Error, which would rethrow out of this click handler.
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
