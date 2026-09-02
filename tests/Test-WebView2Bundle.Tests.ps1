BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-FileSha256.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-WebView2Bundle.ps1")

    $Script:PinnedVersion = '1.0.4129.50'

    # SHA-256 of each file's own name, written with no trailing newline. Using distinct content per
    # file means a test that tampers with one cannot accidentally still match another's pin.
    $Script:BundleFile = @(
        @{ Target = 'Microsoft.Web.WebView2.Core.dll'; Content = 'core' }
        @{ Target = 'Microsoft.Web.WebView2.WinForms.dll'; Content = 'winforms' }
        @{ Target = 'Microsoft.Web.WebView2.Wpf.dll'; Content = 'wpf' }
        @{ Target = 'WebView2Loader.dll'; Content = 'loader' }
    )

    function New-TestBundle {
        # Lays out a bundle that Test-WebView2Bundle should accept, and returns its path. Individual
        # tests then break exactly one thing about it.
        param([string]$Path, [string]$StampVersion = $Script:PinnedVersion, [switch]$NoStamp)

        New-Item -Path $Path -ItemType Directory -Force | Out-Null

        $StampEntry = foreach ($File in $Script:BundleFile) {
            $FilePath = Join-Path $Path -ChildPath $File.Target
            Set-Content -Path $FilePath -Value $File.Content -NoNewline
            '        @{{ Name = "{0}"; Sha256 = "{1}" }}' -f $File.Target, (Get-FileSha256 -Path $FilePath)
        }

        if (-not $NoStamp) {
            $StampContent = @(
                "@{"
                ('    Version = "{0}"' -f $StampVersion)
                "    Files   = @("
                $StampEntry
                "    )"
                "}"
            ) -join "`r`n"
            Set-Content -Path (Join-Path $Path -ChildPath 'WebView2.pin') -Value $StampContent
        }

        return $Path
    }

    function Set-TestArtifact {
        # Stands in for Get-LockedArtifact. The lock is the authority on the expected hashes, so the
        # fixture derives them from the freshly written bundle.
        param([string]$Path, [string]$Version = $Script:PinnedVersion)

        $File = foreach ($Entry in $Script:BundleFile) {
            @{
                Source = 'lib_manual/netcoreapp3.0/{0}' -f $Entry.Target
                Target = $Entry.Target
                Sha256 = (Get-FileSha256 -Path (Join-Path $Path -ChildPath $Entry.Target))
            }
        }

        $Script:TestArtifact = @{
            Id      = 'Microsoft.Web.WebView2'
            Version = $Version
            Files   = @($File)
        }
    }

    function Get-LockedArtifact {
        param([string]$Id)

        if ($null -eq $Script:TestArtifact) {
            throw "no artefact configured"
        }
        return $Script:TestArtifact
    }
}

Describe 'Test-WebView2Bundle' -Tag 'Unit' {

    BeforeEach {
        $Script:BundlePath = New-TestBundle -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        Set-TestArtifact -Path $Script:BundlePath
    }

    Context 'A bundle that should be used' {

        It 'Should accept a complete bundle whose files and stamp match the pin' {
            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeTrue
        }
    }

    Context 'A bundle that must be refused' {

        It 'Should refuse a bundle with a missing file' {
            Remove-Item -Path (Join-Path $Script:BundlePath -ChildPath 'Microsoft.Web.WebView2.Wpf.dll') -Force

            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
        }

        It 'Should refuse a bundle with a tampered file' {
            Set-Content -Path (Join-Path $Script:BundlePath -ChildPath 'Microsoft.Web.WebView2.Core.dll') -Value 'tampered' -NoNewline

            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
        }

        It 'Should refuse a bundle whose stamp records a different version from the pin' {
            # -ne and not -lt on purpose: a pin moving backwards is a rollback after a bad bump, and
            # the newer bundled assemblies must stop being loaded.
            $Rolled = New-TestBundle -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -StampVersion '1.0.9999.0'
            Set-TestArtifact -Path $Rolled

            Test-WebView2Bundle -BundlePath $Rolled | Should -BeFalse
        }

        It 'Should refuse a bundle with no stamp at all' {
            $Unstamped = New-TestBundle -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -NoStamp
            Set-TestArtifact -Path $Unstamped

            Test-WebView2Bundle -BundlePath $Unstamped | Should -BeFalse
        }

        It 'Should refuse a folder that does not exist' {
            Test-WebView2Bundle -BundlePath (Join-Path $TestDrive 'no-such-folder') | Should -BeFalse
        }

        It 'Should refuse an empty bundle path' {
            Test-WebView2Bundle -BundlePath '' | Should -BeFalse
        }
    }

    Context 'It must never throw, whatever it finds' {
        # This is the assertion that protects module import. Test-WebView2Bundle is called before the
        # module has any of its error handling set up, and every failure here has a safe answer: use
        # the download path instead.

        It 'Should return false rather than throw on a garbage stamp' {
            Set-Content -Path (Join-Path $Script:BundlePath -ChildPath 'WebView2.pin') -Value "@{ this is not = valid powershell ((("

            { Test-WebView2Bundle -BundlePath $Script:BundlePath -ErrorAction Stop } | Should -Not -Throw
            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
        }

        It 'Should return false rather than throw on a stamp that parses but records no version' {
            Set-Content -Path (Join-Path $Script:BundlePath -ChildPath 'WebView2.pin') -Value "@{ Files = @() }"

            { Test-WebView2Bundle -BundlePath $Script:BundlePath -ErrorAction Stop } | Should -Not -Throw
            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
        }

        It 'Should return false rather than throw when the stamp holds a command instead of data' {
            # SafeGetValue evaluates constant expressions only, so this is refused rather than run.
            $Marker = Join-Path $TestDrive 'stamp-executed.txt'
            Set-Content -Path (Join-Path $Script:BundlePath -ChildPath 'WebView2.pin') -Value ('@{{ Version = (Set-Content -Path "{0}" -Value "executed") }}' -f $Marker)

            { Test-WebView2Bundle -BundlePath $Script:BundlePath -ErrorAction Stop } | Should -Not -Throw
            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
            Test-Path $Marker | Should -BeFalse -Because 'a stamp file must never be executed'
        }

        It 'Should return false rather than throw when the lock cannot be read' {
            $Script:TestArtifact = $null

            { Test-WebView2Bundle -BundlePath $Script:BundlePath -ErrorAction Stop } | Should -Not -Throw
            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
        }

        It 'Should return false rather than throw when the lock lists no files' {
            $Script:TestArtifact = @{ Id = 'Microsoft.Web.WebView2'; Version = $Script:PinnedVersion; Files = @() }

            { Test-WebView2Bundle -BundlePath $Script:BundlePath -ErrorAction Stop } | Should -Not -Throw
            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
        }
    }

    Context 'It must not damage the installation it inspects' {

        It 'Should leave a tampered bundle file on disk rather than deleting it' {
            # Deliberately not Confirm-FileHash here: that deletes what it rejects, which is right for
            # a download landing in a temp file and wrong for a probe against an installed module
            # folder. Deleting would permanently degrade the install to the download path.
            $Tampered = Join-Path $Script:BundlePath -ChildPath 'Microsoft.Web.WebView2.Core.dll'
            Set-Content -Path $Tampered -Value 'tampered' -NoNewline

            Test-WebView2Bundle -BundlePath $Script:BundlePath | Should -BeFalse
            Test-Path $Tampered -PathType Leaf | Should -BeTrue
        }
    }
}
