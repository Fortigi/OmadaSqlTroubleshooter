# Mock Omada instance

A local, admin-free stand-in for an Omada Identity Cloud tenant. It answers the exact endpoints the
app calls — the OData `C_P_SQLTROUBLESHOOTING` service, `/dataobjdlg.aspx`, the
`SyntaxHighlighting.asmx` / `jQGridPopulationWebService.asmx` / `DataObjectWebService.asmx` web
services — from an on-disk fixture store, so you can **run, test and demo the app with no live tenant
and no credentials**. A **record mode** refreshes the fixtures from a real tenant (scrubbing PII).

This is a higher-fidelity companion to `tests/e2e/`: the e2e suite mocks the app's function seam
in-process, whereas this drives the app over **real HTTP** against a real server.

## How it fits together

```
app  ──►  Invoke-OmadaPSWebRequestWrapper  ──►  Invoke-OmadaRestMethod        (the seam)
                                                      │
                        replay: transport shim ───────┤  plain Invoke-RestMethod, no auth
                                                      ▼
                                            Start-OmadaMockServer  ──►  fixtures/  (via OmadaMockRouter)
```

The app's only network boundary is OmadaWeb.PS's `Invoke-OmadaRestMethod` (it does auth + HTTP).
In **replay** mode a `script:`-scoped shim replaces just that call with an unauthenticated HTTP
request to the mock server — everything above it (URL building, the wrapper, response parsing, the
whole UI) runs unchanged. In **record** mode the shim instead calls the *real* OmadaWeb.PS and tees
each response into the fixture store.

The shim uses `Invoke-WebRequest` and branches on the response content type — JSON is deserialized,
anything else is returned as raw text — to reproduce what OmadaWeb.PS hands back. This matters:
`Invoke-RestMethod` would deserialize the `dataobjdlg.aspx` HTML into an `[XmlDocument]`, which
stringifies to `"System.Xml.XmlDocument"` for `Get-DataConnectionOptionList`, silently yielding **no
data connections and no schema**. `Install-OmadaMockTransport.Tests.ps1` guards against that.

## Files

| File | Purpose |
|---|---|
| `fixtures/` | The example data. `routes.json` maps a route key to a fixture file + content type + status. |
| `OmadaMockRouter.ps1` | Classifies a request (`Get-OmadaMockRouteKey`) and resolves it to a fixture (`Resolve-OmadaMockResponse`). Shared by server + recorder. |
| `OmadaMockServer.ps1` | The admin-free `TcpListener` HTTP server (loop + `New-/Stop-OmadaMockServerHandle`). |
| `Start-OmadaMockServer.ps1` | Blocking CLI to run the server. |
| `Install-OmadaMockTransport.ps1` | Replay shim: `Invoke-OmadaRestMethod` → mock server. |
| `Install-OmadaMockRecorder.ps1` | Record shim: real OmadaWeb.PS → tee scrubbed fixtures. |
| `Sanitize-OmadaFixture.ps1` | PII scrubbing (tenant host, usernames, emails, optional GUIDs). |
| `MockAppEntry.ps1` | In-app entry (dot-sourced by the app hook): installs the right shim and wires the connection. |
| `Launch-AppOnMock.ps1` | One-command launcher: starts the server + app (interactive or unattended; `-Record`). |
| `*.Tests.ps1` | Pester: route classification + a live server round-trip. |

## Run the app against the mock

```powershell
# Interactive: launches the app already pointed at the mock. Just click Connect (or pass -AutoConnect).
pwsh -File tests/mock/Launch-AppOnMock.ps1 -AutoConnect
```

No login prompt, no network — the app lists the seeded queries, data connections (`OISES`), schema
and query results straight from `fixtures/`. Your real `%APPDATA%\OmadaSqlTroubleshooter` is left
untouched (the run uses a throwaway config folder).

### Just the server

```powershell
pwsh -File tests/mock/Start-OmadaMockServer.ps1 -Port 8787
# then, from anywhere:
Invoke-RestMethod http://127.0.0.1:8787/odata/dataobjects/C_P_SQLTROUBLESHOOTING
```

## Refresh the fixtures from a live tenant (record mode)

Run on a Windows machine with OmadaWeb.PS + WebView2 and access to a real tenant:

```powershell
pwsh -File tests/mock/Launch-AppOnMock.ps1 -Record
```

The app opens against your **real** tenant (normal login). Drive the flows you want captured —
connect, pick a query, execute, open the schema/history — and each response is written to
`fixtures/`, scrubbed of the tenant host, usernames and emails. Close the app, review the
`fixtures/` diff, and commit. (Pass `-FixturesDir` to capture into a scratch folder first if you
want to diff before overwriting.)

> GUIDs are kept by default (low sensitivity, useful for realistic rows). Enable
> `-ScrubGuids` on `Install-OmadaMockRecorder` if your tenant's GUIDs must not be committed.

## Run the tests

```powershell
Invoke-Pester -Path tests/mock
```

`OmadaMockRouter.Tests.ps1` is pure and fast; `OmadaMockServer.Tests.ps1` starts a real server on an
OS-assigned port and asserts every endpoint shape. Both are picked up by the psake `Test` task.

## Making a route slow

Testing "the window stays responsive during a long query" needs a request that actually takes a long
time. Two ways to get one:

```powershell
# Live, against a running handle - takes effect on the next request, no restart:
Set-OmadaMockRouteDelay -Handle $Handle -RouteKey "paging.sqldataproducer" -DelayMs 5000
Set-OmadaMockRouteDelay -Handle $Handle -RouteKey "*" -DelayMs 250   # every route
Clear-OmadaMockRouteDelay -Handle $Handle                            # remove all overrides
```

```jsonc
// Or declared per route in fixtures/routes.json, for a fixture that is inherently slow:
"paging.sqldataproducer": { "file": "...", "contentType": "...", "status": 200, "delayMs": 5000 }
```

The delay is applied in the worker just before the response is written, so the client experiences a
slow **socket** — the real `Invoke-RestMethod` path — rather than a pause faked inside a shim. A live
override wins over the manifest value. Because serving is concurrent, delaying one route does not hold
up requests to any other.

## Notes & limitations

- **Windows-only for the app** (WPF + STA + OmadaWeb.PS + WebView2); the server, router and tests are
  cross-platform.
- The server is intentionally minimal HTTP/1.1 over a raw socket, so it needs **no** `netsh http add
  urlacl` / elevation. Requests are served **concurrently** by a small pool of worker runspaces
  (`-WorkerCount`, default 4), so two slow requests genuinely overlap.
- Write operations (save/create/delete) return canned success fixtures — enough to exercise the flows,
  not a stateful database.
- Automating the README screenshot on top of this mock is a **separate, dependent** feature.
