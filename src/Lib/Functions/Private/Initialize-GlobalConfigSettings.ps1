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
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        Set-ConfigProperty -Reset:$Reset.IsPresent

        if ($Script:RunTimeConfig.Logging.LogToConsole -or $Script:AppGlobalConfig.CheckboxConsoleLog) {
            $Script:RunTimeConfig.Logging.LogToConsole = $true
            "Console logging is enabled" | Write-LogOutput -LogType LOG
        }

        # Same shape as console logging above: an explicit -SkipBodyRedaction wins, otherwise the
        # setting the user last chose in the log viewer is restored. Resolving it here - before the
        # first request - is what makes -SkipBodyRedaction unredact the very first body, rather than
        # only from the moment the log window happens to be opened.
        if ($Script:RunTimeConfig.Logging.SkipBodyRedaction -or $Script:AppGlobalConfig.SkipBodyRedaction) {
            Set-BodyRedactionState -Enabled $true
            $true | Set-ConfigProperty -Property "SkipBodyRedaction"
        }
        else {
            Set-BodyRedactionState -Enabled $false
        }

        if ($null -eq ($Script:MainForm.Definition | Get-FormPositionConfig)) {
            $Script:MainForm.Definition.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        }

        # The level a user picks in the log viewer is stored in the global config, so it has to be
        # read back here - the previous code pushed the runtime value INTO the config on every
        # start and overwrote it. An explicitly bound -LogLevel still wins for this session; with
        # no parameter the persisted level is restored; with neither, the schema default applies.
        $PersistedLogLevel = $Script:AppGlobalConfig.LogLevel
        $BoundLogLevel = $null
        if ($Script:RunTimeConfig.Logging.LogLevelExplicit) {
            $BoundLogLevel = $Script:RunTimeConfig.Logging.LogLevelSetting
        }

        $ResolvedLogLevel = Resolve-LogLevel -BoundLogLevel $BoundLogLevel -PersistedLogLevel $PersistedLogLevel -SchemaDefault (Get-ConfigSchemaDefault -Property "LogLevel")
        $Script:RunTimeConfig.Logging.LogLevel = $ResolvedLogLevel
        $Script:RunTimeConfig.Logging.LogLevelSetting = $ResolvedLogLevel
        "Config: LogLevelSetting: {0}" -f $ResolvedLogLevel | Write-LogOutput -LogType DEBUG

        # Write back only when the caller asked for a specific level, when nothing is stored yet, or
        # when the stored value differs from the resolved one - which covers both an unusable value
        # and a usable but unnormalized one such as " debug ", rewritten once as "DEBUG" and stable
        # from then on. A stored value that already matches is never rewritten, so the user's own
        # choice survives every later start.
        if ($Script:RunTimeConfig.Logging.LogLevelExplicit -or [string]::IsNullOrWhiteSpace($PersistedLogLevel) -or $PersistedLogLevel -ne $ResolvedLogLevel) {
            "Config: Persisting LogLevel: {0}" -f $ResolvedLogLevel | Write-LogOutput -LogType DEBUG
            $ResolvedLogLevel | Set-ConfigProperty -Property "LogLevel"
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppGlobalConfig.InstanceGuid)) {
            "Config: Get InstanceGuid: {0}" -f $Script:AppGlobalConfig.InstanceGuid | Write-LogOutput -LogType DEBUG
            $Script:RunTimeConfig.InstanceGuid = $Script:AppGlobalConfig.InstanceGuid
        }
        else {
            # First run (or after -Reset): persist the startup InstanceGuid so the SAME one is reused
            # on every later launch. The shared temporary query object (TMP_<InstanceGuid>) is then
            # stable and recreated/reused instead of a new TMP_ query piling up on the server per run.
            "Config: Persisting new InstanceGuid: {0}" -f $Script:RunTimeConfig.InstanceGuid | Write-LogOutput -LogType DEBUG
            $Script:RunTimeConfig.InstanceGuid | Set-ConfigProperty -Property "InstanceGuid"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
