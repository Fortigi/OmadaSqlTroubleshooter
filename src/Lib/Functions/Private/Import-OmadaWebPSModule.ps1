function Import-OmadaWebPSModule {
    <#
        .SYNOPSIS
        Imports OmadaWeb.PS, honoring an already loaded non-versioned development build.

        .DESCRIPTION
        A development or locally loaded copy of OmadaWeb.PS can report version '0.0', which
        Import-Module -MinimumVersion would reject outright. When such a module is already
        loaded in the current session it is treated as an explicit override by the user or
        developer: it is left in place and a warning is written instead of importing over it.

        Otherwise the module is imported normally with -ErrorAction Stop, so a missing module
        terminates the caller, and with -PassThru, so the actually imported module object can
        be validated against the required minimum version afterwards. Import-Module -PassThru
        can return more than one module object when OmadaWeb.PS pulls in nested modules; those
        are imported before the parent module object is returned, so filtering the PassThru
        result to the module named 'OmadaWeb.PS' and taking the last match yields the
        top-level module that is actually left loaded. If that filter yields no match, the
        imported version cannot be confirmed, so the caller is terminated rather than risking a
        null-valued Version comparison.

        When the imported version is below the required minimum, the module is removed again
        before the error is thrown, but only when it was not already loaded before this
        function ran: unlike the previous Import-Module -MinimumVersion behavior, an unguarded
        import would otherwise leave an out-of-spec OmadaWeb.PS module loaded in the session
        even though the caller terminated. A module that was already loaded (with a real
        version) before this function ran is left as the caller had it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MinimumVersion
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

    $AlreadyLoadedModule = Get-Module -Name "OmadaWeb.PS"
    if ($AlreadyLoadedModule -and $AlreadyLoadedModule.Version -eq [version]"0.0") {
        "Using already loaded non-versioned OmadaWeb.PS module at your own risk!" | Write-Warning
        return
    }

    $WasAlreadyLoaded = $null -ne $AlreadyLoadedModule
    $ImportedModules = @(Import-Module -Name "OmadaWeb.PS" -ErrorAction Stop -PassThru)
    $ImportedOmadaWebPSModule = $ImportedModules | Where-Object { $_.Name -eq "OmadaWeb.PS" } | Select-Object -Last 1

    if (-not $ImportedOmadaWebPSModule) {
        "Importing the OmadaWeb.PS module did not return a module object, so its version could not be confirmed." | Write-Error -ErrorAction "Stop"
        return
    }

    if ($ImportedOmadaWebPSModule.Version -lt [version]$MinimumVersion) {
        if (-not $WasAlreadyLoaded) {
            Remove-Module -Name "OmadaWeb.PS" -Force -ErrorAction SilentlyContinue
        }

        "OmadaWeb.PS module version {0} or higher is required." -f $MinimumVersion | Write-Error -ErrorAction "Stop"
    }
}
