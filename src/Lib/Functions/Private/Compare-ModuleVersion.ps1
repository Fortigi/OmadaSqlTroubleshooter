function Compare-ModuleVersion {
    <#
        .SYNOPSIS
        Compares two module version strings without ever throwing.

        .DESCRIPTION
        Returns exactly -1 when the installed version is older than the gallery version, 0 when
        both are the same and 1 when the installed version is the newer one. Returns $null when
        either value cannot be parsed, so the caller can skip the comparison instead of
        crashing on a cast.

        Both values are first parsed as a SemanticVersion, which understands a prerelease
        label such as '2026.8.22-nightly67'. A four part version such as '2026.6.26.4' is not
        valid SemVer, so the pair falls back to System.Version. Casting a prerelease string to
        System.Version is what broke the startup update check, so no cast is used anywhere.
    #>
    [CmdletBinding()]
    [OutputType([System.Nullable[int]])]
    param(
        [string]$InstalledVersion,
        [string]$GalleryVersion
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

    if ([string]::IsNullOrWhiteSpace($InstalledVersion) -or [string]::IsNullOrWhiteSpace($GalleryVersion)) {
        "Cannot compare version '{0}' with version '{1}' because one of them is empty." -f $InstalledVersion, $GalleryVersion | Write-Verbose
        return $null
    }

    $InstalledSemanticVersion = $null
    $GallerySemanticVersion = $null
    if ([System.Management.Automation.SemanticVersion]::TryParse($InstalledVersion, [ref]$InstalledSemanticVersion) -and [System.Management.Automation.SemanticVersion]::TryParse($GalleryVersion, [ref]$GallerySemanticVersion)) {
        # CompareTo only promises a negative, zero or positive number. Normalize it, because
        # the documented contract of this function is -1, 0 or 1.
        return [Math]::Sign($InstalledSemanticVersion.CompareTo($GallerySemanticVersion))
    }

    $InstalledSystemVersion = $null
    $GallerySystemVersion = $null
    if ([version]::TryParse($InstalledVersion, [ref]$InstalledSystemVersion) -and [version]::TryParse($GalleryVersion, [ref]$GallerySystemVersion)) {
        return [Math]::Sign($InstalledSystemVersion.CompareTo($GallerySystemVersion))
    }

    "Cannot compare version '{0}' with version '{1}' because at least one of them is not a valid version." -f $InstalledVersion, $GalleryVersion | Write-Verbose
    return $null
}
