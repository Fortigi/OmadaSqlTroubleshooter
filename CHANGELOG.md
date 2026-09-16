# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project does
not use semantic versioning: every published tag is date-versioned (for example
`v2026.09.15.91-nightly`), using the build date plus a run number rather than major.minor.patch
numbers. Entries below are grouped by the date-versioned tag they shipped in rather than by a
semantic version.

## [Unreleased]

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
