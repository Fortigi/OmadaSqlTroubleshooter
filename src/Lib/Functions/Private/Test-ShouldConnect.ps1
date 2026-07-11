function Test-ShouldConnect {
    <#
    .SYNOPSIS
    Decides whether the current connection settings should be treated as connected.

    .DESCRIPTION
    Pure decision behind Test-ConnectionSettings. Returns $false (force disconnected) when a connect
    is not actually in progress (ReconnectStatus -le 1 - the value during startup before the
    interactive Connect button or the restore auto-connect raises it to 2), when no tenant URL or
    authentication option is set, or when OAuth is selected without a username/password. Otherwise
    returns $true. Kept as its own function so the rule - in particular the ReconnectStatus gate that
    caused restored tabs to come back disconnected - can be unit tested.
    #>
    [CmdLetBinding()]
    param(
        [int]$ReconnectStatus,
        [string]$Url,
        [string]$AuthenticationOption,
        # OAuth only: whether both a username and a password have been entered.
        [bool]$HasCredentials
    )

    if ($ReconnectStatus -le 1 -or [string]::IsNullOrEmpty($Url) -or [string]::IsNullOrEmpty($AuthenticationOption)) {
        return $false
    }

    if ($AuthenticationOption -eq "OAuth" -and -not $HasCredentials) {
        return $false
    }

    return $true
}
