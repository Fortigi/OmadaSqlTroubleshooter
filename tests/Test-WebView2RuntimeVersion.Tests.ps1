BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    # Dot-sourced so it exists to be mocked below; Pester cannot mock a command that is not defined.
    . (Join-Path $PrivatePath -ChildPath "Get-DependencyLock.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LockedArtifact.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-FileSha256.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-WebView2Stamp.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-WebView2RuntimeVersion.ps1")
    $Script:DependencyLockPath = Join-Path $ParentPath -ChildPath "src\DependencyLock.psd1"
}

Describe 'Test-WebView2RuntimeVersion' -Tag 'Unit' {

    BeforeEach {
        Mock Get-DependencyLock {
            @{
                SchemaVersion = 1
                Artifacts     = @(
                    @{ Id = 'Microsoft.Web.WebView2'; Version = '1.0.4129.50'; Verification = 'Sha256' }
                )
            }
        }

        # Anything that would reach the network. The whole point of this change is that module import
        # no longer resolves a version from nuget.org.
        Mock Invoke-RestMethod { throw 'the network must not be touched' }

        $Script:WebView2StampPath = Join-Path $TestDrive 'WebView2.pin'
        if (Test-Path $Script:WebView2StampPath) {
            Remove-Item $Script:WebView2StampPath -Force
        }
    }

    It 'Should never query NuGet for the newest version' {
        Set-Content -Path $Script:WebView2StampPath -Value '@{ Version = "1.0.4129.50" }'

        Test-WebView2RuntimeVersion | Out-Null

        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'Should not require a reinstall when the stamp matches the pin' {
        Set-Content -Path $Script:WebView2StampPath -Value '@{ Version = "1.0.4129.50" }'

        Test-WebView2RuntimeVersion | Should -BeFalse
    }

    It 'Should require a reinstall when there is no stamp' {
        Test-WebView2RuntimeVersion | Should -BeTrue
    }

    It 'Should require a reinstall when the pin has moved forward' {
        Set-Content -Path $Script:WebView2StampPath -Value '@{ Version = "1.0.3000.10" }'

        Test-WebView2RuntimeVersion | Should -BeTrue
    }

    It 'Should require a reinstall when the pin has been rolled back' {
        # The reason this compares with -ne and not -gt: a rollback after a bad bump is exactly when
        # the newer, unverified assemblies already on disk must stop being loaded.
        Set-Content -Path $Script:WebView2StampPath -Value '@{ Version = "1.0.9999.99" }'

        Test-WebView2RuntimeVersion | Should -BeTrue
    }

    It 'Should require a reinstall when the stamp is unreadable, without throwing' {
        Set-Content -Path $Script:WebView2StampPath -Value 'this is not a hashtable {{{'

        { Test-WebView2RuntimeVersion } | Should -Not -Throw
        Test-WebView2RuntimeVersion | Should -BeTrue
    }

    It 'Should require a reinstall when the stamp records no version' {
        Set-Content -Path $Script:WebView2StampPath -Value '@{ Files = @() }'

        Test-WebView2RuntimeVersion | Should -BeTrue
    }

    Context 'When the stamp records per-file hashes' {

        BeforeEach {
            # Bin is user-writable, so an assembly can be swapped after a verified install without
            # the stamp ever changing. These cover that.
            $Script:AssemblyPath = Join-Path $TestDrive 'Microsoft.Web.WebView2.Core.dll'
            Set-Content -Path $Script:AssemblyPath -Value 'the installed bytes' -NoNewline
            $InstalledHash = Get-FileSha256 -Path $Script:AssemblyPath

            Set-Content -Path $Script:WebView2StampPath -Value (
                '@{{ Version = "1.0.4129.50"; Files = @( @{{ Name = "Microsoft.Web.WebView2.Core.dll"; Sha256 = "{0}" }} ) }}' -f $InstalledHash
            )
        }

        It 'Should not require a reinstall while every stamped file still matches' {
            Test-WebView2RuntimeVersion | Should -BeFalse
        }

        It 'Should require a reinstall when a stamped assembly was swapped after install' {
            Set-Content -Path $Script:AssemblyPath -Value 'something else entirely' -NoNewline

            Test-WebView2RuntimeVersion -WarningAction SilentlyContinue | Should -BeTrue
        }

        It 'Should require a reinstall when a stamped assembly is gone' {
            Remove-Item -Path $Script:AssemblyPath -Force

            Test-WebView2RuntimeVersion | Should -BeTrue
        }

        It 'Should not throw on a stamp whose Files entries are malformed' {
            Set-Content -Path $Script:WebView2StampPath -Value '@{ Version = "1.0.4129.50"; Files = @( @{ Sha256 = "nope" } ) }'

            { Test-WebView2RuntimeVersion } | Should -Not -Throw
        }
    }
}
