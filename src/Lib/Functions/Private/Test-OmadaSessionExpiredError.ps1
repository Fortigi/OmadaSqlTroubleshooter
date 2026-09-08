function Test-OmadaSessionExpiredError {
    <#
    .SYNOPSIS
    Whether an error is OmadaWeb.PS saying "the session has gone and I was told not to sign in".

    .DESCRIPTION
    The contract comes from Fortigi/OmadaWeb.PS#85, which added -NoInteractiveAuthentication. Under
    that switch an expired or missing session is a terminating error rather than a sign-in attempt,
    and it is deliberately identifiable two ways:

      FullyQualifiedErrorId   starts with "OmadaSessionExpired"
      Exception               is System.Security.Authentication.AuthenticationException

    Both are checked, because either can survive where the other does not. The id is a PREFIX match
    on purpose - PowerShell appends the name of every function a terminating error passes through,
    so equality would break the moment the module added a layer. The exception type is checked by
    name rather than with -is, so an error that crossed a runspace boundary and arrived
    deserialized still matches.

    This is what a keep-alive needs to tell "the session is gone" from "the tenant had a bad
    moment": the first means stop, the second means try again later.

    .PARAMETER ErrorRecord
    The error to classify. $null is not a session expiry.

    .OUTPUTS
    [bool]
    #>
    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        $ErrorRecord
    )

    if ($null -eq $ErrorRecord) {
        return $false
    }

    try {
        if ([string]$ErrorRecord.FullyQualifiedErrorId -like "OmadaSessionExpired*") {
            return $true
        }
    }
    catch {
        # An error record that will not yield its id is simply not a match on that test.
    }

    try {
        $Private:Exception = $ErrorRecord.Exception
        while ($null -ne $Private:Exception) {
            # By name, not with -is: a deserialized exception is a PSObject wrapper whose type name
            # is preserved but whose .NET type is not.
            if ($Private:Exception.GetType().FullName -eq "System.Security.Authentication.AuthenticationException") {
                return $true
            }
            $Private:Exception = $Private:Exception.InnerException
        }
    }
    catch {
        # Same reasoning.
    }

    return $false
}
