function Test-LogWindowOpen {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:LogForm -and $null -ne $Script:LogForm.Definition -and $Script:LogForm.Definition.IsVisible) {
            "Test-LogWindowOpen: true" | Write-LogOutput -LogType VERBOSE2
            return $true
        }
        else {
            "Test-LogWindowOpen: false" | Write-LogOutput -LogType VERBOSE2
            return $false
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
