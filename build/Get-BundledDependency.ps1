#Requires -Version 5.1

<#
.SYNOPSIS
    Fetches the pinned dependency package and lays its files out as a bundle in the build output.
.DESCRIPTION
    OmadaSqlTroubleshooter used to download the WebView2 .NET SDK on every machine, on first module
    import. That fails outright on a machine with no route to nuget.org, which is the normal state of
    affairs on the restricted corporate networks Omada customers run. This script fetches the package
    once, at build time, and lays the assemblies out inside the published module so a normal import
    makes no network call at all.

    Every step is verified:

      1. The package is downloaded from the exact URL pinned in src/DependencyLock.psd1 and its
         SHA-256 is checked BEFORE a single entry is read out of it. Unverified bytes are never
         expanded.
      2. Each file listed in the artefact's Files array is copied out by its in-archive path. A
         Source that is not in the package is a terminating error, not a skip - an upstream
         repackaging has to break the build rather than produce a silently incomplete bundle.
      3. Each copied file is re-hashed on disk against its own pin. The package hash cannot cover an
         extracted file, so this is what makes the bundle verifiable at all.
      4. A WebView2.pin stamp is written next to the files, in the same format Install-WebView2
         writes at run time, so Test-WebView2Bundle and Test-WebView2RuntimeVersion read one format.

    This script replaces build/RetrieveDependencies.ps1, build/AddSrcDependencies.ps1 and the two
    copies of RetrieveFromNuGet, all of which downloaded without any integrity check.

    It writes only into -OutputPath, which is under buildoutput. It must never write into src/:
    .gitignore only excludes src/bin/Debug/**, so a stray src\bin\*.dll would be committable and
    would immediately fail the "No redistributable binaries" test in tests/ThirdPartyNotices.Tests.ps1.

    Kept clean of PowerShell 7 syntax on purpose: the PR validation matrix runs one leg under Windows
    PowerShell 5.1.
.PARAMETER ArtifactId
    Id of the artefact in the lock file to bundle.
.PARAMETER OutputPath
    Folder the files are written into. Created if it does not exist.
.PARAMETER LockPath
    Path to the lock file. Defaults to src/DependencyLock.psd1.
.PARAMETER Force
    Re-download even when the folder already holds a complete, matching bundle.
.EXAMPLE
    ./build/Get-BundledDependency.ps1 -OutputPath ./buildoutput/OmadaSqlTroubleShooter/Bin/WebView2Dlls/win-x64

    Fetches the pinned WebView2 SDK and bundles the four assemblies with a pin stamp.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory = $false)]
    [string]$ArtifactId = "Microsoft.Web.WebView2",
    [parameter(Mandatory = $true)]
    [string]$OutputPath,
    [parameter(Mandatory = $false)]
    [string]$LockPath = (Join-Path (Join-Path $PSScriptRoot "..") "src\DependencyLock.psd1"),
    [parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction SilentlyContinue

function Get-Sha256 {
    param([string]$Path)

    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([System.BitConverter]::ToString($Sha256.ComputeHash($Stream)) -replace "-", "").ToLowerInvariant()
        }
        finally {
            $Stream.Dispose()
        }
    }
    finally {
        $Sha256.Dispose()
    }
}

function Get-ExpectedBundleFileName {
    # Everything the bundle folder is allowed to contain: the pinned targets and the stamp. Anything
    # else is an unpinned file that would be redistributed inside the package.
    param([hashtable]$Artifact)

    return @(@($Artifact.Files | ForEach-Object { $_.Target }) + "WebView2.pin")
}

function Get-UnexpectedBundleFileName {
    param([string]$Path, [hashtable]$Artifact)

    $Expected = Get-ExpectedBundleFileName -Artifact $Artifact

    return @(Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -or $Expected -notcontains $_.Name } |
            ForEach-Object { $_.Name })
}

function Test-ExistingBundle {
    # True when the folder already holds every target at its pinned hash, a stamp for this version,
    # and nothing else. Purely a build-time shortcut so a local rebuild does not re-download 9 MB; it
    # never relaxes a check, because a bundle that fails here is simply rebuilt from a verified
    # download.
    param([string]$Path, [hashtable]$Artifact)

    $StampPath = Join-Path $Path "WebView2.pin"
    if (-not (Test-Path $StampPath -PathType Leaf)) {
        return $false
    }

    if ((Get-Content -Path $StampPath -Raw) -notmatch ('Version\s*=\s*"{0}"' -f [regex]::Escape($Artifact.Version))) {
        return $false
    }

    foreach ($File in @($Artifact.Files)) {
        $FilePath = Join-Path $Path $File.Target
        if (-not (Test-Path $FilePath -PathType Leaf)) {
            return $false
        }
        if ((Get-Sha256 -Path $FilePath) -ne $File.Sha256) {
            return $false
        }
    }

    # A folder that holds the right files plus something else is not a bundle this script produced,
    # and reusing it would ship the extra file. Rebuild instead.
    if ((Get-UnexpectedBundleFileName -Path $Path -Artifact $Artifact).Count -gt 0) {
        return $false
    }

    return $true
}

if (-not (Test-Path $LockPath -PathType Leaf)) {
    "Lock file '{0}' does not exist, so nothing can be verified or bundled." -f $LockPath | Write-Error -ErrorAction Stop
}

$Lock = Import-PowerShellDataFile -Path $LockPath
if ($Lock.SchemaVersion -ne 1) {
    "Lock file '{0}' has schema version '{1}', expected 1." -f $LockPath, $Lock.SchemaVersion | Write-Error -ErrorAction Stop
}

$Artifact = @($Lock.Artifacts | Where-Object { $_.Id -eq $ArtifactId })
if ($Artifact.Count -ne 1) {
    "Lock file '{0}' holds {1} entries for artefact '{2}'; exactly one is required." -f $LockPath, $Artifact.Count, $ArtifactId | Write-Error -ErrorAction Stop
}
$Artifact = $Artifact[0]

$PinnedFile = @($Artifact.Files)
if ($PinnedFile.Count -eq 0) {
    "Artefact '{0}' lists no Files, so there is nothing to bundle." -f $ArtifactId | Write-Error -ErrorAction Stop
}

"Bundling {0} {1}" -f $Artifact.Id, $Artifact.Version | Write-Host -ForegroundColor Cyan

New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
$OutputPath = (Resolve-Path -Path $OutputPath).Path

if (-not $Force -and (Test-ExistingBundle -Path $OutputPath -Artifact $Artifact)) {
    "  Bundle already present and matching the pin; skipping download. Use -Force to refetch." | Write-Host
    $ExistingSize = (Get-ChildItem -Path $OutputPath -File | Measure-Object -Property Length -Sum).Sum
    "  Bundle size: {0:N0} bytes ({1:N2} MB)" -f $ExistingSize, ($ExistingSize / 1MB) | Write-Host -ForegroundColor Green
    return
}

# Emptied before anything is written. Overwriting the pinned targets is not enough: if the Files
# list changes between pins - an assembly renamed or dropped upstream - the previous run's copy
# would survive here and be redistributed inside the package with no pin covering it.
Get-ChildItem -Path $OutputPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

$PackagePath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString() + ".nupkg")

try {
    "  Downloading {0}" -f $Artifact.Url | Write-Host
    $WebClient = New-Object System.Net.WebClient
    try {
        $WebClient.DownloadFile($Artifact.Url, $PackagePath)
    }
    finally {
        $WebClient.Dispose()
    }

    # Gate one: the package, before anything is read out of it.
    $ActualPackageSha256 = Get-Sha256 -Path $PackagePath
    if ($ActualPackageSha256 -ne $Artifact.Sha256) {
        "Integrity check FAILED for '{0}' from '{1}'.`r`n  Expected SHA-256: {2}`r`n  Actual SHA-256:   {3}`r`nNothing was extracted. Either the download was corrupted, or the published package no longer matches the version pinned in '{4}'. Do not work around this by editing the lock file." -f $Artifact.Id, $Artifact.Url, $Artifact.Sha256, $ActualPackageSha256, $LockPath | Write-Error -ErrorAction Stop
    }
    "  Package SHA-256 matches the pin" | Write-Host

    # Read entries straight out of the archive rather than expanding it. Nothing unpinned ever
    # reaches disk, and it sidesteps Expand-Archive's refusal to open a file that is not named .zip -
    # the bug that made the old deploy-time copy of this fail.
    $Archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        foreach ($File in $PinnedFile) {
            # 0, 1 and many are all handled explicitly. A zip may legally carry two entries with the
            # same name; letting $Entry become an array would fail inside ExtractToFile with an
            # opaque method-resolution error instead of saying what is actually wrong.
            $Entry = @($Archive.Entries | Where-Object { $_.FullName -eq $File.Source })
            if ($Entry.Count -eq 0) {
                # Deliberately terminating. An upstream repackaging that moves a file must fail the
                # build; a bundle missing an assembly would import, then fail at the first tab.
                "Artefact '{0}' version {1} has no entry '{2}'. The package layout has changed upstream. Correct the Files list in '{3}' and re-pin the hashes with build/Update-DependencyLock.ps1 -Refresh." -f $Artifact.Id, $Artifact.Version, $File.Source, $LockPath | Write-Error -ErrorAction Stop
            }
            if ($Entry.Count -gt 1) {
                "Artefact '{0}' version {1} has {2} entries named '{3}'. Which one is meant is ambiguous, so nothing is extracted." -f $Artifact.Id, $Artifact.Version, $Entry.Count, $File.Source | Write-Error -ErrorAction Stop
            }
            $Entry = $Entry[0]

            $TargetPath = Join-Path $OutputPath $File.Target
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $TargetPath, $true)

            # Gate two: the extracted bytes on disk, against this file's own pin. The package hash
            # above says nothing about a single extracted file.
            $ActualFileSha256 = Get-Sha256 -Path $TargetPath
            if ($ActualFileSha256 -ne $File.Sha256) {
                Remove-Item -Path $TargetPath -Force -ErrorAction SilentlyContinue
                "Integrity check FAILED for '{0}' extracted from '{1}'.`r`n  Expected SHA-256: {2}`r`n  Actual SHA-256:   {3}`r`nThe file was deleted and has not been bundled." -f $File.Target, $File.Source, $File.Sha256, $ActualFileSha256 | Write-Error -ErrorAction Stop
            }

            "    {0,-40} {1,9:N0} bytes  OK" -f $File.Target, (Get-Item $TargetPath).Length | Write-Host
        }
    }
    finally {
        $Archive.Dispose()
    }
}
finally {
    Remove-Item -Path $PackagePath -Force -ErrorAction SilentlyContinue
}

# Same stamp format Install-WebView2 writes at run time, so one reader serves both layouts.
$FileEntry = foreach ($File in $PinnedFile) {
    '        @{{ Name = "{0}"; Sha256 = "{1}" }}' -f $File.Target, $File.Sha256
}

$StampContent = @(
    "# Written by build/Get-BundledDependency.ps1. Records the pin the assemblies in this folder were"
    "# fetched and verified against. Test-WebView2Bundle refuses the bundle when this version no longer"
    "# matches src\DependencyLock.psd1, and the module falls back to the runtime download."
    "@{"
    ('    Version = "{0}"' -f $Artifact.Version)
    "    Files   = @("
    $FileEntry
    "    )"
    "}"
) -join "`r`n"

$StampPath = Join-Path $OutputPath "WebView2.pin"
[System.IO.File]::WriteAllText($StampPath, ($StampContent + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

# Belt and braces after the clear above: whatever is in this folder is about to be published, so
# assert it is exactly the pinned set and nothing more.
$Unexpected = Get-UnexpectedBundleFileName -Path $OutputPath -Artifact $Artifact
if ($Unexpected.Count -gt 0) {
    "The bundle folder '{0}' contains {1} file(s) that are not pinned in '{2}': {3}. Refusing to publish an unpinned binary." -f $OutputPath, $Unexpected.Count, $LockPath, ($Unexpected -join ", ") | Write-Error -ErrorAction Stop
}

$BundleSize = (Get-ChildItem -Path $OutputPath -File | Measure-Object -Property Length -Sum).Sum
"  Wrote stamp '{0}'" -f $StampPath | Write-Host
"  Bundle: {0} file(s) in '{1}'" -f (@($PinnedFile).Count + 1), $OutputPath | Write-Host
"  Bundle size: {0:N0} bytes ({1:N2} MB)" -f $BundleSize, ($BundleSize / 1MB) | Write-Host -ForegroundColor Green
