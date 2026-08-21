function Install-WebView2 {
    [CmdletBinding()]
    param(
        [switch]$IncludeWpf,
        [switch]$Force
    )

    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        $Artifact = Get-LockedArtifact -Id "Microsoft.Web.WebView2"

        $UpdateNeeded = Test-WebView2RuntimeVersion

        if (
            (
                -not (Test-Path $Script:WebView2WinFormsPath -PathType Leaf) -or
                -not (Test-Path $Script:WebView2CorePath -PathType Leaf) -or
                -not (Test-Path $Script:WebView2LoaderPath -PathType Leaf) -or
                (
                    $IncludeWpf.IsPresent -and
                    -not (Test-Path $Script:WebView2WpfPath -PathType Leaf)
                )
            ) -or $Force -or $UpdateNeeded
        ) {
            "'Microsoft.Web.WebView2' version {0} needs to be downloaded. Downloading from NuGet" -f $Artifact.Version | Write-Host

            # The module is PS7-only (#requires -Version 7.0 in the psm1), so the net462 branch the
            # previous implementation carried for Windows PowerShell was unreachable.
            $NuGetDirectoryPath = ".\lib_manual\netcoreapp3.0"
            $DirectoryName = "netcoreapp3.0"

            $RuntimeFolder = "win-x64"
            if ($Env:PROCESSOR_ARCHITECTURE -eq "x86") {
                $RuntimeFolder = "win-x86"
            }

            try {
                # Downloads from the URL pinned in DependencyLock.psd1 and verifies the bytes against
                # the pinned SHA-256 before returning. A mismatch deletes the file and throws, so
                # nothing below ever sees unverified bytes.
                $TempFile = Invoke-DownloadFile -ArtifactId "Microsoft.Web.WebView2"

                $TempZipPath = Expand-DownloadFile -FilePath $TempFile

                Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WinFormsPath) -Force
                "Installed 'Microsoft.Web.WebView2.WinForms.dll' version {0}" -f (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion | Write-Host
                Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2CorePath) -Force
                "Installed 'Microsoft.Web.WebView2.Core.dll' version {0}" -f (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion | Write-Host
                if ($IncludeWpf.IsPresent) {
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Wpf.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WpfPath) -Force
                    "Installed 'Microsoft.Web.WebView2.Wpf.dll' version {0}" -f (Get-Item $Script:WebView2WpfPath).VersionInfo.ProductVersion | Write-Host
                }

                Get-ChildItem -Path $TempZipPath -Filter "WebView2Loader.dll" -Recurse | Where-Object { $_.Directory -like ("*runtimes\{0}*" -f $RuntimeFolder) } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2LoaderPath) -Force
                "Installed 'WebView2Loader.dll' version {0}" -f (Get-Item $Script:WebView2LoaderPath).VersionInfo.ProductVersion | Write-Host

                Remove-Item -Path $TempZipPath -Force -Recurse

                # Records which pin these files came from. Test-WebView2RuntimeVersion reads it back
                # instead of comparing file versions, so a pin that moves backwards - a rollback after
                # a bad bump - still forces a reinstall.
                Write-WebView2Stamp -IncludeWpf:$IncludeWpf.IsPresent

                "WebView2 package installed successfully" | Write-Verbose
            }
            catch {
                if ($IncludeWpf.IsPresent) {
                    $DllFileListString = "'{0}', '{1}', '{2}' and '{3}'" -f ( $NuGetDirectoryPath, (Split-Path $Script:WebView2CorePath -Leaf) -join "\"), ($NuGetDirectoryPath, (Split-Path $Script:WebView2WinFormsPath -Leaf) -join "\"), ($NuGetDirectoryPath, (Split-Path $Script:WebView2WpfPath -Leaf) -join "\"), ( ".\runtimes", $RuntimeFolder , (Split-Path $Script:WebView2LoaderPath -Leaf) -join "\")
                }
                else {
                    $DllFileListString = "'{0}', '{1}' and '{2}'" -f ( $NuGetDirectoryPath, (Split-Path $Script:WebView2CorePath -Leaf) -join "\"), ($NuGetDirectoryPath, (Split-Path $Script:WebView2WinFormsPath -Leaf) -join "\"), ( ".\runtimes", $RuntimeFolder , (Split-Path $Script:WebView2LoaderPath -Leaf) -join "\")
                }
                "Failed to install the binaries. Try restart your PowerShell session or downloading the WebView2 NuGet package manually from '{0}', rename the extension to .zip and extract the files in a temporary location. Copy the following files {1} from the extracted NuGet package to {2} Error:`r`n {3}" -f $Artifact.Url, $DllFileListString, (Split-Path $Script:WebView2LoaderPath), $_.Exception | Write-Error -ErrorAction Stop
                return $false
            }
        }

        return $true
    }
    catch {
        "Failed to install WebView2: {0}" -f $_.Exception.Message | Write-Error
        return $false
    }
}
