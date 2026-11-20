# Shared set-up for the ad-hoc query draft store tests: the store's functions and a Write-LogOutput
# that records instead of showing dialogs. Dot-sourced from each test file's BeforeAll.

$Script:DraftPrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
foreach ($Private:File in @(
        "Get-AdHocQueryDraftPath.ps1"
        "Get-AdHocQueryDraft.ps1"
        "Write-AdHocQueryDraftStore.ps1"
        "Save-AdHocQueryDraft.ps1"
        "Remove-AdHocQueryDraft.ps1"
        "ConvertTo-AdHocQueryDraftTabConfig.ps1"
    )) {
    . (Join-Path $Script:DraftPrivatePath $Private:File)
}

$script:DraftLog = [System.Collections.Generic.List[object]]::new()
function Write-LogOutput {
    param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType = "INFO", $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
    process { $script:DraftLog.Add([PSCustomObject]@{ Message = [string]$Message; LogType = $LogType; SkipDialog = [bool]$SkipDialog }) }
}
