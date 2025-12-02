function Test-SqlHistoryWindowOpen {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:SqlHistoryWindowForm -and $null -ne $Script:SqlHistoryWindowForm.Definition -and $Script:SqlHistoryWindowForm.Definition.IsVisible) {
            "Test-SqlHistoryWindowOpen: true" | Write-LogOutput -LogType VERBOSE2
            return $true
        }
        else {
            "Test-SqlHistoryWindowOpen: false" | Write-LogOutput -LogType VERBOSE2
            return $false
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
