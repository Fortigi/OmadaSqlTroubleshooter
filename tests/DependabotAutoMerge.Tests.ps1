#Requires -Version 7.0

# Dependabot auto-merge decides, without a human, whether a dependency update reaches main. A mistake in
# these functions fails OPEN - an update merges that policy says should have waited - so every decision
# is pinned here against the real policy file, with all network access mocked through
# Invoke-AutoMergeApi.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $ParentPath -ChildPath 'build' -AdditionalChildPath 'DependabotAutoMerge.ps1')
    $Script:Setting = Get-AutoMergeSetting -Path (Join-Path -Path $ParentPath -ChildPath 'build' -AdditionalChildPath 'DependabotAutoMerge.psd1')
    $Script:Now = [datetime]::new(2026, 10, 12, 12, 0, 0, [System.DateTimeKind]::Utc)

    function New-ApiResponse {
        param([int]$StatusCode = 200, [object]$Content)
        [PSCustomObject]@{ StatusCode = $StatusCode; Content = $Content }
    }

    function New-Scorecard {
        param([double]$Score = 8.5, [int]$DangerousWorkflow = 10, [datetime]$Date = $Script:Now.AddDays(-5))
        [PSCustomObject]@{
            overallScore = $Score
            date         = $Date.ToString('o')
            checks       = @([PSCustomObject]@{ name = 'Dangerous-Workflow'; score = $DangerousWorkflow })
        }
    }

    function New-Dependency {
        param([string]$Name = 'actions/checkout', [string]$Version = '4.5.0', [string]$UpdateType = 'version-update:semver-minor')
        [PSCustomObject]@{ Name = $Name; Version = $Version; UpdateType = $UpdateType; DependencyType = 'direct:production'; Group = $null }
    }

    function New-Commit {
        param([string]$Login = 'dependabot[bot]', [bool]$Verified = $true, [string]$Sha = 'abcdef1234567890', [string]$Message = '')
        [PSCustomObject]@{
            sha    = $Sha
            author = [PSCustomObject]@{ login = $Login }
            commit = [PSCustomObject]@{ message = $Message; verification = [PSCustomObject]@{ verified = $Verified } }
        }
    }

    function New-PrFile {
        param([string]$Name, [string]$Status = 'modified')
        [PSCustomObject]@{ filename = $Name; status = $Status }
    }

    $Script:GroupedMessage = @'
ci: bump the github-actions group with 2 updates

Bumps the github-actions group with 2 updates: [actions/checkout](https://github.com/actions/checkout) and [github/codeql-action](https://github.com/github/codeql-action).

Updates `actions/checkout` from 4.4.0 to 4.5.0
- [Release notes](https://github.com/actions/checkout/releases)

Updates `github/codeql-action` from 3.1.0 to 3.2.1
- [Release notes](https://github.com/github/codeql-action/releases)

---
updated-dependencies:
- dependency-name: actions/checkout
  dependency-version: 4.5.0
  dependency-type: direct:production
  update-type: version-update:semver-minor
  dependency-group: github-actions
- dependency-name: github/codeql-action/init
  dependency-version: '3.2.1'
  dependency-type: direct:production
  update-type: version-update:semver-minor
  dependency-group: github-actions
...

Signed-off-by: dependabot[bot] <support@github.com>
'@
}

Describe 'ConvertFrom-DependabotCommitMessage' {
    It 'reads every dependency of a grouped update, unquoting values' {
        $Result = @(ConvertFrom-DependabotCommitMessage -Message $Script:GroupedMessage)
        $Result | Should -HaveCount 2
        $Result[0].Name | Should -Be 'actions/checkout'
        $Result[0].Version | Should -Be '4.5.0'
        $Result[0].UpdateType | Should -Be 'version-update:semver-minor'
        $Result[0].Group | Should -Be 'github-actions'
        $Result[1].Name | Should -Be 'github/codeql-action/init'
        $Result[1].Version | Should -Be '3.2.1'
    }

    It 'reads a CRLF message the same way' {
        $Result = @(ConvertFrom-DependabotCommitMessage -Message ($Script:GroupedMessage -replace '\r?\n', "`r`n"))
        $Result | Should -HaveCount 2
        $Result[1].UpdateType | Should -Be 'version-update:semver-minor'
    }

    It 'falls back to the Bumps line when the metadata carries no dependency-version' {
        $Message = @'
deps: bump Microsoft.Web.WebView2 from 1.0.4129.50 to 1.0.4200.10

Bumps [Microsoft.Web.WebView2](https://aka.ms/webview) from 1.0.4129.50 to 1.0.4200.10.

---
updated-dependencies:
- dependency-name: Microsoft.Web.WebView2
  dependency-type: direct:production
  update-type: version-update:semver-patch
...
'@
        $Result = @(ConvertFrom-DependabotCommitMessage -Message $Message)
        $Result[0].Version | Should -Be '1.0.4200.10'
        $Result[0].UpdateType | Should -Be 'version-update:semver-patch'
    }

    It 'returns nothing for a message without the metadata block' {
        @(ConvertFrom-DependabotCommitMessage -Message 'Fix a typo') | Should -HaveCount 0
    }
}

Describe 'Get-DependabotEcosystem' {
    It 'reads <Expected> from <Branch>' -ForEach @(
        @{ Branch = 'dependabot/github_actions/github-actions-1a2b3c'; Expected = 'github_actions' }
        @{ Branch = 'dependabot/nuget/build/Dependencies/Microsoft.Web.WebView2-1.0.4200.10'; Expected = 'nuget' }
    ) {
        Get-DependabotEcosystem -BranchName $Branch | Should -Be $Expected
    }

    It 'returns nothing for a branch that is not Dependabot''s' {
        Get-DependabotEcosystem -BranchName 'feature/dependabot-like' | Should -BeNullOrEmpty
    }
}

Describe 'Test-PullRequestProvenance' {
    It 'accepts a verified Dependabot commit that only touches workflow files' {
        $Result = Test-PullRequestProvenance -Commit @(New-Commit) -File @(New-PrFile '.github/workflows/pr-validation.yml') -Ecosystem 'github_actions' -Setting $Script:Setting
        $Result.Eligible | Should -BeTrue
    }

    It 'accepts the signed lock-file commit of this repository''s own workflow on a NuGet bump' {
        $Commits = @((New-Commit), (New-Commit -Login 'github-actions[bot]' -Sha '1234567abcdef'))
        $Files = @((New-PrFile 'build/Dependencies/Dependencies.csproj'), (New-PrFile 'src/DependencyLock.psd1'))
        (Test-PullRequestProvenance -Commit $Commits -File $Files -Ecosystem 'nuget' -Setting $Script:Setting).Eligible | Should -BeTrue
    }

    It 'rejects a commit pushed by a person' {
        $Result = Test-PullRequestProvenance -Commit @((New-Commit), (New-Commit -Login 'someone')) -File @(New-PrFile '.github/workflows/e2e.yml') -Ecosystem 'github_actions' -Setting $Script:Setting
        $Result.Eligible | Should -BeFalse
        $Result.Reasons -join ' ' | Should -Match "authored by 'someone'"
    }

    It 'rejects a commit that claims to be Dependabot''s without a verified signature' {
        $Result = Test-PullRequestProvenance -Commit @(New-Commit -Verified $false) -File @(New-PrFile '.github/workflows/e2e.yml') -Ecosystem 'github_actions' -Setting $Script:Setting
        $Result.Eligible | Should -BeFalse
        $Result.Reasons -join ' ' | Should -Match 'no signature GitHub verified'
    }

    It 'rejects a pull request whose first commit is not Dependabot''s' {
        $Result = Test-PullRequestProvenance -Commit @(New-Commit -Login 'github-actions[bot]') -File @(New-PrFile '.github/workflows/e2e.yml') -Ecosystem 'github_actions' -Setting $Script:Setting
        $Result.Eligible | Should -BeFalse
    }

    It 'rejects <Name> (<Status>) on a <Ecosystem> update' -ForEach @(
        @{ Name = 'src/OmadaSqlTroubleshooter.psm1'; Status = 'modified'; Ecosystem = 'github_actions' }
        @{ Name = '.github/workflows/new.yml'; Status = 'added'; Ecosystem = 'github_actions' }
        @{ Name = 'build/Update-DependencyLock.ps1'; Status = 'modified'; Ecosystem = 'nuget' }
        @{ Name = '.github/workflows/pr-validation.yml'; Status = 'modified'; Ecosystem = 'nuget' }
    ) {
        (Test-PullRequestProvenance -Commit @(New-Commit) -File @(New-PrFile -Name $Name -Status $Status) -Ecosystem $Ecosystem -Setting $Script:Setting).Eligible | Should -BeFalse
    }

    It 'rejects an ecosystem that has no auto-merge configuration' {
        (Test-PullRequestProvenance -Commit @(New-Commit) -File @() -Ecosystem 'npm_and_yarn' -Setting $Script:Setting).Eligible | Should -BeFalse
    }
}

Describe 'Test-ScorecardPolicy' {
    It 'passes a recent Scorecard above every floor' {
        @(Test-ScorecardPolicy -Scorecard (New-Scorecard) -ProjectKey 'github.com/a/b' -Policy $Script:Setting.Reputation -Now $Script:Now) | Should -HaveCount 0
    }

    It 'fails <Case>' -ForEach @(
        @{ Case = 'a missing Scorecard'; Scorecard = $null; Pattern = 'no OpenSSF Scorecard' }
        @{ Case = 'a score below the minimum'; Scorecard = 'low'; Pattern = 'below the minimum of 7.0' }
        @{ Case = 'a stale Scorecard'; Scorecard = 'stale'; Pattern = 'days old' }
        @{ Case = 'a dangerous workflow'; Scorecard = 'dangerous'; Pattern = 'Dangerous-Workflow' }
        @{ Case = 'an inconclusive dangerous-workflow check'; Scorecard = 'inconclusive'; Pattern = 'Dangerous-Workflow' }
    ) {
        $Card = switch ($Scorecard) {
            'low' { New-Scorecard -Score 6.9 }
            'stale' { New-Scorecard -Date $Script:Now.AddDays(-60) }
            'dangerous' { New-Scorecard -DangerousWorkflow 0 }
            'inconclusive' { New-Scorecard -DangerousWorkflow -1 }
            default { $null }
        }
        $Reasons = @(Test-ScorecardPolicy -Scorecard $Card -ProjectKey 'github.com/a/b' -Policy $Script:Setting.Reputation -Now $Script:Now)
        $Reasons | Should -Not -HaveCount 0
        $Reasons -join ' ' | Should -Match $Pattern
    }

    It 'fails a Scorecard that lacks a check the policy sets a floor for' {
        $Card = New-Scorecard
        $Card.checks = @()
        (Test-ScorecardPolicy -Scorecard $Card -ProjectKey 'github.com/a/b' -Policy $Script:Setting.Reputation -Now $Script:Now) -join ' ' | Should -Match 'has no Dangerous-Workflow check'
    }
}

Describe 'Test-DependencyReputation' {
    BeforeEach {
        Mock Invoke-AutoMergeApi { New-ApiResponse -StatusCode 404 }
    }

    It 'stops at a major update without asking any reputation source' {
        $Result = Test-DependencyReputation -Dependency (New-Dependency -UpdateType 'version-update:semver-major') -Ecosystem 'github_actions' -Setting $Script:Setting -Now $Script:Now
        $Result.Eligible | Should -BeFalse
        Should -Invoke Invoke-AutoMergeApi -Times 0
    }

    Context 'a GitHub Action' {
        It 'passes a release old enough from a repository with a good Scorecard' {
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/repos/actions/checkout/releases/tags/v4.5.0' } { New-ApiResponse -Content ([PSCustomObject]@{ draft = $false; prerelease = $false; published_at = $Script:Now.AddDays(-10).ToString('o') }) }
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -eq 'https://api.deps.dev/v3/projects/github.com%2Factions%2Fcheckout' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard -Score 8.1) }) }

            $Result = Test-DependencyReputation -Dependency (New-Dependency) -Ecosystem 'github_actions' -Setting $Script:Setting -Now $Script:Now
            $Result.Reasons | Should -BeNullOrEmpty
            $Result.Eligible | Should -BeTrue
            $Result.Score | Should -Be 8.1
            $Result.ProjectKey | Should -Be 'github.com/actions/checkout'
        }

        It 'looks the Scorecard up by owner/repository for an action in a subdirectory' {
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/repos/github/codeql-action/releases/tags/v3.2.1' } { New-ApiResponse -Content ([PSCustomObject]@{ draft = $false; prerelease = $false; published_at = $Script:Now.AddDays(-10).ToString('o') }) }
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -eq 'https://api.deps.dev/v3/projects/github.com%2Fgithub%2Fcodeql-action' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }

            (Test-DependencyReputation -Dependency (New-Dependency -Name 'github/codeql-action/init' -Version '3.2.1') -Ecosystem 'github_actions' -Setting $Script:Setting -Now $Script:Now).Eligible | Should -BeTrue
        }

        It 'fails a version without a published release, since its age is unknown' {
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like 'https://api.deps.dev/*' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }
            $Result = Test-DependencyReputation -Dependency (New-Dependency) -Ecosystem 'github_actions' -Setting $Script:Setting -Now $Script:Now
            $Result.Eligible | Should -BeFalse
            $Result.Reasons -join ' ' | Should -Match 'no published GitHub release'
        }

        It 'fails a release younger than the minimum age, as a security update that bypassed cooldown would be' {
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/releases/tags/v4.5.0' } { New-ApiResponse -Content ([PSCustomObject]@{ draft = $false; prerelease = $false; published_at = $Script:Now.AddHours(-20).ToString('o') }) }
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like 'https://api.deps.dev/*' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }
            $Result = Test-DependencyReputation -Dependency (New-Dependency) -Ecosystem 'github_actions' -Setting $Script:Setting -Now $Script:Now
            $Result.Eligible | Should -BeFalse
            $Result.Reasons -join ' ' | Should -Match 'less than the 3 required'
        }

        It 'fails a prerelease' {
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/releases/tags/v4.5.0' } { New-ApiResponse -Content ([PSCustomObject]@{ draft = $false; prerelease = $true; published_at = $Script:Now.AddDays(-10).ToString('o') }) }
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like 'https://api.deps.dev/*' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }
            (Test-DependencyReputation -Dependency (New-Dependency) -Ecosystem 'github_actions' -Setting $Script:Setting -Now $Script:Now).Eligible | Should -BeFalse
        }
    }

    Context 'a NuGet package' {
        It 'passes a package deps.dev links to a source repository with a good Scorecard, trying the lower-cased id' {
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -eq 'https://api.deps.dev/v3/systems/nuget/packages/microsoft.sqlserver.transactsql.scriptdom/versions/180.103.0' } {
                New-ApiResponse -Content ([PSCustomObject]@{
                        publishedAt     = $Script:Now.AddDays(-12).ToString('o')
                        relatedProjects = @(
                            [PSCustomObject]@{ relationType = 'ISSUE_TRACKER'; projectKey = [PSCustomObject]@{ id = 'github.com/elsewhere/tracker' } }
                            [PSCustomObject]@{ relationType = 'SOURCE_REPO'; projectKey = [PSCustomObject]@{ id = 'github.com/microsoft/sqlscriptdom' } }
                        )
                    })
            }
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -eq 'https://api.deps.dev/v3/projects/github.com%2Fmicrosoft%2Fsqlscriptdom' } { New-ApiResponse -Content ([PSCustomObject]@{ scorecard = (New-Scorecard) }) }

            $Result = Test-DependencyReputation -Dependency (New-Dependency -Name 'Microsoft.SqlServer.TransactSql.ScriptDom' -Version '180.103.0') -Ecosystem 'nuget' -Setting $Script:Setting -Now $Script:Now
            $Result.Reasons | Should -BeNullOrEmpty
            $Result.Eligible | Should -BeTrue
        }

        It 'fails a package deps.dev links to no source repository' {
            Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like 'https://api.deps.dev/v3/systems/nuget/*' } { New-ApiResponse -Content ([PSCustomObject]@{ publishedAt = $Script:Now.AddDays(-12).ToString('o'); relatedProjects = @() }) }
            $Result = Test-DependencyReputation -Dependency (New-Dependency -Name 'Microsoft.Web.WebView2' -Version '1.0.4200.10') -Ecosystem 'nuget' -Setting $Script:Setting -Now $Script:Now
            $Result.Eligible | Should -BeFalse
            $Result.Reasons -join ' ' | Should -Match 'no source repository'
        }

        It 'fails a version deps.dev does not know' {
            (Test-DependencyReputation -Dependency (New-Dependency -Name 'Unknown.Package' -Version '1.0.0') -Ecosystem 'nuget' -Setting $Script:Setting -Now $Script:Now).Eligible | Should -BeFalse
        }
    }
}

Describe 'Get-AutoMergeStep' {
    BeforeAll {
        $Script:Ready = @{
            NeedsLockSync   = $false
            Mergeable       = $true
            BehindBy        = 0
            WorkflowActive  = $false
            ValidationState = 'success'
            ReviewState     = 'success'
        }
    }

    It 'returns <Expected> when <Case>' -ForEach @(
        @{ Case = 'everything is green'; Change = @{}; Expected = 'Merge' }
        @{ Case = 'the branch conflicts'; Change = @{ Mergeable = $false }; Expected = 'Blocked' }
        @{ Case = 'a run is still active'; Change = @{ WorkflowActive = $true; NeedsLockSync = $true }; Expected = 'Wait' }
        @{ Case = 'the lock file is not refreshed yet'; Change = @{ NeedsLockSync = $true; BehindBy = 2; ValidationState = 'missing' }; Expected = 'SyncLock' }
        @{ Case = 'the branch is behind main'; Change = @{ BehindBy = 1; ValidationState = 'failure' }; Expected = 'UpdateBranch' }
        @{ Case = 'validation failed'; Change = @{ ValidationState = 'failure'; ReviewState = 'missing' }; Expected = 'Blocked' }
        @{ Case = 'the review failed'; Change = @{ ReviewState = 'failure' }; Expected = 'Blocked' }
        @{ Case = 'validation never ran'; Change = @{ ValidationState = 'missing'; ReviewState = 'pending' }; Expected = 'DispatchChecks' }
        @{ Case = 'checks are still running'; Change = @{ ValidationState = 'pending' }; Expected = 'Wait' }
    ) {
        $Arguments = $Script:Ready.Clone()
        foreach ($Key in $Change.Keys) { $Arguments[$Key] = $Change[$Key] }
        (Get-AutoMergeStep @Arguments).Action | Should -Be $Expected
    }

    It 'names every check that has to be dispatched' {
        $Arguments = $Script:Ready.Clone()
        $Arguments.ValidationState = 'missing'
        $Arguments.ReviewState = 'missing'
        (Get-AutoMergeStep @Arguments).Detail | Should -Be 'Validation,Review'
    }
}

Describe 'Get-CommitStatusState and Get-CheckRunState' {
    It 'maps commit status <State> to <Expected>' -ForEach @(
        @{ State = 'success'; Expected = 'success' }
        @{ State = 'pending'; Expected = 'pending' }
        @{ State = 'failure'; Expected = 'failure' }
        @{ State = 'error'; Expected = 'failure' }
    ) {
        Mock Invoke-AutoMergeApi { New-ApiResponse -Content ([PSCustomObject]@{ statuses = @([PSCustomObject]@{ context = 'PR Validation'; state = $State }, [PSCustomObject]@{ context = 'other'; state = 'success' }) }) }
        Get-CommitStatusState -Repository 'o/r' -Sha 'abc' -Context 'PR Validation' | Should -Be $Expected
    }

    It 'reports a commit status context that never reported as missing' {
        Mock Invoke-AutoMergeApi { New-ApiResponse -Content ([PSCustomObject]@{ statuses = @() }) }
        Get-CommitStatusState -Repository 'o/r' -Sha 'abc' -Context 'PR Validation' | Should -Be 'missing'
    }

    It 'maps the latest check run (<Status>/<Conclusion>) to <Expected>' -ForEach @(
        @{ Status = 'in_progress'; Conclusion = $null; Expected = 'pending' }
        @{ Status = 'completed'; Conclusion = 'success'; Expected = 'success' }
        @{ Status = 'completed'; Conclusion = 'failure'; Expected = 'failure' }
        @{ Status = 'completed'; Conclusion = 'neutral'; Expected = 'failure' }
        @{ Status = 'completed'; Conclusion = 'cancelled'; Expected = 'missing' }
    ) {
        Mock Invoke-AutoMergeApi {
            New-ApiResponse -Content ([PSCustomObject]@{ check_runs = @(
                        [PSCustomObject]@{ id = 1; status = 'completed'; conclusion = 'success' }
                        [PSCustomObject]@{ id = 2; status = $Status; conclusion = $Conclusion }
                    ) })
        }
        Get-CheckRunState -Repository 'o/r' -Sha 'abc' -Name 'Dependency Review' | Should -Be $Expected
    }
}

Describe 'Invoke-AutoMergeApi' {
    BeforeAll {
        $Script:SavedToken = $env:GITHUB_TOKEN
        $env:GITHUB_TOKEN = 'test-token'
    }
    AfterAll {
        $env:GITHUB_TOKEN = $Script:SavedToken
    }

    It 'sends the GITHUB_TOKEN to api.github.com' {
        Mock Invoke-RestMethod { @{} }
        $null = Invoke-AutoMergeApi -Uri 'https://api.github.com/repos/o/r'
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Headers['Authorization'] -eq 'Bearer test-token' }
    }

    It 'never sends the GITHUB_TOKEN anywhere else' {
        Mock Invoke-RestMethod { @{} }
        $null = Invoke-AutoMergeApi -Uri 'https://api.deps.dev/v3/projects/x'
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { -not $Headers.ContainsKey('Authorization') }
    }
}

Describe 'Format-AutoMergeReport' {
    It 'starts with the marker the comment is found by again, and is stable for the same evaluation' {
        $Evaluation = [PSCustomObject]@{
            Eligible     = $false
            HeadSha      = 'abc123'
            Reasons      = @('`x`: Scorecard 5.0 for github.com/a/b is below the minimum of 7.0')
            Dependencies = @([PSCustomObject]@{ Name = 'x'; Version = '1.2.0'; UpdateType = 'version-update:semver-minor'; ProjectKey = 'github.com/a/b'; Score = 5.0; PublishedAt = $Script:Now; Eligible = $false })
            Step         = $null
        }
        $First = Format-AutoMergeReport -Evaluation $Evaluation
        $First | Should -BeLike '<!-- dependabot-auto-merge -->*'
        $First | Should -Match 'Manual review required'
        $First | Should -Match '\| `x` \| 1.2.0 \| semver-minor \| github.com/a/b \| 5.0 \| 2026-10-12 \| fail \|'
        Format-AutoMergeReport -Evaluation $Evaluation | Should -BeExactly $First
    }
}

Describe 'Invoke-AutoMergeStep' {
    BeforeEach {
        Mock Invoke-WorkflowDispatch { }
        Mock Test-AutoMergeWorkflowActive { $false }
        Mock Get-CommitStatusState { 'success' }
        Mock Get-CheckRunState { 'success' }
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/7' } { New-ApiResponse -Content ([PSCustomObject]@{ mergeable = $true }) }
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/compare/*' } { New-ApiResponse -Content ([PSCustomObject]@{ behind_by = 0 }) }
        $Script:Evaluation = [PSCustomObject]@{
            Number        = 7
            Branch        = 'dependabot/nuget/build/Dependencies/Microsoft.SqlServer.TransactSql.ScriptDom-180.103.0'
            HeadSha       = 'headsha'
            NeedsLockSync = $false
            Files         = @('build/Dependencies/Dependencies.csproj', 'src/DependencyLock.psd1')
        }
    }

    It 'merges exactly the validated head and starts the release when src/ changed' {
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/7/merge' } { New-ApiResponse -Content ([PSCustomObject]@{ merged = $true }) }
        $Step = Invoke-AutoMergeStep -Repository 'o/r' -DefaultBranch 'main' -Evaluation $Script:Evaluation -Setting $Script:Setting
        $Step.Action | Should -Be 'Merged'
        Should -Invoke Invoke-AutoMergeApi -Times 1 -ParameterFilter { $Uri -like '*/pulls/7/merge' -and $Method -eq 'Put' -and $Body.sha -eq 'headsha' -and $Body.merge_method -eq 'squash' }
        Should -Invoke Invoke-WorkflowDispatch -Times 1 -ParameterFilter { $WorkflowFile -eq 'release.yml' -and $Ref -eq 'main' }
    }

    It 'does not start a release for a merge outside src/' {
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/7/merge' } { New-ApiResponse -Content ([PSCustomObject]@{ merged = $true }) }
        $Script:Evaluation.Files = @('.github/workflows/e2e.yml')
        (Invoke-AutoMergeStep -Repository 'o/r' -DefaultBranch 'main' -Evaluation $Script:Evaluation -Setting $Script:Setting).Action | Should -Be 'Merged'
        Should -Invoke Invoke-WorkflowDispatch -Times 0
    }

    It 'reports a merge GitHub refuses as blocked' {
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/7/merge' } { New-ApiResponse -StatusCode 405 -Content ([PSCustomObject]@{ message = 'Repository rule violations found' }) }
        $Step = Invoke-AutoMergeStep -Repository 'o/r' -DefaultBranch 'main' -Evaluation $Script:Evaluation -Setting $Script:Setting
        $Step.Action | Should -Be 'Blocked'
        $Step.Detail | Should -Match 'Repository rule violations'
    }

    It 'dispatches validation on main for the pull request and the review on its branch' {
        Mock Get-CommitStatusState { 'missing' }
        Mock Get-CheckRunState { 'missing' }
        (Invoke-AutoMergeStep -Repository 'o/r' -DefaultBranch 'main' -Evaluation $Script:Evaluation -Setting $Script:Setting).Action | Should -Be 'DispatchChecks'
        Should -Invoke Invoke-WorkflowDispatch -Times 1 -ParameterFilter { $WorkflowFile -eq 'pr-validation.yml' -and $Ref -eq 'main' -and $Inputs.pr_number -eq '7' }
        Should -Invoke Invoke-WorkflowDispatch -Times 1 -ParameterFilter { $WorkflowFile -eq 'dependency-review.yml' -and $Ref -eq $Script:Evaluation.Branch }
    }

    It 'dispatches the lock sync for the branch while the lock file is not refreshed' {
        $Script:Evaluation.NeedsLockSync = $true
        (Invoke-AutoMergeStep -Repository 'o/r' -DefaultBranch 'main' -Evaluation $Script:Evaluation -Setting $Script:Setting).Action | Should -Be 'SyncLock'
        Should -Invoke Invoke-WorkflowDispatch -Times 1 -ParameterFilter { $WorkflowFile -eq 'dependency-lock-sync.yml' -and $Ref -eq 'main' -and $Inputs.branch -eq $Script:Evaluation.Branch }
    }

    It 'changes nothing under -WhatIf' {
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/7/merge' } { New-ApiResponse -Content ([PSCustomObject]@{ merged = $true }) }
        (Invoke-AutoMergeStep -Repository 'o/r' -DefaultBranch 'main' -Evaluation $Script:Evaluation -Setting $Script:Setting -WhatIf).Action | Should -Be 'Merge'
        Should -Invoke Invoke-AutoMergeApi -Times 0 -ParameterFilter { $Method -in 'Post', 'Put', 'Patch' }
        Should -Invoke Invoke-WorkflowDispatch -Times 0
    }
}

Describe 'Invoke-DependabotAutoMerge' {
    BeforeEach {
        Mock Set-AutoMergeComment { }
        Mock Invoke-AutoMergeStep { [PSCustomObject]@{ Action = 'Wait'; Detail = 'checks running' } }
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls?state=open*' } {
            New-ApiResponse -Content @(
                [PSCustomObject]@{ number = 12; draft = $false; user = [PSCustomObject]@{ login = 'dependabot[bot]' }; head = [PSCustomObject]@{ ref = 'dependabot/github_actions/b'; sha = 's12' } }
                [PSCustomObject]@{ number = 10; draft = $false; user = [PSCustomObject]@{ login = 'dependabot[bot]' }; head = [PSCustomObject]@{ ref = 'dependabot/github_actions/a'; sha = 's10' } }
                [PSCustomObject]@{ number = 11; draft = $false; user = [PSCustomObject]@{ login = 'someone' }; head = [PSCustomObject]@{ ref = 'feature/x'; sha = 's11' } }
            )
        }
        Mock Get-DependabotPullRequestEvaluation {
            [PSCustomObject]@{ Number = [int]$PullRequest.number; Branch = $PullRequest.head.ref; HeadSha = $PullRequest.head.sha; Ecosystem = 'github_actions'; Eligible = $true; Reasons = @(); Dependencies = @(); Files = @(); NeedsLockSync = $false; Step = $null }
        }
    }

    It 'evaluates only Dependabot''s pull requests and advances only the oldest eligible one' {
        $Results = Invoke-DependabotAutoMerge -Repository 'o/r' -DefaultBranch 'main' -Setting $Script:Setting -Now $Script:Now
        $Results.Number | Should -Be @(10, 12)
        $Results[0].Step.Action | Should -Be 'Wait'
        $Results[1].Step.Action | Should -Be 'Queued'
        Should -Invoke Invoke-AutoMergeStep -Times 1 -ParameterFilter { $Evaluation.Number -eq 10 }
        Should -Invoke Set-AutoMergeComment -Times 2
    }

    It 'moves on to the next eligible pull request when the oldest is blocked' {
        Mock Invoke-AutoMergeStep { [PSCustomObject]@{ Action = 'Blocked'; Detail = 'validation failed' } } -ParameterFilter { $Evaluation.Number -eq 10 }
        $Results = Invoke-DependabotAutoMerge -Repository 'o/r' -DefaultBranch 'main' -Setting $Script:Setting -Now $Script:Now
        $Results[1].Step.Action | Should -Be 'Wait'
        Should -Invoke Invoke-AutoMergeStep -Times 2
    }

    It 'takes no step for a pull request that is not eligible' {
        Mock Get-DependabotPullRequestEvaluation {
            [PSCustomObject]@{ Number = [int]$PullRequest.number; Branch = $PullRequest.head.ref; HeadSha = $PullRequest.head.sha; Ecosystem = 'github_actions'; Eligible = $false; Reasons = @('major'); Dependencies = @(); Files = @(); NeedsLockSync = $false; Step = $null }
        }
        $null = Invoke-DependabotAutoMerge -Repository 'o/r' -DefaultBranch 'main' -Setting $Script:Setting -Now $Script:Now
        Should -Invoke Invoke-AutoMergeStep -Times 0
        Should -Invoke Set-AutoMergeComment -Times 2
    }
}

Describe 'Get-DependabotPullRequestEvaluation' {
    It 'marks a NuGet pull request without the refreshed lock file as needing a lock sync' {
        $Message = $Script:GroupedMessage -replace 'actions/checkout', 'Microsoft.SqlServer.TransactSql.ScriptDom'
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/5/commits*' } { New-ApiResponse -Content @(New-Commit -Message $Message) }
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/5/files*' } { New-ApiResponse -Content @(New-PrFile 'build/Dependencies/Dependencies.csproj') }
        Mock Test-DependencyReputation { [PSCustomObject]@{ Name = $Dependency.Name; Eligible = $true; Reasons = @() } }

        $PullRequest = [PSCustomObject]@{ number = 5; head = [PSCustomObject]@{ ref = 'dependabot/nuget/build/Dependencies/x-1.0.1'; sha = 'h5' } }
        $Evaluation = Get-DependabotPullRequestEvaluation -Repository 'o/r' -PullRequest $PullRequest -Setting $Script:Setting -Now $Script:Now
        $Evaluation.Eligible | Should -BeTrue
        $Evaluation.Ecosystem | Should -Be 'nuget'
        $Evaluation.NeedsLockSync | Should -BeTrue
    }

    It 'does not judge reputation for a pull request whose provenance already failed' {
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/6/commits*' } { New-ApiResponse -Content @((New-Commit -Message $Script:GroupedMessage), (New-Commit -Login 'someone')) }
        Mock Invoke-AutoMergeApi -ParameterFilter { $Uri -like '*/pulls/6/files*' } { New-ApiResponse -Content @(New-PrFile '.github/workflows/e2e.yml') }
        Mock Test-DependencyReputation { throw 'should not be called' }

        $PullRequest = [PSCustomObject]@{ number = 6; head = [PSCustomObject]@{ ref = 'dependabot/github_actions/x'; sha = 'h6' } }
        (Get-DependabotPullRequestEvaluation -Repository 'o/r' -PullRequest $PullRequest -Setting $Script:Setting -Now $Script:Now).Eligible | Should -BeFalse
    }
}
