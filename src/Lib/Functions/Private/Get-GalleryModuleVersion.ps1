function Get-GalleryModuleVersion {
    [CmdLetBinding()]
    param (
        [string]$ModuleName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Response = Invoke-RestMethod -Uri $ApiEndpoint -Method Get -Headers @{
            "Accept" = "application/xml"
        } -ConnectionTimeoutSeconds 1

        if ($null -ne $Response) {
            $LatestVersion = $Response | Sort-Object updated -Descending | Select-Object -First 1
            return $LatestVersion.Properties.version
        }
        else {
            return $null
        }
    }
    catch {
        return $null
    }
}
