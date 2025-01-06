function Test-MainWindowOpen {

    try {
        if ($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definition -and $Script:MainWindowForm.Definition.IsVisible) {
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
