#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
PARAM(
    [switch]$Force
)
$ErrorActionPreference = "Stop"
try {

    $DeployScriptRoot = (Get-Item ($MyInvocation.MyCommand.Path | Split-Path )).Parent.FullName
    Push-Location $DeployScriptRoot
    [xml]$MainWindowXaml = Get-Content (Join-Path $DeployScriptRoot -ChildPath "src\lib\ui\MainWindow.xaml")
    $ScriptName = "OmadaSqlTroubleshooter.ps1"
    $ScriptTitle = $MainWindowXaml.Window.Title

    $CommitId = "Unknown"
    try {
        $CommitId = git rev-parse HEAD
    }
    catch {}

    "Deploy Scriptname: '{0}'" -f $ScriptName | Write-Verbose

    $OmadaTroubleShooterPs1 = Join-Path  (Get-Item $DeployScriptRoot).FullName -ChildPath "src\$ScriptName"
    "OmadaTroubleShooterPath: '{0}'" -f $OmadaTroubleShooterPs1 | Write-Verbose

    $LocalAppDataPath = Join-Path $env:LOCALAPPDATA -ChildPath $ScriptName.Replace(".ps1", "")
    New-Item $LocalAppDataPath -ItemType Directory -Force | Out-Null
    New-Item (Join-Path $LocalAppDataPath -ChildPath "bin") -ItemType Directory -Force | Out-Null
    $RoamingAppDataPath = Join-Path $env:APPDATA -ChildPath $ScriptName.Replace(".ps1", "")
    New-Item $RoamingAppDataPath -ItemType Directory -Force | Out-Null

    "Deploy '{0}' from '{1}' to '{2}'" -f $ScriptName, $DeployScriptRoot, $LocalAppDataPath | Write-Host

    #Clear existing files in root and lib
    Get-ChildItem -Path $LocalAppDataPath -File | ForEach-Object {
        Get-Item $_ | Remove-Item -Recurse -Force -Confirm:$false
    }
    if (Test-Path (Join-Path $LocalAppDataPath -ChildPath "lib") -PathType Container) {
        Get-ChildItem (Join-Path $LocalAppDataPath -ChildPath "lib") | Remove-Item -Recurse -Force -Confirm:$false
    }
    @("OmadaSqlTroubleshooter.ps1") | ForEach-Object {
        Get-Item -Path (Join-Path $DeployScriptRoot -ChildPath "src\$_") | Copy-Item -Destination $LocalAppDataPath -Force
    }

    Get-Item -Path (Join-Path $DeployScriptRoot -ChildPath "src\Monaco") | Copy-Item -Destination $LocalAppDataPath -Force -Recurse
    New-Item (Join-Path $LocalAppDataPath -ChildPath  "lib\ui") -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path (Join-Path $DeployScriptRoot -ChildPath "src\lib\ui") -Filter *.xaml | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "lib\ui") -Force -Recurse
    Get-ChildItem -Path (Join-Path $DeployScriptRoot -ChildPath "src\lib\ui") -Filter *.ico | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "lib\ui") -Force -Recurse

    @("functions", "events") | ForEach-Object {
        $LibSource = $_
        $SourceChildPath = "src\lib\{0}" -f $LibSource
        $TargetChildPath = "lib\{0}" -f $LibSource
        $TargetFilePath = "{0}\{1}.ps1" -f $TargetChildPath, $LibSource
        New-Item (Join-Path $LocalAppDataPath -ChildPath $TargetChildPath) -ItemType Directory -Force | Out-Null
        "#Source file: {0}, Deployed at {1}, Git commit id: {2}`r`n`r`n" -f $LibSource, (Get-Date).ToString("o"), $CommitId | Out-File -Path (Join-Path $LocalAppDataPath -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        Get-ChildItem -Path (Join-Path $DeployScriptRoot -ChildPath $SourceChildPath) | ForEach-Object {
            Get-Content $_ | Out-File -Path (Join-Path $LocalAppDataPath -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        }
    }

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
        $PackageTempFolder = New-Item (Join-Path $env:TEMP -ChildPath "OmadaTroubleShooter") -ItemType Directory -Force
        $Package = Save-Package Microsoft.Web.WebView2 -MinimumVersion 1.0.2903.40 -Path $PackageTempFolder.FullName
        Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $Package.PackageFilename) | Expand-Archive -DestinationPath $PackageTempFolder.FullName -Force

        New-Item (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls") -ItemType Directory -Force | Out-Null
        foreach ($File in $FilesToCopy) {
            Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $File) | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls")  -Force
        }
        Get-Item $PackageTempFolder.FullName | Remove-Item -Recurse -Force
    }
    else {
        "WebView2 Dll files already present at '{0}'. Do download again use Deploy.ps1 -Force" -f (Join-Path $LocalAppDataPath -ChildPath "Bin\Webview2Dlls") | Write-Host
    }

    if ((Get-Module -Name OmadaWeb.PS -ListAvailable | Measure-Object).Count -le 0) {
        "OmadaWeb.PS module not in any PowerShell Module path. The application cannot run without it!" | Write-Warning
    }
    $WebViewInstalled = $false
    (Join-Path $env:ProgramFiles -ChildPath "Micorosft\EdgeWebView"), (Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft\EdgeWebView") | ForEach-Object {
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
    $OmadaTroubleShooterPs1Path = Join-Path $LocalAppDataPath -ChildPath $ScriptName
    $OmadaTroubleShooterIcoPath = Join-Path $LocalAppDataPath -ChildPath ("lib\ui\{0}" -f $ScriptName.Replace(".ps1", ".ico"))
    $ShortcutFullPath = Join-Path $WshShell.SpecialFolders("Desktop") -ChildPath ("{0}.lnk" -f $ScriptTitle)
    $OmadaTroubleShooterCommand = 'Push-Location {0};{1};Pop-Location;"Window will automatically close in 5 seconds!"|Write-Host -ForegroundColor Green;Start-Sleep -Seconds 5' -f $LocalAppDataPath, $OmadaTroubleShooterPs1Path
    $Arguments = "  -WorkingDirectory {0} -EncodedCommand {1}" -f $LocalAppDataPath, [convert]::ToBase64String([system.text.encoding]::Unicode.GetBytes($OmadaTroubleShooterCommand))

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutFullPath)

    $Shortcut.TargetPath = $PowerShellExecPath
    $Shortcut.WorkingDirectory = $LocalAppDataPath
    $Shortcut.Arguments = $Arguments
    $Shortcut.IconLocation = ("{0},0" -f $OmadaTroubleShooterIcoPath)
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

