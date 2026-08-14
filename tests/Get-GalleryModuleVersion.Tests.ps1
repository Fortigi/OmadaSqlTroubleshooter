BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-GalleryModuleVersion.ps1"
    . $Command
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Get-GalleryModuleVersion' -Tag 'Unit' {
    It 'Should return the version of the most recently updated package' {
        Mock Invoke-RestMethod {
            @(
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{
                        version   = '1.0.0'
                        Published = [PSCustomObject]@{ '#text' = (Get-Date).AddDays(-5) }
                    }
                }
                [PSCustomObject]@{
                    Properties = [PSCustomObject]@{
                        version   = '2.0.0'
                        Published = [PSCustomObject]@{ '#text' = (Get-Date) }
                    }
                }
            )
        }

        Get-GalleryModuleVersion -ModuleName 'OmadaWeb.PS' | Should -Be '2.0.0'
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

