BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:LockPath = Join-Path $Script:RepositoryRoot -ChildPath 'src\DependencyLock.psd1'
    $Script:PrivatePath = Join-Path $Script:RepositoryRoot -ChildPath 'src\Lib\Functions\Private'

    $Script:Lock = Import-PowerShellDataFile -Path $Script:LockPath
    $Script:Artifacts = @($Script:Lock.Artifacts)
}

Describe 'DependencyLock.psd1' -Tag 'Unit' {

    It 'Should exist next to the psm1 so $PSScriptRoot resolves it in src and in the package' {
        Test-Path $Script:LockPath -PathType Leaf | Should -BeTrue
    }

    It 'Should declare a schema version the module understands' {
        $Script:Lock.SchemaVersion | Should -Be 1
    }

    It 'Should pin at least one artefact' {
        $Script:Artifacts.Count | Should -BeGreaterThan 0
    }

    It 'Should list every artefact exactly once' {
        $Duplicate = $Script:Artifacts | Group-Object { $_.Id } | Where-Object { $_.Count -gt 1 }
        $Duplicate | Should -BeNullOrEmpty -Because 'Get-LockedArtifact fails closed on an ambiguous id'
    }

    It 'Should use only the verification mode this module implements' {
        foreach ($Artifact in $Script:Artifacts) {
            # OmadaWeb.PS additionally has an Authenticode mode for msedgedriver.exe. Nothing here
            # needs it, and Invoke-DownloadFile refuses anything that is not Sha256.
            $Artifact.Verification | Should -Be 'Sha256'
        }
    }

    It 'Should pin a 64-character lower-case SHA-256 for every artefact' {
        foreach ($Artifact in $Script:Artifacts) {
            $Artifact.Sha256 | Should -Match '^[0-9a-f]{64}$' -Because "artefact '$($Artifact.Id)' is verified by hash"
            $Artifact.Version | Should -Not -BeNullOrEmpty -Because "artefact '$($Artifact.Id)' is verified by hash"
        }
    }

    It 'Should derive every download URL from the pinned package and version' {
        foreach ($Artifact in $Script:Artifacts) {
            $Expected = 'https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg' -f $Artifact.PackageId.ToLowerInvariant(), $Artifact.Version.ToLowerInvariant()
            $Artifact.Url | Should -Be $Expected -Because "artefact '$($Artifact.Id)' must be fetched from the version it is pinned to"
        }
    }

    It 'Should have an entry for every artefact the module downloads' {
        # Guards against a new download slipping in unpinned. It would fail closed at runtime, which
        # is safe, but is a bug better caught here.
        $KnownId = @($Script:Artifacts | ForEach-Object { $_.Id })
        $Requested = Get-ChildItem -Path $Script:PrivatePath -Filter '*.ps1' -File |
            Select-String -Pattern '-ArtifactId\s+"(?<Id>[^"]+)"' -AllMatches |
            ForEach-Object { $_.Matches } |
            ForEach-Object { $_.Groups['Id'].Value } |
            Sort-Object -Unique

        @($Requested).Count | Should -BeGreaterThan 0
        foreach ($Id in $Requested) {
            $KnownId | Should -Contain $Id -Because "Invoke-DownloadFile -ArtifactId '$Id' would otherwise be refused at runtime"
        }
    }

    It 'Should name an installer that exists for every artefact' {
        foreach ($Artifact in $Script:Artifacts) {
            $InstallerPath = Join-Path $Script:PrivatePath -ChildPath ('{0}.ps1' -f $Artifact.InstalledBy)
            Test-Path $InstallerPath -PathType Leaf | Should -BeTrue -Because "artefact '$($Artifact.Id)' claims to be installed by '$($Artifact.InstalledBy)'"
        }
    }
}

Describe 'Dependency manifest' -Tag 'Unit' {

    It 'Should declare every pinned artefact so Dependabot can raise advisories against it' {
        foreach ($Artifact in $Script:Artifacts) {
            $ManifestPath = Join-Path $Script:RepositoryRoot -ChildPath $Artifact.Manifest
            Test-Path $ManifestPath -PathType Leaf | Should -BeTrue -Because "artefact '$($Artifact.Id)' names manifest '$($Artifact.Manifest)'"

            [xml]$Manifest = Get-Content -Path $ManifestPath -Raw
            $Reference = @($Manifest.Project.ItemGroup.PackageReference | Where-Object { $_.Include -eq $Artifact.PackageId })

            $Reference.Count | Should -Be 1 -Because "'$($Artifact.PackageId)' must appear once in '$($Artifact.Manifest)' to enter the dependency graph"
            $Reference[0].Version | Should -Be $Artifact.Version -Because 'a pin that disagrees with the manifest means the hash was never refreshed'
        }
    }

    It 'Should be watched by Dependabot' {
        $Dependabot = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath '.github\dependabot.yml') -Raw
        $Dependabot | Should -Match 'nuget'
        $Dependabot | Should -Match '/build/Dependencies'
    }
}

Describe 'Dependency lock packaging' -Tag 'Unit' {

    # The lock is deliberately NOT listed in the psd1's FileList. The nuspec packages
    # buildoutput\OmadaSqlTroubleShooter\** wholesale and Publish-Module -Path <folder> publishes the
    # whole folder; neither consults FileList, so a FileList naming one file out of hundreds would be
    # worse documentation than none. These two assertions, plus the post-condition in psakeBuild.ps1,
    # are what stand in for it.

    It 'Should be copied into the build output by psake' {
        $Psake = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath 'build\psakeBuild.ps1') -Raw
        $Psake | Should -Match 'DependencyLock\.psd1' -Because 'a package without the lock refuses every download'
    }

    It 'Should be copied by the local deploy script' {
        $Deploy = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath 'deploy\deploy.ps1') -Raw
        $Deploy | Should -Match 'DependencyLock\.psd1'
    }

    It 'Should be verified by every CI lane that builds or publishes' {
        foreach ($Workflow in @('pr-validation.yml', 'release.yml', 'nightly.yml')) {
            $Content = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath ('.github\workflows\{0}' -f $Workflow)) -Raw
            $Content | Should -Match 'Update-DependencyLock\.ps1 -Check' -Because "$Workflow must fail on a drifted pin"
        }
    }
}

Describe 'No second download path' -Tag 'Unit' {

    It 'Should not have reintroduced an unverified NuGet fetch' {
        # The old build/deploy RetrieveFromNuGet wrote unverified bytes straight to disk, bypassing
        # the SHA-256 gate. If it comes back, this fails.
        $Suspect = Get-ChildItem -Path (Join-Path $Script:RepositoryRoot -ChildPath 'build'), (Join-Path $Script:RepositoryRoot -ChildPath 'deploy') -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'Update-DependencyLock.ps1' } |
            Select-String -Pattern 'nuget\.org/api/v2/package' -SimpleMatch:$false

        $Suspect | Should -BeNullOrEmpty -Because 'every download must go through Invoke-DownloadFile and its hash check'
    }
}
