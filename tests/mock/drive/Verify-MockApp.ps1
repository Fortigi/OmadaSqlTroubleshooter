#Requires -Version 7.0
<#
.SYNOPSIS
Unattended drive script: connects the REAL app to the mock instance and asserts real app state.

.DESCRIPTION
Dot-sourced by MockAppEntry.ps1 (via OMADASQL_MOCK_DRIVE) on the app's dispatcher thread, inside the
module session, after the replay transport shim is installed. It drives the actual UI - raising the
real Connect button's Click event - and asserts on real app state (connection status, the query and
data-connection dropdowns, the schema cache, the results grid), then writes a JSON report to
$env:OMADASQL_MOCK_RESULTS and closes the window.

This is the app-level counterpart to the Pester tests, which only cover the router/server/shim below
the WPF layer.

Do NOT combine with -AutoConnect: this script installs the no-dialog Write-LogOutput override first,
and connecting before that override exists risks a modal MessageBox deadlocking the run.
#>

# --- 1. Neutralize blocking dialogs BEFORE anything can log ----------------------------------------
# The real Write-LogOutput shows a modal MessageBox for ERROR/WARNING/FATAL (unless -SkipDialog),
# which would block this dispatcher thread forever in an unattended run. Record instead of showing.
# Must be "function script:" so it shadows the app function for every caller (same mechanism as
# tests/e2e/OmadaMocks.ps1).
$script:DriveLogMessages = [System.Collections.Generic.List[object]]::new()

function script:Write-LogOutput {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [string]$Message,
        $ErrorObject,
        [ValidateSet("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2")]
        [string]$LogType = "INFO",
        [switch]$SkipDialog
    )
    process {
        $script:DriveLogMessages.Add([PSCustomObject]@{ LogType = $LogType; Message = $Message })
    }
}

function script:Wait-DriveIdle {
    # Pump the dispatcher so queued work (WebView2 callbacks, popup closes) can run while we wait.
    param(
        [int]$Milliseconds = 750
    )
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action] {})
        Start-Sleep -Milliseconds 25
    }
}

$Report = [ordered]@{}
$Elements = $Script:MainForm.Elements

try {
    # --- 2. Connect via the REAL button ------------------------------------------------------------
    $Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    Wait-DriveIdle -Milliseconds 1500

    $Report.Connected = [bool]$Script:ConnectionStatus
    $Report.StatusBarUrl = [string]$Elements.TextBlockStatusBarUrl.Text
    $Report.StatusBarDatabase = [string]$Elements.TextBlockStatusBarDatabaseName.Text

    # Query list (OData C_P_SQLTROUBLESHOOTING?$orderby=...)
    $QueryItems = @($Elements.ComboBoxSelectQuery.Items)
    $Report.QueryCount = $QueryItems.Count
    $Report.QueryFirst = if ($QueryItems.Count -gt 0) { [string]$QueryItems[0].Content } else { $null }

    # Data connections (dataobjdlg.aspx HTML) - the XmlDocument regression lands here: a broken
    # transport yields zero options and no selection.
    $DataConnectionItems = @($Elements.ComboBoxSelectDataConnection.Items)
    $Report.DataConnectionCount = $DataConnectionItems.Count
    $Report.DataConnectionSelected = [string]$Elements.ComboBoxSelectDataConnection.SelectedItem.Content

    # Schema (SyntaxHighlighting.asmx/GetSqlSchema) populates a session cache keyed by pool+DoId.
    $Report.SchemaCacheKeys = if ($null -ne $Script:SqlSchemaCache) { @($Script:SqlSchemaCache.Keys).Count } else { 0 }

    # --- 3. Select a query and execute -------------------------------------------------------------
    # The editor is a REAL WebView2/Monaco here, so this leg is genuinely asynchronous: give it time
    # and record what happened rather than assuming it completed.
    if ($QueryItems.Count -gt 0) {
        $Elements.ComboBoxSelectQuery.SelectedItem = $QueryItems[0]
        Wait-DriveIdle -Milliseconds 3000
        $Report.EditorLoadedQuery = ![string]::IsNullOrWhiteSpace($Script:RunTimeData.CurrentQueryText)

        $Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        Wait-DriveIdle -Milliseconds 5000

        $Rows = @($Elements.DataGridQueryResult.ItemsSource)
        $Report.ResultRowCount = $Rows.Count
        $Report.StatusBarRows = [string]$Elements.TextBlockStatusBarRows.Text
    }

    # --- 4. Surface anything the app complained about ----------------------------------------------
    $Report.ErrorCount = @($script:DriveLogMessages | Where-Object { $_.LogType -in @("ERROR", "FATAL") }).Count
    $Report.WarningCount = @($script:DriveLogMessages | Where-Object { $_.LogType -eq "WARNING" }).Count
    $Report.Problems = @($script:DriveLogMessages |
            Where-Object { $_.LogType -in @("ERROR", "FATAL", "WARNING") } |
            Select-Object -First 15 |
            ForEach-Object { "[{0}] {1}" -f $_.LogType, $_.Message })
    $Report.Completed = $true
}
catch {
    $Report.Completed = $false
    $Report.DriveError = "{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace
}
finally {
    $ResultsPath = $env:OMADASQL_MOCK_RESULTS
    if ([string]::IsNullOrWhiteSpace($ResultsPath)) {
        $ResultsPath = Join-Path ([System.IO.Path]::GetTempPath()) "OmadaMockDriveResults.json"
    }
    $Report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ResultsPath -Encoding UTF8
    New-Item -Path ("{0}.done" -f $ResultsPath) -ItemType File -Force | Out-Null

    try {
        $Script:MainForm.Definition.Close()
    }
    catch {
        # Nothing useful to do if the window is already gone.
    }
}
