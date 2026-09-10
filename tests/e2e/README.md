# End-to-end test suite

Launches the **real** OmadaSqlTroubleshooter application against a **fully mocked** Omada backend and
drives every scenario unattended — no manual clicking, no real server, no interactive login. It is the
"does the whole thing still work?" smoke test.

## Run it

```powershell
./build/build.ps1 -Task E2E
# or directly:
pwsh -NoProfile -File tests/e2e/Invoke-E2ESuite.ps1
```

Exit code is `0` when every scenario passes, non-zero otherwise. A JUnit report is written to
`buildoutput/E2EResults.xml`.

## How it works

- The launcher (`Invoke-E2ESuite.ps1`) starts a hidden `pwsh -STA` process that imports the module and
  runs `Invoke-OmadaSqlTroubleshooter -Reset -NoReconnect`, with three env vars set.
- Two tiny, env-gated hooks in `Invoke-OmadaSqlTroubleshooter` (inert in normal use):
  - `OMADASQL_E2E_APPDATA` → redirects the config folder to a throwaway temp dir, so the run never
    touches the real `%APPDATA%\OmadaSqlTroubleshooter` (the launcher asserts this).
  - `OMADASQL_E2E_SCRIPT` → once the window is loaded and idle, the app dot-sources `Automation.Entry.ps1`
    and then closes. A watchdog force-closes if anything hangs.
- `Automation.Entry.ps1` installs the mocks and runs the scenarios on the app's own dispatcher thread.
  Every mock is declared `function script:Name` so it shadows the real function for **all** callers,
  including WPF event handlers.
- The scenarios drive the **real** UI: they set fields on `$Script:MainForm.Elements`, `RaiseEvent`
  the real Connect/Execute/New buttons, and assert on real app state (connection status, the query and
  data-connection dropdowns, `DataGridQueryResult.ItemsSource`, the tab list, etc.).

The editor read/write seams and the synchronous backend seam (`Invoke-OmadaPSWebRequestWrapper`) are
mocked to complete inline, so most button clicks still run their whole handler chain before
`RaiseEvent` returns and need no rendered Monaco/WebView2 editor.

**Execution is the exception, and deliberately so.** Since issue #40 the query round-trip and the
schema fetch run on a background worker, so they do **not** finish inside the click that started
them. The seam for those is `Start-OmadaBackgroundRequest` (see `OmadaMocks.ps1`), placed there on
purpose: everything above it stays real — the eligibility gate, the parameter preparation, the shared
completion queue, `Complete-OmadaBackgroundRequest`, the error classification and the 50 ms poll
timer — and only the worker's contents are replaced. The fixture is resolved on the UI thread and the
worker waits `$script:E2ERequestDelayMs` before handing it back, so a scenario can create a genuinely
slow query and observe an in-flight one.

That means a scenario must **wait** rather than assert straight after the click:

| Helper | Use it for |
|---|---|
| `Invoke-E2EExecuteAndWait` | Click Execute and wait for the result to land |
| `Invoke-E2EConnectAndWait` | Connect and let the schema fetch land |
| `Invoke-E2EGetSchemaAndWait` | `Get-SqlSchemaObject` and wait |
| `Wait-E2ENoPendingRequests` | Drain everything in flight (also run by `Reset-E2ETabsToOne`) |
| `Wait-E2EUntil` | Any other condition; pumps the dispatcher and re-tests, throws on timeout |
| `Wait-E2EAppSettled` | Let the app's own start-up callbacks land; only the first scenario of a run needs it |

Asserting on the outcome of an execute without waiting tests a race, not the feature.

## Files

| File | Purpose |
|---|---|
| `Invoke-E2ESuite.ps1` | Out-of-process launcher (temp config, timeout/watchdog, JUnit parsing, exit code). |
| `Automation.Entry.ps1` | In-app entry: installs mocks, runs scenarios, writes the report + sentinel. |
| `OmadaMocks.ps1` | `script:`-scoped overrides: the REST wrapper, the editor seams, popup neutralizers, a no-dialog `Write-LogOutput`, a call recorder. |
| `Fixtures.ps1` | Response shapes routed by normalized path + method + `dataType`; tunable per scenario. |
| `Drivers.ps1` | In-process UI drivers (connect, select query, execute, tab helpers, call counter). |
| `Microcheck.ps1` | Tiny `E2ESuite`/`E2ECase`/`E2EAssert*` recorder + JUnit writer. |
| `scenarios/*.ps1` | The scenarios (Core, Tabs, Regression). |

## Coverage

Core: connect, list queries, pick data connection, select + execute + results, empty result,
connect failure (401), save-as-new (+ empty-name rejection). Tabs: Ctrl+Tab/Ctrl+Shift+Tab cycling with
wraparound, duplicate naming (with/without query), close / Close-All. Regression (bugs fixed this
session): schema cache reuse per pool+DB, new-query propagation across connected pool tabs, and
restore/auto-connect returning Connected with lists + query selected (the `ReconnectStatus=2` fix).

Purely computational fixes are covered by the unit tests under `tests/*.Tests.ps1`
(`Get-IncrementedQueryName`, `Test-ShouldConnect`, `Get-WebViewMessageString`,
`Get-DataConnectionOptionList`, `Set-ShowLogButtonEnabled`). Mouse-hit-testing and window-focus
behaviours (tab-drag header detection, reconnect-dialog focus) are not headless-reproducible and remain
manual spot-checks.

## Adding a scenario

Add an `E2ECase` inside an `E2ESuite` in a `scenarios/*.ps1` file. Arrange with the drivers / fixture
tunables (`$script:E2EQueryList`, `$script:E2EResultRows`, ...), act via `RaiseEvent`/real functions,
assert on real state. Start with `Reset-E2ETabsToOne` for a clean single, disconnected tab.

## Why local-only

Importing the module requires OmadaWeb.PS and the WebView2 runtime, and WPF needs STA + an interactive
desktop — so this suite runs locally, not in headless PR CI. The existing unit tests remain the CI gate.
