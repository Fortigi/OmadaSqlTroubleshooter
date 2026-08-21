BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $PrivatePath -ChildPath "New-OmadaSqlTroubleshooterCacheItem.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaSqlTroubleshooterCacheItem.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Public\Clear-OmadaSqlTroubleshooterCache.ps1")
}

Describe 'Clear-OmadaSqlTroubleshooterCache' -Tag 'Unit' {

    BeforeEach {
        # A stand-in for %LOCALAPPDATA%\OmadaSqlTroubleshooter, laid out exactly as the module does.
        $Script:ModuleAppDataPath = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $Script:BinFolder = Join-Path $Script:ModuleAppDataPath 'Bin\win-x64'
        $Script:WebView2UserProfileBasePath = Join-Path $Script:ModuleAppDataPath 'Edge User Data'
        $Script:ProfileFolder = Join-Path $Script:WebView2UserProfileBasePath 'OmadaWebView2Profile'

        New-Item -Path $Script:BinFolder -ItemType Directory -Force | Out-Null
        New-Item -Path $Script:ProfileFolder -ItemType Directory -Force | Out-Null

        Set-Content -Path (Join-Path $Script:BinFolder 'Microsoft.Web.WebView2.Core.dll') -Value 'core'
        Set-Content -Path (Join-Path $Script:BinFolder 'WebView2Loader.dll') -Value 'loader'
        Set-Content -Path (Join-Path $Script:BinFolder 'WebView2.pin') -Value '@{ Version = "1.0.0.0" }'
        Set-Content -Path (Join-Path $Script:ProfileFolder 'Cookies') -Value 'cookie'
    }

    Context 'Reporting' {
        It 'Should report both artefacts by default' {
            $Report = Clear-OmadaSqlTroubleshooterCache -ListOnly

            @($Report).Count | Should -Be 2
            $Report.Scope | Should -Contain 'Binaries'
            $Report.Scope | Should -Contain 'BrowserProfiles'
        }

        It 'Should report how much each artefact holds' {
            $Binaries = Clear-OmadaSqlTroubleshooterCache -ListOnly -Scope Binaries

            $Binaries.Exists | Should -BeTrue
            $Binaries.ItemCount | Should -Be 3
            $Binaries.SizeBytes | Should -BeGreaterThan 0
        }

        It 'Should remove nothing with -ListOnly' {
            Clear-OmadaSqlTroubleshooterCache -ListOnly | Out-Null

            Test-Path $Script:BinFolder | Should -BeTrue
            Test-Path $Script:ProfileFolder | Should -BeTrue
        }

        It 'Should report an artefact that is not there as absent rather than failing' {
            Remove-Item -Path (Join-Path $Script:ModuleAppDataPath 'Bin') -Recurse -Force

            $Binaries = Clear-OmadaSqlTroubleshooterCache -ListOnly -Scope Binaries

            $Binaries.Exists | Should -BeFalse
            $Binaries.ItemCount | Should -Be 0
        }
    }

    Context 'Removal' {
        It 'Should remove only the requested scope' {
            Clear-OmadaSqlTroubleshooterCache -Scope Binaries -Force | Out-Null

            Test-Path (Join-Path $Script:ModuleAppDataPath 'Bin') | Should -BeFalse
            Test-Path $Script:ProfileFolder | Should -BeTrue -Because 'the browser profile was not in scope'
        }

        It 'Should remove the pin stamp along with the assemblies' {
            # Leaving the stamp behind would tell the next import that a now-absent install is current.
            Clear-OmadaSqlTroubleshooterCache -Scope Binaries -Force | Out-Null

            Test-Path (Join-Path $Script:BinFolder 'WebView2.pin') | Should -BeFalse
        }

        It 'Should remove everything when no scope is given' {
            Clear-OmadaSqlTroubleshooterCache -Force | Out-Null

            Test-Path (Join-Path $Script:ModuleAppDataPath 'Bin') | Should -BeFalse
            Test-Path $Script:WebView2UserProfileBasePath | Should -BeFalse
        }

        It 'Should report what it removed' {
            $Report = Clear-OmadaSqlTroubleshooterCache -Scope Binaries -Force

            $Report.Removed | Should -BeTrue
        }

        It 'Should remove nothing with -WhatIf' {
            Clear-OmadaSqlTroubleshooterCache -Force -WhatIf | Out-Null

            Test-Path $Script:BinFolder | Should -BeTrue
            Test-Path $Script:ProfileFolder | Should -BeTrue
        }

        It 'Should not throw when an artefact cannot be removed, and should report it as not removed' {
            # An assembly already loaded into the running session is locked by Windows until that
            # session ends. That has to warn and carry on, not abort.
            Mock Remove-Item { throw 'The process cannot access the file because it is being used by another process.' }

            $Report = $null
            { $Report = Clear-OmadaSqlTroubleshooterCache -Scope Binaries -Force -WarningAction SilentlyContinue } |
                Should -Not -Throw

            $Report.Removed | Should -BeFalse
        }

        It 'Should carry on with the remaining artefacts after one fails' {
            Mock Remove-Item { throw 'locked' }

            $Report = Clear-OmadaSqlTroubleshooterCache -Force -WarningAction SilentlyContinue

            @($Report).Count | Should -Be 2
        }
    }
}
