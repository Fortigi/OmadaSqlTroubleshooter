BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Show-ModuleUpdateNotification.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-GalleryModuleVersion.ps1")
    . (Join-Path $PrivatePath -ChildPath "Compare-ModuleVersion.ps1")
    # Dot-sourced so that Pester has a real command to mock.
    . (Join-Path $PrivatePath -ChildPath "Get-InstalledModuleInfo.ps1")
    # The tracer preamble of the functions under test redacts their bound parameters.
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    # Mirrors the shape of a single OData entry returned by FindPackagesById().
    function New-GalleryPackageEntry {
        param(
            [string]$Version,
            [string]$IsPrerelease = 'false',
            [datetime]$Published = (Get-Date)
        )

        return [PSCustomObject]@{
            Properties = [PSCustomObject]@{
                version      = $Version
                IsPrerelease = [PSCustomObject]@{ '#text' = $IsPrerelease }
                Published    = [PSCustomObject]@{ '#text' = $Published }
            }
        }
    }
}

Describe 'Show-ModuleUpdateNotification' -Tag 'Unit' {
    BeforeEach {
        Mock Get-InstalledModuleInfo {
            @{
                Name             = 'OmadaSqlTroubleShooter'
                Version          = '2026.6.26.4'
                RepositorySource = 'https://www.powershellgallery.com/api/v2'
            }
        }
    }

    It 'Should warn that the module is outdated when the newest published package is a prerelease' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '2026.8.22.1' -Published (Get-Date).AddDays(-30)
                New-GalleryPackageEntry -Version '2026.8.22-nightly67' -IsPrerelease 'true' -Published (Get-Date)
            )
        }

        $Warnings = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' 3>&1

        $Warnings | Should -Not -BeNullOrEmpty
        "$Warnings" | Should -BeLike '*is outdated*2026.8.22.1*'
    }

    It 'Should not throw when the newest published package is a prerelease' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '2026.8.22.1' -Published (Get-Date).AddDays(-30)
                New-GalleryPackageEntry -Version '2026.8.22-nightly67' -IsPrerelease 'true' -Published (Get-Date)
            )
        }

        { Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' -WarningAction SilentlyContinue } | Should -Not -Throw
    }

    It 'Should not warn when the installed version matches the highest stable version' {
        Mock Invoke-RestMethod {
            New-GalleryPackageEntry -Version '2026.6.26.4' -Published (Get-Date)
        }

        $Warnings = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' 3>&1

        $Warnings | Should -BeNullOrEmpty
    }

    It 'Should warn when the installed version is newer than the highest stable version' {
        Mock Invoke-RestMethod {
            New-GalleryPackageEntry -Version '2025.1.10.1' -Published (Get-Date)
        }

        $Warnings = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' 3>&1

        "$Warnings" | Should -BeLike '*is newer than the gallery version*'
    }

    It 'Should skip the check when the module was not installed from the PowerShell Gallery' {
        Mock Get-InstalledModuleInfo {
            @{
                Name             = 'OmadaSqlTroubleShooter'
                Version          = '2026.6.26.4'
                RepositorySource = $null
            }
        }
        Mock Invoke-RestMethod { throw 'the gallery must not be queried' }

        $Verbose = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' -Verbose 4>&1

        "$Verbose" | Should -BeLike '*not sourced from the PowerShell Gallery*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'Should log a single verbose line when the gallery version cannot be determined' {
        Mock Invoke-RestMethod { throw 'network error' }

        $Warnings = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' 3>&1
        $Verbose = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' -Verbose 4>&1

        $Warnings | Should -BeNullOrEmpty
        "$Verbose" | Should -BeLike '*Could not determine the latest published version*'
    }

    It 'Should log a verbose line and not warn when the versions cannot be compared' {
        Mock Get-InstalledModuleInfo {
            @{
                Name             = 'OmadaSqlTroubleShooter'
                Version          = 'not-a-version'
                RepositorySource = 'https://www.powershellgallery.com/api/v2'
            }
        }
        Mock Invoke-RestMethod {
            New-GalleryPackageEntry -Version '2026.6.26.4' -Published (Get-Date)
        }

        $Warnings = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' 3>&1
        $Verbose = Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' -Verbose 4>&1

        $Warnings | Should -BeNullOrEmpty
        "$Verbose" | Should -BeLike '*Could not compare the installed version*'
    }

    It 'Should not throw when the installed module cannot be determined' {
        Mock Get-InstalledModuleInfo { $null }
        Mock Invoke-RestMethod { throw 'the gallery must not be queried' }

        { Show-ModuleUpdateNotification -ModuleName 'OmadaSqlTroubleShooter' } | Should -Not -Throw
    }
}
