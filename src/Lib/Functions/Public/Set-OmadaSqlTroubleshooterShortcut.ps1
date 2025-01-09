<#
.SYNOPSIS
Creates a shortcut for the Omada SQL Troubleshooter application.

.DESCRIPTION
The `Set-OmadaSqlTroubleShooterShortcut` function creates a shortcut for the Omada SQL Troubleshooter application in the Start Menu and optionally on the Desktop.

.PARAMETER NotCreateDesktopShortcut
If specified, the function will not create a desktop shortcut.

.EXAMPLE
Set-OmadaSqlTroubleShooterShortcut

Creates a shortcut for the Omada SQL Troubleshooter application in the Start Menu and on the Desktop.

.EXAMPLE
Set-OmadaSqlTroubleShooterShortcut -NotCreateDesktopShortcut

Creates a shortcut for the Omada SQL Troubleshooter application in the Start Menu only.

.NOTES
Requires PowerShell 7.0 or higher.

#>

function Set-OmadaSqlTroubleShooterShortcut {
    [CmdletBinding()]
    PARAM(
        [switch]$NotCreateDesktopShortcut
    )
    #$ScriptName = "OmadaSqlTroubleshooter.ps1"
    "Create Start Menu shortcut" | Write-Host
    $LocalAppDataPath = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath "OmadaSqlTroubleShooter"
    if (-not (Test-Path -Path $LocalAppDataPath)) {
        New-Item -Path $LocalAppDataPath -ItemType Directory -Force | Out-Null
    }
    $ModuleInfo = Get-Module OmadaSqlTroubleShooter
    $ModulePath = Split-Path -Path $ModuleInfo.Path -Parent
    [xml]$MainWindowXaml = Get-Content (Join-Path $ModulePath -ChildPath "lib\ui\MainWindow.xaml")
    $ScriptTitle = $MainWindowXaml.Window.Title

    $WshShell = New-Object -ComObject WScript.Shell
    $PowerShellExecPath = (Get-Command "pwsh.exe").Path
    $OmadaSqlTroubleShooterIcoPath = Join-Path $ModulePath -ChildPath "lib\ui\OmadaSqlTroubleShooter.ico"
    $ShortcutFullPath = Join-Path $WshShell.SpecialFolders("Programs") -ChildPath ("{0}.lnk" -f $ScriptTitle)
    $RunPath = Join-Path $LocalAppDataPath -ChildPath "Run.ps1"
    "Push-Location '{0}';
Import-Module -Name 'OmadaSqlTroubleShooter';
Invoke-OmadaSqlTroubleshooter;
Pop-Location;
'Window will automatically close in 5 seconds!' | Write-Host -ForegroundColor Green;
Start-Sleep -Seconds 5" -f $LocalAppDataPath | Set-Content $RunPath -Force -Encoding utf8
    $Arguments = ' -File "{0}"' -f $RunPath

    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutFullPath)
    $Shortcut.TargetPath = $PowerShellExecPath
    $Shortcut.WorkingDirectory = $LocalAppDataPath
    $Shortcut.Arguments = $Arguments
    $Shortcut.IconLocation = ("{0},0" -f $OmadaSqlTroubleShooterIcoPath)
    $Shortcut.Save()

    if ($NotCreateDesktopShortcut) {
        "Desktop shortcut not created" | Write-Host
    }
    else {
        Get-Item -Path $ShortcutFullPath | Copy-Item -Destination $WshShell.SpecialFolders("Desktop") -Force
        "Created desktop shortcut. Use parameter -NotCreateDesktopShortcut to skip this part." | Write-Host
    }
}

