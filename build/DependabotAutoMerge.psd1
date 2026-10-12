<#
    Policy for Dependabot auto-merge (.github/workflows/dependabot-auto-merge.yml).

    A Dependabot pull request is merged without a human only when ALL of the following hold. Anything
    else stays a normal pull request that waits for a maintainer, exactly as before.

    AllowedUpdateTypes   - the Dependabot update types that may merge on their own. Every dependency in
                           the pull request must have one of these - a grouped pull request with one
                           major bump in it waits for a human as a whole.

    MinimumReleaseAgeDays
                         - the new version must have been published at least this long ago. The
                           cooldown in .github/dependabot.yml already holds version updates back, but
                           Dependabot SECURITY updates bypass cooldown entirely; this keeps the same
                           window for them before anything merges unattended. A fresh security update
                           can still be merged by hand at once.

    Reputation           - the OpenSSF Scorecard of the dependency's source repository, as published by
                           deps.dev (https://deps.dev, Google's Open Source Insights). No Scorecard -
                           for example a package whose source repository deps.dev does not know - means
                           no reputation, which means a human decides.
      MinimumOverallScore      - the weighted Scorecard score, 0-10.
      MaximumScorecardAgeDays  - a Scorecard older than this is treated as missing. deps.dev refreshes
                                 them weekly, so a stale one means the project dropped out of the scan.
      MinimumCheckScore        - per-check floors on top of the overall score. A check that is missing
                                 or inconclusive (-1) fails its floor. Dangerous-Workflow is the one that
                                 matters most for supply-chain attacks: a 0 there means the project's own
                                 CI can be made to run attacker-controlled code - the route by which a
                                 release gets poisoned without a maintainer account being stolen.

    TrustedCommitAuthors - every commit on the pull request must be authored by one of these accounts AND
                           carry a signature GitHub verified. dependabot[bot] writes the bump;
                           github-actions[bot] is this repository's own workflows - the lock-file refresh
                           and the branch update - which commit through the API and are signed by GitHub
                           for it. A commit pushed by anyone else, a person included, takes the pull
                           request out of auto-merge for good.

    Ecosystems           - per Dependabot ecosystem (the second segment of its branch name), the only
                           files the pull request may touch, all of them modified rather than added or
                           removed. NeedsLockSync marks the ecosystem whose bump is only half an update
                           until .github/workflows/dependency-lock-sync.yml has repinned the hash.

    Checks               - what has to be green on the pull request head before it merges: the commit
                           status PR Validation reports and the check run Dependency Review creates. Both
                           are also required by the "Protect Main" ruleset, which the merge cannot bypass.
#>
@{
    AllowedUpdateTypes    = @(
        'version-update:semver-patch'
        'version-update:semver-minor'
    )

    MinimumReleaseAgeDays = 3

    Reputation            = @{
        MinimumOverallScore     = 7.0
        MaximumScorecardAgeDays = 45
        MinimumCheckScore       = @{
            'Dangerous-Workflow' = 10
        }
    }

    TrustedCommitAuthors  = @(
        'dependabot[bot]'
        'github-actions[bot]'
    )

    Ecosystems            = @{
        github_actions = @{
            AllowedFiles  = @('^\.github/workflows/[^/]+\.ya?ml$')
            NeedsLockSync = $false
        }
        nuget          = @{
            AllowedFiles  = @('^build/Dependencies/Dependencies\.csproj$', '^src/DependencyLock\.psd1$')
            NeedsLockSync = $true
            LockFile      = 'src/DependencyLock.psd1'
        }
    }

    Checks                = @{
        ValidationStatus = 'PR Validation'
        ReviewCheckRun   = 'Dependency Review'
    }

    Workflows             = @{
        Validation = 'pr-validation.yml'
        Review     = 'dependency-review.yml'
        LockSync   = 'dependency-lock-sync.yml'
        Release    = 'release.yml'
    }
}
