BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-ShouldConnect.ps1"
    . $Command
}

Describe 'Test-ShouldConnect' {
    It 'returns true for a valid non-OAuth connection that is actively connecting (ReconnectStatus 2)' {
        Test-ShouldConnect -ReconnectStatus 2 -Url "https://tenant.omada.cloud" -AuthenticationOption "WebView2" | Should -BeTrue
    }

    It 'returns false when ReconnectStatus is 0 (startup, before a connect is in progress)' {
        # Regression guard: restored tabs came back disconnected because the auto-connect path left
        # ReconnectStatus at 0, so this returned false and tore down a successful reconnect.
        Test-ShouldConnect -ReconnectStatus 0 -Url "https://tenant.omada.cloud" -AuthenticationOption "WebView2" | Should -BeFalse
    }

    It 'returns false when ReconnectStatus is 1 (skip-reconnect sentinel)' {
        Test-ShouldConnect -ReconnectStatus 1 -Url "https://tenant.omada.cloud" -AuthenticationOption "WebView2" | Should -BeFalse
    }

    It 'returns true for ReconnectStatus 3 (post-navigation) with valid settings' {
        Test-ShouldConnect -ReconnectStatus 3 -Url "https://tenant.omada.cloud" -AuthenticationOption "Browser" | Should -BeTrue
    }

    It 'returns false when the URL is empty' {
        Test-ShouldConnect -ReconnectStatus 2 -Url "" -AuthenticationOption "WebView2" | Should -BeFalse
    }

    It 'returns false when no authentication option is selected' {
        Test-ShouldConnect -ReconnectStatus 2 -Url "https://tenant.omada.cloud" -AuthenticationOption $null | Should -BeFalse
    }

    It 'returns false for OAuth without credentials' {
        Test-ShouldConnect -ReconnectStatus 2 -Url "https://tenant.omada.cloud" -AuthenticationOption "OAuth" -HasCredentials $false | Should -BeFalse
    }

    It 'returns true for OAuth with credentials' {
        Test-ShouldConnect -ReconnectStatus 2 -Url "https://tenant.omada.cloud" -AuthenticationOption "OAuth" -HasCredentials $true | Should -BeTrue
    }

    It 'does not require credentials for non-OAuth authentication' {
        Test-ShouldConnect -ReconnectStatus 2 -Url "https://tenant.omada.cloud" -AuthenticationOption "WebView2" -HasCredentials $false | Should -BeTrue
    }
}
