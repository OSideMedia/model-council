[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://github.com/OSideMedia/model-council/releases/tag/v1.0.0) [![License](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Platform](https://img.shields.io/badge/platform-Claude%20Code-purple)](https://claude.com/claude-code) [![Seats](https://img.shields.io/badge/seats-Claude%20%2B%20GPT%20%2B%20Gemini-black)](docs/MODEL-PLAYBOOK.md) [![Consultants](https://img.shields.io/badge/consultants-read--only-orange)](commands/council.md)

# Model Council

> One question. Three frontier models from three vendors. One judge.

`/council` is a Claude Code slash command that convenes a multi-model review board on
any question worth more than one opinion: an architecture decision, a pre-release audit,
a bug that survived two fix attempts. Your main Claude Code session writes one
self-contained brief, fans it out in parallel to **Codex (OpenAI)**, **Gemini (Google,
via the Antigravity CLI)**, and an **Opus subagent (Anthropic)** — then verifies their
claims against the actual code and delivers a consensus / disputes / verdict report.

The design premise: models from the same vendor share blind spots. Cross-vendor seats
disagree in useful ways — and a council is only as good as the judge, so every seat is a
**read-only consultant** and nothing becomes a "finding" until the overseer has verified
it in the code itself.

## Why this shape

Most multi-model setups either let several agents edit the same code (merge chaos) or
average their opinions (confidence laundering). This one is a court, not a committee:

- **Consultants never edit.** Codex runs in its read-only sandbox, Gemini answers from
  the brief alone with tool permissions denied, and the Claude seat carries a mandatory
  read-only guard in its prompt.
- **Consensus must be verified.** Two seats agreeing raises *priority*, never
  *confidence* — two models can share one wrong reading. A finding is only "consensus"
  after the overseer confirms it in the file. Echo votes from the file-blind seat don't
  count.
- **Degraded runs are named honestly.** If fewer than two consultant seats answer, the
  report says "single-consultant review", not "council".
- **Briefs are evidence-grade.** Excerpts are generated from disk with line numbers,
  and every finding carries a `verified:` field — "read in the file" vs "inferred from
  the brief" — so fabricated citations have nowhere to hide.

These rules aren't theoretical: this command has repeatedly caught one seat confidently
reporting a shell-injection "vulnerability" that an empirical test refuted in one line,
and fabricating file:line citations for files it never saw. The process is built to
absorb that failure mode.

## What's in the box

| File | What it does |
|---|---|
| `commands/council.md` | The `/council` slash command — brief, seats, deliberation, report |
| `commands/audit-claude-md.md` | Bonus: `/audit-claude-md`, a rule-by-rule CLAUDE.md tuner for the judgement-era models (guardrails stay hard, preferences become guidance, procedures move to skills) |
| `docs/MODEL-PLAYBOOK.md` | The routing doc — which model gets which job, how to brief external CLIs, when a council is worth it vs. one consultant |

## Requirements

- [Claude Code](https://claude.com/claude-code) — runs the overseer and the Opus seat. Works out of the box.
- [Codex CLI](https://github.com/openai/codex) (`npm i -g @openai/codex`) — the OpenAI seat. Optional; an absent seat is recorded and skipped.
- [Antigravity CLI](https://antigravity.google) (`agy`) — the Gemini seat. Optional; same graceful degradation.

A council convenes with whatever answers. Missing seats are reported, never silently
papered over.

## Install

```sh
cp commands/*.md ~/.claude/commands/
cp docs/MODEL-PLAYBOOK.md ~/.claude/
```

## Use

In any Claude Code session:

```
/council Is the caching layer in src/cache/ actually safe under concurrent writes?
```

The session writes the brief, seats the council in parallel, verifies the load-bearing
claims, and reports per-seat attribution, consensus, disputes, and a verdict. It does
**not** act on the verdict — fixes are a separate instruction, so you stay in the loop
between judgment and change.

### When to convene (from the playbook)

Worth a council: architecture decisions that are expensive to reverse, pre-release
audits of money-touching code, a bug that survived two fix attempts, "is this design
actually good?" before a big build.

Not worth it: anything one consultant covers — a verification pass (Opus), a second
implementation (Codex), a mechanical sweep (a fast model fanned out). The playbook has
the full routing table.

## Model pins

The command pins today's frontier tiers (`gpt-5.6-sol` at high reasoning effort,
`gemini-3.1-pro-high`) and documents the recovery path for when vendors rotate slugs:
`~/.codex/models_cache.json` for Codex, `agy models` for Gemini. Councils never install
or upgrade tooling themselves — a broken seat is reported with its fix for *you* to run.

## License

[MIT](LICENSE)
