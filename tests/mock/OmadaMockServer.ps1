#Requires -Version 7.0
<#
.SYNOPSIS
Minimal, admin-free HTTP server that fronts the mock Omada fixture store.

.DESCRIPTION
Uses a raw System.Net.Sockets.TcpListener with just enough HTTP/1.1 to serve the app's requests. This
deliberately avoids System.Net.HttpListener, which needs a URL-ACL reservation (netsh http add urlacl)
or elevation to bind a localhost port - so this "just works" for a normal user on a high port.

Every request is classified and answered by OmadaMockRouter.ps1 (Resolve-OmadaMockResponse), which
reads the response from fixtures/.

Requests are served CONCURRENTLY: the accept loop hands each client to one of a fixed set of worker
runspaces. This used to serve one client at a time, which was fine while the app issued every request
serially on its dispatcher thread - but the app now executes requests off that thread, so a test for
"two tabs executing at once" needs two slow requests to genuinely overlap rather than queue behind
each other. With a serial server such a test would pass (or time out) for the wrong reason.

A response can also be delayed on purpose, which is what makes "long-running query" testable at all:
per route via "delayMs" in routes.json, or live via Set-OmadaMockRouteDelay on a running handle. The
sleep happens in the worker just before the response is written, so it is felt by the client as a slow
socket - the real Invoke-RestMethod path - not as a fake pause inside a shim.

Dot-source this file for the library functions:
  - Invoke-OmadaMockListenerLoop  : blocking accept loop + worker pool (Start-OmadaMockServer.ps1).
  - Invoke-OmadaMockWorkerLoop    : one worker's dequeue/serve loop (runs in a worker runspace).
  - Invoke-OmadaMockClientRequest : serve exactly one accepted client.
  - New-OmadaMockServerHandle     : start the loop in a background runspace; returns a stop handle.
  - Stop-OmadaMockServerHandle    : stop a handle started above.
  - Set-OmadaMockRouteDelay / Clear-OmadaMockRouteDelay : the live per-route delay knob.
Nothing runs on load. OmadaMockRouter.ps1 must be dot-sourced first (or alongside).
#>

function Get-OmadaMockReasonPhrase {
    [CmdletBinding()]
    param([int]$StatusCode)
    switch ($StatusCode) {
        200 { "OK" }
        201 { "Created" }
        204 { "No Content" }
        400 { "Bad Request" }
        401 { "Unauthorized" }
        403 { "Forbidden" }
        404 { "Not Found" }
        500 { "Internal Server Error" }
        default { "OK" }
    }
}

function Find-OmadaMockHeaderEnd {
    <# Index of the CRLFCRLF that ends the header block, or -1 if not yet present. #>
    [CmdletBinding()]
    param([System.Collections.Generic.List[byte]]$Buffer)
    for ($i = 0; $i -le $Buffer.Count - 4; $i++) {
        if ($Buffer[$i] -eq 13 -and $Buffer[$i + 1] -eq 10 -and $Buffer[$i + 2] -eq 13 -and $Buffer[$i + 3] -eq 10) {
            return $i
        }
    }
    return -1
}

function Read-OmadaMockHttpRequest {
    <# Read one HTTP/1.1 request from a stream. Returns @{ Method; Path; Body } or $null. #>
    [CmdletBinding()]
    param([System.IO.Stream]$Stream)

    $Buffer = [System.Collections.Generic.List[byte]]::new()
    $Chunk = [byte[]]::new(8192)
    $HeaderEnd = -1

    while ($true) {
        $Read = $Stream.Read($Chunk, 0, $Chunk.Length)
        if ($Read -le 0) { break }
        $Buffer.AddRange([byte[]]($Chunk[0..($Read - 1)]))
        $HeaderEnd = Find-OmadaMockHeaderEnd -Buffer $Buffer
        if ($HeaderEnd -ge 0) { break }
        if ($Buffer.Count -gt 4MB) { break }
    }
    if ($HeaderEnd -lt 0) { return $null }

    $HeaderText = [System.Text.Encoding]::ASCII.GetString($Buffer.GetRange(0, $HeaderEnd).ToArray())
    $Lines = $HeaderText -split "`r`n"
    if ($Lines.Count -lt 1 -or [string]::IsNullOrWhiteSpace($Lines[0])) { return $null }

    $RequestParts = $Lines[0] -split '\s+'
    if ($RequestParts.Count -lt 2) { return $null }
    $Method = $RequestParts[0]
    $Path = $RequestParts[1]

    $ContentLength = 0
    for ($i = 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^(?i)content-length\s*:\s*(\d+)\s*$') {
            $ContentLength = [int]$Matches[1]
            break
        }
    }

    $BodyBytes = [System.Collections.Generic.List[byte]]::new()
    $BodyStart = $HeaderEnd + 4
    if ($Buffer.Count -gt $BodyStart) {
        $BodyBytes.AddRange($Buffer.GetRange($BodyStart, $Buffer.Count - $BodyStart))
    }
    while ($BodyBytes.Count -lt $ContentLength) {
        $Read = $Stream.Read($Chunk, 0, [Math]::Min($Chunk.Length, $ContentLength - $BodyBytes.Count))
        if ($Read -le 0) { break }
        $BodyBytes.AddRange([byte[]]($Chunk[0..($Read - 1)]))
    }

    $Body = if ($BodyBytes.Count -gt 0) { [System.Text.Encoding]::UTF8.GetString($BodyBytes.ToArray()) } else { $null }
    return @{ Method = $Method; Path = $Path; Body = $Body }
}

function Write-OmadaMockHttpResponse {
    [CmdletBinding()]
    param([System.IO.Stream]$Stream, [hashtable]$Response)

    $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Response.Body)
    $StatusCode = [int]$Response.StatusCode
    $Reason = Get-OmadaMockReasonPhrase -StatusCode $StatusCode

    $Head = [System.Text.StringBuilder]::new()
    [void]$Head.Append("HTTP/1.1 $StatusCode $Reason`r`n")
    [void]$Head.Append("Content-Type: $($Response.ContentType)`r`n")
    [void]$Head.Append("Content-Length: $($BodyBytes.Length)`r`n")
    [void]$Head.Append("Cache-Control: no-store`r`n")
    [void]$Head.Append("Connection: close`r`n")
    [void]$Head.Append("`r`n")

    $HeadBytes = [System.Text.Encoding]::ASCII.GetBytes($Head.ToString())
    $Stream.Write($HeadBytes, 0, $HeadBytes.Length)
    if ($BodyBytes.Length -gt 0) { $Stream.Write($BodyBytes, 0, $BodyBytes.Length) }
    $Stream.Flush()
}

function Get-OmadaMockEffectiveDelayMs {
    <#
    .SYNOPSIS
    How long this response should be held before it is written: the live override for the route if one
    is set, otherwise whatever the manifest declared.

    .DESCRIPTION
    Two sources, in this order:
      1. $Control.RouteDelays[<routeKey>] - set through Set-OmadaMockRouteDelay on a running handle.
         A "*" key applies to every route, which is how a test slows the whole instance in one call.
      2. $Response.DelayMs - the route's "delayMs" in routes.json.
    The live override wins so a test can slow one route without editing (and having to restore) the
    shared fixture manifest.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Response,
        [hashtable]$Control
    )

    if ($null -ne $Control -and $null -ne $Control.RouteDelays) {
        $RouteKey = [string]$Response.RouteKey
        # Read into a local first: another thread may clear the table between the check and the read.
        $Override = $Control.RouteDelays[$RouteKey]
        if ($null -eq $Override) { $Override = $Control.RouteDelays["*"] }
        if ($null -ne $Override) { return [Math]::Max(0, [int]$Override) }
    }
    if ($null -ne $Response -and $null -ne $Response.DelayMs) {
        return [Math]::Max(0, [int]$Response.DelayMs)
    }
    return 0
}

function Invoke-OmadaMockClientRequest {
    <#
    .SYNOPSIS
    Read one request off an accepted client, resolve it, honour its delay, write the response, close.

    .DESCRIPTION
    Split out of the accept loop so the same serving logic runs whether it is called from a worker
    runspace or directly from a test. Errors are recorded on $Control rather than thrown: one bad
    client must not take the server down for the others.
    #>
    [CmdletBinding()]
    param(
        [System.Net.Sockets.TcpClient]$Client,
        [string]$FixturesDir,
        [hashtable]$Control
    )

    try {
        $Client.ReceiveTimeout = 5000
        $Client.SendTimeout = 5000
        $Stream = $Client.GetStream()
        $Request = Read-OmadaMockHttpRequest -Stream $Stream
        if ($null -ne $Request) {
            $Response = Resolve-OmadaMockResponse -Path $Request.Path -Method $Request.Method -Body $Request.Body -FixturesDir $FixturesDir
            $DelayMs = Get-OmadaMockEffectiveDelayMs -Response $Response -Control $Control
            if ($DelayMs -gt 0) {
                # Deliberately AFTER the fixture is resolved and BEFORE anything is written, so the
                # client sees a slow server rather than a slow trickle of bytes - the shape a real
                # long-running Omada query has.
                #
                # Slept in slices rather than in one Start-Sleep so a stop request is honoured
                # promptly: Stop-OmadaMockServerHandle ends up in EndInvoke, which blocks until the
                # workers return, and a worker parked in a single multi-second sleep would hold the
                # whole shutdown for the length of the delay a test had just set.
                $Deadline = [DateTime]::UtcNow.AddMilliseconds($DelayMs)
                while ([DateTime]::UtcNow -lt $Deadline -and (($null -eq $Control) -or $Control.Running)) {
                    Start-Sleep -Milliseconds 25
                }
            }
            Write-OmadaMockHttpResponse -Stream $Stream -Response $Response
        }
    }
    catch {
        if ($null -ne $Control) { $Control.Error = $_.Exception.Message }
    }
    finally {
        try { $Client.Close() } catch { }
    }
}

function Invoke-OmadaMockWorkerLoop {
    <#
    .SYNOPSIS
    One worker's loop: take accepted clients off the shared queue and serve them until told to stop.

    .PARAMETER Queue
    The ConcurrentQueue[TcpClient] the accept loop feeds.
    #>
    [CmdletBinding()]
    param(
        $Queue,
        [string]$FixturesDir,
        [hashtable]$Control
    )

    $Client = $null
    while ($Control.Running) {
        if ($Queue.TryDequeue([ref]$Client)) {
            Invoke-OmadaMockClientRequest -Client $Client -FixturesDir $FixturesDir -Control $Control
        }
        else {
            Start-Sleep -Milliseconds 5
        }
    }

    # Shutting down: close anything still queued rather than leaving a client hanging on a socket that
    # will never be answered - an unanswered client blocks its test until the request timeout instead.
    while ($Queue.TryDequeue([ref]$Client)) {
        try { $Client.Close() } catch { }
    }
}

function Invoke-OmadaMockListenerLoop {
    <#
    .SYNOPSIS
    Blocking accept loop feeding a fixed pool of worker runspaces. Stops when $Control.Running becomes
    $false (polled between accepts).

    .DESCRIPTION
    The accept loop itself does no I/O beyond AcceptTcpClient, so a slow (delayed) response can never
    stall the acceptance of the next connection - which is what lets two concurrent requests actually
    overlap. Serving happens on $WorkerCount worker runspaces, each of which dot-sources the router and
    this file once and then loops.

    .PARAMETER Control
    Optional synchronized hashtable used to signal/observe the server across threads. Keys:
    Running (bool, set $false to stop), Started (bool, set true once listening), Error (last error),
    Port (the actually-bound port), RouteDelays (route key -> delay in ms; "*" for all routes).

    .PARAMETER WorkerCount
    How many requests may be in flight at once. The default of 4 covers the app's tab capacity of
    concurrent executes with room to spare; a value below 1 is raised to 1.
    #>
    [CmdletBinding()]
    param(
        [string]$BindAddress = "127.0.0.1",
        [int]$Port = 8787,
        [string]$FixturesDir,
        [hashtable]$Control,
        [int]$WorkerCount = 4
    )

    if ($null -eq $Control) { $Control = [hashtable]::Synchronized(@{ Running = $true }) }

    # Serving is concurrent now, so the accept loop and every worker touch $Control at the same time -
    # and a plain System.Collections.Hashtable is not safe under that. Callers are asked for a
    # synchronized table, but wrap one that is not rather than trusting them: Hashtable.Synchronized
    # returns a locking wrapper over the SAME storage, so a caller holding the original still sees
    # every write (verified) and nothing is lost by being defensive here.
    if (-not $Control.IsSynchronized) { $Control = [hashtable]::Synchronized($Control) }
    if ($null -eq $Control.RouteDelays) { $Control.RouteDelays = [hashtable]::Synchronized(@{}) }
    elseif (-not $Control.RouteDelays.IsSynchronized) { $Control.RouteDelays = [hashtable]::Synchronized($Control.RouteDelays) }

    if ($WorkerCount -lt 1) { $WorkerCount = 1 }

    $Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    $Queue = [System.Collections.Concurrent.ConcurrentQueue[System.Net.Sockets.TcpClient]]::new()
    $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($BindAddress), $Port)

    $RouterPath = Join-Path $PSScriptRoot "OmadaMockRouter.ps1"
    $ServerPath = Join-Path $PSScriptRoot "OmadaMockServer.ps1"
    $Workers = [System.Collections.Generic.List[object]]::new()

    try {
        $Listener.Start()
        # Report the actually-bound port (matters when Port 0 was passed for an OS-assigned free port).
        $Control.Port = ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port

        for ($Index = 0; $Index -lt $WorkerCount; $Index++) {
            $WorkerShell = [powershell]::Create()
            [void]$WorkerShell.AddScript({
                    param($RouterPath, $ServerPath, $Queue, $Dir, $Control)
                    . $RouterPath
                    . $ServerPath
                    Invoke-OmadaMockWorkerLoop -Queue $Queue -FixturesDir $Dir -Control $Control
                }).AddArgument($RouterPath).AddArgument($ServerPath).AddArgument($Queue).AddArgument($Dir).AddArgument($Control)
            $Workers.Add([pscustomobject]@{ Shell = $WorkerShell; Async = $WorkerShell.BeginInvoke() })
        }

        # Only now: a client that connects the instant Started flips must find a worker ready for it.
        $Control.Started = $true

        while ($Control.Running) {
            if (-not $Listener.Pending()) {
                Start-Sleep -Milliseconds 20
                continue
            }
            $Queue.Enqueue($Listener.AcceptTcpClient())
        }
    }
    finally {
        try { $Listener.Stop() } catch { }
        # $Control.Running is already $false on the normal stop path; force it so the workers also exit
        # when this loop leaves because it threw.
        $Control.Running = $false
        foreach ($Worker in $Workers) {
            try { $Worker.Shell.EndInvoke($Worker.Async) } catch { }
            try { $Worker.Shell.Dispose() } catch { }
        }
        $Control.Started = $false
    }
}

function Set-OmadaMockRouteDelay {
    <#
    .SYNOPSIS
    Make a running mock answer one route (or every route, with -RouteKey "*") slowly.

    .DESCRIPTION
    The knob a test uses to create a genuinely long-running request. It writes into the handle's
    synchronized control table, which the serving workers read per request, so it takes effect
    immediately and needs no restart. Clear it with Clear-OmadaMockRouteDelay.

    .EXAMPLE
    Set-OmadaMockRouteDelay -Handle $Handle -RouteKey "paging.sqldataproducer" -DelayMs 5000
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Handle,
        [Parameter(Mandatory)][string]$RouteKey,
        [Parameter(Mandatory)][int]$DelayMs
    )
    if ($null -eq $Handle.Control.RouteDelays) {
        $Handle.Control.RouteDelays = [hashtable]::Synchronized(@{})
    }
    $Handle.Control.RouteDelays[$RouteKey] = [Math]::Max(0, $DelayMs)
}

function Clear-OmadaMockRouteDelay {
    <#
    .SYNOPSIS
    Remove one route's live delay override, or all of them when -RouteKey is omitted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Handle,
        [string]$RouteKey
    )
    if ($null -eq $Handle.Control.RouteDelays) { return }
    if ([string]::IsNullOrWhiteSpace($RouteKey)) {
        $Handle.Control.RouteDelays.Clear()
    }
    else {
        $Handle.Control.RouteDelays.Remove($RouteKey)
    }
}

function New-OmadaMockServerHandle {
    <#
    .SYNOPSIS
    Start the mock server in a background runspace and return a handle. Use Stop-OmadaMockServerHandle
    to shut it down. Blocks until the listener is accepting (or throws on startup failure/timeout).
    #>
    [CmdletBinding()]
    param(
        [string]$BindAddress = "127.0.0.1",
        [int]$Port = 8787,
        [string]$FixturesDir,
        [int]$StartTimeoutSeconds = 10,
        [int]$WorkerCount = 4
    )

    $Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    $RouterPath = Join-Path $PSScriptRoot "OmadaMockRouter.ps1"
    $ServerPath = Join-Path $PSScriptRoot "OmadaMockServer.ps1"
    # RouteDelays is created here, not in the listener loop, so Set-OmadaMockRouteDelay can be called
    # against the returned handle from this runspace and be seen by the workers in theirs.
    $Control = [hashtable]::Synchronized(@{
            Running     = $true
            Started     = $false
            Error       = $null
            RouteDelays = [hashtable]::Synchronized(@{})
        })

    $Runspace = [runspacefactory]::CreateRunspace()
    $Runspace.ApartmentState = "MTA"
    $Runspace.ThreadOptions = "ReuseThread"
    $Runspace.Open()

    $Shell = [powershell]::Create()
    $Shell.Runspace = $Runspace
    [void]$Shell.AddScript({
            param($RouterPath, $ServerPath, $BindAddress, $Port, $Dir, $Control, $WorkerCount)
            . $RouterPath
            . $ServerPath
            Invoke-OmadaMockListenerLoop -BindAddress $BindAddress -Port $Port -FixturesDir $Dir -Control $Control -WorkerCount $WorkerCount
        }).AddArgument($RouterPath).AddArgument($ServerPath).AddArgument($BindAddress).AddArgument($Port).AddArgument($Dir).AddArgument($Control).AddArgument($WorkerCount)
    $Async = $Shell.BeginInvoke()

    $Deadline = [DateTime]::UtcNow.AddSeconds($StartTimeoutSeconds)
    while (-not $Control.Started -and [DateTime]::UtcNow -lt $Deadline) {
        if ($Async.IsCompleted) { break }   # the loop returned/threw before it started listening
        Start-Sleep -Milliseconds 25
    }
    if (-not $Control.Started) {
        $ErrMessage = if ($Control.Error) { $Control.Error } else { "listener did not start within $StartTimeoutSeconds s" }
        try { $Shell.EndInvoke($Async) } catch { $ErrMessage = $_.Exception.Message }
        $Shell.Dispose(); $Runspace.Dispose()
        throw "Failed to start mock server on ${BindAddress}:${Port} - $ErrMessage"
    }

    $BoundPort = [int]$Control.Port
    return [pscustomobject]@{
        BindAddress = $BindAddress
        Port        = $BoundPort
        BaseUrl     = "http://${BindAddress}:${BoundPort}"
        FixturesDir = $Dir
        Control     = $Control
        PowerShell  = $Shell
        Async       = $Async
        Runspace    = $Runspace
    }
}

function Stop-OmadaMockServerHandle {
    <# Stop a handle from New-OmadaMockServerHandle and clean up its runspace. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Handle,
        [int]$StopTimeoutSeconds = 5
    )
    if ($null -eq $Handle) { return }
    $Handle.Control.Running = $false

    $Deadline = [DateTime]::UtcNow.AddSeconds($StopTimeoutSeconds)
    while (-not $Handle.Async.IsCompleted -and [DateTime]::UtcNow -lt $Deadline) {
        Start-Sleep -Milliseconds 25
    }
    try { $Handle.PowerShell.EndInvoke($Handle.Async) } catch { }
    try { $Handle.PowerShell.Dispose() } catch { }
    try { $Handle.Runspace.Dispose() } catch { }
}
