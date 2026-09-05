function Write-LoadedComponentLog {
    <#
    .SYNOPSIS
    Record which versions of the application's dependencies this session is actually running: the
    OmadaWeb.PS module, and the native/managed assemblies loaded from disk.

    .DESCRIPTION
    Written once at start-up, at INFO, so that any log sent in for diagnosis says what it was
    produced by. Several of the hardest problems in this application depend on exactly this
    information and none of it was in the log before: which OmadaWeb.PS is loaded (its behaviour on
    authentication differs between releases), whether the WebView2 assemblies came from the verified
    bundle or from the download cache, and whether the optional ScriptDom parser is present at all.

    Reports what is loaded and where it came from, not what is pinned - the point is to describe the
    running session, so a mismatch with the lock file is exactly the kind of thing this should make
    visible rather than hide.

    Every lookup is guarded. This is diagnostic output: it must never be the reason the application
    fails to start, and a missing optional component is information, not an error.
    #>
    [CmdLetBinding()]
    param()

    try {
        # --- The application itself -------------------------------------------------------------
        "Application: {0} {1}" -f $Script:RunTimeConfig.ApplicationName, $Script:RunTimeConfig.ApplicationVersion | Write-LogOutput
        "PowerShell: {0} ({1}), {2}" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription | Write-LogOutput -LogType DEBUG

        # --- OmadaWeb.PS --------------------------------------------------------------------------
        # The module the whole transport layer rests on, and the one whose version most often
        # explains a difference in authentication behaviour between two machines.
        $Private:OmadaWeb = Get-Module -Name "OmadaWeb.PS" | Sort-Object Version -Descending | Select-Object -First 1
        if ($null -ne $Private:OmadaWeb) {
            "OmadaWeb.PS: {0} loaded from '{1}'" -f $Private:OmadaWeb.Version, $Private:OmadaWeb.ModuleBase | Write-LogOutput
        }
        else {
            "OmadaWeb.PS: not loaded." | Write-LogOutput -LogType WARNING -SkipDialog
        }

        # --- Assemblies loaded from disk ----------------------------------------------------------
        # Source matters as much as version: WebView2 is either the hash-verified bundle shipped with
        # the module or a download in the user's profile, and which one is in use is not otherwise
        # visible anywhere.
        "WebView2 assemblies resolved from the {0} at '{1}'" -f ([string]$Script:WebView2Source).ToLowerInvariant(), $Script:WebView2BasePath | Write-LogOutput

        $Private:Components = [ordered]@{
            "WebView2.Core"     = $Script:WebView2CorePath
            "WebView2.Wpf"      = $Script:WebView2WpfPath
            "WebView2.WinForms" = $Script:WebView2WinFormsPath
            "WebView2Loader"    = $Script:WebView2LoaderPath
            "ScriptDom"         = $Script:ScriptDomPath
        }

        foreach ($Private:Name in $Private:Components.Keys) {
            Write-LoadedAssemblyLog -Name $Private:Name -Path $Private:Components[$Private:Name]
        }
    }
    catch {
        # Diagnostics must never stop the application starting.
        "Could not record the loaded component versions: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Write-LoadedAssemblyLog {
    <#
    .SYNOPSIS
    Log one assembly's file version and location, or say plainly that it is not there.

    .DESCRIPTION
    Split out so each component is independently guarded: a single unreadable file must not cost the
    log every other component's line.

    The FILE version is reported rather than an assembly identity, because it is what the dependency
    lock pins and what the vendor's release notes quote - and because it can be read without loading
    the assembly, which for a native library like WebView2Loader.dll is not possible anyway.
    #>
    [CmdLetBinding()]
    param(
        [string]$Name,
        [string]$Path
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            "{0}: not configured." -f $Name | Write-LogOutput -LogType DEBUG
            return
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            # DEBUG, not WARNING: ScriptDom is optional and legitimately absent until first use, and
            # a WebView2 file that is genuinely missing fails loudly elsewhere with a better message.
            "{0}: not present at '{1}'." -f $Name, $Path | Write-LogOutput -LogType DEBUG
            return
        }

        $Private:Item = Get-Item -LiteralPath $Path
        $Private:Version = $Private:Item.VersionInfo.FileVersion
        if ([string]::IsNullOrWhiteSpace($Private:Version)) {
            $Private:Version = "unknown version"
        }

        "{0}: {1} ({2:n0} bytes) at '{3}'" -f $Name, $Private:Version, $Private:Item.Length, $Path | Write-LogOutput
    }
    catch {
        "{0}: could not be read at '{1}': {2}" -f $Name, $Path, $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
