function Get-ScriptDomStamp {
    [CmdletBinding()]
    param()

    # Returns the pinned version recorded in the stamp Install-ScriptDom wrote next to the assembly,
    # or $null when there is nothing usable there.
    #
    # This must never throw. A corrupt or hand-edited stamp has to degrade to "reinstall" rather than
    # break the startup path.
    #
    # No tracer preamble: see Get-DependencyLock.

    if ([string]::IsNullOrWhiteSpace($Script:ScriptDomStampPath) -or -not (Test-Path $Script:ScriptDomStampPath -PathType Leaf)) {
        "{0} - No stamp at '{1}'" -f $MyInvocation.MyCommand, $Script:ScriptDomStampPath | Write-Verbose
        return $null
    }

    try {
        # Same parser as Get-DependencyLock: SafeGetValue evaluates constant expressions only, so a
        # stamp file can never execute code.
        $ParseErrors = $null
        $Tokens = $null
        $StampAst = [System.Management.Automation.Language.Parser]::ParseFile($Script:ScriptDomStampPath, [ref]$Tokens, [ref]$ParseErrors)
        if (($ParseErrors | Measure-Object).Count -gt 0) {
            throw ($ParseErrors | ForEach-Object { $_.Message }) -join "; "
        }

        $HashtableAst = $StampAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.HashtableAst] }, $false)
        if ($null -eq $HashtableAst) {
            throw "the file does not contain a hashtable"
        }

        $Stamp = $HashtableAst.SafeGetValue()
    }
    catch {
        "The ScriptDom stamp file '{0}' could not be read ({1}). Treating the installed assembly as unverified." -f $Script:ScriptDomStampPath, $_.Exception.Message | Write-Verbose
        return $null
    }

    if (-not $Stamp.ContainsKey("Version") -or [string]::IsNullOrWhiteSpace($Stamp.Version)) {
        return $null
    }

    return $Stamp.Version
}
