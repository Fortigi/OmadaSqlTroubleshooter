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

    It 'Should list the files taken out of every package' {
        # The package hash cannot verify a file that has been extracted out of the package, and the
        # build-time bundle ships exactly those extracted files. Without a Files list there is
        # nothing for Get-BundledDependency to copy and nothing for Test-WebView2Bundle to check.
        foreach ($Artifact in $Script:Artifacts) {
            @($Artifact.Files).Count | Should -BeGreaterThan 0 -Because "artefact '$($Artifact.Id)' is bundled at build time"
        }
    }

    It 'Should pin a 64-character lower-case SHA-256 for every bundled file' {
        foreach ($Artifact in $Script:Artifacts) {
            foreach ($File in @($Artifact.Files)) {
                $File.Sha256 | Should -Match '^[0-9a-f]{64}$' -Because "'$($File.Target)' is re-verified immediately before it is loaded"
                $File.Source | Should -Not -BeNullOrEmpty
                $File.Target | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'Should map each bundled file onto a unique target name' {
        # Microsoft.Web.WebView2.Wpf.dll exists three times in the package with different bytes. Two
        # sources writing one target would mean whichever copied last wins - the exact ambiguity the
        # two old fetchers disagreed about.
        foreach ($Artifact in $Script:Artifacts) {
            $Duplicate = @($Artifact.Files) | Group-Object { $_.Target } | Where-Object { $_.Count -gt 1 }
            $Duplicate | Should -BeNullOrEmpty -Because "artefact '$($Artifact.Id)' must resolve one source per target"
        }
    }

    It 'Should reference package entries by their in-archive path' {
        foreach ($Artifact in $Script:Artifacts) {
            foreach ($File in @($Artifact.Files)) {
                $File.Source | Should -Not -Match '\\' -Because 'zip entry names use forward slashes'
                $File.Source | Should -BeLike ('*{0}' -f $File.Target) -Because "'$($File.Source)' should end in the file it produces"
            }
        }
    }

    It 'Should take the WPF assembly from the framework Install-WebView2 has always used' {
        # netcoreapp3.0, not net5.0-windows10.0.17763.0 and not net462. All three ship a
        # Microsoft.Web.WebView2.Wpf.dll with different bytes; the deleted build/RetrieveDependencies.ps1
        # took the net5.0 one while the module loaded the netcoreapp3.0 one.
        $WebView2 = @($Script:Artifacts | Where-Object { $_.Id -eq 'Microsoft.Web.WebView2' })[0]
        $Wpf = @($WebView2.Files | Where-Object { $_.Target -eq 'Microsoft.Web.WebView2.Wpf.dll' })[0]
        $Wpf | Should -Not -BeNullOrEmpty
        $Wpf.Source | Should -Be 'lib_manual/netcoreapp3.0/Microsoft.Web.WebView2.Wpf.dll'
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

    It 'Should have its bundled files fetched into the package by psake' {
        # Task Dependencies is what puts the assemblies in the package. Part A removed a Task
        # Dependencies that was in no task chain at all, so the package contained no bin folder;
        # asserting the call and the chain together is what keeps that from recurring.
        $Psake = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath 'build\psakeBuild.ps1') -Raw

        $Psake | Should -Match 'Get-BundledDependency\.ps1' -Because 'something has to fetch the bundle'
        $Psake | Should -Match 'Task Build -Depends Test, Dependencies' -Because 'bundling must be in every chain that publishes, including the nightly which runs a bare Build'
    }

    It 'Should have the bundled files verified by psake before the package is published' {
        $Psake = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath 'build\psakeBuild.ps1') -Raw

        $Psake | Should -Match 'Task TestAssemblies'
        foreach ($Chain in @('Task TestBuildOnly', 'Task Pipeline')) {
            $ChainLine = [regex]::Match($Psake, ('(?m)^{0}.*$' -f [regex]::Escape($Chain))).Value
            $ChainLine | Should -Match 'TestAssemblies' -Because "a package with a broken bundle still imports, so '$Chain' would not otherwise notice"
        }
    }

    It 'Should not require the WebView2 Runtime executable in the build output' {
        # msedgewebview2.exe is the 260 MB WebView2 Runtime, which this project does not
        # redistribute (THIRD-PARTY-NOTICES.md section 3.1). The old TestAssemblies demanded it and
        # could therefore only ever fail.
        $Psake = Get-Content -Path (Join-Path $Script:RepositoryRoot -ChildPath 'build\psakeBuild.ps1') -Raw
        $TaskBody = [regex]::Match($Psake, '(?s)Task TestAssemblies\b[^\{]*\{.*?\r?\n\}').Value

        $TaskBody | Should -Not -BeNullOrEmpty
        $TaskBody | Should -Not -Match 'msedgewebview2'
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
