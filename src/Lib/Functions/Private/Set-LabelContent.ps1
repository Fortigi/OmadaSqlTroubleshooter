function Set-LabelContent {
    PARAM(
        [Parameter(Mandatory = $true,ValueFromPipeline = $true)]
        $LabelObject,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $CurrentButtonContent = $LabelObject.Content
        $LabelObject.Content = $Content
        "{0} set from '{1}' to '{2}'" -f $LabelObject.Name, $CurrentButtonContent, $LabelObject.Content | Write-LogOutput -LogType DEBUG

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }


}
