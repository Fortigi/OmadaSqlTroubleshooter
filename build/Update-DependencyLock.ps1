#Requires -Version 5.1

<#
.SYNOPSIS
    Checks or refreshes the pinned versions and SHA-256 hashes in src/DependencyLock.psd1.
.DESCRIPTION
    OmadaSqlTroubleshooter downloads the WebView2 .NET SDK at runtime and verifies it against the
    pinned SHA-256 in src/DependencyLock.psd1 before the package is expanded or copied into Bin. That
    only holds if the lock file stays truthful, which is what this script is for.

    The versions themselves live in the Dependabot manifest under build/Dependencies. Dependabot bumps
    a version there, this script recomputes the matching URL and hash, and PR validation fails for as
    long as the two disagree.

    -Check validates the lock file and reports drift without changing anything. It is what runs in CI:
    schema and formatting, one entry per artefact, versions matching the manifest, every -ArtifactId
    used in the module present in the lock, and - unless -SkipDownload is given - the published bytes
    still hashing to what is pinned.

    -Refresh takes the versions from the manifest, downloads each artefact, and writes back the
    version, URL and hash of anything that moved. Only those three values are rewritten, in place, so
    comments and the descriptive fields are preserved.

    Kept clean of PowerShell 7 syntax on purpose: the PR validation matrix runs one leg under Windows
    PowerShell 5.1.
.PARAMETER Check
    Report drift and exit non-zero if any is found. Changes nothing.
.PARAMETER Refresh
    Rewrite version, URL and SHA-256 for artefacts whose manifest version has moved.
.PARAMETER SkipDownload
    Skip everything that needs the network, leaving only the offline consistency checks. Only valid
    with -Check.
.PARAMETER LockPath
    Path to the lock file. Defaults to src/DependencyLock.psd1.
.PARAMETER RepositoryRoot
    Repository root the relative paths in the lock file are resolved against.
.EXAMPLE
    ./build/Update-DependencyLock.ps1 -Check

    Verifies that every pinned artefact still hashes to what the lock file claims.
.EXAMPLE
    ./build/Update-DependencyLock.ps1 -Refresh

    Picks up the version from build/Dependencies and refreshes the hash after a Dependabot bump.
#>
[CmdletBinding(DefaultParameterSetName = "Check")]
param(
    [parameter(Mandatory = $false, ParameterSetName = "Check")]
    [switch]$Check,
    [parameter(Mandatory = $true, ParameterSetName = "Refresh")]
    [switch]$Refresh,
    [parameter(Mandatory = $false, ParameterSetName = "Check")]
    [switch]$SkipDownload,
    [parameter(Mandatory = $false)]
    [string]$LockPath = (Join-Path (Join-Path $PSScriptRoot "..") "src\DependencyLock.psd1"),
    [parameter(Mandatory = $false)]
    [string]$RepositoryRoot = (Convert-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Problems = [System.Collections.Generic.List[string]]::new()

function Add-Problem {
    param([string]$Message)

    $Problems.Add($Message)
    $Message | Write-Host -ForegroundColor Red
}

function Get-ManifestVersion {
    # Reads the PackageReference versions out of the Dependabot manifest. These files are never built,
    # so they are parsed as plain XML rather than through MSBuild.
    param([string]$ManifestPath)

    $Version = @{}
    if (-not (Test-Path $ManifestPath -PathType Leaf)) {
        Add-Problem ("Dependency manifest '{0}' does not exist." -f $ManifestPath)
        return $Version
    }

    [xml]$Manifest = Get-Content -Path $ManifestPath -Raw
    foreach ($Reference in $Manifest.Project.ItemGroup.PackageReference) {
        if ($null -eq $Reference) {
            continue
        }
        $Version[$Reference.Include] = $Reference.Version
    }
    return $Version
}

function Get-FlatContainerUrl {
    param([string]$PackageId, [string]$Version)

    return "https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg" -f $PackageId.ToLowerInvariant(), $Version.ToLowerInvariant()
}

function Get-RemoteSha256 {
    param([string]$Url)

    $TempFile = [System.IO.Path]::GetTempFileName()
    try {
        $WebClient = New-Object System.Net.WebClient
        try {
            $WebClient.DownloadFile($Url, $TempFile)
        }
        finally {
            $WebClient.Dispose()
        }
        return (Get-FileHash -Path $TempFile -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
    }
}

function Set-ArtifactValue {
    # Rewrites Version/Url/Sha256 in place for one artefact, leaving every other line - comments and
    # alignment included - exactly as it was.
    param(
        [string[]]$Line,
        [string]$Id,
        [hashtable]$Value
    )

    $CurrentId = $null
    for ($Index = 0; $Index -lt $Line.Count; $Index++) {
        if ($Line[$Index] -match '^\s*Id\s*=\s*"([^"]+)"\s*$') {
            $CurrentId = $Matches[1]
            continue
        }
        if ($CurrentId -ne $Id) {
            continue
        }
        foreach ($Key in $Value.Keys) {
            if ($Line[$Index] -match ('^(\s*{0}\s*=\s*)"[^"]*"\s*$' -f [regex]::Escape($Key))) {
                $Line[$Index] = '{0}"{1}"' -f $Matches[1], $Value[$Key]
            }
        }
    }
    return $Line
}

if ($SkipDownload -and $PSCmdlet.ParameterSetName -ne "Check") {
    "-SkipDownload is only valid together with -Check." | Write-Error -ErrorAction Stop
}

if (-not (Test-Path $LockPath -PathType Leaf)) {
    "Lock file '{0}' does not exist." -f $LockPath | Write-Error -ErrorAction Stop
}

$Lock = Import-PowerShellDataFile -Path $LockPath
$Artifacts = @($Lock.Artifacts)

"Dependency lock: {0}" -f $LockPath | Write-Host -ForegroundColor Cyan
"Artefacts: {0}" -f $Artifacts.Count | Write-Host

#region offline consistency checks

if ($Lock.SchemaVersion -ne 1) {
    Add-Problem ("Lock file schema version is '{0}', expected 1." -f $Lock.SchemaVersion)
}

$DuplicateId = $Artifacts | Group-Object { $_.Id } | Where-Object { $_.Count -gt 1 }
foreach ($Duplicate in $DuplicateId) {
    Add-Problem ("Artefact id '{0}' is listed {1} times; ids must be unique." -f $Duplicate.Name, $Duplicate.Count)
}

$ManifestVersion = @{}
foreach ($Artifact in $Artifacts) {
    foreach ($RequiredKey in @("Id", "Verification", "InstalledBy")) {
        if (-not $Artifact.ContainsKey($RequiredKey) -or [string]::IsNullOrWhiteSpace($Artifact[$RequiredKey])) {
            Add-Problem ("Artefact '{0}' is missing the required key '{1}'." -f $Artifact.Id, $RequiredKey)
        }
    }

    # Sha256 is the only verification mode this module implements. OmadaWeb.PS additionally has an
    # Authenticode mode for msedgedriver.exe, whose version has to track the locally installed Edge
    # build; nothing here has that problem, so anything else is a mistake rather than a variant.
    if ($Artifact.Verification -ne "Sha256") {
        Add-Problem ("Artefact '{0}' has Verification '{1}'; this module only implements 'Sha256'." -f $Artifact.Id, $Artifact.Verification)
        continue
    }

    if ($Artifact.Sha256 -notmatch '^[0-9a-f]{64}$') {
        Add-Problem ("Artefact '{0}' has SHA-256 '{1}', which is not 64 lower-case hex characters." -f $Artifact.Id, $Artifact.Sha256)
    }

    $ExpectedUrl = Get-FlatContainerUrl -PackageId $Artifact.PackageId -Version $Artifact.Version
    if ($Artifact.Url -ne $ExpectedUrl) {
        Add-Problem ("Artefact '{0}' has URL '{1}' but its pinned version implies '{2}'." -f $Artifact.Id, $Artifact.Url, $ExpectedUrl)
    }

    if ([string]::IsNullOrWhiteSpace($Artifact.Manifest)) {
        Add-Problem ("Artefact '{0}' names no Manifest, so no Dependabot manifest tracks it." -f $Artifact.Id)
        continue
    }

    $ManifestPath = Join-Path $RepositoryRoot $Artifact.Manifest
    if (-not $ManifestVersion.ContainsKey($Artifact.Manifest)) {
        $ManifestVersion[$Artifact.Manifest] = Get-ManifestVersion -ManifestPath $ManifestPath
    }
    $Declared = $ManifestVersion[$Artifact.Manifest]

    if (-not $Declared.ContainsKey($Artifact.PackageId)) {
        Add-Problem ("Artefact '{0}' claims to be tracked by '{1}', but that manifest has no PackageReference for '{2}'. Without one it gets no Dependabot alerts." -f $Artifact.Id, $Artifact.Manifest, $Artifact.PackageId)
    }
    elseif ($Declared[$Artifact.PackageId] -ne $Artifact.Version) {
        Add-Problem ("Artefact '{0}' is pinned at version '{1}' but '{2}' declares '{3}'. Run build/Update-DependencyLock.ps1 -Refresh." -f $Artifact.Id, $Artifact.Version, $Artifact.Manifest, $Declared[$Artifact.PackageId])
    }
}

# Every -ArtifactId the module asks for has to exist here, otherwise that download would fail closed
# at runtime instead of at build time.
$KnownId = @($Artifacts | ForEach-Object { $_.Id })
$PrivatePath = Join-Path (Join-Path (Join-Path (Join-Path $RepositoryRoot "src") "Lib") "Functions") "Private"
foreach ($Source in (Get-ChildItem -Path $PrivatePath -Filter "*.ps1" -File)) {
    $Content = Get-Content -Path $Source.FullName -Raw
    foreach ($Match in ([regex]'-ArtifactId\s+"([^"]+)"').Matches($Content)) {
        $RequestedId = $Match.Groups[1].Value
        if ($KnownId -notcontains $RequestedId) {
            Add-Problem ("{0} downloads artefact '{1}', which has no entry in the lock file." -f $Source.Name, $RequestedId)
        }
    }
}

foreach ($Artifact in $Artifacts) {
    $InstallerPath = Join-Path $PrivatePath ("{0}.ps1" -f $Artifact.InstalledBy)
    if (-not (Test-Path $InstallerPath -PathType Leaf)) {
        Add-Problem ("Artefact '{0}' names installer '{1}', which does not exist." -f $Artifact.Id, $Artifact.InstalledBy)
    }
}

#endregion

#region network checks and refresh

if ($PSCmdlet.ParameterSetName -eq "Refresh") {
    $Line = @(Get-Content -Path $LockPath)
    $Changed = 0

    foreach ($Artifact in $Artifacts) {
        $ManifestPath = Join-Path $RepositoryRoot $Artifact.Manifest
        $Declared = Get-ManifestVersion -ManifestPath $ManifestPath
        $Version = $Artifact.Version
        if ($Declared.ContainsKey($Artifact.PackageId)) {
            $Version = $Declared[$Artifact.PackageId]
        }

        $Url = Get-FlatContainerUrl -PackageId $Artifact.PackageId -Version $Version
        $Sha256 = Get-RemoteSha256 -Url $Url

        if ($Version -eq $Artifact.Version -and $Url -eq $Artifact.Url -and $Sha256 -eq $Artifact.Sha256) {
            "  {0} {1} unchanged" -f $Artifact.Id, $Version | Write-Host
            continue
        }

        "  {0}: {1} -> {2}" -f $Artifact.Id, $Artifact.Version, $Version | Write-Host -ForegroundColor Yellow
        "    sha256 {0} -> {1}" -f $Artifact.Sha256, $Sha256 | Write-Host -ForegroundColor Yellow
        $Line = Set-ArtifactValue -Line $Line -Id $Artifact.Id -Value @{
            Version = $Version
            Url     = $Url
            Sha256  = $Sha256
        }
        $Changed++
    }

    if ($Changed -gt 0) {
        # Written without a BOM and with CRLF, matching the rest of the repository.
        [System.IO.File]::WriteAllText($LockPath, (($Line -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        "Updated {0} artefact(s) in '{1}'." -f $Changed, $LockPath | Write-Host -ForegroundColor Green
    }
    else {
        "No changes; every pin already matches its manifest and its published bytes." | Write-Host -ForegroundColor Green
    }
}
elseif (-not $SkipDownload) {
    foreach ($Artifact in $Artifacts) {
        $Actual = Get-RemoteSha256 -Url $Artifact.Url
        if ($Actual -ne $Artifact.Sha256) {
            Add-Problem ("Artefact '{0}' no longer matches what '{1}' serves.`r`n    Pinned: {2}`r`n    Actual: {3}" -f $Artifact.Id, $Artifact.Url, $Artifact.Sha256, $Actual)
        }
        else {
            "  {0} {1} OK" -f $Artifact.Id, $Artifact.Version | Write-Host
        }
    }
}

#endregion

if ($Problems.Count -gt 0) {
    "" | Write-Host
    "{0} problem(s) found in the dependency lock." -f $Problems.Count | Write-Error -ErrorAction Stop
}

"Dependency lock is consistent." | Write-Host -ForegroundColor Green
