#Requires -Version 7.0
# What a draft carries to reopen its tab after a crash - and, as important, what it does not.

BeforeAll {
    . (Join-Path $PSScriptRoot "AdHocQueryDraftStore.Shared.ps1")

    $script:AppConfig = [PSCustomObject]@{
        BaseUrl               = "https://tenant.omada.cloud"
        CurrentSqlQuery       = [PSCustomObject]@{ DoId = 7; DisplayName = "Saved"; FullName = "Saved - 7" }
        LastAuthentication    = "OAuth"
        UserName              = "user@example.com"
        Password              = "01000000d08c9ddf-protected"
        EntraApplicationIdUri = "api://app"
        EntraIdTenantId       = "tenant-id"
        MyCreatedQueriesOnly  = $true
        MyUpdatedQueriesOnly  = $false
        SavePassword          = $true
        IdentityUserName      = "OMADA\user"
        CurrentDataConnection = [PSCustomObject]@{ DoId = 3; DisplayName = "OISES"; FullName = "OISES - 3" }
        ResultOutputMode      = "Text"
    }
}

Describe 'ConvertTo-AdHocQueryDraftTabConfig' -Tag 'Unit' {
    It 'Should never carry a password, saved or not' {
        $Config = ConvertTo-AdHocQueryDraftTabConfig -TabId "t" -AppConfig $script:AppConfig

        $Config.Password | Should -BeNullOrEmpty
        $Config.SavePassword | Should -BeFalse
    }

    It 'Should not carry the selected query: a draft is an ad-hoc query' {
        $Config = ConvertTo-AdHocQueryDraftTabConfig -TabId "t" -AppConfig $script:AppConfig

        $Config.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Config.CurrentSqlQuery.DisplayName | Should -BeNullOrEmpty
        $Config.CurrentSqlQuery.FullName | Should -BeNullOrEmpty
    }

    It 'Should carry the connection settings needed to reconnect' {
        $Config = ConvertTo-AdHocQueryDraftTabConfig -TabId "t" -AppConfig $script:AppConfig

        $Config.Id | Should -Be "t"
        $Config.BaseUrl | Should -Be "https://tenant.omada.cloud"
        $Config.LastAuthentication | Should -Be "OAuth"
        $Config.UserName | Should -Be "user@example.com"
        $Config.EntraApplicationIdUri | Should -Be "api://app"
        $Config.EntraIdTenantId | Should -Be "tenant-id"
        $Config.MyCreatedQueriesOnly | Should -BeTrue
        $Config.MyUpdatedQueriesOnly | Should -BeFalse
        $Config.IdentityUserName | Should -Be "OMADA\user"
        $Config.CurrentDataConnection.DoId | Should -Be 3
        $Config.ResultOutputMode | Should -Be "Text"
    }

    It 'Should keep the Display name, trimmed, as the tab name' {
        (ConvertTo-AdHocQueryDraftTabConfig -TabId "t" -AppConfig $script:AppConfig -DisplayName "  Mine ").DisplayName | Should -Be "Mine"
    }

    It 'Should leave the tab name unset for a blank Display name' {
        (ConvertTo-AdHocQueryDraftTabConfig -TabId "t" -AppConfig $script:AppConfig -DisplayName " ").DisplayName | Should -BeNullOrEmpty
    }

    It 'Should build a usable config without any settings' {
        $Config = ConvertTo-AdHocQueryDraftTabConfig -TabId "t" -AppConfig $null

        $Config.Id | Should -Be "t"
        $Config.BaseUrl | Should -BeNullOrEmpty
        $Config.MyCreatedQueriesOnly | Should -BeFalse
    }
}
