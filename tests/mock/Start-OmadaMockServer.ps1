#Requires -Version 7.0
<#
.SYNOPSIS
Start the mock Omada instance and serve requests until stopped (Ctrl+C or the process is killed).

.DESCRIPTION
Blocking entry point for the mock server. Serves the fixture store over plain HTTP on a localhost
high port - no admin/URL-ACL needed. Point the app's tenant URL at the printed BaseUrl and use the
mock transport shim (see Launch-AppOnMock.ps1) so no interactive login is attempted.

.EXAMPLE
pwsh -File tests/mock/Start-OmadaMockServer.ps1 -Port 8787

.EXAMPLE
# From another shell, sanity-check an endpoint:
Invoke-RestMethod http://127.0.0.1:8787/odata/dataobjects/C_P_SQLTROUBLESHOOTING
#>
[CmdletBinding()]
param(
    [string]$BindAddress = "127.0.0.1",
    [int]$Port = 8787,
    [string]$FixturesDir
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "OmadaMockRouter.ps1")
. (Join-Path $PSScriptRoot "OmadaMockServer.ps1")

$Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
"Omada mock server listening on http://${BindAddress}:${Port}" | Write-Host -ForegroundColor Green
"  fixtures: $Dir" | Write-Host
"  press Ctrl+C to stop" | Write-Host

$Control = @{ Running = $true; Started = $false; Error = $null }
Invoke-OmadaMockListenerLoop -BindAddress $BindAddress -Port $Port -FixturesDir $Dir -Control $Control
