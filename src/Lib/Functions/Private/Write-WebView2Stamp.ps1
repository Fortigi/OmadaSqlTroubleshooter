function Write-WebView2Stamp {
    [CmdletBinding()]
    param(
        [switch]$IncludeWpf
    )

    # Records which pin the installed assemblies came from, next to the assemblies themselves.
    #
    # Test-WebView2RuntimeVersion reads this back instead of comparing the DLLs' ProductVersion for
    # two reasons. A "$Pinned -gt $OnDisk" comparison ignores a pin that moves *backwards* - a
    # rollback after a bad bump, which is precisely when it most needs to take effect - and leaves the
    # newer unverified DLLs already on disk in use. A naive "-ne" risks a re-download loop, because
    # WebView2Loader.dll's ProductVersion has not always tracked the SDK package version.
    #
    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    $Artifact = Get-LockedArtifact -Id "Microsoft.Web.WebView2"

    $InstalledPath = @($Script:WebView2CorePath, $Script:WebView2WinFormsPath, $Script:WebView2LoaderPath)
    if ($IncludeWpf.IsPresent) {
        $InstalledPath += $Script:WebView2WpfPath
    }

    $FileEntry = foreach ($Path in $InstalledPath) {
        if (-not (Test-Path $Path -PathType Leaf)) {
            continue
        }
        '        @{{ Name = "{0}"; Sha256 = "{1}" }}' -f (Split-Path $Path -Leaf), (Get-FileSha256 -Path $Path)
    }

    $StampContent = @(
        "# Written by Install-WebView2. Records the pin the assemblies in this folder were installed"
        "# from. Delete this file, or run Clear-OmadaSqlTroubleshooterCache -Scope Binaries, to force a"
        "# verified reinstall on the next module import."
        "@{"
        ('    Version = "{0}"' -f $Artifact.Version)
        "    Files   = @("
        $FileEntry
        "    )"
        "}"
    ) -join "`r`n"

    Set-Content -Path $Script:WebView2StampPath -Value $StampContent -Encoding UTF8 -Force

    "{0} - Wrote stamp '{1}' for pinned version {2}" -f $MyInvocation.MyCommand, $Script:WebView2StampPath, $Artifact.Version | Write-Verbose
}
