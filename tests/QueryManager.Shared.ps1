# Shared set-up for the query manager's pure functions.
$Script:QmPrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
foreach ($Private:File in @(
        "ConvertTo-WildcardFilterPattern", "ConvertTo-OmadaHistoryDate", "ConvertTo-QueryManagerValue", "Get-QueryManagerColumn",
        "ConvertTo-QueryManagerTable", "Select-QueryManagerQuery", "ConvertTo-QueryHistoryEntry", "Get-QueryHistorySummary",
        "ConvertTo-QueryPropertyList", "New-QueryManagerRequest"
    )) {
    . (Join-Path $Script:QmPrivatePath "$Private:File.ps1")
}
function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType, $ErrorObject, [switch]$SkipDialog) process { } }

$Script:QmFixturePath = [System.IO.Path]::Combine($PSScriptRoot, "mock", "fixtures")
function script:Get-QmFixture { param([string]$Name) Get-Content -Path (Join-Path $Script:QmFixturePath $Name) -Raw | ConvertFrom-Json }
