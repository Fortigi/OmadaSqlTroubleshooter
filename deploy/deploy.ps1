#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
PARAM()
$ErrorActionPreference = "Stop"
try {


    $DeployScriptRoot = (Get-Item ($MyInvocation.MyCommand.Path | Split-Path )).Parent.FullName
    Push-Location $DeployScriptRoot
    $ScriptName = "OmadaSqlTroubleshooter.ps1"
    "Scriptname: {0}" -f $ScriptName | Write-Verbose

    $OmadaTroubleShooterPs1 = Join-Path  (Get-Item $DeployScriptRoot).FullName -ChildPath "src\$ScriptName"
    "OmadaTroubleShooterPath: {0}" -f $OmadaTroubleShooterPs1 | Write-Verbose

    $LocalAppDataPath = Join-Path $env:LOCALAPPDATA -ChildPath $ScriptName.Replace(".ps1", "")
    New-Item $LocalAppDataPath -ItemType Directory -Force | Out-Null
    New-Item (Join-Path $LocalAppDataPath -ChildPath "Bin") -ItemType Directory -Force | Out-Null
    $RoamingAppDataPath = Join-Path $env:APPDATA -ChildPath $ScriptName.Replace(".ps1", "")
    New-Item $RoamingAppDataPath -ItemType Directory -Force | Out-Null


    "Deploy {0} from {1} to {2}" -f $ScriptName, $DeployScriptRoot, $LocalAppDataPath | Write-Host
    Get-Item -Path $OmadaTroubleShooterPs1 | Copy-Item -Destination $LocalAppDataPath -Force
    Get-Item -Path ("{0}.xaml" -f $OmadaTroubleShooterPs1.TrimEnd(".ps1")) | Copy-Item -Destination $LocalAppDataPath -Force
    Get-Item -Path (Join-Path $DeployScriptRoot -ChildPath "src\Monaco") | Copy-Item -Destination $LocalAppDataPath -Force -Recurse
    Get-Item -Path (Join-Path $DeployScriptRoot -ChildPath "src\$($ScriptName.Replace('.ps1','.ico'))") | Copy-Item -Destination $LocalAppDataPath -Force

    #"Get Dll files needed"
    $PackageTempFolder = New-Item (Join-Path $env:TEMP -ChildPath "OmadaTroubleShooter") -ItemType Directory -Force
    $Package = Save-Package Microsoft.Web.WebView2 -MinimumVersion 1.0.2903.40 -Path $PackageTempFolder.FullName
    Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $Package.PackageFilename) | Expand-Archive -DestinationPath $PackageTempFolder.FullName -Force
    Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath "runtimes\win-x64\native\WebView2Loader.dll") | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "Bin")  -Force
    Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.Core.dll") | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "Bin")  -Force
    # Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.WinForms.dll") | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "Bin")  -Force
    Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath "lib_manual\net5.0-windows10.0.17763.0\Microsoft.Web.WebView2.Wpf.dll") | Copy-Item -Destination (Join-Path $LocalAppDataPath -ChildPath "Bin")  -Force
    Get-ChildItem $LocalAppDataPath -Recurse | Unblock-File
    Get-ChildItem $RoamingAppDataPath -Recurse | Unblock-File
    Get-Item $PackageTempFolder.FullName | Remove-Item -Recurse -Force


    $WshShell = New-Object -ComObject WScript.Shell
    $PowerShellExecPath = (Get-Command "pwsh.exe").Path
    $OmadaTroubleShooterPs1Path = Join-Path $LocalAppDataPath -ChildPath $ScriptName
    $OmadaTroubleShooterIcoPath = $OmadaTroubleShooterPs1Path.Replace(".ps1", ".ico")
    $ShortcutFullPath = Join-Path $WshShell.SpecialFolders("Desktop") -ChildPath "$($ScriptName.Replace(".ps1",".lnk"))"
    $OmadaTroubleShooterCommand = "Push-Location {0};{1};Pop-Location" -f $LocalAppDataPath,$OmadaTroubleShooterPs1Path
    $Arguments = " -NonInteractive -WindowStyle Hidden -WorkingDirectory {0} -EncodedCommand {1}" -f $LocalAppDataPath, [convert]::ToBase64String([system.text.encoding]::Unicode.GetBytes($OmadaTroubleShooterCommand))


    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutFullPath)
    $Shortcut.TargetPath = $PowerShellExecPath
    $Shortcut.WorkingDirectory = $LocalAppDataPath
    $Shortcut.Arguments = $Arguments
    $Shortcut.IconLocation = ("{0},0" -f $OmadaTroubleShooterIcoPath)
    $Shortcut.Save()


    Get-Item -Path $ShortcutFullPath | Copy-Item -Destination $WshShell.SpecialFolders("Programs") -Force

    Pop-Location
    "Application copied to '{0}', config can be found here: '{1}'. Shortcut created on desktop and in start-menu." -f $LocalAppDataPath,$RoamingAppDataPath | Write-Host
    "Finished" | Write-Host
}
catch {
    Throw $_
}
finally {
    Pop-Location
}

