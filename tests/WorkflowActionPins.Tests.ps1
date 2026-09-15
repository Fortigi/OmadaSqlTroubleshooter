#Requires -Version 7.0

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:WorkflowsPath = Join-Path -Path $Script:RepositoryRoot -ChildPath '.github\workflows'

    $Script:WorkflowFiles = @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yml' -File) +
        @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yaml' -File)

    # Matches a `uses:` step reference and captures the action, the ref it is pinned to, and
    # whatever trailing comment follows - the same three pieces every "pin to a SHA" policy needs
    # to check. The `@` is required, so a local composite action (`uses: ./some/path`, no `@ref`
    # at all) never matches and is silently skipped below - it is this repository's own code,
    # checked out with the workflow itself, and has nothing to pin. A reusable workflow reference
    # (`uses: owner/repo/.github/workflows/x.yml@ref`) does match; the ref group is what gets
    # validated below, not the action path.
    $Script:UsesPattern = '^\s*(?:-\s*)?uses:\s*(?<Action>\S+?)@(?<Ref>\S+)\s*(?:#\s*(?<Comment>.*))?$'
}

Describe 'Workflow action pins' -Tag 'Unit' {

    It 'Should find at least one workflow file to check' {
        $Script:WorkflowFiles.Count | Should -BeGreaterThan 0 -Because 'this test exists to guard .github/workflows'
    }

    Context 'Every uses: line' {

        BeforeAll {
            $Script:UsesLines = foreach ($File in $Script:WorkflowFiles) {
                $LineNumber = 0
                foreach ($Line in Get-Content -LiteralPath $File.FullName) {
                    $LineNumber++
                    if ($Line -match $Script:UsesPattern) {
                        [PSCustomObject]@{
                            File    = $File.Name
                            Line    = $LineNumber
                            Action  = $Matches.Action
                            Ref     = $Matches.Ref
                            Comment = $Matches.Comment
                            Raw     = $Line.Trim()
                        }
                    }
                }
            }
        }

        It 'Should find at least one action reference to check' {
            $Script:UsesLines.Count | Should -BeGreaterThan 0 -Because 'every workflow in this repository uses at least one third-party action'
        }

        It 'Should pin every action to a full 40-character commit SHA, not a mutable tag or branch' {
            $Unpinned = $Script:UsesLines | Where-Object { $_.Ref -notmatch '^[0-9a-f]{40}$' }
            $Detail = ($Unpinned | ForEach-Object { "$($_.File):$($_.Line)  $($_.Raw)" }) -join "`n"
            $Unpinned | Should -BeNullOrEmpty -Because "a tag or branch can be moved after review; only a commit SHA is immutable`n$Detail"
        }

        It 'Should carry a trailing version comment next to every pinned SHA' {
            # The comment is what makes a 40-character hex string reviewable, and what Dependabot
            # rewrites alongside the SHA on every bump - a SHA with no `# vX.Y.Z` comment is
            # correctly pinned but not maintainable.
            $Uncommented = $Script:UsesLines | Where-Object {
                $_.Ref -match '^[0-9a-f]{40}$' -and ([string]::IsNullOrWhiteSpace($_.Comment) -or $_.Comment -notmatch '^v\d+\.\d+\.\d+')
            }
            $Detail = ($Uncommented | ForEach-Object { "$($_.File):$($_.Line)  $($_.Raw)" }) -join "`n"
            $Uncommented | Should -BeNullOrEmpty -Because "the SHA pin needs a human-readable '# vX.Y.Z' comment for review and for Dependabot to rewrite`n$Detail"
        }
    }

    Context 'pr-validation.yml workflow-level permissions' {

        BeforeAll {
            $Script:PrValidationPath = Join-Path -Path $Script:WorkflowsPath -ChildPath 'pr-validation.yml'
            $Script:PrValidationLines = Get-Content -LiteralPath $Script:PrValidationPath
        }

        It 'Should keep the workflow-level permissions block empty, since every job declares its own' {
            # dispatch, validate and report-status each carry their own job-level `permissions:`
            # block, and a job-level block fully REPLACES the workflow-level one rather than
            # narrowing it - so a non-empty grant up here is dead for all three jobs today and
            # only widens the default for a future job that forgets to declare its own.
            $TopLevelPermissions = @($Script:PrValidationLines | Where-Object { $_ -match '^permissions:' })
            $TopLevelPermissions | Should -HaveCount 1 -Because 'the top-level permissions: key should appear exactly once'
            $TopLevelPermissions[0] | Should -Match '^permissions:\s*\{\}\s*$' -Because 'every job in this workflow declares its own permissions: block'
        }
    }
}
