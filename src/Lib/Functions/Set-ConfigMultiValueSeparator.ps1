function Set-ConfigMultiValueSeparator {
    PARAM(
        [string]$Separator = "§"
    )

    try {
        "Set string separator to {0}!" -f $Separator | Write-LogOutput -LogType VERBOSE
        $Separator | Invoke-ProcessConfigSettings -Property "ConfigMultiValueSeparator"

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
