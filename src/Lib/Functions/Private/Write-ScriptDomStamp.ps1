function Write-ScriptDomStamp {
    [CmdletBinding()]
    param()

    # Records which pin the installed ScriptDom assembly came from, next to the assembly itself.
    # Install-ScriptDom reads it back through Get-ScriptDomStamp instead of comparing the DLL's
    # ProductVersion, for the same reason Write-WebView2Stamp does: a pin that moves BACKWARDS - a
    # rollback after a bad bump - must also force a reinstall, and a version comparison would not.
    #
    # No tracer preamble: see Get-DependencyLock.

    $Artifact = Get-LockedArtifact -Id "Microsoft.SqlServer.TransactSql.ScriptDom"

    $StampContent = @(
        "# Written by Install-ScriptDom. Records the pin the assembly in this folder was installed"
        "# from. Delete this file, or run Clear-OmadaSqlTroubleshooterCache -Scope Binaries, to force"
        "# a verified reinstall on the next start."
        "@{"
        ('    Version = "{0}"' -f $Artifact.Version)
        ('    Sha256  = "{0}"' -f (Get-FileSha256 -Path $Script:ScriptDomPath))
        "}"
    ) -join "`r`n"

    Set-Content -Path $Script:ScriptDomStampPath -Value $StampContent -Encoding UTF8 -Force

    "{0} - Wrote stamp '{1}' for pinned version {2}" -f $MyInvocation.MyCommand, $Script:ScriptDomStampPath, $Artifact.Version | Write-Verbose
}
