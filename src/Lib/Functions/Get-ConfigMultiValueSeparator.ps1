function Get-ConfigMultiValueSeparator {
    try {


        "Getting string separator" | Write-LogOutput -LogType VERBOSE
        if ([string]::IsNullOrEmpty($Script:AppConfig.ConfigMultiValueSeparator)) {
            Set-ConfigMultiValueSeparator -Separator [string]("§")
        }
        return [string]$Script:AppConfig.ConfigMultiValueSeparator
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
