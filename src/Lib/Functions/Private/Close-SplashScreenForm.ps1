function Close-SplashScreenForm {
    try {

        "Closing Splash Screen" | Write-LogOutput -LogType DEBUG
        try {
            $SplashScreenForm.Hide()
            $SplashScreenForm.Dispose()
        }
        catch {}

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
