# Security Policy

OmadaSqlTroubleshooter is used by identity administrators to run SQL against Omada environments, so
it handles tenant credentials, session tokens and production identity data. Security reports are
taken seriously and are handled privately.

## Supported versions

Only the most recent version published to the [PowerShell Gallery](https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter)
receives security fixes. Fixes are shipped as a new release rather than as patches to older versions.

| Version | Supported |
|---|---|
| Latest release on the PowerShell Gallery | :white_check_mark: |
| Any earlier release | :x: |

Run `Update-Module -Name OmadaSqlTroubleshooter` to move to the supported version.

## Reporting a vulnerability

**Do not open a public GitHub issue for a security problem.**

Report privately through GitHub Security Advisories:

1. Go to <https://github.com/Fortigi/OmadaSqlTroubleshooter/security/advisories/new>
2. Describe the issue and submit the draft advisory.

The report is visible only to the maintainers until an advisory is published. If GitHub is not
available to you, email `devops@fortigi.nl` with `OmadaSqlTroubleshooter security` in the subject
line.

### What to include

- The module version (`Get-Module OmadaSqlTroubleshooter -ListAvailable`) and your PowerShell version
  (`$PSVersionTable`).
- Whether the report involves the runtime-downloaded WebView2 assemblies, the saved tab state, the
  application log, or an export.
- Steps to reproduce, ideally as a minimal command sequence.
- The impact you believe the issue has.

Please redact real tokens, credentials, tenant names and query results from anything you send.

### Response expectations

| Stage | Target |
|---|---|
| Acknowledgement of your report | 3 business days |
| Initial assessment and severity classification | 10 business days |
| Fix or documented mitigation for high/critical findings | 30 calendar days after assessment |
| Public advisory | Published together with the fix release |

If a fix takes longer than these targets, you will be told why and given a revised date. Reporters
are credited in the advisory unless they ask not to be.

We ask that you give us a reasonable opportunity to ship a fix before disclosing publicly, and that
testing is limited to environments you own or are authorized to test.

## Scope

In scope:

- The PowerShell code in this repository.
- How the module stores and protects data on disk — see
  [Data stored on your machine](README.md#data-stored-on-your-machine).
- How the module downloads, verifies and loads the WebView2 assemblies.
- What the application log and exports can contain — see
  [What exports and logs can contain](README.md#what-exports-and-logs-can-contain).

Out of scope:

- The Omada product itself. Report those to [Omada](https://www.omadaidentity.com/) directly.
- [OmadaWeb.PS](https://github.com/Fortigi/OmadaWeb.PS), which handles all authentication and REST
  traffic. Report those at that project, which has its own security policy.
- Vulnerabilities in third-party components (Monaco Editor, the WebView2 SDK, the WebView2 Runtime).
  Report those to their maintainers; if this module ships an unsafe version or configuration of one,
  that part *is* in scope, so tell us as well.
- Findings that require an attacker to already have interactive access to the Windows account the
  module runs under.

## Automated security tooling

| Control | Where it is configured |
|---|---|
| Private vulnerability reporting | Repository settings — *Settings > Advanced Security > Private vulnerability reporting* |
| Secret scanning and push protection | Repository settings — *Settings > Advanced Security* |
| Dependabot version and security updates | [.github/dependabot.yml](.github/dependabot.yml) |
| Integrity verification of the runtime-downloaded assemblies | [src/DependencyLock.psd1](src/DependencyLock.psd1), see below |
| Static analysis (PSScriptAnalyzer) and Pester suites | [build/psakeBuild.ps1](build/psakeBuild.ps1), run in PR validation |

## Runtime dependency verification

The module ships no binaries. The four `Microsoft.Web.WebView2` assemblies that host the Monaco SQL
editor — `Microsoft.Web.WebView2.Core.dll`, `Microsoft.Web.WebView2.WinForms.dll`,
`Microsoft.Web.WebView2.Wpf.dll` and `WebView2Loader.dll` — are downloaded to
`%LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin` on first import and then loaded into the PowerShell
session with `[Reflection.Assembly]::LoadFrom`.

That download is the module's entire binary supply chain, so it is verified before the package is
expanded or copied into `Bin`:

- **Pinned and hash-verified.** The artefact has a pinned version, an exact download URL and an
  expected SHA-256 in [`src/DependencyLock.psd1`](src/DependencyLock.psd1), which ships with the
  module. `Invoke-DownloadFile` checks the downloaded bytes against that hash and, on a mismatch,
  **deletes the file** and aborts with an error naming the artefact, the source and both hashes.
- **Fail closed.** An artefact with no entry in the lock file is not downloaded at all. A missing or
  unreadable lock file stops every download rather than allowing an unverified one. The lock is read
  through the PowerShell language parser's `SafeGetValue()`, which evaluates constant expressions
  only, so a tampered lock file cannot itself execute code.
- **No caller-supplied URLs.** `Invoke-DownloadFile` has no `-DownloadUrl` parameter. Everything it
  fetches comes from the URL pinned in the lock, so "download this other thing instead" is not
  expressible, not merely refused.
- **Rollbacks take effect.** `Install-WebView2` writes a `WebView2.pin` stamp recording which pin the
  installed assemblies came from, and `Test-WebView2RuntimeVersion` compares the stamp against the
  lock with `-ne` rather than `-lt`. Moving the pin *backwards* — the correct response to a bad bump
  — therefore forces a verified reinstall instead of silently leaving the newer assemblies in place.
- **No version lookup over the network.** The version comes from the lock file inside the module, so
  module import performs no NuGet metadata request at all, and nothing about the loaded bytes depends
  on what a feed happens to serve on a given day.

To force a fresh, verified download — after a rollback, after an aborted integrity check, or simply
to be sure of what is on disk:

```powershell
Clear-OmadaSqlTroubleshooterCache -Scope Binaries
```

### Keeping the pin current

Pinning would be a liability if nobody noticed a pin going stale or turning vulnerable, so the pinned
package is declared as a `PackageReference` in [`build/Dependencies`](build/Dependencies). That puts
it in this repository's dependency graph, which is what makes Dependabot alerts and security-update
pull requests possible for a component that is never restored from a package manifest.

The flow after a bump — whether Dependabot proposes it or a maintainer does — is:

1. the version changes in `build/Dependencies/Dependencies.csproj`;
2. the pinned hash is refreshed on that branch, either by running
   [`.github/workflows/dependency-lock-sync.yml`](.github/workflows/dependency-lock-sync.yml) from
   the Actions tab against it, or locally with the command below. It is not automatic: workflows
   triggered by Dependabot get a read-only token, and the alternative that works around that would
   hand a write-scoped token to code from the branch being reviewed;
3. PR validation, release and nightly all run `build/Update-DependencyLock.ps1 -Check`, which fails
   while the lock file and the manifest disagree, or while the pinned hash no longer matches what the
   URL serves.

To do it by hand:

```powershell
./build/Update-DependencyLock.ps1 -Refresh   # repin version and hash from build/Dependencies
./build/Update-DependencyLock.ps1 -Check     # verify without changing anything
```

### Why the assemblies are still downloaded rather than shipped

Packaging the assemblies into the module at build time is the better end state, and it is planned:
issue [#54](https://github.com/Fortigi/OmadaSqlTroubleshooter/issues/54) Part B covers bundling them
into the published package with per-file hashes, keeping this download as the fallback. It is not in
this release because redistributing the WebView2 SDK changes Fortigi's obligations under Microsoft's
Distributable Code terms, and that review has to be completed and recorded in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) before the first bundled release.

Pinning and verifying stands on its own in the meantime: it closes the integrity hole for a few
kilobytes of text, needs no licensing decision, and is a prerequisite for bundling anyway — a
build-time fetch that is not itself verified would only move the unverified download from the user's
machine to the build agent.

Note that the **WebView2 Runtime** is a separate question and is not affected by any of this. It is a
prerequisite the user installs from Microsoft; this project neither ships nor downloads it. See
[THIRD-PARTY-NOTICES.md §3.1](THIRD-PARTY-NOTICES.md#31-microsoft-edge-webview2-runtime).
