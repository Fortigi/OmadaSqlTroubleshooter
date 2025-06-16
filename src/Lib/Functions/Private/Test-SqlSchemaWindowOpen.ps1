function Test-SqlSchemaWindowOpen {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if ($null -ne $Script:SqlSchemaWindowForm -and $null -ne $Script:SqlSchemaWindowForm.Definition -and $Script:SqlSchemaWindowForm.Definition.IsVisible) {
            "Test-SqlSchemaWindowOpen: true" | Write-LogOutput -LogType VERBOSE2
            return $true
        }
        else {
            "Test-SqlSchemaWindowOpen: false" | Write-LogOutput -LogType VERBOSE2
            return $false
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
