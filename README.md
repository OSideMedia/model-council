[![Version](https://img.shields.io/badge/version-1.1.1-blue)](https://github.com/OSideMedia/model-council/releases/tag/v1.1.1) [![License](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Platform](https://img.shields.io/badge/platform-Claude%20Code-purple)](https://claude.com/claude-code) [![Seats](https://img.shields.io/badge/seats-Claude%20%2B%20GPT%20%2B%20Gemini-black)](docs/MODEL-PLAYBOOK.md) [![Consultants](https://img.shields.io/badge/consultants-read--only-orange)](commands/council.md)

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

## Staying current

The commands here are a published copy of ones that run live at `~/.claude` on the
author's machine, and a published copy rots quietly: between v1.0.0 and v1.1.0 the live
`/council` gained the falsification gate, the `AUDIT-PRECEDENTS` fold-in, two
sovereignty rules and per-finding dispositions, and this repo shipped none of them for
four weeks without a word. A tool that teaches an older, weaker process is worse than
one that is visibly old.

So the pair is now checked rather than remembered:

```sh
sh tests/check-upstream-sync.sh      # exits 1 on drift, prints the diff
sh tests/refresh-from-live.sh        # regenerates from live, then review git diff
sh tests/selftest-publicise.sh       # proves the redaction refuses; needs no live source
```

The first two run the same `tests/publicise.sh` transform, so "the check is green" and
"running the fixer changes nothing" are the same statement and the two cannot drift
apart. That transform is the *only* sanctioned difference between live and published,
and it does two jobs. It **redacts** the handful of spots that are true on one machine
and misleading in public — a fold-in of local review-dimension files (seats cannot read
your disk, and a public command should not tell them to try), a routing line pointing at
a private source repo, and two parentheticals asserting which CLIs are installed. And it
**refuses**: every redaction asserts the live wording it is anchored to, and every output
is scanned against a deny-list of tokens that must never ship.

The refusal is the load-bearing half. An unguarded transform anchored on live wording
silently does nothing the moment that wording is reworded — it exits 0 and emits the
un-redacted text, the sync gate reports STALE, and the fix it prescribes then *publishes*
that text and goes green. A guard whose repair step launders the leak is worse than no
guard, so a failed assertion aborts the refresh with every published file untouched, and
`tests/selftest-publicise.sh` proves it by moving an anchor and watching the refusal.

The deny-list itself is machine-local, and that is the point: a list of private strings
committed to a public repo publishes the exact strings it exists to withhold. The repo
ships only the format —

```sh
cp tests/publicise-deny.example ~/.claude/publicise-deny.txt   # then fill in your own
```

— and the transform refuses to run without one, rather than deciding a file is safe to
publish while having no idea what private means here. An absent live source reports
`UNKNOWN` and exits 2, never a pass.

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

## Contributing

Issues welcome. One structural thing to know before opening a PR: `commands/*.md` and
`docs/MODEL-PLAYBOOK.md` are **generated**. They are a redacted copy of files that run
live at `~/.claude` on the author's machine, and the next `tests/refresh-from-live.sh`
overwrites them wholesale — so a PR editing those files cannot be merged as-is even when
it is right, and merging it would only mean losing your change at the next release.

Open an issue instead: the fix goes in upstream and flows back down here. PRs against
`README.md`, `tests/`, or anything else in the tree are ordinary PRs.

## License

[MIT](LICENSE)
