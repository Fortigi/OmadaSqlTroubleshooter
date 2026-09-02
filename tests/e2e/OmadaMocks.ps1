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

# --- The background dispatch seam (issue #40) -----------------------------------------------------
# Requests now also run on worker runspaces. The shim above cannot cover those: a worker has its own
# OmadaWeb.PS and would call the REAL Invoke-OmadaRestMethod, so an unmocked background request would
# reach out to whatever tenant URL the app built.
#
# The seam is placed at Start-OmadaBackgroundRequest rather than at
# Invoke-OmadaPSWebRequestWrapperAsync deliberately. Everything ABOVE it stays real - the eligibility
# gate, the parameter preparation, the completion queue, Complete-OmadaBackgroundRequest, the error
# classification and the 50 ms poll timer - which is precisely the machinery issue #40 adds and the
# part a scenario needs to be exercising. Only the worker's contents are replaced: the fixture is
# resolved HERE, on the UI thread (Resolve-E2EFixture is a harness function and could not run in a
# worker anyway), and the worker itself just waits and hands it back.
#
# The wait is real, on a real runspace, so a scenario can genuinely observe an in-flight request:
# set $script:E2ERequestDelayMs to make a query take time.
$script:E2ERequestDelayMs = 0

function script:Start-OmadaBackgroundRequest {
    param(
        [hashtable]$Parameters,
        $TabSession,
        [scriptblock]$OnCompletedScriptBlock,
        $Context,
        [string]$Description
    )

    # Recorded in the same shape as the synchronous seam, so Get-E2ECallCount counts a background
    # request exactly as it counts an inline one and existing assertions keep working.
    $script:E2ECalls.Add([pscustomobject]@{
            Uri      = [string]$Parameters.Uri
            Method   = [string]$Parameters.Method
            Body     = $Parameters.Body
            DataType = $(if ($Parameters.Body -is [System.Collections.IDictionary] -and $Parameters.Body.Contains("dataType")) { [string]$Parameters.Body["dataType"] } else { $null })
        })

    $Payload = @{ Result = $null; ErrorRecord = $null }
    try {
        $Response = Resolve-E2EFixture -Uri $Parameters.Uri -Method $Parameters.Method -Body $Parameters.Body
        if ($Response -is [System.Exception]) {
            $Payload.ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                $Response, "E2EFixtureFailure", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
        }
        else {
            $Payload.Result = $Response
        }
    }
    catch {
        $Payload.ErrorRecord = $_
    }

    $Shell = [powershell]::Create()
    [void]$Shell.AddScript({
            param($DelayMs, $Payload)
            if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
            return $Payload
        }).AddArgument($script:E2ERequestDelayMs).AddArgument($Payload)

    $Pending = [PSCustomObject]@{
        Task                   = $Shell.BeginInvoke()
        Shell                  = $Shell
        TabSession             = $TabSession
        OnCompletedScriptBlock = $OnCompletedScriptBlock
        StartedUtc             = [DateTime]::UtcNow
        IsCancelled            = $false
        IsBackgroundRequest    = $true
        Description            = $Description
        Context                = $Context
    }
    $Script:PendingWebViewCompletions.Add($Pending)
    return $Pending
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
# The editor is not rendered, but the script string is recorded so scenarios can assert on what
# would be pushed to it (e.g. the setSchema(...) payload shape). Cleared per scenario as needed.
$script:E2EEditorScripts = [System.Collections.Generic.List[string]]::new()

function script:Invoke-ExecuteScriptAsync {
    param(
        $ScriptToExecute,
        $OnCompletedScriptBlock
    )
    $script:E2EEditorScripts.Add([string]$ScriptToExecute)
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
# Every choice dialog the app would have shown is recorded, so a scenario can assert that the
# reconnect prompt WAS shown (issue #64) as precisely as it asserts that it was not.
$script:E2EChoices = [System.Collections.Generic.List[object]]::new()

function script:Open-ChoiceForm {
    param(
        $Title,
        $Message,
        $LeftButtonText = "Yes",
        $RightButtonText = "No",
        $LeftButtonReturnValue = $true,
        $RightButtonReturnValue = $false
    )
    $script:E2EChoices.Add([PSCustomObject]@{ Title = [string]$Title; Message = [string]$Message })
    if ($null -ne $script:E2EChoiceReturn) {
        return $script:E2EChoiceReturn
    }
    return $LeftButtonReturnValue
}

$script:E2EPopupMessages = [System.Collections.Generic.List[string]]::new()

function script:Show-PopupWindow {
    param(
        $Message
    )
    # Record the message so scenarios can assert which popups were shown (e.g. the first-open
    # "Opening tab..." popup), but return $null so nothing enters a nested WPF message pump.
    $script:E2EPopupMessages.Add([string]$Message)
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
