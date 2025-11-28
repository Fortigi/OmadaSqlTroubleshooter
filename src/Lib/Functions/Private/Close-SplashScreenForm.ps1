function Close-SplashScreenForm {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
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
