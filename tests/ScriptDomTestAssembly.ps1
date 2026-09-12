# Resolves and loads the pinned ScriptDom assembly for the tests that need a real parser.
#
# The parse assertions across the three validation passes of issue #61 run against the real, pinned
# assembly rather than a stand-in, because the whole point of the dependency is that it produces SQL
# Server's own wording and SQL Server's own tree. A fake parser would let the tests agree with a
# message the server never sends, or with a syntax tree ScriptDom does not build.
#
# Extracted from Get-SqlSyntaxDiagnostic.Tests.ps1 once the schema and compatibility passes arrived
# and needed exactly the same thing. Three copies of a download-and-verify would be three chances for
# one of them to skip the hash check.

function Get-ScriptDomAssemblyPath {
    <#
        Prefers a copy the module has already installed on this machine; otherwise downloads the
        pinned package into a version-stamped cache folder and verifies the bytes against the pinned
        SHA-256 before using them - the same guarantee Invoke-DownloadFile gives at run time.

        Returns the path, or $null when the assembly could not be resolved. Callers mark their tests
        inconclusive on $null rather than failing: an offline build agent is not a broken pass.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $Lock = Import-PowerShellDataFile -Path (Join-Path $RepositoryRoot -ChildPath "src\DependencyLock.psd1")
    $Artifact = @($Lock.Artifacts | Where-Object { $_.Id -eq "Microsoft.SqlServer.TransactSql.ScriptDom" })[0]
    if ($null -eq $Artifact) {
        return $null
    }

    # An already-installed copy is preferred, but only when it is provably THE PINNED ONE. The
    # assertions these tests make are about grammar - exact messages, exact columns, which
    # TSqlNNNParser exists - so running them against whatever happens to be in a developer's Bin
    # folder would make them non-deterministic in the worst way: green here, red in CI, or green in
    # both while asserting the wrong thing.
    #
    # The module already answers this question at startup, and the two checks are its: the stamp
    # Install-ScriptDom wrote next to the assembly must record the pinned VERSION, and the file on
    # disk must still hash to what was recorded when it was installed. Get-ScriptDomStamp is the
    # module's own reader - reused rather than reimplemented, so a stamp this accepts is a stamp the
    # application accepts. Anything less falls through to the pinned download below.
    $Installed = Join-Path ([System.Environment]::GetFolderPath("LocalApplicationData")) "OmadaSqlTroubleshooter\Bin\Microsoft.SqlServer.TransactSql.ScriptDom.dll"
    if (Test-Path $Installed -PathType Leaf) {
        . (Join-Path $RepositoryRoot -ChildPath "src\Lib\Functions\Private\Get-ScriptDomStamp.ps1")
        $Script:ScriptDomStampPath = Join-Path (Split-Path -Path $Installed -Parent) "ScriptDom.pin"

        $Stamp = Get-ScriptDomStamp
        $InstalledHash = (Get-FileHash -Path $Installed -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($null -ne $Stamp -and
            $Stamp.Version -eq $Artifact.Version -and
            $Stamp.Sha256 -eq $InstalledHash) {
            return $Installed
        }

        Write-Warning ("The installed ScriptDom assembly does not match the pinned version {0}; the tests will use a verified download instead." -f $Artifact.Version)
    }

    $CacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaSqlTroubleshooter.ScriptDom.{0}" -f $Artifact.Version)
    $Cached = Join-Path $CacheRoot "Microsoft.SqlServer.TransactSql.ScriptDom.dll"
    $CachedHashPath = "{0}.sha256" -f $Cached

    # The same question the installed copy is asked, asked of the cache: is this the file we put
    # here? A run interrupted mid-copy, or a temp folder something else has been at, otherwise leaves
    # a truncated assembly that every later run reuses in silence - and the failure it produces looks
    # like a flaky parser rather than a broken file.
    #
    # A sidecar hash rather than an attempted load, for two reasons: loading an assembly cannot be
    # undone in the session that does it, and the version an assembly reports is not the package
    # version pinned in the lock, so a load proves less than it appears to.
    if (Test-Path $Cached -PathType Leaf) {
        $Recorded = $null
        if (Test-Path $CachedHashPath -PathType Leaf) {
            $Recorded = (Get-Content -Path $CachedHashPath -Raw).Trim()
        }

        if (![string]::IsNullOrWhiteSpace($Recorded) -and
            (Get-FileHash -Path $Cached -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Recorded) {
            return $Cached
        }

        Write-Warning "The cached ScriptDom assembly is incomplete or does not match what was recorded for it; it will be downloaded again."
        Remove-Item -Path $Cached -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $CachedHashPath -Force -ErrorAction SilentlyContinue
    }

    # The archive and the folder it expands into are scratch on every path, so they are cleaned up in
    # a finally rather than at each exit. There are four ways out of the block below - a hash
    # mismatch, a missing net8.0 build, an exception, and success - and cleaning up at each of them
    # meant the two failure paths left a package and an expanded tree behind on every test run.
    $Package = Join-Path $CacheRoot "package.zip"
    $Expanded = Join-Path $CacheRoot "expanded"

    try {
        New-Item -Path $CacheRoot -ItemType Directory -Force | Out-Null

        # Bounded and terminating on purpose: the point of this helper is to return $null quickly so
        # the caller can mark its tests inconclusive. On a network-restricted agent an unbounded
        # request hangs the whole test run instead.
        Invoke-WebRequest -Uri $Artifact.Url -OutFile $Package -TimeoutSec 60 -ErrorAction Stop

        $ActualHash = (Get-FileHash -Path $Package -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ActualHash -ne $Artifact.Sha256) {
            return $null
        }

        Expand-Archive -Path $Package -DestinationPath $Expanded -Force
        $Source = Get-ChildItem -Path $Expanded -Filter "Microsoft.SqlServer.TransactSql.ScriptDom.dll" -Recurse |
            Where-Object { $_.Directory.Name -eq "net8.0" } |
            Select-Object -First 1
        if ($null -eq $Source) {
            return $null
        }

        # Published atomically, so the partial copy the check above exists to catch cannot be created
        # by this function in the first place: the file only appears at its final name once it is
        # whole. Detection stays, because an interrupted run is not the only way a temp file goes bad.
        $Staging = "{0}.tmp" -f $Cached
        Copy-Item -Path $Source.FullName -Destination $Staging -Force

        (Get-FileHash -Path $Staging -Algorithm SHA256).Hash.ToLowerInvariant() |
            Set-Content -Path $CachedHashPath -NoNewline

        Move-Item -Path $Staging -Destination $Cached -Force
        return $Cached
    }
    catch {
        return $null
    }
    finally {
        Remove-Item -Path $Expanded -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $Package -Force -ErrorAction SilentlyContinue
        Remove-Item -Path ("{0}.tmp" -f $Cached) -Force -ErrorAction SilentlyContinue
    }
}

function Install-ScriptDomForTest {
    <#
        Resolves the assembly and loads it into the session. Returns the path, or $null.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $Path = Get-ScriptDomAssemblyPath -RepositoryRoot $RepositoryRoot
    if ($null -ne $Path) {
        [void][Reflection.Assembly]::LoadFrom($Path)
    }

    return $Path
}
