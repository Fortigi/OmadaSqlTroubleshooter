# Contributing to OmadaSqlTroubleshooter

Thanks for helping improve the tool. This page covers the few things that are specific to this
repository: the one rule we ask every change to follow, where the tests live, and how a pull
request gets validated and merged.

## Every bug fix ships with its regression test

**A pull request that fixes a bug must also add the test that would have caught it.**

Not a test that exercises the area in general — the test that fails on the code as it was, and
passes on the code as it is. Write it first if you can; if you write it afterwards, revert your
fix once and watch the test go red, so you know it is actually testing the fix.

Why this rule and not a coverage target: the bugs this application has shipped were not in the
untested-on-paper corners, they were in seams that looked obvious — a date parsed with the current
culture, a config file that had gained a property, a cookie that was written under one name and
read under another. Each of those came back at least once. A regression test is the cheapest way
to make a fix permanent, and it is far cheaper to write while the failure is still reproducible in
front of you than six months later.

The same applies, in spirit, to a feature: land it with tests for the behaviour you are promising.

If a fix genuinely cannot be tested — it lives in code that only runs against a live tenant, or
only inside a rendered WebView2 control — say so in the pull request and explain why, rather than
leaving the reviewer to wonder. Often the answer is to extract the logic away from the UI first.
`Export-QueryResultFile` is the file-format dispatch lifted out of a `SaveFileDialog`, and
`Format-QueryResultSelection` with its `ConvertTo-SqlLiteral` / `ConvertTo-PowerShellLiteral`
helpers is the clipboard formatting lifted out of a `DataGrid` — both pulled into pure functions
precisely so they could be tested.

## Where the tests live

| Location | What it holds | When to add here |
|---|---|---|
| `tests/*.Tests.ps1` | Pester unit tests for a single function, dot-sourced straight from `src/`. | Anything that is pure logic. Most tests belong here. |
| `tests/e2e/` | The end-to-end suite: the real application, driven unattended against a fully mocked backend. | Behaviour that only appears once the real event handlers run. |
| `tests/mock/` | The mock Omada instance the E2E suite (and a manual `Launch-AppOnMock.ps1` session) runs against. | New backend responses the app needs to be driven through. |

Name a unit test file after the function it covers (`Get-UniqueQueryName.Tests.ps1`), so the build
can map a changed source file to the tests that cover it.

Two things worth knowing before you write one:

- **Do not reference `System.Windows.*` types.** CI runs the unit tests in a plain `pwsh` host
  where those assemblies do not resolve. Keep WPF on the other side of the seam.
- **Most functions start with a tracer preamble** that calls `ConvertTo-RedactedLogString`. Dot-source
  that function in your `BeforeAll` as well, or the function under test fails for an unrelated reason.

## Running the tests

```powershell
# Analyzer + unit tests + build. This is what CI runs on a pull request.
./build/build.ps1 -Task TestBuildOnly -BuildVersion '0.0.0'

# Just the unit tests
Invoke-Pester -Path ./tests -Output Detailed

# The end-to-end suite: real app, mocked backend, no tenant needed. Slow.
./build/build.ps1 -Task E2E
```

The E2E suite also runs nightly on `windows-latest` (`.github/workflows/e2e.yml`) and opens a
tracking issue if the scheduled run fails.

PSScriptAnalyzer gates the test run, so a style violation stops the build before a single test
executes. The repository's PowerShell conventions are Stroustrup braces, no aliases, full cmdlet
names in correct casing, spaces around operators, and aligned hashtable values.

## Branches

| Kind | Format |
|---|---|
| Feature | `feature/<description>` |
| Bug fix | `bugfix/<description>` |
| Hotfix | `hotfix/<description>` |
| Docs | `docs/<description>` |
| Release | `release/v<major>.<minor>.<patch>.<build>[-nightly]` |

`<description>` is lowercase, words separated by hyphens or underscores. Branch from `main`.

## Pull requests

1. Open the pull request against `main`. Describe what broke or was missing, what changed, and how
   you verified it — including the judgement calls a reviewer could reasonably have made
   differently.
2. **Validation does not start on its own.** Comment `/validate` on the pull request to run the
   analyzer, the unit tests and the build on both `pwsh` and Windows PowerShell. Post it as the
   most recent comment; a later comment cancels the run through the workflow's concurrency group.
3. Keep the branch up to date with `main` — validation refuses to run on a branch that is behind.
4. Resolve every review thread, automated ones included, before asking for a merge.

Please do not add AI-attribution trailers (`Co-Authored-By: Claude` and similar) to commits or
pull request descriptions.
