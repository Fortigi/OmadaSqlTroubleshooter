function Test-LogWindowOpen {

    try {
        if ($null -ne $Script:LogWindowForm -and $null -ne $Script:LogWindowForm.Definition -and $Script:LogWindowForm.Definition.IsVisible) {
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
