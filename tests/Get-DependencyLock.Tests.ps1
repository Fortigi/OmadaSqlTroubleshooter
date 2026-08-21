BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-DependencyLock.ps1")
}

Describe 'Get-DependencyLock' -Tag 'Unit' {

    BeforeEach {
        # The cache is module state; clear it so each test starts from a cold read.
        $Script:DependencyLock = $null
    }

    It 'Should read the lock file that ships with the module' {
        $Script:DependencyLockPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\DependencyLock.psd1"

        $Lock = Get-DependencyLock

        $Lock.SchemaVersion | Should -Be 1
        @($Lock.Artifacts).Count | Should -BeGreaterThan 0
    }

    It 'Should cache the result so the lock is read once per session' {
        $Script:DependencyLockPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\DependencyLock.psd1"

        $First = Get-DependencyLock

        # Point the path at nothing. A second read would fail; a cached one cannot.
        $Script:DependencyLockPath = Join-Path $TestDrive 'gone.psd1'
        $Second = Get-DependencyLock

        $Second.Artifacts[0].Id | Should -Be $First.Artifacts[0].Id
    }

    It 'Should refuse to run when the lock file is missing rather than downloading unverified' {
        $Script:DependencyLockPath = Join-Path $TestDrive 'does-not-exist.psd1'

        { Get-DependencyLock -ErrorAction Stop } | Should -Throw -ExpectedMessage '*is missing*'
    }

    It 'Should refuse a lock file written to a schema it does not understand' {
        $FuturePath = Join-Path $TestDrive 'future.psd1'
        Set-Content -Path $FuturePath -Value "@{ SchemaVersion = 99; Artifacts = @(@{ Id = 'X' }) }"
        $Script:DependencyLockPath = $FuturePath

        { Get-DependencyLock -ErrorAction Stop } | Should -Throw -ExpectedMessage '*schema version*'
    }

    It 'Should refuse a lock file that pins nothing, since every download would be refused' {
        $EmptyPath = Join-Path $TestDrive 'empty.psd1'
        Set-Content -Path $EmptyPath -Value "@{ SchemaVersion = 1; Artifacts = @() }"
        $Script:DependencyLockPath = $EmptyPath

        { Get-DependencyLock -ErrorAction Stop } | Should -Throw -ExpectedMessage '*lists no artefacts*'
    }

    It 'Should refuse a file that is not a hashtable at all' {
        $GarbagePath = Join-Path $TestDrive 'garbage.psd1'
        Set-Content -Path $GarbagePath -Value "'just a string'"
        $Script:DependencyLockPath = $GarbagePath

        { Get-DependencyLock -ErrorAction Stop } | Should -Throw -ExpectedMessage '*could not be read*'
    }

    It 'Should refuse a data file containing a command invocation instead of executing it' {
        # SafeGetValue evaluates constant expressions only. This is what stops a tampered lock file
        # from being a code-execution vector in its own right.
        $HostilePath = Join-Path $TestDrive 'hostile.psd1'
        $CanaryPath = Join-Path $TestDrive 'canary.txt'
        Set-Content -Path $HostilePath -Value ("@{{ SchemaVersion = 1; Artifacts = @(); Evil = (New-Item -Path '{0}' -ItemType File) }}" -f ($CanaryPath -replace '\\', '\\'))
        $Script:DependencyLockPath = $HostilePath

        { Get-DependencyLock -ErrorAction Stop } | Should -Throw

        Test-Path $CanaryPath | Should -BeFalse -Because 'the parser must not execute anything in the data file'
    }
}
