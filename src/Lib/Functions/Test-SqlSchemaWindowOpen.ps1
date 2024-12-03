function Test-SqlSchemaWindowOpen {

    try {
        if ($null -ne $Script:SqlSchemaWindowForm -and $null -ne $Script:SqlSchemaWindowForm.Definition -and $Script:SqlSchemaWindowForm.Definition.IsVisible) {
            return $true
        }
        else {
            return $false
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
