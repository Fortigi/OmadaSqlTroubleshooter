# Shared doubles for the close-prompt tests (one tab, and the whole application).

. (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
. (Join-Path $Script:QueryPrivatePath "Test-AdHocQuery.ps1")
. (Join-Path $Script:QueryPrivatePath "Resolve-QuerySavePrompt.ps1")
. (Join-Path $Script:QueryPrivatePath "Get-TabEditorText.ps1")
. (Join-Path $Script:QueryPrivatePath "Get-TabConnectionStatus.ps1")
. (Join-Path $Script:QueryPrivatePath "Get-QuerySavePromptMessage.ps1")

function Get-TabName { param($TabSession) return $TabSession.DisplayName }
function Open-ChoiceForm { param($Title, $Message, $LeftButtonText, $RightButtonText, $LeftButtonReturnValue, $RightButtonReturnValue, $ExtraButtonText, $ExtraButtonReturnValue) }
function Save-Query { param([switch]$NewQuery) }
function Request-NewSqlQueryName { param($TabSession, $Message) }
function Update-TabHeaderTitle { param($TabSession) }
function Sync-AdHocQueryDraft { param($TabSession) }
function Set-ActiveTabContext { param($TabSession) $Script:ActiveTabId = $TabSession.Id }
function Get-ActiveTabSession { $Script:Tabs | Where-Object { $_.Id -eq $Script:ActiveTabId } | Select-Object -First 1 }
