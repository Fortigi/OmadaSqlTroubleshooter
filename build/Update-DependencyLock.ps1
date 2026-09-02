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

function Save-RemotePackage {
    # Downloads an artefact to a temp file and hands back the path. The caller deletes it. Split out
    # from hashing because the per-file pins need the package kept around long enough to be read.
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
    }
    catch {
        # GetTempFileName has already created the file, so a failed download leaves an empty or
        # partial one behind. The caller only deletes what it was handed, and it is handed nothing
        # when this throws - so clean up here before rethrowing.
        Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
        throw
    }
    return $TempFile
}

function Get-Sha256 {
    param([string]$Path)

    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-PackageEntrySha256 {
    # SHA-256 of one entry inside a .nupkg, read straight out of the archive - nothing is expanded to
    # disk. Returns $null when the entry is absent, which the callers report as a problem rather than
    # skipping: a Source that has moved means the bundle would be silently incomplete.
    param([string]$PackagePath, [string]$EntryPath)

    Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction SilentlyContinue

    $Archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        # 0, 1 and many are all handled explicitly. A zip may legally carry two entries with the same
        # name; letting $Entry become an array would fail on $Entry.Open() with an opaque method
        # invocation error rather than saying what is actually wrong.
        $Entry = @($Archive.Entries | Where-Object { $_.FullName -eq $EntryPath })
        if ($Entry.Count -eq 0) {
            return $null
        }
        if ($Entry.Count -gt 1) {
            # Not $null: "absent" and "ambiguous" are different problems and the caller reports them
            # differently.
            "Package '{0}' contains {1} entries named '{2}'. Which one the pin refers to is ambiguous." -f $PackagePath, $Entry.Count, $EntryPath | Write-Error -ErrorAction Stop
        }
        $Entry = $Entry[0]

        $Sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $Stream = $Entry.Open()
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
    finally {
        $Archive.Dispose()
    }
}

function Set-ArtifactValue {
    # Rewrites Version/Url/Sha256 in place for one artefact, leaving every other line - comments and
    # alignment included - exactly as it was.
    #
    # Scanning stops at the artefact's "Files = @(" line. The per-file entries below it carry their
    # own Sha256 keys, and without this the package hash would be written over all four of them.
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
        if ($Line[$Index] -match '^\s*Files\s*=\s*@\(') {
            $CurrentId = $null
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

function Set-ArtifactFileHash {
    # Rewrites the Sha256 of each Files entry belonging to ONE artefact, keyed on the Target line
    # immediately above it. Only the hash line is touched, so Source, Target and the layout survive
    # untouched.
    #
    # Scoped to $Id the same way Set-ArtifactValue is. Target names are not unique across artefacts -
    # nothing stops a second package from also shipping a file called WebView2Loader.dll - and an
    # unscoped rewrite would silently repin another artefact's file to this one's bytes.
    param(
        [string[]]$Line,
        [string]$Id,
        [hashtable]$HashByTarget
    )

    $CurrentId = $null
    $CurrentTarget = $null
    for ($Index = 0; $Index -lt $Line.Count; $Index++) {
        # Id appears only at artefact level; the Files entries below it carry Source/Target/Sha256.
        if ($Line[$Index] -match '^\s*Id\s*=\s*"([^"]+)"\s*$') {
            $CurrentId = $Matches[1]
            $CurrentTarget = $null
            continue
        }
        if ($CurrentId -ne $Id) {
            continue
        }
        if ($Line[$Index] -match '^\s*Target\s*=\s*"([^"]+)"\s*$') {
            $CurrentTarget = $Matches[1]
            continue
        }
        if ($null -eq $CurrentTarget -or -not $HashByTarget.ContainsKey($CurrentTarget)) {
            continue
        }
        if ($Line[$Index] -match '^(\s*Sha256\s*=\s*)"[^"]*"\s*$') {
            $Line[$Index] = '{0}"{1}"' -f $Matches[1], $HashByTarget[$CurrentTarget]
            $CurrentTarget = $null
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

    # Files is what build/Get-BundledDependency.ps1 copies into the package and what the module
    # re-checks before it loads each assembly. An entry that is malformed here is a bundle that
    # cannot be verified, so it is checked as strictly as the package pin itself.
    #
    # Files is optional. An artefact that is bundled into the package must list the files taken out
    # of it, because the package hash cannot verify an extracted file. An artefact that is only ever
    # downloaded to Bin and loaded from there - ScriptDom - is covered end to end by its package hash
    # plus its own install stamp, and has nothing to extract into the package. Note the null filter:
    # @($null) is a one-element array holding $null, so a missing Files would otherwise arrive here
    # as a single malformed entry rather than as no entries at all.
    $ArtifactFile = @($Artifact.Files | Where-Object { $null -ne $_ })
    if ($ArtifactFile.Count -eq 0 -and $Artifact.ContainsKey("Files")) {
        Add-Problem ("Artefact '{0}' declares Files but lists none, so nothing can be bundled or re-verified before load." -f $Artifact.Id)
    }

    $SeenTarget = @{}
    foreach ($File in $ArtifactFile) {
        if ([string]::IsNullOrWhiteSpace($File.Source) -or [string]::IsNullOrWhiteSpace($File.Target)) {
            Add-Problem ("Artefact '{0}' has a Files entry with an empty Source or Target." -f $Artifact.Id)
            continue
        }

        if ($File.Source -match '\\') {
            Add-Problem ("Artefact '{0}' file '{1}' has Source '{2}'; entry paths inside a .nupkg use forward slashes." -f $Artifact.Id, $File.Target, $File.Source)
        }

        if ($File.Sha256 -notmatch '^[0-9a-f]{64}$') {
            Add-Problem ("Artefact '{0}' file '{1}' has SHA-256 '{2}', which is not 64 lower-case hex characters." -f $Artifact.Id, $File.Target, $File.Sha256)
        }

        if ($SeenTarget.ContainsKey($File.Target)) {
            # Two sources writing the same file name means whichever copies last wins, which is
            # precisely the netcoreapp3.0 / net5.0-windows Wpf.dll ambiguity this pin exists to settle.
            Add-Problem ("Artefact '{0}' maps more than one Source onto target '{1}'." -f $Artifact.Id, $File.Target)
        }
        $SeenTarget[$File.Target] = $true
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

        $PackagePath = Save-RemotePackage -Url $Url
        try {
            $Sha256 = Get-Sha256 -Path $PackagePath

            # Per-file hashes are recomputed from the same download the package hash came from, so
            # the two can never describe different bytes.
            $FileHash = @{}
            $FileChanged = $false
            foreach ($File in @($Artifact.Files | Where-Object { $null -ne $_ })) {
                $EntrySha256 = Get-PackageEntrySha256 -PackagePath $PackagePath -EntryPath $File.Source
                if ($null -eq $EntrySha256) {
                    Add-Problem ("Artefact '{0}' version {1} has no entry '{2}'. The package layout changed; the Files list has to be corrected by hand." -f $Artifact.Id, $Version, $File.Source)
                    continue
                }
                $FileHash[$File.Target] = $EntrySha256
                if ($EntrySha256 -ne $File.Sha256) {
                    $FileChanged = $true
                    "    {0} sha256 {1} -> {2}" -f $File.Target, $File.Sha256, $EntrySha256 | Write-Host -ForegroundColor Yellow
                }
            }

            if ($Version -eq $Artifact.Version -and $Url -eq $Artifact.Url -and $Sha256 -eq $Artifact.Sha256 -and -not $FileChanged) {
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
            $Line = Set-ArtifactFileHash -Line $Line -Id $Artifact.Id -HashByTarget $FileHash
            $Changed++
        }
        finally {
            Remove-Item -Path $PackagePath -Force -ErrorAction SilentlyContinue
        }
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
        $PackagePath = Save-RemotePackage -Url $Artifact.Url
        try {
            $Actual = Get-Sha256 -Path $PackagePath
            if ($Actual -ne $Artifact.Sha256) {
                Add-Problem ("Artefact '{0}' no longer matches what '{1}' serves.`r`n    Pinned: {2}`r`n    Actual: {3}" -f $Artifact.Id, $Artifact.Url, $Artifact.Sha256, $Actual)
                continue
            }

            "  {0} {1} OK" -f $Artifact.Id, $Artifact.Version | Write-Host

            # The package hash matching is not enough on its own. The bundle ships extracted files,
            # which that hash cannot cover, so each per-file pin is re-derived from the package here.
            # This is what catches a refresh that bumped the package hash but left the Files stale.
            foreach ($File in @($Artifact.Files | Where-Object { $null -ne $_ })) {
                $EntrySha256 = Get-PackageEntrySha256 -PackagePath $PackagePath -EntryPath $File.Source
                if ($null -eq $EntrySha256) {
                    Add-Problem ("Artefact '{0}' pins file '{1}', but the package has no entry at that path. The bundle would be incomplete." -f $Artifact.Id, $File.Source)
                    continue
                }
                if ($EntrySha256 -ne $File.Sha256) {
                    Add-Problem ("Artefact '{0}' file '{1}' no longer matches the package.`r`n    Pinned: {2}`r`n    Actual: {3}" -f $Artifact.Id, $File.Source, $File.Sha256, $EntrySha256)
                }
                else {
                    "    {0} OK" -f $File.Target | Write-Host
                }
            }
        }
        finally {
            Remove-Item -Path $PackagePath -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

if ($Problems.Count -gt 0) {
    "" | Write-Host
    "{0} problem(s) found in the dependency lock." -f $Problems.Count | Write-Error -ErrorAction Stop
}

"Dependency lock is consistent." | Write-Host -ForegroundColor Green
