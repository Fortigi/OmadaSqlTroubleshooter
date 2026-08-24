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
    if (!(Get-Module -Name Pester -ListAvailable)) { Install-Module -Name Pester -Scope CurrentUser -Force }
    if (!(Get-Module -Name psake -ListAvailable)) { Install-Module -Name psake -Scope CurrentUser -Force }
    if (!(Get-Module -Name PSDeploy -ListAvailable)) { Install-Module -Name PSDeploy -Scope CurrentUser -Force }
    if (!(Get-Module -Name PSScriptAnalyzer -ListAvailable)) { Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force }

    Import-Module -Name Pester -Force
    Import-Module -Name psake -Force
    Import-Module -Name PSDeploy -Force
    Import-Module -Name PSScriptAnalyzer -Force

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
