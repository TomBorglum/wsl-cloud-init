# Contributing

Releases are automated with [release-please](https://github.com/googleapis/release-please).
It reads the commit history on `main`, decides the next version, and maintains a
"chore(main): release X.Y.Z" pull request that updates [`CHANGELOG.md`](CHANGELOG.md)
and the version. Merging that PR tags the version and publishes the GitHub Release.

Commits must therefore follow [Conventional Commits](https://www.conventionalcommits.org/).

## Commit message format

```
<type>(<optional scope>): <description>

<optional body — what changed and why>

<optional footer — BREAKING CHANGE:, Refs #123, Co-Authored-By:>
```

release-please parses the first line, the *subject*. Keep it lowercase, in the
imperative mood ("add", not "added" or "adds"), with no trailing period, and
ideally under ~72 characters.

## Types

The types configured in [`release-please-config.json`](release-please-config.json).
A type picks the changelog section and decides whether the change can cut a
release on its own: a commit in a visible section is a *releasable unit*, and a
commit in a hidden section rides along, triggering no release and appearing in no
notes.

| Type | Example | Changelog section | Cuts a release? |
| --- | --- | --- | --- |
| `feat` | `feat: add openSUSE distro template` | Features | yes — **minor** (1.1.0) |
| `fix` | `fix: correct WSL path conversion` | Bug Fixes | yes — **patch** (1.0.1) |
| `deps` | `deps: bump lazydocker to v0.24.1` | Dependencies | yes — **patch** (1.0.1) |
| `perf` | `perf: skip a redundant interop call` | *(hidden)* | no — rides along |
| `revert` | `revert: undo the sdkman pin` | *(hidden)* | no — rides along |
| `docs` | `docs: clarify the opt-in features` | *(hidden)* | no — rides along |
| `chore` | `chore: tidy script comments` | *(hidden)* | no — rides along |
| `ci` | `ci: pin actions by sha` | *(hidden)* | no — rides along |
| `build` `refactor` `style` `test` | `refactor: extract a helper` | *(hidden)* | no — rides along |

A PR containing only ride-along types opens no release PR until a
`feat`/`fix`/`deps` lands.

> **Visibility = releasability.** Un-hiding a section in
> `release-please-config.json` makes commits of that type start cutting releases.
> That is deliberate for `deps`; be intentional before un-hiding anything else
> (a `docs:`-only change cutting a release is usually noise).

### `deps:` vs `ci:`

**If the change alters what a user receives when they provision, it's `deps:` (or
`feat`/`fix`); if it only touches the build or CI, it's `ci:`/`chore:`.** The
lazydocker and direnv auto-update workflows use `deps:`, because bumping a
shipped tool cuts a patch release, while Dependabot's GitHub Actions bumps use
`ci:`, because they never reach a provisioned environment.

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

Pull requests are **squash-merged**: the whole branch collapses into a single
commit on `main` whose subject comes from the **PR title** and whose body is the
branch's own commit messages. Therefore:

> **The PR title must be a valid Conventional Commit.**

A PR titled `Update docker script` has no type, so it is invisible to
release-please and will neither appear in the changelog nor bump the version.
Title it `fix: ...` / `feat: ...` instead. This holds however many commits the
branch carries, because `squash_merge_commit_title` is `PR_TITLE`.

The one thing release-please still reads from a squash commit's body is a
`BREAKING CHANGE:` footer. That body is the branch's own commit messages
(`squash_merge_commit_message` is `COMMIT_MESSAGES`), **not** the PR description,
so put the footer in a commit on the branch. A footer written only in the PR
description never reaches `main` and is never parsed.

A squash-merged PR yields exactly one changelog entry, its title, so prefer
**focused PRs**: one logical change, one type. Split a branch that would produce
several separate entries into two PRs. The `main-protection` ruleset requires
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

release-please reads commit subjects and PR titles on `main`, never branch names.
Its own release branch, `release-please--branches--main`, is the exception, and it
manages that one itself. Branch names are a human convention; mirror the commit
type:

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
3. Merge that release PR. The version is tagged and the GitHub Release is
   published automatically. No manual tagging.

## ASCII-only PowerShell scripts

Keep every `.ps1` file (e.g. [`windows/scripts/`](windows/scripts/)) **ASCII-only**. The
provisioning entrypoints run under **Windows PowerShell 5.1** (`powershell.exe`), which reads
a script that has no byte-order mark as ANSI (Windows-1252), not UTF-8. A stray non-ASCII
character is mangled into invalid bytes and aborts parsing at provision time, on the user's
machine rather than in review.

The usual culprits are characters an editor or paste inserts automatically: em/en dashes
(`—` `–`), smart quotes (`“” ‘’`), arrows (`→ ↔`), and ellipses (`…`). Use their ASCII
equivalents in strings and comments: `-` or `--`, `->`, straight `"` / `'`, `...`.

Check before committing:

```bash
git grep -nP '[^\x00-\x7F]' -- '*.ps1'   # must print nothing
```

This applies only to `.ps1`. Markdown, shell and template files are UTF-8 and may use these
characters freely.

## direnv directives

The directives in `wsl/user/.config/direnv/lib/` let a project declare a runtime version
**once** in its `.envrc` — `use sdk java 21.0.2-tem` — and have every instance this repo
provisions honour it. `13-install-direnv-functions.sh` installs them.

The same directives are available on a GitHub Actions runner through
[`TomBorglum/actions/setup-direnv`](https://github.com/TomBorglum/actions/tree/main/setup-direnv),
and in a Claude Code cloud session through
[`TomBorglum/claude-cloud-bootstrap`](https://github.com/TomBorglum/claude-cloud-bootstrap). Both
carry their own copies: the actions one a deliberately different CI-only implementation, the cloud
one a vendored copy of these. Keeping those in step is a maintainer duty there, not a gate here, so a change to a
directive in this repository does not have to answer for either.

`use_pixi` installs its own tool rather than relying on provisioning having done it, so it stands
alone on an instance this repo never provisioned. `use_fnm` and `use_sdk` still depend on
`05-install-fnm.sh` and `04-install-sdkman.sh`.

Owning the install means owning the **version store**: `use pixi <version> [template]` puts each
pinned pixi in `~/.pixi/versions/<version>/bin` and points `~/.pixi/bin/pixi` at the one the
active context wants, which is the path `pixi-completion.zsh` evaluates. The store entry is
guarded on the version the binary *reports*, not on its presence, so a `pixi self-update` inside
an active context is undone by the next `direnv allow` rather than surviving at a path the
directive would otherwise accept. `PATH_add` gets the version directory, not just `~/.pixi/bin`,
so a second terminal activating a differently pinned project cannot change what this one runs — the same reason `use_fnm` and `use_sdk` put a version directory
on `PATH` instead of a shared `current` symlink.

The pin lives in the `.envrc` and is not mirrored into `pixi.toml` as `requires-pixi`. Keeping the
two in step would mean rewriting a tracked manifest on every bump, a larger licence than the
scaffold-once one `use_sonarqube_mcp` takes below.

Each directive is **generic over its argument**. `use_sdk`
passes `<candidate> <version>` straight to SDKMAN and exposes the result the same way for
**every** candidate: the bin on `PATH`, plus SDKMAN's `<CANDIDATE>_HOME` (`JAVA_HOME`,
`MAVEN_HOME`, …) derived as `${candidate^^}_HOME`. `use sdk maven 3.9.6`, `use sdk gradle
8.7`, and the like already work with **no code change**.

Adding an entirely **new directive** (a new backend, not a variant of `use_sdk`) means a new
function here. If it is a runtime directive, its CI counterpart lives in the actions repository
linked above and is that repository's to implement and test.

### Two directive conventions

**A directive may scaffold a project file** on first activation. `use_pixi` writes a starter
`pixi.toml`; `use_sonarqube_mcp` writes a `.claude/agents/sonarqube.md`. Each prints a reminder
to commit it, because those generated files are part of the repository.

A directive that scaffolds must never rewrite what it already wrote. This runs on every `cd`, so
reformatting a tracked file each time would leave every consuming repository permanently dirty.
Scaffold when the file is absent, and be a no-op when it is there.

**An optional directive must not break the `.envrc`.** A *runtime* directive `return`s 1 when a
prerequisite is missing, because a missing Node or JVM is a genuine failure worth surfacing
immediately in an interactive shell. A directive for an *optional* integration instead warns to
stderr and `return`s 0, so the rest of the environment still loads. `use_sonarqube_mcp` follows
this pattern: a missing credential or an unreachable Credential Manager produces a warning, never
a failed load.
