function Get-WebView2ExpectedHash {
    [CmdletBinding()]
    param()

    # Returns a hashtable of file name -> expected SHA-256 for the assemblies that are about to be
    # loaded, taken from whichever source they were resolved from.
    #
    #   Bundle   - the Files array in src\DependencyLock.psd1. The lock ships with the module, so it
    #              is the authority on what the pin means.
    #   Download - the stamp Install-WebView2 wrote next to the assemblies it verified. The lock
    #              cannot be used here: it pins the files as they come out of the package, and the
    #              download path is free to be at any pinned version the stamp records.
    #
    # Returns an empty hashtable when there is nothing to compare against, which the caller treats as
    # "cannot verify" rather than "verified".
    #
    # No tracer preamble and no Write-LogOutput here: see Get-DependencyLock. This is reached from
    # Initialize-OmadaSqlTroubleShooter but shares the import-time constraints of its collaborators.

    $ExpectedHash = @{}

    try {
        if ($Script:WebView2Source -eq "Bundle") {
            $Artifact = Get-LockedArtifact -Id "Microsoft.Web.WebView2"
            foreach ($File in @($Artifact.Files)) {
                $ExpectedHash[$File.Target] = $File.Sha256
            }
            return $ExpectedHash
        }

        $Stamp = Get-WebView2Stamp
        if ($null -eq $Stamp) {
            return $ExpectedHash
        }

        foreach ($StampedFile in @($Stamp.Files)) {
            if ($null -eq $StampedFile -or [string]::IsNullOrWhiteSpace($StampedFile.Name)) {
                continue
            }
            $ExpectedHash[$StampedFile.Name] = $StampedFile.Sha256
        }
    }
    catch {
        "The expected WebView2 assembly hashes could not be resolved ({0})." -f $_.Exception.Message | Write-Verbose
        return @{}
    }

    return $ExpectedHash
}
