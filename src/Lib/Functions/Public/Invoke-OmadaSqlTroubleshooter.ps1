#requires -Modules @{ ModuleName="OmadaWeb.PS"; ModuleVersion="2026.07.09.9" }
#requires -Version 7.0

<#
.SYNOPSIS
Starts the Omada SQL Troubleshooter application.

.DESCRIPTION
The `Invoke-OmadaSqlTroubleshooter` function initializes and starts the Omada SQL Troubleshooter application.
This application is used to manage and execute SQL queries stored in the SQL Troubleshooting section in Omada Identity Suite.

.PARAMETER LogLevel
Specifies the log level for the application. Acceptable values are INFO, DEBUG, VERBOSE, WARNING, ERROR, FATAL and VERBOSE2.

.PARAMETER Reset
Resets the stored configuration to default.

.PARAMETER LogToConsole
Outputs logging to the console.

.PARAMETER UseWebView2Auth
Uses the WebView2 for browser-based authentication.

.PARAMETER NoReconnect
Prevents the application from attempting to reconnect to the Omada Identity Suite using the stored connection information.

.EXAMPLE
Invoke-OmadaSqlTroubleshooter

Starts the Omada SQL Troubleshooter application with default settings.

.EXAMPLE
Invoke-OmadaSqlTroubleshooter -LogLevel DEBUG -LogToConsole

Starts the Omada SQL Troubleshooter application with log level set to DEBUG and logs output to the console.

.EXAMPLE
Invoke-OmadaSqlTroubleshooter -Reset

Resets the stored configuration to default and starts the Omada SQL Troubleshooter application.

.NOTES
Requires PowerShell 7.0 or higher and the OmadaWeb.PS module.

#>

function Invoke-OmadaSqlTroubleshooter {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'StartVariables', Justification = 'The CurrentProperties variable is used in a function called from here')]
    param(
        [ValidateSet("INFO", "DEBUG", "VERBOSE", "WARNING", "ERROR", "FATAL", "VERBOSE2")]
        [string]$LogLevel,
        [switch]$Reset,
        [switch]$LogToConsole,
        [switch]$UseWebView2Auth,
        [switch]$NoReconnect
    )
    $Error.Clear()
    #region Initialize
    $StartVariables = Get-Variable
    $ApplicationName = "OmadaSqlTroubleshooter"
    $Script:RunTimeConfig = @{
        ApplicationName    = $ApplicationName
        ApplicationVersion = $Script:ModuleVersion
        ScriptName         = "OmadaSqlTroubleshooter"
        ApplicationTitle   = ""
        ModuleFolder       = Split-Path (Get-Module OmadaSqlTroubleShooter).Path
        AppDataFolder      = if (![string]::IsNullOrWhiteSpace($env:OMADASQL_E2E_APPDATA)) { $env:OMADASQL_E2E_APPDATA } else { Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)) -ChildPath $ApplicationName }
        Logging            = [PSCustomObject]@{
            LogToConsole        = $LogToConsole.IsPresent -or $false
            LogLevel            = $null
            VerboseParameterSet = $PSCmdlet.MyInvocation.BoundParameters.Keys.Contains("Verbose")
            LogLevelSetting     = $(if ([string]::IsNullOrWhiteSpace($LogLevel)) { "WARNING" } else { $LogLevel })
            AppLogObject        = [System.Collections.ObjectModel.ObservableCollection[string]]::new()
        }
        StopWatch          = $null
        LastFormMeasured = Get-Date
        ConfigFile         = [PSCustomObject]@{
            Path = $null
            Name = $null
        }
        AuthenticationSet  = $false
        OutputFileName     = $null
        UseWebView2Auth    = $UseWebView2Auth.IsPresent -or $false
        ReconnectStatus    = 0
        SavePassword       = $false
        InstanceGuid       = $(([System.Guid]::NewGuid()).ToString('N'))
        ResetRequested     = $Reset.IsPresent -or $false
        NoReconnect        = $NoReconnect.IsPresent -or $false
    }

    Initialize-OmadaSqlTroubleShooter

    # Snapshot the raw legacy (pre-tabs) config file, if any, before Initialize-GlobalConfigSettings
    # reconciles the same file against the new, trimmed global-only schema - that reconciliation
    # strips now-obsolete tab-scope properties (BaseUrl, CurrentSqlQuery, etc.) and immediately
    # rewrites the file, so this is the one chance to read them for the one-time tab migration in
    # Restore-TabSessions.
    # -Reset means "start completely clean": skip the one-time legacy migration entirely so a
    # stale pre-tabs config can never seed a restored tab (Restore-TabSessions also drops the
    # persisted tabs store and suppresses the reconnect prompt when ResetRequested is set).
    $Script:LegacyConfigForMigration = $null
    if (-not $Reset -and (Test-Path $Script:RunTimeConfig.ConfigFile.Path -PathType Leaf)) {
        try {
            $RawLegacyConfig = Get-Content $Script:RunTimeConfig.ConfigFile.Path -Raw | ConvertFrom-Json
            if ($RawLegacyConfig.PSObject.Properties.Match("BaseUrl").Count -gt 0 -and ![string]::IsNullOrWhiteSpace($RawLegacyConfig.BaseUrl)) {
                $Script:LegacyConfigForMigration = $RawLegacyConfig
            }
        }
        catch {
            "Failed to read legacy config for migration: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
        }
    }
    #endregion

    #region wpf
    $null  = Open-SplashScreenForm
    "Loading Main Form Object" | Write-LogOutput -LogType DEBUG
    $Script:MainForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\MainForm.xaml") -AppendVersion

    $Script:RunTimeConfig.ApplicationTitle = $Script:MainForm.Definition.Title.ToString()

    # Global safety net: without this, any exception that reaches the dispatcher's message loop
    # unhandled - from a WPF event handler, a Task continuation marshaled via Dispatcher.Invoke/
    # BeginInvoke, or PowerShell's own reentrancy limits when a handler fires while another is
    # already running - terminates the entire process with no chance to see what happened. Log
    # it and keep the app alive instead of a hard crash.
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
            param($DispatcherExceptionSender, $DispatcherExceptionEventArgs)
            try {
                "Unhandled dispatcher exception on {0}: {1}" -f $DispatcherExceptionSender.GetType().Name, $DispatcherExceptionEventArgs.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $DispatcherExceptionEventArgs.Exception
            }
            catch {
                # Write-LogOutput itself failing here must not prevent marking the exception handled.
            }
            $DispatcherExceptionEventArgs.Handled = $true
        })

    #endregion

    #region events

    #How to lookup events for a button: ([System.Windows.Controls.Button].GetEvents()|where name -eq 'Click').AddMethod.Name
    # Events are moved to .\Lib\Events
    "Read Events" | Write-LogOutput -LogType DEBUG
    Import-EventObjects -ClassName "MainForm"
    Import-EventObjects -ClassName "AppLogObject"

    #endregion

    #region process
    try {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{})

        "Application '{0}': Start initialization..." -f $Script:RunTimeConfig.ApplicationTitle | Write-Host -ForegroundColor Green
        $Script:ConnectionStatus = $false
        $Script:RunTimeConfig.ReconnectStatus = 0
        Initialize-GlobalConfigSettings -Reset:$Reset

        Close-SplashScreenForm
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -SkipDialog
        Close-SplashScreenForm
        #Clear-Variables
    }

    try {
        $Message = "Application '{0}': Initialized!" -f $Script:RunTimeConfig.ApplicationTitle
        $Message | Write-Host -ForegroundColor Green
        $Message | Write-LogOutput -LogType DEBUG
        "Loading Main form with settings:`r`n{0}" -f ($Script:AppConfig | ConvertTo-Json) | Write-LogOutput -LogType DEBUG

        # End-to-end automation hook. Inert during normal use; only active when OMADASQL_E2E_SCRIPT is
        # set (by the local E2E harness). Once the window is loaded and the dispatcher goes idle (so the
        # first tab exists), dot-source the automation script - which installs script:-scoped mocks and
        # drives the app - then close. A watchdog force-closes and writes a failing report if the
        # automation never runs or hangs, so the harness process can never wait forever.
        if (![string]::IsNullOrWhiteSpace($env:OMADASQL_E2E_SCRIPT)) {
            $Script:E2EWatchdog = New-Object System.Windows.Threading.DispatcherTimer
            $Script:E2EWatchdog.Interval = [TimeSpan]::FromSeconds(90)
            $Script:E2EWatchdog.Add_Tick({
                    try {
                        $Script:E2EWatchdog.Stop()
                        if (![string]::IsNullOrWhiteSpace($env:OMADASQL_E2E_RESULTS)) {
                            '<testsuites><testsuite name="E2E" tests="1" failures="1"><testcase classname="E2E" name="watchdog"><failure message="E2E watchdog fired: automation did not complete"/></testcase></testsuite></testsuites>' | Set-Content -Path $env:OMADASQL_E2E_RESULTS -Encoding UTF8
                            New-Item -Path ("{0}.done" -f $env:OMADASQL_E2E_RESULTS) -ItemType File -Force | Out-Null
                        }
                    }
                    catch {
                        $_.Exception.Message | Write-Host -ForegroundColor Red
                    }
                    finally {
                        try {
                            $Script:MainForm.Definition.Close()
                        }
                        catch {
                            $_.Exception.Message | Write-Host -ForegroundColor Red
                        }
                    }
                })
            $Script:E2EWatchdog.Start()

            $Script:MainForm.Definition.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [action]{
                    try {
                        . $env:OMADASQL_E2E_SCRIPT
                    }
                    catch {
                        "E2E automation failed: {0}" -f $_.Exception.Message | Write-Host -ForegroundColor Red
                    }
                    finally {
                        try {
                            $Script:E2EWatchdog.Stop()
                        }
                        catch {
                            $_.Exception.Message | Write-Host -ForegroundColor Red
                        }
                        try {
                            $Script:MainForm.Definition.Close()
                        }
                        catch {
                            $_.Exception.Message | Write-Host -ForegroundColor Red
                        }
                    }
                }) | Out-Null
        }

        [void]$Script:MainForm.Definition.ShowDialog()
        $Message = "Application '{0}': Closed, cleaning-up!" -f $Script:RunTimeConfig.ApplicationTitle
        # Each tab's own password/connection state was already persisted (subject to its own
        # SavePassword checkbox) by Save-TabSessions, wired into MainForm.Definition's
        # Add_Closing - which already ran by the time ShowDialog() returns here.
        $Message | Write-Host -ForegroundColor Green
        $Message | Write-LogOutput -LogType DEBUG
        "Set-ConfigProperty" | Write-LogOutput -LogType DEBUG
        Set-ConfigProperty
        "Close Main Form" | Write-LogOutput -LogType DEBUG
        $Script:MainForm.Definition.Close() | Out-Null
        foreach ($Tab in $Script:Tabs) {
            try {
                # A lazily-restored tab that was never viewed has no WebView2 yet (Object is $null) -
                # skip it rather than calling Dispose() on null (matches Complete-TabClose's guard).
                if ($null -ne $Tab.WebView -and $null -ne $Tab.WebView.Object) {
                    $Tab.WebView.Object.Dispose() | Out-Null
                }
            }
            catch {
                "Failed to dispose WebView2 for tab '{0}': {1}" -f $Tab.DisplayName, $_.Exception.Message | Write-LogOutput -LogType WARNING
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -SkipDialog
        Close-SplashScreenForm
        #Clear-Variables
    }

    Pop-Location
    #Clear-Variables
    "Application '{0}': Clean-up complete!" -f $Script:RunTimeConfig.ApplicationTitle | Write-Host -ForegroundColor Green
    #endregion
}
