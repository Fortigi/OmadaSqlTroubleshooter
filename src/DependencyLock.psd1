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
      Files        - the individual files taken out of the package, each with its own SHA-256

    About Files. The package hash above verifies the .nupkg as downloaded. It cannot verify a file
    that has been *extracted* out of it, which is exactly what the build-time bundle in
    Bin\WebView2Dlls\win-x64 contains - so every extracted file carries its own pin here. Those
    same per-file hashes are what let the module re-check each assembly immediately before
    [Reflection.Assembly]::LoadFrom, closing the window between "verified at download" and "loaded",
    during which the user-writable Bin folder could have been written to by something else.

      Source - path inside the .nupkg, forward slashes, exactly as the archive stores it
      Target - file name written into the bundle folder and into %LOCALAPPDATA%\...\Bin
      Sha256 - expected SHA-256 of that one file, lower-case hex

    Note on Microsoft.Web.WebView2.Wpf.dll: the package ships three copies with different bytes, in
    lib/net462, lib_manual/netcoreapp3.0 and lib_manual/net5.0-windows10.0.17763.0. The two fetchers
    this repository used to have disagreed about which one to take. netcoreapp3.0 is the one
    Install-WebView2 has always used and is the one pinned here. build/Get-BundledDependency.ps1
    throws when a Source below is absent from the package, so an upstream repackaging becomes a build
    failure rather than a silently incomplete bundle.
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
            Files        = @(
                @{
                    Source = "lib_manual/netcoreapp3.0/Microsoft.Web.WebView2.Core.dll"
                    Target = "Microsoft.Web.WebView2.Core.dll"
                    Sha256 = "958efdb7f13a6d1f3079756c96956cc96cf713ae46fa085c8b1e7f44316a4f7e"
                }
                @{
                    Source = "lib_manual/netcoreapp3.0/Microsoft.Web.WebView2.WinForms.dll"
                    Target = "Microsoft.Web.WebView2.WinForms.dll"
                    Sha256 = "ba823b3de79297389a9aad662e389d4d229bf3a6a0056f9ede4ee64cc49dc19c"
                }
                @{
                    Source = "lib_manual/netcoreapp3.0/Microsoft.Web.WebView2.Wpf.dll"
                    Target = "Microsoft.Web.WebView2.Wpf.dll"
                    Sha256 = "85f62dc8c6d36759212fae31bdac27ac6f9096f9d84563db765340cf58fa4744"
                }
                @{
                    Source = "runtimes/win-x64/native/WebView2Loader.dll"
                    Target = "WebView2Loader.dll"
                    Sha256 = "a9a09232c25805323d4cfb3fc8f545a190a9c8a99c93262ea99d0b88df99ec90"
                }
            )
        }
    )
}
