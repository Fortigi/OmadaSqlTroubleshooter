#Requires -Version 7.0

# The PowerShell Gallery publish runs on its own when a release is published, and a version on the
# Gallery cannot be replaced. Every function here fails closed; these tests pin that a wrong tag,
# release, asset, digest or package is refused rather than published.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $ParentPath -ChildPath 'build' -AdditionalChildPath 'ReleasePackage.ps1')

    $Script:ModuleName = 'OmadaSqlTroubleShooter'

    function New-TestPackage {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][hashtable]$Entries
        )

        $Archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($Name in $Entries.Keys) {
                $Writer = [System.IO.StreamWriter]::new($Archive.CreateEntry($Name).Open())
                try { $Writer.Write($Entries[$Name]) } finally { $Writer.Dispose() }
            }
        }
        finally {
            $Archive.Dispose()
        }
    }

    function New-Manifest {
        param([string]$Version = '2026.11.12.5', [string]$Prerelease = '')
        "@{ ModuleVersion = '$Version'; PrivateData = @{ PSData = @{ Prerelease = '$Prerelease' } } }"
    }

    function New-Release {
        param(
            [object]$Draft = $false,
            [object]$Prerelease = $false,
            [object[]]$Assets = @(New-Asset)
        )
        [PSCustomObject]@{ tag_name = 'v2026.11.12.5'; draft = $Draft; prerelease = $Prerelease; assets = $Assets }
    }

    function New-Asset {
        param(
            [string]$Name = 'OmadaSqlTroubleshooter.2026.11.12.5.nupkg',
            [string]$Uploader = 'github-actions[bot]',
            [string]$State = 'uploaded',
            [string]$Digest = ('sha256:{0}' -f ('a' * 64))
        )
        [PSCustomObject]@{ name = $Name; state = $State; digest = $Digest; uploader = [PSCustomObject]@{ login = $Uploader } }
    }
}

Describe 'ConvertFrom-ReleaseTag' -Tag 'Unit' {

    It 'Should return the version of a stable release tag' {
        ConvertFrom-ReleaseTag -Tag 'v2026.11.12.5' | Should -Be ([version]'2026.11.12.5')
    }

    It 'Should refuse <Tag>' -ForEach @(
        @{ Tag = 'v2026.11.12.5-nightly' }
        @{ Tag = '2026.11.12.5' }
        @{ Tag = 'v2026.11.12' }
        @{ Tag = 'v1.2.3.4' }
        @{ Tag = 'v2026.11.12.5 ' }
        @{ Tag = '' }
    ) {
        { ConvertFrom-ReleaseTag -Tag $Tag } | Should -Throw '*not a stable release tag*'
    }
}

Describe 'Select-ReleasePackageAsset' -Tag 'Unit' {

    It 'Should return the package uploaded by the release workflow' {
        $Asset = Select-ReleasePackageAsset -Release (New-Release)
        $Asset.name | Should -Be 'OmadaSqlTroubleshooter.2026.11.12.5.nupkg'
    }

    It 'Should ignore assets that are not packages' {
        $Release = New-Release -Assets @((New-Asset -Name 'notes.txt' -Uploader 'someone'), (New-Asset))
        (Select-ReleasePackageAsset -Release $Release).name | Should -BeLike '*.nupkg'
    }

    It 'Should refuse a draft release' {
        { Select-ReleasePackageAsset -Release (New-Release -Draft $true) } | Should -Throw '*still a draft*'
    }

    It 'Should refuse a pre-release' {
        { Select-ReleasePackageAsset -Release (New-Release -Prerelease $true) } | Should -Throw '*pre-release*'
    }

    It 'Should refuse a release whose draft flag is missing' {
        { Select-ReleasePackageAsset -Release (New-Release -Draft $null) } | Should -Throw '*still a draft*'
    }

    It 'Should refuse <Count> packages' -ForEach @(
        @{ Count = 0 }
        @{ Count = 2 }
    ) {
        $Assets = @(1..2 | Select-Object -First $Count | ForEach-Object { New-Asset -Name "p$_.nupkg" })
        { Select-ReleasePackageAsset -Release (New-Release -Assets $Assets) } | Should -Throw "*has $Count .nupkg assets*"
    }

    It 'Should refuse a package uploaded by someone other than the release workflow' {
        { Select-ReleasePackageAsset -Release (New-Release -Assets @(New-Asset -Uploader 'maintainer')) } | Should -Throw "*uploaded by 'maintainer'*"
    }

    It 'Should refuse a package that is not fully uploaded' {
        { Select-ReleasePackageAsset -Release (New-Release -Assets @(New-Asset -State 'starter')) } | Should -Throw "*state 'starter'*"
    }

    It 'Should refuse a package without a digest' {
        { Select-ReleasePackageAsset -Release (New-Release -Assets @(New-Asset -Digest '')) } | Should -Throw '*no digest*'
    }
}

Describe 'Assert-ReleaseAssetDigest' -Tag 'Unit' {

    BeforeAll {
        $Script:File = Join-Path -Path $TestDrive -ChildPath 'package.nupkg'
        Set-Content -LiteralPath $Script:File -Value 'package' -NoNewline
        $Script:Hash = (Get-FileHash -LiteralPath $Script:File -Algorithm SHA256).Hash
    }

    It 'Should accept a matching digest in any letter case' {
        { Assert-ReleaseAssetDigest -Path $Script:File -Digest ('sha256:{0}' -f $Script:Hash.ToLowerInvariant()) } | Should -Not -Throw
    }

    It 'Should refuse a different digest' {
        { Assert-ReleaseAssetDigest -Path $Script:File -Digest ('sha256:{0}' -f ('0' * 64)) } | Should -Throw '*but the release asset digest is*' -Because 'only a byte-identical download may be published'
    }

    It 'Should refuse a digest that is not SHA-256' {
        { Assert-ReleaseAssetDigest -Path $Script:File -Digest ('sha1:{0}' -f ('0' * 40)) } | Should -Throw '*Unsupported asset digest*'
    }
}

Describe 'Expand-ReleasePackage' -Tag 'Unit' {

    BeforeEach {
        $Script:Package = Join-Path -Path $TestDrive -ChildPath ('{0}.nupkg' -f [guid]::NewGuid())
        $Script:Destination = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid()) -AdditionalChildPath $Script:ModuleName
        $Script:Arguments = @{
            PackagePath     = $Script:Package
            DestinationPath = $Script:Destination
            ModuleName      = $Script:ModuleName
            ExpectedVersion = [version]'2026.11.12.5'
        }
    }

    It 'Should extract the module files and leave out the NuGet metadata' {
        New-TestPackage -Path $Script:Package -Entries @{
            '[Content_Types].xml'                                      = '<Types />'
            '_rels/.rels'                                              = '<Relationships />'
            'package/services/metadata/core-properties/abc.psmdcp'     = '<coreProperties />'
            'OmadaSqlTroubleshooter.nuspec'                            = '<package />'
            'OmadaSqlTroubleShooter.psd1'                              = New-Manifest
            'OmadaSqlTroubleShooter.psm1'                              = '# module'
            'Lib/functions/Get-Thing.ps1'                              = '# function'
            'Lib/package/inside.ps1'                                   = '# a nested folder named package is module content'
        }

        $Manifest = Expand-ReleasePackage @Script:Arguments

        $Manifest.Name | Should -Be 'OmadaSqlTroubleShooter.psd1'
        $Files = Get-ChildItem -LiteralPath $Script:Destination -Recurse -File -Force |
            ForEach-Object { [System.IO.Path]::GetRelativePath($Script:Destination, $_.FullName).Replace('\', '/') } |
            Sort-Object
        $Files | Should -Be @('Lib/functions/Get-Thing.ps1', 'Lib/package/inside.ps1', 'OmadaSqlTroubleShooter.psd1', 'OmadaSqlTroubleShooter.psm1')
    }

    It 'Should decode percent-encoded entry names' {
        New-TestPackage -Path $Script:Package -Entries @{
            'OmadaSqlTroubleShooter.psd1'  = New-Manifest
            'Lib/Some%20File%20%281%29.tmp' = 'x'
        }

        Expand-ReleasePackage @Script:Arguments | Out-Null

        Test-Path -LiteralPath (Join-Path -Path $Script:Destination -ChildPath 'Lib' -AdditionalChildPath 'Some File (1).tmp') | Should -BeTrue
    }

    It 'Should refuse an entry that resolves outside the destination' {
        New-TestPackage -Path $Script:Package -Entries @{
            'OmadaSqlTroubleShooter.psd1' = New-Manifest
            '../escaped.ps1'              = '# outside'
        }

        { Expand-ReleasePackage @Script:Arguments } | Should -Throw '*resolves outside*'
    }

    It 'Should refuse a destination that is not empty' {
        New-TestPackage -Path $Script:Package -Entries @{ 'OmadaSqlTroubleShooter.psd1' = New-Manifest }
        New-Item -Path $Script:Destination -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $Script:Destination -ChildPath 'stale.ps1') -Value '# stale'

        { Expand-ReleasePackage @Script:Arguments } | Should -Throw '*not empty*'
    }

    It 'Should refuse a package without the module manifest' {
        New-TestPackage -Path $Script:Package -Entries @{ 'OmadaSqlTroubleShooter.psm1' = '# module' }

        { Expand-ReleasePackage @Script:Arguments } | Should -Throw '*does not contain the module manifest*'
    }

    It 'Should refuse a manifest with a different version' {
        New-TestPackage -Path $Script:Package -Entries @{ 'OmadaSqlTroubleShooter.psd1' = New-Manifest -Version '2026.11.12.4' }

        { Expand-ReleasePackage @Script:Arguments } | Should -Throw '*does not match release version*'
    }

    It 'Should treat leading zeros in the manifest version as the same version' {
        New-TestPackage -Path $Script:Package -Entries @{ 'OmadaSqlTroubleShooter.psd1' = New-Manifest -Version '2026.09.03.5' }
        $Script:Arguments.ExpectedVersion = [version]'2026.9.3.5'

        { Expand-ReleasePackage @Script:Arguments } | Should -Not -Throw
    }

    It 'Should refuse a manifest with a pre-release label' {
        New-TestPackage -Path $Script:Package -Entries @{ 'OmadaSqlTroubleShooter.psd1' = New-Manifest -Prerelease 'nightly5' }

        { Expand-ReleasePackage @Script:Arguments } | Should -Throw '*pre-release label*'
    }

    It 'Should refuse a package that does not exist' {
        { Expand-ReleasePackage @Script:Arguments } | Should -Throw '*does not exist*'
    }
}
