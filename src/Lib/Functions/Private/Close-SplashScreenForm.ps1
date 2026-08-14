function Close-SplashScreenForm {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        "Closing Splash Screen" | Write-LogOutput -LogType DEBUG
        try {
            if ($null -ne $Script:SplashScreenForm -and $null -ne $Script:SplashScreenForm.Definition) {
                $Script:SplashScreenForm.Definition.Hide()
                $Script:SplashScreenForm.Definition.Close()
            }
        }
        catch {}

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
