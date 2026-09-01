function Get-GalleryModuleVersion {
    <#
        .SYNOPSIS
        Returns the highest stable version of a module that is published on the PowerShell Gallery.

        .DESCRIPTION
        FindPackagesById() returns every package of a module, prereleases included. Prereleases
        are filtered out, because a nightly is never something the update check should push a
        user towards. The remaining packages are ordered by their parsed version, not by their
        publication date: a republished older package would otherwise come out as the latest one.
    #>
    [CmdletBinding()]
    param(
        [string]$ModuleName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Parameters = @{
            Uri                      = $ApiEndpoint
            Method                   = "Get"
            Headers                  = @{
                "Accept" = "application/xml"
            }
            ConnectionTimeoutSeconds = 1
        }
        $Response = Invoke-RestMethod @Parameters

        if ($null -eq $Response) {
            "The PowerShell Gallery returned no packages for module '{0}'." -f $ModuleName | Write-Verbose
            return $null
        }

        $StablePackages = @()
        foreach ($Package in @($Response)) {
            $VersionText = "{0}" -f $Package.Properties.version
            if ([string]::IsNullOrWhiteSpace($VersionText)) {
                continue
            }

            # The IsPrerelease property carries an m:type attribute, so Invoke-RestMethod hands
            # it over as an XML element whose value lives in the '#text' child.
            $IsPrereleaseText = "{0}" -f $Package.Properties.IsPrerelease.'#text'
            if ([string]::IsNullOrWhiteSpace($IsPrereleaseText)) {
                $IsPrereleaseText = "{0}" -f $Package.Properties.IsPrerelease
            }

            if ($IsPrereleaseText -eq "true") {
                "Skipping prerelease package '{0}' of module '{1}'." -f $VersionText, $ModuleName | Write-Verbose
                continue
            }

            # A prerelease label makes the version invalid for System.Version, which is exactly
            # the value the caller must never receive. It also catches a prerelease that the feed
            # forgot to flag, and any version string the gallery could not normalize.
            $ParsedVersion = $null
            if (-not [version]::TryParse($VersionText, [ref]$ParsedVersion)) {
                "Skipping package '{0}' of module '{1}' because its version is not a stable version." -f $VersionText, $ModuleName | Write-Verbose
                continue
            }

            $StablePackages += [PSCustomObject]@{
                ParsedVersion = $ParsedVersion
                VersionText   = $VersionText
            }
        }

        if ($StablePackages.Count -eq 0) {
            "No stable package of module '{0}' was found on the PowerShell Gallery." -f $ModuleName | Write-Verbose
            return $null
        }

        $LatestPackage = $StablePackages | Sort-Object -Property ParsedVersion -Descending | Select-Object -First 1
        return $LatestPackage.VersionText
    }
    catch {
        "Could not read the published versions of module '{0}' from the PowerShell Gallery: {1}" -f $ModuleName, $_.Exception.Message | Write-Verbose
        return $null
    }
}
