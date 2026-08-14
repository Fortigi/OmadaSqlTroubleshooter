function Save-FormMeasurements {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        "Save-FormMeasurements" | Write-LogOutput -LogType VERBOSE2
        $MinDelta = 500
        $Timestamp = Get-Date
        if ($Script:RunTimeConfig.LastFormMeasured -gt (Get-Date).AddMilliseconds(-$MinDelta)) {
            "FormMeasurements save ignored because last measurement was less than {0} milliseconds ago. Current Measurement save timestamp = '{1}', last measurement save timestamp: '{2}'" -f $MinDelta, $Timestamp.ToString("o"), $Script:RunTimeConfig.LastFormMeasured.ToString("o") | Write-LogOutput -LogType VERBOSE2
            return
        }
        "FormMeasurements Current Measurement save timestamp = '{0}', last measurement save timestamp: '{1}'" -f $Timestamp.ToString("o"), $Script:RunTimeConfig.LastFormMeasured.ToString("o") | Write-LogOutput -LogType VERBOSE2
        $Script:RunTimeConfig.LastFormMeasured = Get-Date

        if ($Script:MainForm.Definition.IsVisible) {
            $ValueSize = "{0}x{1}" -f [Int]::Abs(($Script:MainForm.Definition | Get-ValidFormMeasurement -Setting "Width")), [Int]::Abs(($Script:MainForm.Definition | Get-ValidFormMeasurement -Setting "Height"))
            $ValueSize | Set-ConfigProperty -Property "MainFormSize"
            $ValuePosition = "{0}x{1}" -f [Int]::Abs(($Script:MainForm.Definition | Get-ValidFormPosition -Setting "Left")), [Int]::Abs(($Script:MainForm.Definition | Get-ValidFormPosition -Setting "Top"))
            $ValuePosition | Set-ConfigProperty -Property "MainFormPosition"
            "MainForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            if ($null -ne $Script:LogForm -and $null -ne $Script:LogForm.Definition -and $Script:LogForm.Definition.IsVisible) {
                $ValueSize = "{0}x{1}" -f [Int]::Abs(($Script:LogForm.Definition | Get-ValidFormMeasurement -Setting "Width")), [Int]::Abs(($Script:LogForm.Definition | Get-ValidFormMeasurement -Setting "Height"))
                $ValueSize | Set-ConfigProperty -Property "LogFormSize"
                $ValuePosition = "{0}x{1}" -f [Int]::Abs(($Script:LogForm.Definition | Get-ValidFormPosition -Setting "Left")), [Int]::Abs(($Script:LogForm.Definition | Get-ValidFormPosition -Setting "Top"))
                $ValuePosition | Set-ConfigProperty -Property "LogFormPosition"
                "LogForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            }
            else {
                "LogForm is not visible" | Write-LogOutput -LogType VERBOSE2
            }
            if ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Definition -and $Script:SqlSchemaForm.Definition.IsVisible) {
                $ValueSize = "{0}x{1}" -f [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidFormMeasurement -Setting "Width")), [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidFormMeasurement -Setting "Height"))
                $ValueSize | Set-ConfigProperty -Property "SqlSchemaFormSize"
                $ValuePosition = "{0}x{1}" -f [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidFormPosition -Setting "Left")), [Int]::Abs(($Script:SqlSchemaForm.Definition | Get-ValidFormPosition -Setting "Top"))
                $ValuePosition | Set-ConfigProperty -Property "SqlSchemaFormPosition"
                "SqlSchemaForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            }
            else {
                "SqlSchemaForm is not visible" | Write-LogOutput -LogType VERBOSE2
            }
        }
        else {
            "MainForm is not visible" | Write-LogOutput -LogType VERBOSE2
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
