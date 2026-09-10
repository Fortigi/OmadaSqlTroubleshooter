# OmadaSqlTroubleshooter — Release Notes

**Release:** `vYYYY.MM.DD.N` (the release workflow stamps the exact build version)
**Baseline for this comparison:** `v2026.06.26.4` — the last non-prerelease release, published 26 June 2026
**Contents:** everything on `main` since that release, i.e. 32 squashed commits covering 50+ merged pull requests
(PR #83 alone is an umbrella merge of 18 individually reviewed pull requests, #75–#101).

This is the largest release the project has had. It changes the application from a single-connection
query window into a multi-session tool with a responsive UI, client-side SQL validation, and a
verified supply chain. Read the **Breaking changes** and **Upgrade notes** sections before rolling out.

---

## At a glance

| | Baseline `v2026.06.26.4` | This release |
|---|---|---|
| Concurrent connections | 1 | Up to 8 tabs (configurable), with shared connection pools |
| Query execution | Blocking — the window froze for the duration | Background runspace, live elapsed time, Cancel button |
| SQL IntelliSense | Token/dot-count guesswork | Clause- and alias-aware, schema-typed, plus snippets |
| SQL error detection | Only after a round-trip to the tenant | Client-side T-SQL parse, squiggles while typing |
| Logging | Serialized credentials, tokens and result rows | Central redaction layer, exportable by design |
| Binary dependencies | Floating version, unverified download | Pinned, SHA-256-verified, bundled in the package |
| Public cmdlets | 2 | 3 (`Clear-OmadaSqlTroubleshooterCache` added) |
| Automated tests | 2 test files | 84 Pester files (~938 cases) + an E2E suite against a mock Omada instance |

---

## Release readiness — one open item

> [!IMPORTANT]
> **The WebView2 .NET SDK redistribution review is still marked `DRAFT, NOT YET SIGNED OFF` in
> `THIRD-PARTY-NOTICES.md` §1.3.**
>
> This release bundles the four `Microsoft.Web.WebView2` assemblies into the published module
> (PR #73). That moves the component from "downloaded by the user" to "redistributed by Fortigi",
> which is a change in Fortigi's obligations. Issue #54 lists the review as an explicit acceptance
> criterion and it carries a `TODO: reviewed by <name>, <date>` placeholder.
>
> A named person at Fortigi must read the Distributable Code terms in the pinned package and record
> the conclusion **before this release ships**. Everything else in the release is independent of it;
> if the review stalls, the bundling can be reverted to the Part A behaviour (pinned and verified
> runtime download) without touching any other feature.

---

# Spotlight — the four major improvements

## 1. Tabbed multi-connection support, with shared connection pools

Issue #28 · PR #31, and refined by #34, #65/#70, #64/#69, #94, #101

The single-session layout was extracted into a per-tab `UserControl` (`MainFormTabContent.xaml`);
`MainForm.xaml` is now just a shell hosting a `TabControl`. Every tab is a fully independent
workspace: its own connection settings, query editor, results grid, and status bar.

The part that makes it genuinely usable is the **connection pool**. Tabs are grouped by
*tenant URL + authentication method + credentials*:

- When one tab in a pool connects, every tab in that pool shares the active connection — no repeated
  sign-in when you open a second tab against the same tenant.
- Disconnecting one tab disconnects only that tab; the rest of the pool stays connected.
- A new tab whose settings match no connected pool starts a pool of its own.

Under the hood this rides on OmadaWeb.PS's per-session `SessionKey` (v2026.07.09.9), so concurrent
tabs get isolated cookie and credential state. The interactive WebView2/Browser login step is
serialised behind an app-level lock, because that UI is still shared across the process.

Tab management: `+` button and **New Tab** context menu, **Duplicate Tab** (connection + query) and
**Duplicate Tab without Query** (connection only), **Close All But This**, **Close All**, drag to
reorder, an unsaved-changes `*` indicator with a save prompt on close, and auto-naming (`Query{#}`)
that is kept unique against your saved queries and pre-filled into the Display name field.

All open tabs are persisted to an encrypted Clixml store (`config\tabs.clixml`, DPAPI via
`Export-Clixml`), with a **one-time migration** from the legacy single-session configuration and a
single reconnect-all prompt on restart.

## 2. Queries execute off the UI thread — with progress and cancellation

Issue #40 (Roadmap C1) · PR #83, an umbrella merge of #75–#101

Previously, executing a query blocked the WPF dispatcher inside `Invoke-OmadaRestMethod`. The window
was frozen for the entire round-trip, and the "Executing Query…" popup could not even paint — the
`Start-Sleep -Milliseconds 100` that was supposed to give it time to appear parks the dispatcher
without pumping it, so it simply froze 100 ms longer (#76).

What ships now:

- **A background MTA runspace pool** (`Initialize-OmadaRequestPool`, `Start-OmadaBackgroundRequest`)
  with `Invoke-OmadaRequestCore` as a runspace-safe request seam.
- **The whole execute chain runs as one job** — save, temporary-object handling, the execute itself,
  and clean-up — rather than as a series of chained completions. One job means one completion, which
  removes the risk that `Set-ActiveTabContext` repoints module-scope state between steps.
- **A live elapsed-time indicator**, refreshed every 100 ms and rendered to tenths through a shared
  `Format-ElapsedTime`, so the live value and the final value cannot drift (#88).
- **A Cancel button** (`Stop-ExecuteQueryRequest`) that abandons the wait and returns the UI to a
  clean state, deleting the temporary query object synchronously.
- **Results marshalled back through the existing completion queue** — no new queue and no new timer
  were added; the existing 50 ms poll timer drains `IAsyncResult` completions unchanged.
- **The data-connection list refresh also runs off-thread** (#101). It was the worst offender:
  three dependent round-trips on the UI thread, on connect and on tab materialisation.

Measured: a dispatcher round-trip completes in under 500 ms while a 1500 ms query is in flight.
Under the old code that could not have completed at all.

Ten of the eighteen sub-PRs came from *running* it against a live tenant, and they are the difference
between "the technique works" and "the application survives a working day":

| PR | What it fixed |
|---|---|
| #84 | Partially-created workers are disposed when a start fails — otherwise each failure leaked a runspace from the pool the fallback depends on |
| #85 | Fall back to the UI thread when a worker cannot run the request |
| #86 | A worker can reuse the existing session; the start-up error dialogs are gone |
| #87 | A failed execute is reported **once**, and the pipeline's log output is back — a worker cannot log, so moving the chain off-thread had silently cost most of the diagnostic value |
| #91 | A tenant 502 no longer costs the session its background worker, and each tab gets its own popup |
| #94 | A tab's messages are held until that tab is on screen |
| #97 | Background execution can **recover** — a transient failure used to disable it for the whole session |
| #98 | The tenant session is kept alive while the application is idle |
| #99 | The worker never attempts an interactive sign-in |
| #100 | Query history loads on a non-US culture and survives its window closing |

### Session keep-alive (issue #89 · PR #98)

An Omada session cookie expires in roughly ten minutes. Measured on a live session: five successful
queries, seventy minutes idle, then the next query failed — nothing on screen had changed, and the
user found out at the worst possible moment.

A keep-alive ping now runs on a timer (`SessionKeepAliveMinutes`, default **5**). Three properties
make it safe:

- **It cannot prompt.** Every ping carries `-NoInteractiveAuthentication` (OmadaWeb.PS #85), and
  `-ForceAuthentication` is stripped — the two are mutually exclusive.
- **It is silent.** Everything logs at DEBUG; no dialog is ever raised.
- **It is skipped** while a request is in flight.

## 3. The editor knows your schema — and your syntax

**Context-aware IntelliSense** (issue #29 · PR #33) replaced the old token/dot-count completion
provider in `src/Monaco/index.html` with a clause- and alias-aware one, without a build step and
still on Monaco 0.52.0:

- `FROM` / `JOIN` positions suggest schema-qualified tables and schemas.
- `SELECT` / `WHERE` / `ON` / `GROUP BY` / `ORDER BY` suggest columns scoped to the tables actually
  referenced in the statement, with built-in functions ranked below them.
- `alias.`, `schema.table.` and bare `table.` all resolve to that table's columns — including
  aliases defined *after* the cursor.
- Column suggestions carry their **data type** in the detail field. `Get-SqlSchema` now emits
  `{n,t}` column objects instead of stripping the type.
- T-SQL built-in functions and snippets (`SELECT … FROM`, `JOIN … ON`, `CASE WHEN`, `GROUP BY`,
  `ORDER BY`).
- The schema is fetched automatically on connect and when you switch database — you no longer have
  to open the schema view first to get completions.

**Client-side T-SQL syntax validation** (issue #61, pass 1 of 2 · PR #74) adds
`Microsoft.SqlServer.TransactSql.ScriptDom` 180.102.0 as a pinned, hash-verified dependency. Parse
errors appear as Monaco markers, debounced ~400 ms after you stop typing, once on execute, and after
each schema push. Executing a query with syntax errors raises a confirmation dialog that can always
be overruled — it is never a hard block.

- Parse cost: ~2.5 ms for an eight-statement, 1.6 KB query, against a 400 ms debounce. A regression
  guard asserts < 200 ms.
- **No Omada round-trip.** The validation path reaches the WebView2 and the parser and nothing else.
- The parser version is discovered by reflection (newest `TSqlNNNParser` in the shipped assembly),
  overridable via `SqlParserVersion`.
- If ScriptDom cannot be installed, the feature degrades silently: one `WARNING`, validation off,
  no exception.

> The **schema** validation pass (identifier resolution against the cached schema) is *not* in this
> release. Issue #61 stays open.

## 4. Nothing secret reaches the log, and nothing unverified reaches the process

**Central log redaction** (issue #39 · PR #51). Verbose logging used to serialize live objects
straight into the application log — and the log window has an "Export Log File" button that users
attach to support tickets. `Invoke-OmadaPSWebRequestWrapper` dumped the whole `RestMethodParam`
splat, `Credential` included, before every REST call, and the full response after it.
`Invoke-ExecuteQuery` rendered every returned row through `Format-Table | Out-String`. Separately,
~92 functions opened by writing their full bound parameter set to `System.Diagnostics.Trace` with
AutoFlush on.

An exported log is now shareable **by design** — it never needs scrubbing, because nothing secret
enters it:

| Helper | Role |
|---|---|
| `ConvertTo-RedactedLogString` | Structure-aware walker. Masks by property name (`authorization`, `cookie`, `token`, `password`, …) and by type (`PSCredential`, `SecureString`, `byte[]`, cookie containers). Collapses arrays over 3 elements. Keeps request-body keys and value *shapes*, not values. Capped on depth, string length and circular references. |
| `Get-LogResultShape` | Renders a result set as `120 row(s) x 3 column(s) [Id, DisplayName, Email]` — never a cell value. |
| `Protect-LogMessage` | Regex safety net over already-flattened text, for secrets in exception messages and third-party output. |

`Write-LogOutput` runs `Protect-LogMessage` over the message before anything is derived from it, so
the log store, console echo, `Write-Verbose`, `Write-Error` and the message-box paths all inherit it.
The credential **user name** is deliberately kept (`PSCredential(UserName=omada\svc_sql)`) — knowing
which account hit a 401 is the first thing you need. The password never is.

**Supply-chain hardening** (issue #54 · PRs #55 and #73). Before: the module downloaded
`Microsoft.Web.WebView2` on every import, at whatever version nuget.org called newest that day, with
no checksum and no signature, straight into `[Reflection.Assembly]::LoadFrom`. A compromised feed —
or anything able to write to that user-writable directory afterwards — ran arbitrary code in the
session. And it could not start at all without egress to nuget.org.

Now:

- `src/DependencyLock.psd1` pins version, exact URL and SHA-256 for every artefact, plus a per-file
  SHA-256 for each bundled assembly.
- `Invoke-DownloadFile` is the single verification gate. It has **no** `-DownloadUrl` parameter — an
  arbitrary URL is structurally unrepresentable, not merely refused at runtime, and a test asserts
  the parameter is absent.
- On hash mismatch the file is **deleted first**, then an error names the artefact, the source and
  both hashes. A blank expected hash fails closed.
- The four WebView2 assemblies are fetched, verified and bundled **at build time** into the published
  module (+0.94 MB). With a valid bundle, module import makes **no network call at all**.
- The bundle is **re-verified at load time**, immediately before each `Add-ReflectionAssembly` — this
  closes the gap where verification happened at download and nothing re-checked a file swapped
  afterwards.
- A missing or corrupt bundle degrades silently to the `%LOCALAPPDATA%` download path.
- `WebView2.pin` / `ScriptDom.pin` stamps record which pin the installed assemblies came from, so a
  pin **rollback** forces a reinstall (a `-gt` version comparison would not have).
- Dependabot now watches both packages; `build/Update-DependencyLock.ps1 -Check` re-derives the
  hashes from what NuGet serves and fails CI on drift.

---

# New features

### Application
- **Tabbed multi-connection workspace** with connection pools, tab persistence, duplication, drag-reorder, close-all/close-others, unsaved-changes indicator and a configurable tab cap (`TabCapacity`, default 8). (#31)
- **Cancel button** for a running query. (#83/#80)
- **Live elapsed-time indicator** in the status bar while a query runs. (#83/#79, #88)
- **Session keep-alive** while the application is idle, `SessionKeepAliveMinutes` (default 5). (#98)
- **Application title mirrors the active tab** — `<App> (<Version>) - <query>[*] - <data connection> - <tenant> [- No connection]`, updated on every tab switch and header rebuild rather than only on connect/disconnect. (#83)
- **Per-tab message queueing** — a query error raised for a tab you are not looking at is held until that tab is next opened, instead of putting a modal about an invisible query in front of you. Application-level failures still surface immediately. (#94)

### Editor
- **Context-aware SQL IntelliSense** with alias resolution, clause awareness, data types, built-in functions and snippets. (#33)
- **Client-side T-SQL syntax validation** with in-editor squiggles and an overrulable execute-time confirmation. (#74)
- **Wildcard filter on the SQL schema tree** — case-insensitive substring matching wrapped in wildcards (`Object` → `*Object*`), with user-typed `*` and `?` preserved and every other character escaped. A schema-name hit reveals that schema's complete table list; columns are never filtered. 250 ms debounce, `Esc` clears, `Enter` applies immediately, and the filter survives a tab or data-connection switch. (#38)

### Results
- **Cell, column and row selection** in the results grid, with clipboard copy in four shapes: plain, with headers (`Ctrl+Shift+C`), as a SQL array (`Ctrl+Shift+S`) and as a PowerShell array (`Ctrl+Shift+P`). (#22)
- **Right-click context menu** on the results grid for quick copy, select-all and save, with entries disabled when there are no results. (#9, #16, #22)

### Keyboard shortcuts (all new since the baseline)
| Shortcut | Action |
|---|---|
| `Ctrl + Shift + K` | Duplicate the current tab (connection and query) |
| `Ctrl + T` | Duplicate the current tab without the editor contents |
| `Ctrl + W` / `Ctrl + F4` | Close the current tab |
| `Ctrl + Tab` / `Ctrl + Shift + Tab` | Next / previous tab (wraps) |
| `Ctrl + C` / `Ctrl + Shift + C` (results) | Copy selection / copy with headers |
| `Ctrl + Shift + S` / `Ctrl + Shift + P` (results) | Copy selection as a SQL / PowerShell array |

### Cmdlets and parameters
- **`Clear-OmadaSqlTroubleshooterCache`** (new public cmdlet). Reports and removes what the module caches under `%LOCALAPPDATA%\OmadaSqlTroubleshooter`: the pinned binaries and their `.pin` stamps, and the WebView2 Edge user profile (`BrowserProfiles`) that holds the sign-in cookies. Supports `-ListOnly`, `-WhatIf` and `-Force`, returns one object per artefact, and reports assemblies it could not remove because they are loaded into the running session. Configuration under `%APPDATA%` is deliberately left alone — settings are not cache. (#55)
- **`Invoke-OmadaSqlTroubleshooter -SkipBodyRedaction`** (new switch). Logs the request body — the query that was sent — instead of its shape, and starts the log viewer with **Show request body** already checked. (#72)

### Documentation
- **`THIRD-PARTY-NOTICES.md`** — a complete inventory split by distribution method (redistributed / runtime-downloaded / user-installed prerequisite), with full MIT and CC BY 4.0 texts, machine-checked on every PR by `tests/ThirdPartyNotices.Tests.ps1`. (#49)
- **`SECURITY.md`** — reporting, dependency verification, and how to keep the pins current. (#55)
- **README: "Data handling & privacy"** — no telemetry, every network destination the application contacts, local storage locations and their protection, what exports and logs can contain, and user responsibilities for exported identity data. Every claim is checkable against source, because all HTTP destinations are hard-coded. (#49)
- **README: "Known issues"** — documents that a query returning no rows and a query that fails produce the same warning, because the Omada SQL Troubleshooter component does not distinguish them.

---

# Improved features

- **Logging is opt-in-granular.** The redaction layer's body rule can be lifted — and *only* that rule — from the log viewer's **Show request body** checkbox or the `-SkipBodyRedaction` switch. Headers, credentials, secure strings, session cookies and body members named for a secret stay masked, and the setting persists across restarts. Switching it on emits one `WARNING` per session. With the option off, output is byte-for-byte what it was before the option existed (asserted with `-BeExactly`). (#72)
- **The log level chosen in the log viewer now persists** across restarts, resolved as *explicit `-LogLevel` parameter → persisted value → schema default*. A hand-edited or stale config degrades to the default instead of throwing on the start-up path, and the default now lives in one place (`appGlobalConfigSchema.json`, `WARNING`) instead of three contradictory hardcoded values. (#63/#68)
- **The log window's bottom bar no longer clips.** Log Level moved up a row; the three checkboxes fit. (#97)
- **The update check works again** when the newest gallery package is a prerelease. `Get-GalleryModuleVersion` skips `IsPrerelease` packages and anything `[version]::TryParse` rejects, and sorts on the *parsed* version rather than on `Published` (several stable entries carry a `Published` date of `1900-01-01`). A new `Compare-ModuleVersion` parses both sides with `SemanticVersion` and falls back to `[version]` for the four-part versions this module publishes; it cannot throw. (#66/#67, #35)
- **The "Executing Query…" popup actually paints**, by yielding to the dispatcher at `DispatcherPriority.Background` instead of sleeping on it. (#76)
- **The temporary query object is reused** instead of creating and deleting a new one per execution, which minimises pollution of Omada's deleted-objects list; it is now also deleted synchronously on cancel. (#14)
- **Font icons replace 14 bundled PNG images**, so the UI scales cleanly and the package carries no icon bitmaps. (#16)
- **Results export and grid view** were refactored into dedicated helpers (`Save-QueryResultToFile`, `Show-QueryResultGridView`, `Copy-DataGridToClipboard`, `Get-DataGridSelectedQueryResult`, `Select-DataGridColumnCells`), which is what made the new copy shapes and the context-menu state handling possible. (#22)
- **Background execution recovers.** `Enable-OmadaBackgroundRequest` turns background dispatch back on once a query has succeeded on the UI thread — that success is the evidence a session exists. Failure classification (`Resolve-ExecuteFallbackAction`) is deliberately conservative: an *unrecognised* failure retries on the UI thread and keeps using workers; only a status-less failure or a recognisable worker-infrastructure failure disables dispatch. (#91, #97)
- **Test coverage went from 2 test files to 84** (~938 Pester cases), plus an end-to-end suite that drives the real application against a **mock Omada instance** — an admin-free `TcpListener` HTTP server serving the exact OData, ASMX and dialog endpoints the app calls from an on-disk fixture store, with recorder, replay-shim and sanitiser tooling. It can be made slow and concurrent per route, which is what made the async work testable at all. (#50, #75)

---

# Fixes

### Connection and tab state
- **`-NoReconnect` no longer connects anyway.** A declined reconnect prompt suppressed the prompt and the auto-connect, but the tab authenticated against the tenant a moment later regardless: `Get-SqlSchemaObject` was documented as returning early when the tab is not connected, and **that guard did not exist**. It checked a process-global reconnect status, a requirements test that only verifies a URL and an auth option are filled in, and a restored config value — never `$Script:ConnectionStatus`. A second silent round-trip came from `Update-QueryList` being called unconditionally on WebView2 navigation completion. Both are now gated. (#64/#69)
- **The UI can no longer disagree with itself about the connection state.** The status bar was written by the transport layer on every successful request while the button text and dropdowns were driven by `$Script:ConnectionStatus` — hence "Connected" next to a `Connect` button. The transport-layer writes are removed; `$Script:ConnectionStatus` is the single source of truth. `Update-QueryList` no longer unconditionally re-enables the query dropdown, refresh button, "my queries" checkboxes and the schema button that `Set-SqlQueryFunctionState -Status $false` had just disabled. (#65/#70)
- **A tenant 502 no longer costs the session its background worker.** The old rule was "no step completed ⇒ the worker cannot run requests"; a status code coming back is in fact proof the worker *reached* the tenant. (#91)
- **Per-tab WebView2 task state.** `Invoke-ExecuteScriptWithResultAsync` / `Invoke-ExecuteScriptAsync` kept the pending WebView2 task in a single `$Script:Task` instead of per-tab state — a concurrency bug the moment two tabs exist. (#31)

### Editor and keyboard
- **`Home` / `End` no longer jump between tabs instead of moving the caret.** WPF's `TabControl.OnKeyDown` claims both keys for first/last-tab navigation and switches on the key alone, ignoring modifiers — so `Home`, `End`, `Shift+Home`, `Shift+End`, `Ctrl+Home` and `Ctrl+End` were all affected. A `TextBox` never triggers it because it marks the event handled; the WebView2 hosting Monaco does not. Simply marking the key handled does not work either — WebView2 only forwards a key to the web content when the routed event returns *unhandled*, so that stops the tab switch **and** kills the caret move. The fix is two halves: a `TabControl` class handler that marks the key handled before `UIElement`'s handler runs, plus a `handledEventsToo` handler at the window that resets `Handled` once the bubble is past the TabControl. Both are gated on the event originating from a `WebView2`, so `TextBox` and `DataGrid` keep normal behaviour. (#34)
- **`Alt` access-key collisions.** `Alt+C` was bound to both Schema and Connect; `Alt+R` to both Refresh and Reset. Duplicates in one scope only cycle focus instead of invoking. See **Breaking changes** for the new assignments. (#34)
- **Duplicate completions on reconnect.** `setSchema` accumulated into its suggestion arrays instead of resetting them on every call. (#33)

### Query history
- **History failed to load entirely on a non-US culture.** `Get-Date ($Row.When)` coerced a server-formatted display string using the current culture; on `nl-NL`, `8/25/2026` is day 8 of month 25. Because the conversion sat inside the row loop, the failure propagated to the outer `catch` and the user lost the **whole** history list — an error dialog and nothing to show. `ConvertTo-OmadaHistoryDate` now tries `InvariantCulture`, then `CurrentCulture`, and an unreadable date becomes `$null` plus a DEBUG line. (#95/#100)
- **Null-reference when the history window is closed during the fetch.** `Invoke-LoadSqlHistoryData` wrote into the grid without checking the window still existed, and `Get-SqlHistory` blocks for a full round-trip. (#96/#100)

### Execution and diagnostics
- **A failed execute is reported once, not repeatedly**, and the pipeline's log output is restored — a worker runspace cannot log, so moving the chain off-thread had silently cost the application most of its diagnostic value. (#87)
- **Worker runspaces reuse the existing session.** OmadaWeb.PS tested whether `ForceAuthentication` was *bound* rather than what it was set to, and this application has always splatted `ForceAuthentication = $false` — so the encrypted cookie cache was never loaded, by anyone, ever. Invisible on the UI thread (the in-memory session already held the cookie); fatal on a worker, which has its own OmadaWeb.PS instance with an empty session table and therefore attempted an interactive WebView2 login. (#86)
- **Workers never attempt sign-in**, via `-NoInteractiveAuthentication` with a capability probe for older OmadaWeb.PS versions. (#99)
- **Partially-created workers are disposed** when a start fails, instead of leaking a runspace from the pool the fallback depends on. (#84)
- **The elapsed-time indicator no longer jerks.** It was refreshed once a second but rendered with `TimeSpan`'s default format — seven fractional digits — so it showed `00:00:03.1234567`, sat frozen for a second, then jumped. Now 100 ms, tenths only, through one shared formatter. (#88)
- **Cleanup paths no longer unwind on a terminating log call**, and the error dialog says what it means. (#83)

### Build and release pipeline
- **`build.ps1` silently swallowed psake task failures.** It ran psake in a child `pwsh.exe` via `Start-Process -Wait` and never checked the exit code, and `Invoke-psake` does not throw on a failed task when called directly — it sets `$psake.build_success = $false` and returns quietly. Analyze and Test really ran, but a failing analyzer rule or failing test **never failed the workflow step**, in release, nightly or PR validation. Now the inner script exits 1 and the outer call captures it with `-PassThru` and throws — so tests genuinely gate the release approval. (#17)
- **Release notes compared against the wrong baseline.** `generate_release_notes` diffed against whatever release came before it chronologically — almost always last night's nightly — so a real release's notes showed a handful of commits instead of everything since the last stable release. The workflow now walks all `v*` tags, drops `-nightly` ones, and picks the highest remaining version. (#18)
- **PR validation reported results against `main`, not the PR head.** `PR Validation` triggers on `issue_comment`, whose payload carries `issue.pull_request` and not `pull_request`, so `dorny/test-reporter` fell through to `github.sha` — main's tip. Every `issue_comment` run in the repo's history was listed against `main`, and concurrent validations could not be told apart. (#52)
- **Nightly builds** are scoped to `src/**` changes, publish to PSGallery as a prerelease before tagging, and use a `YYYY.M.D-nightly{run}` version so a second same-day build is not rejected. (#21, #23, #24, #25)
- **Missing-folder errors during the build** and a broken PSGallery publish step are fixed; `build/PushToPsGallery.ps1` no longer picks `DependencyLock.psd1` as the module manifest. (#15, #20, #55)

---

# Breaking changes

### 1. OmadaWeb.PS minimum version: `2025.10.9.1` → `2026.07.09.9`
Enforced by `#requires` in `Invoke-OmadaSqlTroubleshooter.ps1`. The per-session `SessionKey` this
version introduces is what makes concurrent tabs possible; `-NoInteractiveAuthentication`
(OmadaWeb.PS #85) is what makes the keep-alive and the worker safety guarantees possible.
**The application will not start against an older OmadaWeb.PS.**

```powershell
Update-Module -Name OmadaWeb.PS
```

### 2. Configuration is split into tab scope and global scope
`appConfigSchema.json` now holds only per-tab properties (`BaseUrl`, `CurrentSqlQuery`,
`LastAuthentication`, `UserName`, `Password`, `EntraApplicationIdUri`, `EntraIdTenantId`,
`MyCreatedQueriesOnly`, `MyUpdatedQueriesOnly`, `SavePassword`, `IdentityUserName`,
`CurrentDataConnection`). Everything else — window positions and sizes, log settings, output folder,
`UseWebView2Auth`, `InstanceGuid` — moved to the new `appGlobalConfigSchema.json`. Open tabs are
persisted separately in `config\tabs.clixml` (DPAPI-encrypted).

A **one-time migration** from the legacy single-session configuration runs automatically. It is
one-way: after upgrading, an older build will not see your tabs.

### 3. `Alt` access keys reassigned
| Key | Before | Now |
|---|---|---|
| `Alt + C` | Schema **and** Connect (collision) | Connect / Dis**c**onnect — the same key in both states |
| `Alt + M` | — | Sche**m**a |
| `Alt + R` | Refresh **and** Reset (collision) | Refresh only |
| Reset | `Alt + R` | no access key |

### 4. The request body is redacted in logs by default
SQL query text no longer appears in the application log; a body value is logged as its type and
length (`"C_QUERY": "String(24)"`). This is intentional — an exported log is now shareable without
scrubbing. To get the query text back, tick **Show request body** in the log viewer or start with
`-SkipBodyRedaction`. The query text remains in the editor and in the SQL history window either way.

### 5. The published package now contains binaries
The four `Microsoft.Web.WebView2` assemblies (+0.94 MB) ship inside the module under
`Bin\WebView2Dlls\win-x64`. See **Release readiness** above — the redistribution review is the one
outstanding item. x86 is unaffected and still uses the runtime download.

### 6. First run downloads an additional assembly
`Microsoft.SqlServer.TransactSql.ScriptDom` 180.102.0 (20.1 MB package, 6.63 MB installed) is
fetched to `%LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin` on first use, hash-verified against the pin.
Cold install measured at 1.2 s; warm start 4 ms. If it cannot be fetched, syntax validation is
disabled with a single warning and the application runs normally — but **firewall allowlists that
only permit the WebView2 package URL will need updating** to avoid that warning.

### 7. `Invoke-DownloadFile` no longer accepts a URL
The `-DownloadUrl` parameter is gone; artefacts are addressed by `-ArtifactId` against
`DependencyLock.psd1`. This only affects anyone calling the private function directly.

---

# Removed

| Removed | Why |
|---|---|
| `src/Lib/Functions/Private/_CTE.ps1`, `_Parse-SqlScript.ps1` | Dead code, superseded by the ScriptDom parser (#74) |
| `src/Lib/Functions/Private/Set-MonacoSchema.ps1` | Dead and incompatible with the new `{n,t}` schema shape (#33) |
| `src/Lib/Functions/Private/Initialize-ConfigSettings.ps1` | Replaced by `Initialize-GlobalConfigSettings` + the tab-scope config split (#31) |
| `src/Lib/Functions/Private/Restore-MainWindowFocus.ps1` | Renamed to `Restore-MainFormFocus.ps1` to match the function it defines (#76) |
| `build/RetrieveDependencies.ps1`, `build/AddSrcDependencies.ps1`, `RetrieveFromNuGet` in `deploy/deploy.ps1` | A second, unverified download path that bypassed the new verification gate — and a dead one: it wrote to `Bin\Webview2Dlls` while the module read `Bin\win-x64`, and its `-MinimumVersion` argument landed in `$args` so the URL was built with an empty version segment, which nuget.org serves as *latest* (#55) |
| The NuGet index query in `Test-WebView2RuntimeVersion` | Module import no longer contacts nuget.org to resolve a version (#55) |
| The `$PSVersionTable.PSEdition` branch in `Install-WebView2` | ~20 unreachable lines; the module is PowerShell 7 only (#55) |
| 14 PNG icons under `src/Lib/ui/images/` | Replaced by font icons (#16) |
| Four `MainForm.Elements.*` event files and `WebView.add_NavigationCompleted.ps1` | Moved into the per-tab `MainFormTabContent` model (#31) |

---

# New and changed configuration

Global scope (`%APPDATA%\OmadaSqlTroubleshooter`, `appGlobalConfigSchema.json`):

| Property | Type | Default | Purpose |
|---|---|---|---|
| `TabCapacity` | Int | `8` | Maximum number of open tabs |
| `EnableSyntaxValidation` | Bool | `true` | Client-side T-SQL parse |
| `ValidationDebounceMilliseconds` | Int | `400` | Delay after typing stops before validating |
| `WarnOnExecuteWithErrors` | Bool | `true` | Confirm before executing a query with syntax errors |
| `SqlParserVersion` | String | *(auto)* | Override the `TSqlNNNParser` chosen by reflection |
| `SessionKeepAliveMinutes` | Int | `5` | Idle keep-alive ping interval |
| `SkipBodyRedaction` | Bool | `false` | Log request bodies in full |
| `LogLevel` | String | `WARNING` | Now actually read back on start-up |

---

# Known limitations

- **Issue #40, acceptance criterion 1 is not fully met.** The query execution path — save, temporary
  object, execute, cleanup — plus the schema fetch, `Remove-SqlQueryObject` and the data-connection
  list refresh all run off the UI thread. The criterion as written is absolute, and the remaining
  round-trips in the application are tracked in issue #90 (slices B–D).
- **Issue #61 pass 2 is not in this release.** Syntax validation is ScriptDom-only; identifier
  resolution against the cached schema, the false-positive corpus and `EnableSchemaValidation` are
  still to come. The diagnostics channel (`window.setDiagnostics`, carrying severity and source) was
  built once for both passes, so the schema pass needs no editor-side change.
- **Issue #54 stays open** pending the WebView2 SDK redistribution review.
- **ScriptDom's error position is the token, not the cause.** For `SELECT a, FROM dbo.Person` the
  parser reports `Incorrect syntax near 'FROM'` at column 11, not `Incorrect syntax near ','`. That
  is the token at which the statement became unparseable. This is asserted as the parser's actual
  behaviour, and it is the same parser SSMS, SqlPackage and DacFx use.
- **A query returning no rows and a query that fails show the same warning.** This is a limitation of
  the SQL Troubleshooter component in Omada Identity Suite, which does not distinguish the two.

---

# Upgrade notes

1. **Update OmadaWeb.PS first** — `Update-Module -Name OmadaWeb.PS` (2026.07.09.9 or higher). The
   application will not start without it.
2. **Update the module** — `Update-Module -Name OmadaSqlTroubleshooter`.
3. **Expect a one-time configuration migration** on first start, and a single reconnect-all prompt.
4. **Allow the ScriptDom package URL** through any egress filter, or accept one warning per start and
   no syntax validation. The pinned URL is in `src/DependencyLock.psd1`.
5. **If a start-up integrity check ever aborts an import**, or a pin is rolled back, run
   `Clear-OmadaSqlTroubleshooterCache` and restart — the assemblies are re-downloaded and re-verified.
   Use `-ListOnly` first to see what is stored. Note that an assembly loaded into the running
   PowerShell session is locked by Windows: close that session and run the command again.
6. **If you rely on seeing query text in the log**, tick **Show request body** in the log viewer or
   start with `-SkipBodyRedaction`. Be aware that this puts the query text into any exported log file.

---

# Appendix — merged pull requests since `v2026.06.26.4`

**Features** — #14, #16, #22, #31, #33, #34, #38, #74, #83 (umbrella: #75, #76, #77, #78, #79, #80, #81, #82, #84, #85, #86, #87, #88, #91, #94, #97, #98, #99, #100, #101)

**Fixes** — #35, #57, #67, #69, #70, #100

**Security and supply chain** — #49, #51, #55, #72, #73

**Build, CI and test infrastructure** — #15, #17, #18, #19, #20, #21, #23, #24, #25, #32, #50, #52

**Closed issues** — #28, #29, #39, #40, #63, #64, #65, #66, #89, #95, #96
**Still open, advanced by this release** — #54 (licence review), #61 (schema validation pass), #90 (remaining off-thread slices)

Full commit range: [`v2026.06.26.4...main`](https://github.com/Fortigi/OmadaSqlTroubleshooter/compare/v2026.06.26.4...main)
