$Script:SplashScreenForm.Definition.Add_Loaded({
        try {
            $_ | Show-EventInfo
            $Script:SplashScreenForm.Definition.Focus() | Out-Null
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
