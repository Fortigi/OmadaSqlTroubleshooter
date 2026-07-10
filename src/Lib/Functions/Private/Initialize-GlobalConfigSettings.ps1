function Initialize-GlobalConfigSettings {
    <#
    .SYNOPSIS
    Loads/reconciles the genuinely application-wide settings (log level/console logging, window
    position/size, tab capacity, instance GUID) - the subset of the old, single-session
    Initialize-ConfigSettings that is NOT per-tab connection state. Per-tab restoration now
    happens in Restore-TabSessions/New-TabSession instead.
    #>
    [CmdLetBinding()]
    param(
        [switch]$Reset
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        Set-ConfigProperty -Reset:$Reset.IsPresent

        if ($Script:RunTimeConfig.Logging.LogToConsole -or $Script:AppGlobalConfig.CheckboxConsoleLog) {
            $Script:RunTimeConfig.Logging.LogToConsole = $true
            "Console logging is enabled" | Write-LogOutput -LogType LOG
        }

        if ($null -eq ($Script:MainForm.Definition | Get-FormPositionConfig)) {
            $Script:MainForm.Definition.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        }

        if ($null -ne $Script:RunTimeConfig.Logging.LogLevelSetting) {
            $Script:RunTimeConfig.Logging.LogLevelSetting | Set-ConfigProperty -Property "LogLevel"
            $Script:RunTimeConfig.Logging.LogLevel = $Script:RunTimeConfig.Logging.LogLevelSetting
            "Config: LogLevelSetting: {0}" -f $Script:RunTimeConfig.Logging.LogLevelSetting | Write-LogOutput -LogType DEBUG
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppGlobalConfig.InstanceGuid)) {
            "Config: Get InstanceGuid: {0}" -f $Script:AppGlobalConfig.InstanceGuid | Write-LogOutput -LogType DEBUG
            $Script:RunTimeConfig.InstanceGuid = $Script:AppGlobalConfig.InstanceGuid
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
