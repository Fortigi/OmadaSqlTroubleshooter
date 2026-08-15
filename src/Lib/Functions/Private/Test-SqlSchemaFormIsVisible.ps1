function Test-SqlSchemaFormIsVisible {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Definition -and $Script:SqlSchemaForm.Definition.IsVisible) {
            "Test-SqlSchemaFormIsVisible: true" | Write-LogOutput -LogType VERBOSE2
            return $true
        }
        else {
            "Test-SqlSchemaFormIsVisible: false" | Write-LogOutput -LogType VERBOSE2
            return $false
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
