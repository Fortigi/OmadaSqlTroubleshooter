<#
    Functions behind the complexity and mutation-testing gates (issue #109).

    Dot-sourced by build/psakeBuild.ps1 (Tasks QualityChanged, QualityFull and
    UpdateComplexityBaseline) and by tests/QualityGates.Tests.ps1. The pure helpers - path
    selection, the test map, config and baseline files, the markdown - are separated from the two
    Invoke-* functions that drive PSComplexity and PSMutant, so the parts that decide WHAT gets
    measured can be unit tested without running a mutation suite.
#>

function ConvertTo-RepositoryRelativePath {
    <#
    .SYNOPSIS
        A path relative to the repository root, with forward slashes - the form PSComplexity
        records in its reports and baselines, and the form git prints.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path
    )

    process {
        $FullPath = [System.IO.Path]::GetFullPath($Path, $RepositoryRoot)
        return ([System.IO.Path]::GetRelativePath($RepositoryRoot, $FullPath) -replace '\\', '/')
    }
}

function Get-QualityGateSetting {
    <#
    .SYNOPSIS
        Reads build/QualityGates.psd1.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Import-PowerShellDataFile -Path $Path)
}

function Get-QualitySourceFile {
    <#
    .SYNOPSIS
        Every .ps1 file under the given source paths, excluding _*.ps1 exactly as the build does.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$SourcePath
    )

    $Files = foreach ($Path in $SourcePath) {
        Get-ChildItem -Path (Join-Path -Path $RepositoryRoot -ChildPath $Path) -Recurse -File -Filter '*.ps1' |
            Where-Object { $_.Name -notlike '_*.ps1' }
    }
    return @($Files | Sort-Object -Property FullName)
}

function Select-QualityChangedFile {
    <#
    .SYNOPSIS
        Reduces a pull request's changed-file list to the PowerShell source the gates measure.
    .DESCRIPTION
        Keeps a path only when it is a .ps1 under one of the source paths, is not an _*.ps1 file, and
        still exists - a deleted file has nothing left to measure. Returns repository-relative paths
        with forward slashes, de-duplicated and sorted. An empty result is a legitimate answer (a
        documentation-only change); the caller decides to skip, because both PSComplexity and
        PSMutant refuse an empty -ChangedFile list by design.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$ChangedFile,

        [Parameter(Mandatory = $true)]
        [string[]]$SourcePath
    )

    $Prefixes = @($SourcePath | ForEach-Object { ($_ -replace '\\', '/').TrimEnd('/') + '/' })
    $Selected = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Candidate in $ChangedFile) {
        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            continue
        }
        $Relative = ($Candidate.Trim() -replace '\\', '/').TrimStart('/')
        $Leaf = Split-Path -Path $Relative -Leaf
        if ($Leaf -notlike '*.ps1' -or $Leaf -like '_*') {
            continue
        }
        $UnderSource = @($Prefixes | Where-Object { $Relative.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (-not $UnderSource) {
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $Relative) -PathType Leaf)) {
            continue
        }
        [void]$Selected.Add($Relative)
    }

    return [string[]]@($Selected)
}

function Get-MutationTestMap {
    <#
    .SYNOPSIS
        Maps each source file to the unit test files that own it, from the test naming convention.
    .DESCRIPTION
        CONTRIBUTING.md names a unit test file after the function it covers:
        tests/<FunctionName>.Tests.ps1, optionally with a suffix (<FunctionName>.Untyped.Tests.ps1).
        That function is looked up by file name first and then by every function DEFINED in the
        source tree (from the AST), so a helper that lives in another function's file still maps to
        that file. Suites whose name matches no function - wiring and repository-invariant suites -
        are returned under Unowned rather than guessed at.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [string]$TestPath = 'tests'
    )

    $OwnerByName = @{}
    foreach ($File in (Get-QualitySourceFile -RepositoryRoot $RepositoryRoot -SourcePath $SourcePath)) {
        $Relative = ConvertTo-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path $File.FullName
        $OwnerByName[$File.BaseName] = $Relative
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
        $Definitions = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($Definition in $Definitions) {
            if (-not $OwnerByName.ContainsKey($Definition.Name)) {
                $OwnerByName[$Definition.Name] = $Relative
            }
        }
    }

    $Map = [ordered]@{}
    $Unowned = [System.Collections.Generic.List[string]]::new()
    $TestFiles = Get-ChildItem -Path (Join-Path -Path $RepositoryRoot -ChildPath $TestPath) -Filter '*.Tests.ps1' -File | Sort-Object -Property Name
    foreach ($TestFile in $TestFiles) {
        $FunctionName = ($TestFile.Name -split '\.')[0]
        if (-not $OwnerByName.ContainsKey($FunctionName)) {
            $Unowned.Add($TestFile.Name)
            continue
        }
        $Owner = $OwnerByName[$FunctionName]
        if (-not $Map.Contains($Owner)) {
            $Map[$Owner] = [System.Collections.Generic.List[string]]::new()
        }
        $Map[$Owner].Add(('{0}/{1}' -f ($TestPath -replace '\\', '/').TrimEnd('/'), $TestFile.Name))
    }

    $SortedMap = [ordered]@{}
    foreach ($Key in ($Map.Keys | Sort-Object)) {
        $SortedMap[$Key] = [string[]]$Map[$Key]
    }

    return [pscustomobject]@{
        Map     = $SortedMap
        Unowned = [string[]]$Unowned
    }
}

function New-MutationConfig {
    <#
    .SYNOPSIS
        Writes the PSMutant config the gates run: the policy from QualityGates.psd1 plus the
        generated mutate -> tests map.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Setting,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,

        [Parameter(Mandatory = $true)]
        [string]$ReportPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $Config = [ordered]@{
        mutate           = [string[]]@($Map.Keys)
        tests            = $Map
        operators        = [string[]]$Setting.Operators
        coveredLinesOnly = [bool]$Setting.CoveredLinesOnly
        sandboxSubtrees  = [string[]]$Setting.SandboxSubtrees
        workers          = [int]$Setting.Workers
        thresholds       = [ordered]@{
            high  = $Setting.Thresholds.High
            low   = $Setting.Thresholds.Low
            break = $Setting.Thresholds.Break
        }
        reportPath       = $ReportPath -replace '\\', '/'
    }
    # Only written when there is something to declare: PSMutant validates every key it is given.
    if ($Setting.Equivalents -and $Setting.Equivalents.Count -gt 0) {
        $Equivalents = [ordered]@{}
        foreach ($Key in ($Setting.Equivalents.Keys | Sort-Object)) {
            $Equivalents[$Key] = $Setting.Equivalents[$Key]
        }
        $Config['equivalents'] = $Equivalents
    }

    $Directory = Split-Path -Path $OutputPath -Parent
    if ($Directory) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }
    $Config | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding utf8
    return $OutputPath
}

function New-ScopedComplexityBaseline {
    <#
    .SYNOPSIS
        A copy of the complexity baseline holding only the entries for the given files.
    .DESCRIPTION
        PSComplexity 0.5.1 refuses -BaselineFile together with -ChangedFile: every entry for a file
        outside the changed set is reported as "recorded but no such unit was measured" and the gate
        throws. Handing it a baseline that names only the changed files keeps the two halves of the
        rule - a baselined unit may not get worse, a new unit must be under the ceilings - without
        that false failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineFile,

        [Parameter(Mandatory = $true)]
        [string[]]$ChangedFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $Baseline = Get-Content -LiteralPath $BaselineFile -Raw | ConvertFrom-Json
    $Wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]@($ChangedFile | ForEach-Object { $_ -replace '\\', '/' }), [System.StringComparer]::OrdinalIgnoreCase)
    $Baseline.units = @($Baseline.units | Where-Object { $Wanted.Contains($_.file) })

    $Directory = Split-Path -Path $OutputPath -Parent
    if ($Directory) {
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }
    $Baseline | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding utf8
    return $OutputPath
}

function Get-OrphanedBaselineEntry {
    <#
    .SYNOPSIS
        Baseline entries whose file no longer exists.
    .DESCRIPTION
        A pull request that deletes or renames a baselined file never measures it, so the scoped
        baseline cannot notice the entry went stale - but the weekly whole-tree run would, after the
        merge. Checked on every pull request instead, so the change that orphaned the entry is the
        change that removes it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineFile,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $Baseline = Get-Content -LiteralPath $BaselineFile -Raw | ConvertFrom-Json
    return @($Baseline.units | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $_.file) -PathType Leaf)
        })
}

function Get-ModulePinStatus {
    <#
    .SYNOPSIS
        Compares each pinned build module with the newest version available.
    .PARAMETER LatestVersion
        Resolves a module name to its newest version string. Defaults to the PowerShell Gallery;
        injectable so the comparison can be tested offline.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable[]]$Pin,

        [scriptblock]$LatestVersion = { param($Name) (Find-Module -Name $Name -Repository PSGallery -ErrorAction Stop).Version.ToString() }
    )

    foreach ($Module in $Pin) {
        $Latest = $null
        $LookupError = $null
        try {
            $Latest = & $LatestVersion $Module.Name
        }
        catch {
            $LookupError = $_.Exception.Message
        }
        [pscustomobject]@{
            Name    = $Module.Name
            Pinned  = $Module.RequiredVersion
            Latest  = $Latest
            IsStale = ($null -ne $Latest) -and ([version]$Latest -gt [version]$Module.RequiredVersion)
            Error   = $LookupError
        }
    }
}

function Limit-MarkdownLength {
    <#
    .SYNOPSIS
        Truncates markdown to fit a GitHub issue or check-run body (65,536 characters).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [int]$MaximumLength = 60000
    )

    if ($Text.Length -le $MaximumLength) {
        return $Text
    }
    $Notice = "`n`n_Truncated at $MaximumLength characters. The full report is in the run's artifact._"
    return $Text.Substring(0, $MaximumLength - $Notice.Length) + $Notice
}

function Format-ComplexityViolationMarkdown {
    <#
    .SYNOPSIS
        Offending units as a checklist grouped by file, worst file first.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Violation
    )

    if ($Violation.Count -eq 0) {
        return '_No unit is over the ceilings._'
    }

    $Lines = foreach ($Group in ($Violation | Group-Object -Property File | Sort-Object -Property @{ Expression = { ($_.Group | Measure-Object -Property Cognitive -Maximum).Maximum }; Descending = $true }, Name)) {
        $Units = ($Group.Group | Sort-Object -Property Cognitive -Descending | ForEach-Object {
                '`{0}` (cyclomatic {1}, cognitive {2})' -f $_.Unit, $_.Cyclomatic, $_.Cognitive
            }) -join '; '
        '- [ ] `{0}` — {1}' -f $Group.Name, $Units
    }
    return ($Lines -join "`n")
}

function Format-MutationSurvivorMarkdown {
    <#
    .SYNOPSIS
        Surviving mutants grouped per file, lowest-scoring file first, each file collapsed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Survivor,

        [AllowEmptyCollection()]
        [object[]]$PerFile = @()
    )

    if ($Survivor.Count -eq 0) {
        return '_No surviving mutants._'
    }

    $ScoreByFile = @{}
    foreach ($Entry in $PerFile) {
        $ScoreByFile[$Entry.file] = $Entry
    }

    $Groups = $Survivor | Group-Object -Property File | Sort-Object -Property @{ Expression = { if ($ScoreByFile.ContainsKey($_.Name)) { [double]$ScoreByFile[$_.Name].score } else { 0 } } }, Name
    $Blocks = foreach ($Group in $Groups) {
        $Summary = if ($ScoreByFile.ContainsKey($Group.Name)) {
            $Entry = $ScoreByFile[$Group.Name]
            '`{0}` — {1}% ({2} of {3} survived)' -f $Group.Name, $Entry.score, $Entry.survived, $Entry.total
        }
        else {
            '`{0}` — {1} survived' -f $Group.Name, $Group.Count
        }
        $Items = $Group.Group | Sort-Object -Property Line | ForEach-Object {
            '- line {0}{1}: `{2}`' -f $_.Line, $(if ($_.Function) { " in ``$($_.Function)``" } else { '' }), $_.Description
        }
        "<details><summary>$Summary</summary>`n`n$($Items -join "`n")`n`n</details>"
    }
    return ($Blocks -join "`n")
}

function Invoke-ComplexityGate {
    <#
    .SYNOPSIS
        Runs PSComplexity for one gate and returns the verdict with its markdown.
    .DESCRIPTION
        -ChangedFile restricts the run to those files (the pull request lane); without it the whole
        tree is measured. -BaselineFile applies the ratchet; without it the absolute ceilings apply.
        A baseline that no longer describes the run makes PSComplexity throw; that is reported as a
        failed gate with the module's own explanation rather than as a crashed build.
        Must be called with the repository root as the current location: PSComplexity records
        file paths relative to it, and the baseline is keyed on those paths.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$Setting,

        [Parameter(Mandatory = $true)]
        [string]$ReportPath,

        [string]$SarifPath,

        [string]$BaselineFile,

        [string[]]$ChangedFile
    )

    $Files = Get-QualitySourceFile -RepositoryRoot $RepositoryRoot -SourcePath $Setting.SourcePath
    $GateArguments = @{
        Path          = [string[]]$Files.FullName
        MaxCyclomatic = $Setting.MaxCyclomatic
        MaxCognitive  = $Setting.MaxCognitive
        ReportPath    = $ReportPath
        WarningAction = 'SilentlyContinue'
    }
    if ($SarifPath) { $GateArguments.SarifPath = $SarifPath }
    if ($BaselineFile) { $GateArguments.BaselineFile = $BaselineFile }
    if ($PSBoundParameters.ContainsKey('ChangedFile')) { $GateArguments.ChangedFile = $ChangedFile }

    $Passed = $false
    $GateError = $null
    $Violations = @()
    try {
        $Passed = [bool](Test-PSComplexity @GateArguments)
        $Report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
        $Violations = @($Report.violations)
    }
    catch {
        $GateError = $_.Exception.Message
    }

    return [pscustomobject]@{
        Passed     = $Passed -and -not $GateError
        Violations = $Violations
        Error      = $GateError
        Markdown   = if ($GateError) { "**The complexity baseline does not describe this code:**`n`n``````text`n$GateError`n```````n`nIf a unit improved or was renamed, run ``./build/build.ps1 -Task UpdateComplexityBaseline`` and commit ``complexity-baseline.json``." } else { Format-ComplexityViolationMarkdown -Violation $Violations }
    }
}

function Invoke-MutationGate {
    <#
    .SYNOPSIS
        Runs PSMutant for one gate and returns the verdict with its markdown.
    .DESCRIPTION
        Generates the config from QualityGates.psd1 and the test naming convention, then runs it -
        scoped to -ChangedFile when given (the pull request lane), over every mapped file otherwise.
        Changed source with no owning test file is not in the map, so PSMutant would pass it without
        a word; it is returned as Untested so the caller can put it in front of a reviewer.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$Setting,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [string[]]$ChangedFile
    )

    $TestMap = Get-MutationTestMap -RepositoryRoot $RepositoryRoot -SourcePath $Setting.SourcePath
    $ReportPath = ConvertTo-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path (Join-Path -Path $OutputDirectory -ChildPath 'mutation.json')
    $ConfigPath = New-MutationConfig -Setting $Setting -Map $TestMap.Map -ReportPath $ReportPath -OutputPath (Join-Path -Path $OutputDirectory -ChildPath 'psmutant.config.json')

    $Scoped = $PSBoundParameters.ContainsKey('ChangedFile')
    $Untested = @()
    $Mutable = @($TestMap.Map.Keys)
    if ($Scoped) {
        $Prefix = ($Setting.SourcePath -replace '\\', '/').TrimEnd('/') + '/'
        $UnderMutation = @($ChangedFile | Where-Object { $_.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase) })
        $Mutable = @($UnderMutation | Where-Object { $TestMap.Map.Contains($_) })
        $Untested = @($UnderMutation | Where-Object { -not $TestMap.Map.Contains($_) })
    }

    if ($Mutable.Count -eq 0) {
        return [pscustomobject]@{
            Passed    = $true
            Skipped   = $true
            Score     = $null
            Killed    = 0
            Total     = 0
            Untested  = $Untested
            Report    = $null
            Markdown  = '_No changed file has an owning unit test file, so there was nothing to mutate._'
        }
    }

    $MutationArguments = @{
        ConfigFile = $ConfigPath
        SourceRoot = $RepositoryRoot
    }
    if ($Scoped) { $MutationArguments.ChangedFile = $Mutable }
    $Result = Invoke-PSMutation @MutationArguments

    $ReportFile = Join-Path -Path $OutputDirectory -ChildPath $(if ($Scoped) { 'mutation.changed.json' } else { 'mutation.json' })
    $Report = Get-Content -LiteralPath $ReportFile -Raw | ConvertFrom-Json

    $Markdown = @(
        '**Score {0}%** ({1} of {2} killed) — threshold {3}%.' -f $Result.Score, $Result.Killed, $Result.Total, $Setting.Thresholds.Break
    )
    if ($Result.FailureReason -and "$($Result.FailureReason)" -ne 'None') {
        $Markdown += ''
        $Markdown += 'PSMutant failure reason: `{0}`.' -f $Result.FailureReason
    }
    $NoMutants = @($Report.filesWithNoMutants) + @($Report.filesWithNoCandidate) | Where-Object { $_ }
    if ($NoMutants.Count -gt 0) {
        $Markdown += ''
        $Markdown += 'Not measured (no mutant on a line the tests execute, so these score a vacuous 100%): {0}' -f (($NoMutants | ForEach-Object { '`{0}`' -f $_ }) -join ', ')
    }
    $Markdown += ''
    $Markdown += Format-MutationSurvivorMarkdown -Survivor @($Report.survivors) -PerFile @($Report.perFile)

    return [pscustomobject]@{
        Passed    = ($Result.ExitCode -eq 0)
        Skipped   = $false
        Score     = $Result.Score
        Killed    = $Result.Killed
        Total     = $Result.Total
        Untested  = $Untested
        Report    = $ReportFile
        Markdown  = ($Markdown -join "`n")
    }
}
