#!/bin/sh
# selftest-publicise — prove the redaction actually goes RED.
#
# tests/check-upstream-sync.sh needs the author's live ~/.claude and reports UNKNOWN
# without it, so it cannot run on a CI runner. This one can: every fixture is written
# here, nothing outside a temp directory is read or written.
#
# What it proves, in the order the failures actually happened:
#   1. HAPPY   — an anchored live file publicises cleanly and carries no private token.
#   2. RED     — reword a rule's anchor and publicise REFUSES, rather than silently
#                emitting the un-redacted paragraph (this is the regression: before the
#                assertions, this case exited 0 and printed the private text). Both ends
#                of every block: with only the opener asserted, rewording the closing
#                line left the skip running to end-of-file and shipped a gutted command.
#   3. RED     — a private token with no rule written for it is caught by the deny-list;
#                a basename this repo does not publish is refused outright.
#   4. RED     — refresh-from-live.sh WRITES NOTHING when the transform refuses. This is
#                the one that matters: the sync gate catches drift, but its prescribed
#                repair used to overwrite the published copy with whatever publicise
#                emitted, so a fail-open transform got laundered to green by the fixer.
#   5. RED     — a deny-list that is missing, empty, comments-only, CRLF-saved or
#                sloppily spaced refuses or still bites, instead of passing everything.
#   6. GATE    — check-upstream-sync.sh, run against the fixture tree: CLEAN after a
#                refresh, REFUSED (not STALE, and no "regenerate" advice) when the
#                transform refuses, advice that follows the refusal class, STALE on a
#                hand-edited published copy, and UNKNOWN with exit 2 when one live
#                source is missing — not only when all are.
#
# Usage: sh tests/selftest-publicise.sh
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
pass=0; fail=0

ok()   { pass=$((pass + 1)); echo "  ok    $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL  $1"; }

# --- fixtures: a minimal "live" tree carrying every anchor the rules expect ----------
# The pair set is tests/pairs.sh — the same table the fixer and the gate read. make_live
# writes a fixture for EVERY row and fails loudly if a row has none: the fixer used to
# know one more pair than this fixture tree did, and exited at the missing source before
# reaching the write the "fixer writes nothing" test exists to catch.
# shellcheck source=pairs.sh
. "$here/tests/pairs.sh"
mkdir -p "$work/live/commands" "$work/live/agents"

make_live() {
  cat > "$work/live/commands/council.md" <<'EOF'
---
description: fixture
---
Some portable preamble that must survive untouched.

For security-scoped councils, also fold the infra-first dimensions from
`~/.claude/ACME-PASSES.md` into the brief (secrets archaeology, CI/CD shapes,
LLM/spend surfaces, and the 8/10 confidence floor).
For councils over generative-media code (the PRIVATEPROJ ecosystem),
fold `~/.claude/REELS-PASSES.md` instead/additionally (spend surfaces, the
silent-wrongness taxonomy, and the pixels-or-payload evidence floor).
Trailing portable text that must survive untouched.
EOF
  cat > "$work/live/commands/audit-claude-md.md" <<'EOF'
A file with no redaction rules and nothing private in it.
EOF
  cat > "$work/live/MODEL-PLAYBOOK.md" <<'EOF'
# Model Playbook — who does what

Routing guide for multi-model work across all ~/Projects repos. The overseer (the main
Claude Code session) reads this when deciding whether to delegate and to whom. Live copy:
`~/.claude/MODEL-PLAYBOOK.md`; source of truth: private-source-repo.

Prices below are USD per million tokens, standard synchronous API, read raw from the
platform.claude.com pricing page on 2000-01-01
(`~/.claude/FAKEAUDIT/pricing.md`); windows from the models
overview the same day.

context grows every turn, so a long Haiku job crosses 100K and pays the second row from
then on: in the 2000-01-01 walk test 3 of 10 and 6 of 10 FAKEAGENT turns did. It is
still an eighth of Opus on that row.

**Every agent file pins its model** by family alias in its frontmatter: `model: opus`,
`sonnet` or `haiku` (FAKEOWNER's ruling, 2000-01-01). An alias follows its family to the
newest model.

on cache hits. So the chair makes the call and delegates the digging rather than grinding
a codebase itself. The chair is never downgraded for cost; that is FAKEOWNER's call.

### Opus 5 (Claude subagent, `model: opus`)
The default worker seat for anything touching code: verification audits, design review,
hard debugging, implementation, and every independent reader: a
fresh agent that judges a diff, a draft or another seat's verdict. Precedent: the
2000-01-01 Opus verification audit caught real findings a single pass missed. Use for "is
this actually correct?" passes over shipped work.

deep: fan out fifty file reads, sweep a migration, first-pass finders whose misses a later
pass will catch. Since 2000-01-01 (FAKEOWNER's ruling), an ad-hoc Agent-tool job with no agent
file of its own goes to Sonnet.

model, a planted defect, criteria written before
any arm runs, and a move only when a second run repeats the first. The 2000-01-01 test
(`~/.claude/FAKEAUDIT/`), input-side cost per arm:
| FAKEAGENT (PRIVATEPROJ) | caught both plants | `haiku` |
seat stays on Opus until its own test.

### Codex — GPT-6 / GPT-5.x (`codex exec`, installed)
Independent second implementation, stubborn-bug rescue, cross-vendor code review. Already
wired into the harness via the codex plugin (`codex:rescue` for fix work); for
opinion-only work call
`~/.claude/codex-seat.sh --sandbox read-only -C <repo> - < <brief-file>`
and says so on stderr — never pass `-m` to it. It is a read-only seat: it builds the
`codex exec` argv itself, ignores the user's Codex config, and refuses (exit 2) any
argument outside its short list and any CLI version it was not measured on (its header
has the list). The FAKEHOOK Stop hook goes through the same wrapper. The codex plugin does not: it leaves the model unset and inherits
`~/.codex/config.toml` (FAKEOWNER's default, shared with the FAKEAPP app), so if
`/codex:rescue` dies on a usage limit the manual fallback is `/codex:rescue --model
<the wrapper's fallback slug> …`. Its value is exactly that it is NOT Claude — different
training, different blind spots.

**Which Codex tier for which job** (FAKEOWNER's call, 2000-01-01; Standard speed always,
since Fast draws more):

| Astra | only when FAKEOWNER asks for it | |

The council seat and the FAKEHOOK hook always take the first row. They pin `high`
themselves.

Why: on 2000-01-01 the review rounds of one PR ran on Astra at high and took 99 points of
the FAKEPLAN weekly window in about two hours, at roughly 99 credits a point and 99 credits a
median round. At the vendor's Standard rates the same tokens cost about 6x less on 6.1
Sol and about 100x less on Luna.

### Gemini via Antigravity CLI (`agy`, installed)
Body.
the seat is empty). The seat named a Pro slug until 2000-01-01, when `agy models` listed
no Pro tier (the Gemini app still offers 3.1 Pro). It had not run since 01-01, so nobody
saw it break.
Gemini can check a FAKEMODEL take against its prompt, a FAKEKIT Converter kit's motion, a
tutorial cut against its script.
a call; that 120-page document went to Gemini in one. The call moved the Argon weekly
meter from 50% to 48%, so, on cost grounds, send a manual's relevant chapters rather than
the whole manual.

## Availability fallback

FAKEOWNER's rule, 2000-01-01. When Codex, a council seat, or any review tool is unavailable —
usage limit, not installed, auth dead — the STEP still happens, with the strongest
available Claude. Portable fallback prose that must survive untouched.
The FAKEHOOK Stop hook names this fallback in its systemMessage when Codex is down.

## The two dials

The reason `max` is reserved for the last row
is measured, not stylistic: those are the passes where a miss is expensive AND invisible —
the fail-open sweep, the FAKELEDGER that was 9.9× low with every row present, a map that
repeats its own error and looks identical to a correct one from the inside.

## Briefing

scored against the call log it reads as true (fakerepo `ops/judge.py`, 2026-08-22 raid).
EOF
  cat > "$work/live/codex-seat.sh" <<'EOF'
#!/usr/bin/env bash
# codex-seat.sh — fixture. Two comment lines carry a rule: the header and cli_words().
# spent, `codex exec` dies with "You've hit your usage limit" and every seat that pinned
# Astra — the /council seat, the FAKEHOOK Stop hook, ad-hoc `codex exec` calls —
# would simply go empty.
#
# PRIMARY since 2000-01-01 is GPT-6.1 Sol, FAKEOWNER's call after Codex review rounds used 50%
# of the FAKEPLAN weekly window in two hours on Astra. At Standard rates (developers.openai.com/
# codex/pricing) the same tokens cost ~6x less on 6.1 Sol. It needs CLI >= 0.163.0:
# 0.153.4's catalog did not list it. Astra is for when FAKEOWNER asks for it.
#
# the light tier (docs-only reviews); the
# fallback is the same. The council seat and the FAKEHOOK hook never pass it.
# FAKEHOOK.py cli_words() is the same rule in Python: keep the two in step.
# would hide the reason from an empty seat (ow-0a1b2c, 2000-01-01). The CLI's own words
  # 5c. a failed review whose TRANSCRIPT quotes the phrase is NOT a spent seat (ow-0a1b2c):
# flow-0a1b2c and ow-0a1b2c7 are not ledger ids.
#   -c web_search="disabled"   FAKEOWNER's call for the review seat; its effect on the real
#                              provider is not measured
  refuse "the read-only guarantees were measured on codex-cli $VERIFIED_CLI, and '$CODEX_BIN --version' answered exit $rc, $(shown "${out:0:80}"). Nothing was run. After a CLI upgrade: run 'python3 -I tests/codex-seat-probe.py' in fakerepo against the new CLI; if every row holds, edit the VERIFIED_CLI line in $0."
echo "fixture seat"
EOF
  cat > "$work/live/agy-seat.sh" <<'EOF'
#!/usr/bin/env bash
# agy-seat.sh — fixture. One rule: the header's last-run date, read off the author's logs.
# 2000-01-01 (agy 0.0.0) `agy models` listed no Pro tier (Argon and Flash only, though
# the Gemini app still offers 3.1 Pro). The seat had not run since 2000-01-01 (agy's own
# run logs), so nobody saw it break. Here the slugs live in one file, `--check` reads
# `agy models`, and the run shape is fixed:
echo "fixture agy seat"
EOF
  # The Claude seat's agent definition is published as it is installed (`norules`): the
  # frontmatter is what the harness and the council command's shadow search read, so a
  # transform that reworded it would publish a different seat. It is still deny-scanned.
  cat > "$work/live/agents/council-seat.md" <<'EOF'
---
name: council-seat
description: fixture seat
tools: Read, Grep, Glob
model: opus
effort: high
---

You are a READ-ONLY consultant. Fixture body that must survive untouched.
EOF
  for_each_pair fixture_present
}
fixture_present() {  # <live-rel> <published-rel> — every row in the table needs a fixture
  [ -f "$work/live/$1" ] || { echo "  FAIL  no fixture for pair '$1' — add it to make_live"; exit 1; }
}
make_live

# The deny-list is machine-local, so the selftest brings its own — which also proves
# the mechanism is data-driven rather than hardcoded. Every "private" token in the
# fixtures below is invented: this file is published too, so it must not spell the real
# ones any more than the transform may.
cat > "$work/deny" <<'EOF'
# fixture deny-list
ACME-PASSES
REELS-PASSES
private-source-repo
privateproj
fakerepo
FAKEHOOK
FAKEAPP
FAKELEDGER
FAKEOWNER
FAKEAUDIT
FAKEAGENT
FAKEPLAN
FAKEKIT
EOF
PUBLICISE_DENY="$work/deny"; export PUBLICISE_DENY

pub="$here/tests/publicise.sh"

# expect_refusal <label> <live-file> <sed-expr> <stderr-must-contain>
#   Mutates a fresh fixture with the sed expression (and proves the mutation changed
#   something — a no-op mutation would test nothing), then requires: non-zero exit, the
#   named text on stderr, and an EMPTY stdout — a refusal that emits half a file is a
#   file for a caller to publish by accident.
expect_refusal() {
  make_live
  sed "$3" "$2" > "$work/mutated" || { bad "$1: sed failed"; return; }
  if cmp -s "$work/mutated" "$2"; then bad "$1: the mutation changed nothing — the case tests nothing"; return; fi
  mv "$work/mutated" "$2"
  sh "$pub" "$2" > "$work/out.red" 2>"$work/err" && st=0 || st=$?
  if [ "$st" -eq 0 ]; then
    bad "$1: publicise exited 0 and emitted $(wc -l < "$work/out.red" | tr -d ' ') lines"
    return
  fi
  if ! grep -q -F -- "$4" "$work/err"; then
    bad "$1: refused (exit $st) but not for the expected reason: $(head -1 "$work/err")"
  elif [ -s "$work/out.red" ]; then
    bad "$1: refused (exit $st) but still wrote $(wc -l < "$work/out.red" | tr -d ' ') lines to stdout"
  else
    ok "$1: refused (exit $st), named '$4', emitted nothing"
  fi
}

# --- 1. HAPPY PATH -------------------------------------------------------------------
echo "1. happy path — anchored live files publicise cleanly"
happy_one() {  # <live-rel> <published-rel>
  if sh "$pub" "$work/live/$1" > "$work/out.${1##*/}" 2>"$work/err"; then
    ok "${1##*/} transformed"
  else
    bad "${1##*/} should have transformed: $(cat "$work/err")"
  fi
}
for_each_pair happy_one
# The output must carry NONE of the private tokens...
for token in ACME-PASSES REELS-PASSES private-source-repo privateproj fakerepo FAKEHOOK FAKEAPP FAKELEDGER FAKEOWNER \
             FAKEAUDIT FAKEAGENT FAKEPLAN FAKEKIT; do
  if grep -qi -F -- "$token" "$work"/out.* 2>/dev/null; then
    bad "private token '$token' survived into published output"
  else
    ok "'$token' absent from published output"
  fi
done
# ...and must keep the portable text either side of a redacted paragraph.
if grep -q "Trailing portable text that must survive untouched." "$work/out.council.md" \
   && grep -q "Some portable preamble that must survive untouched." "$work/out.council.md"; then
  ok "text either side of the redaction survives"
else
  bad "the transform ate text it should have passed through"
fi

# The Claude seat's agent definition must come out byte for byte: its frontmatter is the
# restriction, and the council command's shadow search holds the installed file to it.
if cmp -s "$work/live/agents/council-seat.md" "$work/out.council-seat.md"; then
  ok "council-seat.md is published unchanged"
else
  bad "the transform changed council-seat.md, or did not publish it"
fi

# The precedent redaction must drop the private name and KEEP the prose before it.
if grep -q "^scored against the call log it reads as true (from a judging harness" \
     "$work/out.MODEL-PLAYBOOK.md"; then
  ok "precedent citation keeps its claim, loses the private repo name"
else
  bad "precedent redaction ate the sentence or did not fire"
fi

# The machine-state blocks must come out as portable advice, not as holes.
if grep -q "wired into the harness" "$work/out.MODEL-PLAYBOOK.md"; then
  bad "the 'already wired into the harness' claim reached the output"
elif grep -q "if you have it installed" "$work/out.MODEL-PLAYBOOK.md"; then
  ok "plugin wiring becomes 'if you have it installed'"
else
  bad "plugin-wiring rule removed the claim but wrote no replacement"
fi
if grep -q "Point every Codex caller you wire up" "$work/out.MODEL-PLAYBOOK.md" \
   && grep -q "^Opus verification audit\|has caught real findings a single pass missed" "$work/out.MODEL-PLAYBOOK.md" \
   && grep -q "a spend ledger that under-counted" "$work/out.MODEL-PLAYBOOK.md"; then
  ok "stop-hook, precedent and ledger blocks carry their portable replacements"
else
  bad "a machine-state block lost its replacement text"
fi
# The availability-fallback lines: the owner attribution and the named hook go, the
# portable prose between them stays.
if grep -q "^When Codex, a council seat, or any review tool is unavailable —$" "$work/out.MODEL-PLAYBOOK.md" \
   && grep -q "^A Stop hook that runs a Codex review can name this fallback in its message when Codex is down, instead of going quiet\.$" "$work/out.MODEL-PLAYBOOK.md" \
   && grep -q "^available Claude\. Portable fallback prose that must survive untouched\.$" "$work/out.MODEL-PLAYBOOK.md"; then
  ok "availability fallback: owner line and hook line replaced, the paragraph between them intact"
else
  bad "availability-fallback rules misfired: $(grep -n -A5 '^## Availability fallback' "$work/out.MODEL-PLAYBOOK.md" | tr '\n' '|')"
fi
if grep -q "any hook you point at Codex" "$work/out.codex-seat.sh" \
   && grep -q '^echo "fixture seat"$' "$work/out.codex-seat.sh"; then
  ok "codex-seat header names no particular hook; the code below it is untouched"
else
  bad "codex-seat header rule misfired or ate the script body"
fi
if grep -q '^# Any hook that re-implements cli_words() (in Python, say) must keep the two in step\.$' "$work/out.codex-seat.sh" \
   && ! grep -q 'FAKEHOOK' "$work/out.codex-seat.sh"; then
  ok "codex-seat cli_words() line names no particular hook"
else
  bad "seat/cli-words-twin misfired: $(grep -n 'cli_words' "$work/out.codex-seat.sh" | tr '\n' '|')"
fi
# The 2026-10-24 rules: each private line comes out as its portable replacement, and the
# prose either side of a block survives. Whole lines, matched as fixed strings.
has_line() { grep -q -x -F -- "$2" "$work/out.$1"; }
missing=""
for want in \
  "(saved as a local copy); windows from the models" \
  "overview the same day." \
  "then on: in one walk test, about half the turns of a long review job did. It is" \
  '`sonnet` or `haiku`. An alias follows its family to the' \
  "a codebase itself. The chair is never downgraded for cost; that is the user's call." \
  "fresh agent that judges a diff, a draft or another seat's verdict. A verification pass at" \
  'this actually correct?" passes over shipped work.' \
  "pass will catch. An ad-hoc Agent-tool job with no agent" \
  "gate-checking agent moved to Haiku: all three models caught both planted defects with no" \
  "on Opus until its own test." \
  'and says so on stderr — never pass `-m` to it. It is a read-only seat: it builds the' \
  "has the list). Point every Codex caller you wire up (a Stop hook, a plugin, an ad-hoc" \
  "<the wrapper's fallback slug> …\`. Its value is exactly that it is NOT Claude — different" \
  "training, different blind spots." \
  "**Which Codex tier for which job** (Standard speed always," \
  "| GPT-6 Astra | only when you ask for it by name | |" \
  'The council seat and any review hook always take the first row. They pin `high`' \
  "Why: on a subscription, review rounds on Astra at high effort spend the weekly usage" \
  "window fast. At the vendor's Standard rates the same tokens cost about 6x less on 6.1" \
  "Sol and about 100x less on Luna." \
  "no Pro tier (the Gemini app still offers 3.1 Pro). The seat had been idle, so nobody" \
  "saw it break." \
  "Gemini can check a Seedance take against its prompt, a reference clip's motion, a" \
  "a call; that 120-page document went to Gemini in one. A call that size draws noticeably on" \
  "the Argon weekly limit, so, on cost grounds, send a manual's relevant chapters rather than" \
  "the whole manual."; do
  has_line MODEL-PLAYBOOK.md "$want" || missing="$missing [$want]"
done
for want in \
  "# PRIMARY is GPT-6.1 Sol: on a subscription, review rounds on Astra at high effort spend" \
  "# not list it. Use Astra only when you ask for it by name." \
  "# fallback is the same. The council seat and any review hook never pass it." \
  '#   -c web_search="disabled"   chosen for the review seat; its effect on the real' \
  "#                              provider is not measured" \
  '  refuse "the read-only guarantees were measured on codex-cli $VERIFIED_CLI, and '"'"'$CODEX_BIN --version'"'"' answered exit $rc, $(shown "${out:0:80}"). Nothing was run. After a CLI upgrade: this published copy cannot be re-verified from here, because the probe the guarantees were measured with (codex-seat-probe.py) is kept with the wrapper'"'"'s source and not in this repository. Install the verified version ('"'"'npm i -g @openai/codex@$VERIFIED_CLI'"'"') or take a later release of this wrapper that was verified on the newer CLI."'; do
  has_line codex-seat.sh "$want" || missing="$missing [$want]"
done
if [ -z "$missing" ]; then
  ok "2026-10-24 rules: every replacement line present, the prose either side intact"
else
  bad "2026-10-24 rules misfired, missing:$missing"
fi
missing=""
for want in \
  "# the Gemini app still offers 3.1 Pro). The seat had been idle, so nobody saw it break." \
  "# Here the slugs live in one file, \`--check\` reads" \
  "# \`agy models\`, and the run shape is fixed:" \
  'echo "fixture agy seat"'; do
  has_line agy-seat.sh "$want" || missing="$missing [$want]"
done
if [ -z "$missing" ] && ! grep -q 'had not run since' "$work/out.agy-seat.sh"; then
  ok "agy/last-run: the date is gone, the header and body either side intact"
else
  bad "agy/last-run misfired, missing:$missing"
fi


# --- 2. RED: a reworded anchor must REFUSE, not silently pass the private text --------
echo "2. red — reworded OPENING anchors refuse (the original fail-open regression)"
# "also fold" -> "fold in": an ordinary edit, and enough to miss the anchor.
expect_refusal "council opener reworded" "$work/live/commands/council.md" \
  's/^For security-scoped councils, also fold the infra-first dimensions from$/For security-scoped councils, fold in the infra-first dimensions from/' \
  "council/local-dimensions"
expect_refusal "playbook heading reworded" "$work/live/MODEL-PLAYBOOK.md" \
  's/^### Codex — GPT-6 \/ GPT-5\.x (`codex exec`, installed)$/### Codex — GPT-6 \/ GPT-5.x (`codex exec`, available)/' \
  "playbook/codex-installed"
expect_refusal "precedent anchor reworded" "$work/live/MODEL-PLAYBOOK.md" \
  's/^scored against the call log it reads as true (/scored against the call log it reads true (/' \
  "playbook/judge-precedent"

echo "2b. red — reworded TERMINATING anchors refuse (before: exit 0 and the rest of the file gone)"
# "floor)." -> "floor.)": one transposed character, and the skip used to run to EOF.
expect_refusal "council terminator reworded" "$work/live/commands/council.md" \
  's/pixels-or-payload evidence floor)\.$/pixels-or-payload evidence floor.)/' \
  "council/local-dimensions (terminating anchor)"
expect_refusal "playbook header terminator reworded" "$work/live/MODEL-PLAYBOOK.md" \
  's/; source of truth:/; source of truth —/' \
  "playbook/routing-header (terminating anchor)"

echo "2b'. red — every machine-state rule refuses when either of its anchors moves"
expect_refusal "opus-precedent opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/verdict\. Precedent: the$/verdict. Precedent — the/' \
  "playbook/opus-precedent (opening anchor)"
expect_refusal "opus-precedent terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/ Opus verification audit caught real findings/ Opus verification audit found real findings/' \
  "playbook/opus-precedent (terminating anchor)"
expect_refusal "codex-plugin-wired opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/cross-vendor code review\. Already$/cross-vendor code review. It is already/' \
  "playbook/codex-plugin-wired (opening anchor)"
expect_refusal "codex-plugin-wired terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^opinion-only work call$/opinion-only work, call/' \
  "playbook/codex-plugin-wired (terminating anchor)"
expect_refusal "stop-hook-config opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/never pass `-m` to it\. It is a read-only seat: it builds the$/never pass `-m` to it — a read-only seat: it builds the/' \
  "playbook/stop-hook-config (opening anchor)"
expect_refusal "stop-hook-config terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/`\. Its value is exactly that it is NOT Claude — different$/`. Its value is precisely that it is NOT Claude — different/' \
  "playbook/stop-hook-config (terminating anchor)"
expect_refusal "ledger-incident opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/^is measured, not stylistic:/is measured, not stylistic —/' \
  "playbook/ledger-incident (opening anchor)"
expect_refusal "ledger-incident terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^repeats its own error and looks identical/repeats its own error, looking identical/' \
  "playbook/ledger-incident (terminating anchor)"
expect_refusal "seat stop-hook-mention opener" "$work/live/codex-seat.sh" \
  's/^# spent, `codex exec` dies with/# spent, `codex exec` fails with/' \
  "seat/stop-hook-mention (opening anchor)"
expect_refusal "seat stop-hook-mention terminator" "$work/live/codex-seat.sh" \
  's|^# Astra — the /council seat, the |# Astra: the /council seat, the |' \
  "seat/stop-hook-mention (terminating anchor)"
expect_refusal "seat cli-words-twin" "$work/live/codex-seat.sh" \
  's/ is the same rule in Python: keep/ is the same rule, in Python: keep/' \
  "seat/cli-words-twin"

echo "2b''. red — the availability-fallback line rules refuse when either end of their anchor moves"
expect_refusal "fallback-owner, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/rule, 2000-01-01\. When Codex,/rule, 2000-01-01: when Codex,/' \
  "playbook/fallback-owner"
expect_refusal "fallback-owner, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/any review tool is unavailable —$/any review tool is unavailable:/' \
  "playbook/fallback-owner"
expect_refusal "fallback-stop-hook, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/Stop hook names this fallback/Stop hook mentions this fallback/' \
  "playbook/fallback-stop-hook"
expect_refusal "fallback-stop-hook, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/in its systemMessage when Codex is down\.$/in its systemMessage when Codex is offline./' \
  "playbook/fallback-stop-hook"

echo "2b'''. red — every 2026-10-24 rule refuses when either end of its anchor moves"
expect_refusal "pricing-source, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's|^(`~/\.claude/FAKEAUDIT/pricing\.md`)|[`~/.claude/FAKEAUDIT/pricing.md`]|' \
  "playbook/pricing-source"
expect_refusal "pricing-source, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's|); windows from the models$|); window from the models|' \
  "playbook/pricing-source"
expect_refusal "haiku-walk-agent, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^then on: in the 2000-01-01 walk test/then on, in the 2000-01-01 walk test/' \
  "playbook/haiku-walk-agent"
expect_refusal "haiku-walk-agent, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/ turns did\. It is$/ turns did, and it is/' \
  "playbook/haiku-walk-agent"
expect_refusal "pin-ruling, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^`sonnet` or `haiku` (FAKEOWNER/`sonnet`, or `haiku` (FAKEOWNER/' \
  "playbook/pin-ruling"
expect_refusal "pin-ruling, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/An alias follows its family to the$/An alias tracks its family to the/' \
  "playbook/pin-ruling"
expect_refusal "chair-call, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^a codebase itself\. The chair is never/a codebase itself: the chair is never/' \
  "playbook/chair-call"
expect_refusal "chair-call, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/that is FAKEOWNER.s call\.$/that is FAKEOWNER'"'"'s decision./' \
  "playbook/chair-call"
expect_refusal "sonnet-ruling, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^pass will catch\. Since 2000-01-01/pass will catch. From 2000-01-01/' \
  "playbook/sonnet-ruling"
expect_refusal "sonnet-ruling, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/an ad-hoc Agent-tool job with no agent$/an ad-hoc Agent-tool job without an agent/' \
  "playbook/sonnet-ruling"
expect_refusal "walk-test-table opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/repeats the first\. The 2000-01-01 test$/repeats the first. The 2000-01-01 trial/' \
  "playbook/walk-test-table (opening anchor)"
expect_refusal "walk-test-table terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^seat stays on Opus until its own test\.$/seat stays on Opus until it is tested./' \
  "playbook/walk-test-table (terminating anchor)"
expect_refusal "codex-tier-owner, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^\*\*Which Codex tier for which job\*\*/**Which Codex tier for what job**/' \
  "playbook/codex-tier-owner"
expect_refusal "codex-tier-owner, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/; Standard speed always,$/; Standard speed, always,/' \
  "playbook/codex-tier-owner"
expect_refusal "astra-row, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^| Astra | only when/| Astra | only if/' \
  "playbook/astra-row"
expect_refusal "astra-row, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/asks for it | |$/asks for it | — |/' \
  "playbook/astra-row"
expect_refusal "tier-hook, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^The council seat and the FAKEHOOK hook always/The council seat and the FAKEHOOK hook both/' \
  "playbook/tier-hook"
expect_refusal "tier-hook, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/first row\. They pin `high`$/first row; they pin `high`/' \
  "playbook/tier-hook"
expect_refusal "usage-incident opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/^Why: on 2000-01-01 the review rounds/Why: on 2000-01-01 review rounds/' \
  "playbook/usage-incident (opening anchor)"
expect_refusal "usage-incident terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^median round\. At the vendor/median round. At the provider/' \
  "playbook/usage-incident (terminating anchor)"
expect_refusal "media-projects, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^Gemini can check a FAKEMODEL take/Gemini checks a FAKEMODEL take/' \
  "playbook/media-projects"
expect_refusal "media-projects, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/kit.s motion, a$/kit motion, a/' \
  "playbook/media-projects"
expect_refusal "argon-meter opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/The call moved the Argon weekly$/The call moved the weekly Argon/' \
  "playbook/argon-meter (opening anchor)"
expect_refusal "argon-meter terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^meter from 50% to 48%, so,/meter from 50% to 48% so,/' \
  "playbook/argon-meter (terminating anchor)"
expect_refusal "seat primary-note opener" "$work/live/codex-seat.sh" \
  's/^# PRIMARY since 2000-01-01 is GPT-6\.1 Sol,/# PRIMARY since 2000-01-01: GPT-6.1 Sol,/' \
  "seat/primary-note (opening anchor)"
expect_refusal "seat primary-note terminator" "$work/live/codex-seat.sh" \
  's/Astra is for when FAKEOWNER asks for it\.$/Astra is for FAKEOWNER to ask for./' \
  "seat/primary-note (terminating anchor)"
expect_refusal "seat light-hook" "$work/live/codex-seat.sh" \
  's/hook never pass it\.$/hook never passes it./' \
  "seat/light-hook"
# The read-only seat (2026-11): a comment naming the owner, and the version-gate message
# naming a private repo. The message keeps the probe's file name: the wrapper's own
# selftest requires it in the refusal.
expect_refusal "seat web-search-owner, start side" "$work/live/codex-seat.sh" \
  's/^#   -c web_search="disabled"   FAKEOWNER/#   -c web_search=disabled   FAKEOWNER/' \
  "seat/web-search-owner"
expect_refusal "seat web-search-owner, end side" "$work/live/codex-seat.sh" \
  's/call for the review seat; its effect on the real$/call for the review seat: its effect on the real/' \
  "seat/web-search-owner"
expect_refusal "seat version-gate-probe, start side" "$work/live/codex-seat.sh" \
  's/^  refuse "the read-only guarantees were measured on/  refuse "the read-only guarantees were proven on/' \
  "seat/version-gate-probe"
expect_refusal "seat version-gate-probe, the probe command" "$work/live/codex-seat.sh" \
  's/in fakerepo against the new CLI;/inside fakerepo against the new CLI;/' \
  "seat/version-gate-probe"
expect_refusal "seat version-gate-probe, end side" "$work/live/codex-seat.sh" \
  's/edit the VERIFIED_CLI line in \$0\."$/change the VERIFIED_CLI line in $0."/' \
  "seat/version-gate-probe"
expect_refusal "seat-last-run, start side" "$work/live/MODEL-PLAYBOOK.md" \
  's/^no Pro tier (the Gemini app/no Pro tier (though the Gemini app/' \
  "playbook/seat-last-run"
expect_refusal "seat-last-run, end side" "$work/live/MODEL-PLAYBOOK.md" \
  's/had not run since 01-01, so nobody$/had not run since 01-01; nobody/' \
  "playbook/seat-last-run"
expect_refusal "agy last-run opener" "$work/live/agy-seat.sh" \
  's/The seat had not run since 2000-01-01 (agy.s own$/The seat last ran on 2000-01-01 (agy'"'"'s own/' \
  "agy/last-run (opening anchor)"
expect_refusal "agy last-run terminator" "$work/live/agy-seat.sh" \
  's/^# run logs), so nobody saw it break\./# run logs), and nobody saw it break./' \
  "agy/last-run (terminating anchor)"

echo "2c. red — anchors present but out of order refuse (the awk's own guard)"
make_live
# Move the council terminator ABOVE its opener: grep finds both, the block never closes.
# Two passes over the file — the terminator has to be known before the opener is reached.
awk '
  NR == FNR { if ($0 ~ /pixels-or-payload evidence floor\)\.$/) held = $0; next }
  /^For security-scoped councils, also fold/ { print held }
  /pixels-or-payload evidence floor\)\.$/ { next }
  { print }
' "$work/live/commands/council.md" "$work/live/commands/council.md" > "$work/mutated" \
  && mv "$work/mutated" "$work/live/commands/council.md"
grep -q "pixels-or-payload evidence floor)\.$" "$work/live/commands/council.md" \
  || bad "out-of-order fixture lost its terminator — the case would test the wrong thing"
if sh "$pub" "$work/live/commands/council.md" > "$work/out.red" 2>"$work/err"; then
  bad "out-of-order anchors: publicise exited 0 and emitted $(wc -l < "$work/out.red" | tr -d ' ') lines"
else
  if grep -q "did not open and close" "$work/err" && [ ! -s "$work/out.red" ]; then
    ok "out-of-order anchors: refused by the block guard, emitted nothing"
  else
    bad "out-of-order anchors: refused for another reason or wrote output: $(head -1 "$work/err")"
  fi
fi

echo "2d. red — a block whose anchors an earlier rule swallowed refuses (never entered)"
make_live
# Move opus-precedent's opener and terminator INSIDE the routing-header block: grep still
# finds both in the live file, the header rule consumes them, and the opus rule's awk
# must notice it never entered its block rather than exit 0 with the text gone.
awk '
  NR == FNR { if ($0 ~ /^fresh agent that judges a diff/) a = $0
              if ($0 ~ /^[0-9-]+ Opus verification audit caught/) b = $0; next }
  /^fresh agent that judges a diff/ || /^[0-9-]+ Opus verification audit caught/ { next }
  { print }
  /^Routing guide for multi-model work/ { print a; print b }
' "$work/live/MODEL-PLAYBOOK.md" "$work/live/MODEL-PLAYBOOK.md" > "$work/mutated" \
  && mv "$work/mutated" "$work/live/MODEL-PLAYBOOK.md"
grep -q "^2000-01-01 Opus verification audit caught" "$work/live/MODEL-PLAYBOOK.md" \
  || bad "swallowed-block fixture lost its anchors — the case would test the wrong thing"
sh "$pub" "$work/live/MODEL-PLAYBOOK.md" > "$work/out.red" 2>"$work/err" && st=0 || st=$?
if [ "$st" -eq 0 ]; then
  bad "swallowed block: publicise exited 0 (the opus text silently vanished into the header rule)"
elif grep -q "playbook/opus-precedent" "$work/err" && grep -q "did not open and close" "$work/err" && [ ! -s "$work/out.red" ]; then
  ok "swallowed block: refused by the never-entered guard, named the rule, emitted nothing"
else
  bad "swallowed block: refused for another reason: $(head -1 "$work/err")"
fi

echo "2e. red — a line rule whose anchor an earlier block consumed refuses (grep found it, awk did not)"
make_live
awk '
  NR == FNR { if ($0 ~ /^### Codex — GPT-6/) a = $0; next }
  /^### Codex — GPT-6/ { next }
  { print }
  /^Routing guide for multi-model work/ { print a }
' "$work/live/MODEL-PLAYBOOK.md" "$work/live/MODEL-PLAYBOOK.md" > "$work/mutated" \
  && mv "$work/mutated" "$work/live/MODEL-PLAYBOOK.md"
grep -q "^### Codex — GPT-6" "$work/live/MODEL-PLAYBOOK.md" \
  || bad "consumed-line fixture lost its anchor — the case would test the wrong thing"
sh "$pub" "$work/live/MODEL-PLAYBOOK.md" > "$work/out.red" 2>"$work/err" && st=0 || st=$?
if [ "$st" -eq 0 ]; then
  bad "consumed line: publicise exited 0 (the heading vanished into the header rule, unreported)"
elif grep -q "playbook/codex-installed" "$work/err" && grep -q "awk matched no line" "$work/err" && [ ! -s "$work/out.red" ]; then
  ok "consumed line: refused by the grep-found-awk-missed guard, named the rule, emitted nothing"
else
  bad "consumed line: refused for another reason: $(head -1 "$work/err")"
fi

# --- 3. RED: unruled files -----------------------------------------------------------
echo "3. red — a basename this repo does not publish is refused; --no-rules is the explicit override"
make_live
printf 'A renamed command with nothing private in it.\n' > "$work/live/commands/council-v2.md"
if sh "$pub" "$work/live/commands/council-v2.md" > "$work/out.red" 2>"$work/err"; then
  bad "an unknown basename was published with no rules at all"
else
  grep -q "unknown file 'council-v2.md'" "$work/err" && [ ! -s "$work/out.red" ] \
    && ok "unknown basename refused by name, emitted nothing" \
    || bad "unknown basename refused for the wrong reason: $(head -1 "$work/err")"
fi
if sh "$pub" --no-rules "$work/live/commands/council-v2.md" > "$work/out.nr" 2>"$work/err"; then
  cmp -s "$work/out.nr" "$work/live/commands/council-v2.md" \
    && ok "--no-rules publishes an unknown, clean file verbatim" \
    || bad "--no-rules altered a file it had no rules for"
else
  bad "--no-rules still refused a clean unknown file: $(head -1 "$work/err")"
fi
if sh "$pub" --no-rules "$work/live/commands/council.md" > "$work/out.red" 2>"$work/err"; then
  bad "--no-rules on a file the table knows SKIPPED its rules and exited 0"
else
  st=$?
  [ "$st" -eq 2 ] && grep -q "is in the table" "$work/err" && [ ! -s "$work/out.red" ] \
    && ok "--no-rules on a known file is a usage error (exit 2), rules cannot be skipped" \
    || bad "--no-rules on a known file: exit $st, $(head -1 "$work/err")"
fi

echo "3b. red — deny-list catches an unruled private token"
make_live
printf 'A new file that mentions the private-source-repo in passing.\n' \
  > "$work/live/commands/some-new-command.md"
if sh "$pub" --no-rules "$work/live/commands/some-new-command.md" >/dev/null 2>"$work/err"; then
  bad "an unruled file leaked a deny-list token"
else
  grep -q "deny-list token" "$work/err" \
    && ok "deny-list refused a file that has no rules of its own" \
    || bad "refused, but not via the deny-list: $(head -1 "$work/err")"
fi

echo "3b'. red — agy-seat.sh output is deny-scanned like every published file"
make_live
printf '# a comment that names FAKEHOOK\n' >> "$work/live/agy-seat.sh"
if sh "$pub" "$work/live/agy-seat.sh" > "$work/out.red" 2>"$work/err"; then
  bad "agy-seat.sh leaked a deny-list token"
else
  grep -q "deny-list token" "$work/err" && [ ! -s "$work/out.red" ] \
    && ok "agy-seat.sh: a deny-list token refuses it, emitted nothing" \
    || bad "agy-seat.sh refused, but not via the deny-list: $(head -1 "$work/err")"
fi

echo "3c. red — a pairs.sh row whose basename has no arm in the rule table refuses at startup"
make_live
cp -R "$here" "$work/repo-renamed"
rm -rf "$work/repo-renamed/.git"
# (The first row shares its line with `PAIRS='`, so the pattern is not anchored at ^.)
sed 's|commands/council\.md  *commands/council\.md$|commands/council-2.md         commands/council.md|' \
  "$work/repo-renamed/tests/pairs.sh" > "$work/mutated" && mv "$work/mutated" "$work/repo-renamed/tests/pairs.sh"
grep -q 'commands/council-2.md' "$work/repo-renamed/tests/pairs.sh" \
  || bad "renamed-row fixture did not take — the case would test nothing"
# Any file will do: the check is on the TABLE, before the file is looked at.
if PUBLICISE_DENY="$work/deny" sh "$work/repo-renamed/tests/publicise.sh" "$work/live/MODEL-PLAYBOOK.md" \
     > "$work/out.red" 2>"$work/err"; then
  bad "renamed pair row: publicise exited 0 — council.md's rules are dead and nothing noticed"
elif grep -q '^publicise: \[rules\]' "$work/err" && grep -q "council-2.md" "$work/err" && [ ! -s "$work/out.red" ]; then
  ok "renamed pair row: refused at startup with class [rules], named the row, emitted nothing"
else
  bad "renamed pair row: refused for another reason: $(head -1 "$work/err")"
fi

# --- 4. RED: the fixer must not launder a refusal into a green gate -------------------
echo "4. red — refresh-from-live.sh writes nothing when the transform refuses"
cp -R "$here" "$work/repo"
rm -rf "$work/repo/.git"
published_hash() {  # one digest over every published file in the table
  ph_acc=""
  ph_one() { ph_acc="$ph_acc $(shasum < "$work/repo/$2" | cut -d' ' -f1)"; }
  for_each_pair ph_one
  printf '%s' "$ph_acc"
}
# 4a. A clean fixture refreshes every pair, and the gate then agrees the copy is CLEAN.
make_live
if LIVE="$work/live" sh "$work/repo/tests/refresh-from-live.sh" >/dev/null 2>"$work/err"; then
  ok "refresh-from-live wrote the published copies from a clean fixture"
else
  bad "refresh-from-live refused a clean fixture: $(head -1 "$work/err")"
fi
gate() {  # runs the gate in the copy against the fixture tree; prints exit status
  LIVE="$work/live" sh "$work/repo/tests/check-upstream-sync.sh" > "$work/gate.out" 2>&1 && echo 0 || echo $?
}
# The gate adds ONE thing to a refusal, the line that holds for every class. So its block
# for a refused file must be exactly: the header, the transform's own stderr for the same
# input (indented), and that line. Nothing keyed on the class can hide in it: the
# transform runs again directly, under the same environment, and the two are compared
# byte for byte. (Advice keyed on the class drifted from the cause three rounds running.)
gate_tail='           Resolve what the message above names; do NOT run
           tests/refresh-from-live.sh — it would publish what was refused.'
gate_adds_only_the_rule() {  # <live-rel> <published-rel> [VAR=value ...]; reads $work/gate.out
  ga_live=$1; ga_pub=$2; shift 2
  if env "$@" sh "$work/repo/tests/publicise.sh" "$work/live/$ga_live" > /dev/null 2> "$work/direct.err"; then
    return 1
  else ga_st=$?; fi
  { printf 'REFUSED  %s — publicise exit %s:\n' "$ga_pub" "$ga_st"
    sed 's/^/           /' "$work/direct.err"
    printf '%s\n' "$gate_tail"; } > "$work/expect.block"
  # The block runs to the next verdict line or the blank line before the summary, so a
  # line the gate adds without indentation is inside the comparison too.
  awk -v hdr="REFUSED  $ga_pub " 'index($0, hdr) == 1 { f = 1; print; next }
    f && ($0 == "" || /^(ok|STALE|REFUSED|UNKNOWN) /) { f = 0 } f { print }' \
    "$work/gate.out" > "$work/actual.block"
  [ -s "$work/direct.err" ] && cmp -s "$work/expect.block" "$work/actual.block"
}
st=$(gate)
if [ "$st" -eq 0 ] && grep -q "^SYNC CLEAN — 6 file(s)" "$work/gate.out"; then
  ok "gate: CLEAN after the refresh, all 6 pairs checked"
else
  bad "gate: expected CLEAN over 6 pairs after a refresh, got exit $st: $(tail -1 "$work/gate.out")"
fi
# 4a'. A published folder that is not there yet (a new pair's first refresh, or a folder
# someone removed) is created, not tripped over. The fixer used to write each file with a
# bare redirect, so a missing folder stopped it at that file with the earlier ones
# already written: the all-or-nothing rule broken by the one case no transform refuses.
rm -rf "$work/repo/agents"
if LIVE="$work/live" sh "$work/repo/tests/refresh-from-live.sh" >/dev/null 2>"$work/err" \
   && [ -f "$work/repo/agents/council-seat.md" ] && [ "$(gate)" -eq 0 ]; then
  ok "refresh-from-live creates a missing published folder, and the gate is CLEAN after it"
else
  bad "refresh-from-live with no published agents/ folder: $(tail -1 "$work/err")"
fi
# 4b. Now the transform refuses: the fixer must write nothing.
before=$(published_hash)
sed 's/^For security-scoped councils, also fold the infra-first dimensions from$/For security-scoped councils, fold in the infra-first dimensions from/' \
  "$work/live/commands/council.md" > "$work/mutated.md" && mv "$work/mutated.md" "$work/live/commands/council.md"
if LIVE="$work/live" sh "$work/repo/tests/refresh-from-live.sh" >/dev/null 2>"$work/err"; then
  bad "refresh-from-live exited 0 with a refusing transform"
else
  ok "refresh-from-live failed instead of publishing"
fi
after=$(published_hash)
if [ "$before" = "$after" ]; then
  ok "published files are byte-identical across every pair — nothing was laundered"
else
  bad "published files CHANGED while the transform was refusing"
fi

# --- 6. GATE: the sync check tells a refusal from staleness and never passes on UNKNOWN --
echo "6. gate — REFUSED is its own verdict, and UNKNOWN never passes"
# The fixture still carries the moved anchor from 4b.
st=$(gate)
if [ "$st" -eq 1 ] && grep -q "^REFUSED  commands/council.md" "$work/gate.out" \
   && grep -q "council/local-dimensions" "$work/gate.out"; then
  ok "gate: a refusing live file is REFUSED (exit 1) with the transform's reason"
else
  bad "gate: refusal not reported as REFUSED, exit $st: $(grep -E '^(STALE|REFUSED|SYNC)' "$work/gate.out" | head -2 | tr '\n' '|')"
fi
if grep -q "regenerate with" "$work/gate.out"; then
  bad "gate: told the user to regenerate after a REFUSAL — that publishes the refused text"
else
  ok "gate: no 'regenerate' advice after a refusal"
fi
# The next step is the transform's own ("Re-anchor rule ..."), and the gate adds only
# the line every refusal shares.
if grep -q "Re-anchor rule" "$work/gate.out" && gate_adds_only_the_rule commands/council.md commands/council.md; then
  ok "gate: an anchor refusal carries the transform's re-anchor step, and the gate adds only 'do not refresh'"
else
  bad "gate: anchor refusal block is not the transform's message plus the shared line: $(diff "$work/expect.block" "$work/actual.block" | head -3 | tr '\n' '|')"
fi
grep -q "^STALE    commands/council.md" "$work/gate.out" \
  && bad "gate: the refusal ALSO shows as STALE" \
  || ok "gate: the refused file is not double-reported as STALE"
# STALE: a hand-edited published copy, transform healthy.
make_live
printf '\nhand-edited line\n' >> "$work/repo/docs/MODEL-PLAYBOOK.md"
st=$(gate)
if [ "$st" -eq 1 ] && grep -q "^STALE    docs/MODEL-PLAYBOOK.md" "$work/gate.out" && grep -q "regenerate with" "$work/gate.out"; then
  ok "gate: a drifted published copy is STALE (exit 1) and the fixer is the advice"
else
  bad "gate: stale copy mis-reported, exit $st: $(tail -1 "$work/gate.out")"
fi
LIVE="$work/live" sh "$work/repo/tests/refresh-from-live.sh" >/dev/null 2>&1 || bad "gate: could not re-clean the copy"
# UNKNOWN with ONE source missing: exit 2 and the absent file named (before: CLEAN, exit 0).
rm "$work/live/codex-seat.sh"
st=$(gate)
if [ "$st" -eq 2 ] && grep -q "^SYNC UNKNOWN" "$work/gate.out" && grep -q "codex-seat.sh" "$work/gate.out"; then
  ok "gate: one missing live source is UNKNOWN (exit 2) and named — not CLEAN"
else
  bad "gate: partial UNKNOWN mis-reported, exit $st: $(tail -2 "$work/gate.out" | tr '\n' '|')"
fi
# REFUSED for want of a deny-list: the advice must be about the deny-list, not the anchor.
make_live
LIVE="$work/live" sh "$work/repo/tests/refresh-from-live.sh" >/dev/null 2>&1 || bad "gate: could not re-clean the copy"
if PUBLICISE_DENY="$work/no-such-deny-file" LIVE="$work/live" sh "$work/repo/tests/check-upstream-sync.sh" \
     > "$work/gate.out" 2>&1; then st=0; else st=$?; fi
if [ "$st" -eq 1 ] && grep -q "^REFUSED  commands/council.md" "$work/gate.out" \
   && grep -q "no readable deny-list at" "$work/gate.out" && grep -q "if you have no list yet" "$work/gate.out" \
   && ! grep -q -i "fix the anchor" "$work/gate.out" \
   && gate_adds_only_the_rule commands/council.md commands/council.md PUBLICISE_DENY="$work/no-such-deny-file"; then
  ok "gate: a deny-list refusal carries the transform's install-if-none step, nothing about anchors"
else
  bad "gate: wrong advice for a deny-list refusal, exit $st: $(diff "$work/expect.block" "$work/actual.block" | head -3 | tr '\n' '|')"
fi
# REFUSED because the deny scan could not run: a real list is in place, so the advice must
# not be the deny-list arm's "install one" (copying the example over it would lose the
# real list), nor the anchor arm's. The fake python3 answers the transform's probes (it is
# the real one there) and fails on the real list, so the scan's own message is what the
# gate must carry.
mkdir -p "$work/gatepy"
printf '#!/bin/sh\ngrep -q ACME-PASSES "$4" && exit 1\nexec %s "$@"\n' "$(command -v python3)" > "$work/gatepy/python3"
chmod +x "$work/gatepy/python3"
if PATH="$work/gatepy:$PATH" LIVE="$work/live" sh "$work/repo/tests/check-upstream-sync.sh" \
     > "$work/gate.out" 2>&1; then st=0; else st=$?; fi
if [ "$st" -eq 1 ] && grep -q "^REFUSED  commands/council.md" "$work/gate.out" \
   && grep -q "Unicode deny scan could not run or could not judge" "$work/gate.out" \
   && ! grep -q -i "install one\|install it\|cp .*publicise-deny.example" "$work/gate.out" \
   && ! grep -q -i "fix the anchor" "$work/gate.out" \
   && grep -q "^SYNC REFUSED .*do not refresh" "$work/gate.out" \
   && gate_adds_only_the_rule commands/council.md commands/council.md PATH="$work/gatepy:$PATH"; then
  ok "gate: a scan that could not run carries the transform's scan message, never 'install the example'"
else
  bad "gate: wrong advice for a scan refusal, exit $st: $(diff "$work/expect.block" "$work/actual.block" | head -3 | tr '\n' '|')"
fi
# REFUSED [block] for a byte that is not UTF-8, in a file with no anchors at all (Codex
# round 8's input): the advice is the transform's "re-encode it", never "fix the anchor".
make_live
LIVE="$work/live" sh "$work/repo/tests/refresh-from-live.sh" >/dev/null 2>&1 || bad "gate: could not re-clean the copy"
printf 'caf\377\n' >> "$work/live/commands/audit-claude-md.md"
st=$(gate)
if [ "$st" -eq 1 ] && grep -q "^REFUSED  commands/audit-claude-md.md" "$work/gate.out" \
   && grep -q "publicise: \[block\] the output for .* is not valid UTF-8" "$work/gate.out" \
   && grep -q "re-encode it" "$work/gate.out" && ! grep -q -i "fix the anchor" "$work/gate.out" \
   && gate_adds_only_the_rule commands/audit-claude-md.md commands/audit-claude-md.md; then
  ok "gate: a [block] encoding refusal carries 're-encode it', nothing about anchors"
else
  bad "gate: wrong advice for a [block] encoding refusal, exit $st: $(diff "$work/expect.block" "$work/actual.block" | head -3 | tr '\n' '|')"
fi
make_live
# UNKNOWN with EVERY source missing (a CI runner): exit 2.
mkdir -p "$work/nolive"
if LIVE="$work/nolive" sh "$work/repo/tests/check-upstream-sync.sh" > "$work/gate.out" 2>&1; then st=0; else st=$?; fi
[ "$st" -eq 2 ] && ok "gate: no live source at all is UNKNOWN (exit 2)" \
                || bad "gate: no live source exited $st"

# --- 5. RED: the deny-list must be usable, not merely present --------------------------
echo "5. red — a missing deny-list refuses rather than publishing unchecked"
make_live
if PUBLICISE_DENY="$work/no-such-deny-file" sh "$pub" "$work/live/commands/council.md" \
     >/dev/null 2>"$work/err"; then
  bad "published with no deny-list at all"
else
  grep -q "no readable deny-list at" "$work/err" \
    && ok "refused, and said where the list should live" \
    || bad "refused for the wrong reason: $(head -1 "$work/err")"
fi

echo "5b. red — a deny-list with no usable tokens refuses (before: exit 0, nothing scanned)"
# expect_deny_refusal <label> <list-file> <stderr-must-contain>
expect_deny_refusal() {
  make_live
  if PUBLICISE_DENY="$2" sh "$pub" "$work/live/commands/council.md" > "$work/out.red" 2>"$work/err"; then
    bad "$1: published (exit 0)"
  else
    grep -q -F -- "$3" "$work/err" && [ ! -s "$work/out.red" ] \
      && ok "$1: refused, named '$3'" \
      || bad "$1: refused for the wrong reason: $(head -1 "$work/err")"
  fi
}
: > "$work/deny.empty"
expect_deny_refusal "empty list" "$work/deny.empty" "has no tokens"
printf '# only a comment\n\n# and another\n' > "$work/deny.comments"
expect_deny_refusal "comments-only list" "$work/deny.comments" "has no tokens"
printf '   # an indented comment used to count as a token\n' > "$work/deny.indented"
expect_deny_refusal "indented-comment-only list" "$work/deny.indented" "has no tokens"

echo "5c. red — tokens survive CRLF endings and stray whitespace (before: they matched nothing)"
# The token must be one that reaches the OUTPUT (the council rule removes ACME-PASSES
# before the scan runs, so that would prove nothing): the fixture's last line ends in
# "survive untouched." with nothing after the period. Each list below spells that token
# in a way the old loader mangled — CR, trailing spaces, leading spaces — and each must
# still bite.
printf '# saved on Windows\r\nsurvive untouched.\r\n' > "$work/deny.crlf"
expect_deny_refusal "CRLF list" "$work/deny.crlf" "deny-list token"
printf 'survive untouched.   \n' > "$work/deny.trailing"
expect_deny_refusal "trailing-space token" "$work/deny.trailing" "deny-list token"
printf '   survive untouched.\n' > "$work/deny.leading"
expect_deny_refusal "leading-space token" "$work/deny.leading" "deny-list token"
# No trailing newline (an editor that does not add one, a `printf` without \n): the
# normaliser's sed preserves the missing newline, so a plain `read` never returns the
# last line — while the token COUNT still saw it and waved the list through.
printf 'survive untouched.' > "$work/deny.nonl"
expect_deny_refusal "single token, no trailing newline" "$work/deny.nonl" "deny-list token"
printf 'nothing-here\nsurvive untouched.' > "$work/deny.two-nonl"
expect_deny_refusal "two tokens, last one unterminated" "$work/deny.two-nonl" "deny-list token"

echo "5d. red — the deny match is case-insensitive (a token in caps still bites lower-case text)"
printf 'SURVIVE UNTOUCHED.\n' > "$work/deny.caps"
expect_deny_refusal "upper-case token vs lower-case text" "$work/deny.caps" "deny-list token"

# The ids are invented: like every token here, this file is published too.
echo "7. ledger ids — the two live shapes are stripped, any other shape refuses, look-alikes stay"
make_live
if sh "$pub" "$work/live/codex-seat.sh" > "$work/out.ids" 2>"$work/err"; then
  if ! grep -q -i -E '(^|[^0-9a-z])ow-0a1b2c([^0-9a-z]|$)' "$work/out.ids" \
     && has_line ids "# would hide the reason from an empty seat (2000-01-01). The CLI's own words" \
     && has_line ids "  # 5c. a failed review whose TRANSCRIPT quotes the phrase is NOT a spent seat:" \
     && has_line ids "# flow-0a1b2c and ow-0a1b2c7 are not ledger ids."; then
    ok "\" (<id>)\" and \"(<id>, \" stripped; flow-<hex> and a seven-digit run left as written"
  else
    bad "ledger ids: output kept an id, or the strip mangled a line: $(grep -n -i 'ow-0a1b2c' "$work/out.ids" | head -3)"
  fi
else
  bad "ledger ids: the codex-seat fixture should have published: $(head -1 "$work/err")"
fi
expect_refusal "an id in a shape nobody strips" "$work/live/codex-seat.sh" \
  's/^# would simply go empty\.$/# would simply go empty, see ow-0a1b2c./' "work-ledger id"
expect_refusal "an id in capitals" "$work/live/codex-seat.sh" \
  's/seat (ow-0a1b2c):$/seat (OW-0A1B2C):/' "work-ledger id"
expect_refusal "an id glued to a dash" "$work/live/codex-seat.sh" \
  's/(ow-0a1b2c, 2000-01-01)/(ow-0a1b2c-r2, 2000-01-01)/' "work-ledger id"
expect_refusal "an id in the council command" "$work/live/commands/council.md" \
  's/^Some portable preamble that must survive untouched\.$/Some portable preamble (see ow-0a1b2c) that must survive untouched./' \
  "work-ledger id"

echo "7b. red — a NUL byte in the output hides neither an id nor a token"
# GNU grep 3.5 and later reports a match in a file it judges binary on STDERR only, so the
# scans that tested captured text published both of these on Linux (CI's platform). BSD
# grep prints the notice on stdout, so on a Mac the old scans refused anyway; the red for
# these cases is CI's. The file is audit-claude-md.md because it has no rules: only sed
# touches it before the scans, and sed keeps a NUL everywhere, while BSD awk cuts a line
# at one, so on a Mac a ruled file reaches the scans with its NUL already gone.
# The refusal's FIRST stderr line must be the [class] line: the sync gate reads its
# advice from there, and a shell warning about the NUL would sit above it.
# expect_nul_refusal <label> <line to append, a NUL after it> <deny-list> <stderr-must-contain>
expect_nul_refusal() {
  make_live
  nul_live="$work/live/commands/audit-claude-md.md"
  printf '%s\000\n' "$2" >> "$nul_live"
  if tr -d '\000' < "$nul_live" | cmp -s - "$nul_live"; then
    bad "$1: no NUL byte reached the fixture — the case tests nothing"; return
  fi
  if PUBLICISE_DENY="$3" sh "$pub" "$nul_live" > "$work/out.red" 2>"$work/err"; then
    bad "$1: published (exit 0), $(wc -l < "$work/out.red" | tr -d ' ') lines"
  elif ! grep -q -F -- "$4" "$work/err"; then
    bad "$1: refused, but not for the expected reason: $(head -1 "$work/err")"
  elif ! head -1 "$work/err" | grep -q '^publicise: \[deny-hit\] '; then
    bad "$1: the first stderr line is not the [deny-hit] class line: $(head -1 "$work/err")"
  elif [ -s "$work/out.red" ]; then
    bad "$1: refused but still wrote $(wc -l < "$work/out.red" | tr -d ' ') lines to stdout"
  else
    ok "$1: refused as [deny-hit], named '$4', emitted nothing"
  fi
}
expect_nul_refusal "an id on a line with a NUL byte" "# see ow-0a1b2c here." "$work/deny" "work-ledger id"
printf 'nothing private in it.\n' > "$work/deny.nul"
expect_nul_refusal "a token in a file with a NUL byte" "x" "$work/deny.nul" "deny-list token"

echo "7c. red — a grep that fails while scanning the output is a refusal, not a clean pass"
# A fake grep that fails (status 2, as for a read error) on the transform's staged
# output and nothing else. Before scan(), `|| true` swallowed that status and the empty
# capture read as "no id found".
real_grep=$(command -v grep)
mkdir -p "$work/badgrep"
cat > "$work/badgrep/grep" <<EOF
#!/bin/sh
for a in "\$@"; do
  case \$a in */publicise.*/cur) echo "grep: \$a: simulated read error" >&2; exit 2 ;; esac
done
exec "$real_grep" "\$@"
EOF
chmod +x "$work/badgrep/grep"
make_live
if PATH="$work/badgrep:$PATH" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
  bad "a failing scan published (exit 0), $(wc -l < "$work/out.red" | tr -d ' ') lines"
elif head -1 "$work/err" | grep -q '^publicise: \[scan\] grep failed (status 2) scanning the output' \
     && grep -q 'simulated read error' "$work/err" && [ ! -s "$work/out.red" ]; then
  ok "a failing scan refused as [scan] on its first stderr line, quoted grep's error, emitted nothing"
else
  bad "a failing scan refused for the wrong reason: $(head -1 "$work/err")"
fi

echo "7d. red — an output that is not UTF-8 is refused before any scan can be fooled"
# Under a UTF-8 locale a byte that is not UTF-8 matches neither [^0-9A-Za-z] nor `$`, so
# "ow-0a1b2c" followed by one was no match, and GNU sed passes the byte through: published
# on Linux. BSD grep misses even a plain token on such a line, and a token in other
# capitals beyond ASCII ("Équipe" for "équipe") then passed both scan views. Each case
# must refuse as not UTF-8, class line first, nothing on stdout. The bytes are octal
# escapes in a printf format (\303\211 is É, \303\251 is é).
utf8_loc=$(locale -a 2>/dev/null | grep -i -E '^(c|en_us)\.utf-?8$' | head -1 || true)
# expect_utf8_refusal <label> <printf format appended> <deny-list> <stderr-must-contain> [locale]
expect_utf8_refusal() {
  make_live
  # shellcheck disable=SC2059
  printf "$2" >> "$work/live/commands/audit-claude-md.md"
  if LC_ALL=${5:-$utf8_loc} PUBLICISE_DENY="$3" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
    bad "$1: published (exit 0)"
  elif ! head -1 "$work/err" | grep -q '^publicise: \[[a-z-]*\] '; then
    bad "$1: the first stderr line is not a class line: $(head -1 "$work/err")"
  elif ! grep -q -F -- "$4" "$work/err"; then
    bad "$1: refused, but not for the expected reason: $(head -1 "$work/err")"
  elif [ -s "$work/out.red" ]; then
    bad "$1: refused but still wrote $(wc -l < "$work/out.red" | tr -d ' ') lines to stdout"
  else
    ok "$1: refused, class line first, named '$4'"
  fi
}
if [ -z "$utf8_loc" ]; then
  bad "no C.UTF-8 or en_US.UTF-8 in 'locale -a': sections 7d and 7e cannot run here"
else
  expect_utf8_refusal "an invalid byte right after an id" '# see ow-0a1b2c\377\n' "$work/deny" "not valid UTF-8"
  expect_utf8_refusal "an invalid byte right before an id" '\377ow-0a1b2c here\n' "$work/deny" "not valid UTF-8"
  expect_utf8_refusal "invalid bytes on both sides of an id" '# \377ow-0a1b2c\377\n' "$work/deny" "not valid UTF-8"
  expect_utf8_refusal "an id after a period, then an invalid byte" '# see ow-0a1b2c.\377\n' "$work/deny" "not valid UTF-8"
  printf 'zq7private\n' > "$work/deny.utf8"
  expect_utf8_refusal "invalid bytes on both sides of a deny token" '\377zq7private\377\n' "$work/deny.utf8" "not valid UTF-8"
  printf '\303\251quipe\n' > "$work/deny.fold"
  expect_utf8_refusal "invalid bytes around a token in other capitals" '\377\303\211quipe\377\n' "$work/deny.fold" "not valid UTF-8"
  expect_utf8_refusal "invalid bytes under the C locale" '# see ow-0a1b2c\377\n' "$work/deny" "not valid UTF-8" C

  echo "7e. red — a token hits in any capitals and any Unicode spelling, in any locale"
  # grep -i folds one character to one and compares code points as written; each case
  # below passed it (under C, the first passed even that). Octal: \303\211 É, \303\251 é,
  # \303\237 ß, \341\272\236 ẞ, \314\201 a combining acute, \357\254\201 the ﬁ ligature,
  # \357\275\232 a full-width z.
  expect_utf8_refusal "É for é under the C locale" '\303\211quipe here\n' "$work/deny.fold" "deny-list token" C
  expect_utf8_refusal "É for é under a UTF-8 locale" '\303\211quipe here\n' "$work/deny.fold" "deny-list token"
  printf 'stra\303\237e\n' > "$work/deny.sharp"
  expect_utf8_refusal "STRASSE for straße" 'STRASSE here\n' "$work/deny.sharp" "deny-list token"
  expect_utf8_refusal "STRAẞE (capital sharp s) for straße" 'STRA\341\272\236E here\n' "$work/deny.sharp" "deny-list token"
  expect_utf8_refusal "a decomposed é for a precomposed token" 'e\314\201quipe here\n' "$work/deny.fold" "deny-list token"
  printf 'e\314\201quipe\n' > "$work/deny.nfd"
  expect_utf8_refusal "a precomposed é for a decomposed token" '\303\251quipe here\n' "$work/deny.nfd" "deny-list token"
  printf 'finance-desk\n' > "$work/deny.lig"
  expect_utf8_refusal "the fi ligature for f-i" '\357\254\201nance-desk here\n' "$work/deny.lig" "deny-list token"
  expect_utf8_refusal "a full-width letter for its plain spelling" '\357\275\232q7private here\n' "$work/deny.utf8" "deny-list token"
fi

echo "7e2. red — a Unicode scan that cannot run refuses; only its own two answers count"
# A broken or missing python3 exits 1 or 127 and a stub may exit 0: none of them may read
# as "clean". A stub that always gives one of the scan's own answers, 10 (a hit) or 11
# (none), must fail the probes too: one that always said 11 passed every token the byte
# scan cannot see (Codex round 11). Each fake python3 stands first on PATH for one run.
for fake_st in 1 0 127 10 11; do
  mkdir -p "$work/fakepy$fake_st"
  printf '#!/bin/sh\nexit %s\n' "$fake_st" > "$work/fakepy$fake_st/python3"
  chmod +x "$work/fakepy$fake_st/python3"
  make_live
  if PATH="$work/fakepy$fake_st:$PATH" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
    bad "a python3 that exits $fake_st let the file publish"
  elif head -1 "$work/err" | grep -q "^publicise: \[scan\] python3 gave the wrong answer on a known input" \
       && [ ! -s "$work/out.red" ]; then
    ok "a python3 that exits $fake_st: refused as [scan] naming python3, emitted nothing"
  else
    bad "a python3 that exits $fake_st: wrong refusal: $(head -1 "$work/err")"
  fi
done
# One that answers the probes (the real python3) and fails on the real list: the status
# read behind the probes refuses it.
real_py=$(command -v python3)
mkdir -p "$work/fakepylist"
printf '#!/bin/sh\ngrep -q ACME-PASSES "$4" && exit 1\nexec %s "$@"\n' "$real_py" > "$work/fakepylist/python3"
chmod +x "$work/fakepylist/python3"
make_live
if PATH="$work/fakepylist:$PATH" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
  bad "a python3 that fails only on the real list let the file publish"
elif head -1 "$work/err" | grep -q "^publicise: \[scan\] the Unicode deny scan could not run or could not judge the text (status 1)" \
     && [ ! -s "$work/out.red" ]; then
  ok "a python3 that fails only on the real list: refused as [scan], emitted nothing"
else
  bad "a python3 that fails only on the real list: wrong refusal: $(head -1 "$work/err")"
fi

echo "7e2b. red — an iconv that cannot judge refuses as [scan], never as a bad byte"
# A broken iconv exits 1 on every input, the same status as a real bad byte, and a missing
# one exits 127. Either way the live file is fine (plain ASCII here) and "re-encode it"
# would be the wrong repair (Codex round 9), so it must refuse as [scan] and name iconv.
for fake_st in 1 127; do
  mkdir -p "$work/fakeiconv$fake_st"
  printf '#!/bin/sh\nexit %s\n' "$fake_st" > "$work/fakeiconv$fake_st/iconv"
  chmod +x "$work/fakeiconv$fake_st/iconv"
  make_live
  if PATH="$work/fakeiconv$fake_st:$PATH" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
    bad "an iconv that exits $fake_st let the file publish"
  elif head -1 "$work/err" | grep -q "^publicise: \[scan\] iconv gave the wrong answer on a known input" \
       && ! grep -q -i "re-encode\|not valid UTF-8" "$work/err" && [ ! -s "$work/out.red" ]; then
    ok "an iconv that exits $fake_st: refused as [scan] naming iconv, no 're-encode', emitted nothing"
  else
    bad "an iconv that exits $fake_st: wrong refusal: $(head -1 "$work/err")"
  fi
done

echo "7e2c. red — a grep or awk that cannot judge refuses as [scan], never as a moved anchor"
# Codex round 10: a grep that cannot run (a missing shared library exits 127) read as
# "anchor not found" and prescribed re-anchoring an intact file; the awk rule handlers did
# the same. council.md is the live file because its rules call require() and awk. Stubs
# that always fail or always succeed must fail the probes; a "file" shim answers the
# probes (stdin) and fails only on a file, so the status reads behind them are exercised.
expect_tool_refusal() {  # <label> <tool> <shim body> <first stderr line must contain>
  mkdir -p "$work/tool.$1"
  printf '#!/bin/sh\n%s\n' "$3" > "$work/tool.$1/$2"
  chmod +x "$work/tool.$1/$2"
  make_live
  if PATH="$work/tool.$1:$PATH" sh "$pub" "$work/live/commands/council.md" > "$work/out.red" 2>"$work/err"; then
    bad "$1: the file published"
  elif head -1 "$work/err" | grep -q "^publicise: \[scan\] $4" \
       && ! grep -q -i "anchor not found\|re-anchor\|did not open and close\|matched no line" "$work/err" \
       && [ ! -s "$work/out.red" ]; then
    ok "$1: refused as [scan] naming $2, nothing about anchors, emitted nothing"
  else
    bad "$1: wrong refusal: $(head -1 "$work/err")"
  fi
}
file_shim() {  # <tool> — the real tool on stdin, exit 2 when the last argument is a file
  real=$(command -v "$1")
  printf 'for a in "$@"; do last=$a; done\n[ -f "${last:-}" ] && exit 2\nexec %s "$@"' "$real"
}
for st in 1 0 127; do
  expect_tool_refusal "a grep that always exits $st" grep "exit $st" "grep gave the wrong answer on a known input"
  expect_tool_refusal "an awk that always exits $st" awk "exit $st" "awk gave the wrong answer on a known input"
done
expect_tool_refusal "an iconv that always exits 0" iconv "exit 0" "iconv gave the wrong answer on a known input"
expect_tool_refusal "a grep that fails only on a file" grep "$(file_shim grep)" "rule '.*': grep stopped with status 2"
expect_tool_refusal "an awk that fails only on a file" awk "$(file_shim awk)" "rule '.*': awk stopped with status 2"

echo "7e2d. red — a tool that copies or rewrites text gives the known output, or refuses"
# A stub that exits 0 having written nothing, or the wrong text, must fail the probes:
# a cat or mv that does nothing would drop a rule's redaction, a tr or sed that does
# would shorten the deny-list.
expect_tool_refusal "a cat that writes nothing" cat "exit 0" "cat gave the wrong answer on a known input"
expect_tool_refusal "an mv that moves nothing" mv "exit 0" "mv gave the wrong answer on a known input"
expect_tool_refusal "an mv that always fails" mv "exit 1" "mv gave the wrong answer on a known input"
expect_tool_refusal "a tr that writes nothing" tr "exit 0" "tr gave the wrong answer on a known input"
expect_tool_refusal "a tr that writes one harmless token" tr "printf 'harmless\\n'" "tr gave the wrong answer on a known input"
expect_tool_refusal "a sed that writes nothing" sed "exit 0" "sed gave the wrong answer on a known input"
expect_tool_refusal "a sed that always fails" sed "exit 1" "sed gave the wrong answer on a known input"
# Codex round 11's input: the list names "harmless" then "zq7private", the live file says
# zq7private, and a tr that passes the probes prints the list's first token and exits 1
# on the real list. `tr | sed` returned sed's 0, so the list was "harmless" alone and the
# private token published. A sed that does the same on the real list is the second stage.
printf 'harmless\nzq7private\n' > "$work/deny.r11"
mkdir -p "$work/norm.tr" "$work/norm.sed"
{ echo '#!/bin/sh'
  printf "real='%s'\n" "$(command -v tr)"
  cat <<'EOF'
out=$("$real" "$@"; echo x); out=${out%x}
case $out in *zq7private*) printf 'harmless\n'; exit 1;; esac
printf '%s' "$out"
EOF
} > "$work/norm.tr/tr"
{ echo '#!/bin/sh'
  printf "real='%s'\n" "$(command -v sed)"
  cat <<'EOF'
for a in "$@"; do last=$a; done
if [ -f "${last:-}" ] && grep -q zq7private "$last" && grep -q '^harmless' "$last"; then
  printf 'harmless\n'; exit 1
fi
exec "$real" "$@"
EOF
} > "$work/norm.sed/sed"
chmod +x "$work/norm.tr/tr" "$work/norm.sed/sed"
expect_norm_refusal() {  # <label> <tool> <first stderr line must contain>
  make_live
  printf 'zq7private here\n' >> "$work/live/commands/audit-claude-md.md"
  if PATH="$work/norm.$2:$PATH" PUBLICISE_DENY="$work/deny.r11" sh "$pub" "$work/live/commands/audit-claude-md.md" \
       > "$work/out.red" 2>"$work/err"; then
    bad "$1: the private token published"
  elif head -1 "$work/err" | grep -q "^publicise: \[scan\] $3" && [ ! -s "$work/out.red" ]; then
    ok "$1: refused as [scan] naming $2, emitted nothing"
  else
    bad "$1: wrong refusal: $(head -1 "$work/err")"
  fi
}
expect_norm_refusal "a tr that fails part-way through the real list" tr "tr stopped with status 1 normalising the deny-list"
expect_norm_refusal "a sed that fails part-way through the real list" sed "sed stopped with status 1 normalising the deny-list"
# And the clean control: the same list and file with every tool real refuse as a hit.
make_live
printf 'zq7private here\n' >> "$work/live/commands/audit-claude-md.md"
if PUBLICISE_DENY="$work/deny.r11" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
  bad "control: zq7private published with every tool real"
elif head -1 "$work/err" | grep -q '^publicise: \[deny-hit\]'; then
  ok "control: with every tool real, the same list and file refuse as [deny-hit]"
else
  bad "control: wrong refusal: $(head -1 "$work/err")"
fi

echo "7e3. red — a character this python3 does not know refuses; a token is one line"
# The fold is only as good as python3's Unicode tables: a capital newer than them has no
# case mapping, so it passed a list naming its small letter. U+FDD0 is a noncharacter,
# unassigned (category Cn) in every Unicode version, so it stands in for "newer than these
# tables" on any python3. \357\267\220 is U+FDD0, \342\200\250 U+2028.
# expect_scan_refusal <label> <printf format appended> <deny-list> <stderr-must-contain>
expect_scan_refusal() {
  make_live
  # shellcheck disable=SC2059
  printf "$2" >> "$work/live/commands/audit-claude-md.md"
  if PUBLICISE_DENY="$3" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
    bad "$1: published (exit 0)"
  elif ! head -1 "$work/err" | grep -q '^publicise: \[scan\] '; then
    bad "$1: the first stderr line is not a [scan] line: $(head -1 "$work/err")"
  elif ! grep -q -F -- "$4" "$work/err"; then
    bad "$1: refused as [scan], but did not name '$4': $(grep 'unicode deny scan' "$work/err" | head -1)"
  elif [ -s "$work/out.red" ]; then
    bad "$1: refused but still wrote $(wc -l < "$work/out.red" | tr -d ' ') lines to stdout"
  else
    ok "$1: refused as [scan], named '$4'"
  fi
}
expect_scan_refusal "an unknown character in the output" 'x\357\267\220y here\n' "$work/deny" "U+FDD0"
printf 'zq7\357\267\220\n' > "$work/deny.cn"
expect_scan_refusal "an unknown character in a deny-list token" 'nothing private\n' "$work/deny.cn" "U+FDD0"
# A token holding U+2028 is ONE token. splitlines() made it two, "acme" and "research",
# and the second refused every file that said "research".
printf 'acme\342\200\250research\n' > "$work/deny.ls"
make_live
printf 'ordinary research notes\n' >> "$work/live/commands/audit-claude-md.md"
if PUBLICISE_DENY="$work/deny.ls" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
  ok "a token holding U+2028 does not split: 'research' alone published"
else
  bad "a token holding U+2028 was split, and refused a file saying 'research': $(head -1 "$work/err")"
fi
# ...and it still matches whole, in other capitals (a hit only the Unicode scan can make).
printf '\303\251quipe\342\200\250x\n' > "$work/deny.ls2"
expect_utf8_refusal "a token holding U+2028, in other capitals" '\303\211quipe\342\200\250x here\n' "$work/deny.ls2" "deny-list token" C

echo "7e4. red — a token dressed in marks or invisible characters still hits"
# The fold compared a token with the line as a plain substring, and three things break a
# substring without changing what a reader sees: a mark added to a letter of the token
# (normalising sorts the marks, so the token's own mark is no longer next to its letter),
# a mark left off (a name typed without its accent), and a character with no width put
# between two letters. Each case below published. Octal: \314\243 a combining dot below,
# \314\201 a combining acute, \342\200\213 a zero-width space, \342\200\214 and \342\200\215
# the zero-width non-joiner and joiner, \302\255 a soft hyphen, \342\201\240 a word joiner,
# \342\200\256 a right-to-left override, \357\273\277 a byte-order mark, \315\217 a
# combining grapheme joiner, \357\270\217 a variation selector, \343\205\244 a Hangul filler.
if [ -z "$utf8_loc" ]; then
  bad "no C.UTF-8 or en_US.UTF-8 in 'locale -a': section 7e4 cannot run here"
else
  expect_utf8_refusal "one more mark on an accented letter of the token" '\303\211\314\243quipe here\n' "$work/deny.fold" "deny-list token"
  expect_utf8_refusal "the same, under the C locale" '\303\211\314\243quipe here\n' "$work/deny.fold" "deny-list token" C
  expect_utf8_refusal "an accented token typed without its accent" 'Equipe here\n' "$work/deny.fold" "deny-list token"
  expect_utf8_refusal "a mark added inside a plain token" 'zq7pri\314\201vate here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a zero-width space inside the token" 'zq7\342\200\213private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a zero-width space inside, in other capitals" 'ZQ7\342\200\213PRIVATE here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a zero-width non-joiner inside the token" 'zq7\342\200\214private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a zero-width joiner inside the token" 'zq7\342\200\215private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a soft hyphen inside the token" 'zq7\302\255private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a word joiner inside the token" 'zq7\342\201\240private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a right-to-left override inside the token" 'zq7\342\200\256private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a byte-order mark inside the token" 'zq7\357\273\277private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a combining grapheme joiner inside the token" 'zq7\315\217private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a variation selector inside the token" 'zq7\357\270\217private here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "a Hangul filler inside the token" 'zq7\343\205\244private here\n' "$work/deny.utf8" "deny-list token"
  # \315\205 is U+0345, a combining mark that case folding turns into the letter iota. Marks
  # dropped only after the fold left that iota standing between the token's letters, so
  # they are dropped before it as well (Codex review, round 1).
  expect_utf8_refusal "a mark that case folding turns into a letter, inside the token" 'zq7pri\315\205vate here\n' "$work/deny.utf8" "deny-list token"
  expect_utf8_refusal "the same mark, in other capitals" 'ZQ7PRI\315\205VATE here\n' "$work/deny.utf8" "deny-list token"
  # ...and dropping before the fold must not lose what the fold alone caught. \341\276\263
  # is a small alpha with an iota subscript (a mark); its capitals are the two letters
  # \316\221\316\231, alpha and iota. The fold joins them, a drop before the fold alone
  # does not, so the scan compares both ways and a hit in either refuses.
  printf 'zq\341\276\263private\n' > "$work/deny.iota"
  expect_utf8_refusal "a token with an iota subscript, written in capitals" 'ZQ\316\221\316\231PRIVATE here\n' "$work/deny.iota" "deny-list token"
  expect_utf8_refusal "the same token with a zero-width space inside" 'zq\341\276\263pri\342\200\213vate here\n' "$work/deny.iota" "deny-list token"
  # The other direction (Codex review, round 2): a token spelt with the letter iota,
  # \316\271, against the mark that folds to it.
  printf 'zq7pri\316\271vate\n' > "$work/deny.iota2"
  expect_utf8_refusal "a token with the letter iota, written with the subscript mark" 'zq7pri\315\205vate here\n' "$work/deny.iota2" "deny-list token"
  # The list itself may carry the dressing (pasted from a page that had it).
  printf 'zq7\342\200\213private\n' > "$work/deny.zw"
  expect_utf8_refusal "a token saved with a zero-width space, against the plain spelling" 'zq7private here\n' "$work/deny.zw" "deny-list token"
  # A token that is nothing else names no text at all: it must stop the run, since it can
  # neither be matched nor safely ignored.
  printf '\342\200\213\314\201\n' > "$work/deny.bare"
  expect_scan_refusal "a token that is only marks and invisible characters" 'nothing private\n' "$work/deny.bare" "nothing but marks"

  # Controls. The scan only decides; it must not rewrite. A line holding accents and a
  # zero-width space but no token publishes, byte for byte.
  # expect_published <label> <printf format appended> <deny-list>
  expect_published() {
    make_live
    # shellcheck disable=SC2059
    printf "$2" >> "$work/live/commands/audit-claude-md.md"
    # shellcheck disable=SC2059
    printf "$2" > "$work/want.line"
    if ! LC_ALL=$utf8_loc PUBLICISE_DENY="$3" sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.keep" 2>"$work/err"; then
      bad "$1: refused: $(head -1 "$work/err")"
    elif [ "$(tail -n 1 "$work/out.keep" | od -c)" != "$(od -c < "$work/want.line")" ]; then
      bad "$1: published, but the line was changed on the way out"
    else
      ok "$1: published, the line unchanged byte for byte"
    fi
  }
  expect_published "accents and a zero-width space, no token" 'caf\303\251 na\303\257ve\342\200\213 text e\314\201\314\243 here\n' "$work/deny.fold"
  expect_published "all but the last letter of a token" 'zq7privat here, and \303\251quip too\n' "$work/deny.fold"
  expect_published "a token's letters with a visible letter between them" 'zq7xprivate here\n' "$work/deny.utf8"
  # Known limits, pinned so a change in either direction is seen. A letter from another
  # script that looks the same (\320\260 is Cyrillic "а") and a token broken by a space
  # are not seen; the README says so.
  printf 'acme-private\n' > "$work/deny.limit"
  expect_published "known limit: a look-alike letter from another script" '\320\260cme-private here\n' "$work/deny.limit"
  expect_published "known limit: a token broken by a space" 'acme -private here\n' "$work/deny.limit"
fi

echo "7f. red — an exit nobody reported still says why, class line first"
# A live file that exists but cannot be read: `cat` fails and set -e stops the script
# without fail(). The words "Permission denied" lived only in tools.err, which the EXIT
# trap removed, so the caller saw a bare nonzero status. Skipped when running as root,
# which can read the file anyway.
make_live
chmod 000 "$work/live/commands/audit-claude-md.md"
if [ -r "$work/live/commands/audit-claude-md.md" ]; then
  ok "unreadable live file: skipped (this user can read a mode-000 file)"
elif sh "$pub" "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
  bad "an unreadable live file published (exit 0)"
elif head -1 "$work/err" | grep -q '^publicise: \[block\] stopped on an unexpected error' \
     && grep -q -i 'permission denied' "$work/err" && [ ! -s "$work/out.red" ]; then
  ok "an unreadable live file refused as [block] and quoted the tool's reason"
else
  bad "an unreadable live file refused without a class line or a reason: $(head -1 "$work/err")"
fi
chmod 644 "$work/live/commands/audit-claude-md.md"
# --no-rules on a tabled file is a usage refusal raised after stderr is redirected: its
# message must still reach the caller.
make_live
if sh "$pub" --no-rules "$work/live/commands/audit-claude-md.md" > "$work/out.red" 2>"$work/err"; then
  bad "--no-rules on a tabled file was accepted"
elif grep -q 'is in the table and gets its rules regardless' "$work/err"; then
  ok "--no-rules on a tabled file refused, and the reason reached stderr"
else
  bad "--no-rules on a tabled file refused silently: $(head -1 "$work/err")"
fi
# A reader that closes stdout early stops the final write part-way. The exit is nonzero,
# but part of the output went out, so the message must say it may be partial, never
# "Nothing was written" (it did, on a 1 MB file read by `head -c 1`). 1.1 MB is far more
# than a pipe holds, so the write is still running when the reader closes.
yes 'a portable line of plain text that must reach the reader' | head -n 20000 > "$work/stdout-early.md"
( sh "$pub" --no-rules "$work/stdout-early.md" 2>"$work/err" && echo 0 > "$work/st" || echo $? > "$work/st" ) \
  | head -c 1 > "$work/out.red"
st=$(cat "$work/st")
if [ "$st" -eq 0 ]; then
  bad "stdout closed early: publicise exited 0, so the write never stopped and the row tested nothing"
elif head -1 "$work/err" | grep -q '^publicise: \[block\] stopped while writing the output' \
     && ! grep -q 'Nothing was written' "$work/err" && [ -s "$work/out.red" ]; then
  ok "stdout closed early: [block], says the output may be partial (exit $st)"
else
  bad "stdout closed early (exit $st): $(head -1 "$work/err")"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
