BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Resolve-KeyLogAction.ps1"
    . $Command
}

Describe 'Resolve-KeyLogAction' {
    BeforeEach {
        $State = [System.Collections.Generic.HashSet[string]]::new()
    }

    It 'logs the first press as "pressed"' {
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -Be "pressed"
    }

    It 'suppresses an auto-repeat of a held key' {
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -Be "pressed"
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -BeNullOrEmpty
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -BeNullOrEmpty
    }

    It 'suppresses the duplicate down from the second event route (window + WebView2)' {
        # Same physical press arriving twice must produce only one "pressed".
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -Be "pressed"
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -BeNullOrEmpty
    }

    It 'logs the first release as "released" and drops the duplicate/repeat up' {
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -Be "pressed"
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $true -State $State | Should -Be "released"
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $true -State $State | Should -BeNullOrEmpty
    }

    It 'logs a fresh press again after the key has been released' {
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -Be "pressed"
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $true  -State $State | Should -Be "released"
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -Be "pressed"
    }

    It 'does not log a release for a key that was never pressed' {
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $true -State $State | Should -BeNullOrEmpty
    }

    It 'tracks different keys independently (a chord like Ctrl+S)' {
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -Be "pressed"
        Resolve-KeyLogAction -KeyName "S"        -IsRelease $false -State $State | Should -Be "pressed"
        Resolve-KeyLogAction -KeyName "S"        -IsRelease $false -State $State | Should -BeNullOrEmpty
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $false -State $State | Should -BeNullOrEmpty
        Resolve-KeyLogAction -KeyName "S"        -IsRelease $true  -State $State | Should -Be "released"
        Resolve-KeyLogAction -KeyName "LeftCtrl" -IsRelease $true  -State $State | Should -Be "released"
    }
}
