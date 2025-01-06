function Set-ButtonContent {
    PARAM(
        [Parameter(Mandatory = $true,ValueFromPipeline = $true)]
        $ButtonObject,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $CurrentButtonContent = $ButtonObject.Content
        $ButtonObject.Content = $Content
        "{0} set from '{1}' to '{2}'" -f $ButtonObject.Name, $CurrentButtonContent, $ButtonObject.Content | Write-LogOutput -LogType DEBUG

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }


}
