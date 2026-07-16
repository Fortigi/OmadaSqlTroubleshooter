#Requires -Version 7.0
<#
.SYNOPSIS
Minimal, admin-free HTTP server that fronts the mock Omada fixture store.

.DESCRIPTION
Uses a raw System.Net.Sockets.TcpListener with just enough HTTP/1.1 to serve the app's requests. This
deliberately avoids System.Net.HttpListener, which needs a URL-ACL reservation (netsh http add urlacl)
or elevation to bind a localhost port - so this "just works" for a normal user on a high port.

Every request is classified and answered by OmadaMockRouter.ps1 (Resolve-OmadaMockResponse), which
reads the response from fixtures/. Requests are simple, come only from the app via Invoke-RestMethod,
and are served one at a time (the app issues them serially on its dispatcher thread).

Dot-source this file for the library functions:
  - Invoke-OmadaMockListenerLoop  : blocking accept/serve loop (used by Start-OmadaMockServer.ps1).
  - New-OmadaMockServerHandle      : start the loop in a background runspace; returns a stop handle.
  - Stop-OmadaMockServerHandle     : stop a handle started above.
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

function Invoke-OmadaMockListenerLoop {
    <#
    .SYNOPSIS
    Blocking accept/serve loop. Stops when $Control.Running becomes $false (polled between accepts).

    .PARAMETER Control
    Optional synchronized hashtable used to signal/observe the server across threads. Keys:
    Running (bool, set $false to stop), Started (bool, set true once listening), Error (last error).
    #>
    [CmdletBinding()]
    param(
        [string]$BindAddress = "127.0.0.1",
        [int]$Port = 8787,
        [string]$FixturesDir,
        [hashtable]$Control
    )

    if ($null -eq $Control) { $Control = @{ Running = $true } }
    $Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($BindAddress), $Port)

    try {
        $Listener.Start()
        # Report the actually-bound port (matters when Port 0 was passed for an OS-assigned free port).
        $Control.Port = ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
        $Control.Started = $true
        while ($Control.Running) {
            if (-not $Listener.Pending()) {
                Start-Sleep -Milliseconds 20
                continue
            }
            $Client = $Listener.AcceptTcpClient()
            try {
                $Client.ReceiveTimeout = 5000
                $Client.SendTimeout = 5000
                $Stream = $Client.GetStream()
                $Request = Read-OmadaMockHttpRequest -Stream $Stream
                if ($null -ne $Request) {
                    $Response = Resolve-OmadaMockResponse -Path $Request.Path -Method $Request.Method -Body $Request.Body -FixturesDir $Dir
                    Write-OmadaMockHttpResponse -Stream $Stream -Response $Response
                }
            }
            catch {
                $Control.Error = $_.Exception.Message
            }
            finally {
                $Client.Close()
            }
        }
    }
    finally {
        try { $Listener.Stop() } catch { }
        $Control.Started = $false
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
        [int]$StartTimeoutSeconds = 10
    )

    $Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    $RouterPath = Join-Path $PSScriptRoot "OmadaMockRouter.ps1"
    $ServerPath = Join-Path $PSScriptRoot "OmadaMockServer.ps1"
    $Control = [hashtable]::Synchronized(@{ Running = $true; Started = $false; Error = $null })

    $Runspace = [runspacefactory]::CreateRunspace()
    $Runspace.ApartmentState = "MTA"
    $Runspace.ThreadOptions = "ReuseThread"
    $Runspace.Open()

    $Shell = [powershell]::Create()
    $Shell.Runspace = $Runspace
    [void]$Shell.AddScript({
            param($RouterPath, $ServerPath, $BindAddress, $Port, $Dir, $Control)
            . $RouterPath
            . $ServerPath
            Invoke-OmadaMockListenerLoop -BindAddress $BindAddress -Port $Port -FixturesDir $Dir -Control $Control
        }).AddArgument($RouterPath).AddArgument($ServerPath).AddArgument($BindAddress).AddArgument($Port).AddArgument($Dir).AddArgument($Control)
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
