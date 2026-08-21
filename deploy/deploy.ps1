#requires -Version 7.0
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'WebViewInstalled', Justification = 'The variable is used, but script analyzer does not recognize it')]
[CmdletBinding(SupportsShouldProcess)]
PARAM(
    [switch]$Force
)
$ErrorActionPreference = "Stop"
try {


    # There used to be a local RetrieveFromNuGet here that pre-seeded the WebView2 assemblies into
    # Bin\Webview2Dlls. It has been removed rather than repaired. It was broken (it passed
    # -MinimumVersion to a function declaring -Version, so the version segment of the URL was empty
    # and nuget.org served whatever was latest), it wrote to a folder the module never reads, and -
    # decisively - it was a second download path with no integrity check, bypassing the SHA-256 gate
    # in Invoke-DownloadFile. The module now downloads and verifies the assemblies itself on first
    # import, against the pin in src\DependencyLock.psd1.

    $DeployScriptRoot = (Get-Item ($MyInvocation.MyCommand.Path | Split-Path )).Parent.FullName
    Push-Location $DeployScriptRoot
    $ScriptRootName = "src"
    [xml]$MainFormXaml = Get-Content (Join-Path $DeployScriptRoot -ChildPath "$ScriptRootName\lib\ui\MainForm.xaml")
    $ScriptName = "OmadaSqlTroubleshooter.ps1"
    $ScriptTitle = $MainFormXaml.Window.Title

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

    # DependencyLock.psd1 must travel with the psm1: the module resolves it through $PSScriptRoot and
    # refuses every download without it.
    @("OmadaSqlTroubleshooter.psm1", "OmadaSqlTroubleshooter.psd1", "DependencyLock.psd1") | ForEach-Object {
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
        Import-Module .\OmadaSqlTroubleshooter.psd1;
        Invoke-OmadaSqlTroubleshooter -NoReconnect;
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

