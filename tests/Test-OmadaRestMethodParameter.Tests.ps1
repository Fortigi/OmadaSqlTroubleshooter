#Requires -Version 7.0
# Whether the installed OmadaWeb.PS declares a parameter - asked before every request.
#
# Reading .Parameters runs the module's dynamic-parameter block: 236 ms per call with 2026.9.23.47,
# a quarter of a second of UI thread per request. So the answer is cached per module name, version and
# path. What is asserted is that the cache saves the read without ever answering for a different module.
#
# The basic yes/no answers are also covered in Add-OmadaNonInteractiveAuthentication.Tests.ps1.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Test-OmadaRestMethodParameter.ps1")

    # A command whose .Parameters counts its own reads - the expensive part the cache must skip.
    function script:New-FakeCommand {
        param([string[]]$Parameter, $Module)

        $Private:Fake = [pscustomobject]@{ Module = $Module; DeclaredParameters = @{} }
        foreach ($Private:Name in $Parameter) {
            $Private:Fake.DeclaredParameters[$Private:Name] = $null
        }

        $Private:Fake | Add-Member -MemberType ScriptProperty -Name Parameters -Value {
            $script:ParameterReads++
            return $this.DeclaredParameters
        }

        return $Private:Fake
    }

    function script:New-FakeModule {
        param([string]$Version = "2026.9.23.47", [string]$Path = "C:\Modules\OmadaWeb.PS\OmadaWeb.PS.psm1")
        return [pscustomobject]@{ Name = "OmadaWeb.PS"; Version = [version]$Version; Path = $Path }
    }
}

Describe "Test-OmadaRestMethodParameter - the cache" {

    BeforeEach {
        $Script:OmadaRestMethodParameterCache = @{}
        $script:ParameterReads = 0
    }

    It "reads the parameters once for repeated questions to the same module" {
        $script:Command = New-FakeCommand -Parameter "Uri", "SkipBodyRedaction" -Module (New-FakeModule)
        Mock Get-Command { return $script:Command }

        foreach ($Private:Run in 1..5) {
            Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeTrue
        }

        $script:ParameterReads | Should -Be 1
    }

    It "caches a no as well as a yes" {
        $script:Command = New-FakeCommand -Parameter "Uri" -Module (New-FakeModule)
        Mock Get-Command { return $script:Command }

        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeFalse
        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeFalse

        $script:ParameterReads | Should -Be 1
    }

    It "asks again for another parameter" {
        $script:Command = New-FakeCommand -Parameter "Uri", "SkipBodyRedaction" -Module (New-FakeModule)
        Mock Get-Command { return $script:Command }

        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeTrue
        Test-OmadaRestMethodParameter -Name "NoInteractiveAuthentication" | Should -BeFalse

        $script:ParameterReads | Should -Be 2
    }

    It "asks again after the module version changed" {
        # An upgrade or downgrade mid-session must not be answered for by the old version.
        $script:Command = New-FakeCommand -Parameter "Uri" -Module (New-FakeModule -Version "2026.7.9.9")
        Mock Get-Command { return $script:Command }
        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeFalse

        $script:Command = New-FakeCommand -Parameter "Uri", "SkipBodyRedaction" -Module (New-FakeModule -Version "2026.9.23.47")
        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeTrue
    }

    It "asks again for the same version loaded from another path" {
        $script:Command = New-FakeCommand -Parameter "Uri" -Module (New-FakeModule -Path "C:\A\OmadaWeb.PS.psm1")
        Mock Get-Command { return $script:Command }
        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeFalse

        $script:Command = New-FakeCommand -Parameter "Uri", "SkipBodyRedaction" -Module (New-FakeModule -Path "C:\B\OmadaWeb.PS.psm1")
        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeTrue
    }

    It "never caches a command that does not come from a module" {
        $script:Command = New-FakeCommand -Parameter "Uri", "SkipBodyRedaction" -Module $null
        Mock Get-Command { return $script:Command }

        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeTrue
        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeTrue

        $script:ParameterReads | Should -Be 2
        $Script:OmadaRestMethodParameterCache.Count | Should -Be 0
    }

    It "answers no when the command is not there, and caches nothing" {
        Mock Get-Command { return $null }

        Test-OmadaRestMethodParameter -Name "SkipBodyRedaction" | Should -BeFalse
        $Script:OmadaRestMethodParameterCache.Count | Should -Be 0
    }
}
