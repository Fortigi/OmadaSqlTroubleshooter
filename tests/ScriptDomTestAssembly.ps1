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

    $Installed = Join-Path ([System.Environment]::GetFolderPath("LocalApplicationData")) "OmadaSqlTroubleshooter\Bin\Microsoft.SqlServer.TransactSql.ScriptDom.dll"
    if (Test-Path $Installed -PathType Leaf) {
        return $Installed
    }

    $CacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaSqlTroubleshooter.ScriptDom.{0}" -f $Artifact.Version)
    $Cached = Join-Path $CacheRoot "Microsoft.SqlServer.TransactSql.ScriptDom.dll"
    if (Test-Path $Cached -PathType Leaf) {
        return $Cached
    }

    try {
        New-Item -Path $CacheRoot -ItemType Directory -Force | Out-Null
        $Package = Join-Path $CacheRoot "package.zip"
        Invoke-WebRequest -Uri $Artifact.Url -OutFile $Package

        $ActualHash = (Get-FileHash -Path $Package -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ActualHash -ne $Artifact.Sha256) {
            Remove-Item -Path $Package -Force -ErrorAction SilentlyContinue
            return $null
        }

        $Expanded = Join-Path $CacheRoot "expanded"
        Expand-Archive -Path $Package -DestinationPath $Expanded -Force
        $Source = Get-ChildItem -Path $Expanded -Filter "Microsoft.SqlServer.TransactSql.ScriptDom.dll" -Recurse |
            Where-Object { $_.Directory.Name -eq "net8.0" } |
            Select-Object -First 1
        if ($null -eq $Source) {
            return $null
        }

        Copy-Item -Path $Source.FullName -Destination $Cached -Force
        Remove-Item -Path $Expanded -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $Package -Force -ErrorAction SilentlyContinue
        return $Cached
    }
    catch {
        return $null
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
