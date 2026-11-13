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
excerpts inlined (the Antigravity seat starts in an empty folder and sees nothing but
the brief), file paths for the seats that can read, constraints, and the exact output format
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

**Pre-flight count.** Before any seat starts, write one line in the scratchpad (not the
brief, which leaves the machine) with two counts: the seats, one model run each, and the
verification, one read of the cited code by you for each finding you expect to carry
into step 3. Reserve the verification first: it happens inside the council and is what
turns a seat's claim into a finding. A fix, and the fresh reader it gets, come later and
only on a separate instruction (step 4), so they are not counted here. The budget is
whatever limit the user set for this council, in its own unit (runs, spend, a share of
their usage; a session cannot read its own meter), so price both counts in that unit;
with no limit set, write the count and cut nothing. When the limit cannot cover both
counts, drop a seat or narrow the scope, then recount the verification for what is left:
every finding still in scope keeps its read. Name the cut in the report; a council nobody
verified has spent its budget on claims (cloudflare/security-audit-skill, MIT, `c1c8a8c`, SKILL.md § Cost
budget, adapted 2026-10-25).

**2. Seat the council.** Run all seats in parallel; each gets the same brief and none
sees your own opinion (form yours, but keep it out of the brief). Only the seat-level
framing differs: the Codex and Claude seats also get read access, the Antigravity seat
gets nothing but the brief. Councils are read-only: never install or upgrade any tool
mid-council — if a seat's CLI is broken, missing, or rejects its model, record the seat
as empty and report the remediation below for the user to run separately.

- **Codex seat**:
  `~/.claude/codex-seat.sh --sandbox read-only -c model_reasoning_effort="high" -C <repo-root> - < <brief>`
  as a background Bash task. The wrapper is the one place the Codex model IDs live: it
  runs its primary model and, only when Codex answers "You've hit your usage limit",
  re-runs the same brief on its fallback and says so on stderr. Never pass `-m` yourself — the
  wrapper refuses it, because a caller-pinned model has no fallback. Read-only sandbox
  always — council members opine, they never edit. **Add `--skip-git-repo-check` whenever `-C` points outside a git repo** — a brief
  staged in the scratchpad is the normal case, and without the flag the seat dies instantly
  with "Not inside a trusted directory and --skip-git-repo-check was not specified" while
  the wrapper still reports exit 0. Check the seat's output is non-empty before counting it;
  a silently empty seat costs quorum and reads as agreement (2026-09-03).
  The effort pin matters: the models' own defaults are low or medium, and without the pin
  the seat runs at that default (the wrapper does not load the local
  `~/.codex/config.toml`). `codex debug
  models` lists the slugs this CLI is served (it is filtered per client version); the bare
  display names the ChatGPT app shows are not valid API slugs. A seat whose
  stderr says BOTH models are usage-limited is empty — the window was shared or spent;
  record it as such. If a model is rejected outright, the fix (for the user, not
  mid-council) is: `~/.claude/codex-seat.sh --check`, then a reviewed change of the
  wrapper's three model lines (primary, light, fallback) to listed slugs. Do not upgrade
  the CLI to get a newer list: the wrapper runs only on the CLI version it was verified
  on and exits 2 on any other, and a newer CLI needs its probe re-run, an independent
  review and explicit approval before that pin changes. A seat whose stderr says
  `codex-seat: refusing:` was refused by the wrapper with exit 2 (an argument outside its
  list, or a CLI version other than the verified one, named in that line); it counts as
  an empty seat.
- **Antigravity seat (Gemini)**:
  `~/.claude/agy-seat.sh < <brief>` as a background Bash task. The wrapper is the one
  place the Gemini model IDs live, and it fixes the run shape: `--disable-slash-commands`
  (briefs are data, not commands — without it, print mode may expand `/command` tokens
  inside the brief), `--sandbox`, and a fresh empty folder to start in. Headless `agy`
  denies shell commands, but its file viewer opens anything in the folder it starts in
  (measured 2026-10-18: launched from a repo, it quoted the README), so the empty folder
  is what makes the seat see the brief alone. The wrapper accepts no caller arguments,
  so `--dangerously-skip-permissions` (which would let an external model run arbitrary
  commands) and `--model` cannot reach agy. Any non-zero exit means the seat is empty,
  and stderr says why: a blank answer, an answer cut off by the 10-minute timeout, or
  agy's own error. Never count it as agreement. If the model is rejected
  (agy self-updates its catalog), run `~/.claude/agy-seat.sh --check` and edit the
  wrapper's model lines to a slug `agy models` lists. If `agy` is absent, record the
  seat as empty (user installs with:
  `curl -fsSL https://antigravity.google/cli/install.sh | bash`).
- **Claude seat**: the `council-seat` agent (Agent tool, `subagent_type: "council-seat"`)
  with the same brief and no extra context, so it reaches its view independently. Pass no
  `model` or `effort` on the call: the installed definition
  (`~/.claude/agents/council-seat.md`) pins Opus at high effort and declares only Read,
  Grep and Glob, so its declared list has no file-writing tool and no shell. A brief that
  needs git or shell output carries that output inline. Its prompt MUST still contain
  this literal guard: "You are a READ-ONLY consultant: do not edit, create, or delete any
  files, and run no state-changing commands."
  If `council-seat` is missing, shadowed or cannot be verified, the Claude seat is empty:
  say so in the report and never fall back to `general-purpose` or any other agent. An
  Agent call that answers "Agent type 'council-seat' not found" is that empty seat.
  **Run the shadow search first.** A project file that declares the same name replaces
  the installed definition without a warning, its tools and model included (measured on
  Claude Code 2.1.323: a project `.claude/agents/` file, one in a parent folder, and one
  in a folder added with `--add-dir` each took the seat over and ran with every tool).
  Run the block below from the session's working directory, and after `"$PWD"` list
  every added directory (`--add-dir`, `/add-dir`), each as an absolute path in quotes.
  Seat the agent only if the last line it prints is `council-seat shadow search: CLEAR`. A `NOT-CLEAR` line, an
  error, or no output at all is an empty seat; so is a session where you cannot tell
  which directories were added. Do not edit or remove a file the search names to get to
  CLEAR: report it.

  ```sh
  # council-seat shadow search: the Claude seat is seated only if the last line printed is CLEAR
  ( bad=0; live="$HOME/.claude/agents"
    no() { echo "NOT-CLEAR $*"; bad=1; }
    scan() {   # $1: an agents folder. Every .md under it is read, the installed seat file aside.
      out=$(find -L "$1" -type f -iname '*.md' ! -samefile "$live/council-seat.md" -exec awk '
        function verdict() {
          if (seen && (odd || !closed || n != 1 || tolower(base) ~ /council-seat/))
            print "NOT-CLEAR cannot rule out a council-seat definition: " file
        }
        FNR == 1 { verdict(); seen = 1; file = FILENAME; base = file; sub(/.*\//, "", base)
                   odd = ($0 != "---"); closed = 0; n = 0 }
        FNR > 1 && $0 == "---" { closed = 1 }
        tolower($0) ~ /council-seat/ { odd = 1 }
        FNR > 1 && !closed {
          if ($0 ~ /\\/) odd = 1
          key = $0; sub(/:.*/, "", key); gsub(/[^A-Za-z]/, "", key)
          if (tolower(key) == "name") n++
        }
        END { verdict() }
      ' {} + 2>&1) || no "the search itself failed in: $1 under $(pwd)"
      [ -z "$out" ] || { echo "$out"; no "see the line(s) above, in: $1 under $(pwd)"; }
      # awk cannot be trusted with these bytes (BSD awk cuts a line at a NUL), so no file may hold one
      out=$(find -L "$1" -type f -iname '*.md' -exec sh -c 'for f; do
        LC_ALL=C tr -d "\000\015" < "$f" | cmp -s - "$f" ||
          echo "NOT-CLEAR holds a NUL or a carriage return: $f"
      done' sh {} + 2>&1) || no "the byte check itself failed in: $1 under $(pwd)"
      [ -z "$out" ] || { echo "$out"; no "see the line(s) above, in: $1 under $(pwd)"; }
    }
    [ -z "${CLAUDE_CONFIG_DIR+set}" ] || no "CLAUDE_CONFIG_DIR is set, so the installed folder is not $live"
    LC_ALL=C awk '
      NR == 1 && $0 != "---" { bad = 1 }
      NR > 1 && !closed {
        if ($0 == "---") closed = 1
        else if ($0 == "name: council-seat") k["name"]++
        else if ($0 == "tools: Read, Grep, Glob") k["tools"]++
        else if ($0 == "model: opus") k["model"]++
        else if ($0 == "effort: high") k["effort"]++
        else if ($0 ~ /^description: [A-Za-z0-9 .,;\/-]+$/) k["description"]++
        else bad = 1
      }
      END { exit !(!bad && closed && k["name"] == 1 && k["tools"] == 1 && k["model"] == 1 &&
                   k["effort"] == 1 && k["description"] == 1) }
    ' "$live/council-seat.md" 2>/dev/null ||
      no "the installed seat is missing or is not the restricted definition: $live/council-seat.md"
    scan "$live"
    for start in "$PWD"; do
      case "$start" in /*) ;; *) no "not an absolute path: $start"; continue ;; esac
      for chain in -P -L; do   # the physical ancestors, then the ones the path spells
        cd "$chain" "$start" 2>/dev/null || { no "cannot enter: $start"; continue; }
        while :; do
          if [ -e .claude ] || [ -L .claude ]; then
            ls .claude > /dev/null 2>&1 || no "cannot read .claude under: $(pwd)"
            if [ -e .claude/agents ] || [ -L .claude/agents ]; then scan .claude/agents; fi
          fi
          case "$PWD" in / | //) break ;; esac
          cd "$chain" .. 2>/dev/null || { no "cannot go above: $(pwd)"; break; }
        done
      done
    done
    # The verdict is always the last line: a folder name printed above cannot stand in for it.
    if [ "$bad" = 0 ]; then echo "council-seat shadow search: CLEAR"
    else echo "council-seat shadow search: NOT-CLEAR"; exit 1; fi )
  ```

  The search first holds the installed definition to its exact frontmatter (the five
  lines, nothing added; the description may hold only letters, digits, spaces and
  `. , ; / -`, and no agent file may hold a NUL or a carriage return, so no byte can
  smuggle in another line), then reads every agent file
  in each `.claude/agents/` folder from the start directory up to the filesystem root,
  along the physical path and along the path as spelled when a symlink makes them differ.
  The installed folder is read the same way, with only the seat's own file set aside
  (told apart by identity, not by path), so a second file there declaring the name is
  refused too. Its last line
  is always its verdict, and a refusal also exits non-zero. It refuses any file it cannot rule out: one that
  does not open and close a frontmatter block, has no `name` line or more than one,
  carries a backslash escape in its frontmatter, or spells the seat's name anywhere in
  its text or its filename. A `.claude` folder it cannot read, a folder it cannot enter
  or leave, a failing `find` or `awk`, and a relocated config folder are each NOT-CLEAR.
  It is a line reader, not a YAML parser, so it errs toward an empty seat. It trusts
  `find`, `awk`, `tr`, `cmp`, `ls` and `sh` as the session's PATH finds them: one that is
  missing or fails outright is NOT-CLEAR, one that misreports is not caught. What it is:
  an instruction you carry out, not a runtime security boundary. Nothing stops a session from skipping it or
  naming another agent; a definition passed with `--agents` or by managed settings
  outranks the installed one and is not searched; and the harness can add tools of its
  own to a subagent's list. In the one background test of this seat (Claude Code 2.1.323)
  it added a provider-side `advisor` tool, which was not invoked: what that tool does and
  costs when invoked is unverified. No handback tool was added in that test, though one
  has been seen on other background agents. The added tools are not guaranteed to stay
  the same across versions. The seat reads whatever this session can read. Claim no more for it than: no
  file-writing tool and no shell in its declared list.

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

**4. Report.** Open with the roster: one line per seat, then the overseer on a line of its
own. The overseer is the judge, not a seat, and is never counted as one. A seat's line
holds four things and its one-line position:

- **Provider and seat**: OpenAI and the Codex seat, Google and the Gemini seat (the
  Antigravity seat above), Anthropic and the Claude seat.
- **Requested**: the model the seat was configured to run, and its effort where that is
  pinned, named as the place that holds the pin names it (a wrapper's model line, the
  agent definition).
- **Answered**: the model that answered, with one of four marks and the source behind
  it. `observed`: a record of the answer itself names the model, and you name that
  record. `stated by its CLI`: this run's output names the model the CLI was run with,
  but not from the answer. That is the Codex seat: the `model:` line of the header the
  Codex CLI prints comes before any answer, so it shows what was selected, and it is
  quoted only for a seat that answered. `pinned`: nothing in this run names the model,
  so the line repeats the configured pin, which is not independent evidence of what
  answered. That is the Gemini seat (its wrapper passes the model and a run's output does
  not name it) and the Claude seat (the agent definition asks for it). `unknown`: no
  source names it, so write `unknown`, never a guess. A configured model is never
  reported as observed, and neither is one a CLI only states.
- **Status**, one of:
  - `answered`.
  - `answered after model fallback`: only when the wrapper's stderr carries its
    `falling back to` line. Name both models. It is the same seat and the same provider.
  - `empty`, with the reason, and the reasons kept apart. Refused by its wrapper before
    any model ran: a stderr line starting `codex-seat: refusing:` or `agy-seat: refusing:`,
    quoted; exit 2 alone does not show a refusal. A model or CLI failure: both models
    usage-limited, a rejected model, an error exit. A blank or cut-off answer. A Claude
    seat that is missing, shadowed or could not be verified: it stays empty, and no other
    agent is seated in its place.
  - `replaced by a fallback read`: the playbook's stand-in reader did the step. It gets
    its own line under that label, with its own model. It is not the seat it stands in
    for, is never a result from that seat's provider, and does not count toward the two
    seats a council needs.

The overseer's line gives the session's model as the session states it, marked
`stated by the session`, or `unknown`. Keep the roster to these lines: the seats' raw
output is the detailed record, and it stays where it was written. Then give the seat
count (seats that answered, a model fallback included; never a fallback read), the
consensus/dispute/verdict sections, and which seats were empty or errored. Every finding
in the report carries a disposition — `fixed`, `rejected: <reason>`
or `unverified` — and the `rejected` rows are the candidates for the AUDIT-PRECEDENTS
write-back offered under Precedents above; a council that ends without dispositions
leaves its false positives to be re-argued next time. A lead reported as
`needs_validation` (below the confidence floor, naming the one fact that would settle it)
is not a finding: list it after the findings, with no disposition until that fact is
observed. A security-scoped council also
ends with a coverage table: each surface in scope looked at (by which seat, with the
file:line it read), not looked at (why), or deferred (to when), so its "clean" says what
it covered. Do not act on the verdict — fixes
and builds are a separate instruction from the user.
