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
            Version      = "1.0.4258.31"
            Url          = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.4258.31/microsoft.web.webview2.1.0.4258.31.nupkg"
            Sha256       = "56f7f4b8bf9aee4b8efefbbdd4f67d5f74ebd1b100ed0806da71bf76af481aa9"
            Verification = "Sha256"
            InstalledBy  = "Install-WebView2"
            PinReason    = ""
            Description  = "Hosts the Monaco SQL editor inside the WPF application."
            Files        = @(
                @{
                    Source = "lib_manual/netcoreapp3.0/Microsoft.Web.WebView2.Core.dll"
                    Target = "Microsoft.Web.WebView2.Core.dll"
                    Sha256 = "d60e6e94245078cb56e44ebd5f360dc04bf18e460136be93bfc4cfca43b98505"
                }
                @{
                    Source = "lib_manual/netcoreapp3.0/Microsoft.Web.WebView2.WinForms.dll"
                    Target = "Microsoft.Web.WebView2.WinForms.dll"
                    Sha256 = "84b5772260dbdfe95591197edc9315dcd2cc86ad610e4b14ddd5e4291e31a381"
                }
                @{
                    Source = "lib_manual/netcoreapp3.0/Microsoft.Web.WebView2.Wpf.dll"
                    Target = "Microsoft.Web.WebView2.Wpf.dll"
                    Sha256 = "78a08b271412d2f98a5fa3f4472be22d4fcb62f951c6c347234de05bc93eb99e"
                }
                @{
                    Source = "runtimes/win-x64/native/WebView2Loader.dll"
                    Target = "WebView2Loader.dll"
                    Sha256 = "3426dcc55fdfb8b5e7ac623cf33b4ccf283fbf68a0c5a65bddfdb4d749a8abee"
                }
            )
        }
        @{
            Id           = "Microsoft.SqlServer.TransactSql.ScriptDom"
            PackageId    = "Microsoft.SqlServer.TransactSql.ScriptDom"
            Manifest     = "build/Dependencies/Dependencies.csproj"
            Version      = "180.117.0"
            Url          = "https://api.nuget.org/v3-flatcontainer/microsoft.sqlserver.transactsql.scriptdom/180.117.0/microsoft.sqlserver.transactsql.scriptdom.180.117.0.nupkg"
            Sha256       = "6c002292912846e55715c100afc8ab20cba4f51aa8b53c489ce6e8d64aa4f97c"
            Verification = "Sha256"
            InstalledBy  = "Install-ScriptDom"
            PinReason    = ""
            Description  = "Parses T-SQL locally so syntax errors are reported in the editor before a query is sent to Omada. The package declares no dependencies and the shipped assembly references nothing outside the base class library, so it needs no companion entry here."
        }
    )
}
