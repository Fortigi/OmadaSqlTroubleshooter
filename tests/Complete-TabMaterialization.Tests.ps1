#Requires -Version 7.0
# The auto-connect branch of Complete-TabMaterialization: what a restored tab does once it is connected.
#
# That branch builds the data connection list BEFORE Test-ConnectionSettings connects the tab. A
# disconnected tab's list is built synchronously, so everything the list completion triggers that
# requires a connected tab declines - the schema fetch, and since issue #165 the ODW ingestion probe
# and the schema preload. Those are repeated after the connect, and that repetition is what is
# asserted here. Without it a restored tab never learned the ingestion flag, and the log said only
# "Tab is not connected; not probing the ODW ingestion setting."
#
# Everything the function calls is stubbed: the assertions are about ORDER and GATING, not about what
# the called functions do.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Complete-TabMaterialization.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test"; ReconnectStatus = 0 }

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog)
        process { $script:Calls.Add("Write-LogOutput:{0}" -f $InputObject) }
    }

    function Set-ActiveTabContext { param($TabSession) }
    function Test-OmadaConnection { return $script:ConnectionSucceeds }
    function Update-DataConnectionList { param([switch]$NotShowPopupWindow) $script:Calls.Add("Update-DataConnectionList") }
    function Set-DataConnection { $script:Calls.Add("Set-DataConnection") }
    function Test-ConnectionButton { }
    function Initialize-WebViewForTab { param($TabSession) }
    function Set-SqlConnectionState { param([bool]$Status) $script:Calls.Add("Set-SqlConnectionState") }

    # The connect itself. Records the moment the tab became connected, so the assertions can check that
    # the connected-only work came AFTER it.
    function Test-ConnectionSettings {
        $script:Calls.Add("Test-ConnectionSettings")
        $Script:ConnectionStatus = $script:ConnectSetsStatus
    }

    function Get-SqlSchemaObject { $script:Calls.Add("Get-SqlSchemaObject:{0}" -f $Script:ConnectionStatus) }
    function Start-OmadaIngestionSettingProbe { $script:Calls.Add("Start-OmadaIngestionSettingProbe:{0}" -f $Script:ConnectionStatus) }
    function Start-SqlSchemaPreload { $script:Calls.Add("Start-SqlSchemaPreload:{0}" -f $Script:ConnectionStatus) }

    function script:New-TestTabSession {
        param([bool]$PendingAutoConnect = $true)

        return [pscustomobject]@{
            Id                 = "tab-1"
            DisplayName        = "Restored"
            IsMaterialized     = $false
            PendingAutoConnect = $PendingAutoConnect
        }
    }

    function script:Reset-MaterializationState {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:ConnectionSucceeds = $true
        $script:ConnectSetsStatus = $true

        $Script:ActiveTabId = "tab-1"
        $Script:ConnectionStatus = $false
        $Script:AppConfig = [pscustomobject]@{
            CurrentSqlQuery       = [pscustomobject]@{ DoId = ""; FullName = ""; DisplayName = "" }
            CurrentDataConnection = [pscustomobject]@{ FullName = "" }
        }
    }
}

Describe "Complete-TabMaterialization - connected-only work after an auto-connect" {

    BeforeEach {
        Reset-MaterializationState
    }

    It "probes the ingestion setting once the tab is connected" {
        Complete-TabMaterialization -TabSession (New-TestTabSession)

        @($script:Calls | Where-Object { $_ -eq "Start-OmadaIngestionSettingProbe:True" }).Count | Should -Be 1
    }

    It "preloads the schemas once the tab is connected" {
        Complete-TabMaterialization -TabSession (New-TestTabSession)

        @($script:Calls | Where-Object { $_ -eq "Start-SqlSchemaPreload:True" }).Count | Should -Be 1
    }

    It "does both after the connect, not before it" {
        # The defect: the list update's own calls ran while the tab was still disconnected. The repeat
        # only helps if it comes after Test-ConnectionSettings.
        Complete-TabMaterialization -TabSession (New-TestTabSession)

        $Private:ConnectIndex = $script:Calls.IndexOf("Test-ConnectionSettings")
        $Private:ConnectIndex | Should -BeGreaterOrEqual 0
        $script:Calls.IndexOf("Start-OmadaIngestionSettingProbe:True") | Should -BeGreaterThan $Private:ConnectIndex
        $script:Calls.IndexOf("Start-SqlSchemaPreload:True") | Should -BeGreaterThan $Private:ConnectIndex
    }

    It "does neither when the connect did not succeed" {
        # A tab that is still disconnected must not reach the tenant (issue #64).
        $script:ConnectSetsStatus = $false

        Complete-TabMaterialization -TabSession (New-TestTabSession)

        @($script:Calls | Where-Object { $_ -like "Start-OmadaIngestionSettingProbe*" }).Count | Should -Be 0
        @($script:Calls | Where-Object { $_ -like "Start-SqlSchemaPreload*" }).Count | Should -Be 0
    }

    It "does neither for a tab that was not asked to reconnect" {
        Complete-TabMaterialization -TabSession (New-TestTabSession -PendingAutoConnect $false)

        @($script:Calls | Where-Object { $_ -like "Start-OmadaIngestionSettingProbe*" }).Count | Should -Be 0
        @($script:Calls | Where-Object { $_ -like "Start-SqlSchemaPreload*" }).Count | Should -Be 0
        $script:Calls | Should -Contain "Set-SqlConnectionState"
    }

    It "does neither when the tenant could not be reached" {
        $script:ConnectionSucceeds = $false

        Complete-TabMaterialization -TabSession (New-TestTabSession)

        @($script:Calls | Where-Object { $_ -like "Start-OmadaIngestionSettingProbe*" }).Count | Should -Be 0
        @($script:Calls | Where-Object { $_ -like "Start-SqlSchemaPreload*" }).Count | Should -Be 0
    }

    It "does nothing for a tab that is already materialized" {
        $Private:Tab = New-TestTabSession
        $Private:Tab.IsMaterialized = $true

        Complete-TabMaterialization -TabSession $Private:Tab

        $script:Calls.Count | Should -Be 0
    }
}
