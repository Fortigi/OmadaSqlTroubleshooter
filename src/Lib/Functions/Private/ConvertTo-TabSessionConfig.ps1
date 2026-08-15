function ConvertTo-TabSessionConfig {
    <#
    .SYNOPSIS
    Maps a legacy (pre-tabs) flat config object onto a single tab-config entry, for the
    one-time migration that folds an existing single-session config into "tab 1".
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $LegacyAppConfig
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $DisplayName = $null
        if ($null -ne $LegacyAppConfig -and $LegacyAppConfig.PSObject.Properties.Match("DisplayName").Count -gt 0) {
            $DisplayName = $LegacyAppConfig.DisplayName
        }
        if ([string]::IsNullOrWhiteSpace($DisplayName)) {
            $DisplayName = Get-DefaultTabDisplayName
        }

        # Plain dot-access is deliberate here, not an oversight: this codebase never enables
        # Set-StrictMode, so reading a property off $LegacyAppConfig (or off a $null
        # sub-property, e.g. a missing CurrentSqlQuery) already safely evaluates to $null
        # rather than throwing - no ?. null-conditional needed.
        return [PSCustomObject]@{
            Id                    = (New-Guid).Guid
            DisplayName           = $DisplayName
            BaseUrl               = $LegacyAppConfig.BaseUrl
            CurrentSqlQuery       = [PSCustomObject]@{
                DoId        = $LegacyAppConfig.CurrentSqlQuery.DoId
                DisplayName = $LegacyAppConfig.CurrentSqlQuery.DisplayName
                FullName    = $LegacyAppConfig.CurrentSqlQuery.FullName
            }
            LastAuthentication    = $LegacyAppConfig.LastAuthentication
            UserName              = $LegacyAppConfig.UserName
            Password              = $LegacyAppConfig.Password
            EntraApplicationIdUri = $LegacyAppConfig.EntraApplicationIdUri
            EntraIdTenantId       = $LegacyAppConfig.EntraIdTenantId
            MyCreatedQueriesOnly  = [bool]$LegacyAppConfig.MyCreatedQueriesOnly
            MyUpdatedQueriesOnly  = [bool]$LegacyAppConfig.MyUpdatedQueriesOnly
            SavePassword          = [bool]$LegacyAppConfig.SavePassword
            IdentityUserName      = $LegacyAppConfig.IdentityUserName
            CurrentDataConnection = [PSCustomObject]@{
                DoId        = $LegacyAppConfig.CurrentDataConnection.DoId
                DisplayName = $LegacyAppConfig.CurrentDataConnection.DisplayName
                FullName    = $LegacyAppConfig.CurrentDataConnection.FullName
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
