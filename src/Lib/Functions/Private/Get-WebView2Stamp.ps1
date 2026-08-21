function Get-WebView2Stamp {
    [CmdletBinding()]
    param()

    # Reads the stamp Install-WebView2 wrote next to the assemblies, or returns $null when there is
    # nothing usable there.
    #
    # This must never throw. It is called during module import to decide whether a reinstall is due,
    # and a corrupt or hand-edited stamp has to degrade to "reinstall" rather than kill the import.
    #
    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    if ([string]::IsNullOrWhiteSpace($Script:WebView2StampPath) -or -not (Test-Path $Script:WebView2StampPath -PathType Leaf)) {
        "{0} - No stamp at '{1}'" -f $MyInvocation.MyCommand, $Script:WebView2StampPath | Write-Verbose
        return $null
    }

    try {
        # Same parser as Get-DependencyLock: SafeGetValue evaluates constant expressions only, so a
        # stamp file can never execute code.
        $ParseErrors = $null
        $Tokens = $null
        $StampAst = [System.Management.Automation.Language.Parser]::ParseFile($Script:WebView2StampPath, [ref]$Tokens, [ref]$ParseErrors)
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
        "The WebView2 stamp file '{0}' could not be read ({1}). Treating the installed assemblies as unverified." -f $Script:WebView2StampPath, $_.Exception.Message | Write-Verbose
        return $null
    }

    if (-not $Stamp.ContainsKey("Version") -or [string]::IsNullOrWhiteSpace($Stamp.Version)) {
        "The WebView2 stamp file '{0}' records no version. Treating the installed assemblies as unverified." -f $Script:WebView2StampPath | Write-Verbose
        return $null
    }

    return $Stamp
}
