#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
PARAM(
    [switch]$Force
)
$ErrorActionPreference = "Stop"
try {

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

    New-Item (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls") -ItemType Directory -Force | Out-Null
    $FilesToCopy = @(
        "runtimes\win-x64\native\WebView2Loader.dll",
        "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.Core.dll",
        "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.WinForms.dll",
        "lib_manual\net5.0-windows10.0.17763.0\Microsoft.Web.WebView2.Wpf.dll"
    )
    $DownLoadFiles = $false
    foreach ($File in $FilesToCopy) {
        $File = "bin\Webview2Dlls\{0}" -f $File.Split("\")[-1]
        if (!(Test-Path (Join-Path $LocalAppDataPath -ChildPath $File) -PathType Leaf)) {
            $DownLoadFiles = $true
        }
    }

    New-Item (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime") -ItemType Directory -Force | Out-Null

    if ($DownLoadFiles -or $Force) {
        if ($null -eq (Get-PackageSource | Where-Object { $_.Name -eq "NuGet" })) {
            "Package source 'NuGet' not found. You can retry after registering it using this command: 'Register-PackageSource -Name NuGet -Location `"https://api.NuGet.org/v3/index.json`" -ProviderName NuGet'" | Write-Host
            break
        }

        "Get WebView2 from NuGet (this might take a minute or two to complete)" | Write-Host
        $PackageTempFolder = New-Item (Join-Path $env:TEMP -ChildPath "OmadaSqlTroubleShooter") -ItemType Directory -Force
        $WebView2DllsDownloaded = $false
        try {
            $Package = Save-Package Microsoft.Web.WebView2 -MinimumVersion 1.0.2903.40 -Path $PackageTempFolder.FullName
            $WebView2DllsDownloaded = $true
        }
        catch {
            "Failed to download WebView2 Dll files from NuGet. Please get the latest release from https://www.nuget.org/packages/microsoft.web.webview2. The following files need to be copied to '{0}': {1}. Error: {2}" -f (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls"), $FilesToCopy, $_.Exception.Message | Write-Warning
            $WebView2DllsDownloaded
        }
        if ($WebView2DllsDownloaded) {
            Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $Package.PackageFilename) | Expand-Archive -DestinationPath $PackageTempFolder.FullName -Force

            foreach ($File in $FilesToCopy) {
                Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $File) | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls")  -Force
            }
            Get-Item $PackageTempFolder.FullName | Remove-Item -Recurse -Force
        }
    }
    else {
        "WebView2 Dll files already present at '{0}'. Do download again use Deploy.ps1 -Force" -f (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls") | Write-Host
    }

    if ((Get-Module -Name OmadaWeb.PS -ListAvailable | Measure-Object).Count -le 0) {
        "OmadaWeb.PS module not in any PowerShell Module path. The application cannot run without it!" | Write-Warning
    }
    $WebViewInstalled = $false
    (Join-Path $env:ProgramFiles -ChildPath "Microsoft\EdgeWebView"), (Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft\EdgeWebView") | ForEach-Object {
        if (Test-Path $_) {
            (Get-ChildItem $_ -Filter *.exe -Recurse | Where-Object { $_.Name -eq "msedgewebview2.exe" }) | ForEach-Object {
                "A webview installation found at '{0}'" -f (Split-Path $_) | Write-Host
                $WebViewInstalled = $true
            }
        }
    }
    if (!$WebViewInstalled -and !(Test-Path (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\.downloadWebViewRunTime") -PathType Leaf) -and !(Test-Path (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\msedgewebview2.exe") -PathType Leaf)) {
        $Message = "Copy Webview2 RunTime files here because the Webview2 RunTime does not seem to be present at your system. You can download it from: https://developer.microsoft.com/en-us/microsoft-edge/webview2?form=MA13LH#download-section" | Write-Warning
        $Message | Out-File (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\.downloadWebViewRunTime") -Force -Encoding utf8
    }
    else { try { Get-Item (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\.downloadWebViewRunTime") | Remove-Item -Force -Confirm:$false }catch {} }

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

