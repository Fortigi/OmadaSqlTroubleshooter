function Test-WebView2Bundle {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$BundlePath
    )

    # Returns $true only when the folder holds a complete bundle that matches the pin: a stamp that
    # parses, whose version equals the lock's, and every file the lock lists present and hashing to
    # its pinned value.
    #
    # THIS MUST NEVER THROW. It is called during module import to choose between the bundled
    # assemblies and the runtime download. Any problem at all - no folder, no stamp, a hand-edited
    # stamp, a missing file, a tampered file, an unreadable lock - has to come back as $false so the
    # module degrades to downloading rather than failing to import. That is the whole reason the
    # fallback still exists.
    #
    # No tracer preamble and no Write-LogOutput here: see Get-DependencyLock. This runs during module
    # import, before Invoke-OmadaSqlTroubleshooter populates $Script:RunTimeConfig.

    try {
        if ([string]::IsNullOrWhiteSpace($BundlePath) -or -not (Test-Path $BundlePath -PathType Container)) {
            "{0} - No bundle folder at '{1}'" -f $MyInvocation.MyCommand, $BundlePath | Write-Verbose
            return $false
        }

        $Artifact = Get-LockedArtifact -Id "Microsoft.Web.WebView2"

        $PinnedFile = @($Artifact.Files)
        if ($PinnedFile.Count -eq 0) {
            "{0} - The lock lists no files for the bundle, so it cannot be verified" -f $MyInvocation.MyCommand | Write-Verbose
            return $false
        }

        $StampPath = Join-Path $BundlePath -ChildPath "WebView2.pin"
        if (-not (Test-Path $StampPath -PathType Leaf)) {
            "{0} - No stamp at '{1}'" -f $MyInvocation.MyCommand, $StampPath | Write-Verbose
            return $false
        }

        # Same parser as Get-DependencyLock: SafeGetValue evaluates constant expressions only, so a
        # stamp file can never execute code. A stamp full of garbage lands in the catch below and
        # comes back as $false, which is what keeps a corrupt bundle from killing module import.
        $ParseErrors = $null
        $Tokens = $null
        $StampAst = [System.Management.Automation.Language.Parser]::ParseFile($StampPath, [ref]$Tokens, [ref]$ParseErrors)
        if (($ParseErrors | Measure-Object).Count -gt 0) {
            "{0} - Stamp '{1}' does not parse" -f $MyInvocation.MyCommand, $StampPath | Write-Verbose
            return $false
        }

        $HashtableAst = $StampAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.HashtableAst] }, $false)
        if ($null -eq $HashtableAst) {
            "{0} - Stamp '{1}' contains no hashtable" -f $MyInvocation.MyCommand, $StampPath | Write-Verbose
            return $false
        }

        $Stamp = $HashtableAst.SafeGetValue()

        if (-not $Stamp.ContainsKey("Version") -or [string]::IsNullOrWhiteSpace($Stamp.Version)) {
            "{0} - Stamp '{1}' records no version" -f $MyInvocation.MyCommand, $StampPath | Write-Verbose
            return $false
        }

        if ($Stamp.Version -ne $Artifact.Version) {
            # Deliberately -ne and not -lt. A pin moving backwards is a rollback after a bad bump,
            # precisely when it most needs to take effect.
            "The bundled WebView2 assemblies are stamped {0} but the pinned version is {1}. They will be ignored in favour of a verified download." -f $Stamp.Version, $Artifact.Version | Write-Verbose
            return $false
        }

        foreach ($File in $PinnedFile) {
            $FilePath = Join-Path $BundlePath -ChildPath $File.Target
            if (-not (Test-Path $FilePath -PathType Leaf)) {
                "{0} - Bundled assembly '{1}' is missing" -f $MyInvocation.MyCommand, $File.Target | Write-Verbose
                return $false
            }

            # Compared against the hash in the LOCK, not the one in the stamp. The stamp sits in the
            # same folder as the assemblies, so anything able to swap a DLL could rewrite the stamp
            # to match it; the lock ships with the module and is what the pin actually means.
            #
            # Hashed rather than run through Confirm-FileHash on purpose. Confirm-FileHash deletes the
            # file it rejects, which is right for a download landing in a temp file and wrong for a
            # probe against an installed module folder - a probe must not damage the installation it
            # is inspecting. The real gate is unchanged: Confirm-FileHash still runs against these
            # same hashes immediately before each assembly is loaded, whichever folder it came from.
            if ((Get-FileSha256 -Path $FilePath) -ne $File.Sha256) {
                "The bundled WebView2 assembly '{0}' does not match the hash pinned in the dependency lock. The bundle will be ignored in favour of a verified download." -f $File.Target | Write-Warning
                return $false
            }
        }

        "{0} - Bundle at '{1}' is complete and matches pinned version {2}" -f $MyInvocation.MyCommand, $BundlePath, $Artifact.Version | Write-Verbose
        return $true
    }
    catch {
        # Intentionally swallowed. See the contract at the top: no failure mode here may prevent the
        # module from importing, because there is always the download path to fall back to.
        "The bundled WebView2 assemblies could not be verified ({0}). Falling back to the runtime download." -f $_.Exception.Message | Write-Verbose
        return $false
    }
}
