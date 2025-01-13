#requires -Module OmadaWeb.PS
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
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'StartVariables', Justification = 'The CurrentPoperties variable is used in a function called from here')]
    [CmdletBinding()]
    PARAM(
        [ValidateSet("INFO", "DEBUG", "VERBOSE", "WARNING", "ERROR", "FATAL", "VERBOSE2")]
        [string]$LogLevel,
        [switch]$Reset,
        [switch]$LogToConsole
    )
    $Error.Clear()

    #region Initialize
    $StartVariables = Get-Variable
    $ApplicationName = "OmadaSqlTroubleshooter"

    $Script:RunTimeConfig = @{
        ScriptName         = "OmadaSqlTroubleshooter"
        ApplicationTitle   = ""
        ModuleFolder       = Split-Path (Get-Module OmadaSqlTroubleShooter).Path
        AppDataFolder      = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)) -ChildPath $ApplicationName
        Logging            = [PSCustomObject]@{
            LogToConsole        = $LogToConsole.IsPresent -or $false
            LogLevel            = $null
            VerboseParameterSet = $PSCmdlet.MyInvocation.BoundParameters.Keys.Contains("Verbose")
            LogLevelSetting     = $(if ([string]::IsNullOrWhiteSpace($LogLevel)) { $null }else { $LogLevel })
            AppLogObject        = [System.Collections.ObjectModel.ObservableCollection[string]]::new()
        }
        StopWatch          = $null
        LastWindowMeasured = Get-Date
        ConfigFile         = [PSCustomObject]@{
            Path = $null
            Name = $null
        }
        AuthenticationSet  = $false
        OutputFileName     = $null
    }
    Get-ChildItem -Path (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Lib\Functions") -Filter *.ps1 | ForEach-Object {
        . $_.FullName
    }
    Initialize-OmadaSqlTroubleShooter
    #endregion

    #region wpf
    $SplashScreenForm = Open-SplashScreenForm
    "Loading Main Window Object" | Write-LogOutput -LogType DEBUG
    $Script:MainWindowForm = New-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\MainWindow.xaml")
    $Script:RunTimeConfig.ApplicationTitle = $Script:MainWindowForm.Definition.Title.ToString()
    "Get WebView" | Write-LogOutput -LogType DEBUG
    $Script:Webview.Object = $Script:MainWindowForm.Definition.FindName("webView21")
    #endregion

    #region events

    #How to lookup events for a button: ([System.Windows.Controls.Button].GetEvents()|where name -eq 'Click').AddMethod.Name
    try {
        # Events are moved to .\Lib\Events
        "Read Events" | Write-LogOutput -LogType DEBUG
        Get-ChildItem -Path (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Lib\Events") -Filter *.ps1 | ForEach-Object {
            . $_.FullName
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "NotFound") {
            "SQL Troubleshooting Object not found or OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR
        }
        else {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    }
    #endregion

    #region process
    try {
        "Show Splash Screen" | Write-LogOutput -LogType DEBUG
        [void]$SplashScreenForm.Show()
        [System.Windows.Forms.Application]::DoEvents()

        "Application '{0}': Start initialization..." -f $Script:RunTimeConfig.ApplicationTitle | Write-Host -ForegroundColor Green
        Initialize-ConfigSettings

        Close-SplashScreenForm
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -SkipDialog
        Close-SplashScreenForm
        Clear-Variables
    }

    try {
        $Message = "Application '{0}': Initialized!" -f $Script:RunTimeConfig.ApplicationTitle
        $Message | Write-Host -ForegroundColor Green
        $Message | Write-LogOutput -LogType DEBUG
        "Loading Main Window with settings:`r`n{0}" -f ($Script:AppConfig | ConvertTo-Json) | Write-LogOutput -LogType DEBUG

        [void]$Script:MainWindowForm.Definition.ShowDialog()
        $Message = "Application '{0}': Closed, cleaning-up!" -f $Script:RunTimeConfig.ApplicationTitle
        $Message | Write-Host -ForegroundColor Green
        $Message | Write-LogOutput -LogType DEBUG
        "Invoke-ConfigSetting" | Write-LogOutput -LogType DEBUG
        Invoke-ConfigSetting
        "Close Main Window" | Write-LogOutput -LogType DEBUG
        $Script:MainWindowForm.Definition.Close() | Out-Null
        $Script:Webview.Object.Dispose() | Out-Null
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -SkipDialog
        Close-SplashScreenForm
        Clear-Variables
    }

    Pop-Location
    Clear-Variables
    "Application '{0}': Clean-up complete!" -f $Script:RunTimeConfig.ApplicationTitle | Write-Host -ForegroundColor Green
    #endregion
}
