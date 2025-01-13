#requires -Version 7.0
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'WebViewInstalled', Justification = 'The variable is used, but script analyzer does not recognize it')]
[CmdletBinding(SupportsShouldProcess)]
PARAM(
    [switch]$Force
)
$ErrorActionPreference = "Stop"
try {


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
                ("Download {0} from NuGet to {1}" -f $PackageId,$PackageOutputFilePath) | Write-Verbose
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


    $DeployScriptRoot = (Get-Item ($MyInvocation.MyCommand.Path | Split-Path )).Parent.FullName
    Push-Location $DeployScriptRoot
    $ScriptRootName = "src"
    [xml]$MainWindowXaml = Get-Content (Join-Path $DeployScriptRoot -ChildPath "$ScriptRootName\lib\ui\MainWindow.xaml")
    $ScriptName = "OmadaSqlTroubleshooter.ps1"
    $ScriptTitle = $MainWindowXaml.Window.Title

    $CommitId = "Unknown"
    try {
        if ((Get-Command "git.exe" | Measure-Object).Count -gt 0) {
            $CommitId = git rev-parse HEAD
        }
    }
    catch { $Error.clear }

    "Deploy Scriptname: '{0}'" -f $ScriptName | Write-Verbose

    $OmadaSqlTroubleShooterPs1 = Join-Path  (Get-Item $DeployScriptRoot).FullName -ChildPath "$ScriptRootName\$ScriptName"
    "OmadaSqlTroubleShooterPath: '{0}'" -f $OmadaSqlTroubleShooterPs1 | Write-Verbose

    $LocalAppDataPath = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath $ScriptName.Replace(".ps1", "")
    New-Item $LocalAppDataPath -ItemType Directory -Force | Out-Null
    New-Item (Join-Path $LocalAppDataPath -ChildPath "bin") -ItemType Directory -Force | Out-Null
    $RoamingAppDataPath = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)) -ChildPath $ScriptName.Replace(".ps1", "")
    New-Item $RoamingAppDataPath -ItemType Directory -Force | Out-Null

    "Deploy '{0}' from '{1}' to '{2}'" -f $ScriptName, $DeployScriptRoot, $LocalAppDataPath | Write-Host

    #Clear existing files in root and lib
    Get-ChildItem -Path $LocalAppDataPath -File | ForEach-Object {
        Get-Item $_ | Remove-Item -Recurse -Force -Confirm:$false
    }
    if (Test-Path (Join-Path $LocalAppDataPath -ChildPath "lib") -PathType Container) {
        Get-ChildItem (Join-Path $LocalAppDataPath -ChildPath "lib") | Remove-Item -Recurse -Force -Confirm:$false
    }

    @("OmadaSqlTroubleshooter.psm1", "OmadaSqlTroubleshooter.psd1") | ForEach-Object {
        Get-Item -Path (Join-Path $DeployScriptRoot -ChildPath "$ScriptRootName\$_") | Copy-Item -Destination $LocalAppDataPath -Force
    }

    Get-Item -Path (Join-Path $DeployScriptRoot -ChildPath "$ScriptRootName\Monaco") | Copy-Item -Destination $LocalAppDataPath -Force -Recurse
    New-Item (Join-Path $LocalAppDataPath -ChildPath  "lib\ui") -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path (Join-Path $DeployScriptRoot -ChildPath "$ScriptRootName\lib\ui") -Filter *.xaml | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "lib\ui") -Force -Recurse
    Get-ChildItem -Path (Join-Path $DeployScriptRoot -ChildPath "$ScriptRootName\lib\ui") -Filter *.ico | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "lib\ui") -Force -Recurse

    New-Item (Join-Path $LocalAppDataPath -ChildPath  "lib\schema") -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path (Join-Path $DeployScriptRoot -ChildPath "$ScriptRootName\lib\schema") -Filter *.json | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "lib\schema") -Force -Recurse

    @("functions", "events") | ForEach-Object {
        $LibSource = $_
        $SourceChildPath = "$ScriptRootName\lib\{0}" -f $LibSource
        $TargetChildPath = "lib\{0}" -f $LibSource
        $TargetFilePath = "{0}\{1}.ps1" -f $TargetChildPath, $LibSource
        New-Item (Join-Path $LocalAppDataPath -ChildPath $TargetChildPath) -ItemType Directory -Force | Out-Null
        "#Source file: {0}, Deployed at {1}, Git commit id: {2}`r`n`r`n" -f $LibSource, (Get-Date).ToString("o"), $CommitId | Out-File -Path (Join-Path $LocalAppDataPath -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        Get-ChildItem -Path (Join-Path $DeployScriptRoot -ChildPath $SourceChildPath) -Recurse -File | ForEach-Object {
            Get-Content $_ | Out-File -Path (Join-Path $LocalAppDataPath -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        }
    }

    RetrieveFromNuGet -PackageId "Microsoft.Data.Sqlite.Core" -MinimumVersion "9.0.0" -DestinationFolder (Join-Path $LocalAppDataPath -ChildPath "Bin\Sqlite") -FilesToCopy @("lib\net8.0\Microsoft.Data.Sqlite.dll") -Force:$Force.IsPresent
    RetrieveFromNuGet -PackageId "SQLitePCLRaw.core" -MinimumVersion "2.1.10" -DestinationFolder (Join-Path $LocalAppDataPath -ChildPath "Bin\Sqlite") -FilesToCopy @("lib\netstandard2.0\SQLitePCLRaw.core.dll") -Force:$Force.IsPresent
    RetrieveFromNuGet -PackageId "Microsoft.Web.WebView2" -MinimumVersion "1.0.2903.40" -DestinationFolder (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls") -FilesToCopy @("runtimes\win-x64\native\WebView2Loader.dll", "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.Core.dll", "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.WinForms.dll", "lib_manual\net5.0-windows10.0.17763.0\Microsoft.Web.WebView2.Wpf.dll") -Force:$Force.IsPresent

    if ((Get-Module -Name OmadaWeb.PS -ListAvailable | Measure-Object).Count -le 0) {
        "OmadaWeb.PS module not in any PowerShell Module path. The application cannot run without it!" | Write-Warning
    }
    $WebViewInstalled = $false
    (Join-Path $env:ProgramFiles -ChildPath "Microsoft\EdgeWebView"), (Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft\EdgeWebView"), (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime"), (Join-Path $PsscriptRoot -ChildPath "bin\Webview2Runtime") | ForEach-Object {
        if (Test-Path $_) {
            (Get-ChildItem $_ -Filter *.exe -Recurse | Where-Object { $_.Name -eq "msedgewebview2.exe" }) | ForEach-Object {
                "A webview installation found at '{0}'" -f (Split-Path $_) | Write-Verbose
                $WebViewInstalled = $true
            }
        }
    }

    if (!$WebViewInstalled) {
        "Webview2 RunTime does not seem to be present at your system. You can download it from: https://developer.microsoft.com/en-us/microsoft-edge/webview2?form=MA13LH#download-section. When you are not able to install it, you can also add the webview2 binaries in folder {0}" -f (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime") | Write-Warning
    }

    Get-ChildItem $LocalAppDataPath -Recurse | Unblock-File
    Get-ChildItem $RoamingAppDataPath -Recurse | Unblock-File

    "Create shortcuts" | Write-Host
    $WshShell = New-Object -ComObject WScript.Shell
    $PowerShellExecPath = (Get-Command "pwsh.exe").Path
    $OmadaSqlTroubleShooterIcoPath = Join-Path $LocalAppDataPath -ChildPath ("lib\ui\{0}" -f $ScriptName.Replace(".ps1", ".ico"))
    $ShortcutFullPath = Join-Path $WshShell.SpecialFolders("Desktop") -ChildPath ("{0}.lnk" -f $ScriptTitle)
    $RunPath = Join-Path $LocalAppDataPath -ChildPath "Run.ps1"
    "Push-Location '{0}';
    try{{
        Import-Module .\OmadaSqlTroubleshooter.psd1 -Force;
        Invoke-OmadaSqlTroubleshooter;
        Pop-Location;
        'Window will automatically close in 5 seconds!' | Write-Host -ForegroundColor Green;
    }}
    catch {{
        Throw $_
    }}
    finally {{
        Start-Sleep -Seconds 5
    }}" -f $LocalAppDataPath | Set-Content $RunPath -Force -Encoding utf8

    $Arguments = ' -File "{0}"' -f $RunPath

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutFullPath)

    $Shortcut.TargetPath = $PowerShellExecPath
    $Shortcut.WorkingDirectory = $LocalAppDataPath
    $Shortcut.Arguments = $Arguments
    $Shortcut.IconLocation = ("{0},0" -f $OmadaSqlTroubleShooterIcoPath)
    $Shortcut.Save()

    Get-Item -Path $ShortcutFullPath | Copy-Item -Destination $WshShell.SpecialFolders("Programs") -Force

    Pop-Location

    "Application copied to '{0}', config can be found here: '{1}'. Shortcut created on desktop '{2}' and in start-menu '{3}'. To uninstall, just remove the files." -f $LocalAppDataPath, $RoamingAppDataPath, $ShortcutFullPath, $WshShell.SpecialFolders("Programs") | Write-Host -ForegroundColor Green
    "Finished" | Write-Host
}
catch {
    Throw $_
}
finally {
    Pop-Location
}

