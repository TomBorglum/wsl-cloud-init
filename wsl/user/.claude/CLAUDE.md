# Writing style

Never write what is already written elsewhere — in the code, in a vendor's documentation, in
git history, or in another file of this project.

## Authored documents

These rules apply to every markdown file you write or edit — README, docs, skills, plans,
commit messages, PR bodies. They are about documentation, not about replies in the terminal.

Write reference material, not narrative.

- Lead with the fact. Do not open a section by announcing what it will cover.
- One claim per sentence. Do not stack em-dash asides to carry a second claim.
- State what a thing does. Cut the sentence explaining why it is pleasant that it does so.
- Keep rationale only where it changes what the reader does. Delete the rest.
- Do not restate the call. Where code or configuration already shows an invocation — the flags
  passed, the values set, the literal strings printed — document the surface the reader
  controls and what changes when they change it, never the mechanics that produce it.
- Never document a third-party tool's own flags, options or environment variables. Name the one
  being used and stop.
- No second-person tour framing: not "the sign-in you already have", "so there is no second
  token to create", "ready to run without extra setup".
- No superlatives, no editorial adjectives, no suspense. "Fast", "simply", "just", "powerful"
  and "seamlessly" are noise.
- Lists for genuine enumerations. Tables for mappings of path, flag or option to meaning. Prose
  for everything else, and never structure as decoration.
- No closing paragraph that recaps the section it closes.
- Prefer the present indicative and the active voice. Name the thing that acts.

## Comments in code

These rules apply to comments in every file that carries code — shell, YAML, JSON, PowerShell,
Dockerfile, Python, and configuration of any kind.

A comment records only what the code cannot state and no other document already states:

- A reason a plain reading of the code contradicts: why this value, why this order, why this
  workaround.
- A constraint the code cannot express: an invariant another file depends on, a required
  ordering, a safety or security requirement.
- A pointer needed to verify the line: an issue URL, a CVE, a specification section.

NEVER write a comment that:

- Explains what a third-party flag, environment variable, option, function or API does. Name
  the one being used and stop.
- Restates in other words the line, step or block it sits on.
- Repeats a name already on the line it annotates.
- Narrates the change rather than the code: "now also", "previously", "added so that". That
  belongs in the commit message and the pull request body.
- Speculates about a later version, an upstream rename, or a future caller.
- Announces what the block below it will do, or labels a section as a divider.
- Paraphrases what this project's own documentation already states.

One line is the default and two is the ceiling. A comment longer than the code it sits on means
the rationale belongs in documentation or in the commit message, not inline. A constraint, a
warning or a security note is exempt, per **What brevity never costs** below.

In a file you are editing, fix or delete an offending comment attached to a line you change.
Leave every other comment alone. Comment cleanup is not part of a feature diff.

## What brevity never costs

Never shorten by dropping any of these:

- A constraint, a warning, or a security note.
- An exact path, flag, command, environment variable or version.
- Verbatim error text or output.
- A rule in a skill or instruction file. Cut its narration, keep the rule, and keep its
  rationale where the rationale is what makes it followed.

Correctness and completeness outrank concision. When a rule here would cost either, ignore it.
