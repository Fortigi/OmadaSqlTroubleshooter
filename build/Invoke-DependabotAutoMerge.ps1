<#
.SYNOPSIS
    Decides whether one Dependabot pull request may merge on its own. Run by
    .github/workflows/dependabot-auto-merge.yml.
.DESCRIPTION
    Evaluates the pull request against build/DependabotAutoMerge.psd1, writes the verdict as one comment
    on it, and reports eligible=true|false and the evaluated head_sha as step outputs. It changes nothing
    else: starting validation and enabling auto-merge is the workflow's job.

    Needs GITHUB_TOKEN in the environment; pull-requests write for the comment.
.PARAMETER DryRun
    Evaluate and report only, without writing the comment.
.EXAMPLE
    $env:GITHUB_TOKEN = gh auth token; ./build/Invoke-DependabotAutoMerge.ps1 -Repository Fortigi/OmadaSqlTroubleshooter -PullRequestNumber 160 -DryRun
#>
[CmdletBinding()]
param(
    [string]$Repository = $env:GITHUB_REPOSITORY,

    [Parameter(Mandatory = $true)]
    [int]$PullRequestNumber,

    [string]$SettingPath = (Join-Path -Path $PSScriptRoot -ChildPath 'DependabotAutoMerge.psd1'),

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'DependabotAutoMerge.ps1')

if ([string]::IsNullOrEmpty($Repository)) {
    throw 'No repository given and GITHUB_REPOSITORY is not set.'
}

$Setting = Get-AutoMergeSetting -Path $SettingPath
$PullRequest = Invoke-AutoMergeApi -Uri ('https://api.github.com/repos/{0}/pulls/{1}' -f $Repository, $PullRequestNumber)
if ($PullRequest.StatusCode -ne 200) {
    throw ('Reading pull request #{0} failed with HTTP {1}.' -f $PullRequestNumber, $PullRequest.StatusCode)
}

$Evaluation = Get-DependabotPullRequestEvaluation -Repository $Repository -PullRequest $PullRequest.Content -Setting $Setting -Now ([datetime]::UtcNow)
$Report = Format-AutoMergeReport -Evaluation $Evaluation

$Report | Write-Host
if (-not [string]::IsNullOrEmpty($env:GITHUB_STEP_SUMMARY)) {
    $Report | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
Set-AutoMergeComment -Repository $Repository -Number $Evaluation.Number -Body $Report -WhatIf:$DryRun

if (-not [string]::IsNullOrEmpty($env:GITHUB_OUTPUT)) {
    'eligible={0}' -f $Evaluation.Eligible.ToString().ToLowerInvariant() | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    'head_sha={0}' -f $Evaluation.HeadSha | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
