#Requires -Version 7.0
<#
.SYNOPSIS
Runs the OmadaSqlTroubleshooter end-to-end suite: launches the REAL app against a fully mocked Omada
backend in a hidden STA pwsh process, drives every scenario unattended, and reports pass/fail.

.DESCRIPTION
No manual interaction, no real Omada server, no interactive login. The app self-drives via the
env-gated automation hook in Invoke-OmadaSqlTroubleshooter. Config is redirected to a throwaway temp
folder so the real %APPDATA%\OmadaSqlTroubleshooter is never touched. Exit code is non-zero if any
scenario fails or the app hangs.
#>
[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

$E2ERoot = Split-Path -Path $PSCommandPath -Parent
$RepoRoot = Resolve-Path (Join-Path $E2ERoot "..\..")
# Casing matters: the manifest on disk is OmadaSqlTroubleshooter.psd1 (lowercase "s" in "shooter"),
# unlike the OmadaSqlTroubleShooter.psm1 beside it. The wrong casing only breaks on a case-sensitive
# filesystem, so it survives local Windows runs.
$ModulePath = Join-Path $RepoRoot "src\OmadaSqlTroubleshooter.psd1"
$BuildOutput = Join-Path $RepoRoot "buildoutput"
$ResultsPath = Join-Path $BuildOutput "E2EResults.xml"
$SentinelPath = "{0}.done" -f $ResultsPath
$AutomationScript = Join-Path $E2ERoot "Automation.Entry.ps1"

if (-not (Test-Path $BuildOutput)) {
    New-Item -Path $BuildOutput -ItemType Directory -Force | Out-Null
}
Remove-Item -Path $ResultsPath, $SentinelPath -ErrorAction Ignore

# Throwaway config dir so the run never touches the user's real settings/saved tabs.
$TempAppData = Join-Path ([System.IO.Path]::GetTempPath()) ("osqE2E_{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -Path $TempAppData -ItemType Directory -Force | Out-Null

$RealAppData = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)) "OmadaSqlTroubleshooter"
$RealAppDataBefore = if (Test-Path $RealAppData) { (Get-Item $RealAppData).LastWriteTimeUtc } else { $null }

$Command = "Import-Module '$ModulePath' -Force; Invoke-OmadaSqlTroubleshooter -Reset -NoReconnect -LogLevel ERROR"

"Launching E2E app run (STA, hidden)..." | Write-Host -ForegroundColor Cyan
"  module    : $ModulePath" | Write-Host
"  appdata   : $TempAppData" | Write-Host
"  results   : $ResultsPath" | Write-Host

$Process = $null
try {
    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = "pwsh"
    $ProcessInfo.Arguments = "-STA -NoProfile -NonInteractive -Command `"$Command`""
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.CreateNoWindow = $true
    $ProcessInfo.EnvironmentVariables["OMADASQL_E2E_APPDATA"] = $TempAppData
    $ProcessInfo.EnvironmentVariables["OMADASQL_E2E_SCRIPT"] = $AutomationScript
    $ProcessInfo.EnvironmentVariables["OMADASQL_E2E_RESULTS"] = $ResultsPath

    $Process = [System.Diagnostics.Process]::Start($ProcessInfo)
    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $Process.Kill($true) } catch { }
        throw "E2E run timed out after $TimeoutSeconds seconds (app hung)."
    }
}
finally {
    Remove-Item -Path $TempAppData -Recurse -Force -ErrorAction Ignore
}

# Isolation guard: the real config folder must be untouched.
$RealAppDataAfter = if (Test-Path $RealAppData) { (Get-Item $RealAppData).LastWriteTimeUtc } else { $null }
if ($RealAppDataBefore -ne $RealAppDataAfter) {
    throw "E2E isolation breach: real %APPDATA%\OmadaSqlTroubleshooter was modified during the run."
}

if (-not (Test-Path $SentinelPath)) {
    throw "E2E produced no completion sentinel - the automation did not finish (see app output above)."
}

[xml]$Report = Get-Content -Path $ResultsPath -Raw
$Total = [int]$Report.testsuites.tests
$Failures = [int]$Report.testsuites.failures

"" | Write-Host
"E2E result: {0} test(s), {1} failure(s). Report: {2}" -f $Total, $Failures, $ResultsPath | Write-Host -ForegroundColor $(if ($Failures -gt 0) { "Red" } else { "Green" })

if ($Failures -gt 0) {
    foreach ($Case in $Report.SelectNodes("//testcase[failure]")) {
        "  FAIL: {0} -- {1}" -f $Case.name, $Case.failure.message | Write-Host -ForegroundColor Red
    }
    exit 1
}
exit 0
