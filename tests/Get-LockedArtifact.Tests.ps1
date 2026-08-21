BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    # Dot-sourced so it exists to be mocked below; Pester cannot mock a command that is not defined.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-DependencyLock.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-LockedArtifact.ps1")
    $Script:DependencyLockPath = Join-Path $ParentPath -ChildPath "src\DependencyLock.psd1"
}

Describe 'Get-LockedArtifact' -Tag 'Unit' {

    BeforeEach {
        # A stand-in lock, so these tests assert the lookup's behaviour rather than the current pins.
        Mock Get-DependencyLock {
            @{
                SchemaVersion = 1
                Artifacts     = @(
                    @{ Id = 'Test.Pinned'; Version = '1.2.3'; Verification = 'Sha256' }
                    @{ Id = 'Test.Other'; Version = '4.5.6'; Verification = 'Sha256' }
                )
            }
        }
    }

    It 'Should return the entry for a known id' {
        $Artifact = Get-LockedArtifact -Id 'Test.Pinned'

        $Artifact.Id | Should -Be 'Test.Pinned'
        $Artifact.Version | Should -Be '1.2.3'
    }

    It 'Should return a single entry, not a one-element array' {
        $Artifact = Get-LockedArtifact -Id 'Test.Other'

        $Artifact.Version | Should -Be '4.5.6'
    }

    It 'Should fail closed on an id that is not pinned' {
        # An artefact nobody pinned is an artefact nobody can verify.
        { Get-LockedArtifact -Id 'Definitely.Not.Pinned' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*no lock entry for artefact*'
    }

    It 'Should fail closed on a duplicated id rather than picking one' {
        Mock Get-DependencyLock {
            @{
                SchemaVersion = 1
                Artifacts     = @(
                    @{ Id = 'Test.Duplicate'; Version = '1.0.0'; Verification = 'Sha256' }
                    @{ Id = 'Test.Duplicate'; Version = '9.9.9'; Verification = 'Sha256' }
                )
            }
        }

        { Get-LockedArtifact -Id 'Test.Duplicate' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*is listed 2 times*'
    }
}
