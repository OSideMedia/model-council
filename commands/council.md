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
  edit. The effort pin matters: gpt-5.6-sol's own default is low, and without the pin the
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
  that every seat missed.

**4. Report** with per-seat attribution (model + one-line summary of its position), the
seat count, the consensus/dispute/verdict sections, and which seats were empty or
errored. Do not act on the verdict — fixes and builds are a separate instruction from
the user.
