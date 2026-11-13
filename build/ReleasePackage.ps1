<#
    Functions behind the PowerShell Gallery publish (.github/workflows/publish-psgallery.yml).

    Dot-sourced by that workflow and by tests/ReleasePackage.Tests.ps1.

    The publish runs when a maintainer publishes the draft GitHub release that
    .github/workflows/release.yml creates. It does not rebuild the module: it publishes the exact
    .nupkg the release workflow built, tested and attached to that release. These functions decide
    whether the release and its package may be published, and turn the package back into the module
    folder Publish-Module expects. Every check fails closed: anything unexpected throws and nothing
    reaches the Gallery.

    All GitHub access stays in the workflow, so these are plain functions of their inputs.
#>

# The identity GitHub records as uploader for assets attached with the workflow's GITHUB_TOKEN. A
# package uploaded by hand through the Releases page or by a personal token carries a user login
# instead, and is rejected: only what the release workflow built may be published.
$Script:ReleaseAssetUploader = 'github-actions[bot]'

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.ZipFile

function ConvertFrom-ReleaseTag {
    <#
    .SYNOPSIS
        Returns the module version a stable release tag stands for.
    .DESCRIPTION
        Accepts only the tag format release.yml creates: v<yyyy>.<MM>.<dd>.<run number>. A nightly
        tag (-nightly suffix) or any other format throws, so a pre-release or a hand-made tag can
        never be published as a stable Gallery version.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Tag
    )

    if ($Tag -notmatch '^v(?<Version>\d{4}\.\d{2}\.\d{2}\.\d+)$') {
        throw "Release tag '$Tag' is not a stable release tag (expected v<yyyy>.<MM>.<dd>.<run number>)."
    }

    return [version]$Matches.Version
}

function Select-ReleasePackageAsset {
    <#
    .SYNOPSIS
        Returns the one .nupkg asset of a published, stable release that the release workflow uploaded.
    .PARAMETER Release
        The release object as returned by GET /repos/{owner}/{repo}/releases/tags/{tag}.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Release
    )

    if ($Release.draft -ne $false) {
        throw "Release '$($Release.tag_name)' is still a draft."
    }
    if ($Release.prerelease -ne $false) {
        throw "Release '$($Release.tag_name)' is a pre-release; only stable releases are published to the PowerShell Gallery."
    }

    $Packages = @($Release.assets | Where-Object { $_.name -like '*.nupkg' })
    if ($Packages.Count -ne 1) {
        throw "Release '$($Release.tag_name)' has $($Packages.Count) .nupkg assets; exactly one is required."
    }

    $Package = $Packages[0]
    if ($Package.state -ne 'uploaded') {
        throw "Asset '$($Package.name)' is in state '$($Package.state)', not 'uploaded'."
    }
    if ($Package.uploader.login -ne $Script:ReleaseAssetUploader) {
        throw "Asset '$($Package.name)' was uploaded by '$($Package.uploader.login)', not by the release workflow ('$Script:ReleaseAssetUploader')."
    }
    if ([string]::IsNullOrWhiteSpace($Package.digest)) {
        throw "Asset '$($Package.name)' has no digest to verify the download against."
    }

    return $Package
}

function Assert-ReleaseAssetDigest {
    <#
    .SYNOPSIS
        Throws unless the file's SHA-256 matches the digest GitHub reports for the release asset.
    .PARAMETER Digest
        The asset's digest field, in the form 'sha256:<hex>'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Digest
    )

    if ($Digest -notmatch '^sha256:(?<Hash>[0-9a-fA-F]{64})$') {
        throw "Unsupported asset digest '$Digest' (expected sha256:<64 hex characters>)."
    }

    $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if (-not [string]::Equals($Actual, $Matches.Hash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "SHA-256 of '$Path' is $Actual, but the release asset digest is $($Matches.Hash)."
    }

    Write-Host "SHA-256 verified: $Actual"
}

function Test-NuGetPackageMetadataPath {
    <#
    .SYNOPSIS
        True for the entries nuget pack adds around the module files, which are not part of the module.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    return (
        $RelativePath -eq '[Content_Types].xml' -or
        $RelativePath -like '_rels/*' -or
        $RelativePath -like 'package/*' -or
        ($RelativePath -like '*.nuspec' -and $RelativePath -notlike '*/*')
    )
}

function Expand-ReleasePackage {
    <#
    .SYNOPSIS
        Extracts the module from a release .nupkg into an empty folder and verifies its manifest.
    .DESCRIPTION
        The release nuspec packs the module folder at the package root (target=""), so the package
        is the module plus NuGet's own metadata entries, which are skipped here. Entry names are
        percent-decoded, because nuget pack encodes characters such as spaces in them. An entry that
        would land outside the destination folder throws.

        The module manifest must exist and carry exactly the version the release tag stands for,
        with no pre-release label. Returns the manifest file.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [version]$ExpectedVersion
    )

    # Resolved against the PowerShell location, not the process working directory that the .NET
    # path APIs below would otherwise use.
    $PackagePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($PackagePath)
    $DestinationPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DestinationPath)

    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "Package '$PackagePath' does not exist."
    }
    if (Test-Path -LiteralPath $DestinationPath) {
        if (Get-ChildItem -LiteralPath $DestinationPath -Force | Select-Object -First 1) {
            throw "Destination '$DestinationPath' is not empty."
        }
    }
    else {
        [void][System.IO.Directory]::CreateDirectory($DestinationPath)
    }

    $Root = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $RootPrefix = $Root + [System.IO.Path]::DirectorySeparatorChar

    $Archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        foreach ($Entry in $Archive.Entries) {
            $RelativePath = [System.Uri]::UnescapeDataString($Entry.FullName).Replace('\', '/')
            if ($RelativePath.EndsWith('/') -or (Test-NuGetPackageMetadataPath -RelativePath $RelativePath)) {
                continue
            }

            $TargetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Root, $RelativePath))
            if (-not $TargetPath.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Package entry '$($Entry.FullName)' resolves outside '$Root'."
            }

            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($TargetPath))
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $TargetPath, $false)
        }
    }
    finally {
        $Archive.Dispose()
    }

    $ManifestPath = Join-Path -Path $Root -ChildPath ('{0}.psd1' -f $ModuleName)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Package does not contain the module manifest '$ModuleName.psd1' at its root."
    }

    $Manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
    if ([version]$Manifest.ModuleVersion -ne $ExpectedVersion) {
        throw "Module manifest version $($Manifest.ModuleVersion) does not match release version $ExpectedVersion."
    }
    $Prerelease = $Manifest.PrivateData.PSData.Prerelease
    if (-not [string]::IsNullOrWhiteSpace($Prerelease)) {
        throw "Module manifest carries pre-release label '$Prerelease'; a stable release must not."
    }

    return (Get-Item -LiteralPath $ManifestPath)
}
