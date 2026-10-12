<#
.SYNOPSIS
    One reconciliation pass of Dependabot auto-merge. Run by .github/workflows/dependabot-auto-merge.yml.
.DESCRIPTION
    Evaluates every open Dependabot pull request against build/DependabotAutoMerge.psd1, writes the
    verdict as one comment per pull request, and takes the next step for the first eligible one. See
    build/DependabotAutoMerge.ps1 for why it works as a reconciler.

    Needs GITHUB_TOKEN in the environment, with contents, pull-requests and actions write.
.PARAMETER DryRun
    Evaluate and report only: no comment, no dispatch, no branch update, no merge.
.EXAMPLE
    $env:GITHUB_TOKEN = gh auth token; ./build/Invoke-DependabotAutoMerge.ps1 -Repository Fortigi/OmadaSqlTroubleshooter -DryRun
#>
[CmdletBinding()]
param(
    [string]$Repository = $env:GITHUB_REPOSITORY,

    [string]$DefaultBranch = 'main',

    [string]$SettingPath = (Join-Path -Path $PSScriptRoot -ChildPath 'DependabotAutoMerge.psd1'),

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'DependabotAutoMerge.ps1')

if ([string]::IsNullOrEmpty($Repository)) {
    throw 'No repository given and GITHUB_REPOSITORY is not set.'
}

$Setting = Get-AutoMergeSetting -Path $SettingPath
$Results = @(Invoke-DependabotAutoMerge -Repository $Repository -DefaultBranch $DefaultBranch -Setting $Setting -WhatIf:$DryRun)

$Summary = [System.Collections.Generic.List[string]]::new()
$Summary.Add('## Dependabot auto-merge')
$Summary.Add('')
if ($DryRun) {
    $Summary.Add('_Dry run: nothing was commented, dispatched, updated or merged._')
    $Summary.Add('')
}
if ($Results.Count -eq 0) {
    $Summary.Add('No open Dependabot pull requests.')
}
else {
    $Summary.Add('| Pull request | Ecosystem | Eligible | Step |')
    $Summary.Add('|---|---|---|---|')
    foreach ($Result in $Results) {
        $Step = if ($Result.Step) { '{0} - {1}' -f $Result.Step.Action, $Result.Step.Detail } else { 'manual review' }
        $Summary.Add(('| #{0} `{1}` | {2} | {3} | {4} |' -f $Result.Number, $Result.Branch, $Result.Ecosystem, $(if ($Result.Eligible) { 'yes' } else { 'no' }), $Step))
    }
    foreach ($Result in $Results | Where-Object { -not $_.Eligible }) {
        $Summary.Add('')
        $Summary.Add(('#{0}:' -f $Result.Number))
        foreach ($Reason in $Result.Reasons) {
            $Summary.Add(('- {0}' -f $Reason))
        }
    }
}

$Text = $Summary -join "`n"
$Text | Write-Host
if (-not [string]::IsNullOrEmpty($env:GITHUB_STEP_SUMMARY)) {
    $Text | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
