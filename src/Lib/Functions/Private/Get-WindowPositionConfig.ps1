function Get-WindowPositionConfig {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form
    )
    try {
        $Property = "{0}Position" -f $Form.Name
        if ($null -ne $Script:AppConfig.$Property -and $Script:AppConfig.$Property -match "\b\d+x\d+\b") {
            return $Script:AppConfig.$Property
        }
        else {
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
