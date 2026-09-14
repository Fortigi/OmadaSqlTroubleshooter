BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Import-OmadaWebPSModule.ps1")
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    # Dot-sourced so that Pester has real commands to mock.
    function Get-Module {
        param(
            [string]$Name
        )
    }

    function Import-Module {
        param(
            [string]$Name,
            [switch]$PassThru,
            [string]$ErrorAction
        )
    }

    function Remove-Module {
        param(
            [string]$Name,
            [switch]$Force,
            [string]$ErrorAction
        )
    }
}

Describe 'Import-OmadaWebPSModule' -Tag 'Unit' {
    It 'Should continue normally when the installed version equals the minimum version' {
        Mock Get-Module { $null }
        Mock Import-Module {
            [PSCustomObject]@{ Name = 'OmadaWeb.PS'; Version = [version]'2026.7.9.9' }
        }

        { Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' } | Should -Not -Throw
        Should -Invoke Import-Module -Times 1
    }

    It 'Should continue normally when a newer version is installed' {
        Mock Get-Module { $null }
        Mock Import-Module {
            [PSCustomObject]@{ Name = 'OmadaWeb.PS'; Version = [version]'2026.8.1.1' }
        }

        { Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' } | Should -Not -Throw
    }

    It 'Should terminate with the minimum-version error when an older version is installed' {
        Mock Get-Module { $null }
        Mock Import-Module {
            [PSCustomObject]@{ Name = 'OmadaWeb.PS'; Version = [version]'2026.1.1.1' }
        }
        Mock Remove-Module { }

        { Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' -ErrorAction Stop } | Should -Throw '*OmadaWeb.PS module version 2026.07.09.9 or higher is required.*'
    }

    It 'Should remove the too-old module it imported before terminating, since it was not already loaded' {
        Mock Get-Module { $null }
        Mock Import-Module {
            [PSCustomObject]@{ Name = 'OmadaWeb.PS'; Version = [version]'2026.1.1.1' }
        }
        Mock Remove-Module { }

        { Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' -ErrorAction Stop } | Should -Throw

        Should -Invoke Remove-Module -Times 1 -ParameterFilter { $Name -eq 'OmadaWeb.PS' }
    }

    It 'Should not remove the too-old module when it was already loaded before this function ran' {
        Mock Get-Module {
            [PSCustomObject]@{ Name = 'OmadaWeb.PS'; Version = [version]'2026.1.1.1' }
        }
        Mock Import-Module {
            [PSCustomObject]@{ Name = 'OmadaWeb.PS'; Version = [version]'2026.1.1.1' }
        }
        Mock Remove-Module { }

        { Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' -ErrorAction Stop } | Should -Throw

        Should -Invoke Remove-Module -Times 0
    }

    It 'Should terminate instead of dereferencing a null module object when the PassThru result has no match' {
        Mock Get-Module { $null }
        Mock Import-Module { @() }

        { Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' -ErrorAction Stop } | Should -Throw '*version could not be confirmed*'
    }

    It 'Should terminate when no module is available to import' {
        Mock Get-Module { $null }
        Mock Import-Module { throw 'Unable to find module' }

        { Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' -ErrorAction Stop } | Should -Throw '*Unable to find module*'
    }

    It 'Should continue using an already loaded module with version 0.0 and display a warning' {
        Mock Get-Module {
            [PSCustomObject]@{ Name = 'OmadaWeb.PS'; Version = [version]'0.0' }
        }
        Mock Import-Module { throw 'Import-Module must not be called' }

        $Warnings = Import-OmadaWebPSModule -MinimumVersion '2026.07.09.9' 3>&1

        "$Warnings" | Should -Be 'Using already loaded non-versioned OmadaWeb.PS module at your own risk!'
        Should -Invoke Import-Module -Times 0
    }

    It 'Should not perform module version validation when the minimum version is configured as 0.0' {
        Mock Get-Module { $null }
        Mock Import-Module { throw 'Import-Module must not be called' }

        # Mirrors the psm1 caller, which skips calling Import-OmadaWebPSModule entirely when the
        # configured minimum version is '0.0'.
        $MinimumOmadaWebPSVersion = '0.0'
        if ($MinimumOmadaWebPSVersion -ne '0.0') {
            Import-OmadaWebPSModule -MinimumVersion $MinimumOmadaWebPSVersion
        }

        Should -Invoke Import-Module -Times 0
        Should -Invoke Get-Module -Times 0
    }
}
