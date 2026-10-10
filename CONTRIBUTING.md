# Contributing

Releases are automated with [release-please](https://github.com/googleapis/release-please).
It reads the commit history on `main`, decides the next version, and maintains a
"chore(main): release X.Y.Z" pull request that updates [`CHANGELOG.md`](CHANGELOG.md)
and the version. Merging that PR tags the version and publishes the GitHub Release.

For that to work, commits must follow [Conventional Commits](https://www.conventionalcommits.org/).
This document is the guard rail for how to name commits and branches so the
automation does the right thing.

## Commit message format

```
<type>(<optional scope>): <description>

<optional body — what changed and why>

<optional footer — BREAKING CHANGE:, Refs #123, Co-Authored-By:>
```

The first line (the *subject*) is what release-please parses. Keep it lowercase,
in the imperative mood ("add", not "added" or "adds"), with no trailing period,
and ideally under ~72 characters.

## Types

These are the types configured in [`release-please-config.json`](release-please-config.json).
A type does two independent things: it selects the changelog section the change
appears under, and — because release-please treats any commit in a **visible**
(non-hidden) section as a *releasable unit* — it decides whether the change can
cut a release on its own. We keep only `feat`, `fix`, and `deps` visible, so only
those (plus any breaking change) cut releases; every other type is hidden and
merely rides along.

| Type | Example | Changelog section | Cuts a release? |
| --- | --- | --- | --- |
| `feat` | `feat: add openSUSE distro template` | Features | yes — **minor** (1.1.0) |
| `fix` | `fix: correct WSL path conversion` | Bug Fixes | yes — **patch** (1.0.1) |
| `deps` | `deps: bump lazydocker to v0.24.1` | Dependencies | yes — **patch** (1.0.1) |
| `perf` | `perf: skip a redundant interop call` | *(hidden)* | no — rides along¹ |
| `revert` | `revert: undo the sdkman pin` | *(hidden)* | no — rides along¹ |
| `docs` | `docs: clarify the opt-in features` | *(hidden)* | no — rides along¹ |
| `chore` | `chore: tidy script comments` | *(hidden)* | no — rides along¹ |
| `ci` | `ci: pin actions by sha` | *(hidden)* | no — rides along¹ |
| `build` `refactor` `style` `test` | `refactor: extract a helper` | *(hidden)* | no — rides along¹ |

¹ **Rides along**: does not trigger a release on its own and — being hidden —
does not appear in the notes either. A PR containing only ride-along types will
not open a release PR until a `feat`/`fix`/`deps` lands.

> **Visibility = releasability.** If you un-hide a section in
> `release-please-config.json`, commits of that type will start cutting releases.
> That is deliberate for `deps`; be intentional before un-hiding anything else
> (a `docs:`-only change cutting a release is usually noise).

### `deps:` vs `ci:`

**If the change alters what a user receives when they provision, it's `deps:` (or
`feat`/`fix`); if it only touches the build or CI, it's `ci:`/`chore:`.** That is
why the lazydocker auto-update workflow uses `deps:` (bumping a shipped tool cuts
a patch release) while Dependabot's GitHub Actions bumps use `ci:` (they never
reach a provisioned environment).

## Breaking changes

A breaking change forces a **major** bump (2.0.0). Mark it either with a `!`
after the type, or with a `BREAKING CHANGE:` footer:

```
feat!: drop Ubuntu-22.04 support
```

```
feat: drop Ubuntu-22.04 support

BREAKING CHANGE: 22.04 is no longer provisioned; use 24.04 or newer.
```

## Squash merges

Pull requests are **squash-merged**, so the whole branch collapses into a single
commit on `main` whose subject is taken from the **PR title** and whose body is
the branch's own commit messages. Therefore:

> **The PR title must be a valid Conventional Commit.**

A PR titled `Update docker script` (no type) is invisible to release-please and
will neither appear in the changelog nor bump the version. Title it
`fix: ...` / `feat: ...` instead. That holds however many commits the branch
carries, because `squash_merge_commit_title` is `PR_TITLE`. GitHub's default,
`COMMIT_OR_PR_TITLE`, takes the subject from the *commit* when a branch has
exactly one — so a single sloppy commit subject would quietly cut no release.

The one thing release-please still reads from a squash commit's body is a
`BREAKING CHANGE:` footer. That body is the branch's own commit messages
(`squash_merge_commit_message` is `COMMIT_MESSAGES`), **not** the PR
description, so put the footer in a commit on the branch. A footer written only
in the PR description never reaches `main` and is never parsed.

A squash-merged PR yields exactly one changelog entry: its title. So prefer
**focused PRs** — one logical change, one type. A branch that would produce
several separate entries is two PRs: the `main-protection` ruleset requires
linear history and allows only squash and rebase, so the merge commit that would
have preserved each Conventional Commit individually cannot land.

## Version selection

release-please aggregates **every commit merged since the last release** (across
all PRs, not just one branch) and applies the highest-impact bump:

```
any  feat! / BREAKING CHANGE       →  MAJOR
else any  feat                     →  MINOR
else any  fix / deps               →  PATCH
else only ride-along types         →  no release
   (perf, revert, docs, chore, ci, …)
```

## Branch names

release-please ignores branch names entirely — it only reads commit subjects and
PR titles on `main` (its own release branch, `release-please--branches--main`, is
the exception, and it manages that one itself). Branch names are therefore a
human convention only. Mirror the commit type for readability:

```
<type>/<short-kebab-description>

feat/opensuse-template
fix/wsl-path-conversion
deps/bump-lazydocker
docs/readme-opt-in
```

Optionally prefix an issue number: `feat/123-opensuse-template`.

## The release flow

1. Open a PR with a Conventional Commit **title** and let the SonarCloud check pass.
2. Merge it. release-please opens or updates the **chore(main): release X.Y.Z** PR.
3. Merge that release PR — the version is tagged and the GitHub Release is
   published automatically. No manual tagging.

## ASCII-only PowerShell scripts

Keep every `.ps1` file (e.g. [`windows/scripts/`](windows/scripts/)) **ASCII-only**. The
provisioning entrypoints run under **Windows PowerShell 5.1** (`powershell.exe`), which reads
a script that has no byte-order mark as ANSI (Windows-1252), not UTF-8. A stray non-ASCII
character therefore gets mangled into invalid bytes and aborts parsing at provision time —
the failure surfaces on the user's machine, not in review.

The usual culprits are characters an editor or paste inserts automatically: em/en dashes
(`—` `–`), smart quotes (`“” ‘’`), arrows (`→ ↔`), and ellipses (`…`). Use their ASCII
equivalents in strings and comments: `-` or `--`, `->`, straight `"` / `'`, `...`.

Check before committing:

```bash
git grep -nP '[^\x00-\x7F]' -- '*.ps1'   # must print nothing
```

(This applies only to `.ps1`. Markdown, shell, and template files are UTF-8 and may use these
characters freely — this document does.)

## direnv directives

The directives in `wsl/user/.config/direnv/lib/` are what let a project declare a runtime
version **once** in its `.envrc` — `use sdk java 21.0.2-tem` — and have every instance this
repo provisions honour it. `13-install-direnv-functions.sh` installs them on WSL,
`cloud/scripts/03-install-direnv-functions.sh` in a cloud session.

The same directives are available on a GitHub Actions runner through
[`TomBorglum/actions/setup-direnv`](https://github.com/TomBorglum/actions/tree/main/setup-direnv),
which is maintained and released independently of this repository.

pixi is the odd one out among them, deliberately. `use_pixi` installs its own tool rather than
relying on provisioning having done it — the first step toward directives that stand alone, so
that an `.envrc` can eventually pull in the ones it needs on an instance this repo never
provisioned. `use_fnm` and `use_sdk` still depend on `05-install-fnm.sh` and
`04-install-sdkman.sh`.

Each directive is **generic over its argument**, so most additions cost nothing. `use_sdk`
passes `<candidate> <version>` straight to SDKMAN and exposes the result the same way for
**every** candidate — the bin on `PATH`, plus SDKMAN's `<CANDIDATE>_HOME` (`JAVA_HOME`,
`MAVEN_HOME`, …) derived as `${candidate^^}_HOME`. So `use sdk maven 3.9.6`, `use sdk gradle
8.7`, and the like already work with **no code change**.

Adding an entirely **new directive** (a new backend, not a variant of `use_sdk`) means a new
function here. If it is a runtime directive, its CI counterpart lives in the actions repository
linked above and is that repository's to implement and test.

### Two directive conventions

**A directive may scaffold a project file** on first activation. `use_pixi` writes a starter
`pixi.toml`; `use_sonarqube_mcp` writes a `.mcp.json`; `use_claude_env` writes a
`.claude/settings.json`. Each prints a reminder to commit it — those generated files are part of
the repository, so commit them.

`use_claude_env` is the one that writes into a file it does not own, since a repository's
`.claude/settings.json` usually already exists and holds permissions and `env` of its own. It
therefore merges with `jq` rather than creating, adding only the hook entries whose `command` is
absent, and rewrites nothing when they are all present — a directive that reformatted a tracked
file on every `cd` would leave every consuming repository permanently dirty.

**An optional directive must not break the `.envrc`.** A *runtime* directive `return`s 1 when a
prerequisite is missing, because a missing Node or JVM is a genuine failure worth surfacing — it
is visible immediately in an interactive shell. A directive for an *optional* integration
instead warns to stderr and `return`s 0, so the rest of the environment still loads.
`use_sonarqube_mcp` follows this pattern: a missing credential or an unreachable Credential
Manager produces a warning, never a failed load.
