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

The four `Microsoft.Web.WebView2` assemblies that host the Monaco SQL editor —
`Microsoft.Web.WebView2.Core.dll`, `Microsoft.Web.WebView2.WinForms.dll`,
`Microsoft.Web.WebView2.Wpf.dll` and `WebView2Loader.dll` — are the module's entire binary supply
chain. They are loaded into the PowerShell session with `[Reflection.Assembly]::LoadFrom`, so
whatever bytes are on disk at that moment run with the privileges of the session.

They reach the machine one of two ways, and both are verified:

- **Bundled (normal).** `build/Get-BundledDependency.ps1` fetches the pinned package during the
  build, checks its SHA-256 **before** opening it, extracts each pinned file, re-hashes every
  extracted file against its own pin, and writes the result into the package at
  `Bin\WebView2Dlls\win-x64` (0.94 MB). Importing the module then makes **no network call at all**,
  which is what lets the application start on a machine with no route to nuget.org.
- **Downloaded (fallback).** Where the bundle is missing, incomplete or fails its hash check — and on
  32-bit processes, which are not bundled — `Install-WebView2` downloads the same pinned package to
  `%LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin` and verifies it there, exactly as before.

Because the module now redistributes those assemblies rather than only downloading them, per-file
SHA-256 pins were added alongside the package pin: a package hash cannot verify a file that has been
extracted out of the package.

Whichever route the assemblies took, these properties hold:

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
- **Re-verified immediately before loading.** Verification used to happen only at download time, and
  nothing re-checked a file that was swapped afterwards — both folders the assemblies can come from
  are writable by something at some point. Each assembly is now hashed against its pinned value
  immediately before `Add-ReflectionAssembly`, once per session. A mismatch **deletes the file** and
  aborts rather than loading it; the next import re-downloads and re-verifies.
- **A broken bundle degrades, it does not break.** `Test-WebView2Bundle` never throws. A missing,
  incomplete, tampered or wrongly-versioned bundle returns "unusable" and the module falls back to
  the verified download, so a damaged install cannot stop the module from importing. It compares
  against the hashes in the lock file rather than the ones in the bundle's own stamp, since anything
  able to swap an assembly could also rewrite a stamp sitting beside it.

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

### Why the assemblies are shipped, and why the download stays

Shipping them removes the last reason the application needed egress to nuget.org to start. That was
never a theoretical problem: restricted corporate networks are the norm for Omada customers, and
`Install-WebView2` returning `$false` is a terminating error, so a machine without a route to
nuget.org could not run the application at all.

The build-time fetch is verified for the same reason the run-time one is. Bundling *without* pinning
would only move the unverified download from the user's machine to the build agent, which is why the
pin and the hash gate landed first, in
[#54](https://github.com/Fortigi/OmadaSqlTroubleshooter/issues/54) Part A.

The `%LOCALAPPDATA%` download path stays, for three reasons:

1. The module folder is typically read-only, and the bundle is used in place. Nothing is copied out
   of it, so a writable location is still needed when the bundle cannot be used.
2. A damaged or corrupted bundle has to degrade to something that works rather than bricking the
   install.
3. 32-bit processes are not bundled — the manifest declares `ProcessorArchitecture = 'Amd64'` — and
   still need the assemblies.

> **Licensing status.** Bundling moves `Microsoft.Web.WebView2` from "downloaded by the user" to
> "redistributed by Fortigi", which is a real change in Fortigi's obligations. The redistribution
> review in [THIRD-PARTY-NOTICES.md §1.3](THIRD-PARTY-NOTICES.md) is currently a **draft awaiting
> sign-off** and must be accepted by a named person at Fortigi before the first release that ships
> the bundle.

Only the SDK assemblies are bundled. The 260 MB WebView2 **Runtime** is not, and bundling it was
rejected — see the note below and
[THIRD-PARTY-NOTICES.md §3.1](THIRD-PARTY-NOTICES.md#31-microsoft-edge-webview2-runtime).

Note that the **WebView2 Runtime** is a separate question and is not affected by any of this. It is a
prerequisite the user installs from Microsoft; this project neither ships nor downloads it. See
[THIRD-PARTY-NOTICES.md §3.1](THIRD-PARTY-NOTICES.md#31-microsoft-edge-webview2-runtime).
