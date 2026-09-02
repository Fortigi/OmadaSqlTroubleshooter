function Install-ScriptDom {
    <#
    .SYNOPSIS
        Downloads and installs the Microsoft.SqlServer.TransactSql.ScriptDom assembly that backs the
        editor's client-side T-SQL syntax diagnostics.

    .DESCRIPTION
        Mirrors Install-WebView2: the version, download URL and SHA-256 come from
        src\DependencyLock.psd1, Invoke-DownloadFile verifies the bytes before anything is expanded,
        and a small stamp file next to the assembly records which pin it came from so a pin that
        moves - forwards or backwards - forces a verified reinstall.

        It differs from Install-WebView2 in one important respect: this dependency is OPTIONAL. The
        syntax pass is a convenience, not a prerequisite, so every failure path here returns $false
        instead of throwing. The caller switches the feature off and the application behaves exactly
        as it did before the feature existed.

    .PARAMETER Force
        Reinstall even when the installed assembly already matches the pinned version.

    .OUTPUTS
        [bool] $true when the assembly is present at $Script:ScriptDomPath and matches the pin.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    # No tracer preamble: see Get-DependencyLock. The parameters carry nothing worth tracing and this
    # runs on the startup path.

    try {
        if ([string]::IsNullOrWhiteSpace($Script:ScriptDomPath)) {
            "The ScriptDom install path was never resolved, so the T-SQL parser cannot be installed." | Write-Verbose
            return $false
        }

        $Artifact = Get-LockedArtifact -Id "Microsoft.SqlServer.TransactSql.ScriptDom"

        # Version AND hash, via the same stamp Test-WebView2RuntimeVersion uses for the WebView2
        # assemblies. Trusting the recorded version alone would let a swapped DLL in a user-writable
        # Bin survive indefinitely, because the download that was verified is not the file that would
        # be loaded.
        if (-not $Force.IsPresent -and -not (Test-ScriptDomInstallRequired)) {
            "ScriptDom {0} is already installed and verified at '{1}'" -f $Artifact.Version, $Script:ScriptDomPath | Write-Verbose
            return $true
        }

        "'Microsoft.SqlServer.TransactSql.ScriptDom' version {0} needs to be downloaded. Downloading from NuGet" -f $Artifact.Version | Write-Verbose

        # Downloads from the URL pinned in DependencyLock.psd1 and verifies the bytes against the
        # pinned SHA-256 before returning. A mismatch deletes the file and throws, so nothing below
        # ever sees unverified bytes.
        $TempFile = Invoke-DownloadFile -ArtifactId "Microsoft.SqlServer.TransactSql.ScriptDom"

        $ExpandedPath = $null
        try {
            $ExpandedPath = Expand-DownloadFile -FilePath $TempFile

            # The module is PS7-only (#requires -Version 7.0 in the psm1), so net8.0 is the only
            # target framework in the package worth taking. The netstandard and net472 copies in the
            # same package would load, but net8.0 is the one built for the runtime this module
            # actually runs on.
            $SourceFile = Get-ChildItem -Path $ExpandedPath -Filter "Microsoft.SqlServer.TransactSql.ScriptDom.dll" -Recurse |
                Where-Object { $_.Directory.Name -eq "net8.0" } |
                Select-Object -First 1

            if ($null -eq $SourceFile) {
                "The pinned ScriptDom package contains no net8.0 build of 'Microsoft.SqlServer.TransactSql.ScriptDom.dll'." | Write-Verbose
                return $false
            }

            Copy-Item -Path $SourceFile.FullName -Destination $Script:ScriptDomPath -Force

            Write-ScriptDomStamp

            "Installed 'Microsoft.SqlServer.TransactSql.ScriptDom.dll' version {0}" -f $Artifact.Version | Write-Verbose
        }
        finally {
            if ($null -ne $ExpandedPath -and (Test-Path $ExpandedPath)) {
                Remove-Item -Path $ExpandedPath -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

        return (Test-Path $Script:ScriptDomPath -PathType Leaf)
    }
    catch {
        # Deliberately swallowed. The syntax pass is optional; the caller reports the single WARNING
        # and turns the feature off. Nothing about a failed download here may stop the application.
        "Installing the ScriptDom T-SQL parser failed: {0}" -f $_.Exception.Message | Write-Verbose
        return $false
    }
}
