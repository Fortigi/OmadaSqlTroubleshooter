BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-FileSha256.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Confirm-FileHash.ps1")
    $Script:DependencyLockPath = Join-Path $ParentPath -ChildPath "src\DependencyLock.psd1"

    # SHA-256 of the five bytes "hello", with no trailing newline.
    $Script:HelloSha256 = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
}

Describe 'Confirm-FileHash' -Tag 'Unit' {

    BeforeEach {
        $Script:PayloadPath = Join-Path $TestDrive 'payload.bin'
        Set-Content -Path $Script:PayloadPath -Value 'hello' -NoNewline
    }

    It 'Should accept a file whose hash matches the pin' {
        { Confirm-FileHash -Path $Script:PayloadPath -ExpectedSha256 $Script:HelloSha256 -ArtifactName 'Test 1.0.0' -ErrorAction Stop } |
            Should -Not -Throw

        Test-Path $Script:PayloadPath -PathType Leaf | Should -BeTrue -Because 'a matching file must be left in place'
    }

    It 'Should accept an upper-case expected hash, since hex casing carries no meaning' {
        { Confirm-FileHash -Path $Script:PayloadPath -ExpectedSha256 $Script:HelloSha256.ToUpperInvariant() -ArtifactName 'Test 1.0.0' -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'Should refuse a file whose hash does not match the pin' {
        Set-Content -Path $Script:PayloadPath -Value 'tampered' -NoNewline

        { Confirm-FileHash -Path $Script:PayloadPath -ExpectedSha256 $Script:HelloSha256 -ArtifactName 'Test 1.0.0' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*Integrity check FAILED*'
    }

    It 'Should delete the file on a mismatch rather than merely rejecting it' {
        # The whole point: unverified bytes must not be left on disk for a later code path to pick up.
        Set-Content -Path $Script:PayloadPath -Value 'tampered' -NoNewline

        try {
            Confirm-FileHash -Path $Script:PayloadPath -ExpectedSha256 $Script:HelloSha256 -ArtifactName 'Test 1.0.0' -ErrorAction Stop
        }
        catch {}

        Test-Path $Script:PayloadPath -PathType Leaf | Should -BeFalse
    }

    It 'Should name the artefact, the source and both hashes in the failure' {
        Set-Content -Path $Script:PayloadPath -Value 'tampered' -NoNewline

        $Message = $null
        try {
            Confirm-FileHash -Path $Script:PayloadPath -ExpectedSha256 $Script:HelloSha256 -ArtifactName 'Test 1.0.0' -SourceUrl 'https://example.invalid/test.nupkg' -ErrorAction Stop
        }
        catch {
            $Message = $_.Exception.Message
        }

        $Message | Should -BeLike '*Test 1.0.0*'
        $Message | Should -BeLike '*https://example.invalid/test.nupkg*'
        $Message | Should -BeLike ('*{0}*' -f $Script:HelloSha256)
        # SHA-256 of "tampered".
        $Message | Should -BeLike '*d121be3103007b41edf96f8262925f8c7d61894afe9a041843b631f69445bc57*'
    }

    It 'Should fail closed when the expected hash is blank instead of accepting anything' {
        { Confirm-FileHash -Path $Script:PayloadPath -ExpectedSha256 '' -ArtifactName 'Test 1.0.0' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*no expected SHA-256*'
    }

    It 'Should fail when the file does not exist' {
        { Confirm-FileHash -Path (Join-Path $TestDrive 'missing.bin') -ExpectedSha256 $Script:HelloSha256 -ArtifactName 'Test 1.0.0' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*does not exist*'
    }
}
