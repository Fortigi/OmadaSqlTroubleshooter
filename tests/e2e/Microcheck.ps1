# Minimal in-process test recorder for the E2E harness. Runs on the app's single UI/dispatcher
# thread (no second Pester module load). Every function is script:-scoped so it lands in the module
# session state when dot-sourced by the automation hook.

$script:E2EResults = [System.Collections.Generic.List[object]]::new()
$script:E2ECurrentSuite = "E2E"

function script:E2ESuite {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    $script:E2ECurrentSuite = $Name
    try {
        & $Body
    }
    catch {
        # A failure while arranging a suite (outside an It) is recorded as a suite-level failure so it
        # surfaces instead of silently aborting the run.
        $script:E2EResults.Add([pscustomobject]@{ Suite = $Name; Name = "<suite setup>"; Passed = $false; Message = $_.Exception.Message })
        "[FAIL] {0} :: <suite setup> -- {1}" -f $Name, $_.Exception.Message | Write-Host -ForegroundColor Red
    }
}

function script:E2ECase {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    $Record = [pscustomobject]@{ Suite = $script:E2ECurrentSuite; Name = $Name; Passed = $true; Message = $null }
    try {
        # Per-case state that would otherwise carry over. The executing-query popup history is
        # asserted as "nothing was left open", and a case that legitimately ends with a query still
        # in flight would fail the next one.
        if (Get-Command Clear-E2EExecutePopupHistory -ErrorAction SilentlyContinue) {
            Clear-E2EExecutePopupHistory
        }

        & $Body
    }
    catch {
        $Record.Passed = $false
        $Record.Message = $_.Exception.Message
    }
    $script:E2EResults.Add($Record)

    if ($Record.Passed) {
        "[PASS] {0} :: {1}" -f $Record.Suite, $Record.Name | Write-Host -ForegroundColor Green
    }
    else {
        "[FAIL] {0} :: {1} -- {2}" -f $Record.Suite, $Record.Name, $Record.Message | Write-Host -ForegroundColor Red
    }
}

function script:E2EAssert {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function script:E2EAssertEqual {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )
    if ($Expected -ne $Actual) {
        throw ("{0} (expected '{1}', got '{2}')" -f $Message, $Expected, $Actual)
    }
}

function script:E2EAssertTrue {
    param(
        $Value,
        [string]$Message
    )
    if (-not $Value) {
        throw $Message
    }
}

function script:Write-E2EResultsFile {
    param(
        [string]$Path
    )
    $Total = $script:E2EResults.Count
    $Failures = @($script:E2EResults | Where-Object { -not $_.Passed }).Count

    $Builder = [System.Text.StringBuilder]::new()
    [void]$Builder.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$Builder.AppendLine(('<testsuites tests="{0}" failures="{1}">' -f $Total, $Failures))
    [void]$Builder.AppendLine(('  <testsuite name="OmadaSqlTroubleshooter.E2E" tests="{0}" failures="{1}">' -f $Total, $Failures))
    foreach ($Result in $script:E2EResults) {
        $CaseName = ("{0} :: {1}" -f $Result.Suite, $Result.Name)
        $SafeName = [System.Security.SecurityElement]::Escape($CaseName)
        if ($Result.Passed) {
            [void]$Builder.AppendLine(('    <testcase classname="{0}" name="{1}" />' -f [System.Security.SecurityElement]::Escape($Result.Suite), $SafeName))
        }
        else {
            $SafeMessage = [System.Security.SecurityElement]::Escape([string]$Result.Message)
            [void]$Builder.AppendLine(('    <testcase classname="{0}" name="{1}"><failure message="{2}" /></testcase>' -f [System.Security.SecurityElement]::Escape($Result.Suite), $SafeName, $SafeMessage))
        }
    }
    [void]$Builder.AppendLine('  </testsuite>')
    [void]$Builder.AppendLine('</testsuites>')

    $Builder.ToString() | Set-Content -Path $Path -Encoding UTF8
    return [pscustomobject]@{ Total = $Total; Failures = $Failures }
}
