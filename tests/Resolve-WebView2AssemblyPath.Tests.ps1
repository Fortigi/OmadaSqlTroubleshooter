BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    # Test-WebView2Bundle is dot-sourced so it can be mocked - Mock refuses a command that does not
    # exist. Its own behaviour is covered by Test-WebView2Bundle.Tests.ps1; here it is only the
    # bundle-valid / bundle-invalid switch.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-FileSha256.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-WebView2Bundle.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Resolve-WebView2AssemblyPath.ps1")

    $Script:AssemblyName = @(
        'Microsoft.Web.WebView2.Core.dll'
        'Microsoft.Web.WebView2.WinForms.dll'
        'Microsoft.Web.WebView2.Wpf.dll'
        'WebView2Loader.dll'
    )
}

Describe 'Resolve-WebView2AssemblyPath' -Tag 'Unit' {

    BeforeEach {
        $Script:ModuleRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $Script:BinPath = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $Script:ModuleRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $Script:BinPath -ItemType Directory -Force | Out-Null

        $Script:ExpectedBundlePath = Join-Path $Script:ModuleRoot -ChildPath 'Bin\WebView2Dlls\win-x64'
    }

    Context 'A valid bundle is present' {

        BeforeEach {
            Mock Test-WebView2Bundle { return $true }
        }

        It 'Should return the bundled paths' {
            $Resolved = Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'AMD64'

            $Resolved.Core | Should -Be (Join-Path $Script:ExpectedBundlePath -ChildPath 'Microsoft.Web.WebView2.Core.dll')
            $Resolved.WinForms | Should -Be (Join-Path $Script:ExpectedBundlePath -ChildPath 'Microsoft.Web.WebView2.WinForms.dll')
            $Resolved.Wpf | Should -Be (Join-Path $Script:ExpectedBundlePath -ChildPath 'Microsoft.Web.WebView2.Wpf.dll')
            $Resolved.Loader | Should -Be (Join-Path $Script:ExpectedBundlePath -ChildPath 'WebView2Loader.dll')
        }

        It 'Should not require an install, so module import makes no network call' {
            $Resolved = Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'AMD64'

            $Resolved.RequiresInstall | Should -BeFalse
            $Resolved.Source | Should -Be 'Bundle'
        }

        It 'Should look for the bundle inside the module folder' {
            Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'AMD64' | Out-Null

            Should -Invoke Test-WebView2Bundle -Times 1 -ParameterFilter { $BundlePath -eq $Script:ExpectedBundlePath }
        }

        It 'Should use the bundle in place and copy nothing out of it' {
            # The module folder is typically read-only, which is fine for LoadFrom. Copying would need
            # a writable module folder and would defeat the point of shipping the files.
            Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'AMD64' | Out-Null

            Get-ChildItem -Path $Script:BinPath -Recurse -File | Should -BeNullOrEmpty
        }
    }

    Context 'No usable bundle' {

        BeforeEach {
            Mock Test-WebView2Bundle { return $false }
        }

        It 'Should fall back to the %LOCALAPPDATA% download paths, unchanged from before' {
            $Resolved = Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'AMD64'

            $ExpectedDownloadPath = Join-Path $Script:BinPath -ChildPath 'win-x64'
            foreach ($Name in $Script:AssemblyName) {
                @($Resolved.Core, $Resolved.WinForms, $Resolved.Wpf, $Resolved.Loader) |
                    Should -Contain (Join-Path $ExpectedDownloadPath -ChildPath $Name)
            }
        }

        It 'Should require an install so the fallback download runs' {
            $Resolved = Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'AMD64'

            $Resolved.RequiresInstall | Should -BeTrue
            $Resolved.Source | Should -Be 'Download'
        }
    }

    Context 'x86' {
        # Only x64 is bundled: the manifest declares ProcessorArchitecture = 'Amd64', and neither of
        # the two fetchers this repository used to have ever targeted x86.

        It 'Should always require an install, whatever a bundle folder might contain' {
            Mock Test-WebView2Bundle { return $true }

            $Resolved = Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'x86'

            $Resolved.RequiresInstall | Should -BeTrue
            $Resolved.Source | Should -Be 'Download'
        }

        It 'Should return the win-x86 download paths' {
            Mock Test-WebView2Bundle { return $true }

            $Resolved = Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'x86'

            $Resolved.Core | Should -Be (Join-Path (Join-Path $Script:BinPath -ChildPath 'win-x86') -ChildPath 'Microsoft.Web.WebView2.Core.dll')
        }

        It 'Should not even look at a bundle' {
            Mock Test-WebView2Bundle { return $true }

            Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'x86' | Out-Null

            Should -Invoke Test-WebView2Bundle -Times 0
        }
    }

    Context 'Every caller gets a complete answer' {

        It 'Should always return all four assembly paths and a resolution decision' {
            foreach ($BundleIsValid in @($true, $false)) {
                Mock Test-WebView2Bundle { return $BundleIsValid }.GetNewClosure()

                $Resolved = Resolve-WebView2AssemblyPath -ModuleRoot $Script:ModuleRoot -BinPath $Script:BinPath -ProcessorArchitecture 'AMD64'

                foreach ($Key in @('Core', 'WinForms', 'Wpf', 'Loader', 'BasePath', 'Source', 'RequiresInstall')) {
                    $Resolved.ContainsKey($Key) | Should -BeTrue -Because "the psm1 reads '$Key'"
                }
                $Resolved.Core | Should -Not -BeNullOrEmpty
            }
        }
    }
}
