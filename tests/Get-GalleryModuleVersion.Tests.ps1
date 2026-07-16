BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-GalleryModuleVersion.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Get-GalleryModuleVersion' -Tag 'Unit' {
    It 'Should return the version of the most recently updated package' {
        Mock Invoke-RestMethod {
            @(
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{
                        version      = '1.0.0'
                        Published    = [PSCustomObject]@{ '#text' = (Get-Date).AddDays(-5) }
                        IsPrerelease = [PSCustomObject]@{ '#text' = 'false' }
                    }
                }
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{
                        version      = '2.0.0'
                        Published    = [PSCustomObject]@{ '#text' = (Get-Date) }
                        IsPrerelease = [PSCustomObject]@{ '#text' = 'false' }
                    }
                }
            )
        }

        $Result = Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS'

        $Result.Version | Should -Be '2.0.0'
        $Result.FullVersion | Should -Be '2.0.0'
        $Result.IsPrerelease | Should -Be 'false'
    }

    It 'Should return the prerelease suffix as part of Version and FullVersion' {
        Mock Invoke-RestMethod {
            @(
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{
                        version      = '2.1.0-beta1'
                        Published    = [PSCustomObject]@{ '#text' = (Get-Date) }
                        IsPrerelease = [PSCustomObject]@{ '#text' = 'true' }
                    }
                }
            )
        }

        $Result = Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS'

        $Result.Version | Should -Be '2.1.0-beta1'
        $Result.FullVersion | Should -Be '2.1.0-beta1'
        $Result.IsPrerelease | Should -Be 'true'
    }

    It 'Should return $null when the gallery response is empty' {
        Mock Invoke-RestMethod { $null }

        Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -BeNullOrEmpty
    }

    It 'Should return $null when the request fails' {
        Mock Invoke-RestMethod { throw 'network error' }

        Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -BeNullOrEmpty
    }

    It 'Should request the correct PowerShell Gallery API endpoint' {
        Mock Invoke-RestMethod { $null }

        Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Out-Null

        Should -Invoke Invoke-RestMethod -ParameterFilter {
            $Uri -eq "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='OmadaWeb.PS'"
        }
    }
}

