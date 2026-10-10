<#
    Policy for the complexity and mutation-testing gates (issue #109).

    The PR lane (Task QualityChanged) holds the code a pull request changed to these numbers; the
    weekly lane (Task QualityFull, .github/workflows/quality-weekly.yml) holds the whole tree to them
    and files a bug per failing gate. Both read this file and nothing else, so a threshold is changed
    in exactly one place.

    Complexity
      MaxCyclomatic / MaxCognitive - the per-unit ceilings, the same ones PSComplexity and PSMutant
                                     gate themselves with.
      BaselineFile                 - units that were already over the ceilings when the gate was
                                     introduced, with the score each may not exceed. It only ratchets
                                     down: run ./build/build.ps1 -Task UpdateComplexityBaseline after
                                     a unit improves, and commit the result.
      SourcePath                   - what is measured, relative to the repository root. Files named
                                     _*.ps1 are excluded, as they are from the build itself.

    Mutation
      SourcePath       - the source tree whose files are mutated, relative to the repository root.
      Operators        - PSMutant operator classes. Adding one renumbers every mutant and lowers the
                         score, so move Thresholds.Break in the same change.
      CoveredLinesOnly - only mutate lines the mapped tests execute; an uncovered mutant teaches
                         nothing.
      SandboxSubtrees  - what PSMutant copies into its sandbox. build is needed because some suites
                         read build/Dependencies.
      Workers          - mutants evaluated in parallel. 3 on the 4-vCPU windows-latest runner.
      Thresholds       - High/Low colour the console score only. Break fails the gate below it.
                         Started at 73 from the first measurement (73.7% on windows-latest,
                         2026-10-09); raise it as the score rises, never lower it to make a red run
                         green.
      Equivalents      - 'path:Function:original -> mutated' = 'why no test can tell the two apart'.
                         PSMutant fails the run if a declaration is ever killed or stops matching.
#>
@{
    Complexity = @{
        MaxCyclomatic = 15
        MaxCognitive  = 15
        BaselineFile  = 'complexity-baseline.json'
        SourcePath    = @('src/Lib/Functions', 'src/Lib/Events')
    }

    Mutation   = @{
        SourcePath       = 'src/Lib/Functions'
        Operators        = @('BinaryOperator', 'BooleanLiteral', 'NegationRemoval', 'NumberLiteral')
        CoveredLinesOnly = $true
        SandboxSubtrees  = @('src', 'tests', 'build')
        Workers          = 3
        Thresholds       = @{
            High  = 85
            Low   = 73
            Break = 73
        }
        Equivalents      = @{}
    }
}
