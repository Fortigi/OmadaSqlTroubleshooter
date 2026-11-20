#Requires -Version 7.0
# A rename or delete reaches every connected tab of the pool, without reloading any editor.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-QueryListItemDoId.ps1")
    . (Join-Path $Script:QueryPrivatePath "Update-CachedQueryList.ps1")
    . (Join-Path $Script:QueryPrivatePath "Update-QueryInConnectedPoolTabs.ps1")

    function Get-ActiveTabSession { $Script:Tabs | Where-Object { $_.Id -eq $Script:ActiveTabId } | Select-Object -First 1 }
    function Get-TabConnectionIdentity { param($TabSession) [PSCustomObject]@{ Key = $TabSession.PoolKey; IsEmpty = [string]::IsNullOrWhiteSpace($TabSession.PoolKey) } }

    function script:New-ComboBox {
        param([string[]]$Content, [int]$Selected = -1)
        $Items = [System.Collections.ArrayList]::new()
        foreach ($C in $Content) { [void]$Items.Add([PSCustomObject]@{ Content = $C }) }
        $Box = [PSCustomObject]@{ Items = $Items; SelectedItem = $null; Text = "" }
        if ($Selected -ge 0) { $Box.SelectedItem = $Items[$Selected]; $Box.Text = $Items[$Selected].Content }
        return $Box
    }

    function script:New-PoolTab {
        param($Id, $PoolKey = "pool", [bool]$Connected = $true, $ComboBox)
        return [PSCustomObject]@{
            Id               = $Id
            DisplayName      = $Id
            PoolKey          = $PoolKey
            ConnectionStatus = $Connected
            RunTimeData      = [PSCustomObject]@{ QueryListCache = @{ QueryList = @(@{ 42 = "Accounts" }, @{ 43 = "Other" }) } }
            Elements         = [PSCustomObject]@{ ComboBoxSelectQuery = $ComboBox }
        }
    }
}

Describe 'Update-QueryInConnectedPoolTabs' -Tag 'Unit' {
    BeforeEach {
        $script:QueryLog.Clear()
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        $script:Active = New-PoolTab -Id "active" -ComboBox (New-ComboBox -Content "Accounts - 42", "Other - 43" -Selected 0)
        $script:Peer = New-PoolTab -Id "peer" -ComboBox (New-ComboBox -Content "Accounts - 42", "Other - 43" -Selected 1)
        $script:PeerSelected = New-PoolTab -Id "peer-selected" -ComboBox (New-ComboBox -Content "Accounts - 42" -Selected 0)
        $script:OtherPool = New-PoolTab -Id "other-pool" -PoolKey "elsewhere" -ComboBox (New-ComboBox -Content "Accounts - 42")
        $script:Offline = New-PoolTab -Id "offline" -Connected $false -ComboBox (New-ComboBox -Content "Accounts - 42")
        $Script:Tabs = @($script:Active, $script:Peer, $script:PeerSelected, $script:OtherPool, $script:Offline)
        $Script:ActiveTabId = "active"
        $Script:ConnectionStatus = $true
    }

    Context 'Rename' {
        It 'Should rename the entry in every connected tab of the pool' {
            Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed"

            $script:Active.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Renamed - 42"
            $script:Peer.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Renamed - 42"
            $script:PeerSelected.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Renamed - 42"
            $script:Active.Elements.ComboBoxSelectQuery.Items[1].Content | Should -Be "Other - 43"
        }

        It 'Should refresh the shown text where the entry is selected, without changing the selection' {
            $Selected = $script:Active.Elements.ComboBoxSelectQuery.SelectedItem

            Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed"

            $script:Active.Elements.ComboBoxSelectQuery.SelectedItem | Should -Be $Selected
            $script:Active.Elements.ComboBoxSelectQuery.Text | Should -Be "Renamed - 42"
            $script:Peer.Elements.ComboBoxSelectQuery.Text | Should -Be "Other - 43"
        }

        It 'Should rename the cached entry' {
            Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed"

            $script:Peer.RunTimeData.QueryListCache.QueryList[0][42] | Should -Be "Renamed"
        }

        It 'Should leave other pools and disconnected tabs alone' {
            Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed"

            $script:OtherPool.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Accounts - 42"
            $script:Offline.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Accounts - 42"
            $script:OtherPool.RunTimeData.QueryListCache.QueryList[0][42] | Should -Be "Accounts"
        }

        It 'Should not match another query whose id merely ends the same' {
            $script:Active.Elements.ComboBoxSelectQuery.Items.Add([PSCustomObject]@{ Content = "Long - 142" })

            Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed"

            $script:Active.Elements.ComboBoxSelectQuery.Items[2].Content | Should -Be "Long - 142"
        }
    }

    Context 'Remove' {
        It 'Should remove the entry and its cache entry' {
            Update-QueryInConnectedPoolTabs -DoId "42" -Remove

            @($script:Active.Elements.ComboBoxSelectQuery.Items.Content) | Should -Be @("Other - 43")
            @($script:Peer.Elements.ComboBoxSelectQuery.Items.Content) | Should -Be @("Other - 43")
            @($script:Peer.RunTimeData.QueryListCache.QueryList).Count | Should -Be 1
        }

        It 'Should keep the entry in a background tab where it is selected' {
            Update-QueryInConnectedPoolTabs -DoId "42" -Remove

            @($script:PeerSelected.Elements.ComboBoxSelectQuery.Items.Content) | Should -Be @("Accounts - 42")
        }

        It 'Should leave other pools alone' {
            Update-QueryInConnectedPoolTabs -DoId "42" -Remove

            @($script:OtherPool.Elements.ComboBoxSelectQuery.Items).Count | Should -Be 1
        }
    }

    It 'Should update only the active tab when it has no pool identity' {
        $script:Active.PoolKey = $null

        Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed"

        $script:Active.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Renamed - 42"
        $script:Peer.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Accounts - 42"
    }

    It 'Should use the live connection state of the active tab' {
        $Script:ConnectionStatus = $false
        $script:Active.ConnectionStatus = $true

        Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed"

        $script:Active.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Accounts - 42"
        $script:Peer.Elements.ComboBoxSelectQuery.Items[0].Content | Should -Be "Renamed - 42"
    }

    It 'Should tolerate a tab without a query dropdown' {
        $script:Peer.Elements.ComboBoxSelectQuery = $null

        { Update-QueryInConnectedPoolTabs -DoId "42" -DisplayName "Renamed" } | Should -Not -Throw
        $script:Peer.RunTimeData.QueryListCache.QueryList[0][42] | Should -Be "Renamed"
    }
}
