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
The type controls two independent things: which changelog section the change
appears under, and whether it is a **releasable unit** — i.e. whether it can cut
a release on its own. For our `simple` release type the releasable units are
`feat`, `fix`, and `deps` (plus any breaking change); everything else only ever
rides along.

| Type | Example | Changelog section | Cuts a release? |
| --- | --- | --- | --- |
| `feat` | `feat: add openSUSE distro template` | Features | yes — **minor** (1.1.0) |
| `fix` | `fix: correct WSL path conversion` | Bug Fixes | yes — **patch** (1.0.1) |
| `deps` | `deps: bump lazydocker to v0.24.1` | Dependencies | yes — **patch** (1.0.1) |
| `perf` | `perf: skip a redundant interop call` | Performance Improvements | no — rides along¹ |
| `revert` | `revert: undo the sdkman pin` | Reverts | no — rides along¹ |
| `docs` | `docs: clarify the opt-in features` | Documentation | no — rides along¹ |
| `chore` | `chore: tidy script comments` | *(hidden)* | no — rides along¹ |
| `ci` | `ci: pin actions by sha` | *(hidden)* | no — rides along¹ |
| `build` `refactor` `style` `test` | `refactor: extract a helper` | *(hidden)* | no — rides along¹ |

¹ **Rides along**: does not trigger a release on its own, but is included in the
next release that a `feat`/`fix`/`deps` cuts. Visible types show up in the notes;
hidden ones don't. A PR containing only ride-along types will not open a release
PR until a releasable unit lands.

### `deps:` vs `ci:` — shipped tools vs CI tooling

`deps:` is releasable on purpose: it's how an update to a tool that is **shipped
into the provisioned environment** produces a new release. The lazydocker
auto-update workflow uses `deps:` so that bumping lazydocker cuts a patch release
of wsl-cloud-init — users get the newer tool in a tagged version.

Dependabot, by contrast, updates the GitHub Actions used only in CI. Those never
reach a provisioned environment, so its PRs use `ci:` (hidden, non-releasable):
they keep CI current without cutting a product release. Rule of thumb: **if the
change alters what a user receives when they provision, it's `deps:` (or
`feat`/`fix`); if it only touches the build/CI, it's `ci:`/`chore:`.**

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

## Squash merges: the PR title is what counts

Pull requests are **squash-merged**, so the whole branch collapses into a single
commit on `main` whose subject is taken from the **PR title** — the individual
commit messages on the branch are discarded. Therefore:

> **The PR title must be a valid Conventional Commit.**

A PR titled `Update docker script` (no type) is invisible to release-please and
will neither appear in the changelog nor bump the version. Title it
`fix: ...` / `feat: ...` instead.

The one thing release-please still reads from a squash commit's body is a
`BREAKING CHANGE:` footer, so put that in the PR description when it applies.

### When you want several distinct changelog entries from one branch

Because a squash gives exactly one changelog entry (the PR title), prefer
**focused PRs** — one logical change, one type. If you genuinely need a single
branch to produce multiple separate entries (e.g. several `feat:` lines), merge
that PR with a **merge commit** instead of a squash so each Conventional Commit
on the branch is preserved and parsed individually.

## How the version is chosen

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

## The release flow, end to end

1. Open a PR with a Conventional Commit **title** and let the SonarCloud check pass.
2. Merge it. release-please opens or updates the **chore(main): release X.Y.Z** PR.
3. Merge that release PR — the version is tagged and the GitHub Release is
   published automatically. No manual tagging.
