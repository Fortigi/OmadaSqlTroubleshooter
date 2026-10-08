# Plan: adopting gstack in OmadaSqlTroubleshooter

Status: **proposal** — nothing below has been installed or changed yet.
Researched against gstack `main` at commit `c7edf46` (VERSION `1.91.47.0`, 2026-10-08).

## 1. What gstack is, and what it is not

[gstack](https://github.com/garrytan/gstack) (MIT, Garry Tan) is a set of Claude Code skills
(Markdown `SKILL.md` files plus Bun/TypeScript helper binaries) that give the agent role-based
workflows: plan reviews (`/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/autoplan`),
code review (`/review`), debugging (`/investigate`), release (`/ship`, `/land-and-deploy`),
security audit (`/cso`), retrospectives (`/retro`), safety rails (`/careful`, `/freeze`, `/guard`)
and a headless-Chromium browser daemon (`/browse`, `/qa`, design and benchmark skills).

It is **not** a runtime framework: nothing ships inside the module, nothing changes in `src/`.
It changes how AI-assisted development on this repository is planned, reviewed and shipped.

### Install footprint (verified from source)

| Location | Written by | Contents |
|---|---|---|
| `~/.claude/skills/gstack` + per-skill dirs in `~/.claude/skills/` | `./setup` | Skills, compiled helper binaries, Chromium build |
| `~/.claude/settings.json` | `./setup` | Hook entries, incl. a default-on timeline **Stop hook** |
| `~/.gstack/` | runtime | Config, learnings, telemetry/egress receipts, analytics |
| `<repo>/CLAUDE.md` | `gstack-team-init` | `## gstack` section (optional nudge, or "REQUIRED" block) |
| `<repo>/.claude/settings.json`, `.claude/hooks/check-gstack.sh` | `gstack-team-init required` | PreToolUse hook that **blocks** skill use when gstack is absent |
| `<repo>/.gstack`, `.gstack-worktrees` | runtime | Per-project state — must be git-ignored |

## 2. Fit assessment for this repository

This project is a Windows-only WPF/WebView2 PowerShell module with Pester tests, a psake build, a
comment-triggered (`/validate`) PR pipeline and date-based versioning. gstack is built primarily
around web apps, `package.json`/`VERSION` repos and auto-running CI. Skill-by-skill:

| Skill | Value here | Notes |
|---|---|---|
| `/office-hours`, `/spec`, `/plan-eng-review`, `/plan-ceo-review`, `/autoplan` | **High** | Fits the issue-driven feature work (#151–#169 pattern). Design docs land under `~/.gstack`, not the repo, unless we decide otherwise |
| `/review` | **High** | Diff review before `/validate`. Overlaps with Claude Code Review if that is also used — pick one as primary |
| `/investigate` | **High** | Matches CONTRIBUTING's "reproduce, regression-test, fix" rule |
| `/cso` | **Medium–High** | Tool handles identity data and auth cookies; SECURITY.md already sets a high bar. Needs a native toolchain or reports "not assessed" |
| `/test-audit` | Medium | Useful on the ~100 Pester files |
| `/careful`, `/guard`, `/freeze` | Medium | Cheap safety rails, especially `/freeze` to keep a change inside `src/Lib/Functions/` |
| `/retro`, `/learn`, `/document-release` | Medium | `/document-release` must respect the Keep-a-Changelog + date-version format |
| `/ship` | **Low without adaptation** | See conflicts C1–C4 below |
| `/land-and-deploy`, `/canary`, `/benchmark`, `/setup-deploy` | **None** | No web deploy target; releases go via `release.yml` / PSGallery |
| `/browse`, `/qa`, `/design-*`, `/scrape`, `/pair-agent`, `/connect-chrome`, `/ios-*`, `/make-pdf`, `gbrain` | **None / negative** | App UI is a WPF desktop window with an embedded WebView2; gstack's browser cannot drive it. The E2E suite (`tests/e2e/`) already covers this. Disabling them reduces attack surface and context noise |

## 3. Conflicts that must be resolved before use

| # | Conflict | Evidence | Resolution |
|---|---|---|---|
| C1 | **AI-attribution trailers.** `/ship` adds co-author trailers; CONTRIBUTING.md forbids them | `ship/SKILL.md.tmpl` §Step 13; CONTRIBUTING.md "Pull requests" | Explicit override in `CLAUDE.md`: no `Co-Authored-By` / AI trailers in commits or PR bodies |
| C2 | **Versioning.** `/ship` bumps a `VERSION` file; this repo is date-versioned by `build/BuildVersioning.ps1` (`yyyy.MM.dd.rev`) | `ship` Step 12 | No `VERSION` file → `/ship` takes its documented `NO_VERSION` path (no bump). Do **not** let it create one. State this in `CLAUDE.md` |
| C3 | **CHANGELOG.** Keep a Changelog with `## [Unreleased]`, grouped by date tag, issue refs | CHANGELOG.md header | Document in `CLAUDE.md`: entries go under `[Unreleased]`, reference the issue, never invent a version heading |
| C4 | **CI is comment-triggered.** Validation only runs after a `/validate` comment and refuses a branch behind `main` | `.github/workflows/pr-validation.yml`, CONTRIBUTING.md | `CLAUDE.md` tells `/ship` to merge `main`, open the PR, then post `/validate` as the last comment. `/land-and-deploy` stays disabled |
| C5 | **Branch naming** `feature/…`, `bugfix/…`, `hotfix/…`, `docs/…` | CONTRIBUTING.md "Branches" | Encode in `CLAUDE.md` |
| C6 | **Test command detection.** gstack reads a `## Testing` section in `CLAUDE.md` first, else auto-detects (it will not detect Pester/psake) | `ship/sections/tests.md`, `test-coverage.md` | Add `## Testing` with the exact commands (§5.2). Also add `## Test Coverage` with `Base control: off` — the coverage gate is built for JS/Python tooling |
| C7 | **Supply-chain posture.** Repo pins every Action to a SHA; gstack defaults to an hourly update check, offers `auto_upgrade`, and team mode is designed to track upstream ("no version drift") | `bin/gstack-config`; README team mode | Pin the global install to a reviewed commit, `auto_upgrade: false`, upgrade deliberately (§5.1). This is the main deviation from upstream's recommended setup — consequence: we lag upstream fixes until we upgrade |
| C8 | **Cloud sessions.** The Claude Code cloud container has Bun and Node but **no `pwsh`**, so neither gstack's test step nor any Pester run works there today | `which pwsh` empty in this session | Either a SessionStart hook / environment setup script installing PowerShell 7 (+ Pester, PSScriptAnalyzer per `build/InstallModules.ps1`) and gstack, or accept that cloud sessions can plan/review but not test. WPF/E2E tests stay Windows-only regardless |

## 4. Decisions needed from you

1. **Your primary dev OS.** gstack's `./setup` is bash; on Windows it needs Git Bash/MSYS + Node.js,
   and some features (`gstack-memorable`, paid evals) are unavailable. If you develop on Windows,
   WSL is an alternative but then Claude Code runs on the Linux side and cannot run the WPF app.
2. **Team mode `optional` vs `required`.** Recommendation: **`optional`**. `required` installs a
   PreToolUse hook that blocks every AI session (including cloud sessions and other contributors)
   when gstack is missing — disproportionate for a repo with external contributors.
3. **Telemetry.** Opt-in and off by default. Recommendation: leave **off** (`gstack-config set telemetry off`).
   Nothing about code is sent even when on, but it is unnecessary egress for an IAM tool.
4. **Where plan/design docs live.** gstack keeps them in `~/.gstack/projects/…`. Option: commit
   approved design docs to `docs/design/` so they survive and are reviewable.
5. **Skill prefix.** `./setup --prefix` (`/gstack-review`) avoids collisions with built-in Claude
   Code commands such as `/review` and `/security-review`. Recommendation: **prefix on**.

## 5. Implementation plan

### Phase 0 — Evaluate safely (≈1 hour, no repo changes)

1. Read the pinned commit's `setup`, `bin/gstack-team-init`, `SECURITY.md` and the hook it installs.
2. Install globally on your machine, pinned:
   ```bash
   git clone --single-branch https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
   cd ~/.claude/skills/gstack && git checkout <reviewed-sha> && ./setup --prefix
   gstack-config set telemetry off
   gstack-config set auto_upgrade false
   gstack-config set disabled_skills browse,qa,qa-only,design-consultation,design-shotgun,design-html,design-review,scrape,pair-agent,connect-chrome,open-gstack-browser,setup-browser-cookies,benchmark,canary,land-and-deploy,setup-deploy,ios-qa,ios-fix,ios-design-review,ios-clean,ios-sync,make-pdf,setup-gbrain,sync-gbrain,skillify
   ```
   (Verify each config key with `gstack-config` on the pinned version — names are taken from the
   current source and may change.)
3. Check `~/.claude/settings.json` afterwards and decide whether to keep the timeline Stop hook
   (`./setup --no-timeline-stop-hook` to omit it).
4. Run `gstack-paths --explain` and `gstack-egress list` to confirm where state lives and that
   nothing leaves the machine.

### Phase 1 — Give the repo a real `CLAUDE.md` (prerequisite, valuable without gstack)

The repo has no `CLAUDE.md` today. gstack reads it for test commands, coverage rules and project
conventions, so it must exist before gstack is useful. Branch `docs/claude-md`. Contents:

- **Project summary** and layout (`src/Lib/Functions/{Public,Private}`, `src/Lib/ui`, `tests/`, `build/`).
- **Rules from CONTRIBUTING.md**: regression test with every fix; no `System.Windows.*` in unit
  tests; dot-source `ConvertTo-RedactedLogString`; Stroustrup braces, no aliases, aligned hashtables;
  SHA-pinned Actions; branch names; **no AI-attribution trailers** (C1).
- **Security posture** from SECURITY.md: read-only SQL, redacted logging, no secrets in logs/tests.
- `## Testing`:
  ```
  Framework: Pester 5 + PSScriptAnalyzer (pwsh 7)
  Full (what CI runs): ./build/build.ps1 -Task TestBuildOnly -BuildVersion '0.0.0'
  Unit only:           Invoke-Pester -Path ./tests -Output Detailed
  E2E (Windows only, slow): ./build/build.ps1 -Task E2E
  ```
- `## Test Coverage`: `Base control: off`, `Star rating: off` (C6).
- `## Release` (C2–C4): no `VERSION` file, date versioning by the pipeline, CHANGELOG under
  `[Unreleased]`, post `/validate` after opening a PR, never use `/land-and-deploy`.

### Phase 2 — Wire gstack into the repo (`optional` team mode)

1. From the repo root: `~/.claude/skills/gstack/bin/gstack-team-init optional`.
   It appends a `## gstack (recommended)` section to `CLAUDE.md`; review that text, and adjust the
   install snippet to the pinned-commit procedure from Phase 0.
2. Add to `.gitignore`: `.gstack/`, `.gstack-worktrees/`, `.claude/skills/gstack/`, `.agents/skills/gstack/`,
   `.claude/settings.local.json`.
3. Add a short "AI-assisted development (optional)" section to CONTRIBUTING.md pointing at
   `CLAUDE.md`, stating gstack is optional and that the human-facing rules are unchanged.
4. PR, `/validate`, merge. No `src/` changes, so the existing pipeline is the only gate needed.

### Phase 3 — Cloud sessions (optional, only if you use claude.ai/code on this repo)

Add a SessionStart hook (`.claude/settings.json` + script) or environment setup script that:
installs PowerShell 7 and the modules from `build/InstallModules.ps1`, and clones gstack at the
pinned SHA and runs `./setup --prefix`. Requires the environment's network policy to allow
`github.com`, the PowerShell package feed and the PowerShell Gallery. Unit tests then run in the
cloud; E2E and anything WPF stays Windows-only. Skip this phase if cloud use is rare.

### Phase 4 — Pilot on real work (1–2 issues)

Pick one bug and one small feature from the open issues and run the full loop:
`/gstack-office-hours` or `/gstack-spec` → `/gstack-plan-eng-review` → implement →
`/gstack-review` → `/gstack-ship` (expect `NO_VERSION`) → `/validate`. Record per step: useful,
noise, or wrong for this repo. Run `/gstack-cso` once on `main` as a baseline audit and compare
with SECURITY.md.

### Phase 5 — Decide and tune

- Keep, trim or drop skills based on the pilot; update `disabled_skills`.
- Capture repo-specific corrections as `/gstack-learn` learnings or as `CLAUDE.md` rules (the
  latter are versioned and reviewable — preferred).
- Define the upgrade procedure: review the upstream diff between pinned SHA and the new one,
  re-run the pilot loop on a small change, then bump the pinned SHA in `CLAUDE.md`.

## 6. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Upstream churn (gstack ships multiple releases per week; skills and config keys change) | Workflows break or change behaviour silently | Pin + deliberate upgrades (C7) |
| Hooks in `~/.claude/settings.json` affect **all** repos on your machine | Unexpected behaviour elsewhere | Review hooks after setup; `--no-timeline-stop-hook` if unwanted |
| `/ship` assumptions (VERSION, auto CI, co-author) | Wrong commits/PRs | `CLAUDE.md` overrides (Phase 1); review the first PRs by hand |
| Context/token cost of large skill prompts | Slower, more expensive sessions | Disable unused skills; use `/autoplan` only for larger changes |
| Overlap with existing review tooling | Duplicate, conflicting findings | Choose one primary reviewer per PR |

## 7. Unknowns (verify during Phase 0)

- Whether `./setup` on Windows/Git Bash works with your local setup — gstack lists Windows as
  "supported with limits"; not tested here.
- Whether the `gstack-config` keys above are unchanged on the commit you pin.
- How `/ship`'s `NO_VERSION` path handles CHANGELOG drafting in practice (source says it skips the
  CHANGELOG entry; Phase 1's `CLAUDE.md` rule may or may not be picked up — check in the pilot).

## Conclusion

gstack's planning, review, investigation and security skills fit this repository well; its browser,
design, deploy and iOS skills do not apply to a WPF desktop module and should be disabled. The real
work is not the install but encoding this repo's conventions in a `CLAUDE.md` (which is worth doing
regardless), pinning gstack for supply-chain hygiene, and running `/ship` through the `NO_VERSION`,
no-trailer, `/validate`-triggered path. Recommended route: Phase 0 → 1 → 2 (`optional`) → 4, with
Phase 3 only if cloud sessions matter to you.
