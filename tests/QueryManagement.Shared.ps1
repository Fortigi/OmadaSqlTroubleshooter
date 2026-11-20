# Shared doubles for the rename / delete / save-as-new tests: a tab's state and the functions around it.

$Script:QueryPrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
$Script:Tracer = [System.Diagnostics.Trace]

$script:QueryLog = [System.Collections.Generic.List[object]]::new()
function Write-LogOutput {
    param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType = "INFO", $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
    process { $script:QueryLog.Add([PSCustomObject]@{ Message = [string]$Message; LogType = $LogType }) }
}
function Write-ContainedErrorLog {
    param([Parameter(ValueFromPipeline = $true)][string]$Message, $ErrorObject, [switch]$TabScoped)
    process { $script:QueryLog.Add([PSCustomObject]@{ Message = $Message; LogType = "ERROR" }) }
}
function ConvertTo-RedactedLogString { param($InputObject, $MaxDepth) return "" }

function script:New-QueryTestState {
    param($DoId = 42, $Name = "Accounts", [bool]$Connected = $true)

    $Script:ConnectionStatus = $Connected
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
    $Script:AppConfig = [PSCustomObject]@{
        BaseUrl         = "https://t"
        CurrentSqlQuery = [PSCustomObject]@{ DoId = $DoId; DisplayName = $Name; FullName = "{0} - {1}" -f $Name, $DoId }
    }
    $Script:RunTimeData = [PSCustomObject]@{
        CurrentSqlQuery  = [PSCustomObject]@{ DoId = $DoId; DisplayName = $Name; FullName = "{0} - {1}" -f $Name, $DoId }
        CurrentQueryText = "SELECT saved"
        QueryText        = $null
        QueryListCache   = @{ QueryList = @(@{ 42 = "Accounts" }, @{ 43 = "Other" }) }
        RestMethodParam  = @{ Uri = $null; Method = "GET"; Body = $null }
    }
    $script:SelectedItem = [PSCustomObject]@{ Content = "{0} - {1}" -f $Name, $DoId }
    $Script:MainForm = [PSCustomObject]@{
        Elements = [PSCustomObject]@{
            ComboBoxSelectQuery = [PSCustomObject]@{ SelectedItem = $script:SelectedItem; Text = $script:SelectedItem.Content }
            TextBoxDisplayName  = [PSCustomObject]@{ Text = $Name }
            ButtonSaveQuery     = [PSCustomObject]@{ IsEnabled = $false }
            ButtonExecuteQuery  = [PSCustomObject]@{ IsEnabled = $false }
            ButtonRenameQuery   = [PSCustomObject]@{ IsEnabled = $false }
            ButtonDeleteQuery   = [PSCustomObject]@{ IsEnabled = $false }
        }
    }
    $script:TestTab = [PSCustomObject]@{
        Id          = "tab-1"
        DisplayName = "Query1"
        OpenOrder   = 3
        IsDirty     = $false
        EditorText  = "SELECT on screen"
        DraftText   = $null
        AppConfig   = $Script:AppConfig
        RunTimeData = $Script:RunTimeData
        Elements    = $Script:MainForm.Elements
    }
    $Script:ActiveTabId = "tab-1"
    $Script:Tabs = @($script:TestTab)
    $script:QueryLog.Clear()
}
