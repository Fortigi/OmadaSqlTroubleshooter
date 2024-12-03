function Save-WindowMeasurements {
    try {
        "{0}x{1}" -f ($Script:MainWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Width"), ($Script:MainWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Height") | Invoke-ProcessConfigSettings -Property "MainWindowSize"
        "{0}x{1}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top | Invoke-ProcessConfigSettings -Property "MainWindowPosition"

        if ($null -ne $Script:LogWindowForm -and $null -ne $Script:LogWindowForm.Definition -and $Script:LogWindowForm.Definition.IsVisible) {
            "{0}x{1}" -f ($Script:LogWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Width"), ($Script:LogWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Height") | Invoke-ProcessConfigSettings -Property "LogWindowSize"
            "{0}x{1}" -f $Script:LogWindowForm.Definition.Left, $Script:LogWindowForm.Definition.Top | Invoke-ProcessConfigSettings -Property "LogWindowPosition"
        }
        if ($null -ne $Script:SqlSchemaWindowForm -and $null -ne $Script:SqlSchemaWindowForm.Definition -and $Script:SqlSchemaWindowForm.Definition.IsVisible) {
            "{0}x{1}" -f ($Script:SqlSchemaWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Width"), ($Script:SqlSchemaWindowForm.Definition | Get-WindowAllowedMeasurement -Setting "Height") | Invoke-ProcessConfigSettings -Property "SqlSchemaWindowSize"
            "{0}x{1}" -f $Script:SqlSchemaWindowForm.Definition.Left, $Script:SqlSchemaWindowForm.Definition.Top | Invoke-ProcessConfigSettings -Property "SqlSchemaWindowPosition"
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
