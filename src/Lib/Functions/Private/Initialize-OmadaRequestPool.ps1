function Initialize-OmadaRequestPool {
    <#
    .SYNOPSIS
    Open (once) the runspace pool that background Omada requests run in, and return it.

    .DESCRIPTION
    Issue #40: an Omada round-trip must not block the WPF UI thread. The workers live in a pool
    rather than being created per request, because each one has to Import-Module OmadaWeb.PS and
    that is not free - the module resolves and loads WebView2 assemblies on import. A pool with a
    warmed InitialSessionState pays that once per worker, not once per query.

    Called lazily from Start-OmadaBackgroundRequest, so a session that never issues a background
    request never opens a pool at all, and a failure to open one is a fallback to synchronous
    execution rather than a failure to start the app.

    .NOTES
    The workers are MTA, deliberately, and that is the enforcement half of this application's
    background authentication policy.

    OmadaWeb.PS authenticates by opening a WinForms modal (Start-WebView2Login calls
    $Script:WinForm.ShowDialog()), on whatever thread calls it. WinForms and WebView2 need STA. A
    worker that could show that dialog would show it with NO owner window: not modal to this app,
    possibly behind the main window, while the main window stays fully interactive - so the user can
    start a second execute on another tab while an invisible login prompt waits. That is a worse
    failure than not authenticating at all.

    Making the workers MTA means an attempted interactive login in a worker FAILS instead of
    prompting. Combined with Test-OmadaBackgroundRequestEligible, which only dispatches for a tab
    that already authenticated on the UI thread, the policy is: interactive authentication happens
    on the UI thread or it does not happen. An already-authenticated request touches none of that
    path - it is Invoke-RestMethod against a cookie OmadaWeb.PS loads from its encrypted on-disk
    cache - so MTA costs it nothing.

    (The mock server's own background runspace, tests/mock/OmadaMockServer.ps1, is MTA for unrelated
    reasons; this is not that precedent being copied, it is the same conclusion reached separately.)

    .OUTPUTS
    The open RunspacePool, or $null when one could not be opened.
    #>
    [CmdletBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if ($null -ne $Script:OmadaRequestPool -and $Script:OmadaRequestPool.RunspacePoolStateInfo.State -eq [System.Management.Automation.Runspaces.RunspacePoolState]::Opened) {
            return $Script:OmadaRequestPool
        }

        # Sized to the tab capacity so every tab can have a request in flight at once - the
        # "two tabs executing concurrently" criterion of issue #40 - with a floor of 2 so a
        # misconfigured capacity cannot serialize everything.
        $Private:MaxWorkers = if ($null -ne $Script:AppGlobalConfig -and $Script:AppGlobalConfig.TabCapacity -gt 0) { [int]$Script:AppGlobalConfig.TabCapacity } else { 8 }
        if ($Private:MaxWorkers -lt 2) { $Private:MaxWorkers = 2 }

        $Private:SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $Private:SessionState.ApartmentState = [System.Threading.ApartmentState]::MTA
        $Private:SessionState.ImportPSModule("OmadaWeb.PS")

        $Private:Pool = [runspacefactory]::CreateRunspacePool(1, $Private:MaxWorkers, $Private:SessionState, $Host)
        $Private:Pool.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $Private:Pool.Open()

        $Script:OmadaRequestPool = $Private:Pool
        "Background request pool opened with up to {0} worker(s)." -f $Private:MaxWorkers | Write-LogOutput -LogType DEBUG
        return $Script:OmadaRequestPool
    }
    catch {
        # Never fatal. Every caller falls back to running the request synchronously, which is exactly
        # what the app did before issue #40 - slower, but correct.
        #
        # The half-built pool is disposed first. CreateRunspacePool can succeed and Open() still
        # throw, and the pool holds worker threads from the moment it is created - so returning
        # without disposing leaks them for the life of the process, on a path the app is otherwise
        # designed to survive and retry.
        if ($null -ne $Private:Pool) {
            try { $Private:Pool.Dispose() } catch { }
        }
        "Could not open the background request pool; requests will run on the UI thread. {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        $Script:OmadaRequestPool = $null
        return $null
    }
}

function Close-OmadaRequestPool {
    <#
    .SYNOPSIS
    Close and dispose the background request pool. Called when the main window closes.

    .DESCRIPTION
    Left open, the pool's worker threads keep the process alive after the window has gone. Closing is
    best-effort and never throws: this runs on the shutdown path, where a failure here would be far
    more disruptive than a leaked runspace in a process that is exiting anyway.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $Script:OmadaRequestPool) {
        return
    }

    try { $Script:OmadaRequestPool.Close() } catch { }
    try { $Script:OmadaRequestPool.Dispose() } catch { }
    $Script:OmadaRequestPool = $null
}
