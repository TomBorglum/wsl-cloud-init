#!/bin/bash
use_update-branch() {
  # Reload this .envrc on a branch switch so the update fires exactly once per
  # switch. HEAD's content changes on checkout but not on rebase (the symref
  # still reads "ref: refs/heads/<branch>"), so this does not loop.
  local headfile
  headfile="$(git rev-parse --git-path HEAD 2>/dev/null)"
  [ -n "$headfile" ] && [ -f "$headfile" ] && watch_file "$headfile"

  # Best-effort: _update-branch prints its own diagnostics (dirty tree, detached
  # HEAD, rebase conflict). Never fail the .envrc load over a sync hiccup, so
  # other directives (e.g. use fnm) still apply.
  #
  # If a rebase rewrites .envrc to net-unchanged content it bumps the mtime,
  # triggering one extra reload — the follow-up rebase is a no-op that touches
  # nothing, so there is no further reload. We accept that single redundant
  # reload rather than snapshotting and restoring .envrc's mtime.
  _update-branch || echo "use_update-branch: branch not updated (see above); continuing" >&2
}

# Fetch the remote's default branch and rebase the current branch onto it.
_update-branch() {
  # Must be inside a git work tree.
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "update-branch: not inside a git repository" >&2
    return 1
  fi

  # Base branch: ask the remote for its current default branch rather than
  # trusting the local origin/HEAD symref, which is cached at clone time and
  # goes stale if the default branch is changed upstream. Needs connectivity.
  local base
  base="$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's@^ref: refs/heads/\(.*\)\tHEAD$@\1@p')"
  if [ -z "$base" ]; then
    echo "update-branch: could not determine the remote's default branch — is origin reachable?" >&2
    return 1
  fi

  # Resolve the current branch; refuse on detached HEAD.
  local branch
  if ! branch="$(git symbolic-ref --quiet --short HEAD)"; then
    echo "update-branch: detached HEAD — check out a branch first" >&2
    return 1
  fi

  # Abort if the working tree has uncommitted changes.
  if [ -n "$(git status --porcelain)" ]; then
    echo "update-branch: uncommitted changes — commit or stash before updating" >&2
    return 1
  fi

  # Fetch the latest base from origin, then rebase the branch onto it. Pass -q to
  # both so the success path stays quiet (no fetch summary, no "up to date" line);
  # the single "Updated ..." line below is the only success output. Errors and
  # rebase conflicts still report normally.
  git fetch -q origin "$base" || return 1

  if ! git rebase -q "origin/$base"; then
    echo "update-branch: rebase hit conflicts — resolve them, then run 'git rebase --continue' (or 'git rebase --abort')." >&2
    return 1
  fi

  echo "Updated $branch onto origin/$base"
}
