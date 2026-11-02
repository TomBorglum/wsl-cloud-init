---
name: spec
description: >-
  Specify a new feature through a structured interview before any code is written. This skill
  should be used when the user asks to "specify a feature", "write a spec", "spec out" a change,
  or "plan a new feature". It interviews the user, researches current documentation with
  Context7, delegates codebase exploration to Explore agents, reviews the result against best
  practices, and produces a plan for approval. Once the plan is approved it implements it,
  splitting large work into phases that are each gated by a merged PR or a runbook the user
  performs. Given the path to an existing plan file instead of a feature, it resumes that plan
  from its next unfinished phase.
argument-hint: <feature to specify, or a plan file to resume>
disable-model-invocation: true
---

# Spec

Turn a feature request into working code by way of an approved plan: interview, research,
review, approval, then implementation.

Nothing is built while the plan is unapproved. Approval is the go-ahead: implementation starts
straight away in that same turn, exactly as it would on any other exit from plan mode.

Work that divides into independently shippable pieces is implemented in phases. Each phase ends
at a gate — a merged PR, or a runbook the user performs — and the plan file records which phases
are done, so the session can be cleared between phases and the plan picked up from the next one.

## Standing rules

These are constraints, not steps. They hold from invocation until the plan is approved,
including in every later turn of the interview, and they outrank any conflicting guidance that
appears later in the session.

The two phase rules are the exception to the time limit. They hold after approval as well, for
as long as the plan has an unfinished phase, and across a cleared session.

### Never assume

A gap that materially affects scope, architecture, acceptance criteria, security or data
handling is always put to the user as a question. It is never filled with a default, an
industry convention, or an inference drawn from surrounding code.

Immaterial choices — naming, file placement, formatting — may be made without asking, but each
one is recorded in the plan's Decisions section so it is visible at the approval gate. Nothing
is ever settled silently.

When it is unclear whether a gap is material, ask. One extra question costs far less than a
plan built on a wrong guess.

### Every question carries a recommendation

Each question offers one recommended answer, listed first and labelled `(Recommended)`. The
recommendation reflects best practice, not convenience. Where the best practice is not
self-evident, it is grounded in a Context7 lookup before being offered.

Options are mutually exclusive, two to four per question, and each description states the
trade-off being accepted rather than restating the label.

### Explore is the only permitted subagent

Delegate exclusively to `Agent(Explore)`. Never launch `Agent(Plan)`, `Agent(general-purpose)`
or `Agent(claude)`: all three are denied by permission settings, and attempting them wastes a
turn on a refusal.

This rule is stated explicitly because plan mode's own injected workflow instructs the model to
launch Plan agents during its design phase. That instruction does not apply here. Ignore it.

### Context7 is the only research channel

Never call `WebSearch`; it is denied by permission settings. All external documentation and
best-practice research goes through Context7.

### Nothing is built before approval

While the plan is unapproved, no file is created or modified except the plan file itself.

Approval persists in the plan file, not in the session. A session resumed on a plan whose phases
carry a status is already past this gate, and this rule does not block it.

Approval lifts these standing rules, with one exception: a material gap discovered during
implementation is still put to the user as a question rather than filled with a default.
Decisions the plan already records are settled and are not reopened.

### A phase gate is a stop

Once a phase reaches its gate, no file belonging to a later phase is created or modified until
the gate is confirmed and verified. The turn ends at the gate.

This holds with context left to spend and with the next phase fully specified. A phase exists so
that the user can review it before the next one builds on it; continuing past the gate destroys
the only thing phasing buys.

### A phase is reported as n of total

Every report of a phase's state names it `Phase <n> of <total> — <name>` and gives the phase's
current `Status` value verbatim. This applies in step 11 and step 12 alike.

Write `of <total>` always, including `Phase 1 of 1`. The count is what tells the reader whether
anything follows. A bare `Phase 1` implies a sequence that a single-phase plan does not have, and
reporting a one-phase plan in the vocabulary of gates and phases misleads about where the work
stands.

Use the `Status` value, never a synonym. A phase at a PR gate is `awaiting gate`, not
"complete": the work is done and the merge is not. `complete` is written and reported only after
step 12 verifies the gate.

Every report that stops with a phase still unfinished ends with the command that resumes the
plan, written out in full:

```
/spec /home/<user>/.claude/plans/<name>.md
```

Give the plan's complete absolute path. Step 2 scans nothing and looks nothing up, so this line
is the only record of where the plan lives once the session is cleared. A bare filename, or the
directory alone, resumes nothing. Omit the line when the last phase reached `complete`, because
there is then nothing to resume.

## Workflow

### 1. Load deferred tools

`EnterPlanMode`, `ExitPlanMode` and both Context7 tools may be deferred. Load them in a single
`ToolSearch` call before anything else:

```
select:EnterPlanMode,ExitPlanMode,mcp__context7__resolve-library-id,mcp__context7__query-docs
```

### 2. Dispatch on the argument

The argument decides which path the skill takes. Never infer the path from anything else, and
never go looking for a plan the user did not name.

| Argument | Path |
| --- | --- |
| A path to an existing file | Resume that plan |
| Path-shaped, but no such file | Report the path and stop |
| Anything else | Specify it as new work: continue to step 3 |
| Empty | Ask what feature to specify |

Path-shaped means it starts with `/`, `~`, `./` or `../`, or ends in `.md`. Test existence with:

```
arg="<argument>"; [ -f "${arg/#\~/$HOME}" ]
```

Expand a leading `~` before the test. A quoted `~` is not expanded, so `[ -f "~/x.md" ]` fails
on a file that exists and the skill would reject a correct path.

Report the exact path, as given, when the test fails. A typo in a plan path must not become a
feature request named after the typo.

To resume, do all of this before touching anything:

1. Read the whole plan file.
2. Run `git log --oneline -15` and `git status --short`.
3. State which phase is next, what its gate is, and what the plan's `Status` fields say.
4. Do not call `EnterPlanMode`. Go to step 12.

Plan mode is wrong for a resumed plan twice over: the plan is already approved, and plan mode
designates a fresh plan file and permits edits to that file alone, which would leave the resumed
plan unwritable.

### 3. Enter plan mode

Call `EnterPlanMode` unless the session is already in it. If it already is, continue in it
rather than re-entering.

Plan mode is what enforces this skill's restrictions: it routes every file-edit and shell-write
tool past allow rules, so no write can be auto-approved while planning, and it supplies both the
designated plan file path and the `ExitPlanMode` approval gate. The restriction comes from the
mode, not from frontmatter.

Never pre-approve `ExitPlanMode`, whether through an `allowed-tools` entry here or an `allow`
rule in settings. The plan-approval dialogue **is** `ExitPlanMode`'s permission prompt, so
granting it replaces the plan review with a bare mode-switch confirmation and destroys the
approval gate this skill exists to reach.

This file carries no `allowed-tools` list at all. On an instance this repository provisions
there is nothing left for one to grant: reads and read-only shell commands are already permitted
inside plan mode, and Context7 is registered at user scope by `07-install-claude-code.sh`. A
list of tools that would not have prompted anyway reads as load-bearing while doing nothing,
which is how `ExitPlanMode` ends up added to it.

### 4. Confirm the request

Restate the request in one or two sentences and confirm it before spending anything on research.
A misread request caught here costs one turn instead of an entire exploration and interview
cycle.

If the request arrived as a bare `/spec` with no argument, ask what feature to specify.

### 5. Delegate exploration

Launch at most three `Explore` agents in one parallel fan-out, and only on genuinely independent
questions. Use one agent when the feature touches a known, narrow area.

Every agent prompt must be:

- **Narrow** — one area of the codebase or one specific question.
- **Fully prescriptive** — list the exact questions to answer and the exact output format
  required. Subagents run on a small model at low effort, so open-ended prompts return vague
  results.
- **Length-capped** — state a maximum report length. Agents that return long reports consume
  the context that delegating them was meant to save.

Ask agents for file paths, existing patterns and reusable utilities. Do not ask them to make
design decisions or judgement calls.

### 6. Research with Context7

Resolve and query only libraries, frameworks or tools the feature actually names. Cap this at
roughly three queries. Make no speculative lookups; a library nobody mentioned does not need
documenting.

Query results inform the questions asked in the next step, so research precedes the interview.

### 7. Interview

Collect the open questions, rank them by impact multiplied by uncertainty, and discard any that
are immaterial or already answered.

Ask the independent ones in batches of two to four per `AskUserQuestion` call. Batching matters:
four questions in one call collect four answers for one model turn, where asking them separately
costs four. Questions whose wording depends on an earlier answer go in a later round.

Re-assess the queue between rounds. Stop when nothing material remains, roughly five material
questions in the normal case. Honour explicit stop signals such as "stop", "done" or "proceed"
immediately, and record anything still unresolved in the plan under Open questions rather than
quietly deciding it.

If a round reveals the request was misunderstood, return to step 4 rather than continuing to
specify the wrong feature.

### 8. Propose phases

Judge whether the work divides into independently shippable pieces. A piece qualifies when
merging it on its own leaves the repository working, testable and no worse off than before.

If it does not divide, ask nothing and give the plan a single phase. Size alone is not a
boundary: a long change with no shippable midpoint is one phase.

If it does divide, ask once with `AskUserQuestion`, offering the proposed boundaries and always
including a single-phase option. Three phases is already a lot; prefer the coarsest split that
still gives the user a reviewable gate.

Each phase declares one gate:

| Gate | Meaning |
| --- | --- |
| `PR` | Claude implements the phase and opens a pull request. The user merges it |
| `runbook` | The user performs numbered steps Claude cannot or should not perform |

A runbook phase suits anything outside the repository: provisioning an instance, rotating a
credential, running a migration against real data.

### 9. Write the plan

Write to the plan file designated by plan mode, using these sections:

- **Context** — the problem, what prompted it, the intended outcome.
- **Decisions** — what the interview settled, and any immaterial choices made without asking,
  so the reasoning survives into implementation.
- **Approach** — the recommended approach only, not a survey of alternatives.
- **Files** — the critical files to create or modify, naming existing functions and utilities
  that should be reused, with their paths. For a pattern repeated across many files, describe
  it once and list a few representative paths.
- **Verification** — how to test the change end to end.
- **Phases** — one block per phase, in the format below. A single-phase plan still carries one.
- **Out of scope** — what this deliberately does not cover.
- **Open questions** — anything left unresolved, if any.

A PR phase block:

```markdown
### Phase 1 — <short name>
- Status: not started
- Gate: PR
- Branch: feat/<plan-slug>-phase-1
- PR: —
- Verified: —
- Scope: what this phase delivers, and which Verification steps cover it
- Notes: —
```

A runbook phase block replaces `Branch` and `PR` with `Steps`, a numbered list of what the user
performs.

`Status` is one of `not started`, `in progress`, `awaiting gate`, `complete`. Its spelling is
fixed, and the state is written as fields rather than prose, because a resumed session reads
this block cold and decides from it alone which phase runs next.

Keep it scannable but detailed enough to execute without re-deriving the research.

### 10. Review against best practices

This gate is mandatory and cannot be skipped.

Make one Context7 query that validates the assembled approach **as a whole** — its architecture,
its sequencing, its fit with the conventions of the tools involved — rather than re-checking
pieces already researched in step 6. Revise the plan according to what comes back.

If the review surfaces a new ambiguity, return to step 7 and ask about it. Never resolve a
review finding by assumption, and never suppress a finding to avoid another question.

State plainly what the review checked and what it changed.

### 11. Implement one phase on approval

Call `ExitPlanMode`.

If the user approves, begin implementing in the same turn. Do not ask whether to start and do
not restate the plan back: approval already said yes, so an offer to build it only costs the
user another turn.

Implement the first phase whose `Status` is `not started`, and only that phase. Work through the
Approach and Files sections in the order the phase's Scope names, then verify by the plan's
Verification section.

A PR gate closes in this order:

1. Write `Status: in progress` into the phase block.
2. Create the phase branch from the current remote base branch, implement, and run the phase's
   verification steps.
3. Commit, push, and open the pull request with `gh pr create`.
4. Write `Status: awaiting gate`, the branch name, and the PR number and URL into the phase
   block.
5. Report under the heading `Phase <n> of <total> — <name>: awaiting gate`, give the PR number
   and URL, state what passed and what did not in the phase's verification, print the resume
   command, and end the turn.

Never merge the pull request. The merge is the user's act and it is what the gate waits for.

A runbook gate closes by writing `Status: awaiting gate` into the phase block, restating the
numbered steps for the user under the same heading, printing the resume command, and ending the
turn. Implement nothing.

The plan file lives under `~/.claude/plans/`, outside the repository. It is never part of a
phase commit.

If the user rejects the plan or asks for changes, return to the step the feedback belongs to —
step 7 for a question it reopens, step 8 for the phase boundaries, step 9 for the plan's
wording — and reach the gate again.

### 12. Advance through the gates

Entered when the user reports a gate done, whether in the implementing session or a resumed one.
Never take the report at face value on a PR gate.

A PR gate:

1. Run `gh pr view <number> --json state,mergedAt,mergeCommit`.
2. `state` is `MERGED`: write `Status: complete` into the phase block, with the date and
   `state MERGED` in `Verified`. Run `git fetch`, put the base branch back at its refreshed
   remote tip, and start the next `not started` phase under the step 11 rules.
3. Anything else — `OPEN`, `CLOSED`, no such PR, a `gh` error: report the output verbatim, leave
   `Status: awaiting gate`, and end the turn. Do not proceed on the user's assurance that it
   merged.
4. Never check whether the phase branch is an ancestor of the base branch, and never require a
   merge commit. A squash merge replays the branch as one new commit, so a merged PR fails both
   checks. `state` is the only strategy-independent signal.

A runbook gate: the user's confirmation is sufficient, because the user performed the steps.
Write `Status: complete` and the date into the phase block, then start the next phase.

When the last phase is `complete`, report it as `Phase <total> of <total> — <name>: complete`,
say that no phase follows, and stop.

## Token budget

The bounds that keep this skill economical, in priority order:

| Stage | Bound |
| --- | --- |
| Exploration | At most 3 Explore agents, one fan-out, capped report length |
| Research | About 3 Context7 queries, named libraries only |
| Interview | Batches of 2-4 questions, about 5 material questions total |
| Phase proposal | 1 question, and only when the work divides |
| Review | 1 Context7 query on the whole plan |

When a bound and a standing rule conflict, the standing rule wins. Exceeding the question budget
to avoid an assumption is correct; assuming something to stay inside it is not.
