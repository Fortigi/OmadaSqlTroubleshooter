#Requires -Version 7.0
# Issue #165. The schema fan-out: one background request per data connection, once the connection list
# is known.
#
# THE ELIGIBILITY GATE IS WHY THIS SUITE EXISTS. Get-SqlSchemaObject falls back to the SYNCHRONOUS
# wrapper whenever dispatch returns $null, so a fan-out that ignored Test-OmadaBackgroundRequestEligible
# would fire one blocking authenticated request per database on the UI thread at connect - with a
# disabled background path, which is one observed worker failure away, that is eight freezes where the
# feature was meant to remove one. Nothing in the running application would report it as a defect; it
# would simply be slow in a way the old lazy design never was.
#
# Get-DataConnectionReferenceList is loaded for real: what counts as a connection, and where its name
# ends, is that function's decision and must not be duplicated here.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Start-SqlSchemaPreload.ps1")

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
    function Get-DataConnectionOptionText { param([switch]$NoRefresh) return , @($script:OptionList) }

    # The real one builds a splat from live request state; what matters here is only that the gate is
    # asked, which the next stub records.
    function Build-OmadaRequestParameter { return @{ } }

    function Test-OmadaBackgroundRequestEligible {
        param([hashtable]$Parameters)
        $script:EligibilityAsked++
        return $script:Eligible
    }

    # The shape Get-SqlSchemaCacheKey produces: "<SessionKey>|<DoId>".
    function Get-SqlSchemaCacheKey {
        param([string]$DataConnectionDoId)
        return "session-a|{0}" -f $DataConnectionDoId
    }

    function Get-SqlSchemaDatabaseNode {
        param([string]$DataConnectionDoId)
        return $script:Node[$DataConnectionDoId]
    }

    # The dispatch itself, recorded rather than performed. Every guard that decides whether a request is
    # made belongs to the real Get-SqlSchemaObject; this suite asserts WHICH connections reach it.
    function Get-SqlSchemaObject {
        param([string]$DataConnectionDoId, [string]$DataConnectionName)
        $script:Requested += [pscustomobject]@{ DoId = $DataConnectionDoId; Name = $DataConnectionName }
    }

    function script:Reset-PreloadState {
        $Script:ConnectionStatus = $true
        $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test"; ReconnectStatus = 3 }
        $Script:AppConfig = [pscustomobject]@{
            CurrentDataConnection = [pscustomobject]@{ DoId = "1001572" }
        }
        $Script:SqlSchemaCache = @{}

        $script:ConnectionReady = $true
        $script:Eligible = $true
        $script:EligibilityAsked = 0
        $script:Requested = @()
        $script:LogMessages.Clear()

        $script:OptionList = @(
            "OISES - 1001572"
            "ODW - 2003044"
            "Reporting - 1001999"
        )

        # Tag hashtables, as Update-SqlSchemaDatabaseTree builds them.
        $script:Node = @{
            "2003044" = [pscustomobject]@{ Tag = @{ DoId = "2003044"; Name = "ODW"; Loaded = $false; Requested = $false } }
            "1001999" = [pscustomobject]@{ Tag = @{ DoId = "1001999"; Name = "Reporting"; Loaded = $false; Requested = $false } }
        }
    }
}

Describe "Start-SqlSchemaPreload - the eligibility gate" {

    BeforeEach {
        Reset-PreloadState
    }

    It "requests nothing at all when background requests are unavailable" {
        # The whole point. Falling through to Get-SqlSchemaObject here would mean one SYNCHRONOUS
        # request per database on the UI thread, at connect.
        $script:Eligible = $false

        Start-SqlSchemaPreload

        @($script:Requested).Count | Should -Be 0
    }

    It "says why, so a slow first expand is explainable" {
        $script:Eligible = $false

        Start-SqlSchemaPreload

        @($script:LogMessages | Where-Object { $_.Message -like "*not available*expand*" }).Count | Should -Be 1
    }

    It "asks the real decision function rather than reading its flags" {
        # A copy of that decision here would be free to drift from it.
        Start-SqlSchemaPreload

        $script:EligibilityAsked | Should -Be 1
    }

    It "asks it once, not once per connection" {
        Start-SqlSchemaPreload

        $script:EligibilityAsked | Should -Be 1
        @($script:Requested).Count | Should -Be 2
    }
}

Describe "Start-SqlSchemaPreload - which connections it asks for" {

    BeforeEach {
        Reset-PreloadState
    }

    It "requests every connection except the active one" {
        # The active connection is fetched by the normal path; asking again would be a duplicate.
        Start-SqlSchemaPreload

        @($script:Requested.DoId) | Should -Be @("2003044", "1001999")
    }

    It "passes each connection its name, which is how the editor addresses a database" {
        Start-SqlSchemaPreload

        ($script:Requested | Where-Object { $_.DoId -eq "1001999" }).Name | Should -BeExactly "Reporting"
    }

    It "skips a connection whose schema is already cached" {
        $Script:SqlSchemaCache["session-a|2003044"] = @{ d = "cached" }

        Start-SqlSchemaPreload

        @($script:Requested.DoId) | Should -Be @("1001999")
    }

    It "requests nothing when every connection is cached or active" {
        $Script:SqlSchemaCache["session-a|2003044"] = @{ d = "cached" }
        $Script:SqlSchemaCache["session-a|1001999"] = @{ d = "cached" }

        Start-SqlSchemaPreload

        @($script:Requested).Count | Should -Be 0
    }

    It "keeps the dropdown's order" {
        $script:OptionList = @("Reporting - 1001999", "OISES - 1001572", "ODW - 2003044")

        Start-SqlSchemaPreload

        @($script:Requested.DoId) | Should -Be @("1001999", "2003044")
    }

    It "requests nothing when the connection list is empty" {
        $script:OptionList = @()

        Start-SqlSchemaPreload

        @($script:Requested).Count | Should -Be 0
    }

    It "skips an entry whose DoId is not a positive integer" {
        # Issue #165. A nameless ComboBoxItem - Set-DataConnection adds one whose Content is
        # CurrentDataConnection.FullName, which is $null on a tab whose connection was never populated
        # - parsed as DoId 0, and the preload then asked the tenant for database "0" on every refresh.
        # Get-SqlSchemaObject refuses it as well, and that is the gate that matters; this keeps the
        # preload from counting a skipped entry as requested.
        $script:OptionList = @("OISES - 1001572", " - 0", "Reporting - 1001999")

        Start-SqlSchemaPreload

        @($script:Requested.DoId) | Should -Be @("1001999")
        @($script:Requested.DoId) | Should -Not -Contain "0"
    }

    It "reports only the entries it actually asked for" {
        # The count in the DEBUG line is what a reader uses to tell "preloaded" from "skipped", so a
        # junk entry must not inflate it.
        $script:OptionList = @("OISES - 1001572", " - 0", "Reporting - 1001999")

        Start-SqlSchemaPreload

        @($script:LogMessages | Where-Object { $_.Message -like "Schema preload: requested 1 of *" }).Count | Should -Be 1
    }

    It "reports how many of how many it asked for" {
        Start-SqlSchemaPreload

        @($script:LogMessages | Where-Object { $_.Message -like "Schema preload: requested 2 of 3*" }).Count | Should -Be 1
    }
}

Describe "Start-SqlSchemaPreload - the connection guards" {

    BeforeEach {
        Reset-PreloadState
    }

    It "requests nothing for a tab that is not connected" {
        # Issue #64 again: a restored, deliberately disconnected tab must not reach the tenant.
        $Script:ConnectionStatus = $false

        Start-SqlSchemaPreload

        @($script:Requested).Count | Should -Be 0
        $script:EligibilityAsked | Should -Be 0 -Because "the cheaper guard comes first"
    }

    It "requests nothing when the connection is not ready" {
        $script:ConnectionReady = $false

        Start-SqlSchemaPreload

        @($script:Requested).Count | Should -Be 0
    }

    It "requests nothing while a reconnect is in progress" {
        $Script:RunTimeConfig.ReconnectStatus = 1

        Start-SqlSchemaPreload

        @($script:Requested).Count | Should -Be 0
    }
}

Describe "Start-SqlSchemaPreload - the tree node's state" {

    BeforeEach {
        Reset-PreloadState
    }

    It "marks a node as requested before dispatching it" {
        # So a user expanding the node while its response is in flight does not ask for it again.
        Start-SqlSchemaPreload

        $script:Node["2003044"].Tag.Requested | Should -BeTrue
        $script:Node["1001999"].Tag.Requested | Should -BeTrue
    }

    It "still dispatches when the tree has no node for a connection" {
        # The schema window is optional - the editor's completion needs these schemas whether or not it
        # was ever opened.
        $script:Node = @{}

        Start-SqlSchemaPreload

        @($script:Requested).Count | Should -Be 2
    }

    It "leaves a cached connection's node alone" {
        $Script:SqlSchemaCache["session-a|2003044"] = @{ d = "cached" }

        Start-SqlSchemaPreload

        $script:Node["2003044"].Tag.Requested | Should -BeFalse
    }
}
