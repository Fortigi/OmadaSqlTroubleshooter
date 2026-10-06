# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project does
not use semantic versioning: every published tag is date-versioned (for example
`v2026.09.15.91-nightly`), using the build date plus a run number rather than major.minor.patch
numbers. Entries below are grouped by the date-versioned tag they shipped in rather than by a
semantic version.

## [Unreleased]

### Changed

- The session log file now follows the application log level (#157). The log viewer, the console and
  the file filter on one and the same level and never differ: a line is written to the file exactly
  when the viewer shows it, and changing the level in the log viewer applies to the file from the next
  line on, without a restart. Lines buffered before the file opens are filtered when it opens, against
  the level the application is running at by then. This replaces the file's own log level from #121 /
  PR #124, which defaulted to `DEBUG` on the reasoning that the file should be more detailed than the
  window — it did not cover a viewer set *more* verbose than the file, which silently dropped `VERBOSE`
  and `VERBOSE2` entries from the file that the viewer was showing. The `SessionLogFileLogLevel`
  setting is retired; a configuration file that still contains it loads without error and the value is
  ignored. Redaction is unchanged: the file stays behind the same single gate as the window.

### Added

- Every database in the SQL schema window, and completion across databases (#158). The schema window
  now lists one collapsible node per data connection and loads each one's schema **the first time you
  expand it**, so opening the window still costs a single round trip no matter how many connections
  the tenant has; the wildcard filter works across the new level, and a database that has not been
  loaded matches on its own name only. In the editor, `[DatabaseA].` completes that database's
  schemas and `[DatabaseA].[Schema].` its tables — fetched in the background the first time a
  database is named, and served from the per-pool cache with no request after that. Bracketed
  identifiers are now understood by the completion parser generally, so `FROM [dbo].[Person] p`
  resolves its alias where it previously did not. The schema validation pass also checks
  `[DatabaseA].[Schema].[Table]` names once that database's schema is cached, which additionally
  restores the column diagnostics of local tables in a query that joins another database — those
  were previously suppressed for the whole query. It still never makes a request of its own, so a
  database that has not been loaded is left alone exactly as before.

- Explicit database selection inside the SQL query (#152). `SELECT * FROM [Db].[Schema].[Table]`,
  `Db.Schema.Table` and `[Db]..[Table]` now run against the named database whatever the **Data
  connection** dropdown has selected, and `USE [Db]` switches the dropdown, the status bar and the
  loaded schema and sticks for later executions. The name is resolved client-side against the data
  connection list, so nothing changes about what Omada receives: the prefix and the `USE` are
  stripped from the text that is posted, and the query stored on the data object stays the original
  text. The database is resolved **per statement**, on top of #151, so one script may span databases
  — each statement runs against its own connection with its own result grid, and a `USE` applies
  from its own statement onward. An unknown database, a single statement addressing two databases,
  and a four-part linked-server name are all rejected before any request is made. Works identically
  for selection execution, and costs a query with no prefix nothing.

### Fixed

- <kbd>Ctrl</kbd>+<kbd>C</kbd> and the other three copy shortcuts in a result grid (#166). Pressing
  them with cells or rows selected logged `You cannot call a method on a null-valued expression` and
  copied nothing, while the same copy from the context menu worked. The shortcuts re-raised the shared
  menu item's `Click` event, and they do that from inside a `.GetNewClosure()` scriptblock — which runs
  in a detached dynamic module whose scope does not include this module's `$Script:` variables, so
  every one of those menu-item variables read as `$null`. They now call `Copy-DataGridToClipboard`
  directly, exactly as each menu item's own handler does; commands resolve from a closure where
  variables do not. <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>C</kbd>,
  <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>P</kbd> and <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> were
  broken by the same cause and are fixed with it.
- The column-selection anchor is cleared when focus moves to another result grid (#166). The same
  closure-scope detachment silently swallowed the `$null` assignment that clears it, so a
  shift-click in a newly focused grid range-selected from a column in the grid just left. The clear now
  goes through `Clear-DataGridColumnSelectionAnchor`, which owns the write in the scope that owns the
  state. This one failed with no error and no log line, which is why it is called out separately.

## [Baseline] - 2026-09-16

*This changelog was introduced on this date; earlier releases are not itemised here. The
highlights below summarise the feature set as it stands at tag `v2026.09.16.93-nightly`.
Per-release history before this point is on the
[GitHub Releases page](https://github.com/Fortigi/OmadaSqlTroubleshooter/releases).*

### Highlights

- Opt-in session log file, rotated per session and split into 5 MB parts, with an on/off toggle in
  the log window.
- Supply-chain security gate for CI: cooldown period, GitHub Dependency Review, SHA-pinned actions,
  and Harden-Runner.
- Client-side SQL pre-validation covering T-SQL syntax (ScriptDom) and schema-aware, Omada
  compatibility rules.
- Background worker execution for queries, off the UI thread, with progress reporting and
  cancellation.
- Hash-verified, pinned WebView2 SDK download and bundling at build time.
- Central log-redaction layer so credentials, tokens and result data are no longer serialized into
  logs.
- Context-aware SQL auto-completion in the Monaco editor.
- Tabbed multi-connection support.
- Wildcard filter on the SQL schema tree.
- Mock Omada instance for testing without a live tenant.
- Third-party notices and privacy documentation.
- Nightly builds published to the PowerShell Gallery as pre-release packages.
- A status bar and a Messages tab in place of popups and modals; the status bar message can be
  shown in full on hover and reports what an execute did and which query it ran.
- Single-sourced tab connection state, so the UI cannot disagree with itself and a disconnected tab
  cannot be silently reconnected by the startup schema push.
- PR validation reports results against the PR head instead of main, and no longer runs a Windows
  PowerShell 5.1 leg.
- The chosen log level in the log viewer persists across restarts.

[Unreleased]: https://github.com/Fortigi/OmadaSqlTroubleshooter/compare/v2026.09.16.93-nightly...HEAD
[Baseline]: https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/v2026.09.16.93-nightly
