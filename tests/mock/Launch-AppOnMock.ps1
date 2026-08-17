#Requires -Version 7.0
<#
.SYNOPSIS
Launch the real OmadaSqlTroubleshooter app against the local mock Omada instance - no live tenant.

.DESCRIPTION
Replay mode (default): starts the mock server, then launches the app (STA) with the OMADASQL_MOCK_SCRIPT
hook pointed at MockAppEntry.ps1, so the app connects to the mock with no interactive login. Use it to
click around by hand (-Interactive, the default) or to run unattended (-DriveScript ... to drive and
close, e.g. for the future README-screenshot feature).

Record mode (-Record): does NOT start the mock server. Launches the app so you connect to your REAL
tenant; every response is captured (scrubbed) into the fixture store. Drive the flows you want, then
close the app and review the fixtures/ diff.

Config is redirected to a throwaway temp folder (via the existing OMADASQL_E2E_APPDATA redirect) so your
real %APPDATA%\OmadaSqlTroubleshooter is never touched.

.EXAMPLE
pwsh -File tests/mock/Launch-AppOnMock.ps1                 # interactive, app on the mock
.EXAMPLE
pwsh -File tests/mock/Launch-AppOnMock.ps1 -AutoConnect    # connect automatically on launch
.EXAMPLE
pwsh -File tests/mock/Launch-AppOnMock.ps1 -Record         # capture fixtures from your real tenant
#>
[CmdletBinding()]
param(
    [string]$BindAddress = "127.0.0.1",
    [int]$Port = 8787,
    [string]$FixturesDir,
    [switch]$Record,
    [switch]$AutoConnect,
    [string]$DriveScript,
    [string]$ResultsPath,
    # Guard against an unattended run hanging forever (a modal dialog, a WebView2 stall). 0 means
    # wait indefinitely, which is what you want for interactive use; a drive script defaults to 180s.
    [int]$TimeoutSeconds = 0,
    [string]$ModulePath,
    [ValidateSet("INFO", "DEBUG", "VERBOSE", "WARNING", "ERROR", "FATAL", "VERBOSE2")]
    [string]$LogLevel = "WARNING"
)

$ErrorActionPreference = "Stop"

$MockDir = $PSScriptRoot
$RepoRoot = Resolve-Path (Join-Path $MockDir "..\..")
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    # Casing matters: the manifest on disk is OmadaSqlTroubleshooter.psd1 (lowercase "s" in
    # "shooter"), unlike the .psm1 next to it. Getting it wrong only breaks on a case-sensitive
    # filesystem, so it survives local Windows testing.
    $ModulePath = Join-Path $RepoRoot "src\OmadaSqlTroubleshooter.psd1"
}
if ([string]::IsNullOrWhiteSpace($FixturesDir)) {
    $FixturesDir = Join-Path $MockDir "fixtures"
}
$MockBaseUrl = "http://${BindAddress}:${Port}"
$MockEntry = Join-Path $MockDir "MockAppEntry.ps1"

# Throwaway config dir so the mock run never touches the user's real settings/saved tabs.
$TempAppData = Join-Path ([System.IO.Path]::GetTempPath()) ("osqMock_{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -Path $TempAppData -ItemType Directory -Force | Out-Null

$ServerProcess = $null
try {
    # --- Start the mock server (replay only) --------------------------------------------------------
    if (-not $Record) {
        "Starting mock server on $MockBaseUrl ..." | Write-Host -ForegroundColor Cyan
        $ServerInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ServerInfo.FileName = "pwsh"
        $ServerInfo.Arguments = "-NoProfile -NonInteractive -File `"$(Join-Path $MockDir 'Start-OmadaMockServer.ps1')`" -BindAddress $BindAddress -Port $Port -FixturesDir `"$FixturesDir`""
        $ServerInfo.UseShellExecute = $false
        $ServerProcess = [System.Diagnostics.Process]::Start($ServerInfo)

        # Wait until the server answers the probe endpoint.
        $Ready = $false
        $Deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $Ready -and [DateTime]::UtcNow -lt $Deadline) {
            try {
                Invoke-RestMethod -Uri "$MockBaseUrl/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -NoProxy -TimeoutSec 2 | Out-Null
                $Ready = $true
            }
            catch { Start-Sleep -Milliseconds 200 }
        }
        if (-not $Ready) { throw "Mock server did not become ready on $MockBaseUrl." }
        "Mock server ready." | Write-Host -ForegroundColor Green
    }

    # --- Launch the app (STA) with the mock hook ----------------------------------------------------
    $AppArgs = "-Reset -NoReconnect -LogLevel $LogLevel"
    $Command = "Import-Module '$ModulePath' -Force; Invoke-OmadaSqlTroubleshooter $AppArgs"

    $AppInfo = New-Object System.Diagnostics.ProcessStartInfo
    $AppInfo.FileName = "pwsh"
    $AppInfo.Arguments = "-STA -NoProfile -Command `"$Command`""
    $AppInfo.UseShellExecute = $false
    $AppInfo.EnvironmentVariables["OMADASQL_E2E_APPDATA"] = $TempAppData
    $AppInfo.EnvironmentVariables["OMADASQL_MOCK_SCRIPT"] = $MockEntry
    $AppInfo.EnvironmentVariables["OMADASQL_MOCK_FIXTURES"] = $FixturesDir
    if ($Record) {
        $AppInfo.EnvironmentVariables["OMADASQL_MOCK_RECORD"] = "1"
        "RECORD mode: connect the app to your REAL tenant and drive the flows to capture." | Write-Host -ForegroundColor Yellow
    }
    else {
        $AppInfo.EnvironmentVariables["OMADASQL_MOCK_BASEURL"] = $MockBaseUrl
        if ($AutoConnect) { $AppInfo.EnvironmentVariables["OMADASQL_MOCK_AUTOCONNECT"] = "1" }
        if (![string]::IsNullOrWhiteSpace($DriveScript)) {
            $AppInfo.EnvironmentVariables["OMADASQL_MOCK_DRIVE"] = (Resolve-Path -LiteralPath $DriveScript).Path
            if ($TimeoutSeconds -le 0) { $TimeoutSeconds = 180 }
            if ([string]::IsNullOrWhiteSpace($ResultsPath)) {
                $ResultsPath = Join-Path $RepoRoot "buildoutput\MockAppDriveResults.json"
            }
            $ResultsDir = Split-Path -Path $ResultsPath -Parent
            if (![string]::IsNullOrWhiteSpace($ResultsDir) -and -not (Test-Path $ResultsDir)) {
                New-Item -Path $ResultsDir -ItemType Directory -Force | Out-Null
            }
            Remove-Item -Path $ResultsPath, ("{0}.done" -f $ResultsPath) -ErrorAction Ignore
            $AppInfo.EnvironmentVariables["OMADASQL_MOCK_RESULTS"] = $ResultsPath
            "  results : $ResultsPath" | Write-Host
        }
    }

    "Launching app..." | Write-Host -ForegroundColor Cyan
    $AppProcess = [System.Diagnostics.Process]::Start($AppInfo)

    if ($TimeoutSeconds -gt 0) {
        if (-not $AppProcess.WaitForExit($TimeoutSeconds * 1000)) {
            try { $AppProcess.Kill($true) } catch { }
            throw "App run timed out after $TimeoutSeconds seconds (window never closed - a modal dialog or a stalled WebView2 will do this)."
        }
    }
    else {
        $AppProcess.WaitForExit()
    }
    "App closed (exit code $($AppProcess.ExitCode))." | Write-Host

    if (![string]::IsNullOrWhiteSpace($ResultsPath) -and (Test-Path -LiteralPath $ResultsPath)) {
        "--- drive report ---" | Write-Host -ForegroundColor Cyan
        Get-Content -LiteralPath $ResultsPath -Raw | Write-Host
    }
}
finally {
    if ($null -ne $ServerProcess -and -not $ServerProcess.HasExited) {
        try { $ServerProcess.Kill($true) } catch { }
    }
    Remove-Item -Path $TempAppData -Recurse -Force -ErrorAction Ignore
}
