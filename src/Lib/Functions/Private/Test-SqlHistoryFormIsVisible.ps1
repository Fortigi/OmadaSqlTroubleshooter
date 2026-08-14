function Test-SqlHistoryFormOpen {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if ($null -ne $Script:SqlHistoryForm -and $null -ne $Script:SqlHistoryForm.Definition -and $Script:SqlHistoryForm.Definition.IsVisible) {
            "Test-SqlHistoryFormOpen: true" | Write-LogOutput -LogType VERBOSE2
            return $true
        }
        else {
            "Test-SqlHistoryFormOpen: false" | Write-LogOutput -LogType VERBOSE2
            return $false
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
