function Test-MainWindowOpen {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if ($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definition -and $Script:MainWindowForm.Definition.IsVisible) {
            return $true
        }
        else {
            return $false
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
