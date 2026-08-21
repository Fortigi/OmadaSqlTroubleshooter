function Test-WebView2RuntimeVersion {
    [CmdletBinding()]
    param()

    # Returns $true when the assemblies on disk have to be reinstalled.
    #
    # This used to ask nuget.org for the newest non-prerelease version on every module import and
    # compare it against the DLLs' ProductVersion, which meant the loaded bytes were whatever the feed
    # served that day and the module could not start without egress to nuget.org. The pinned version
    # now comes from DependencyLock.psd1, so no network call is made here at all.
    #
    # The comparison is against the stamp Install-WebView2 writes, not against the file versions - see
    # Write-WebView2Stamp for why.
    #
    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    try {
        $Artifact = Get-LockedArtifact -Id "Microsoft.Web.WebView2"

        $Stamp = Get-WebView2Stamp

        if ($null -eq $Stamp) {
            "No usable WebView2 stamp found. The assemblies will be (re)installed and verified." | Write-Verbose
            return $true
        }

        if ($Stamp.Version -ne $Artifact.Version) {
            # Deliberately -ne and not -lt: a pin moving backwards is a rollback, and the newer,
            # unverified assemblies already on disk must not keep being loaded.
            "The installed WebView2 assemblies are stamped {0} but the pinned version is {1}. They will be reinstalled and verified." -f $Stamp.Version, $Artifact.Version | Write-Host
            return $true
        }

        "WebView2 assemblies match the pinned version {0}" -f $Artifact.Version | Write-Verbose
        return $false
    }
    catch {
        "Error in Test-WebView2RuntimeVersion: {0}" -f $_.Exception.Message | Write-Warning
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
