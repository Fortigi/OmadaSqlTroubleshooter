function Save-WindowMeasurements {
    try {
        "Save-WindowMeasurements" | Write-LogOutput -LogType VERBOSE2
        $MinDelta = 500
        $Timestamp = Get-Date
        if ($Script:LastWindowMeasured -gt (Get-Date).AddMilliseconds(-$MinDelta)) {
            "WindowMeasurements save ignored because last measurement was less than {0} milliseconds ago. Current Measurement save timestamp = '{1}', last measurement save timestamp: '{2}'" -f $MinDelta, $Timestamp.ToString("o"), $Script:LastWindowMeasured.ToString("o") | Write-LogOutput -LogType VERBOSE2
            return
        }
        "WindowMeasurements Current Measurement save timestamp = '{0}', last measurement save timestamp: '{1}'" -f $Timestamp.ToString("o"), $Script:LastWindowMeasured.ToString("o") | Write-LogOutput -LogType VERBOSE2
        $Script:LastWindowMeasured = Get-Date

        if ($Script:MainWindowForm.Definition.IsVisible) {
            $ValueSize = "{0}x{1}" -f [int32]::Abs(($Script:MainWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Width")), [int32]::Abs(($Script:MainWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Height"))
            $ValueSize | Invoke-ProcessConfigSettings -Property "MainWindowSize"
            $ValuePosition = "{0}x{1}" -f [int32]::Abs(($Script:MainWindowForm.Definition | Get-WindowAllowedPosition -Setting "Left")), [int32]::Abs(($Script:MainWindowForm.Definition | Get-WindowAllowedPosition -Setting "Top"))
            $ValuePosition | Invoke-ProcessConfigSettings -Property "MainWindowPosition"
            "MainWindowForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            if ($null -ne $Script:LogWindowForm -and $null -ne $Script:LogWindowForm.Definition -and $Script:LogWindowForm.Definition.IsVisible) {
                $ValueSize = "{0}x{1}" -f [int32]::Abs(($Script:LogWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Width")), [int32]::Abs(($Script:LogWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Height"))
                $ValueSize | Invoke-ProcessConfigSettings -Property "LogWindowSize"
                $ValuePosition = "{0}x{1}" -f [int32]::Abs(($Script:LogWindowForm.Definition | Get-WindowAllowedPosition -Setting "Left")), [int32]::Abs(($Script:LogWindowForm.Definition | Get-WindowAllowedPosition -Setting "Top"))
                $ValuePosition | Invoke-ProcessConfigSettings -Property "LogWindowPosition"
                "LogWindowForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            }
            else {
                "LogWindowForm is not visible" | Write-LogOutput -LogType VERBOSE2
            }
            if ($null -ne $Script:SqlSchemaWindowForm -and $null -ne $Script:SqlSchemaWindowForm.Definition -and $Script:SqlSchemaWindowForm.Definition.IsVisible) {
                $ValueSize = "{0}x{1}" -f [int32]::Abs(($Script:SqlSchemaWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Width")), [int32]::Abs(($Script:SqlSchemaWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Height"))
                $ValueSize | Invoke-ProcessConfigSettings -Property "SqlSchemaWindowSize"
                $ValuePosition = "{0}x{1}" -f [int32]::Abs(($Script:SqlSchemaWindowForm.Definition | Get-WindowAllowedPosition -Setting "Left")), [int32]::Abs(($Script:SqlSchemaWindowForm.Definition | Get-WindowAllowedPosition -Setting "Top"))
                $ValuePosition | Invoke-ProcessConfigSettings -Property "SqlSchemaWindowPosition"
                "SqlSchemaWindowForm Size:'{0}', Position: '{1}'" -f $ValueSize, $ValuePosition | Write-LogOutput -LogType VERBOSE2
            }
            else {
                "SqlSchemaWindowForm is not visible" | Write-LogOutput -LogType VERBOSE2
            }
        }
        else {
            "MainWindowForm is not visible" | Write-LogOutput -LogType VERBOSE2
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
