BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-ActiveTabSession.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe 'Get-ActiveTabSession' {
    BeforeEach {
        $Script:Tabs = @(
            [PSCustomObject]@{ Id = "11111111-1111-1111-1111-111111111111"; DisplayName = "Tab 1" }
            [PSCustomObject]@{ Id = "22222222-2222-2222-2222-222222222222"; DisplayName = "Tab 2" }
        )
    }

    It 'should return the tab session matching $Script:ActiveTabId' {
        $Script:ActiveTabId = "22222222-2222-2222-2222-222222222222"
        (Get-ActiveTabSession).DisplayName | Should -Be "Tab 2"
    }

    It 'should return nothing when $Script:ActiveTabId matches no tab' {
        $Script:ActiveTabId = "33333333-3333-3333-3333-333333333333"
        Get-ActiveTabSession | Should -BeNullOrEmpty
    }

    It 'should return nothing when there are no tabs' {
        $Script:Tabs = @()
        $Script:ActiveTabId = "11111111-1111-1111-1111-111111111111"
        Get-ActiveTabSession | Should -BeNullOrEmpty
    }
}
