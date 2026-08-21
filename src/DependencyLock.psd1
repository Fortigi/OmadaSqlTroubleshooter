<#
    Pinned version and expected SHA-256 of every binary OmadaSqlTroubleshooter downloads.

    The module ships no binaries. The four Microsoft.Web.WebView2 assemblies that host the Monaco SQL
    editor are downloaded to %LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin the first time the module is
    imported, and then loaded into the PowerShell session with [Reflection.Assembly]::LoadFrom.
    Without this file there is nothing to check those bytes against, so a compromised feed - or
    anything able to write to that user-writable directory - would run arbitrary code in the session.

    Invoke-DownloadFile refuses to fetch anything that is not listed here, and verifies every download
    before the package is expanded or copied into Bin. A mismatch deletes the file and aborts.

    THIS FILE IS MAINTAINED BY THE BUILD. Run build/Update-DependencyLock.ps1 -Refresh to update it
    after a version change; build/Update-DependencyLock.ps1 -Check runs in PR validation and fails the
    build when a hash here no longer matches what the URL serves, or when a version here has drifted
    from build/Dependencies/Dependencies.csproj.

    Keys per artefact:
      Id           - the identifier callers pass to Invoke-DownloadFile -ArtifactId
      PackageId    - NuGet package id, and the key linking the entry to the Dependabot manifest
      Manifest     - the build/Dependencies project this entry takes its version from
      Version      - pinned version
      Url          - the exact URL the module downloads from
      Sha256       - expected SHA-256 of the downloaded bytes, lower-case hex
      Verification - "Sha256". No other mode is implemented: every artefact here is hash-pinned.
      InstalledBy  - the module function that downloads it
      PinReason    - why this entry is held at a version the manifest does not track
      Description  - why the module needs it
#>
@{
    SchemaVersion = 1
    Artifacts     = @(
        @{
            Id           = "Microsoft.Web.WebView2"
            PackageId    = "Microsoft.Web.WebView2"
            Manifest     = "build/Dependencies/Dependencies.csproj"
            Version      = "1.0.4129.50"
            Url          = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.4129.50/microsoft.web.webview2.1.0.4129.50.nupkg"
            Sha256       = "d3934f482d484b89fb4825df720c710664e1143a1e90f7b3a60794ef33f473d2"
            Verification = "Sha256"
            InstalledBy  = "Install-WebView2"
            PinReason    = ""
            Description  = "Hosts the Monaco SQL editor inside the WPF application."
        }
    )
}
