function Get-GalleryModuleVersion {
    [CmdletBinding()]
    param(
        [string]$ModuleName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Parameters = @{
            Uri                      = $ApiEndpoint
            Method                   = "Get"
            Headers                  = @{
                "Accept" = "application/xml"
            }
            ConnectionTimeoutSeconds = 2
        }
        $Response = Invoke-RestMethod @Parameters
        $Response = $Response | Select-Object *, @{Name = 'Version'; Expression = { ($_.Properties.version) } }, @{Name = 'Published'; Expression = { ($_.Properties.Published.'#text') } }, @{Name = 'IsPrerelease'; Expression = { ($_.Properties.IsPrerelease.'#text') } }

        $Return = $null
        if ($null -ne $Response) {
            $LatestVersion = $Response | Sort-Object Published -Descending | Select-Object -First 1
            if ($null -ne $LatestVersion.version) {
                $Return = [pscustomobject]@{
                    Version           = ($LatestVersion.version.split("-") | Measure-Object).Count -gt 1 ? "{0}-{1}" -f [string]::Join("-", ($LatestVersion.version -split "-")[0..$(($LatestVersion.version.split("-") | Measure-Object).Count - 2)]), ($LatestVersion.version -split "-")[$(($LatestVersion.version.split("-") | Measure-Object).Count - 1)] : $LatestVersion.version
                    FullVersion       = $LatestVersion.version
                    Published         = $LatestVersion.Published
                    IsPrerelease      = $LatestVersion.IsPrerelease
                    LastVersionObject = $LatestVersion
                }
            }
        }
        else {
            $Return = $null
        }
        return $Return
    }
    catch {
        return $null
    }
}

