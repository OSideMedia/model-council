# Model Playbook — who does what

Routing guide for multi-model work across your projects. The overseer (the main
Claude Code session) reads this when deciding whether to delegate and to whom. Live copy:
`~/.claude/MODEL-PLAYBOOK.md`; source of truth: this repo.

## The one law

The overseer holds the whole picture and owns the final judgment. Every other model —
Claude subagent or external CLI — is a consultant: it gets a self-contained brief, returns
a report, and its claims are treated as unverified until checked against the actual code.
Never adopt a consultant's finding into a fix or a report without verifying the
load-bearing part yourself.

## Seats

### The main session (overseer)
Orchestration, synthesis, final verdicts, anything user-facing, anything needing the full
session context. May solicit judgment from consultants, but never delegates decision
authority, spend decisions, approvals, or destructive actions.

### Opus (Claude subagent, `model: opus`)
Deep verification audits, design review, hard debugging passes — a slower, deeper model
reliably catches real findings a single fast pass misses. Use for: "is this actually
correct?" passes over shipped work, adversarial review of a plan.

### Sonnet (Claude subagent, `model: sonnet`)
Bulk mechanical work: parallel file sweeps, migrations, boilerplate, broad searches,
first-pass finders in review workflows. Cheap enough to fan out wide.

### Haiku (Claude subagent, `model: haiku`)
High-volume trivial work: classification, extraction, per-file yes/no questions.

### Codex — GPT-5.x (`codex exec`, installed)
Independent second implementation, stubborn-bug rescue, cross-vendor code review. For
opinion-only work call
`codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort="high" -C <repo> - < <brief-file>`
(brief via stdin — matches the /council seat exactly) so it can read the code but not
touch it. Its value is exactly that it is NOT Claude — different training, different
blind spots.

### Gemini via Antigravity CLI (`agy`, installed)
Cross-vendor tiebreaker and alternative design perspective. Google retired the old
`@google/gemini-cli` OAuth for individual accounts on 2026-06-18; the supported
terminal path is now the Antigravity CLI (`agy`, auths through the Antigravity
subscription, self-updates). Headless:
`agy -p "<brief>" --model gemini-3.1-pro-high --print-timeout 5m` — use
`gemini-3.1-pro-high` for council seats, a `gemini-3.6-flash-*` tier for quick checks.
Headless runs auto-deny all tool permissions, so the seat answers from the brief alone —
inline the relevant code in the brief. NEVER pass `--dangerously-skip-permissions`.
(`agy` also exposes claude-* and gpt-oss models; ignore them — Claude seats run as real
subagents and Codex covers OpenAI.) The Antigravity IDE itself stays manual-only.

## Briefing external models

Codex and Gemini share nothing with the session: no memory, no conversation, no MEMORY.md.
A brief must be self-contained — what the repo is, the specific question, relevant file
paths, constraints, and the exact output wanted. Access differs per seat: Codex can read
the repo itself under its read-only sandbox; Gemini receives ONLY the brief, so inline
everything it must see. Never paste secrets, keys, or `.secrets/` contents into a brief;
briefs leave the machine.

## When to convene a council (vs. just asking one consultant)

Council (`/council`) — multiple independent opinions, worth the cost:
- Architecture decisions that are expensive to reverse
- Pre-release audits of paid-lane / spend-touching code
- A bug that has survived two failed fix attempts
- "Is this design actually good?" before a big build

One consultant is enough:
- Second implementation of a well-specified piece → Codex
- Verification pass over finished work → Opus subagent
- Mechanical sweep → Sonnet fan-out

No delegation at all: trivial edits, questions answerable from context, anything where
reading the file yourself is faster than writing the brief.
