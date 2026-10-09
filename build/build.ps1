[CmdLetBinding()]
param(
    [string[]]$Task = 'default',
    [string[]]$BuildVersion = "",
    [switch]$AllowPrerelease
)
$ErrorActionPreference = "Stop"

$ScriptBlockString = @"
    PARAM(
        [string[]]`$Task,
        [string[]]`$BuildVersion,
        [string]`$AllowPrerelease=`'false'
    )
    # The one home of the module list and its pinned versions is BuildModules.psd1; this installs and
    # imports exactly those versions.
    . .\InstallModules.ps1 -Import

    `$Location = Get-Location
    Invoke-psake -buildFile "`$Location\psakeBuild.ps1" -taskList `$Task -Verbose:`$VerbosePreference -parameters @{"BuildVersion" = `$BuildVersion; "AllowPrerelease" = `$AllowPrerelease }
    if (-not `$psake.build_success) { exit 1 }
"@

$TaskParam = ($Task | ForEach-Object { "'$_'" }) -join ','
$Command = "Set-Location '$($PSScriptRoot)'; & {$ScriptBlockString} -Task @($TaskParam) -BuildVersion '$BuildVersion' -AllowPrerelease '$($AllowPrerelease.IsPresent)'"
$Process = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoProfile", "-NoLogo", "-ExecutionPolicy", "Bypass", "-Command", $Command -Wait -NoNewWindow -PassThru
if ($Process.ExitCode -ne 0) {
    throw "Build failed: psake exited with code $($Process.ExitCode). See output above for the failing task."
}
