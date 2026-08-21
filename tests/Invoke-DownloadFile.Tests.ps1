BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Get-FileSha256.ps1")
    . (Join-Path $PrivatePath -ChildPath "Confirm-FileHash.ps1")
    # Dot-sourced so it exists to be mocked below; Pester cannot mock a command that is not defined.
    . (Join-Path $PrivatePath -ChildPath "Get-DependencyLock.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LockedArtifact.ps1")
    . (Join-Path $PrivatePath -ChildPath "Save-RemoteFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-DownloadFile.ps1")
    $Script:DependencyLockPath = Join-Path $ParentPath -ChildPath "src\DependencyLock.psd1"
}

Describe 'Invoke-DownloadFile' -Tag 'Unit' {

    BeforeEach {
        # A stand-in lock, so these tests assert the gate's behaviour rather than the current pins.
        # "hello" hashes to the SHA-256 below.
        Mock Get-DependencyLock {
            @{
                SchemaVersion = 1
                Artifacts     = @(
                    @{
                        Id           = 'Test.Pinned'
                        PackageId    = 'Test.Pinned'
                        Version      = '1.2.3'
                        Url          = 'https://example.invalid/test.pinned.1.2.3.nupkg'
                        Sha256       = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
                        Verification = 'Sha256'
                    }
                    @{
                        Id           = 'Test.Unsupported'
                        Version      = '1.0.0'
                        Url          = 'https://example.invalid/other.zip'
                        Sha256       = ''
                        Verification = 'Authenticode'
                    }
                )
            }
        }

        # Stands in for the network. Each test decides what the "server" returns.
        $Script:TestPayload = 'hello'
        $Script:CapturedOutputFile = $null
        Mock Save-RemoteFile {
            $Script:CapturedOutputFile = $OutputFile
            Set-Content -Path $OutputFile -Value $Script:TestPayload -NoNewline
        }
    }

    AfterEach {
        if (-not [string]::IsNullOrWhiteSpace($Script:CapturedOutputFile) -and (Test-Path $Script:CapturedOutputFile)) {
            Remove-Item $Script:CapturedOutputFile -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Should not expose a -DownloadUrl parameter at all' {
        # OmadaWeb.PS needs one for msedgedriver.exe, whose version must track the locally installed
        # Edge build. Nothing here does, so "download an arbitrary URL" is made unrepresentable rather
        # than merely refused.
        (Get-Command Invoke-DownloadFile).Parameters.Keys | Should -Not -Contain 'DownloadUrl'
    }

    It 'Should return the downloaded file when its hash matches the pin' {
        $Path = Invoke-DownloadFile -ArtifactId 'Test.Pinned'

        Test-Path $Path -PathType Leaf | Should -BeTrue
        Get-Content -Path $Path -Raw | Should -Be 'hello'
    }

    It 'Should download from the URL pinned in the lock, not one supplied by the caller' {
        Invoke-DownloadFile -ArtifactId 'Test.Pinned' | Out-Null

        Should -Invoke Save-RemoteFile -Times 1 -Exactly -ParameterFilter {
            $DownloadUrl -eq 'https://example.invalid/test.pinned.1.2.3.nupkg'
        }
    }

    It 'Should refuse a tampered download and delete it' {
        $Script:TestPayload = 'tampered'

        { Invoke-DownloadFile -ArtifactId 'Test.Pinned' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*Integrity check FAILED*'

        # The bytes must be gone, not merely rejected.
        Test-Path $Script:CapturedOutputFile -PathType Leaf | Should -BeFalse
    }

    It 'Should report the artefact, the expected hash and the actual hash in the failure' {
        $Script:TestPayload = 'tampered'

        $Message = $null
        try {
            Invoke-DownloadFile -ArtifactId 'Test.Pinned' -ErrorAction Stop
        }
        catch {
            $Message = $_.Exception.Message
        }

        $Message | Should -BeLike '*Test.Pinned 1.2.3*'
        $Message | Should -BeLike '*2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824*'
        # SHA-256 of "tampered".
        $Message | Should -BeLike '*d121be3103007b41edf96f8262925f8c7d61894afe9a041843b631f69445bc57*'
    }

    It 'Should refuse an artefact that is not in the lock file without downloading anything' {
        { Invoke-DownloadFile -ArtifactId 'Definitely.Not.Pinned' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*no lock entry for artefact*'

        # Fails before the network is touched at all, not after.
        Should -Invoke Save-RemoteFile -Times 0 -Exactly
    }

    It 'Should refuse an artefact declared with a verification mode this module does not implement' {
        { Invoke-DownloadFile -ArtifactId 'Test.Unsupported' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*only implements 'Sha256'*"

        Should -Invoke Save-RemoteFile -Times 0 -Exactly
    }
}
