<#
    Policy for Dependabot auto-merge (.github/workflows/dependabot-auto-merge.yml).

    GitHub auto-merge is enabled on a Dependabot pull request only when ALL of the following hold, and
    GitHub then still merges it only once every check the "Protect Main" ruleset requires - PR
    Validation and Dependency Review - is green. Anything else stays a normal pull request that waits for
    a maintainer, exactly as before.

    AllowedUpdateTypes   - the Dependabot update types that may merge on their own. Every dependency in
                           the pull request must have one of these - a grouped pull request with one
                           major bump in it waits for a human as a whole.

    MinimumReleaseAgeDays
                         - the new version must have been published at least this long ago, by the
                           GitHub release's published_at. The cooldown in .github/dependabot.yml already
                           holds version updates back, but Dependabot SECURITY updates bypass cooldown
                           entirely; this keeps the same window for them before anything merges
                           unattended. A fresh security update can still be merged by hand at once.

    Reputation           - the OpenSSF Scorecard of the action's repository, as published by deps.dev
                           (https://deps.dev, Google's Open Source Insights). No Scorecard means no
                           reputation, which means a human decides.
      MinimumOverallScore      - the weighted Scorecard score, 0-10.
      MaximumScorecardAgeDays  - a Scorecard older than this is treated as missing. deps.dev refreshes
                                 them weekly, so a stale one means the project dropped out of the scan.
      MinimumCheckScore        - per-check floors on top of the overall score. A check that is missing
                                 or inconclusive (-1) fails its floor. Dangerous-Workflow is the one that
                                 matters most for supply-chain attacks: a 0 there means the project's own
                                 CI can be made to run attacker-controlled code - the route by which a
                                 release gets poisoned without a maintainer account being stolen.

    TrustedCommitAuthors - every commit on the pull request must be authored by one of these accounts AND
                           carry a signature GitHub verified. A commit pushed by anyone else, a person
                           included, takes the pull request out of auto-merge.

    Ecosystems           - the Dependabot ecosystems (the second segment of its branch name) that may
                           auto-merge, each with the only files a pull request may touch, all of them
                           modified rather than added or removed. Only github_actions: the NuGet bumps
                           in build/Dependencies also need the lock-file refresh and trigger a release on
                           merge, and stay with a maintainer.
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
    )

    Ecosystems            = @{
        github_actions = @{
            AllowedFiles = @('^\.github/workflows/[^/]+\.ya?ml$')
        }
    }
}
