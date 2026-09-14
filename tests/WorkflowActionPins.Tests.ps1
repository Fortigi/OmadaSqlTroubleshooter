BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:WorkflowsPath = Join-Path -Path $Script:RepositoryRoot -ChildPath '.github\workflows'

    $Script:WorkflowFiles = @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yml' -File) +
        @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yaml' -File)

    # Matches a `uses:` step reference and captures the action, the ref it is pinned to, and
    # whatever trailing comment follows - the same three pieces every "pin to a SHA" policy needs
    # to check. A local composite action (`uses: ./some/path`) or a reusable workflow reference
    # (`uses: owner/repo/.github/workflows/x.yml@ref`) both still match; the ref group is what gets
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
                        # A local composite action (uses: ./path/to/action) has nothing to pin - it
                        # is this repository's own code, checked out with the workflow itself.
                        if ($Matches.Action -like './*') { continue }

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
                $_.Ref -match '^[0-9a-f]{40}$' -and ([string]::IsNullOrWhiteSpace($_.Comment) -or $_.Comment -notmatch '^v\d')
            }
            $Detail = ($Uncommented | ForEach-Object { "$($_.File):$($_.Line)  $($_.Raw)" }) -join "`n"
            $Uncommented | Should -BeNullOrEmpty -Because "the SHA pin needs a human-readable '# vX.Y.Z' comment for review and for Dependabot to rewrite`n$Detail"
        }
    }
}
