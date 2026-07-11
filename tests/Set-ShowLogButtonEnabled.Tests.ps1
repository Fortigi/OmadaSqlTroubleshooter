BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Set-ShowLogButtonEnabled.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function New-FakeTab {
        param($Button)
        [PSCustomObject]@{ Elements = [PSCustomObject]@{ ButtonShowLog = $Button } }
    }
}

Describe 'Set-ShowLogButtonEnabled' {
    It 'disables the ButtonShowLog on every tab' {
        $ButtonA = [PSCustomObject]@{ IsEnabled = $true }
        $ButtonB = [PSCustomObject]@{ IsEnabled = $true }
        $Script:Tabs = @((New-FakeTab $ButtonA), (New-FakeTab $ButtonB))

        Set-ShowLogButtonEnabled -Enabled $false

        $ButtonA.IsEnabled | Should -BeFalse
        $ButtonB.IsEnabled | Should -BeFalse
    }

    It 'enables the ButtonShowLog on every tab' {
        $ButtonA = [PSCustomObject]@{ IsEnabled = $false }
        $ButtonB = [PSCustomObject]@{ IsEnabled = $false }
        $Script:Tabs = @((New-FakeTab $ButtonA), (New-FakeTab $ButtonB))

        Set-ShowLogButtonEnabled -Enabled $true

        $ButtonA.IsEnabled | Should -BeTrue
        $ButtonB.IsEnabled | Should -BeTrue
    }

    It 'does not throw when a tab has no ButtonShowLog (element missing / no active tab)' {
        $Button = [PSCustomObject]@{ IsEnabled = $true }
        $Script:Tabs = @((New-FakeTab $null), (New-FakeTab $Button))

        { Set-ShowLogButtonEnabled -Enabled $false } | Should -Not -Throw
        $Button.IsEnabled | Should -BeFalse
    }

    It 'does not throw when there are no tabs (Log window opened before the first tab)' {
        $Script:Tabs = @()
        { Set-ShowLogButtonEnabled -Enabled $false } | Should -Not -Throw
    }
}
