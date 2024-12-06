function Test-SqlSchemaWindowOpen {

    try {
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
