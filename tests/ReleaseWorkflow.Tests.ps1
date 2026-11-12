#Requires -Version 7.0

# Guards the split between creating a release and publishing it. release.yml creates a DRAFT and must
# never publish to the PowerShell Gallery itself: the Gallery publish belongs to
# publish-psgallery.yml, which only runs once a maintainer publishes the draft, so the Gallery
# version and the follower notifications go out together after the release notes are final.

BeforeAll {
    $Script:WorkflowsPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '.github' -AdditionalChildPath 'workflows'
    $Script:Release = Get-Content -LiteralPath (Join-Path -Path $Script:WorkflowsPath -ChildPath 'release.yml') -Raw
    $Script:Publish = Get-Content -LiteralPath (Join-Path -Path $Script:WorkflowsPath -ChildPath 'publish-psgallery.yml') -Raw
}

Describe 'Release workflow' -Tag 'Unit' {

    It 'Should create the GitHub release as a draft' {
        $Script:Release | Should -Match '(?m)^\s+draft:\s*true\s*$'
    }

    It 'Should not publish to the PowerShell Gallery' {
        $Script:Release | Should -Not -Match 'PushToPsGallery|PSGALLERY_API_KEY|Publish-Module' -Because 'the Gallery publish must wait until the draft release is published'
    }
}

Describe 'PowerShell Gallery publish workflow' -Tag 'Unit' {

    It 'Should run only when a release is published' {
        $Script:Publish | Should -Match '(?ms)^on:\s*\r?\n\s+release:\s*\r?\n\s+types:\s*\[\s*published\s*\]'
        $Script:Publish | Should -Not -Match '(?m)^\s+(push|workflow_dispatch|schedule|pull_request\w*):' -Because 'any other trigger would publish without a published release'
    }

    It 'Should skip pre-releases and nightly tags' {
        $Script:Publish | Should -Match 'github\.event\.release\.prerelease == false'
        $Script:Publish | Should -Match "!endsWith\(github\.event\.release\.tag_name, '-nightly'\)"
    }

    It 'Should verify the release package before publishing it' {
        foreach ($Command in 'ConvertFrom-ReleaseTag', 'Select-ReleasePackageAsset', 'Assert-ReleaseAssetDigest', 'Expand-ReleasePackage') {
            $Script:Publish | Should -Match ([regex]::Escape($Command))
        }
        $Script:Publish.IndexOf('Expand-ReleasePackage') | Should -BeLessThan $Script:Publish.IndexOf('PushToPsGallery.ps1')
    }

    It 'Should only read repository contents' {
        $Script:Publish | Should -Not -Match '(?m)^\s+contents:\s*write'
    }
}
