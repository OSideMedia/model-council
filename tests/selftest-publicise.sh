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
mkdir -p "$work/live/commands"

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

### Opus 5 (Claude subagent, `model: opus`)
The default worker seat for anything touching code: verification audits, design review,
hard debugging, implementation. $5/$25 — half the chair's rate. Precedent: the 2000-01-01
Opus verification audit caught real findings a single pass missed. Use for "is this
actually correct?" passes over shipped work.

### Codex — GPT-6 / GPT-5.x (`codex exec`, installed)
Independent second implementation, stubborn-bug rescue, cross-vendor code review. Already
wired into the harness via the codex plugin (`codex:rescue` for fix work); for
opinion-only work call
`~/.claude/codex-seat.sh --sandbox read-only -C <repo> - < <brief-file>`
and says so on stderr — never pass `-m` to it. The FAKEHOOK Stop hook goes through
the same wrapper. The codex plugin does not: it leaves the model unset and inherits
`~/.codex/config.toml` (also gpt-6-astra, set from the FAKEAPP app), so if `/codex:rescue`
dies on a usage limit the manual fallback is `/codex:rescue --model gpt-5.6-sol …`. Its
value is exactly that it is NOT Claude.

### Gemini via Antigravity CLI (`agy`, installed)
Body.

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
# FAKEHOOK.py cli_words() is the same rule in Python: keep the two in step.
echo "fixture seat"
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
for token in ACME-PASSES REELS-PASSES private-source-repo privateproj fakerepo FAKEHOOK FAKEAPP FAKELEDGER FAKEOWNER; do
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
  's/Precedent: the 2000-01-01$/Precedent — the 2000-01-01/' \
  "playbook/opus-precedent (opening anchor)"
expect_refusal "opus-precedent terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^Opus verification audit caught real findings/Opus verification audit found real findings/' \
  "playbook/opus-precedent (terminating anchor)"
expect_refusal "codex-plugin-wired opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/cross-vendor code review\. Already$/cross-vendor code review. It is already/' \
  "playbook/codex-plugin-wired (opening anchor)"
expect_refusal "codex-plugin-wired terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^opinion-only work call$/opinion-only work, call/' \
  "playbook/codex-plugin-wired (terminating anchor)"
expect_refusal "stop-hook-config opener" "$work/live/MODEL-PLAYBOOK.md" \
  's/never pass `-m` to it\. The FAKEHOOK/never pass `-m` to it — the FAKEHOOK/' \
  "playbook/stop-hook-config (opening anchor)"
expect_refusal "stop-hook-config terminator" "$work/live/MODEL-PLAYBOOK.md" \
  's/^dies on a usage limit the manual fallback is/dies on a usage limit, the manual fallback is/' \
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
  NR == FNR { if ($0 ~ /^hard debugging, implementation\./) a = $0
              if ($0 ~ /^Opus verification audit caught/) b = $0; next }
  /^hard debugging, implementation\./ || /^Opus verification audit caught/ { next }
  { print }
  /^Routing guide for multi-model work/ { print a; print b }
' "$work/live/MODEL-PLAYBOOK.md" "$work/live/MODEL-PLAYBOOK.md" > "$work/mutated" \
  && mv "$work/mutated" "$work/live/MODEL-PLAYBOOK.md"
grep -q "^Opus verification audit caught" "$work/live/MODEL-PLAYBOOK.md" \
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
st=$(gate)
if [ "$st" -eq 0 ] && grep -q "^SYNC CLEAN — 4 file(s)" "$work/gate.out"; then
  ok "gate: CLEAN after the refresh, all 4 pairs checked"
else
  bad "gate: expected CLEAN over 4 pairs after a refresh, got exit $st: $(tail -1 "$work/gate.out")"
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
# The advice must be the ANCHOR arm's, not the generic fallback: both say "do not
# refresh", so only the anchor-specific sentence pins the arm.
grep -q "Fix the anchor or the live wording" "$work/gate.out" \
  && ok "gate: an anchor refusal gets the anchor-specific advice" \
  || bad "gate: anchor refusal fell through to generic advice: $(grep -A1 'exit 3' "$work/gate.out" | tail -1)"
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
   && grep -q "deny-list is missing or empty" "$work/gate.out" && ! grep -q "Fix the anchor" "$work/gate.out"; then
  ok "gate: a deny-list refusal gets deny-list advice, not 'fix the anchor'"
else
  bad "gate: wrong advice for a deny-list refusal, exit $st: $(grep -E 'Fix the anchor|deny-list' "$work/gate.out" | head -2 | tr '\n' '|')"
fi
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
  grep -q "no deny-list at" "$work/err" \
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

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
