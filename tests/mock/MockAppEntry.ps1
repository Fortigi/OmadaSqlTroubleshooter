#Requires -Version 7.0
<#
.SYNOPSIS
In-app entry for the mock instance. Dot-sourced by Invoke-OmadaSqlTroubleshooter's OMADASQL_MOCK_SCRIPT
hook once the window is idle, so it runs on the dispatcher thread inside the module session.

.DESCRIPTION
Reads its configuration from environment variables (set by Launch-AppOnMock.ps1) and installs the
right seam:

  Replay mode (default): install the transport shim (Install-OmadaMockTransport) so every Omada call
  goes to the local mock server; point the tab's URL + BaseUrl at the mock; select a non-interactive
  auth option. Optionally auto-connect, then optionally dot-source a drive script (used unattended,
  e.g. by the future README-screenshot feature).

  Record mode (OMADASQL_MOCK_RECORD=1): install the recorder (Install-OmadaMockRecorder) which calls
  the REAL OmadaWeb.PS and tees scrubbed responses to the fixture store. BaseUrl/auth are left alone -
  you connect to your real tenant and drive the flows you want captured.

Environment contract:
  OMADASQL_MOCK_BASEURL     mock server base url, e.g. http://127.0.0.1:8787 (replay)
  OMADASQL_MOCK_FIXTURES    fixtures directory (optional; defaults to ./fixtures)
  OMADASQL_MOCK_RECORD      "1" => record mode
  OMADASQL_MOCK_AUTOCONNECT "1" => click Connect after setup (replay)
  OMADASQL_MOCK_DRIVE       optional path to a drive script dot-sourced after setup (replay)
#>

function Assert-OmadaMockShimInstalled {
    # Fail loudly if the script:-scoped Invoke-OmadaRestMethod override did not actually shadow the
    # OmadaWeb.PS command - otherwise real auth/HTTP would fire silently.
    param([string]$Marker)
    $Cmd = Get-Command Invoke-OmadaRestMethod -ErrorAction SilentlyContinue
    $Body = if ($null -ne $Cmd -and $Cmd.CommandType -eq "Function") { $Cmd.ScriptBlock.ToString() } else { "" }
    if ($Body -notmatch $Marker) {
        throw "Mock shim not installed: Invoke-OmadaRestMethod is not the mock override (module-scope shadowing failed)."
    }
}

$MockToolDir = $PSScriptRoot
$MockFixtures = $env:OMADASQL_MOCK_FIXTURES
$MockBaseUrl = $env:OMADASQL_MOCK_BASEURL

try {
    . (Join-Path $MockToolDir "OmadaMockRouter.ps1")

    if ($env:OMADASQL_MOCK_RECORD -eq "1") {
        # ---- Record mode: capture real responses into fixtures --------------------------------------
        . (Join-Path $MockToolDir "Sanitize-OmadaFixture.ps1")
        . (Join-Path $MockToolDir "Install-OmadaMockRecorder.ps1")
        Install-OmadaMockRecorder -FixturesDir $MockFixtures
        Assert-OmadaMockShimInstalled -Marker "OMADA_MOCK_RECORDER_MARKER"
        "Mock RECORD mode active. Connect to your real tenant and drive the flows to capture." | Write-Host -ForegroundColor Green
        return
    }

    # ---- Replay mode: talk to the local mock server ------------------------------------------------
    . (Join-Path $MockToolDir "Install-OmadaMockTransport.ps1")
    Install-OmadaMockTransport -MockBaseUrl $MockBaseUrl
    Assert-OmadaMockShimInstalled -Marker "OMADA_MOCK_TRANSPORT_MARKER"

    $Elements = $Script:MainForm.Elements

    # Point the active tab at the mock. Set BOTH the textbox and BaseUrl: Get-SqlQueryObject re-derives
    # BaseUrl from TextBoxURL.Text on every fetch, so the textbox must hold the mock URL too.
    $Elements.TextBoxURL.Text = $MockBaseUrl
    $MockBaseUrl | Set-ConfigProperty -Property "BaseUrl"

    # Any auth option works (the shim bypasses auth entirely); pick a non-credential one.
    $AuthItem = $Elements.ComboBoxSelectAuthenticationOption.Items | Where-Object { $_.Content -eq "WebView2" } | Select-Object -First 1
    if ($null -eq $AuthItem) {
        $AuthItem = $Elements.ComboBoxSelectAuthenticationOption.Items | Select-Object -First 1
    }
    if ($null -ne $AuthItem) { $Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $AuthItem }

    "Mock REPLAY mode active against $MockBaseUrl." | Write-Host -ForegroundColor Green

    if ($env:OMADASQL_MOCK_AUTOCONNECT -eq "1") {
        "Auto-connecting to mock..." | Write-Host
        $Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    }

    if (![string]::IsNullOrWhiteSpace($env:OMADASQL_MOCK_DRIVE) -and (Test-Path -LiteralPath $env:OMADASQL_MOCK_DRIVE)) {
        "Running mock drive script: $env:OMADASQL_MOCK_DRIVE" | Write-Host
        . $env:OMADASQL_MOCK_DRIVE
    }
}
catch {
    "MockAppEntry failed: {0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace | Write-Host -ForegroundColor Red
}
