[cmdletbinding()]
param(
    [string[]]$Task = 'default'
)
$ErrorActionPreference = "Stop"

if (!(Get-Module -Name Pester -ListAvailable)) { Install-Module -Name Pester -Scope CurrentUser -Confirm:$false -Force }
if (!(Get-Module -Name psake -ListAvailable)) { Install-Module -Name psake -Scope CurrentUser -Confirm:$false -Force }
if (!(Get-Module -Name PSDeploy -ListAvailable)) { Install-Module -Name PSDeploy -Scope CurrentUser -Confirm:$false -Force }

Import-Module -Name Pester -Force
Import-Module -Name psake -Force
Import-Module -Name PSDeploy -Force

Invoke-psake -buildFile "$PSScriptRoot\psakeBuild.ps1" -taskList $Task -Verbose:$VerbosePreference

