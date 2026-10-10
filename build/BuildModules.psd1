<#
    The PowerShell modules the build itself runs on, each pinned to one exact version.

    This file is the only place these versions live. build/InstallModules.ps1 installs exactly these
    versions and build/build.ps1 imports exactly these versions, so a CI runner, a developer machine
    and next month's runner all execute the same analyzer, the same test runner and the same metrics.
    That matters most for PSComplexity: its scores have changed between releases for source that did
    not, so an unpinned upgrade would turn a green commit red without anyone touching it.

    Dependabot does not cover the PowerShell Gallery. The weekly quality workflow
    (.github/workflows/quality-weekly.yml) compares every pin here with the Gallery and files an
    issue when one has a newer release; bump the version here and run the build to adopt it.

    Keys per module:
      Name            - the PowerShell Gallery module name
      RequiredVersion - the exact version installed and imported
      Import          - $true when build/build.ps1 imports it before invoking psake
#>
@{
    Modules = @(
        @{
            Name            = 'Pester'
            RequiredVersion = '6.2.0'
            Import          = $true
        }
        @{
            Name            = 'psake'
            RequiredVersion = '5.0.4'
            Import          = $true
        }
        @{
            Name            = 'PSDeploy'
            RequiredVersion = '1.0.5'
            Import          = $true
        }
        @{
            Name            = 'PSScriptAnalyzer'
            RequiredVersion = '1.25.0'
            Import          = $true
        }
        @{
            Name            = 'PSComplexity'
            RequiredVersion = '0.5.1'
            Import          = $true
        }
        @{
            # PSMutant deliberately declares no Pester dependency and runs under whichever Pester is
            # already loaded, which is the Pester pinned above.
            Name            = 'PSMutant'
            RequiredVersion = '0.5.0'
            Import          = $true
        }
    )

    # Pester 6 does not load on PowerShell 7.0 - 7.3, and PSComplexity and PSMutant need 7.0 at least.
    MinimumPowerShellVersion = '7.4'
}
