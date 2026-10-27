function Test-NewPasswordlessCredential {
    <#
    .SYNOPSIS
    Whether a credential becomes passwordless for its username with this update.

    .DESCRIPTION
    Update-TabCredential runs on every focus change of the username and password fields, on every
    change of authentication option and on every tab restore. It tells the user once that the
    password is not needed - when the tab's credential changes into a passwordless one for a
    username - instead of on each of those calls.

    .PARAMETER Previous
    The tab's credential before the update, or $null.

    .PARAMETER Current
    The credential the update sets, or $null.

    .OUTPUTS
    [bool] $true when Current is passwordless and Previous was not a passwordless credential for the
    same username.
    #>
    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [System.Management.Automation.PSCredential]$Previous,
        [AllowNull()]
        [System.Management.Automation.PSCredential]$Current
    )

    if ($null -eq $Current -or $Current.Password.Length -gt 0) {
        return $false
    }
    if ($null -eq $Previous -or $Previous.Password.Length -gt 0) {
        return $true
    }
    return $Previous.UserName -ne $Current.UserName
}
