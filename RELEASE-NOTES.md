# OmadaSqlTroubleshooter — Release Notes

**Release:** `vYYYY.MM.DD.N` (stamped by the release workflow)
**Since:** `v2026.06.26.4` (26 June 2026) — 32 commits, 50+ merged PRs.
PR #83 is an umbrella merge of #75–#101.

---

## Notes

### Spotlight

- **Tabbed multi-connection workspace** — up to 8 tabs (`TabCapacity`), each with its own connection, editor and results. Tabs sharing tenant + auth + credentials share one connection, so a second tab against the same tenant needs no new sign-in. Tabs persist encrypted (DPAPI) across restarts. (#31)
- **Queries no longer freeze the UI** — execution runs in a background MTA runspace with a live elapsed-time indicator, a **Cancel** button, and a 5-minute idle keep-alive so an expired session no longer surprises you 70 minutes later. Schema fetch and data-connection refresh moved off-thread too. (#83, #98, #101)
- **The editor understands your schema and your syntax** — clause- and alias-aware IntelliSense with column data types and snippets, plus client-side T-SQL parsing (ScriptDom) that squiggles syntax errors while you type, with no Omada round-trip. (#33, #74)
- **Logs are shareable by design** — credentials, tokens, cookies and result rows are redacted centrally; an exported log needs no scrubbing. (#51)
- **Verified supply chain** — every loaded binary is version-pinned and SHA-256-verified, re-checked at load time, and the WebView2 assemblies now ship inside the package. With an intact bundle, module import makes no network call. (#55, #73)

### Breaking changes

1. **OmadaWeb.PS `2026.07.09.9` minimum** (was `2025.10.9.1`), `#requires`-enforced. Run `Update-Module OmadaWeb.PS` first — the app will not start otherwise.
2. **Configuration split** into per-tab (`appConfigSchema.json`) and global (`appGlobalConfigSchema.json`) scope; open tabs live in `config\tabs.clixml`. A one-time migration runs automatically and is **one-way** — older builds will not see your tabs.
3. **`Alt` access keys reassigned** — `Alt+C` = Connect/Disconnect, `Alt+M` = Schema, `Alt+R` = Refresh, Reset has no access key. (Previously `Alt+C` and `Alt+R` were each bound twice.)
4. **Request bodies are redacted by default** — SQL text no longer appears in logs (`"C_QUERY": "String(24)"`). Tick **Show request body** or start with `-SkipBodyRedaction` to get it back.
5. **The package now contains binaries** — four `Microsoft.Web.WebView2` assemblies, +0.94 MB. x86 still uses the runtime download.
6. **First run fetches ScriptDom** (`180.102.0`, 6.63 MB installed) to `%LOCALAPPDATA%`. Egress allowlists that only permit the WebView2 URL need updating, or syntax validation is disabled with one warning.
7. **`Invoke-DownloadFile` lost `-DownloadUrl`** — artefacts are addressed by `-ArtifactId` against `DependencyLock.psd1`. Affects direct callers of the private function only.

> [!IMPORTANT]
> **Open before shipping:** `THIRD-PARTY-NOTICES.md` §1.3 still marks the WebView2 SDK redistribution review `DRAFT, NOT YET SIGNED OFF`, with a `TODO: reviewed by <name>, <date>` placeholder. Bundling those assemblies (#73) moves them from "downloaded by the user" to "redistributed by Fortigi", and issue #54 lists the review as an acceptance criterion. Either get it signed off, or revert to the pinned-and-verified runtime download — that reverts independently of every other change here.

---

## Changes

### New features

- Tabbed workspace with connection pooling, `+` button, **Duplicate Tab** / **Duplicate Tab without Query**, **Close All But This**, **Close All**, drag-reorder, unsaved-changes `*` indicator with save prompt, and unique auto-naming (`Query{#}`). (#31)
- **Cancel** button for a running query; the temporary query object is deleted synchronously on cancel. (#83)
- Live elapsed-time indicator, 100 ms refresh, rendered to tenths. (#83, #88)
- Session keep-alive while idle — `SessionKeepAliveMinutes`, default 5. Never prompts (`-NoInteractiveAuthentication`), logs at DEBUG only, skipped while a request is in flight. (#98)
- Window title mirrors the active tab: `<App> (<Version>) - <query>[*] - <data connection> - <tenant> [- No connection]`. (#83)
- Per-tab message queueing — an error raised for a background tab is held until that tab is on screen. App-level failures still surface immediately. (#94)
- Context-aware SQL IntelliSense: schema-qualified tables after `FROM`/`JOIN`; columns scoped to the referenced tables in `SELECT`/`WHERE`/`ON`/`GROUP BY`/`ORDER BY`; `alias.`, `schema.table.` and bare `table.` all resolve (including aliases defined after the cursor); data types shown in the detail field; built-in functions and snippets. Schema loads on connect and on database switch. (#33)
- Client-side T-SQL syntax validation with Monaco markers, ~400 ms debounce, plus an overrulable confirmation on execute. ~2.5 ms per parse; degrades silently to off if ScriptDom is unavailable. (#74)
- Wildcard filter on the SQL schema tree — 250 ms debounce, `Esc` clears, `Enter` applies, survives tab and data-connection switches. (#38)
- Results grid: cell, column and row selection, right-click context menu, and four clipboard shapes. (#9, #16, #22)
- **`Clear-OmadaSqlTroubleshooterCache`** (new public cmdlet) — reports and removes pinned binaries, `.pin` stamps and the WebView2 sign-in profile under `%LOCALAPPDATA%`. Supports `-ListOnly`, `-WhatIf`, `-Force`; reports assemblies locked by the running session. Configuration under `%APPDATA%` is left alone. (#55)
- **`-SkipBodyRedaction`** switch on `Invoke-OmadaSqlTroubleshooter`. (#72)
- New docs: `THIRD-PARTY-NOTICES.md` (machine-checked on every PR), `SECURITY.md`, README sections on data handling/privacy and known issues. (#49, #55)

### Improved functionality

- Log level chosen in the viewer now persists across restarts; resolution order is `-LogLevel` → persisted → schema default, and the default lives in one place instead of three contradictory hardcoded values. (#63/#68)
- Log redaction is granular — **Show request body** lifts only the body rule; headers, credentials, secure strings and cookies stay masked. Credential *user names* are deliberately kept (`PSCredential(UserName=omada\svc_sql)`); passwords never are. (#51, #72)
- Update check works again when the newest gallery package is a prerelease. (#35, #66/#67)
- The "Executing Query…" popup actually paints — it yields at `DispatcherPriority.Background` instead of sleeping on the dispatcher. (#76)
- The temporary query object is reused rather than created and deleted per execution, minimising Omada's deleted-objects pollution. (#14)
- Background execution recovers after a transient failure instead of staying disabled for the session; failure classification is conservative — an unrecognised failure retries on the UI thread and keeps using workers. (#97)
- Font icons replace 14 bundled PNGs, so the UI scales cleanly. (#16)
- Export/copy refactored into dedicated helpers (`Save-QueryResultToFile`, `Show-QueryResultGridView`, `Copy-DataGridToClipboard`, `Select-DataGridColumnCells`). (#22)
- Log window's bottom bar no longer clips the checkboxes. (#97)

### New keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+K` / `Ctrl+T` | Duplicate tab / duplicate without query |
| `Ctrl+W`, `Ctrl+F4` | Close tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab (wraps) |
| `Ctrl+C` / `Ctrl+Shift+C` | Copy selection / copy with headers |
| `Ctrl+Shift+S` / `Ctrl+Shift+P` | Copy selection as SQL / PowerShell array |

### New configuration (global scope)

| Property | Default | Purpose |
|---|---|---|
| `TabCapacity` | `8` | Maximum open tabs |
| `EnableSyntaxValidation` | `true` | Client-side T-SQL parse |
| `ValidationDebounceMilliseconds` | `400` | Delay before validating |
| `WarnOnExecuteWithErrors` | `true` | Confirm execute with syntax errors |
| `SqlParserVersion` | *(auto)* | Override the reflected `TSqlNNNParser` |
| `SessionKeepAliveMinutes` | `5` | Idle keep-alive interval |
| `SkipBodyRedaction` | `false` | Log request bodies in full |
| `LogLevel` | `WARNING` | Now actually read back on start-up |

### Removed

- Dead code: `_CTE.ps1`, `_Parse-SqlScript.ps1`, `Set-MonacoSchema.ps1`, `Initialize-ConfigSettings.ps1`, four `MainForm.Elements.*` event files, 14 PNG icons.
- `build/RetrieveDependencies.ps1`, `build/AddSrcDependencies.ps1` and `RetrieveFromNuGet` in `deploy/deploy.ps1` — a second, unverified download path that bypassed the new gate (and a dead one: it wrote to `Bin\Webview2Dlls` while the module read `Bin\win-x64`).
- The NuGet index query in `Test-WebView2RuntimeVersion` — import no longer contacts nuget.org to resolve a version.
- The `PSEdition` branch in `Install-WebView2` — unreachable; the module is PowerShell 7 only.

---

## Fixes

### Connection and tab state
- **`-NoReconnect` connected anyway.** `Get-SqlSchemaObject`'s documented "return early when not connected" guard did not exist — it checked a process-global reconnect status and a restored config value, never `$Script:ConnectionStatus`. A second silent round-trip came from an unconditional `Update-QueryList` on WebView2 navigation. Both gated. (#64/#69)
- **The UI disagreed with itself about connection state** — "Connected" next to a `Connect` button. The transport layer wrote the status bar on every successful request while the buttons followed `$Script:ConnectionStatus`. Transport-layer writes removed; `$Script:ConnectionStatus` is now the single source of truth. `Update-QueryList` no longer re-enables controls that `Set-SqlQueryFunctionState -Status $false` just disabled. (#65/#70)
- **A tenant 502 cost the session its background worker.** A returned status code proves the worker reached the tenant. (#91)
- **Pending WebView2 task state was process-global** (`$Script:Task`) rather than per-tab — a concurrency bug the moment two tabs exist. (#31)

### Editor and keyboard
- **`Home`/`End` jumped between tabs instead of moving the caret.** `TabControl.OnKeyDown` claims both keys and ignores modifiers, so `Shift+Home`, `Ctrl+End` etc. were all affected; a `TextBox` is immune because it marks the event handled, WebView2 is not. Simply marking it handled kills the caret move too (WebView2 only forwards unhandled keys), so the fix is a `TabControl` class handler plus a `handledEventsToo` handler at the window that resets `Handled` past the TabControl — both gated on a `WebView2` source. (#34)
- **`Alt+C` and `Alt+R` were each bound twice**, so they cycled focus instead of invoking. (#34)
- **Duplicate completions after reconnect** — `setSchema` accumulated instead of resetting its arrays. (#33)

### Query history
- **History failed to load entirely on a non-US culture.** `Get-Date` coerced a server-formatted string with the current culture; on `nl-NL`, `8/25/2026` is day 8 of month 25. The failure sat inside the row loop but propagated to the outer catch, so the user lost the *whole* list. Dates now parse `InvariantCulture` → `CurrentCulture`, and an unreadable date becomes `$null` plus a DEBUG line. (#95/#100)
- **Null reference when the history window was closed mid-fetch** — `Get-SqlHistory` blocks for a full round-trip and the grid was written without checking the window still existed. (#96/#100)

### Execution and diagnostics
- **Failed executes were reported repeatedly, and pipeline log output was lost** — a worker runspace cannot log, so moving the chain off-thread had silently cost most of the diagnostic value. (#87)
- **Workers could not reuse the existing session.** OmadaWeb.PS tested whether `ForceAuthentication` was *bound* rather than its value, and this app has always splatted `ForceAuthentication = $false` — so the encrypted cookie cache was never loaded, by anyone. Invisible on the UI thread; fatal on a worker, which then tried an interactive login. (#86)
- Workers never attempt sign-in, via `-NoInteractiveAuthentication` with a capability probe for older OmadaWeb.PS. (#99)
- Partially-created workers are disposed when a start fails, instead of leaking a runspace from the pool the fallback depends on. (#84)
- A worker that cannot run the request falls back to the UI thread. (#85)
- The elapsed indicator jerked — refreshed once a second but rendered with `TimeSpan`'s seven fractional digits. (#88)
- Cleanup paths no longer unwind on a terminating log call. (#83)

---

## Other

### Build and CI

- **`build.ps1` silently swallowed psake failures.** It ran psake in a child `pwsh.exe` via `Start-Process -Wait` and never checked the exit code, and `Invoke-psake` sets `$psake.build_success = $false` rather than throwing. Analyze and Test ran, but a failing rule or test **never failed the workflow step** — in release, nightly or PR validation. Tests now genuinely gate the release approval. (#17)
- **Release notes compared against the wrong baseline** — `generate_release_notes` diffed against the chronologically previous release, almost always last night's nightly. The workflow now picks the highest non-`-nightly` `v*` tag. (#18)
- **PR validation reported results against `main`.** `issue_comment` payloads carry `issue.pull_request`, not `pull_request`, so `dorny/test-reporter` fell through to `github.sha`. Every `issue_comment` run in the repo's history was listed against main. (#52)
- Nightly builds scoped to `src/**`, published to PSGallery as a prerelease before tagging, versioned `YYYY.M.D-nightly{run}` so a second same-day build is not rejected. (#21, #23, #24, #25)
- `build/PushToPsGallery.ps1` no longer selects `DependencyLock.psd1` as the module manifest; missing-folder and publish-step errors fixed. (#15, #20, #55)
- Dependabot added for NuGet and GitHub Actions; `build/Update-DependencyLock.ps1 -Check` re-derives hashes from what NuGet serves and fails CI on drift. (#55)

### Testing

- **2 test files → 84** (~938 Pester cases), plus an end-to-end suite driving the real application against a **mock Omada instance** — an admin-free `TcpListener` server replaying the exact OData, ASMX and dialog endpoints from an on-disk fixture store, with recorder, replay-shim and sanitiser tooling. Per-route latency and concurrency controls are what made the async work testable. (#50, #75)

### Known limitations

- **Issue #40 criterion 1 is not fully met.** The execute chain, schema fetch, `Remove-SqlQueryObject` and the data-connection refresh are off-thread; remaining round-trips are tracked in **#90**.
- **Issue #61 pass 2 not included** — validation is ScriptDom-only; schema/identifier resolution and `EnableSchemaValidation` still to come. The diagnostics channel was built for both passes, so the schema pass needs no editor change.
- **Issue #54 stays open** pending the redistribution review.
- **ScriptDom reports the token, not the cause** — `SELECT a, FROM dbo.Person` gives `Incorrect syntax near 'FROM'`, not the comma. Same parser as SSMS, SqlPackage and DacFx.
- **Zero rows and a failed query produce the same warning** — a limitation of the SQL Troubleshooter component in Omada Identity Suite.

### Upgrade

1. `Update-Module OmadaWeb.PS` (≥ 2026.07.09.9) **first**.
2. `Update-Module OmadaSqlTroubleshooter`.
3. Expect a one-time config migration and a single reconnect-all prompt on first start.
4. Allow the pinned ScriptDom URL (`src/DependencyLock.psd1`) through egress filters, or accept one warning and no syntax validation.
5. On an integrity abort or a pin rollback: `Clear-OmadaSqlTroubleshooterCache` and restart. Use `-ListOnly` first; a loaded assembly is locked by Windows, so close that session.

---

**Full range:** [`v2026.06.26.4...main`](https://github.com/Fortigi/OmadaSqlTroubleshooter/compare/v2026.06.26.4...main)
