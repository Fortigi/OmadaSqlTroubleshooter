function Test-LogWindowOpen {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if ($null -ne $Script:LogWindowForm -and $null -ne $Script:LogWindowForm.Definition -and $Script:LogWindowForm.Definition.IsVisible) {
            "Test-LogWindowOpen: true" | Write-LogOutput -LogType VERBOSE2
            return $true
        }
        else {
            "Test-LogWindowOpen: false" | Write-LogOutput -LogType VERBOSE2
            return $false
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
