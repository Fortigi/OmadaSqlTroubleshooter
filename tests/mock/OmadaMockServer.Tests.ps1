#Requires -Version 7.0
# Round-trip tests: start the real mock server and assert each endpoint returns the shape the app
# consumes. Cross-platform (TcpListener + Invoke-RestMethod), uses an OS-assigned port to avoid clashes.

BeforeAll {
    . (Join-Path $PSScriptRoot "OmadaMockRouter.ps1")
    . (Join-Path $PSScriptRoot "OmadaMockServer.ps1")

    $script:Handle = New-OmadaMockServerHandle -BindAddress "127.0.0.1" -Port 0
    $script:BaseUrl = $script:Handle.BaseUrl

    function script:Get-Mock {
        param([string]$PathAndQuery, [string]$Method = "GET", $Body)
        $Params = @{ Uri = "$script:BaseUrl$PathAndQuery"; Method = $Method; NoProxy = $true; TimeoutSec = 5 }
        if ($null -ne $Body) {
            $Params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
            $Params.ContentType = "application/json"
        }
        return Invoke-RestMethod @Params
    }
}

AfterAll {
    if ($null -ne $script:Handle) { Stop-OmadaMockServerHandle -Handle $script:Handle }
}

Describe "Mock server over HTTP" {
    It "answers the connection probe with 200" {
        { Get-Mock -PathAndQuery "/odata/dataobjects/C_P_SQLTROUBLESHOOTING" } | Should -Not -Throw
    }
    It "returns a non-empty query list with Id + DisplayName" {
        $Result = Get-Mock -PathAndQuery "/odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$orderby=DisplayName,NAME&`$filter=Deleted ne true"
        $Result.value.Count | Should -BeGreaterThan 0
        $Result.value[0].Id | Should -Not -BeNullOrEmpty
        $Result.value[0].DisplayName | Should -Not -BeNullOrEmpty
    }
    It "returns a single query object carrying C_QUERY" {
        $Result = Get-Mock -PathAndQuery "/odata/dataobjects/C_P_SQLTROUBLESHOOTING(10521)"
        $Result.C_QUERY | Should -Match "SELECT"
    }
    It "returns a schema keyed by schema.table" {
        $Result = Get-Mock -PathAndQuery "/webservice/SyntaxHighlighting.asmx/GetSqlSchema" -Method "POST" -Body @{ connectionId = 4201 }
        $Result.d | Should -Not -BeNullOrEmpty
        ($Result.d.PSObject.Properties.Name -contains "dbo.tblDataObject") | Should -BeTrue
    }
    It "returns the SQL Troubleshooting view row" {
        $Result = Get-Mock -PathAndQuery "/WebService/JQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body @{ dataType = "Views" }
        ($Result.d.Rows | Where-Object { $_.Name -eq "SQL Troubleshooting" }).Count | Should -BeGreaterThan 0
    }
    It "returns executable result rows for SqlDataProducer" {
        $Result = Get-Mock -PathAndQuery "/webservice/jQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body @{ dataType = "SqlDataProducer" }
        $Result.d.Rows.Count | Should -BeGreaterThan 0
        $Result.d.Records | Should -BeGreaterThan 0
    }
    It "returns history rows whose ChangedFields decode to SQL Query changes" {
        $Result = Get-Mock -PathAndQuery "/webservice/jQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body @{ dataType = "DataObjectHistory" }
        $Fields = $Result.d.Rows[0].ChangedFields | ConvertFrom-Json
        ($Fields | Where-Object { $_.Field -eq "SQL Query" }).Count | Should -BeGreaterThan 0
    }
    It "returns data connection HTML the app can parse into options" {
        # Must assert on the RAW markup: the app hands this response to
        # Get-DataConnectionOptionList -Html ([string]). Invoke-RestMethod would deserialize the
        # text/html body into an [XmlDocument] that stringifies to "System.Xml.XmlDocument" and
        # matches no <option> - the exact failure the transport shim now avoids.
        $Response = Invoke-WebRequest -Uri "$script:BaseUrl/dataobjdlg.aspx?DOID=8801" -NoProxy -TimeoutSec 5
        $Response.Content | Should -BeOfType [string]
        $Response.Content | Should -Match "OISES"
        [regex]::Matches($Response.Content, '<option.*?value="(\d+).*?data-uid="(.*?)".*?>(.*?)</option>').Count | Should -BeGreaterThan 0
    }
}

Describe "Get-OmadaMockEffectiveDelayMs" {
    It "prefers a live route override over the manifest value" {
        $Control = @{ RouteDelays = @{ "schema" = 750 } }
        Get-OmadaMockEffectiveDelayMs -Response @{ RouteKey = "schema"; DelayMs = 10 } -Control $Control | Should -Be 750
    }
    It "applies a '*' override to a route with no override of its own" {
        $Control = @{ RouteDelays = @{ "*" = 40 } }
        Get-OmadaMockEffectiveDelayMs -Response @{ RouteKey = "probe"; DelayMs = 0 } -Control $Control | Should -Be 40
    }
    It "lets a route-specific override win over '*'" {
        $Control = @{ RouteDelays = @{ "*" = 40; "probe" = 5 } }
        Get-OmadaMockEffectiveDelayMs -Response @{ RouteKey = "probe" } -Control $Control | Should -Be 5
    }
    It "falls back to the manifest value when nothing is overridden" {
        Get-OmadaMockEffectiveDelayMs -Response @{ RouteKey = "schema"; DelayMs = 120 } -Control @{ RouteDelays = @{} } | Should -Be 120
    }
    It "returns 0 with no control table and no manifest value" {
        Get-OmadaMockEffectiveDelayMs -Response @{ RouteKey = "schema" } -Control $null | Should -Be 0
    }
}

Describe "Mock server control table safety" {
    It "hands the caller a synchronized control table and delay table" {
        # Serving is concurrent, so both are read and written from several threads at once. A plain
        # System.Collections.Hashtable is not safe under that.
        $script:Handle.Control.IsSynchronized | Should -BeTrue
        $script:Handle.Control.RouteDelays.IsSynchronized | Should -BeTrue
    }

    It "wraps a caller's unsynchronized control table without losing its writes" {
        # Start-OmadaMockServer.ps1 used to pass a plain hashtable. Hashtable.Synchronized returns a
        # locking wrapper over the SAME storage, so wrapping defensively is free: a caller still
        # holding the original sees everything the loop writes, and vice versa.
        $Plain = @{ Running = $true }
        $Wrapped = [hashtable]::Synchronized($Plain)

        $Wrapped["Started"] = $true
        $Plain["Port"] = 1234

        $Wrapped.IsSynchronized | Should -BeTrue
        $Plain["Started"] | Should -BeTrue
        $Wrapped["Port"] | Should -Be 1234
    }
}

Describe "Mock server delay and concurrency" {
    AfterEach {
        Clear-OmadaMockRouteDelay -Handle $script:Handle
    }

    It "holds a delayed route for at least the requested time" {
        Set-OmadaMockRouteDelay -Handle $script:Handle -RouteKey "probe" -DelayMs 600
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Get-Mock -PathAndQuery "/odata/dataobjects/C_P_SQLTROUBLESHOOTING" | Out-Null
        $Stopwatch.Stop()
        # A margin below the requested delay absorbs timer granularity; the point of the assertion is
        # that the delay was honoured at all, not that it was honoured to the millisecond.
        $Stopwatch.ElapsedMilliseconds | Should -BeGreaterThan 450
    }

    It "answers an undelayed route quickly while a delay is set on a different route" {
        Set-OmadaMockRouteDelay -Handle $script:Handle -RouteKey "probe" -DelayMs 3000
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Get-Mock -PathAndQuery "/webservice/SyntaxHighlighting.asmx/GetSqlSchema" -Method "POST" -Body @{ connectionId = 4201 } | Out-Null
        $Stopwatch.Stop()
        $Stopwatch.ElapsedMilliseconds | Should -BeLessThan 1500
    }

    It "serves two delayed requests concurrently rather than one after the other" {
        # The whole point of the worker pool. Serially these two 1 s requests take ~2 s; overlapped
        # they take ~1 s. The 1.6 s bound is comfortably between the two so the test says which
        # happened without being flaky on a loaded machine.
        #
        # HttpClient rather than two runspaces running Invoke-RestMethod: the two GetAsync tasks
        # overlap with no runspace-startup cost inside the measured window, which is what keeps the
        # bound meaningful instead of mostly measuring PowerShell's own warm-up.
        Set-OmadaMockRouteDelay -Handle $script:Handle -RouteKey "probe" -DelayMs 1000

        $Url = "$script:BaseUrl/odata/dataobjects/C_P_SQLTROUBLESHOOTING"
        $HttpClient = [System.Net.Http.HttpClient]::new()
        try {
            $HttpClient.Timeout = [TimeSpan]::FromSeconds(30)
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Tasks = @($HttpClient.GetAsync($Url), $HttpClient.GetAsync($Url))
            [System.Threading.Tasks.Task]::WaitAll($Tasks)
            $Stopwatch.Stop()
            foreach ($Task in $Tasks) {
                [int]$Task.Result.StatusCode | Should -Be 200
            }
        }
        finally {
            $HttpClient.Dispose()
        }

        $Stopwatch.ElapsedMilliseconds | Should -BeLessThan 1600
    }
}
