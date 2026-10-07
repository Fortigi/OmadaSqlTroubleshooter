#Requires -Version 7.0
# Issue #165. The ODW ingestion probe: one page read per connection pool, cached, three-state.
#
# What is asserted here is the DECISION-MAKING, not the parsing - ConvertFrom-OmadaAppPageVars has its
# own suite. Three things in particular, because each is a way this feature could go quietly wrong:
#
#   * a probe that ran for a disconnected tab would authenticate behind -NoReconnect (issue #64);
#   * a probe whose FAILURE was cached would refuse to filter for the rest of the session;
#   * a filter that treated "not known" as "off" is correct, but one that treated it as "on" would hide
#     databases the user needs.
#
# ConvertFrom-OmadaAppPageVars is loaded for real rather than stubbed: the contract between the probe
# and the parser is "is the flag present, and is it true", and a stub would let the two drift.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertFrom-OmadaAppPageVars.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaIngestionSetting.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    function Write-ContainedErrorLog {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, $ErrorObject)
        process { }
    }

    function ConvertTo-RedactedLogString { param($InputObject, $MaxDepth, [switch]$ShapeOnly) return "<redacted>" }
    function Test-ConnectionRequirements { return $script:ConnectionReady }

    # The prune that the completion triggers. Recorded, not performed: it touches WPF.
    function Remove-FilteredDataConnectionItem { $script:PruneCalls++ }

    # Dispatch, stubbed. $null models "not dispatched", which is what sends the probe down the inline
    # path - the fallback that is acceptable here precisely because it is ONE request.
    function Invoke-OmadaPSWebRequestWrapperAsync {
        param([scriptblock]$OnResultScriptBlock, $Context, [hashtable]$PipelineContext, [string]$Description)

        $script:Dispatched += [pscustomobject]@{
            Description = $Description
            Context     = $Context
            OnResult    = $OnResultScriptBlock
        }

        return $script:DispatchResult
    }

    function Invoke-OmadaPSWebRequestWrapper {
        $script:InlineCalls++
        return $script:InlinePage
    }

    $Script:PageWithFlag = "appPageVars={customerId: 1000,isIngestionEnabled: true,isOISaaS: true}"
    $Script:PageWithoutFlag = "appPageVars={customerId: 1000,isOISaaS: true}"

    function script:Reset-ProbeState {
        param([string]$SessionKey = "session-a")

        $Script:OmadaIngestionSettingCache = @{}
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $Script:ConnectionStatus = $true
        $Script:AppConfig = [pscustomobject]@{ BaseUrl = "https://tenant.example" }
        $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test" }
        $Script:RunTimeData = [pscustomobject]@{
            RestMethodParam = @{ SessionKey = $SessionKey }
        }

        $script:ConnectionReady = $true
        $script:Dispatched = @()
        $script:DispatchResult = [pscustomobject]@{ Description = "ODW ingestion setting" }
        $script:InlineCalls = 0
        $script:InlinePage = $Script:PageWithFlag
        $script:PruneCalls = 0
        $script:LogMessages.Clear()
    }
}

Describe "Get-OmadaIngestionSetting - the cache read" {

    BeforeEach {
        Reset-ProbeState
    }

    It "answers null when this session has not learned the flag" {
        # Which the filter must treat exactly like false.
        Get-OmadaIngestionSetting | Should -BeNullOrEmpty
    }

    It "answers true once a true has been cached" {
        $Script:OmadaIngestionSettingCache["session-a"] = $true

        Get-OmadaIngestionSetting | Should -BeTrue
    }

    It "answers false once a false has been cached, which is not the same as not knowing" {
        $Script:OmadaIngestionSettingCache["session-a"] = $false

        $Private:Answer = Get-OmadaIngestionSetting
        $Private:Answer | Should -BeFalse
        $Private:Answer | Should -Not -BeNullOrEmpty -Because "a cached false is an answer, not an absence"
    }

    It "is keyed per connection pool, so another session's answer is not borrowed" {
        $Script:OmadaIngestionSettingCache["session-b"] = $true

        Get-OmadaIngestionSetting | Should -BeNullOrEmpty
    }

    It "makes no request of its own" {
        Get-OmadaIngestionSetting | Out-Null

        @($script:Dispatched).Count | Should -Be 0
        $script:InlineCalls | Should -Be 0
    }
}

Describe "Start-OmadaIngestionSettingProbe - when it refuses to ask" {

    BeforeEach {
        Reset-ProbeState
    }

    It "asks nothing for a tab that is not connected" {
        # Issue #64: a restored but deliberately disconnected tab satisfies every other check, and a
        # probe here would authenticate against the tenant behind -NoReconnect.
        $Script:ConnectionStatus = $false

        Start-OmadaIngestionSettingProbe

        @($script:Dispatched).Count | Should -Be 0
        $script:InlineCalls | Should -Be 0
    }

    It "asks nothing when the connection is not ready" {
        $script:ConnectionReady = $false

        Start-OmadaIngestionSettingProbe

        @($script:Dispatched).Count | Should -Be 0
    }

    It "asks nothing when the answer is already cached" {
        # So a second tab on the same session costs nothing at all.
        $Script:OmadaIngestionSettingCache["session-a"] = $false

        Start-OmadaIngestionSettingProbe

        @($script:Dispatched).Count | Should -Be 0
    }

    It "asks nothing while a probe for this session is already on the queue" {
        $Script:PendingWebViewCompletions.Add([pscustomobject]@{ Description = "ODW ingestion setting" })

        Start-OmadaIngestionSettingProbe

        @($script:Dispatched).Count | Should -Be 0
    }

    It "is not confused by another request on the queue" {
        $Script:PendingWebViewCompletions.Add([pscustomobject]@{ Description = "SQL schema" })

        Start-OmadaIngestionSettingProbe

        @($script:Dispatched).Count | Should -Be 1
    }
}

Describe "Start-OmadaIngestionSettingProbe - the request it makes" {

    BeforeEach {
        Reset-ProbeState
    }

    It "reads logon.aspx on the tenant's base URL" {
        Start-OmadaIngestionSettingProbe

        $Script:RunTimeData.RestMethodParam.Uri | Should -BeExactly "https://tenant.example/logon.aspx"
    }

    It "labels the request so the in-flight check can find it" {
        Start-OmadaIngestionSettingProbe

        $script:Dispatched[0].Description | Should -BeExactly "ODW ingestion setting"
    }

    It "carries the cache key on the context rather than re-deriving it later" {
        # By the time the completion runs, the active tab may belong to a different session.
        Start-OmadaIngestionSettingProbe

        $script:Dispatched[0].Context.CacheKey | Should -BeExactly "session-a"
    }

    It "runs inline when no worker was available, because this is one read with no side effects" {
        $script:DispatchResult = $null

        Start-OmadaIngestionSettingProbe

        $script:InlineCalls | Should -Be 1
        Get-OmadaIngestionSetting | Should -BeTrue
    }
}

Describe "Complete-OmadaIngestionSettingProbe - what it caches" {

    BeforeEach {
        Reset-ProbeState
    }

    It "caches true and applies the filter" {
        Complete-OmadaIngestionSettingProbe -Response $Script:PageWithFlag -CacheKey "session-a"

        Get-OmadaIngestionSetting | Should -BeTrue
        $script:PruneCalls | Should -Be 1
    }

    It "caches an explicit false, and still applies the filter" {
        # The prune is a no-op for a false flag - Remove-UnusedDataConnection keeps everything - but the
        # call is made unconditionally rather than this function second-guessing the filter.
        Complete-OmadaIngestionSettingProbe -Response "appPageVars={isIngestionEnabled: false}" -CacheKey "session-a"

        Get-OmadaIngestionSetting | Should -BeFalse
        $script:PruneCalls | Should -Be 1
    }

    It "caches nothing when the request failed" {
        # So the next connect on this session asks again. Caching the failure would turn one bad
        # response into a session-long refusal to filter.
        $Private:Failure = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("boom"), "x", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        Complete-OmadaIngestionSettingProbe -Response $Private:Failure -CacheKey "session-a"

        $Script:OmadaIngestionSettingCache.ContainsKey("session-a") | Should -BeFalse
        $script:PruneCalls | Should -Be 0
    }

    It "caches nothing for a null response" {
        Complete-OmadaIngestionSettingProbe -Response $null -CacheKey "session-a"

        $Script:OmadaIngestionSettingCache.ContainsKey("session-a") | Should -BeFalse
    }

    It "caches a null when the page does not publish the flag, so it is asked only once" {
        # Absent is not false - nothing is filtered - but it IS an answer. The page was read and does
        # not carry the setting, so asking the same tenant again cannot produce a different result.
        #
        # Not caching it meant one probe per connect for the rest of the session, which is how #165's
        # fan-out ended up adding ~40 completions across an E2E run. The three-state contract still
        # holds because the cache is read through ContainsKey.
        Complete-OmadaIngestionSettingProbe -Response $Script:PageWithoutFlag -CacheKey "session-a"

        $Script:OmadaIngestionSettingCache.ContainsKey("session-a") | Should -BeTrue
        $Script:OmadaIngestionSettingCache["session-a"] | Should -BeNullOrEmpty
        Get-OmadaIngestionSetting | Should -BeNullOrEmpty
        $script:PruneCalls | Should -Be 0
    }

    It "does not probe again once the answer is known to be absent" {
        # The consequence that matters: the connect path must stop paying for a flag this tenant does
        # not publish.
        Complete-OmadaIngestionSettingProbe -Response $Script:PageWithoutFlag -CacheKey "session-a"
        $script:Dispatched = @()

        Start-OmadaIngestionSettingProbe

        @($script:Dispatched).Count | Should -Be 0
        $script:InlineCalls | Should -Be 0
    }

    It "caches a null even when the cache has not been created yet" {
        # Complete- is reachable with a cold cache through the inline fallback, and writing into a
        # $null hashtable would throw into the contained catch - leaving the re-probe in place with
        # nothing to show the fix had not taken effect.
        $Script:OmadaIngestionSettingCache = $null

        { Complete-OmadaIngestionSettingProbe -Response $Script:PageWithoutFlag -CacheKey "session-a" } | Should -Not -Throw

        $Script:OmadaIngestionSettingCache.ContainsKey("session-a") | Should -BeTrue
    }

    It "caches against the key it was given, not the active session" {
        # The completion runs later, possibly on another tab.
        $Script:RunTimeData.RestMethodParam.SessionKey = "session-b"

        Complete-OmadaIngestionSettingProbe -Response $Script:PageWithFlag -CacheKey "session-a"

        $Script:OmadaIngestionSettingCache["session-a"] | Should -BeTrue
        $Script:OmadaIngestionSettingCache.ContainsKey("session-b") | Should -BeFalse
    }

    It "logs the flag, and never the page" {
        # The blob carries AD topology, environment identifiers and endpoint configuration.
        Complete-OmadaIngestionSettingProbe -Response $Script:PageWithFlag -CacheKey "session-a"

        @($script:LogMessages | Where-Object { $_.Message -like "*ODW ingestion enabled*" }).Count | Should -Be 1
        @($script:LogMessages | Where-Object { $_.Message -like "*appPageVars*" }).Count | Should -Be 0
        @($script:LogMessages | Where-Object { $_.Message -like "*tenant.example*" }).Count | Should -Be 0
    }
}
