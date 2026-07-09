BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-DefaultTabDisplayName.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-TabSessionConfig.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe 'ConvertTo-TabSessionConfig' {
    It 'should map every legacy field onto the tab-config shape' {
        $Legacy = [PSCustomObject]@{
            BaseUrl               = "https://tenant.omada.cloud"
            CurrentSqlQuery       = [PSCustomObject]@{ DoId = 42; DisplayName = "My Query"; FullName = "My Query (42)" }
            LastAuthentication    = "WebView2"
            UserName              = "jdoe"
            Password              = "super-secret"
            EntraApplicationIdUri = "api://app-id"
            EntraIdTenantId       = "11111111-1111-1111-1111-111111111111"
            MyCreatedQueriesOnly  = $true
            MyUpdatedQueriesOnly  = $false
            SavePassword          = $true
            IdentityUserName      = "jdoe@example.com"
            CurrentDataConnection = [PSCustomObject]@{ DoId = 7; DisplayName = "Production"; FullName = "Production (7)" }
            DisplayName           = "My Tab"
        }

        $Result = ConvertTo-TabSessionConfig -LegacyAppConfig $Legacy

        $Result.DisplayName | Should -Be "My Tab"
        $Result.BaseUrl | Should -Be "https://tenant.omada.cloud"
        $Result.CurrentSqlQuery.DoId | Should -Be 42
        $Result.CurrentSqlQuery.DisplayName | Should -Be "My Query"
        $Result.CurrentSqlQuery.FullName | Should -Be "My Query (42)"
        $Result.LastAuthentication | Should -Be "WebView2"
        $Result.UserName | Should -Be "jdoe"
        $Result.Password | Should -Be "super-secret"
        $Result.EntraApplicationIdUri | Should -Be "api://app-id"
        $Result.EntraIdTenantId | Should -Be "11111111-1111-1111-1111-111111111111"
        $Result.MyCreatedQueriesOnly | Should -Be $true
        $Result.MyUpdatedQueriesOnly | Should -Be $false
        $Result.SavePassword | Should -Be $true
        $Result.IdentityUserName | Should -Be "jdoe@example.com"
        $Result.CurrentDataConnection.DoId | Should -Be 7
        $Result.CurrentDataConnection.DisplayName | Should -Be "Production"
        $Result.CurrentDataConnection.FullName | Should -Be "Production (7)"
        [guid]::TryParse($Result.Id, [ref]([guid]::Empty)) | Should -Be $true
    }

    It 'should default DisplayName to Get-DefaultTabDisplayName when blank' {
        $Legacy = [PSCustomObject]@{ BaseUrl = "https://tenant.omada.cloud"; DisplayName = "" }
        (ConvertTo-TabSessionConfig -LegacyAppConfig $Legacy).DisplayName | Should -Match '^SqlQuery_\d{14}$'
    }

    It 'should default DisplayName to Get-DefaultTabDisplayName when missing entirely' {
        $Legacy = [PSCustomObject]@{ BaseUrl = "https://tenant.omada.cloud" }
        (ConvertTo-TabSessionConfig -LegacyAppConfig $Legacy).DisplayName | Should -Match '^SqlQuery_\d{14}$'
    }

    It 'should not throw and should still return a shaped object when passed $null' {
        $Result = ConvertTo-TabSessionConfig -LegacyAppConfig $null
        $Result.BaseUrl | Should -BeNullOrEmpty
        $Result.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Result.DisplayName | Should -Match '^SqlQuery_\d{14}$'
        [guid]::TryParse($Result.Id, [ref]([guid]::Empty)) | Should -Be $true
    }

    It 'should coerce missing MyCreatedQueriesOnly/MyUpdatedQueriesOnly/SavePassword to false' {
        $Legacy = [PSCustomObject]@{ BaseUrl = "https://tenant.omada.cloud" }
        $Result = ConvertTo-TabSessionConfig -LegacyAppConfig $Legacy
        $Result.MyCreatedQueriesOnly | Should -Be $false
        $Result.MyUpdatedQueriesOnly | Should -Be $false
        $Result.SavePassword | Should -Be $false
    }
}
