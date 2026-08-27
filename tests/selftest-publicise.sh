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
#                assertions, this case exited 0 and printed the private text).
#   3. RED     — a private token with no rule written for it is caught by the deny-list.
#   4. RED     — refresh-from-live.sh WRITES NOTHING when the transform refuses. This is
#                the one that matters: the sync gate catches drift, but its prescribed
#                repair used to overwrite the published copy with whatever publicise
#                emitted, so a fail-open transform got laundered to green by the fixer.
#
# Usage: sh tests/selftest-publicise.sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
pass=0; fail=0

ok()   { pass=$((pass + 1)); echo "  ok    $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL  $1"; }

# --- fixtures: a minimal "live" tree carrying every anchor the rules expect ----------
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

### Codex — GPT-5.x (`codex exec`, installed)
Body.

### Gemini via Antigravity CLI (`agy`, installed)
Body.

## Briefing

scored against the call log it reads as true (fakerepo `ops/judge.py`, 2026-08-22 raid).
EOF
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
EOF
PUBLICISE_DENY="$work/deny"; export PUBLICISE_DENY

pub="$here/tests/publicise.sh"

# --- 1. HAPPY PATH -------------------------------------------------------------------
echo "1. happy path — anchored live files publicise cleanly"
for f in "$work/live/commands/council.md" "$work/live/commands/audit-claude-md.md" \
         "$work/live/MODEL-PLAYBOOK.md"; do
  if sh "$pub" "$f" > "$work/out.$(basename "$f")" 2>"$work/err"; then
    ok "$(basename "$f") transformed"
  else
    bad "$(basename "$f") should have transformed: $(cat "$work/err")"
  fi
done
# The output must carry NONE of the private tokens...
for token in ACME-PASSES REELS-PASSES private-source-repo privateproj fakerepo; do
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


# --- 2. RED: a reworded anchor must REFUSE, not silently pass the private text --------
echo "2. red — reworded anchor refuses (the original fail-open regression)"
make_live
# "also fold" -> "fold in": an ordinary edit, and enough to miss the anchor.
sed 's/^For security-scoped councils, also fold the infra-first dimensions from$/For security-scoped councils, fold in the infra-first dimensions from/' \
  "$work/live/commands/council.md" > "$work/mutated.md" && mv "$work/mutated.md" "$work/live/commands/council.md"
if sh "$pub" "$work/live/commands/council.md" > "$work/out.red" 2>"$work/err"; then
  bad "publicise exited 0 on a moved anchor — it emitted:"
  grep -n -i "ACME-PASSES\|privateproj" "$work/out.red" | head -3 | sed 's/^/          /'
else
  ok "publicise refused (exit $?)"
  grep -q "council/local-dimensions" "$work/err" \
    && ok "the error names the rule that lost its anchor" \
    || bad "the error does not name the failing rule"
  [ ! -s "$work/out.red" ] && ok "nothing was emitted on stdout" \
                           || bad "it wrote output despite refusing"
fi

# Same shape on the playbook's heading rule.
make_live
sed 's/^### Codex — GPT-5\.x (`codex exec`, installed)$/### Codex — GPT-5.x (`codex exec`, available)/' \
  "$work/live/MODEL-PLAYBOOK.md" > "$work/mutated.md" && mv "$work/mutated.md" "$work/live/MODEL-PLAYBOOK.md"
if sh "$pub" "$work/live/MODEL-PLAYBOOK.md" >/dev/null 2>"$work/err"; then
  bad "playbook heading rule exited 0 on a moved anchor"
else
  grep -q "playbook/codex-installed" "$work/err" \
    && ok "playbook rule refused and named itself" \
    || bad "playbook rule refused but did not name itself"
fi

# --- 3. RED: deny-list catches a token no rule was written for ------------------------
echo "2c. red — the precedent rule refuses when its anchor moves"
make_live
sed 's/^scored against the call log it reads as true (/scored against the call log it reads true (/' \
  "$work/live/MODEL-PLAYBOOK.md" > "$work/mutated.md" && mv "$work/mutated.md" "$work/live/MODEL-PLAYBOOK.md"
if sh "$pub" "$work/live/MODEL-PLAYBOOK.md" >/dev/null 2>"$work/err"; then
  bad "precedent rule exited 0 on a moved anchor"
else
  grep -q "playbook/judge-precedent" "$work/err" \
    && ok "precedent rule refused and named itself" \
    || bad "refused, but not via the precedent rule: $(head -1 "$work/err")"
fi

echo "3. red — deny-list catches an unruled private token"
make_live
printf 'A new file that mentions the private-source-repo in passing.\n' \
  > "$work/live/commands/some-new-command.md"
if sh "$pub" "$work/live/commands/some-new-command.md" >/dev/null 2>"$work/err"; then
  bad "an unruled file leaked a deny-list token"
else
  grep -q "deny-list token" "$work/err" \
    && ok "deny-list refused a file that has no rules of its own" \
    || bad "refused, but not via the deny-list: $(head -1 "$work/err")"
fi

# --- 4. RED: the fixer must not launder a refusal into a green gate -------------------
echo "4. red — refresh-from-live.sh writes nothing when the transform refuses"
cp -R "$here" "$work/repo"
rm -rf "$work/repo/.git"
before=$(cat "$work/repo/commands/council.md" "$work/repo/docs/MODEL-PLAYBOOK.md" | shasum | cut -d' ' -f1)
make_live
sed 's/^For security-scoped councils, also fold the infra-first dimensions from$/For security-scoped councils, fold in the infra-first dimensions from/' \
  "$work/live/commands/council.md" > "$work/mutated.md" && mv "$work/mutated.md" "$work/live/commands/council.md"
if LIVE="$work/live" sh "$work/repo/tests/refresh-from-live.sh" >/dev/null 2>"$work/err"; then
  bad "refresh-from-live exited 0 with a refusing transform"
else
  ok "refresh-from-live failed instead of publishing"
fi
after=$(cat "$work/repo/commands/council.md" "$work/repo/docs/MODEL-PLAYBOOK.md" | shasum | cut -d' ' -f1)
if [ "$before" = "$after" ]; then
  ok "published files are byte-identical — nothing was laundered"
else
  bad "published files CHANGED while the transform was refusing"
fi

# --- 5. RED: an absent deny-list must refuse, not silently skip the scan -------------
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

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
