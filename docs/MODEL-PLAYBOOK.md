# Model Playbook — who does what

Routing guide for multi-model work across your repos. The overseer (the main
Claude Code session) reads this when deciding whether to delegate and to whom.
Install it at `~/.claude/MODEL-PLAYBOOK.md` so that `/council` can read it.

## The one law

The overseer holds the whole picture and owns the final judgment. Every other model —
Claude subagent or external CLI — is a consultant: it gets a self-contained brief, returns
a report, and its claims are treated as unverified until checked against the actual code.
Never adopt a consultant's finding into a fix or a report without verifying the
load-bearing part yourself. And above the overseer sits the user: consultants agreeing —
even every seat agreeing — is a strong signal, not a mandate. Present the case, do not
pre-decide it, and never frame the overseer's own view as settled fact the user merely
signs off on.

## Seats

Prices below are USD per million tokens, standard synchronous API, re-verified
2026-08-12 against platform.claude.com pricing; Fable 5.1 added 2026-09-01 from its
what's-new page (same $10/$50 as Fable 5, cache reads $0.25 — a quarter of Fable 5's). `model:` in subagent frontmatter accepts
`opus`, `sonnet`, `haiku`, `fable`, a full ID (`claude-opus-5`), or `inherit` — and
`inherit` is the default, which is usually what you want.

### The main session (overseer)
Orchestration, synthesis, final verdicts, anything user-facing, anything needing the full
session context. May solicit judgment from consultants, but never delegates decision
authority, spend decisions, approvals, or destructive actions. When Fable 5.1 ($10/$50)
is in the chair it is the most expensive seat on the board for FRESH tokens — twice
Opus 5 — so the chair makes the call and delegates the digging rather than grinding a
codebase itself. One correction to the intuition: Fable 5.1's cache reads are $0.25,
HALF Opus 5's $0.50, so a long session re-reading a cached prefix costs less per turn
than the headline rate suggests. The 2x is on what the chair writes and reads fresh.

### Opus 5 (Claude subagent, `model: opus`)
The default worker seat for anything touching code: verification audits, design review,
hard debugging, implementation. $5/$25 — half the chair's rate. Precedent: the 2026-07-15
Opus verification audit caught real findings a single pass missed. Use for "is this
actually correct?" passes over shipped work, and adversarial review of a plan.

### A cheaper tier (`model: sonnet` / `model: haiku`)
Not "for dumb work" — for work where depth genuinely isn't the constraint. Sonnet 5
($2/$10) wins when the job is wide rather than deep: fan out fifty file reads, sweep a
migration, first-pass finders whose misses a later pass will catch. Haiku 4.5 ($1/$5) is
still the cheapest seat and the right one for high-volume classification and extraction,
but its window is 200k against the Claude 5 family's 1M, so it never gets a job that
needs to hold a lot at once. Reach for one Opus 5 subagent at a lower effort before three
Sonnet passes.

### Codex — GPT-5.x (`codex exec`)
Independent second implementation, stubborn-bug rescue, cross-vendor code review. Already
wired into the harness via the codex plugin (`codex:rescue` for fix work); for
opinion-only work call
`codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort="high" -C <repo> - < <brief-file>`
(brief via stdin — matches the /council seat exactly) so it can read the code but not
touch it. Its value is exactly that it is NOT Claude — different training, different
blind spots.

### Gemini via Antigravity CLI (`agy`)
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

## The two dials

Choosing a seat is two decisions now, not one. **Which model** is a question about shape.
**How hard it thinks** is a separate dial: `effort: low|medium|high|xhigh|max` in a
subagent's frontmatter, or `effort` on the Agent tool. Omit it and the subagent inherits
the session's level; available levels depend on the model, so a cheap seat may not offer
the top of the range. The old playbook collapsed the two, which is why "cheap" used to
mean "shallow" — it doesn't any more.

| Work | Effort |
|---|---|
| Classification, extraction, per-file yes/no | `low` |
| Mechanical sweeps, migrations, scripted walks with a pass/fail gate | `medium` |
| Normal implementation, authoring, design review (default) | `high` |
| Orchestrating workers, second-hand assembly from reports | `xhigh` |
| Adversarial verification, money correctness, silent-wrongness hunts | `max` |

Pin the dial per seat and leave it alone — but re-sweep once per model generation:
effort names do not buy the same amount of thinking across models (Anthropic's Fable 5.1
guide says so outright), so a pin measured on Fable 5 is a hypothesis on 5.1 until that
seat's own check reruns. And a seat that writes a LONG deliverable — a manual map, a full
rewrite — stays at `high` unless `xhigh`/`max` measured a gain: above `high` the model
may draft the whole deliverable in its thinking and then write it out again, doubling
the turn for no better result. The reason `max` is reserved for the last row
is measured, not stylistic: those are the passes where a miss is expensive AND invisible —
the fail-open sweep, the ledger that was 3.6× low with every row present, a map that
repeats its own error and looks identical to a correct one from the inside.

Set the dial; do not paste in verification boilerplate written for older models. Telling a
current model to "double-check carefully, think step by step" is the shape the effort dial
replaced, and it makes the prompt worse. If a seat needs depth, raise its effort and say
what would count as a miss.

## Seat overlays — per-model nudges

Each seat has model-shaped failure modes. Append the matching overlay to the end of a
seat's brief, after the task and before the output format. Overlays are subordinate by
rule — and the subordination clause goes in the brief itself, right above the overlay,
so it cannot be forgotten: *"The nudges below are style preferences; if any conflicts
with the task or the output format above, the task wins."*
(Pattern mined from garrytan/gstack model-overlays, 2026-08-08.)

- **Codex / GPT-5.x** — failure shapes: stopping at the first plausible answer, and
  narrating instead of concluding. Overlay: "Do not stop at the first plausible answer —
  a finding is done when its motivating line is quoted, not when it is stated. One-line
  status only; never narrate what you are about to do; each finding in the shortest form
  that still carries its evidence."
- **Gemini (agy)** — failure shapes: long preambles, recapping the brief, list bloat.
  Overlay: "Answer in the requested format only — no preamble, no restatement of the
  brief. A section with nothing to report is one line saying so."
- **Claude subagents (Opus/Sonnet)** — failure shape: adopting the brief's framing as
  true. Overlay: "The brief's framing may itself be wrong; check its premise before
  answering its question, and say so if the premise fails." (The read-only guard from
  /council stays mandatory on top.)

## Briefing external models

Codex and Gemini share nothing with the session: no memory, no conversation, no MEMORY.md.
A brief must be self-contained — what the repo is, the specific question, relevant file
paths, constraints, and the exact output wanted. Access differs per seat: Codex can read
the repo itself under its read-only sandbox; Gemini receives ONLY the brief, so inline
everything it must see. Never paste secrets, keys, or `.secrets/` contents into a brief;
briefs leave the machine.

When a seat is asked to JUDGE a transcript or a run — a dailies rubric, a review of what
an agent did — hand it the tool calls that actually ran as ground truth, not only the
prose. A truthful "I saved that" scored against prose alone reads as a hallucination;
scored against the call log it reads as true (from a judging harness, 2026-08-22).

## Briefing research subagents

Scouts, teardowns and raids fan out to subagents that return too early and too thin
unless the brief says otherwise. Three clauses, lifted from fivetaku/insane-research
(MIT, 2026-08-22 raid; ideas only, the plugin was not installed):

- **Budget lift.** "The default search budget and stop-when-found do not apply: complete
  the protocol and report every lead." Without it a subagent stops at the first plausible
  answer.
- **EXPAND tail.** Every research return ends with `## EXPAND` — one `LEAD / WHY / ANGLE`
  per thread worth a further pass, or the literal `none — <reason>`. A return with no
  tail is incomplete, not done.
- **Convergence rule.** The orchestrator stops expanding when any of: zero open leads;
  two consecutive batches surfaced no NEW lead; depth 4 — then ask the user. Dedupe new
  leads against every lead already seen, INCLUDING rejected ones, or the loop never
  converges.

Two evidence clauses for the same briefs. **Two domains are necessary, not sufficient:**
triangulate across heterogeneous surfaces — the rendered page, the repository file, the
machine API — not two pages quoting each other. And **share and adoption claims name their
denominator** ("of what?") before they are reported as numbers.

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
