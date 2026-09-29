#!/bin/bash
# use_claude_env
#
# CI-only (GitHub Actions) direnv directive. The action installs this file onto the
# runner's ~/.config/direnv/lib; it is never run outside GitHub Actions. Self-contained by
# design: it sources no other file in this repository.
#
# The terminal copy scaffolds a repository's .claude/settings.json so Claude Code loads
# the .envrc. A runner has no Claude Code and no home directory worth configuring, and
# writing into the checkout would leave the working tree dirty for later steps. So this is
# a deliberate no-op — it exists only so a committed .envrc containing `use claude_env`
# evaluates cleanly on the runner instead of failing with an undefined directive. It
# exports nothing and writes nothing.
use_claude_env() {
  return 0
}
