function Get-WindowSizeConfig {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form
    )
    try {
        $Property = "{0}Size" -f $Form.Name
        if ($null -ne $Script:AppConfig.$Property -and $Script:AppConfig.$Property -match "\d+x\d+") {
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
