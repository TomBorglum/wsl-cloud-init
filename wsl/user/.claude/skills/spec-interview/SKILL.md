---
name: spec-interview
description: Specify a change before building it: fetch current documentation from Context7, interview with structured questions that each carry one documented recommendation, then end in an approved plan.
argument-hint: <what you want built or changed>
disable-model-invocation: true
---

# spec-interview

Turn a one-line request into an agreed specification before any code is written. The
order is what carries the value: current documentation first, then questions whose
options are grounded in that documentation, then a plan — never an implementation that
quietly encodes an assumption nobody stated.

Invoked explicitly, never on its own. Suited to work with real design surface: a new
feature, a refactor, a migration, a new script, anything spanning more than one file.
Invoked on a typo fix, a rename, or a question about existing code, there is nothing to
interview about — say so and do the work.

## Workflow

1. **Fetch the docs first — always, no exceptions.** Before the first question, run at
   least one `resolve-library-id` → `query-docs` round against the Context7 MCP server
   (that order; `query-docs` needs the ID the first call returns) for every library,
   framework, SDK, CLI or cloud service the request names or implies. When the work is
   purely internal, resolve the language, runtime or tooling actually in play instead —
   `bash`, `jq`, `direnv`, `zsh` — so the round still happens and still returns something
   to reason from. Never open the interview on memory alone: the point of the lookup is
   that training data lags behind the tool being used.

2. **Interview — assume nothing.** Every unknown becomes a question, never a silent
   default. Ask with `AskUserQuestion` rather than in prose, so answering is clicking:
   up to 4 questions per batch, 2–4 options each. Keep asking in batches until nothing
   material is unresolved, and prefer a second batch informed by the first over one
   oversized batch of guesses.

3. **One recommendation per question.** Exactly one option per question is labelled
   `(Recommended)` and placed first, and its description states the fact from the fetched
   documentation that makes it the recommendation — not a generic preference and not
   "best practice" in the abstract. Where the documentation does not settle a question,
   say so in that option's description and recommend on stated engineering grounds
   instead. Every non-recommended option still gets an honest description of its
   trade-off; an option nobody would pick is not a choice.

4. **Cite what was consulted.** Name the Context7 library IDs the recommendations rest
   on. Where a lookup returned nothing relevant, say that plainly and mark the
   recommendations that therefore rest on judgement. An uncited recommendation is
   indistinguishable from a guess, which defeats the purpose of step 1.

5. **Plan, then stop.** Write the plan and call `ExitPlanMode` for approval before
   touching a file. If the session is not already in plan mode, call `EnterPlanMode`
   first; if it is, continue in it rather than re-entering. No edits until the plan is
   approved.

## Hand off, do not duplicate

This skill owns the interview and the lookup, not the writing. Once the plan is approved,
defer to whichever narrower skill covers the deliverable — `bash-install-script` for an
install script, and so on — and let it own its conventions. Re-deriving those conventions
here would duplicate them badly and leave two copies to keep in step.

## The user overrides

A request to skip the interview, or the lookup, or to just make the change, is honoured
for that request. State what is being skipped, then proceed.

## Adding to this file

**This file stays under 200 lines**, so refining it displaces rather than accumulates. A
line that wants room past 200 retires one.

A line earns its place only if all three hold. Most candidates fail the first.

1. **Claude would plausibly do it otherwise unprompted.** Only what is not already
   ordinary competence. A line restating what any competent engineer does anyway costs
   tokens on every invocation and changes nothing.
2. **It changes the interview.** It alters a question asked, an option offered, the order
   of the steps, or what it declines to handle. Prose that motivates the skill rather than
   directing it is not an instruction.
3. **It cannot live anywhere better.** A convention long enough to need examples belongs
   in a sibling reference file that this one points at, read on demand rather than on
   every invocation.

Then state it in one to three lines, imperative, never second person. **Never restate the
`description` above** — it is pre-loaded every session, so a copy here is a second place
to keep in step, and the first to go stale.
