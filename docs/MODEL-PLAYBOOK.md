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

Prices below are USD per million tokens, standard synchronous API, read raw from the
platform.claude.com pricing page on 2026-10-19
(saved as a local copy); windows from the models
overview the same day.

| Seat | Input | Output | Cache hit | 5m write | Window |
|---|---|---|---|---|---|
| Fable 5.1 | $10 | $50 | $0.25 | $12.50 | 1M |
| Opus 5.5 | $4 | $20 | $0.20 | $5 | 1M |
| Sonnet 5.5 | $2 | $10 | $0.10 | $2.50 | 1M |
| Haiku 5.5, prompt up to 100K | $0.10 | $0.50 | $0.01 | $0.125 | 1M |
| Haiku 5.5, prompt over 100K | $0.50 | $2.50 | $0.05 | $0.625 | |

Haiku's row is chosen per request on the whole prompt, cache reads included. A subagent's
context grows every turn, so a long Haiku job crosses 100K and pays the second row from
then on: in one walk test, about half the turns of a long review job did. It is
still an eighth of Opus on that row.

**Every agent file pins its model** by family alias in its frontmatter: `model: opus`,
`sonnet` or `haiku`. An alias follows its family to the
newest model, so a pin survives a generation bump. Never pin a full ID: model IDs live
in one file per repo. A file with no `model:` inherits the chair, so with Fable in the
chair every worker runs at 2.5x Opus.

### The main session (overseer)
Orchestration, synthesis, final verdicts, anything user-facing, anything needing the full
session context. May solicit judgment from consultants, but never delegates decision
authority, spend decisions, approvals, or destructive actions. When Fable 5.1 is in the
chair it is the most expensive seat on the board: 2.5x Opus 5.5 on fresh tokens and 1.25x
on cache hits. So the chair makes the call and delegates the digging rather than grinding
a codebase itself. The chair is never downgraded for cost; that is the user's call.

### Opus 5.5 (`model: opus`)
The default worker seat for anything touching code: builders, money code, verification
audits, design review, hard debugging, implementation, and every independent reader: a
fresh agent that judges a diff, a draft or another seat's verdict. A verification pass at
this seat has caught real findings a single pass missed. Use for "is
this actually correct?" passes over shipped work, and adversarial review of a plan.

### A cheaper tier (`model: sonnet` / `model: haiku`)
Not "for dumb work": for work where depth genuinely isn't the constraint. Sonnet 5.5 is
half Opus 5.5 on every line, cache hits included. It wins when the job is wide rather than
deep: fan out fifty file reads, sweep a migration, first-pass finders whose misses a later
pass will catch. An ad-hoc Agent-tool job with no agent
file of its own goes to Sonnet when it is a search, a doc read (fetching and summarising
documentation, not judging work) or a sweep: pass `model: "sonnet"` on the call. A job
that judges work is an independent reader and stays on Opus. Agent files carry their own
pins, set by the rule below. Haiku 5.5 is the cheapest seat, a fortieth of Opus on input
and output up to a 100K prompt, and it has the family's 1M window (Haiku 4.5 had 200K).
Reach for one Opus 5.5 subagent at a lower effort before three Sonnet passes.

A verification seat moves to a cheaper model only on a walk test: the same brief on each
model, a planted defect (or a real open bug proven to show first), criteria written before
any arm runs, and a move only when a second run repeats the first. In one such test, a
gate-checking agent moved to Haiku: all three models caught both planted defects with no
false finding, Haiku did it again on a second run, and its input cost was an eighth to a
fifth of Opus's. A UI flow-testing agent stayed on Opus: Haiku missed the target, and
Sonnet caught it once but not on the repeat. Output tokens were not measured (a subagent
transcript hides thinking), so those costs are the input side only. Every other seat stays
on Opus until its own test.

### Codex — GPT-6 / GPT-5.x (`codex exec`)
Independent second implementation, stubborn-bug rescue, cross-vendor code review. Fix
work can go through the codex plugin (`codex:rescue`) if you have it installed; for
opinion-only work call
`~/.claude/codex-seat.sh --sandbox read-only -c model_reasoning_effort="high" -C <repo> - < <brief-file>`
(brief via stdin — matches the /council seat exactly) so it can read the code but not
touch it. The wrapper is the ONE file that holds the Codex model IDs: its primary first,
and when Codex reports the usage window spent it re-runs the same brief on its fallback
and says so on stderr — never pass `-m` to it. Point every Codex caller you wire up (a
Stop hook, a plugin, an ad-hoc `codex exec`) at the same wrapper. The codex plugin does
not go through it: it leaves the model unset and inherits `~/.codex/config.toml`, so if
`/codex:rescue` dies on a usage limit the manual fallback is `/codex:rescue --model
<the wrapper's fallback slug> …`. Its value is exactly that it is NOT Claude — different
training, different blind spots.

**Which Codex tier for which job** (Standard speed always,
since Fast draws 2.5x on a subscription):

| Job | Model | How |
|---|---|---|
| First review of a code diff | GPT-6.1 Sol | the wrapper, `-c model_reasoning_effort="high"` |
| Re-read of a fix the reviewer already asked for | GPT-6.1 Sol | the wrapper, `-c model_reasoning_effort="medium"` |
| Docs- or comment-only diff, simple checks | GPT-6 Luna | `codex-seat.sh --light`, effort `"high"` |
| GPT-6 Astra | only when you ask for it by name | |

The council seat and any review hook always take the first row. They pin `high`
themselves and never pass `--light`; the medium and light rows are for reviews run by
hand. Callers set effort with `-c`, never the model: `--light` is how a caller picks the
light tier while its slug stays in the wrapper.

Why: on a subscription, review rounds on Astra at high effort spend the weekly usage
window fast. At the vendor's Standard rates the same tokens cost about 6x less on 6.1
Sol and about 100x less on Luna (a guide, not a forecast: a cheaper model can take more
steps). Briefs stay narrow either way: name the diff and the functions, not whole files,
and pipe long test output to its summary.

### Gemini via Antigravity CLI (`agy`)
Cross-vendor tiebreaker, alternative design perspective, and the one seat that watches
and listens. Google retired the old `@google/gemini-cli` OAuth for individual accounts on
2026-06-18; the supported terminal path is now the Antigravity CLI (`agy`, auths through
the Antigravity subscription, self-updates on launch). Always through the wrapper:
`~/.claude/agy-seat.sh < <brief-file>` for council seats, `--media <file>...` to have it
watch or listen, `--light` for quick text checks. The wrapper is the ONE file that holds
the Gemini model IDs (Argon for the seat and for media, Flash 3.8 for `--light`) and the
run shape; `--check` reads `agy models`, and its header lists the exit codes (non-zero =
the seat is empty). The seat named a Pro slug until 2026-10-18, when `agy models` listed
no Pro tier (the Gemini app still offers 3.1 Pro). The seat had been idle, so nobody
saw it break.

Measured 2026-10-18 (agy 1.4.2), and the reason the wrapper exists: headless agy denies
shell commands and reads outside its workspace, but its file viewer opens anything INSIDE
the folder it starts in, without asking. Launched from a repo it quoted the README;
through the wrapper, which starts it in a fresh empty folder, it could not. So the seat
sees the brief and nothing else: inline the relevant code. `@note.txt` or
`@/absolute/path` in a brief attaches nothing. agy tries to read the file, the read is
denied (it is outside the workspace), and the wrapper exits 4. A `--print-timeout` expiry
returns the partial answer with exit 0; the wrapper makes that exit 5. NEVER pass `--dangerously-skip-permissions` (the wrapper
refuses every caller argument).

**Where Gemini earns its keep: watching and listening.** Claude Code's Read tool takes
images and PDFs, and Codex CLI 0.163's `-i` takes images. Neither takes video or audio.
Gemini can check a Seedance take against its prompt, a reference clip's motion, a
tutorial cut against its script, or VO timing. In one test on 2026-10-18 (a synthetic
clip whose content could not be guessed), Argon high was exact on colour, direction,
speed, the on-screen words and their seconds, and a tone's seconds and Hz. That held
both in a .wav and inside the mp4. Flash low misplaced the .wav tone and could not hear
the mp4's, so media runs on Argon only. A long PDF in one pass looks like a second niche,
on the strength of one test the same day. Argon read a 120-page synthetic PDF in one call
and got all five needles: the page count, a code in the page-1 text, a flowchart drawn as
an image with no text layer (flow order, arrow direction, a circle's colour and corner), a
word buried on page 93, and a table cell on page 118. Claude's Read takes a PDF 20 pages
a call; that 120-page document went to Gemini in one. A call that size draws noticeably on
the Argon weekly limit, so, on cost grounds, send a manual's relevant chapters rather than
the whole manual. As a code reviewer it stays the tiebreaker, not the default. Council audits measured refuted
findings (2 of 6, 2 of 16), so every Gemini claim, media ones included, is a lead to
verify, never a verdict.
`agy -p /usage` prints the Antigravity meters: Gemini 5-hour and weekly, plus a separate
Argon weekly limit. They are not the Gemini app's meter (the reset times differ).
(`agy` also exposes claude-* and gpt-oss models; ignore them — Claude seats run as real
subagents and Codex covers OpenAI.) The Antigravity IDE itself stays manual-only.

## Availability fallback

When Codex, a council seat, or any review tool is unavailable —
usage limit, not installed, auth dead — the STEP still happens, with the strongest
available Claude: a fresh Opus/Fable subagent reads the raw diff (never the lane that
wrote it), and the result is labelled "fallback read (<seat> unavailable)". Use the real
seat the moment it is back; never skip the step, never wait for the seat. A council with
fewer than two external seats is a "single-consultant review" by name and still runs.
A Stop hook that runs a Codex review can name this fallback in its message when Codex is down, instead of going quiet.

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
the fail-open sweep, a spend ledger that under-counted with every row present, a map that
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
- **Claude subagents (Opus/Sonnet/Haiku)** — failure shape: adopting the brief's framing as
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

**A steer reaches only the agents that load it.** Probed 2026-09-27 (codegraph evaluation),
one self-report each from a general-purpose and an Explore subagent: neither had the MCP
servers' instructions; the general-purpose one had the user CLAUDE.md and the memory index;
the **Explore** one had neither, and Explore does most code search. Both saw `LSP` as a
deferred name only. Only the user CLAUDE.md was tested; a project CLAUDE.md is presumed to
travel the same way, unproven. So a rule that lives in CLAUDE.md or in an MCP server's
instructions also rides in the brief. For a code question in a TypeScript or Python repo,
the brief says: "load `LSP` with `ToolSearch select:LSP`; use `findReferences`,
`incomingCalls` and `goToDefinition` before grep for who-calls, where-used and definition
questions; grep stays right for strings, prose and config." For shell, `bash-language-server`
has no call hierarchy: `findReferences` and `goToDefinition` only. The two agents disagreed
on CLAUDE.md, so the probe can see PRESENT. Re-probe after a Claude Code upgrade.

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
