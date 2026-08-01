First inventory the rule sources: the project CLAUDE.md (the audit target), any nested
CLAUDE.md / CLAUDE.local.md files, the global `~/.claude/CLAUDE.md`, and this project's
`.claude/skills/*/SKILL.md` and `.claude/commands/*.md`. Read them — the conflict check
below is impossible from the target file alone. Then audit the target CLAUDE.md rule by
rule (a rule may span several physical lines; judge complete rules, not wrapped
fragments) against these criteria:

**KEEP in CLAUDE.md** if the line is:
- A brief statement of what this repo is for (2–3 lines max, at the top)
- A global behavioral rule that isn't obvious from the codebase
- A "never do this" guardrail where breaking it causes immediate, hard-to-undo damage (spending money, publishing, deleting, shipping without approval)
- A non-obvious constraint with material security, correctness, privacy, or financial consequences — even when the damage is delayed or technically reversible (an auth boundary, a data-handling rule, a required verification step)
- A one-line pointer to a skill or doc that holds the detail ("for verification, see /verify")

**REPHRASE as judgement guidance** if the line is:
- A style or workflow preference stated as an absolute ("never", "always", "do not") where breaking it is cheap to fix — rewrite as "prefer X when Y" or "match the surrounding code/pattern"; newer models do better with judgement than commandments
- Reserve hard directives for the guardrails above; a preference dressed as a law overconstrains the model

**MOVE out of CLAUDE.md** if the line is (treat these as presumptions, not automatic verdicts — a line that also carries a non-obvious guardrail stays):
- A persona or identity statement ("You are a...", "Your role is...", "Act as...") — belongs in SKILL.md where it sets tone for a specific task
- Describing what a tool does (Claude Code can read tool descriptions itself)
- File paths or directory structure (Claude Code can navigate the codebase)
- Step-by-step procedures for a specific task (belongs in the relevant SKILL.md or sub-skill file)
- Reference tables, schemas, or API docs (belongs in a docs/ file or README)
- Deep context or history (belongs in README or docs)
- Creative guidance aimed at the end user, not at Claude Code's behavior

**FLAG as conflict** if the line:
- Duplicates or contradicts a rule in a skill, a command file, or the global ~/.claude/CLAUDE.md. Cite both sides of every conflict — never flag from memory of one file. Distinguish three cases: a genuine contradiction (must be resolved), a redundant copy in files that load into the same context (keep the rule in the most specific place, delete the copy), and an intentional restatement in a file that only loads when invoked (a skill or command repeating a guardrail for its own scope is often deliberate — CLAUDE.md loads every session, an invoked command does not, so deleting the CLAUDE.md copy would remove the rule from ordinary sessions).

**Do this in three steps:**
1. Show me a table: each current line, its verdict (keep / rephrase / move / conflict), and where it moves to or what it becomes
2. Wait for my approval
3. Then rewrite CLAUDE.md: guardrails as one rule per line, preferences as judgement guidance, a one-line pointer left behind for anything that moved. Also create or update the destination files for anything that moved. Before rewriting, confirm the current CLAUDE.md is committed to git; if it is untracked or not in a repo, copy it to CLAUDE.md.bak first — this rewrite must pass its own hard-to-undo test.

The test for every line: "If Claude Code broke this rule because it didn't know about it, would the damage be immediate and hard to undo?" If yes it stays as a hard rule. If it's a preference, rephrase it as guidance. If Claude Code could figure it out from the codebase or a skill file, it moves.
