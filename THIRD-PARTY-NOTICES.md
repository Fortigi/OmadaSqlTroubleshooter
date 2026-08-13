# Third-Party Notices

OmadaSqlTroubleshooter is published by Fortigi under the MIT License — see [LICENSE](LICENSE).

This file lists every third-party component that OmadaSqlTroubleshooter **redistributes**,
**downloads at run time**, or **requires as a prerequisite**. Each component remains licensed
under its own terms, reproduced or linked below.

Components are grouped by how they reach the end user, because that determines which
obligations apply:

| Section | How the component reaches the user | Redistributed by Fortigi? |
|---|---|---|
| [1. Redistributed components](#1-redistributed-components) | Committed to this repository and shipped inside the published module | **Yes** |
| [2. Downloaded at run time](#2-components-downloaded-at-run-time) | Fetched from the vendor's servers onto the user's machine by this module | No |
| [3. Prerequisites](#3-prerequisites-installed-by-the-user) | Installed separately by the user | No |

Last reviewed: **2026-08-13**, against commit contents of `src/`.
The inventory below is checked automatically on every pull request by
`tests/ThirdPartyNotices.Tests.ps1`, so it cannot silently drift out of date.

---

## 1. Redistributed components

The files below are committed to this repository and are copied into the published
`OmadaSqlTroubleshooter` package by `build/psakeBuild.ps1`. Their licence notices travel with
the package: `LICENSE` and this file are included in the module output.

### 1.1 Monaco Editor

| Field | Value |
|---|---|
| Component | Monaco Editor |
| Version | 0.52.0 (commit `f6dc0eb8fce67e57f6036f4769d92c1666cdf546`) |
| Publisher | Microsoft Corporation |
| Licence | MIT |
| Project | <https://github.com/microsoft/monaco-editor> |
| Licence text | <https://github.com/microsoft/monaco-editor/blob/v0.52.0/LICENSE.txt> |
| Upstream notices | <https://github.com/microsoft/monaco-editor/blob/v0.52.0/ThirdPartyNotices.txt> |
| Location in repository | `src/Monaco/min/vs/**` |
| Location in package | `Monaco/min/vs/**` |

Monaco provides the SQL query editor. The redistributed subset comprises the AMD loader
(`loader.js`), the editor core and its web worker, the `basic-languages/sql` grammar, the
JSON/HTML/CSS/TypeScript language services, and the localisation message bundles
(`nls.messages.*.js`).

The MIT licence requires the copyright notice to be preserved. It is preserved in two places:
in the header comment of each redistributed Monaco file (unmodified from upstream), and here:

```
The MIT License (MIT)

Copyright (c) 2016 - present Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### 1.2 Codicons (`codicon.ttf`)

| Field | Value |
|---|---|
| Component | Codicons — the VS Code icon font, distributed inside Monaco Editor |
| Version | As bundled with Monaco Editor 0.52.0 |
| Publisher | Microsoft Corporation |
| Licence | Icons: **CC BY 4.0** · Code: **MIT** |
| Project | <https://github.com/microsoft/vscode-codicons> |
| Licence text | Icons: <https://github.com/microsoft/vscode-codicons/blob/main/LICENSE> · Code: <https://github.com/microsoft/vscode-codicons/blob/main/LICENSE-CODE> |
| Location in repository | `src/Monaco/min/vs/base/browser/ui/codicons/codicon/codicon.ttf` |
| Location in package | `Monaco/min/vs/base/browser/ui/codicons/codicon/codicon.ttf` |

The font file supplies the editor's glyphs and is referenced from
`src/Monaco/min/vs/editor/editor.main.css`. It is listed separately from Monaco because the
icon artwork carries a different licence (CC BY 4.0) from the surrounding MIT-licensed code.

Attribution, as CC BY 4.0 requires: *Codicons* © Microsoft Corporation, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), unmodified.

---

## 2. Components downloaded at run time

These are **not** redistributed by Fortigi. Each user's machine fetches them directly from the
vendor, under the vendor's own terms, and they are stored only in that user's profile.

### 2.1 Microsoft.Web.WebView2 (WebView2 .NET SDK)

| Field | Value |
|---|---|
| Component | `Microsoft.Web.WebView2` |
| Version | The latest stable version, resolved at run time |
| Publisher | Microsoft Corporation |
| Licence | Microsoft Software License Terms, embedded in the NuGet package |
| Licence text | <https://www.nuget.org/packages/Microsoft.Web.WebView2/#license-body> |
| Project | <https://aka.ms/webview> |
| Downloaded by | `src/Lib/Functions/Private/Install-WebView2.ps1`, on module import |
| Downloaded from | `https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/<version>` |
| Version resolved via | `https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json` |
| Installed to | `%LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin\<edition>\win-x64\` (or `win-x86`) |

Four files are extracted from the package: `Microsoft.Web.WebView2.Core.dll`,
`Microsoft.Web.WebView2.WinForms.dll`, `Microsoft.Web.WebView2.Wpf.dll` and
`WebView2Loader.dll`. They host the Monaco editor inside the WPF application.

No copy of this package is committed to this repository or included in the published module.

---

## 3. Prerequisites installed by the user

### 3.1 Microsoft Edge WebView2 Runtime

| Field | Value |
|---|---|
| Component | Microsoft Edge WebView2 Runtime (Evergreen or Fixed Version) |
| Publisher | Microsoft Corporation |
| Licence | Microsoft Software License Terms, accepted by the user on download/installation |
| Obtained from | <https://developer.microsoft.com/en-us/microsoft-edge/webview2> |

**Redistribution review — conclusion (reviewed 2026-08-13):**
OmadaSqlTroubleshooter does **not** redistribute the WebView2 Runtime in either distribution
mode, so Microsoft's redistribution terms for the Runtime do not apply to this project.

- **Evergreen mode (default).** The application uses whichever Runtime is already installed on
  the machine, installed by the user or by their organisation directly from Microsoft.
- **Fixed Version mode (optional fallback).** Where the Evergreen Runtime cannot be installed,
  the user downloads the Fixed Version `.cab` **from Microsoft themselves** and extracts it to
  `%LOCALAPPDATA%\OmadaSqlTroubleshooter\bin\Webview2Runtime` — the procedure documented in the
  [README](README.md#requirements). `src/Lib/Functions/Private/Initialize-WebViewForTab.ps1`
  only *reads* that folder if the user has populated it; nothing in this project ships,
  downloads, or mirrors those binaries.

This repository contains no `.exe`, `.dll`, `.msi` or `.cab` files, which is asserted by
`tests/ThirdPartyNotices.Tests.ps1` so that a Runtime cannot be committed by accident.

Microsoft's guidance on the two modes:
<https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution>

### 3.2 OmadaWeb.PS

| Field | Value |
|---|---|
| Component | OmadaWeb.PS (version 2026.07.09.9 or higher) |
| Publisher | Fortigi |
| Licence | MIT — Copyright (c) 2024 Fortigi |
| Licence text | <https://github.com/Fortigi/OmadaWeb.PS/blob/main/LICENSE> |
| Project | <https://github.com/Fortigi/OmadaWeb.PS> |
| Installed by | The user, with `Install-Module -Name OmadaWeb.PS` |

OmadaWeb.PS handles all authentication and REST traffic to the Omada tenant. It is a required
dependency — imported by `src/OmadaSqlTroubleShooter.psm1` at load time and declared in the
`#requires` statement of `src/Lib/Functions/Public/Invoke-OmadaSqlTroubleshooter.ps1`. It is
installed from the PowerShell Gallery by the user and is not redistributed with this module.

OmadaWeb.PS downloads its own dependencies at run time — **Selenium WebDriver**
(Apache-2.0), **Newtonsoft.Json** (MIT) and **msedgedriver** (Microsoft) — none of which are
downloaded, bundled, or otherwise handled by OmadaSqlTroubleshooter. They are covered by the
third-party notices of that module.

---

## Keeping this file current

`tests/ThirdPartyNotices.Tests.ps1` runs as part of the Pester suite on every pull request and
nightly build. It fails the build when:

- the bundled Monaco version in the tree no longer matches the version recorded above;
- a path listed above no longer exists in the repository;
- a redistributable binary (`.exe`, `.dll`, `.msi`, `.cab`) is committed to the repository;
- a component listed above loses its entry in this file.

When a component is added, upgraded, or removed, update this file in the same change. Once a
machine-readable SBOM is produced for the module, generate the inventory table from it and
keep the licence texts here.

## Reporting a problem

If you believe a component is listed incorrectly, or a notice is missing, please open an issue
at <https://github.com/Fortigi/OmadaSqlTroubleshooter/issues>.
