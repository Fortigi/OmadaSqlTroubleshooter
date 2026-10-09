#Requires -Version 7.0

# The helpers behind the complexity and mutation-testing gates (issue #109). These decide WHAT the
# gates measure - which changed files count, which tests own which source file, what config and
# baseline PSMutant and PSComplexity are handed - so a mistake here makes a gate measure the wrong
# thing while still reporting green. The two Invoke-* functions that drive the modules themselves are
# exercised end to end by the PR and weekly lanes, not here: a mutation run per test would be minutes.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath 'build\QualityGates.ps1')

    function New-SourceTree {
        param([string]$Root)
        foreach ($Path in @(
                'src\Lib\Functions\Private\Get-Alpha.ps1'
                'src\Lib\Functions\Private\Get-Beta.ps1'
                'src\Lib\Functions\Private\_Draft.ps1'
                'src\Lib\Functions\Public\Invoke-Gamma.ps1'
                'src\Lib\Events\MainForm.Elements.Button.ps1'
                'tests\Get-Alpha.Tests.ps1'
                'tests\Get-Alpha.Edge.Tests.ps1'
                'tests\Get-Helper.Tests.ps1'
                'tests\SomeWiring.Tests.ps1'
            )) {
            $Full = Join-Path $Root -ChildPath $Path
            New-Item -Path (Split-Path $Full -Parent) -ItemType Directory -Force | Out-Null
            Set-Content -Path $Full -Value '# placeholder'
        }
        # Get-Helper lives inside Get-Beta.ps1, so its test belongs to that file.
        Set-Content -Path (Join-Path $Root 'src\Lib\Functions\Private\Get-Beta.ps1') -Value @'
function Get-Beta { 1 }
function Get-Helper { 2 }
'@
        Set-Content -Path (Join-Path $Root 'src\Lib\Functions\Private\Get-Alpha.ps1') -Value 'function Get-Alpha { 0 }'
    }
}

Describe 'ConvertTo-RepositoryRelativePath' {
    It 'returns a forward-slash path relative to the root' {
        $Root = (Join-Path $TestDrive 'repo')
        ConvertTo-RepositoryRelativePath -RepositoryRoot $Root -Path (Join-Path $Root 'src\Lib\x.ps1') | Should -Be 'src/Lib/x.ps1'
    }

    It 'resolves a relative path against the root, not the current location' {
        $Root = (Join-Path $TestDrive 'repo')
        ConvertTo-RepositoryRelativePath -RepositoryRoot $Root -Path 'src\Lib\x.ps1' | Should -Be 'src/Lib/x.ps1'
    }
}

Describe 'Get-QualitySourceFile' {
    BeforeAll {
        $Script:Root = Join-Path $TestDrive 'sources'
        New-SourceTree -Root $Script:Root
    }

    It 'finds every .ps1 under the source paths' {
        $Names = (Get-QualitySourceFile -RepositoryRoot $Script:Root -SourcePath 'src/Lib/Functions', 'src/Lib/Events').Name
        $Names | Should -Contain 'Get-Alpha.ps1'
        $Names | Should -Contain 'Invoke-Gamma.ps1'
        $Names | Should -Contain 'MainForm.Elements.Button.ps1'
    }

    It 'excludes _*.ps1, as the build does' {
        (Get-QualitySourceFile -RepositoryRoot $Script:Root -SourcePath 'src/Lib/Functions').Name | Should -Not -Contain '_Draft.ps1'
    }
}

Describe 'Select-QualityChangedFile' {
    BeforeAll {
        $Script:Root = Join-Path $TestDrive 'changed'
        New-SourceTree -Root $Script:Root
        $Script:SourcePath = @('src/Lib/Functions', 'src/Lib/Events')
    }

    It 'keeps PowerShell source under the measured paths' {
        $Result = Select-QualityChangedFile -RepositoryRoot $Script:Root -SourcePath $Script:SourcePath -ChangedFile @(
            'src/Lib/Functions/Private/Get-Alpha.ps1'
            'src/Lib/Events/MainForm.Elements.Button.ps1'
        )
        $Result | Should -Be @('src/Lib/Events/MainForm.Elements.Button.ps1', 'src/Lib/Functions/Private/Get-Alpha.ps1')
    }

    It 'drops files outside the measured paths, non-PowerShell files and _*.ps1' {
        $Result = Select-QualityChangedFile -RepositoryRoot $Script:Root -SourcePath $Script:SourcePath -ChangedFile @(
            'README.md'
            'tests/Get-Alpha.Tests.ps1'
            'src/Lib/Functions/Private/_Draft.ps1'
            'build/psakeBuild.ps1'
        )
        @($Result).Count | Should -Be 0
    }

    It 'drops a deleted file, which has nothing left to measure' {
        @(Select-QualityChangedFile -RepositoryRoot $Script:Root -SourcePath $Script:SourcePath -ChangedFile 'src/Lib/Functions/Private/Gone.ps1').Count | Should -Be 0
    }

    It 'normalises backslashes and removes duplicates' {
        $Result = Select-QualityChangedFile -RepositoryRoot $Script:Root -SourcePath $Script:SourcePath -ChangedFile @(
            'src\Lib\Functions\Private\Get-Alpha.ps1'
            'src/Lib/Functions/Private/Get-Alpha.ps1'
        )
        $Result | Should -Be @('src/Lib/Functions/Private/Get-Alpha.ps1')
    }

    It 'returns an empty list for blank input instead of throwing' {
        @(Select-QualityChangedFile -RepositoryRoot $Script:Root -SourcePath $Script:SourcePath -ChangedFile @('', ' ')).Count | Should -Be 0
    }

    It 'does not treat a sibling folder sharing the prefix as a source path' {
        $Sibling = Join-Path $Script:Root 'src\Lib\FunctionsOld\Get-Old.ps1'
        New-Item -Path (Split-Path $Sibling -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $Sibling -Value '# old'
        @(Select-QualityChangedFile -RepositoryRoot $Script:Root -SourcePath $Script:SourcePath -ChangedFile 'src/Lib/FunctionsOld/Get-Old.ps1').Count | Should -Be 0
    }
}

Describe 'Get-MutationTestMap' {
    BeforeAll {
        $Script:Root = Join-Path $TestDrive 'map'
        New-SourceTree -Root $Script:Root
        $Script:Result = Get-MutationTestMap -RepositoryRoot $Script:Root -SourcePath 'src/Lib/Functions'
    }

    It 'maps a test to the file named after its function, including suffixed test files' {
        $Script:Result.Map['src/Lib/Functions/Private/Get-Alpha.ps1'] | Should -Be @('tests/Get-Alpha.Edge.Tests.ps1', 'tests/Get-Alpha.Tests.ps1')
    }

    It 'maps a test to the file that DEFINES its function when no file carries that name' {
        $Script:Result.Map['src/Lib/Functions/Private/Get-Beta.ps1'] | Should -Be @('tests/Get-Helper.Tests.ps1')
    }

    It 'leaves a suite that names no function unowned rather than guessing' {
        $Script:Result.Unowned | Should -Be @('SomeWiring.Tests.ps1')
    }

    It 'does not map a source file that has no test' {
        $Script:Result.Map.Contains('src/Lib/Functions/Public/Invoke-Gamma.ps1') | Should -BeFalse
    }
}

Describe 'New-MutationConfig' {
    BeforeAll {
        $Script:Setting = @{
            Operators        = @('BinaryOperator', 'NumberLiteral')
            CoveredLinesOnly = $true
            SandboxSubtrees  = @('src', 'tests', 'build')
            Workers          = 3
            Thresholds       = @{ High = 85; Low = 73; Break = 73 }
            Equivalents      = @{}
        }
        $Script:Map = [ordered]@{ 'src/Lib/Functions/Private/Get-Alpha.ps1' = [string[]]@('tests/Get-Alpha.Tests.ps1') }
    }

    It 'writes the policy and the generated map in PSMutant''s key names' {
        $Path = New-MutationConfig -Setting $Script:Setting -Map $Script:Map -ReportPath 'buildoutput\quality\mutation.json' -OutputPath (Join-Path $TestDrive 'cfg\a.json')
        $Config = Get-Content $Path -Raw | ConvertFrom-Json
        $Config.mutate | Should -Be @('src/Lib/Functions/Private/Get-Alpha.ps1')
        $Config.tests.'src/Lib/Functions/Private/Get-Alpha.ps1' | Should -Be @('tests/Get-Alpha.Tests.ps1')
        $Config.operators | Should -Be @('BinaryOperator', 'NumberLiteral')
        $Config.coveredLinesOnly | Should -BeTrue
        $Config.workers | Should -Be 3
        $Config.thresholds.break | Should -Be 73
        $Config.reportPath | Should -Be 'buildoutput/quality/mutation.json'
    }

    It 'keeps a single test file a JSON array rather than collapsing it to a string' {
        $Path = New-MutationConfig -Setting $Script:Setting -Map $Script:Map -ReportPath 'r.json' -OutputPath (Join-Path $TestDrive 'cfg\b.json')
        (Get-Content $Path -Raw) | Should -Match '"src/Lib/Functions/Private/Get-Alpha.ps1":\s*\[\s*"tests/Get-Alpha.Tests.ps1"\s*\]'
    }

    It 'omits equivalents when none are declared' {
        $Path = New-MutationConfig -Setting $Script:Setting -Map $Script:Map -ReportPath 'r.json' -OutputPath (Join-Path $TestDrive 'cfg\c.json')
        (Get-Content $Path -Raw | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'equivalents'
    }

    It 'writes declared equivalents with their reasons' {
        $Setting = $Script:Setting.Clone()
        $Setting.Equivalents = @{ 'src/x.ps1:Get-X:6 -> 7' = 'depth never exceeds 4' }
        $Path = New-MutationConfig -Setting $Setting -Map $Script:Map -ReportPath 'r.json' -OutputPath (Join-Path $TestDrive 'cfg\d.json')
        (Get-Content $Path -Raw | ConvertFrom-Json).equivalents.'src/x.ps1:Get-X:6 -> 7' | Should -Be 'depth never exceeds 4'
    }
}

Describe 'Complexity baseline helpers' {
    BeforeAll {
        $Script:Root = Join-Path $TestDrive 'baseline'
        New-SourceTree -Root $Script:Root
        $Script:BaselinePath = Join-Path $Script:Root 'complexity-baseline.json'
        @{
            schemaVersion = 1
            metricVersion = 1
            generatedAt   = '2026-10-09T00:00:00Z'
            units         = @(
                @{ file = 'src/Lib/Functions/Private/Get-Alpha.ps1'; unit = 'Get-Alpha'; cyclomatic = 20; cognitive = 30 }
                @{ file = 'src/Lib/Functions/Private/Get-Beta.ps1'; unit = 'Get-Beta'; cyclomatic = 18; cognitive = 22 }
                @{ file = 'src/Lib/Functions/Private/Removed.ps1'; unit = 'Removed'; cyclomatic = 16; cognitive = 16 }
            )
        } | ConvertTo-Json -Depth 4 | Set-Content -Path $Script:BaselinePath
    }

    Context 'New-ScopedComplexityBaseline' {
        It 'keeps only the entries for the changed files' {
            $Path = New-ScopedComplexityBaseline -BaselineFile $Script:BaselinePath -ChangedFile 'src/Lib/Functions/Private/Get-Beta.ps1' -OutputPath (Join-Path $TestDrive 'scoped\a.json')
            $Scoped = Get-Content $Path -Raw | ConvertFrom-Json
            @($Scoped.units).Count | Should -Be 1
            $Scoped.units[0].unit | Should -Be 'Get-Beta'
        }

        It 'preserves the metric version, which PSComplexity refuses to compare across' {
            $Path = New-ScopedComplexityBaseline -BaselineFile $Script:BaselinePath -ChangedFile 'src/Lib/Functions/Private/Get-Beta.ps1' -OutputPath (Join-Path $TestDrive 'scoped\b.json')
            (Get-Content $Path -Raw | ConvertFrom-Json).metricVersion | Should -Be 1
        }

        It 'writes an empty unit list, not a missing one, when no changed file is baselined' {
            $Path = New-ScopedComplexityBaseline -BaselineFile $Script:BaselinePath -ChangedFile 'src/Lib/Functions/Public/Invoke-Gamma.ps1' -OutputPath (Join-Path $TestDrive 'scoped\c.json')
            (Get-Content $Path -Raw) | Should -Match '"units":\s*\[\s*\]'
        }

        It 'matches backslash paths to the forward-slash entries' {
            $Path = New-ScopedComplexityBaseline -BaselineFile $Script:BaselinePath -ChangedFile 'src\Lib\Functions\Private\Get-Alpha.ps1' -OutputPath (Join-Path $TestDrive 'scoped\d.json')
            (Get-Content $Path -Raw | ConvertFrom-Json).units[0].unit | Should -Be 'Get-Alpha'
        }
    }

    Context 'Get-OrphanedBaselineEntry' {
        It 'returns the entries whose file no longer exists, and only those' {
            $Orphaned = @(Get-OrphanedBaselineEntry -BaselineFile $Script:BaselinePath -RepositoryRoot $Script:Root)
            $Orphaned.Count | Should -Be 1
            $Orphaned[0].file | Should -Be 'src/Lib/Functions/Private/Removed.ps1'
        }
    }
}

Describe 'Get-ModulePinStatus' {
    It 'flags a pin with a newer release as stale' {
        $Status = Get-ModulePinStatus -Pin @{ Name = 'Pester'; RequiredVersion = '6.2.0' } -LatestVersion { param($Name) '6.3.0' }
        $Status.IsStale | Should -BeTrue
        $Status.Latest | Should -Be '6.3.0'
    }

    It 'treats a pin at the latest release as current' {
        (Get-ModulePinStatus -Pin @{ Name = 'Pester'; RequiredVersion = '6.2.0' } -LatestVersion { param($Name) '6.2.0' }).IsStale | Should -BeFalse
    }

    It 'compares versions numerically, not as text' {
        (Get-ModulePinStatus -Pin @{ Name = 'X'; RequiredVersion = '1.9.0' } -LatestVersion { param($Name) '1.10.0' }).IsStale | Should -BeTrue
    }

    It 'reports a failed lookup instead of throwing or claiming the pin is current' {
        $Status = Get-ModulePinStatus -Pin @{ Name = 'X'; RequiredVersion = '1.0.0' } -LatestVersion { param($Name) throw 'gallery unreachable' }
        $Status.Error | Should -Be 'gallery unreachable'
        $Status.Latest | Should -BeNullOrEmpty
        $Status.IsStale | Should -BeFalse
    }
}

Describe 'Limit-MarkdownLength' {
    It 'leaves short text alone' {
        Limit-MarkdownLength -Text 'short' | Should -Be 'short'
    }

    It 'truncates to the maximum and says so' {
        $Result = Limit-MarkdownLength -Text ('x' * 500) -MaximumLength 200
        $Result.Length | Should -Be 200
        $Result | Should -Match 'Truncated at 200 characters'
    }
}

Describe 'Format-ComplexityViolationMarkdown' {
    It 'groups units per file as a checklist, worst file first' {
        $Markdown = Format-ComplexityViolationMarkdown -Violation @(
            [pscustomobject]@{ File = 'src/a.ps1'; Unit = 'A1'; Cyclomatic = 16; Cognitive = 17 }
            [pscustomobject]@{ File = 'src/b.ps1'; Unit = 'B1'; Cyclomatic = 40; Cognitive = 90 }
            [pscustomobject]@{ File = 'src/a.ps1'; Unit = 'A2'; Cyclomatic = 20; Cognitive = 30 }
        )
        $Lines = $Markdown -split "`n"
        $Lines.Count | Should -Be 2
        $Lines[0] | Should -Be '- [ ] `src/b.ps1` — `B1` (cyclomatic 40, cognitive 90)'
        $Lines[1] | Should -Be '- [ ] `src/a.ps1` — `A2` (cyclomatic 20, cognitive 30); `A1` (cyclomatic 16, cognitive 17)'
    }

    It 'says so when there is nothing over the ceilings' {
        Format-ComplexityViolationMarkdown -Violation @() | Should -Be '_No unit is over the ceilings._'
    }
}

Describe 'Format-MutationSurvivorMarkdown' {
    It 'lists survivors per file, lowest score first, with line, function and change' {
        $Markdown = Format-MutationSurvivorMarkdown -Survivor @(
            [pscustomobject]@{ File = 'src/good.ps1'; Line = 9; Function = 'Get-Good'; Description = '-eq -> -ne' }
            [pscustomobject]@{ File = 'src/weak.ps1'; Line = 3; Function = 'Get-Weak'; Description = '0 -> 1' }
        ) -PerFile @(
            [pscustomobject]@{ file = 'src/good.ps1'; score = 90; survived = 1; total = 10 }
            [pscustomobject]@{ file = 'src/weak.ps1'; score = 50; survived = 1; total = 2 }
        )
        $Markdown.IndexOf('src/weak.ps1') | Should -BeLessThan $Markdown.IndexOf('src/good.ps1')
        $Markdown | Should -Match ([regex]::Escape('`src/weak.ps1` — 50% (1 of 2 survived)'))
        $Markdown | Should -Match ([regex]::Escape('- line 3 in `Get-Weak`: `0 -> 1`'))
    }

    It 'says so when every mutant was killed' {
        Format-MutationSurvivorMarkdown -Survivor @() | Should -Be '_No surviving mutants._'
    }
}
