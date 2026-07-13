# Mock overrides for the E2E harness. EVERY override MUST be declared "function script:Name" so it
# lands in the module's top-level script scope and shadows the dot-sourced app function for ALL
# callers - including WPF event handlers and the completion blocks, which resolve names through the
# module script scope. A plain "function Name" would land in a child scope and NOT intercept them.

$script:E2ECalls = [System.Collections.Generic.List[object]]::new()
$script:E2EChoiceReturn = $null   # what a (mocked) reconnect dialog returns; set per scenario

# --- The single backend seam ----------------------------------------------------------------------
function script:Invoke-OmadaPSWebRequestWrapper {
    $RequestParameters = $Script:RunTimeData.RestMethodParam
    $script:E2ECalls.Add([pscustomobject]@{
            Uri      = [string]$RequestParameters.Uri
            Method   = [string]$RequestParameters.Method
            Body     = $RequestParameters.Body
            DataType = $(if ($RequestParameters.Body -is [System.Collections.IDictionary] -and $RequestParameters.Body.Contains("dataType")) { [string]$RequestParameters.Body["dataType"] } else { $null })
        })
    $Response = Resolve-E2EFixture -Uri $RequestParameters.Uri -Method $RequestParameters.Method -Body $RequestParameters.Body
    # A fixture may return a plain [Exception] to mean "the underlying REST call threw" (e.g. a failed
    # auth probe that Test-OmadaConnection must catch). An [ErrorRecord] is instead returned as-is,
    # matching the real wrapper's non-auth error contract that callers test with -is [ErrorRecord].
    if ($Response -is [System.Exception]) {
        throw $Response
    }
    return $Response
}

# --- Editor read seam: reproduce the poll-timer contract synchronously -----------------------------
# The real poll timer sets $Script:Task then invokes the completion block. Invoke-ExecuteQuery reads
# $Script:Task.Result as a JSON string. We invoke the block inline so execute is fully synchronous.
function script:Invoke-ExecuteScriptWithResultAsync {
    param(
        $ScriptToExecute,
        $OnCompletedScriptBlock
    )
    $Script:Task = [pscustomobject]@{ Status = "RanToCompletion"; Result = (Get-E2EEditorPayloadJson) }
    if ($null -ne $OnCompletedScriptBlock) {
        & $OnCompletedScriptBlock $null
    }
}

# --- Editor write seams: no-op (no rendered WebView2; nothing to assert on editor content) ---------
function script:Invoke-ExecuteScriptAsync {
    param(
        $ScriptToExecute,
        $OnCompletedScriptBlock
    )
    $Script:Task = [pscustomobject]@{ Status = "RanToCompletion"; Result = $null }
    if ($null -ne $OnCompletedScriptBlock) {
        & $OnCompletedScriptBlock $null
    }
}

function script:Push-ToEditor {
    param(
        [string]$ScriptToExecute
    )
    # swallow - the editor is not rendered in the harness
}

# --- Popup neutralizers so nothing enters a nested WPF message pump --------------------------------
function script:Open-ChoiceForm {
    param(
        $Title,
        $Message,
        $LeftButtonText = "Yes",
        $RightButtonText = "No",
        $LeftButtonReturnValue = $true,
        $RightButtonReturnValue = $false
    )
    if ($null -ne $script:E2EChoiceReturn) {
        return $script:E2EChoiceReturn
    }
    return $LeftButtonReturnValue
}

function script:Show-PopupWindow {
    param(
        $Message
    )
    return $null
}

# Suppress ALL modal log dialogs. The real Write-LogOutput pops a blocking WinForms/WPF MessageBox for
# ERROR/WARNING/FATAL (unless -SkipDialog) which would deadlock the dispatcher during an unattended
# run. This override echoes those to the console and never shows a dialog. Assertions - not dialogs -
# are how the harness detects failures.
# Records every log message (type + text) so scenarios can assert on trace output (e.g. the tab
# rename trace). Cleared per scenario via Clear-E2ELog.
$script:E2ELogMessages = [System.Collections.Generic.List[object]]::new()

function script:Write-LogOutput {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [string]$Message,
        $ErrorObject,
        [ValidateSet("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2")]
        [string]$LogType = "INFO",
        [switch]$SkipDialog
    )
    process {
        $script:E2ELogMessages.Add([PSCustomObject]@{ LogType = $LogType; Message = $Message })
        if ($LogType -in @("ERROR", "WARNING", "FATAL")) {
            "[{0}] {1}" -f $LogType, $Message | Write-Host -ForegroundColor DarkYellow
        }
    }
}

function script:Install-E2EMocks {
    # Sanity: assert the mock actually shadows the app function before any scenario runs. If this
    # fails, the script: scoping is wrong and real HTTP would fire - fail loudly instead of hanging.
    $Resolved = (Get-Command Invoke-OmadaPSWebRequestWrapper -ErrorAction Stop).ScriptBlock.ToString()
    if ($Resolved -notmatch "Resolve-E2EFixture") {
        throw "E2E mock installation failed: Invoke-OmadaPSWebRequestWrapper is not the mock (script: scoping problem)."
    }
}
