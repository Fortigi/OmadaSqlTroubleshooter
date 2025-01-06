function Test-Shortcut {
    $LocalAppDataPath = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath "OmadaSqlTroubleShooter"
    if (-not (Test-Path -Path $LocalAppDataPath)) {
        New-Item -Path $LocalAppDataPath -ItemType Directory -Force | Out-Null
    }
    $PsCallStack = Get-PSCallStack | Where-Object { $_.ScriptName -like "*OmadaSqlTroubleShooter.psm1" }

    $ModulePath = Split-Path -Path $PsCallStack.ScriptName -Parent
    [xml]$MainWindowXaml = Get-Content (Join-Path $ModulePath -ChildPath "lib\ui\MainWindow.xaml")
    $ScriptTitle = $MainWindowXaml.Window.Title
    $WshShell = New-Object -ComObject WScript.Shell
    $ShortcutFullPath = Join-Path $WshShell.SpecialFolders("Programs") -ChildPath ("{0}.lnk" -f $ScriptTitle)

    $RunPath = Join-Path $LocalAppDataPath -ChildPath "Run.ps1"

    if (-not (Test-Path $ShortcutFullPath -PathType Leaf) ) {
        "Start Menu shortcut for this application is not present. Run Set-OmadaSqlTroubleshooterShortcut to create a Start Menu shortcut" | Write-Warning
    }
    else {
        if (-not (Test-Path $RunPath -PathType Leaf) ) {
            "Run.ps1. Start Menu shortcut will not work. Run Set-OmadaSqlTroubleshooterShortcut to fix the shortcut(s)." | Write-Error
        }
    }
}
