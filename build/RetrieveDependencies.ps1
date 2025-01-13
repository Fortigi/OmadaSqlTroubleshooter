PARAM(
    $DestinationFolder,
    [switch]$Force
)
function RetrieveFromNuGet {
    PARAM(
        $PackageId,
        $Version,
        $DestinationFolder,
        $FilesToCopy,
        [switch]$Force
    )

    New-Item $DestinationFolder -ItemType Directory -Force | Out-Null

    $DownLoadFiles = $false
    foreach ($File in $FilesToCopy) {
        if (!(Test-Path (Join-Path $DestinationFolder -ChildPath ( $File.Split("\")[-1])) -PathType Leaf)) {
            $DownLoadFiles = $true
        }
    }

    if ($DownLoadFiles -or $Force) {
        if ($null -eq (Get-PackageSource | Where-Object { $_.Name -eq "NuGet" })) {
            "Package source 'NuGet' not found. You can retry after registering it using this command: 'Register-PackageSource -Name NuGet -Location `"https://api.NuGet.org/v3/index.json`" -ProviderName NuGet'" | Write-Host
            break
        }

        #"Get {0} from NuGet (this might take a minute or two to complete)" -f $PackageId | Write-Host
        $PackageTempFolder = New-Item (Join-Path $env:TEMP -ChildPath "OmadaSqlTroubleShooter") -ItemType Directory -Force
        $FilesDownloaded = $false
        try {
            #$Package = Save-Package $PackageId -MinimumVersion $MinimumVersion -Path $PackageTempFolder.FullName -ProviderName NuGet -Force

            $PackageFilename = ("{0}.nupkg" -f $PackageId)
            $PackageOutputFilePath = Join-Path $PackageTempFolder.FullName -ChildPath $PackageFilename
            $Parameters = @{
                Uri     = ("https://www.nuget.org/api/v2/package/{0}/{1}" -f $PackageId, $Version)
                OutFile = $PackageOutputFilePath
            }
            ("Download {0} from NuGet to {1}" -f $PackageId, $PackageOutputFilePath) | Write-Verbose
            Invoke-WebRequest @Parameters
            $FilesDownloaded = $true
        }
        catch {
            "Failed to download {0} Dll files from NuGet. Please get the latest release from https://www.nuget.org/packages/{1}. The following files need to be copied to '{1}': {2}. Error: {3}" -f $PackageId, $DestinationFolder, $FilesToCopy, $_.Exception.Message | Write-Warning
            $FilesDownloaded
        }
        if ($FilesDownloaded) {
            Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $PackageFilename) | Expand-Archive -DestinationPath $PackageTempFolder.FullName -Force

            foreach ($File in $FilesToCopy) {
                Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $File) | Copy-Item -Destination $DestinationFolder  -Force
            }
            Get-Item $PackageTempFolder.FullName | Remove-Item -Recurse -Force
        }
    }
    else {
        "{0} Dll files already present at '{1}'. Do download again use Deploy.ps1 -Force" -f $PackageId, $DestinationFolder | Write-Host
    }
}

RetrieveFromNuGet -PackageId "Microsoft.Web.WebView2" -MinimumVersion "1.0.2903.40" -DestinationFolder (Join-Path $DestinationFolder -ChildPath "Webview2Dlls") -FilesToCopy @("runtimes\win-x64\native\WebView2Loader.dll", "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.Core.dll", "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.WinForms.dll", "lib_manual\net5.0-windows10.0.17763.0\Microsoft.Web.WebView2.Wpf.dll") -Force:$Force.IsPresent
