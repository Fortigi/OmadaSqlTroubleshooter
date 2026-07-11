# E2E automation entry point. Dot-sourced by Invoke-OmadaSqlTroubleshooter's env-gated hook once the
# window has loaded (ApplicationIdle), so this runs on the app's dispatcher thread inside the module
# session state - meaning "function script:Name" definitions in the dot-sourced files below shadow the
# real app functions for every caller.

$E2ERoot = Split-Path -Path $PSCommandPath -Parent

# Order matters: fixtures + mocks + framework + drivers, then scenarios.
. (Join-Path $E2ERoot "Microcheck.ps1")
. (Join-Path $E2ERoot "Fixtures.ps1")
. (Join-Path $E2ERoot "OmadaMocks.ps1")
. (Join-Path $E2ERoot "Drivers.ps1")

# Fail loudly if the mock is not actually shadowing the app function (script: scoping problem).
Install-E2EMocks

$ScenarioFolder = Join-Path $E2ERoot "scenarios"
foreach ($ScenarioFile in (Get-ChildItem -Path $ScenarioFolder -Filter "*.ps1" | Sort-Object Name)) {
    try {
        . $ScenarioFile.FullName
    }
    catch {
        $script:E2EResults.Add([pscustomobject]@{ Suite = $ScenarioFile.BaseName; Name = "<load>"; Passed = $false; Message = $_.Exception.Message })
        "[FAIL] {0} :: <load> -- {1}" -f $ScenarioFile.BaseName, $_.Exception.Message | Write-Host -ForegroundColor Red
    }
}

# Write the JUnit report + a sentinel the out-of-process launcher waits on.
$ResultsPath = $env:OMADASQL_E2E_RESULTS
if ([string]::IsNullOrWhiteSpace($ResultsPath)) {
    $ResultsPath = Join-Path $E2ERoot "E2EResults.xml"
}
$Summary = Write-E2EResultsFile -Path $ResultsPath
New-Item -Path ("{0}.done" -f $ResultsPath) -ItemType File -Force | Out-Null

"" | Write-Host
"E2E summary: {0} test(s), {1} failure(s)." -f $Summary.Total, $Summary.Failures | Write-Host -ForegroundColor $(if ($Summary.Failures -gt 0) { "Red" } else { "Green" })
