---
description: Convene a multi-model council (Codex + Gemini + an Opus subagent) on one question; seats are read-only consultants, you own the verdict
argument-hint: [question or scope]
disable-model-invocation: true
---

Convene a multi-model council on the question or scope given in $ARGUMENTS (if empty, ask
what the question is). Read `~/.claude/MODEL-PLAYBOOK.md` first — it defines the seats and
the one law: council members are consultants, you are the judge.

**1. Write the brief.** Distill the question into a self-contained brief in a scratchpad
file: what the repo/project is (2-3 lines), the specific question, the relevant code
excerpts inlined (the Antigravity seat cannot read files — it answers from the brief
alone), file paths for the seats that can read, constraints, and the exact output format
you want back. Excerpt integrity: generate inlined excerpts directly from disk with line
numbers (`nl -ba`), and if you claim a file is included in full, verify it actually is
before sending — a silently truncated "verbatim" copy poisons the file-blind seat.
Required output format for every seat: findings as a numbered list, each with evidence,
a confidence, and a `verified:` field — "read in the file" vs "inferred from the brief".
Ask seats that can read for file:line citations; ask the file-blind seat to cite section
names or the brief's line numbers, never repository line numbers it cannot see.
Pre-emit gate (put it in the brief verbatim): a finding must QUOTE the line(s) that
motivate it — a claim that field X is missing from module Y quotes the lines of Y where
X would live; "this pattern is unsafe" is not a finding without the line that makes it
unsafe here. A finding that cannot quote its motivating line is capped at low confidence
and reported as unverified, never as a defect. Second gate, same paragraph of the brief:
every finding names the test that would FALSIFY it — the input, state or command under
which the defect shows and the observation that would prove it absent. "If you cannot
construct one, the finding is too vague: drop it or downgrade it to info." The overseer
verifies findings in the file; this moves the burden upstream so that what arrives is
already checkable (bernstein's adversary role, 2026-08-22 raid).

**Precedents.** If the repo has an `AUDIT-PRECEDENTS.md` (check `DOCS/` and repo root),
inline it in every brief: it records false-positive classes already adjudicated in past
audits ("Supabase calls never throw — flag missing `.error` checks, not missing
try/catch") and hard exclusions. Seats must not re-report a listed class; a finding that
argues a precedent is wrong must say so explicitly and argue against the recorded reason.
After the verdict, offer to append any newly dismissed FP class to the file with a
one-line reason — the same false positive should never cost a second council.

If the repo (or your own setup) carries a file of domain-specific review
dimensions — infra and secrets for a security-scoped council, spend and
provider-contract surfaces for one over generative-media code — fold it into
the brief and state its confidence floor. Seats cannot see your machine, so
any such dimensions have to travel in the brief itself.
External models share nothing with this session, so the brief must stand alone. Never
include secrets, keys, or `.secrets/` contents — briefs leave the machine.

**2. Seat the council.** Run all seats in parallel; each gets the same brief and none
sees your own opinion (form yours, but keep it out of the brief). Only the seat-level
framing differs: the Codex and Claude seats also get read access, the Antigravity seat
gets nothing but the brief. Councils are read-only: never install or upgrade any tool
mid-council — if a seat's CLI is broken, missing, or rejects its model, record the seat
as empty and report the remediation below for the user to run separately.

- **Codex seat**:
  `codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort="high" -C <repo-root> - < <brief>`
  as a background Bash task. Read-only sandbox always — council members opine, they never
  edit. **Add `--skip-git-repo-check` whenever `-C` points outside a git repo** — a brief
  staged in the scratchpad is the normal case, and without the flag the seat dies instantly
  with "Not inside a trusted directory and --skip-git-repo-check was not specified" while
  the wrapper still reports exit 0. Check the seat's output is non-empty before counting it;
  a silently empty seat costs quorum and reads as agreement (2026-09-03).
  The effort pin matters: gpt-5.6-sol's own default is low, and without the pin the
  seat's depth silently depends on the local `~/.codex/config.toml`. `-sol` is the
  frontier tier (terra = balanced, luna = fast); the bare "gpt-5.6" the ChatGPT app
  displays is not a valid API slug. If the model is rejected, the fix (for the user, not
  mid-council) is: upgrade the CLI (`npm i -g @openai/codex@latest` — a stale CLI serves
  a stale model list), then pick the priority-1 slug from `~/.codex/models_cache.json`.
- **Antigravity seat (Gemini)**:
  `agy -p "$(cat <brief>)" --model gemini-3.1-pro-high --disable-slash-commands --sandbox --print-timeout 10m`
  as a background Bash task. `--disable-slash-commands` because briefs are data, not
  commands — without it, print mode may expand `/command` tokens inside the brief.
  Headless `agy` auto-denies every tool permission and `--sandbox` backs that up, so it
  answers from the brief alone — that is by design; NEVER pass
  `--dangerously-skip-permissions` (it would let an external model run arbitrary
  commands). If the model slug is rejected (agy self-updates), run `agy models` and take
  the current `*-pro-high` tier. If `agy` is absent, record the seat as empty (user
  installs with: `curl -fsSL https://antigravity.google/cli/install.sh | bash`).
- **Claude seat**: an Opus subagent (Agent tool, `model: opus`) with the same brief. Its
  prompt MUST contain this literal guard (the other seats are sandboxed mechanically;
  this one is only as read-only as its prompt): "You are a READ-ONLY consultant: do not
  edit, create, or delete any files, and run no state-changing commands." It must reach
  its view independently — same brief, no extra context.

Quorum is whatever answers; never block the council on one member, and note any seat that
errored or timed out. But name the result honestly: if fewer than two non-overseer seats
reported, say plainly that no cross-vendor cross-check happened and deliver it as a
single-consultant review, not a council.

**3. Deliberate.** When all seats have reported, synthesize:

- **Consensus** — findings raised by 2+ seats *that you then verified in the code
  yourself*. Agreement raises priority, never confidence — two models can share one
  wrong reading, and the file-blind seat echoing a claim it cannot check does not count
  toward the 2. Mark anything you could not verify as unverified.
- **Disputes** — where seats disagree, with who said what. Verify the load-bearing claim
  in the actual code before taking a side; a council member being confident is not
  evidence.
- **Your verdict** — what you'd actually do, with reasoning. Include anything you caught
  that every seat missed. Two sovereignty rules bound the verdict: cross-model agreement
  is a recommendation, never a mandate — seats agreeing is a reason to verify, not
  consent to act. And on questions of product taste or direction, present both sides
  and stop; never render your view as a pre-filled "assessment" column that frames one
  option as settled fact. The user fills in that column.

**4. Report** with per-seat attribution (model + one-line summary of its position), the
seat count, the consensus/dispute/verdict sections, and which seats were empty or
errored. Every finding in the report carries a disposition — `fixed`, `rejected: <reason>`
or `unverified` — and the `rejected` rows are the candidates for the AUDIT-PRECEDENTS
write-back offered under Precedents above; a council that ends without dispositions
leaves its false positives to be re-argued next time. Do not act on the verdict — fixes
and builds are a separate instruction from the user.
