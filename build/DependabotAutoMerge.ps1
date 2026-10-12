<#
    Functions behind Dependabot auto-merge (.github/workflows/dependabot-auto-merge.yml). Policy in
    build/DependabotAutoMerge.psd1, which explains every threshold.

    Dot-sourced by build/Invoke-DependabotAutoMerge.ps1 and by tests/DependabotAutoMerge.Tests.ps1.

    These functions only DECIDE whether a Dependabot pull request may merge on its own, and say why in
    one comment on it. Starting validation and enabling GitHub auto-merge is left to the workflow.

    All network access goes through Invoke-AutoMergeApi, which is what the tests mock. The decisions -
    parsing the Dependabot commit, judging provenance and reputation - are plain functions of their
    inputs.
#>

$Script:AutoMergeCommentMarker = '<!-- dependabot-auto-merge -->'

function Get-AutoMergeSetting {
    <#
    .SYNOPSIS
        Reads build/DependabotAutoMerge.psd1.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Import-PowerShellDataFile -Path $Path)
}

function Invoke-AutoMergeApi {
    <#
    .SYNOPSIS
        One REST call. Never throws on an HTTP error status: returns StatusCode and Content instead,
        so a 404 is an answer ("no such release") rather than an exception.
    .DESCRIPTION
        The GITHUB_TOKEN is attached only to requests for api.github.com - never to deps.dev or any
        other host a URL might point at.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [ValidateSet('Get', 'Post', 'Put', 'Patch')]
        [string]$Method = 'Get',

        [object]$Body
    )

    $Headers = @{ 'User-Agent' = 'OmadaSqlTroubleshooter-dependabot-auto-merge' }
    if (([uri]$Uri).Host -eq 'api.github.com') {
        $Headers['Accept'] = 'application/vnd.github+json'
        $Headers['X-GitHub-Api-Version'] = '2022-11-28'
        if (-not [string]::IsNullOrEmpty($env:GITHUB_TOKEN)) {
            $Headers['Authorization'] = 'Bearer {0}' -f $env:GITHUB_TOKEN
        }
    }

    $Request = @{
        Uri                = $Uri
        Method             = $Method
        Headers            = $Headers
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'ResponseStatusCode'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $Request['Body'] = $Body | ConvertTo-Json -Depth 10 -Compress
        $Request['ContentType'] = 'application/json'
    }

    $Content = Invoke-RestMethod @Request
    return [PSCustomObject]@{
        StatusCode = [int]$ResponseStatusCode
        Content    = $Content
    }
}

function ConvertTo-UtcDate {
    <#
    .SYNOPSIS
        A timestamp from a JSON response as UTC. ConvertFrom-Json already turns ISO 8601 strings into
        DateTime, but not every response goes through it the same way, so accept both.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    if ($Value -is [datetime]) {
        return ([datetimeoffset]$Value).UtcDateTime
    }
    return [datetimeoffset]::Parse([string]$Value, [cultureinfo]::InvariantCulture).UtcDateTime
}

function Get-DependabotEcosystem {
    <#
    .SYNOPSIS
        The ecosystem segment of a Dependabot branch name: dependabot/<ecosystem>/..., for example
        github_actions or nuget. $null for any other branch.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    if ($BranchName -match '^dependabot/(?<Ecosystem>[^/]+)/') {
        return $Matches.Ecosystem
    }
    return $null
}

function ConvertFrom-DependabotCommitMessage {
    <#
    .SYNOPSIS
        The dependencies a Dependabot commit updates, from the metadata block it ends every commit
        message with:

            ---
            updated-dependencies:
            - dependency-name: actions/checkout
              dependency-version: 4.3.0
              dependency-type: direct:production
              update-type: version-update:semver-minor
              dependency-group: github-actions
            ...

        This is the same block dependabot/fetch-metadata parses. Parsing it here keeps one more
        third-party action out of a job that holds write permissions. When an older message carries
        no dependency-version, the version is taken from its "Updates `x` from a to b" or
        "Bumps x from a to b." line instead.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $Block = [regex]::Match($Message, '(?ms)^updated-dependencies:[ \t]*\r?$(?<Body>.*?)^\.\.\.[ \t]*\r?$')
    if (-not $Block.Success) {
        return @()
    }

    $Dependencies = [System.Collections.Generic.List[hashtable]]::new()
    $Current = $null
    foreach ($Line in ($Block.Groups['Body'].Value -split '\r?\n')) {
        if ($Line -match '^\s*-\s+dependency-name:\s*(?<Value>.+?)\s*$') {
            $Current = @{
                Name           = $Matches.Value.Trim('''"')
                Version        = $null
                DependencyType = $null
                UpdateType     = $null
                Group          = $null
            }
            $Dependencies.Add($Current)
            continue
        }
        if ($null -eq $Current -or $Line -notmatch '^\s+(?<Key>[a-z-]+):\s*(?<Value>.+?)\s*$') {
            continue
        }
        $Value = $Matches.Value.Trim('''"')
        switch ($Matches.Key) {
            'dependency-version' { $Current.Version = $Value }
            'dependency-type' { $Current.DependencyType = $Value }
            'update-type' { $Current.UpdateType = $Value }
            'dependency-group' { $Current.Group = $Value }
        }
    }

    foreach ($Dependency in $Dependencies) {
        if ([string]::IsNullOrEmpty($Dependency.Version)) {
            $Name = [regex]::Escape($Dependency.Name)
            $Line = [regex]::Match($Message, ('(?m)^Updates `{0}` (?:from \S+ )?to (?<To>\S+?)\.?\s*$' -f $Name))
            if (-not $Line.Success) {
                $Line = [regex]::Match($Message, ('(?m)^Bumps \[?{0}\]?(?:\([^)]*\))? from \S+ to (?<To>\S+?)\.\s*$' -f $Name))
            }
            if ($Line.Success) {
                $Dependency.Version = $Line.Groups['To'].Value
            }
        }
        [PSCustomObject]$Dependency
    }
}

function Get-DepsDevScorecard {
    <#
    .SYNOPSIS
        The OpenSSF Scorecard deps.dev holds for a project key such as github.com/actions/checkout,
        or $null when it has none.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectKey
    )

    foreach ($Candidate in @($ProjectKey, $ProjectKey.ToLowerInvariant()) | Select-Object -Unique) {
        $Response = Invoke-AutoMergeApi -Uri ('https://api.deps.dev/v3/projects/{0}' -f [uri]::EscapeDataString($Candidate))
        if ($Response.StatusCode -eq 200 -and $null -ne $Response.Content.scorecard) {
            return $Response.Content.scorecard
        }
    }
    return $null
}

function Get-GitHubActionRelease {
    <#
    .SYNOPSIS
        The published GitHub release behind an action version, or $null. Dependabot reports the
        version without a leading v for most actions, while the tag usually has one, so both
        spellings are tried.
    .DESCRIPTION
        published_at is set by GitHub when the release is published, so unlike a commit or tagger
        date it cannot be backdated by whoever pushes the tag.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $Tags = if ($Version -like 'v*') { @($Version, $Version.Substring(1)) } else { @("v$Version", $Version) }
    foreach ($Tag in $Tags) {
        $Response = Invoke-AutoMergeApi -Uri ('https://api.github.com/repos/{0}/releases/tags/{1}' -f $Repository, [uri]::EscapeDataString($Tag))
        if ($Response.StatusCode -eq 200 -and -not $Response.Content.draft) {
            return [PSCustomObject]@{
                Tag         = $Tag
                PublishedAt = ConvertTo-UtcDate -Value $Response.Content.published_at
                Prerelease  = [bool]$Response.Content.prerelease
            }
        }
    }
    return $null
}

function Test-ScorecardPolicy {
    <#
    .SYNOPSIS
        Why a Scorecard falls short of the Reputation policy - an empty list when it does not.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Scorecard,

        [Parameter(Mandatory = $true)]
        [string]$ProjectKey,

        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [datetime]$Now
    )

    if ($null -eq $Scorecard) {
        return @("deps.dev has no OpenSSF Scorecard for $ProjectKey")
    }

    $Reasons = [System.Collections.Generic.List[string]]::new()
    $Score = [double]$Scorecard.overallScore
    if ($Score -lt [double]$Policy.MinimumOverallScore) {
        $Reasons.Add(('Scorecard {0:0.0} for {1} is below the minimum of {2:0.0}' -f $Score, $ProjectKey, [double]$Policy.MinimumOverallScore))
    }

    $Age = ($Now - (ConvertTo-UtcDate -Value $Scorecard.date)).TotalDays
    if ($Age -gt $Policy.MaximumScorecardAgeDays) {
        $Reasons.Add(('Scorecard for {0} is {1:0} days old, more than the {2} allowed' -f $ProjectKey, $Age, $Policy.MaximumScorecardAgeDays))
    }

    foreach ($CheckName in @($Policy.MinimumCheckScore.Keys | Sort-Object)) {
        $Minimum = [int]$Policy.MinimumCheckScore[$CheckName]
        $Check = @($Scorecard.checks | Where-Object { $_.name -eq $CheckName }) | Select-Object -First 1
        if ($null -eq $Check) {
            $Reasons.Add(('Scorecard for {0} has no {1} check' -f $ProjectKey, $CheckName))
        }
        elseif ([int]$Check.score -lt $Minimum) {
            $Reasons.Add(('Scorecard check {0} for {1} is {2}, below the minimum of {3}' -f $CheckName, $ProjectKey, [int]$Check.score, $Minimum))
        }
    }
    return $Reasons.ToArray()
}

function Test-DependencyReputation {
    <#
    .SYNOPSIS
        Judges one updated dependency against the policy: update type, release age, and the OpenSSF
        Scorecard of its source repository. Eligible only when nothing fell short.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Dependency,

        [Parameter(Mandatory = $true)]
        [string]$Ecosystem,

        [Parameter(Mandatory = $true)]
        [hashtable]$Setting,

        [Parameter(Mandatory = $true)]
        [datetime]$Now
    )

    $Reasons = [System.Collections.Generic.List[string]]::new()
    $Result = [ordered]@{
        Name        = $Dependency.Name
        Version     = $Dependency.Version
        UpdateType  = $Dependency.UpdateType
        ProjectKey  = $null
        Score       = $null
        PublishedAt = $null
        Eligible    = $false
        Reasons     = $Reasons
    }

    if ($Dependency.UpdateType -notin $Setting.AllowedUpdateTypes) {
        $Reasons.Add(("update type '{0}' is not one that merges on its own" -f $Dependency.UpdateType))
        return [PSCustomObject]$Result
    }
    if ([string]::IsNullOrEmpty($Dependency.Version)) {
        $Reasons.Add('the Dependabot commit does not say which version it updates to')
        return [PSCustomObject]$Result
    }

    switch ($Ecosystem) {
        'github_actions' {
            $Segments = $Dependency.Name -split '/'
            if ($Segments.Count -lt 2) {
                $Reasons.Add(("'{0}' is not an owner/repository action reference" -f $Dependency.Name))
                break
            }
            $Repository = '{0}/{1}' -f $Segments[0], $Segments[1]
            $Result.ProjectKey = 'github.com/{0}' -f $Repository
            $Release = Get-GitHubActionRelease -Repository $Repository -Version $Dependency.Version
            if ($null -eq $Release) {
                $Reasons.Add(('{0} has no published GitHub release for {1}, so its age cannot be established' -f $Repository, $Dependency.Version))
            }
            elseif ($Release.Prerelease) {
                $Reasons.Add(('{0} {1} is a prerelease' -f $Repository, $Release.Tag))
            }
            else {
                $Result.PublishedAt = $Release.PublishedAt
            }
        }
        default {
            $Reasons.Add(("ecosystem '{0}' has no reputation source" -f $Ecosystem))
        }
    }

    if ($null -ne $Result.PublishedAt) {
        $AgeDays = ($Now - $Result.PublishedAt).TotalDays
        if ($AgeDays -lt $Setting.MinimumReleaseAgeDays) {
            $Reasons.Add(('{0} {1} was published {2:0.0} days ago, less than the {3} required' -f $Dependency.Name, $Dependency.Version, $AgeDays, $Setting.MinimumReleaseAgeDays))
        }
    }

    if (-not [string]::IsNullOrEmpty($Result.ProjectKey)) {
        $Scorecard = Get-DepsDevScorecard -ProjectKey $Result.ProjectKey
        if ($null -ne $Scorecard) {
            $Result.Score = [double]$Scorecard.overallScore
        }
        foreach ($Reason in (Test-ScorecardPolicy -Scorecard $Scorecard -ProjectKey $Result.ProjectKey -Policy $Setting.Reputation -Now $Now)) {
            $Reasons.Add($Reason)
        }
    }

    $Result.Eligible = ($Reasons.Count -eq 0)
    return [PSCustomObject]$Result
}

function Test-PullRequestProvenance {
    <#
    .SYNOPSIS
        Whether a pull request is still purely Dependabot's own work, and touches nothing outside the
        files its ecosystem may change.
    .DESCRIPTION
        GitHub attributes a commit to an account by its author e-mail, which anyone can set - so the
        account alone proves nothing. The verified signature is what ties the commit to Dependabot.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Commit,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$File,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Ecosystem,

        [Parameter(Mandatory = $true)]
        [hashtable]$Setting
    )

    $Reasons = [System.Collections.Generic.List[string]]::new()
    $EcosystemSetting = if ([string]::IsNullOrEmpty($Ecosystem)) { $null } else { $Setting.Ecosystems[$Ecosystem] }
    if ($null -eq $EcosystemSetting) {
        $Reasons.Add(("ecosystem '{0}' is not configured for auto-merge" -f $Ecosystem))
    }

    if ($Commit.Count -eq 0) {
        $Reasons.Add('the pull request has no commits')
    }
    elseif ($Commit[0].author.login -ne 'dependabot[bot]') {
        $Reasons.Add('the first commit is not Dependabot''s')
    }
    foreach ($Item in $Commit) {
        $Login = $Item.author.login
        $ShortSha = ([string]$Item.sha).Substring(0, [Math]::Min(7, ([string]$Item.sha).Length))
        if ($Login -notin $Setting.TrustedCommitAuthors) {
            $Reasons.Add(("commit {0} is authored by '{1}', not by a trusted bot" -f $ShortSha, $Login))
        }
        elseif (-not $Item.commit.verification.verified) {
            $Reasons.Add(('commit {0} by {1} has no signature GitHub verified' -f $ShortSha, $Login))
        }
    }

    if ($null -ne $EcosystemSetting) {
        foreach ($Item in $File) {
            if ($Item.status -ne 'modified') {
                $Reasons.Add(('{0} is {1}; only modified files are expected' -f $Item.filename, $Item.status))
                continue
            }
            $Allowed = @($EcosystemSetting.AllowedFiles | Where-Object { $Item.filename -match $_ }).Count -gt 0
            if (-not $Allowed) {
                $Reasons.Add(('{0} is outside the files a {1} update may change' -f $Item.filename, $Ecosystem))
            }
        }
    }

    return [PSCustomObject]@{
        Eligible = ($Reasons.Count -eq 0)
        Reasons  = $Reasons.ToArray()
    }
}

function Format-AutoMergeReport {
    <#
    .SYNOPSIS
        The markdown for the pull request comment and the job summary. Deliberately free of timestamps
        and run ids, so an unchanged evaluation produces an identical body and the comment is not
        rewritten on every run.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Evaluation
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add($Script:AutoMergeCommentMarker)
    $Lines.Add('### Dependabot auto-merge')
    $Lines.Add('')
    if ($Evaluation.Eligible) {
        $Lines.Add('**Auto-merge enabled.** PR Validation was started for this head; GitHub merges the pull request once every check the ruleset requires is green, and not before.')
    }
    else {
        $Lines.Add('**Manual review required.** This pull request does not meet the auto-merge policy; a maintainer reviews it and comments `/validate` as usual.')
    }
    $Lines.Add('')

    if (@($Evaluation.Dependencies).Count -gt 0) {
        $Lines.Add('| Dependency | Version | Update type | Source repository | Scorecard | Published | Result |')
        $Lines.Add('|---|---|---|---|---|---|---|')
        foreach ($Dependency in $Evaluation.Dependencies) {
            $Lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} |' -f
                    $Dependency.Name,
                    $Dependency.Version,
                    ($Dependency.UpdateType -replace '^version-update:', ''),
                    $(if ($Dependency.ProjectKey) { $Dependency.ProjectKey } else { '-' }),
                    $(if ($null -ne $Dependency.Score) { '{0:0.0}' -f $Dependency.Score } else { '-' }),
                    $(if ($Dependency.PublishedAt) { $Dependency.PublishedAt.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) } else { '-' }),
                    $(if ($Dependency.Eligible) { 'pass' } else { 'fail' })))
        }
        $Lines.Add('')
    }

    if (@($Evaluation.Reasons).Count -gt 0) {
        $Lines.Add('Why:')
        $Lines.Add('')
        foreach ($Reason in $Evaluation.Reasons) {
            $Lines.Add(('- {0}' -f $Reason))
        }
        $Lines.Add('')
    }

    $Lines.Add(('<sub>Evaluated head `{0}` against `build/DependabotAutoMerge.psd1`. Scorecard data: deps.dev (OpenSSF Scorecard).</sub>' -f $Evaluation.HeadSha))
    return ($Lines -join "`n")
}

function Set-AutoMergeComment {
    <#
    .SYNOPSIS
        Creates the pull request's auto-merge comment, or edits the existing one when the body
        changed. One comment per pull request, never a new one per run.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [int]$Number,

        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    $Comments = (Invoke-AutoMergeApi -Uri ('https://api.github.com/repos/{0}/issues/{1}/comments?per_page=100' -f $Repository, $Number)).Content
    $Existing = @($Comments | Where-Object { $_.user.login -eq 'github-actions[bot]' -and ([string]$_.body).StartsWith($Script:AutoMergeCommentMarker) }) | Select-Object -First 1

    if ($null -ne $Existing -and ([string]$Existing.body -replace '\r\n', "`n") -eq $Body) {
        return
    }
    if (-not $PSCmdlet.ShouldProcess(('#{0}' -f $Number), 'Write auto-merge comment')) {
        return
    }
    if ($null -ne $Existing) {
        $null = Invoke-AutoMergeApi -Method Patch -Uri ('https://api.github.com/repos/{0}/issues/comments/{1}' -f $Repository, $Existing.id) -Body @{ body = $Body }
    }
    else {
        $null = Invoke-AutoMergeApi -Method Post -Uri ('https://api.github.com/repos/{0}/issues/{1}/comments' -f $Repository, $Number) -Body @{ body = $Body }
    }
}

function Get-DependabotPullRequestEvaluation {
    <#
    .SYNOPSIS
        Reads one Dependabot pull request and judges it against the policy: provenance first, then
        every dependency's reputation. Makes no changes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$PullRequest,

        [Parameter(Mandatory = $true)]
        [hashtable]$Setting,

        [Parameter(Mandatory = $true)]
        [datetime]$Now
    )

    $Number = [int]$PullRequest.number
    $Ecosystem = Get-DependabotEcosystem -BranchName $PullRequest.head.ref
    $Commits = @((Invoke-AutoMergeApi -Uri ('https://api.github.com/repos/{0}/pulls/{1}/commits?per_page=100' -f $Repository, $Number)).Content)
    $Files = @((Invoke-AutoMergeApi -Uri ('https://api.github.com/repos/{0}/pulls/{1}/files?per_page=100' -f $Repository, $Number)).Content)

    $Reasons = [System.Collections.Generic.List[string]]::new()
    $Provenance = Test-PullRequestProvenance -Commit $Commits -File $Files -Ecosystem ([string]$Ecosystem) -Setting $Setting
    foreach ($Reason in $Provenance.Reasons) { $Reasons.Add($Reason) }

    $Dependencies = @()
    if ($Provenance.Eligible) {
        $Parsed = @(ConvertFrom-DependabotCommitMessage -Message ([string]$Commits[0].commit.message))
        if ($Parsed.Count -eq 0) {
            $Reasons.Add('the Dependabot commit carries no updated-dependencies metadata')
        }
        $Dependencies = @(foreach ($Dependency in $Parsed) {
                Test-DependencyReputation -Dependency $Dependency -Ecosystem $Ecosystem -Setting $Setting -Now $Now
            })
        foreach ($Dependency in $Dependencies) {
            foreach ($Reason in $Dependency.Reasons) {
                $Reasons.Add(('`{0}`: {1}' -f $Dependency.Name, $Reason))
            }
        }
    }

    return [PSCustomObject]@{
        Number       = $Number
        Branch       = [string]$PullRequest.head.ref
        HeadSha      = [string]$PullRequest.head.sha
        Ecosystem    = $Ecosystem
        Eligible     = ($Reasons.Count -eq 0)
        Reasons      = $Reasons.ToArray()
        Dependencies = $Dependencies
    }
}
