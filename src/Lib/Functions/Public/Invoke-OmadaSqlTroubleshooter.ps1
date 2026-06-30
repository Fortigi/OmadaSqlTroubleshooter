#requires -Modules @{ ModuleName="OmadaWeb.PS"; ModuleVersion="2025.10.9.1" }
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
        AppDataFolder      = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)) -ChildPath $ApplicationName
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
    }
    Get-ChildItem -Path (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Lib\Functions") -Filter *.ps1 | Where-Object { $_.Name -notlike "_*.ps1" } | ForEach-Object {
        . $_.FullName
    }

    Initialize-OmadaSqlTroubleShooter
    #endregion

    #region wpf
    $null  = Open-SplashScreenForm
    "Loading Main Form Object" | Write-LogOutput -LogType DEBUG
    $Script:MainForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\MainForm.xaml") -AppendVersion

    "Initializing UI components" | Write-LogOutput -LogType DEBUG
    Initialize-UiComponents

    $Script:RunTimeConfig.ApplicationTitle = $Script:MainForm.Definition.Title.ToString()
    "Get WebView" | Write-LogOutput -LogType DEBUG
    $Script:Webview.Object = $Script:MainForm.Definition.FindName("webView21")
    Import-EventObjects -ClassName "WebView"

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
        Initialize-ConfigSettings

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

        [void]$Script:MainForm.Definition.ShowDialog()
        $Message = "Application '{0}': Closed, cleaning-up!" -f $Script:RunTimeConfig.ApplicationTitle
        if (!$Script:RunTimeConfig.SavePassword) {
            $null | Set-ConfigProperty -Property "Password"
        }
        elseif ($null -ne $Script:MainForm.Elements.TextBoxPassword.Password) {
            $Script:MainForm.Elements.TextBoxPassword.Password | Set-ConfigProperty -Property "Password"
        }
        $Message | Write-Host -ForegroundColor Green
        $Message | Write-LogOutput -LogType DEBUG
        "Set-ConfigProperty" | Write-LogOutput -LogType DEBUG
        Set-ConfigProperty
        "Close Main Form" | Write-LogOutput -LogType DEBUG
        $Script:MainForm.Definition.Close() | Out-Null
        $Script:Webview.Object.Dispose() | Out-Null
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
