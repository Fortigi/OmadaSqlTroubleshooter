BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-GalleryModuleVersion.ps1"
    . $Command
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    # Mirrors the shape of a single OData entry returned by FindPackagesById(): every
    # property that carries an m:type attribute arrives as an XML element with a '#text'
    # child, while the plain version string arrives as a bare string.
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

Describe 'Get-GalleryModuleVersion' -Tag 'Unit' {
    It 'Should return the highest stable version' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '1.0.0' -Published (Get-Date).AddDays(-5)
                New-GalleryPackageEntry -Version '2.0.0' -Published (Get-Date)
            )
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -Be '2.0.0'
    }

    It 'Should ignore a prerelease that is the most recently published package' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '2026.6.26.4' -Published (Get-Date).AddDays(-30)
                New-GalleryPackageEntry -Version '2026.8.22-nightly67' -IsPrerelease 'true' -Published (Get-Date)
            )
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -Be '2026.6.26.4'
    }

    It 'Should ignore a prerelease even when the feed does not flag it as one' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '2026.6.26.4' -Published (Get-Date).AddDays(-30)
                New-GalleryPackageEntry -Version '2026.8.22-nightly67' -IsPrerelease 'false' -Published (Get-Date)
            )
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -Be '2026.6.26.4'
    }

    It 'Should return the highest version rather than the most recently published version' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '2026.8.22.1' -Published (Get-Date).AddDays(-10)
                New-GalleryPackageEntry -Version '2026.6.26.4' -Published (Get-Date)
            )
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -Be '2026.8.22.1'
    }

    It 'Should return $null when the feed contains only prereleases' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '2026.8.18-nightly62' -IsPrerelease 'true' -Published (Get-Date).AddDays(-4)
                New-GalleryPackageEntry -Version '2026.8.22-nightly67' -IsPrerelease 'true' -Published (Get-Date)
            )
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -BeNullOrEmpty
    }

    It 'Should skip an entry whose version cannot be parsed' {
        Mock Invoke-RestMethod {
            @(
                New-GalleryPackageEntry -Version '2026.6.26.4' -Published (Get-Date).AddDays(-30)
                New-GalleryPackageEntry -Version 'not-a-version' -Published (Get-Date)
            )
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -Be '2026.6.26.4'
    }

    It 'Should return a single stable version when the feed holds only one package' {
        Mock Invoke-RestMethod {
            New-GalleryPackageEntry -Version '2026.6.26.4' -Published (Get-Date)
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -Be '2026.6.26.4'
    }

    It 'Should return $null when the gallery response is empty' {
        Mock Invoke-RestMethod { $null }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -BeNullOrEmpty
    }

    It 'Should log a verbose line when the gallery response is empty' {
        Mock Invoke-RestMethod { $null }

        $Verbose = Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' -Verbose 4>&1

        "$Verbose" | Should -BeLike '*returned no packages*'
    }

    It 'Should return $null when the request fails' {
        Mock Invoke-RestMethod { throw 'network error' }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Should -BeNullOrEmpty
    }

    It 'Should request the correct PowerShell Gallery API endpoint' {
        Mock Invoke-RestMethod { $null }

        Get-GalleryModuleVersion -ModuleName 'OmadaSqlTroubleShooter' | Out-Null

        Should -Invoke Invoke-RestMethod -ParameterFilter {
            $Uri -eq "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='OmadaSqlTroubleShooter'"
        }
    }
}
