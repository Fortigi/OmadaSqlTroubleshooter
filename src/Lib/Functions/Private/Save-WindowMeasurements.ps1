function Save-WindowMeasurements {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        "Save-WindowMeasurements" | Write-LogOutput -LogType VERBOSE2
        $MinDelta = 500
        $Timestamp = Get-Date
        if ($Script:RunTimeConfig.LastWindowMeasured -gt (Get-Date).AddMilliseconds(-$MinDelta)) {
            "WindowMeasurements save ignored because last measurement was less than {0} milliseconds ago. Current Measurement save timestamp = '{1}', last measurement save timestamp: '{2}'" -f $MinDelta, $Timestamp.ToString("o"), $Script:RunTimeConfig.LastWindowMeasured.ToString("o") | Write-LogOutput -LogType VERBOSE2
            return
        }
        "WindowMeasurements Current Measurement save timestamp = '{0}', last measurement save timestamp: '{1}'" -f $Timestamp.ToString("o"), $Script:RunTimeConfig.LastWindowMeasured.ToString("o") | Write-LogOutput -LogType VERBOSE2
        $Script:RunTimeConfig.LastWindowMeasured = Get-Date

        if ($Script:MainFormForm.Definition.IsVisible) {
            $ValueSize = "{0}x{1}" -f [Int]::Abs(($Script:MainFormForm.Definition | Get-ValidWindowMeasurement -Setting "Width")), [Int]::Abs(($Script:MainFormForm.Definition | Get-ValidWindowMeasurement -Setting "Height"))
            $ValueSize | Set-ConfigProperty -Property "MainFormSize"
            $ValuePosition = "{0}x{1}" -f [Int]::Abs(($Script:MainFormForm.Definition | Get-ValidWindowPosition -Setting "Left")), [Int]::Abs(($Script:MainFormForm.Definition | Get-ValidWindowPosition -Setting "Top"))
            $ValuePosition | Set-ConfigProperty -Property "MainFormPosition"
            "MainFormForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            if ($null -ne $Script:LogForm -and $null -ne $Script:LogForm.Definition -and $Script:LogForm.Definition.IsVisible) {
                $ValueSize = "{0}x{1}" -f [Int]::Abs(($Script:LogForm.Definition | Get-ValidWindowMeasurement -Setting "Width")), [Int]::Abs(($Script:LogForm.Definition | Get-ValidWindowMeasurement -Setting "Height"))
                $ValueSize | Set-ConfigProperty -Property "LogWindowSize"
                $ValuePosition = "{0}x{1}" -f [Int]::Abs(($Script:LogForm.Definition | Get-ValidWindowPosition -Setting "Left")), [Int]::Abs(($Script:LogForm.Definition | Get-ValidWindowPosition -Setting "Top"))
                $ValuePosition | Set-ConfigProperty -Property "LogWindowPosition"
                "LogForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            }
            else {
                "LogForm is not visible" | Write-LogOutput -LogType VERBOSE2
            }
            if ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Definition -and $Script:SqlSchemaForm.Definition.IsVisible) {
                $ValueSize = "{0}x{1}" -f [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidWindowMeasurement -Setting "Width")), [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidWindowMeasurement -Setting "Height"))
                $ValueSize | Set-ConfigProperty -Property "SqlSchemaFormSize"
                $ValuePosition = "{0}x{1}" -f [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidWindowPosition -Setting "Left")), [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidWindowPosition -Setting "Top"))
                $ValuePosition | Set-ConfigProperty -Property "SqlSchemaFormPosition"
                "SqlSchemaForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            }
            else {
                "SqlSchemaForm is not visible" | Write-LogOutput -LogType VERBOSE2
            }
        }
        else {
            "MainFormForm is not visible" | Write-LogOutput -LogType VERBOSE2
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
