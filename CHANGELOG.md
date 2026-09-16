# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project does
not use semantic versioning: every published tag is date-versioned (for example
`v2026.09.15.91-nightly`), using the build date plus a run number rather than major.minor.patch
numbers. Entries below are grouped by the date-versioned tag they shipped in rather than by a
semantic version.

## [Unreleased]

## [v2026.09.16.93-nightly] - 2026-09-16

### Added

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

### Changed

- Replaced popups and modals with a status bar and a Messages tab; the status bar message can be
  shown in full on hover and reports what an execute did and which query it ran.
- Retyped "Copy as SQL/PowerShell array" and the array copy from the SQL schema/column types
  instead of sniffing rendered text.
- Single-sourced tab connection state so the UI cannot disagree with itself, and stopped the
  startup schema push from silently connecting a disconnected tab.
- Dropped the Windows PowerShell 5.1 leg from PR validation; aligned GitHub Actions workflows.
- PR validation now reports results against the PR head instead of main.
- Persisted the chosen log level in the log viewer across restarts.

### Fixed

- Fixed the update check when the newest PowerShell Gallery package is a prerelease.
- Fixed "allow pre-release" handling to use `Save-Module` instead of `Install-Module`.
- Fixed the tab strip stealing Home/End from the editor, and Alt key collisions.
- Fixed the gallery version and module info lookup.

[Unreleased]: https://github.com/Fortigi/OmadaSqlTroubleshooter/compare/v2026.09.16.93-nightly...HEAD
[v2026.09.16.93-nightly]: https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/v2026.09.16.93-nightly
