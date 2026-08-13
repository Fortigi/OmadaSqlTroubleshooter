function Get-GalleryModuleVersion {
    [CmdletBinding()]
    param(
        [string]$ModuleName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Parameters = @{
            Uri             = $ApiEndpoint
            Method          = "Get"
            Headers         = @{
                "Accept" = "application/xml"
            }
            ConnectionTimeoutSeconds = 1
        }
        $Response = Invoke-RestMethod @Parameters
        $Response = $Response | Select-Object *,@{Name='Published';Expression={($_.Properties.Published.'#text') }}

        if ($null -ne $Response) {
            $LatestVersion = $Response | Sort-Object Published -Descending | Select-Object -First 1
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

