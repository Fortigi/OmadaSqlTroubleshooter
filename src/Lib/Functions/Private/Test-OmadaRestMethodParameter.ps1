function Test-OmadaRestMethodParameter {
    <#
    .SYNOPSIS
    Whether the installed OmadaWeb.PS accepts a given parameter on Invoke-OmadaRestMethod.

    .DESCRIPTION
    A capability probe, in a function of its own so that callers can be tested without mocking
    Get-Command - which Pester itself uses, making it an unreliable thing to intercept.

    The probe matters because PowerShell REJECTS an unknown parameter rather than ignoring it. Passing
    a parameter that an older module does not declare turns a working request into a failed one, so
    every optional parameter this application adds has to be asked about first.

    Both of this application's optional parameters go through here - SkipBodyRedaction from
    Build-OmadaRequestParameter and NoInteractiveAuthentication from
    Add-OmadaNonInteractiveAuthentication - so there is one answer to "does the installed module
    support this?" rather than one per caller.

    Dynamic parameters count: OmadaWeb.PS declares most of its own through New-DynamicParam, and they
    do appear in Get-Command's .Parameters - verified against both 2026.7.9.9 and 2026.9.9.

    .PARAMETER Name
    The parameter to ask about.

    .OUTPUTS
    [bool] $false when the module, or the parameter, is not there.
    #>
    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        $Private:Command = Get-Command -Name "Invoke-OmadaRestMethod" -ErrorAction SilentlyContinue
        if ($null -eq $Private:Command) {
            return $false
        }

        return [bool]$Private:Command.Parameters.ContainsKey($Name)
    }
    catch {
        # An unanswerable question is answered "no": not adding an optional parameter is always safe,
        # adding one the module rejects is not.
        return $false
    }
}
