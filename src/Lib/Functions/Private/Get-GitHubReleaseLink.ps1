function Get-GitHubReleaseLink {
    <#
    .SYNOPSIS
        The GitHub release page of the running version, or $null when GitHub has no release for it.

    .DESCRIPTION
        A build only knows its version number (2026.11.20.160). The release pipeline publishes that
        number either as a release (tag v2026.11.20.160) or as a nightly pre-release
        (v2026.11.20.160-nightly), and a local or development build is neither - so whether a release
        exists can only be answered by GitHub. This asks it, under these rules:

          - Only for a version in the pipeline's date format (Test-GitHubReleaseVersion). "Development"
            and anything else asks nothing.
          - Only when called: by the Help menu as it opens and by the Help window. Never at start-up.
          - Both possible tags are asked at once, and the answer is waited for at most
            -TimeoutMilliseconds, so opening the menu cannot hang on a slow or blocked network.
          - The answer is kept for the session, a "no" included: a network that does not reach GitHub
            is asked once, not on every menu open.

        Nothing but the version is sent, as part of the address (api.github.com, the public releases
        API; no sign-in).

    .PARAMETER Version
        The running version.

    .PARAMETER TimeoutMilliseconds
        How long to wait for GitHub.

    .OUTPUTS
        [string] The release page, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Version = [string]$Script:RunTimeConfig.ApplicationVersion,

        [int]$TimeoutMilliseconds = 2000
    )

    if (-not (Test-GitHubReleaseVersion -Version $Version)) {
        return $null
    }

    if ($null -ne $Script:GitHubReleaseLinkCache -and $Script:GitHubReleaseLinkCache.Version -eq $Version) {
        return $Script:GitHubReleaseLinkCache.Url
    }

    $Private:Url = Invoke-GitHubReleaseLookup -Tag @(Get-GitHubReleaseTagCandidate -Version $Version) -TimeoutMilliseconds $TimeoutMilliseconds
    $Script:GitHubReleaseLinkCache = [PSCustomObject]@{ Version = $Version; Url = $Private:Url }
    "GitHub release for version {0}: {1}" -f $Version, $(if ($Private:Url) { $Private:Url } else { "none found" }) | Write-LogOutput -LogType DEBUG
    return $Private:Url
}

function Test-GitHubReleaseVersion {
    <#
    .SYNOPSIS
        Whether a version is in the release pipeline's format (yyyy.MM.dd.run, BuildVersioning.ps1),
        and so can have a GitHub release. Also what keeps anything else out of the request address.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Version
    )

    return $Version -match '^\d{4}\.\d{1,2}\.\d{1,2}\.\d+$'
}

function Get-GitHubReleaseTagCandidate {
    <#
    .SYNOPSIS
        The tags a version can have been released under: the release first, then the nightly.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    "v{0}" -f $Version
    "v{0}-nightly" -f $Version
}

function Invoke-GitHubReleaseLookup {
    <#
    .SYNOPSIS
        Asks GitHub's public releases API for each tag at once, and gives the page of the first one
        (in the order given) that has a published release.

    .DESCRIPTION
        GET https://api.github.com/repos/Fortigi/OmadaSqlTroubleshooter/releases/tags/<tag>. GitHub
        answers 404 for a tag without a release and for a draft (drafts are not public), so only a
        published release counts. GitHub's API refuses a request without a User-Agent; it is the
        product name only.

        A request that fails, or has not answered within the timeout, counts as no release.

    .PARAMETER Tag
        The tags, in order of preference.

    .PARAMETER TimeoutMilliseconds
        How long to wait for all of them.

    .PARAMETER Client
        The HTTP client; one is made (and disposed) when none is given. For the tests.

    .OUTPUTS
        [string] The release page, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Tag,

        [int]$TimeoutMilliseconds = 2000,

        $Client
    )

    $Private:OwnClient = $null -eq $Client
    if ($Private:OwnClient) {
        $Client = [System.Net.Http.HttpClient]::new()
        $Client.DefaultRequestHeaders.UserAgent.ParseAdd("OmadaSqlTroubleshooter")
        $Client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json")
    }

    try {
        $Private:Requests = @($Tag | ForEach-Object {
                $Client.GetAsync(("https://api.github.com/repos/Fortigi/OmadaSqlTroubleshooter/releases/tags/{0}" -f [System.Uri]::EscapeDataString($_)))
            })
        $null = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$Private:Requests, $TimeoutMilliseconds)

        foreach ($Private:Request in $Private:Requests) {
            if ($Private:Request.Status -ne [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                continue
            }
            $Private:Response = $Private:Request.Result
            $Private:Content = if ($Private:Response.IsSuccessStatusCode) { $Private:Response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } else { $null }
            $Private:Url = ConvertFrom-GitHubReleaseResponse -StatusCode ([int]$Private:Response.StatusCode) -Content $Private:Content
            if ($null -ne $Private:Url) {
                return $Private:Url
            }
        }
        return $null
    }
    catch {
        "Could not ask GitHub for the release: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
        return $null
    }
    finally {
        if ($Private:OwnClient) {
            $Client.Dispose()
        }
    }
}

function ConvertFrom-GitHubReleaseResponse {
    <#
    .SYNOPSIS
        The release page from GitHub's answer for one tag, or $null.

    .DESCRIPTION
        Only a 200 with a published release counts, and only a page of this repository's releases is
        returned: the address is handed to the operating system to open, so whatever else the answer
        might hold is not.

    .PARAMETER StatusCode
        The HTTP status.

    .PARAMETER Content
        The JSON body.

    .OUTPUTS
        [string] or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [int]$StatusCode,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Content
    )

    if ($StatusCode -ne 200 -or [string]::IsNullOrWhiteSpace($Content)) {
        return $null
    }

    try {
        $Private:Release = $Content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    $Private:Url = [string]$Private:Release.html_url
    if ($Private:Release.draft -eq $true -or $Private:Url -notlike "https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/*") {
        return $null
    }
    return $Private:Url
}
