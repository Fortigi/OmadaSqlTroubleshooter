#requires -Module OmadaWeb.PS
#requires -Version 7.0
[cmdletbinding()]
PARAM(
    [ValidateSet("INFO", "DEBUG", "VERBOSE", "WARNING", "ERROR", "FATAL", "VERBOSE2")]
    [string]$LogLevel,
    [switch]$Reset,
    [switch]$LogToConsole
)
$Error.Clear()
$ScriptRootFolder = (Get-Item $PSScriptRoot).FullName
Push-Location $ScriptRootFolder

#region functions
# functions are moved to .\Lib\Functions
Get-ChildItem -Path (Join-Path $ScriptRootFolder -ChildPath "Lib\Functions") -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}
#endregion

#region init
$ScriptName = "OmadaSqlTroubleshooter.ps1"
$ApplicationTitle = ""
$StartVariables = Get-Variable

$AppLogObject = [System.Collections.ObjectModel.ObservableCollection[string]]::new()
$AppLogObject.Add("Application log initialized`r`n")

"Initialize pre-load settings..." | Write-LogOutput -LogType DEBUG
$ConfigFileName = $ScriptName -replace ".ps1", ".json"

$AppDataRootFolder = Join-Path $Env:APPDATA -ChildPath (Get-Item $ScriptRootFolder).Name

iF (Test-Path $AppDataRootFolder -PathType Container) {
    New-Item (Join-Path $AppDataRootFolder -ChildPath "config") -ItemType Directory -Force | Out-Null
    $Script:ConfigFilePath = (Join-Path $AppDataRootFolder -ChildPath "config\$ConfigFileName")
}
else {
    $Script:ConfigFilePath = Join-Path $ScriptRootFolder -ChildPath $ConfigFileName
}
$Script:LogToConsole = $LogToConsole.IsPresent -or $false
$SqlQueryDoIdAttribute = "c-13"
$SqlQueryCreatedByAttribute = "c-2"
$SqlQueryChangedByAttribute = "c-4"
$Script:AppConfig = $null
$Script:AuthenticationSet = $false
$QueryText = $null
$SqlQueryObject = $null
$Script:CurrentSqlQueryDisplayName = $null
$Result = $null
$Script:QueryResult = $null
$Script:LogLevelSetting = [string]::IsNullOrWhiteSpace($LogLevel) ? $null : $LogLevel
$Script:OutputFileName = $null
$Script:CurrentQueryText = $null
$Script:WebView = $null
$Script:WebviewUserDataFolder = $null
$Script:StopWatch = $null
$Script:VerboseParameterSet = $PSCmdlet.MyInvocation.BoundParameters.Keys.Contains("Verbose")

$Script:LastWindowMeasured = Get-Date

$PositionManagerTemplate = @{
    Synchronizing       = $false
    PositionOffSetLeft  = 0
    PositionOffSetRight = 0
    PositionOffSetTop   = 0
    MainWindowRight     = 0
    MainWindowBottom    = 0
    ChildWindowLeft     = 0
    ChildWindowRight    = 0
    ChildWindowBottom   = 0
    LastPositionChange  = Get-Date
}
$Script:PositionManagerLogWindow = $PositionManagerTemplate.PsObject.Copy()
[int32]$Script:PositionManagerLogWindow.PositionOffSetLeft = 1200
$Script:PositionManagerSqlSchemaWindow = $PositionManagerTemplate.PsObject.Copy()
[int32]$Script:PositionManagerSqlSchemaWindow.PositionOffSetRight = 405

$Script:QueryListCache = @{
    QueryList   = $null
    LastRefresh = Get-Date
    TTL         = 300
}

try {
    Remove-Variable "Task" -ErrorAction SilentlyContinue
}
catch {}

#region assemblies
"Load module OmadaWeb.PS" | Write-LogOutput -LogType DEBUG
Import-Module OmadaWeb.PS

"Load Assemblies" | Write-LogOutput -LogType DEBUG
#Set path to the bin folder to be sure that WebView2Loader.dll is found there.
$Env:Path += ";$ScriptRootFolder\Bin"
$Env:Path += ";$ScriptRootFolder\Bin\Webview2Dlls"
$Env:Path += ";$ScriptRootFolder"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework

"Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.Wpf.dll" | ForEach-Object {
    $Script:WebView2Path = Join-Path $ScriptRootFolder -ChildPath "Bin\WebView2Dlls\$_"
    if ((Test-Path $Script:WebView2Path -PathType Leaf)) {
        [System.Reflection.Assembly]::LoadFrom($Script:WebView2Path) | Out-Null
    }
    else {
        Throw ("The WebView2 Dll '{0}' is cannot be found at the '{1}' bin folder!" -f $_, $DllSource)
        Break
    }
}
$Script:WebViewLoaderPath = Join-Path $ScriptRootFolder -ChildPath "Bin\WebView2Dlls\WebView2Loader.dll"
if (!(Test-Path $Script:WebViewLoaderPath -PathType Leaf)) {
    Throw ("The WebView2Loader Dll '{0}' is cannot be found at the '{1}' bin folder!" -f "WebView2Loader.dll", $DllSource)
    Break
}

#endregion

#region controls

"Initializing application..." | Write-LogOutput -LogType DEBUG
[Windows.Forms.Application]::EnableVisualStyles()

"Loading Splash Object" | Write-LogOutput -LogType DEBUG
$SplashForm = New-Object System.Windows.Forms.Form
$SplashForm.Text = "Loading..."
$SplashForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$SplashForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$SplashForm.Width = 300
$SplashForm.Height = 250
$SplashForm.BackColor = [System.Drawing.Color]::White

# Create a PictureBox for the logo
$LogoPictureBox = New-Object System.Windows.Forms.PictureBox
$LogoPictureBox.Image = Get-Icon -Type WinForms
$LogoPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$LogoPictureBox.Width = 150
$LogoPictureBox.Height = 150
#$LogoPictureBox.Location = New-Object System.Drawing.Point(($SplashForm.Width - $LogoPictureBox.Width) / 2, 20)
$LogoPictureBox.Location = New-Object System.Drawing.Point(65, 20)
$SplashForm.Controls.Add($LogoPictureBox)

$SplashLabel = New-Object System.Windows.Forms.Label
$SplashLabel.Text = "Initializing application..."
$SplashLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$SplashLabel.AutoSize = $True
$SplashLabel.Location = New-Object System.Drawing.Point(55, 180)
$SplashForm.Controls.Add($SplashLabel)
#endregion

"Loading Main Window Object" | Write-LogOutput -LogType DEBUG
$Script:MainWindowForm = New-FormObject -FormPath (Join-Path $ScriptRootFolder -ChildPath "lib\ui\MainWindow.xaml")
"Get WebView" | Write-LogOutput -LogType DEBUG
$Script:WebView = $Script:MainWindowForm.Definition.FindName("webView21")

#region events

#How to lookup events for a button: ([System.Windows.Controls.Button].GetEvents()|where name -eq 'Click').AddMethod.Name
try {
    # Events are moved to .\Lib\Events
    "Read Events" | Write-LogOutput -LogType DEBUG
    Get-ChildItem -Path (Join-Path $ScriptRootFolder -ChildPath "Lib\Events") -Filter *.ps1 | ForEach-Object {
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
    Invoke-ProcessConfigSettings -Reset:$Reset.IsPresent

    if ($Script:LogToConsole -or $Script:AppConfig.CheckboxConsoleLog) {
        $Script:LogToConsole = $true
        "Console logging is enabled" | Write-LogOutput -LogType LOG
    }

    "Show Splash Screen" | Write-LogOutput -LogType DEBUG
    [void]$SplashForm.Show()
    $ApplicationTitle = $Script:MainWindowForm.Definition.Title.ToString()
    "Application '{0}': Start initialization..." -f $ApplicationTitle | Write-Host -ForegroundColor Green

    [System.Windows.Forms.Application]::DoEvents()
    if ($null -eq ($Script:MainWindowForm.Definition | Get-WindowPositionConfig)) {
        $Script:MainWindowForm.Definition.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }
    $Result = $Null

    "Pre-set Main Window Components from config" | Write-LogOutput -LogType DEBUG
    $Script:OutputFileName = $Null
    $SqlQueryObject = $Null
    $Script:CurrentSqlQueryDisplayName = $Null
    $Script:CurrentUrl = $Null

    $Script:MainWindowForm.Elements.TextBoxURL.Text = $Script:AppConfig.BaseUrl
    $Script:MainWindowForm.Elements.TextBoxURL.IsEnabled = $True
    if (![String]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text)) {
        $Script:CurrentUrl = $Script:MainWindowForm.Elements.TextBoxURL.Text
        "Config: Current Url: {0}" -f $Script:CurrentUrl | Write-LogOutput -LogType DEBUG
    }

    $InvokeOmadaRestMethodParam = @{
        Uri                = $Null
        Method             = "GET"
        AuthenticationType = $($Script:AppConfig.LastAuthentication)
    }
    $Password = $Null

    if([string]::IsNullOrWhiteSpace($Script:Appconfig.ConfigMultiValueSeparator)) {
        Set-ConfigMultiValueSeparator -Separator "§"
    }

    if ($Script:AppConfig.MyQueriesOnly) {
        "Config: MyQueriesOnly: True" | Write-LogOutput -LogType DEBUG
        $Script:MainWindowForm.Elements.CheckboxMyQueries.IsChecked = $True
    }

    if ($null -ne $Script:LogLevelSetting) {
        $Script:LogLevelSetting | Invoke-ProcessConfigSettings -Property "LogLevel"
        "Config: LogLevelSetting: {0}" -f $Script:LogLevelSetting | Write-LogOutput -LogType DEBUG
    }

    if (![string]::IsNullOrWhiteSpace($Script:AppConfig.SelectedSqlQueryDoId)) {
        "Config: SelectedSqlQueryDoId: {0}" -f $Script:AppConfig.SelectedSqlQueryDoId | Write-LogOutput -LogType DEBUG

        $ComboBoxSelectQueryItem = $null
        $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq (Get-ConfigMultiValue $Script:AppConfig.SelectedSqlQueryDoId) }
        if ($null -eq $ComboBoxSelectQueryItem) {
            "Config: Set SelectedSqlQueryDoId: {0}" -f $Script:AppConfig.SelectedSqlQueryDoId | Write-LogOutput -LogType DEBUG
            $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
            $ComboBoxSelectQueryItem.Content = (Get-ConfigMultiValue  $Script:AppConfig.SelectedSqlQueryDoId)
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
            $Script:CurrentSqlQueryDisplayName = (Get-ConfigMultiValue $Script:AppConfig.SelectedSqlQueryDoId -Array)[0]
            $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $Script:CurrentSqlQueryDisplayName
        }
        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedValue = $ComboBoxSelectQueryItem
    }

    if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection)) {
        "Config: CurrentDataConnection: {0}" -f $Script:AppConfig.CurrentDataConnection | Write-LogOutput -LogType DEBUG
        Set-DataConnection
    }

    if ([string]::IsNullOrWhiteSpace($Script:AppConfig.LastAuthentication)) {
        "Config: LastAuthentication: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG
        $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedValue = $Script:AppConfig.LastAuthentication
    }

    if (![string]::IsNullOrWhiteSpace($Script:AppConfig.UserName)) {
        "Config: UserName: {0}" -f $Script:AppConfig.UserName | Write-LogOutput -LogType DEBUG
        $Script:MainWindowForm.Elements.TextBoxUserName.Text = $Script:AppConfig.UserName
    }
    Set-OmadaUrl
    Set-AuthenticationOption
    Test-ConnectionSettings
    "Close Splash Screen" | Write-LogOutput -LogType DEBUG
    $SplashForm.Hide()
    $SplashForm.Dispose()
}
catch {
    Remove-Variable Webview
    $_.Exception.Message | Write-LogOutput -LogType ERROR -SkipDialog
}

try {
    $Message = "Application '{0}': Initialized!" -f $ApplicationTitle
    $Message | Write-Host -ForegroundColor Green
    $Message | Write-LogOutput -LogType DEBUG
    "Loading Main Window with settings:`r`n{0}" -f ($Script:AppConfig | ConvertTo-Json) | Write-LogOutput -LogType DEBUG

    [void]$Script:MainWindowForm.Definition.ShowDialog()
    $Message = "Application '{0}': Closed, cleaning-up!" -f $ApplicationTitle
    $Message | Write-Host -ForegroundColor Green
    $Message | Write-LogOutput -LogType DEBUG
    "Invoke-ProcessConfigSettings" | Write-LogOutput -LogType DEBUG
    Invoke-ProcessConfigSettings
    "Close Main Window" | Write-LogOutput -LogType DEBUG
    $Script:MainWindowForm.Definition.Close() | Out-Null
    $Script:WebView.Dispose() | Out-Null
}
catch {
    $_.Exception.Message | Write-LogOutput -LogType ERROR -SkipDialog
}

Pop-Location
$EndVariables = Get-Variable
$SkipVariableNames = @("WshShell", "WhatIfPreference", "WarningPreference", "VerbosePreference", "true", "PSItem", "Task")
foreach ($EndVariable in $EndVariables) {
    if ($EndVariable.Name -notin $StartVariables.Name -and $EndVariable.Name -notin $SkipVariableNames) {
        try {
            Remove-Variable -Name $EndVariable.Name -Force -ErrorAction SilentlyContinue
        }
        catch {}
    }
}
"Application '{0}': Clean-up complete!" -f $ApplicationTitle | Write-Host -ForegroundColor Green
#endregion
