function Clear-OmadaSqlTroubleshooterCache {
    <#
    .SYNOPSIS
        Reports and removes the data OmadaSqlTroubleshooter caches on this machine.

    .DESCRIPTION
        The module caches two things under %LOCALAPPDATA%\OmadaSqlTroubleshooter:

        - Binaries: the four Microsoft.Web.WebView2 assemblies, downloaded from the URL pinned in
          DependencyLock.psd1 and verified against its SHA-256 on first import, together with the
          WebView2.pin stamp recording which pin they came from. Removing them only costs a fresh,
          verified download on the next import.
        - BrowserProfiles: the Edge user profile WebView2 keeps under "Edge User Data". This holds
          the sign-in cookies that make re-authentication silent, so it is what to remove to sign
          out completely or switch user.

        Removing the binaries is the supported way to recover when a pinned version was rolled back,
        when an integrity check aborted an import, or when the assemblies on disk are suspect.

        The application's configuration under %APPDATA%\OmadaSqlTroubleshooter is deliberately left
        alone: saved connections, window positions and preferences are settings, not cache.

        Run with -ListOnly to see what is stored without changing anything. Without -ListOnly the
        artefacts are removed after confirmation; use -WhatIf to preview and -Force to skip the
        prompt. In both cases one object per artefact is returned.

        An assembly that is already loaded into the running PowerShell session is locked by Windows
        and cannot be removed. The command reports which ones it could not remove and continues;
        close that PowerShell session and run it again to remove them.

    .PARAMETER Scope
        Which artefacts to report and remove: All (the default), Binaries or BrowserProfiles. More
        than one value can be given.

    .PARAMETER ListOnly
        Report what is stored without removing anything.

    .PARAMETER Force
        Remove without asking for confirmation. -WhatIf still takes precedence.

    .INPUTS
        None. This command does not accept pipeline input.

    .OUTPUTS
        PSCustomObject. One object per artefact, with the Scope, Artefact, Path, TargetPath,
        ItemType, Protection, Exists, ItemCount, SizeBytes and Removed properties.

    .EXAMPLE
        Clear-OmadaSqlTroubleshooterCache -ListOnly | Format-Table Scope, Artefact, Path, ItemCount, SizeBytes

        Shows everything the module has cached on this machine without removing any of it.

    .EXAMPLE
        Clear-OmadaSqlTroubleshooterCache -Scope Binaries -Force

        Drops the downloaded WebView2 assemblies and their pin stamp, so the next module import
        downloads and verifies them again. Keeps the browser profile, so sign-in stays silent.

    .EXAMPLE
        Clear-OmadaSqlTroubleshooterCache -WhatIf

        Reports exactly what would be removed, and removes nothing.

    .LINK
        https://github.com/Fortigi/OmadaSqlTroubleshooter
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet("All", "Binaries", "BrowserProfiles")]
        [string[]]$Scope = "All",

        [Parameter()]
        [switch]$ListOnly,

        [Parameter()]
        [switch]$Force
    )

    # No tracer preamble here: this command is meant to be usable without starting the application,
    # so $Script:RunTimeConfig - which the tracer line and Write-LogOutput both read - may not exist.

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        $Item = @(Get-OmadaSqlTroubleshooterCacheItem -Scope $Scope)

        if ($ListOnly.IsPresent) {
            return $Item
        }

        # -Force suppresses the confirmation prompt without disabling -WhatIf, which must keep
        # reporting rather than removing.
        if ($Force.IsPresent -and -not $WhatIfPreference) {
            $ConfirmPreference = "None"
        }

        foreach ($CacheItem in $Item) {
            if (-not $CacheItem.Exists) {
                "{0} - Nothing to remove for '{1}' ({2})" -f $MyInvocation.MyCommand, $CacheItem.Artefact, $CacheItem.Path | Write-Verbose
                continue
            }

            $Action = "Remove {0} ({1} item(s), {2:N0} bytes)" -f $CacheItem.Artefact, $CacheItem.ItemCount, $CacheItem.SizeBytes

            if ($PSCmdlet.ShouldProcess($CacheItem.Path, $Action)) {
                $Failed = $false
                foreach ($PathToRemove in $CacheItem.TargetPath) {
                    try {
                        Remove-Item -Path $PathToRemove -Recurse -Force -Confirm:$false -ErrorAction Stop
                        "{0} - Removed '{1}'" -f $MyInvocation.MyCommand, $PathToRemove | Write-Verbose
                    }
                    catch {
                        # An assembly already loaded into this process is locked until the session
                        # ends, so a failure here is expected rather than exceptional: report it and
                        # carry on with the remaining artefacts.
                        $Failed = $true
                        "Could not remove '{0}': {1} Close this PowerShell session and run the command again if the files are still in use." -f $PathToRemove, $_.Exception.Message | Write-Warning
                    }
                }
                $CacheItem.Removed = -not $Failed
            }
        }

        return $Item
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
