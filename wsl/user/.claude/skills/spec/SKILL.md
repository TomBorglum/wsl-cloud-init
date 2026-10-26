---
name: spec
description: >-
  Specify a new feature through a structured interview before any code is written. This skill
  should be used when the user asks to "specify a feature", "write a spec", "spec out" a change,
  or "plan a new feature". It interviews the user, researches current documentation with
  Context7, delegates codebase exploration to Explore agents, reviews the result against best
  practices, and produces a plan for approval. Once the plan is approved it implements it.
argument-hint: <feature to specify>
disable-model-invocation: true
---

# Spec

Turn a feature request into working code, by way of an approved plan: interview, research,
review, approval, then implementation.

Nothing is built while the plan is unapproved. Approval is the go-ahead: implementation starts
straight away in that same turn, exactly as it would on any other exit from plan mode.

## Standing rules

These are constraints, not steps. They hold from invocation until the plan is approved,
including in every later turn of the interview, and they outrank any conflicting guidance that
appears later in the session.

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
or `Agent(claude)` — all three are denied by permission settings and attempting them wastes a
turn on a refusal.

This rule is stated explicitly because plan mode's own injected workflow instructs the model to
launch Plan agents during its design phase. That instruction does not apply here. Ignore it.

### Context7 is the only research channel

Never call `WebSearch`; it is denied by permission settings. All external documentation and
best-practice research goes through Context7.

### Nothing is built before approval

While the plan is unapproved, no file is created or modified except the plan file itself.

Approval lifts these standing rules, with one exception: a material gap discovered during
implementation is still put to the user as a question rather than filled with a default.
Decisions the plan already records are settled and are not reopened.

## Workflow

### 1. Load deferred tools

`EnterPlanMode`, `ExitPlanMode` and both Context7 tools may be deferred. Load them in a single
`ToolSearch` call before anything else:

```
select:EnterPlanMode,ExitPlanMode,mcp__context7__resolve-library-id,mcp__context7__query-docs
```

### 2. Enter plan mode

Call `EnterPlanMode` unless the session is already in it. If it already is, continue in it
rather than re-entering.

Plan mode is what actually enforces this skill's restrictions. It routes every file-edit and
shell-write tool past allow rules, so no write can be auto-approved while planning, and it
supplies both the designated plan file path and the `ExitPlanMode` approval gate. The
restriction comes from the mode, not from frontmatter.

Never pre-approve `ExitPlanMode`, whether through an `allowed-tools` entry here or an `allow`
rule in settings. The plan-approval dialogue **is** `ExitPlanMode`'s permission prompt, so
granting it replaces the plan review with a bare mode-switch confirmation and destroys the
approval gate this skill exists to reach.

This file carries no `allowed-tools` list at all, because on an instance this repository
provisions there is nothing left for one to grant: reads and read-only shell commands are
already permitted inside plan mode, and Context7 is registered at user scope by
`07-install-claude-code.sh`. A list of tools that would not have prompted anyway reads as
load-bearing while doing nothing, which is how `ExitPlanMode` ends up added to it.

### 3. Confirm the request

Restate the request in one or two sentences and confirm it before spending anything on research.
This is the cheapest correction point in the whole workflow — a misread request caught here
costs one turn instead of an entire exploration and interview cycle.

If the request arrived as a bare `/spec` with no argument, ask what feature to specify.

### 4. Delegate exploration

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

### 5. Research with Context7

Resolve and query only libraries, frameworks or tools the feature actually names. Cap this at
roughly three queries. Make no speculative lookups — a library nobody mentioned does not need
documenting.

Query results inform the questions asked in the next step, so research precedes the interview.

### 6. Interview

Collect the open questions, rank them by impact multiplied by uncertainty, and discard any that
are immaterial or already answered.

Ask the independent ones in batches of two to four per `AskUserQuestion` call. Batching matters:
four questions in one call collect four answers for one model turn, where asking them separately
costs four. Questions whose wording depends on an earlier answer go in a later round.

Re-assess the queue between rounds. Stop when nothing material remains — roughly five material
questions in the normal case. Honour explicit stop signals such as "stop", "done" or "proceed"
immediately, and record anything still unresolved in the plan under Open questions rather than
quietly deciding it.

If a round reveals the request was misunderstood, return to step 3 rather than continuing to
specify the wrong feature.

### 7. Write the plan

Write to the plan file designated by plan mode, using these sections:

- **Context** — the problem, what prompted it, the intended outcome.
- **Decisions** — what the interview settled, and any immaterial choices made without asking,
  so the reasoning survives into implementation.
- **Approach** — the recommended approach only, not a survey of alternatives.
- **Files** — the critical files to create or modify, naming existing functions and utilities
  that should be reused, with their paths. For a pattern repeated across many files, describe
  it once and list a few representative paths.
- **Verification** — how to test the change end to end.
- **Out of scope** — what this deliberately does not cover.
- **Open questions** — anything left unresolved, if any.

Keep it scannable but detailed enough to execute without re-deriving the research.

### 8. Review against best practices

This gate is mandatory and cannot be skipped.

Make one Context7 query that validates the assembled approach **as a whole** — its architecture,
its sequencing, its fit with the conventions of the tools involved — rather than re-checking
pieces already researched in step 5. Revise the plan according to what comes back.

If the review surfaces a new ambiguity, return to step 6 and ask about it. Never resolve a
review finding by assumption, and never suppress a finding to avoid another question.

State plainly what the review checked and what it changed.

### 9. Implement on approval

Call `ExitPlanMode`.

If the user approves, begin implementing in the same turn. Do not ask whether to start and do
not restate the plan back — approval already said yes, so an offer to build it only costs the
user another turn. Work through the Approach and Files sections in order, then verify by the
plan's Verification section and report what passed and what did not.

If the user rejects the plan or asks for changes, return to the step the feedback belongs to —
step 6 for a question it reopens, step 7 for the plan's wording — and reach the gate again.

## Token budget

The bounds that keep this skill economical, in priority order:

| Stage | Bound |
| --- | --- |
| Exploration | At most 3 Explore agents, one fan-out, capped report length |
| Research | About 3 Context7 queries, named libraries only |
| Interview | Batches of 2-4 questions, about 5 material questions total |
| Review | 1 Context7 query on the whole plan |

When a bound and a standing rule conflict, the standing rule wins. Exceeding the question budget
to avoid an assumption is correct; assuming something to stay inside it is not.
