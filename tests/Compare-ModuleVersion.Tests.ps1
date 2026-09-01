BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Compare-ModuleVersion.ps1"
    . $Command
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Compare-ModuleVersion' -Tag 'Unit' {
    Context 'Stable versions' {
        It 'Should return -1 when the installed version is older than the gallery version' {
            Compare-ModuleVersion -InstalledVersion '2026.6.26.4' -GalleryVersion '2026.8.22.1' | Should -Be -1
        }

        It 'Should return 1 when the installed version is newer than the gallery version' {
            Compare-ModuleVersion -InstalledVersion '2026.8.22.1' -GalleryVersion '2026.6.26.4' | Should -Be 1
        }

        It 'Should return 0 when both versions are equal' {
            Compare-ModuleVersion -InstalledVersion '2026.6.26.4' -GalleryVersion '2026.6.26.4' | Should -Be 0
        }

        It 'Should compare a four part installed version with a three part gallery version' {
            Compare-ModuleVersion -InstalledVersion '2026.6.26.4' -GalleryVersion '2026.8.22' | Should -Be -1
        }
    }

    Context 'Prerelease versions' {
        It 'Should rank a stable release above the prerelease that carries the same numbers' {
            Compare-ModuleVersion -InstalledVersion '2026.8.22' -GalleryVersion '2026.8.22-nightly67' | Should -Be 1
        }

        It 'Should rank a prerelease below the stable release that carries the same numbers' {
            Compare-ModuleVersion -InstalledVersion '2026.8.22-nightly67' -GalleryVersion '2026.8.22' | Should -Be -1
        }

        It 'Should compare two prereleases of the same version by their label' {
            Compare-ModuleVersion -InstalledVersion '2026.8.22-nightly66' -GalleryVersion '2026.8.22-nightly67' | Should -Be -1
        }

        It 'Should not throw when a prerelease is compared with a four part version' {
            { Compare-ModuleVersion -InstalledVersion '2026.6.26.4' -GalleryVersion '2026.8.22-nightly67' } | Should -Not -Throw
        }
    }

    Context 'Unparsable input' {
        It 'Should return $null instead of throwing when the gallery version cannot be parsed' {
            Compare-ModuleVersion -InstalledVersion '2026.6.26.4' -GalleryVersion 'not-a-version' | Should -BeNullOrEmpty
        }

        It 'Should return $null instead of throwing when the installed version cannot be parsed' {
            Compare-ModuleVersion -InstalledVersion 'not-a-version' -GalleryVersion '2026.6.26.4' | Should -BeNullOrEmpty
        }

        It 'Should return $null when a version is empty' {
            Compare-ModuleVersion -InstalledVersion '' -GalleryVersion '2026.6.26.4' | Should -BeNullOrEmpty
        }

        It 'Should return $null when a version is $null' {
            Compare-ModuleVersion -InstalledVersion $null -GalleryVersion $null | Should -BeNullOrEmpty
        }

        It 'Should never throw for an unparsable value' {
            { Compare-ModuleVersion -InstalledVersion 'abc' -GalleryVersion 'def' } | Should -Not -Throw
        }
    }
}
