function Get-FormSizeConfig {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form
    )
    try {

        $Property = "{0}Size" -f $Form.Name
        if ($null -ne $Script:AppGlobalConfig.$Property -and $Script:AppGlobalConfig.$Property -match "\d+x\d+") {
            return $Script:AppGlobalConfig.$Property
        }
        else {
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
