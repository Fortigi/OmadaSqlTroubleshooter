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

    CACHED PER MODULE VERSION. Reading .Parameters runs the module's dynamic-parameter block, which
    took 236 ms per call with OmadaWeb.PS 2026.9.23.47 - and Build-OmadaRequestParameter asks before
    every request, so it was a quarter of a second of UI thread per request. Get-Command itself is a
    millisecond. The key is the module's name, version and path, so an upgrade, a downgrade or a module
    loaded from elsewhere is asked afresh. A command that does not come from a module (a function
    defined in the session, a test double) is never cached.

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

        $Private:Module = $Private:Command.Module
        if ($null -eq $Private:Module) {
            return [bool]$Private:Command.Parameters.ContainsKey($Name)
        }

        $Private:CacheKey = "{0}|{1}|{2}|{3}" -f $Private:Module.Name, $Private:Module.Version, $Private:Module.Path, $Name
        if ($null -eq $Script:OmadaRestMethodParameterCache) {
            $Script:OmadaRestMethodParameterCache = @{}
        }

        # The answer is also tied to the function's own ScriptBlock. Get-Command hands back the same
        # ScriptBlock object for as long as the function is unchanged and a new one once it is
        # redefined - which the module key alone cannot see: two functions defined in the same module
        # (a test framework's, on CI) share name, version and path.
        $Private:Cached = $Script:OmadaRestMethodParameterCache[$Private:CacheKey]
        if ($null -ne $Private:Cached -and [object]::ReferenceEquals($Private:Cached.ScriptBlock, $Private:Command.ScriptBlock)) {
            return $Private:Cached.Answer
        }

        $Private:Answer = [bool]$Private:Command.Parameters.ContainsKey($Name)
        $Script:OmadaRestMethodParameterCache[$Private:CacheKey] = @{
            Answer      = $Private:Answer
            ScriptBlock = $Private:Command.ScriptBlock
        }

        return $Private:Answer
    }
    catch {
        # An unanswerable question is answered "no": not adding an optional parameter is always safe,
        # adding one the module rejects is not.
        return $false
    }
}
