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

        # The version matching is not on its own enough. Bin is user-writable, so an assembly can be
        # swapped after a verified install without the stamp changing - the download was verified,
        # but nothing had re-checked the bytes since. Comparing each file against the hash recorded
        # at install time closes that, and a mismatch means a re-download rather than a hard failure.
        #
        # Install-WebView2 separately tests that each assembly is present, so a missing file already
        # forces a reinstall; this catches the file that is present but no longer what was installed.
        $BinFolder = Split-Path $Script:WebView2StampPath
        foreach ($StampedFile in @($Stamp.Files)) {
            if ($null -eq $StampedFile -or [string]::IsNullOrWhiteSpace($StampedFile.Name)) {
                continue
            }

            $FilePath = Join-Path $BinFolder -ChildPath $StampedFile.Name
            if (-not (Test-Path $FilePath -PathType Leaf)) {
                "The stamped WebView2 assembly '{0}' is missing. The assemblies will be reinstalled and verified." -f $StampedFile.Name | Write-Host
                return $true
            }

            if ((Get-FileSha256 -Path $FilePath) -ne $StampedFile.Sha256) {
                "The WebView2 assembly '{0}' no longer matches the hash recorded when it was installed. It will be reinstalled and verified." -f $StampedFile.Name | Write-Warning
                return $true
            }
        }

        "WebView2 assemblies match the pinned version {0}" -f $Artifact.Version | Write-Verbose
        return $false
    }
    catch {
        "Error in Test-WebView2RuntimeVersion: {0}" -f $_.Exception.Message | Write-Warning
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
