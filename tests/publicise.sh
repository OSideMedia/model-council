#!/bin/sh
# publicise — the only sanctioned difference between the live commands and the published ones.
#
# This repo is a PUBLIC release of commands that live at ~/.claude on one machine.
# Almost all of the payload is identical; the exceptions are a handful of spots that are
# true on the author's machine and misleading (or private) in public: a fold-in of local
# review-dimension files, one of which names a private project; a routing line pointing
# at a private source repo; two "installed" parentheticals that read as claims about the
# reader's machine; a precedent citation naming a private repo and a file in it; and a
# handful of machine-state claims (a hook that is wired in, a plugin that is installed, a
# dated private audit, a private billing incident) that are facts here and fiction there.
#
# Copying blind would ship a command that tells its seats to read files nobody has.
# Hand-editing after each copy would mean the two files drift a little more every
# release and nobody could tell an intentional difference from a stale one.
#
# So the difference is a FUNCTION instead of a habit: this script is the only thing
# allowed to differ them, and tests/check-upstream-sync.sh defines the gate as "this
# transform, applied to the live file, reproduces the published file exactly". Gate
# and fix are then the same computation and cannot drift apart.
#
# WHY THE ASSERTIONS (each added after the transform was caught failing open):
# every rule below is anchored on live wording. Reword the anchor upstream — "also fold"
# to "fold in" is enough — and an unguarded rule silently does nothing, exits 0, and
# emits the private paragraph. The sync gate then reports STALE, and its prescribed fix,
# refresh-from-live.sh, WRITES that paragraph into the public repo and goes green. A
# guard whose repair step launders the leak is worse than no guard. So:
#
#   1. Every rule ASSERTS every anchor it depends on — BOTH ends of a block, not only
#      the line that opens it. With only the opener asserted, rewording the closing line
#      ("floor)." to "floor.)") left the skip running to end-of-file: exit 0, the rest of
#      the command gone, nothing said. A missing anchor exits 3 and names the rule.
#   2. A block that opens and never closes in the transformed text is ALSO a refusal
#      (anchors out of order, or an earlier rule consumed one) — the awk says so, exit 3.
#   3. Every output is scanned against a DENY-LIST regardless of which rules fired. This
#      catches private tokens no rule has been written for yet — which is exactly how
#      a private repo name reached the public copy in v1.1.0. The list is normalised
#      before use (CR, surrounding whitespace, comments, blank lines): a list saved with
#      CRLF endings once made every token end in a carriage return and match nothing,
#      and a list of zero surviving tokens is a refusal, not a pass.
#   4. Rules dispatch on the file's basename, and a basename this repo does not publish
#      (see tests/pairs.sh) is a refusal: a renamed live file must not slip through with
#      no rules at all. `--no-rules` is the explicit override for a file that really has
#      none; it is refused on a file the table knows.
#   5. Output is staged and emitted only after every rule and the scan have passed, so
#      a refusal never prints a partial file for a caller to catch by accident.
#
# The residual hole, named rather than papered over: if private content is renamed such
# that BOTH the anchor and its deny-list entry stop matching, no mechanism here can see
# it. Update the deny-list whenever you rename a private file, repo or project.
#
# NOT IDEMPOTENT, deliberately: the assertions mean this script only accepts a LIVE file.
# Feeding it an already-published copy fails loudly instead of silently doing nothing.
#
# Usage: publicise.sh [--no-rules] <live-file>   # writes the public form to stdout
#   exit 0 published form on stdout · 2 usage · 3 REFUSED (reason on stderr, stdout empty)
set -eu

usage() { echo "usage: publicise.sh [--no-rules] <live-file>" >&2; exit 2; }
no_rules=0
if [ "${1:-}" = "--no-rules" ]; then no_rules=1; shift; fi
[ $# -eq 1 ] || usage
[ -f "$1" ] || { echo "publicise: no such file: $1" >&2; exit 2; }

live=$1
name=${live##*/}
here_tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=pairs.sh
. "$here_tests/pairs.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/publicise.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
cur=$work/cur    # the text as transformed so far; emitted only at the very end
nxt=$work/nxt    # the next rule's output, promoted to $cur once the rule has passed

# Tokens that must never appear in a published file: one fixed string per line,
# matched case-insensitively, `#` comments and blank lines ignored.
#
# The list is MACHINE-LOCAL and deliberately not part of this repo. A deny-list
# committed to a public repo publishes the very strings it exists to withhold — which
# is the same class of mistake it is meant to catch. See tests/publicise-deny.example
# for the format; copy it to the path below and fill in your own.
DENY_FILE=${PUBLICISE_DENY:-$HOME/.claude/publicise-deny.txt}

fail() {
  printf 'publicise: %s\n' "$1" >&2
  exit 3
}

require() {  # <anchor-ERE> <rule-name>
  grep -E -q -- "$1" "$live" && return 0
  fail "rule '$2': anchor not found in $live

  The live wording changed, or this is not a live file.
  Next step, in order:
    1. Re-anchor rule '$2' in tests/publicise.sh to the new live wording; or
    2. delete the rule, if the live file intentionally no longer carries that content.
  Do NOT run tests/refresh-from-live.sh until one of those is done — it would
  publish the un-redacted text."
}

advance() { mv -f "$nxt" "$cur"; }

# redact_block <rule> <opening-anchor-ERE> <terminating-anchor-ERE> <replacement-text>
#   Replaces the lines from the opener through the terminator (inclusive) with the
#   replacement. Both anchors are asserted on the live file BEFORE awk runs; the awk
#   then refuses on its own if it reaches end-of-file still inside the block, or never
#   entered it. The anchors travel to awk through the environment — `-v` would
#   re-interpret every backslash in the pattern — and the same ERE is used by grep and
#   awk, so one pattern cannot be found by one and missed by the other.
redact_block() {
  require "$2" "$1 (opening anchor)"
  require "$3" "$1 (terminating anchor)"
  RULE_OPEN=$2 RULE_CLOSE=$3 RULE_REPL=$4 awk '
    BEGIN { opn = ENVIRON["RULE_OPEN"]; cls = ENVIRON["RULE_CLOSE"]; repl = ENVIRON["RULE_REPL"] }
    !skip && $0 ~ opn { skip = 1; next }
    skip  && $0 ~ cls { printf "%s\n", repl; skip = 0; closed = 1; next }
    skip { next }
    { print }
    END { if (skip || !closed) exit 1 }
  ' "$cur" > "$nxt" || fail "rule '$1': both anchors are in $live, but the block did not open and close
  in order in the transformed text (the terminator precedes the opener, or an earlier
  rule already consumed one of them). Nothing was written; fix the rule or the live file."
  advance
}

# redact_line <rule> <anchor-ERE> <replacement-line>
#   Replaces every line matching the anchor with the replacement.
redact_line() {
  require "$2" "$1"
  RULE_RE=$2 RULE_REPL=$3 awk '
    BEGIN { re = ENVIRON["RULE_RE"]; repl = ENVIRON["RULE_REPL"] }
    $0 ~ re { printf "%s\n", repl; hit = 1; next }
    { print }
    END { if (!hit) exit 1 }
  ' "$cur" > "$nxt" || fail "rule '$1': grep found the anchor in $live but awk matched no line in the
  transformed text (an earlier rule consumed it, or the two regex engines disagree
  on the pattern). Nothing was written."
  advance
}

if [ "$no_rules" -eq 1 ] && pair_known "$name"; then
  echo "publicise: --no-rules is for a file outside tests/pairs.sh; '$name' is in the table and gets its rules regardless" >&2
  exit 2
fi

cat -- "$live" > "$cur"

case $name in
  council.md)
    # Replace the local-dimensions paragraph with a portable equivalent. Matching is
    # anchored on the sentence that opens it and the one that closes it, so an edit
    # anywhere else in the file flows through untouched and the gate still sees it.
    redact_block 'council/local-dimensions' \
      '^For security-scoped councils, also fold the infra-first dimensions from$' \
      'pixels-or-payload evidence floor\)\.$' \
      'If the repo (or your own setup) carries a file of domain-specific review
dimensions — infra and secrets for a security-scoped council, spend and
provider-contract surfaces for one over generative-media code — fold it into
the brief and state its confidence floor. Seats cannot see your machine, so
any such dimensions have to travel in the brief itself.'
    ;;

  MODEL-PLAYBOOK.md)
    # The header names the author's project root and private source repo.
    redact_block 'playbook/routing-header' \
      '^Routing guide for multi-model work across all ~/Projects repos\. The overseer \(the main$' \
      '; source of truth:' \
      'Routing guide for multi-model work across your repos. The overseer (the main
Claude Code session) reads this when deciding whether to delegate and to whom.
Install it at `~/.claude/MODEL-PLAYBOOK.md` so that `/council` can read it.'
    # The two "installed" parentheticals state what is true on that machine, which a
    # reader will take as a claim about their own.
    redact_line 'playbook/codex-installed' \
      '^### Codex — GPT-6 / GPT-5\.x \(`codex exec`, installed\)$' \
      '### Codex — GPT-6 / GPT-5.x (`codex exec`)'
    redact_line 'playbook/gemini-installed' \
      '^### Gemini via Antigravity CLI \(`agy`, installed\)$' \
      '### Gemini via Antigravity CLI (`agy`)'
    # Anchored short of the parenthetical on purpose: an anchor that spells the private
    # name would publish it, which is the same mistake the deny-list is kept off-repo to
    # avoid. Everything before the '(' is portable prose and stays.
    redact_line 'playbook/judge-precedent' \
      '^scored against the call log it reads as true \(' \
      'scored against the call log it reads as true (from a judging harness, 2026-08-22).'
    # MACHINE-STATE CLAIMS. The four blocks below are true on the author's machine and
    # read as claims about the reader's: a dated private audit cited as precedent, a
    # plugin "already wired into the harness", a Stop hook and a config file described
    # as the reader's own, and a private billing incident. Each is replaced with what a
    # stranger's machine can actually do. Where a line carries a private name the
    # opening anchor stops short of it (same reason as judge-precedent above); the whole
    # line is replaced regardless of what follows the anchor.
    redact_block 'playbook/opus-precedent' \
      '^hard debugging, implementation\. \$5/\$25 — half the chair'\''s rate\. Precedent: the ' \
      '^Opus verification audit caught real findings a single pass missed\. Use for "is this$' \
      'hard debugging, implementation. $5/$25 — half the chair'\''s rate. A verification pass at
this seat has caught real findings a single pass missed. Use for "is this'
    redact_block 'playbook/codex-plugin-wired' \
      '^Independent second implementation, stubborn-bug rescue, cross-vendor code review\. Already$' \
      '^opinion-only work call$' \
      'Independent second implementation, stubborn-bug rescue, cross-vendor code review. Fix
work can go through the codex plugin (`codex:rescue`) if you have it installed; for
opinion-only work call'
    redact_block 'playbook/stop-hook-config' \
      '^and says so on stderr — never pass `-m` to it\. The ' \
      '^dies on a usage limit the manual fallback is `/codex:rescue --model gpt-5\.6-sol …`\. Its$' \
      'and says so on stderr — never pass `-m` to it. Point every Codex caller you wire up (a
Stop hook, a plugin, an ad-hoc `codex exec`) at the same wrapper. The codex plugin does
not go through it: it leaves the model unset and inherits `~/.codex/config.toml`, so if
`/codex:rescue` dies on a usage limit the manual fallback is
`/codex:rescue --model gpt-5.6-sol …`. Its'
    redact_block 'playbook/ledger-incident' \
      '^is measured, not stylistic: those are the passes where a miss is expensive AND invisible —$' \
      '^repeats its own error and looks identical to a correct one from the inside\.$' \
      'is measured, not stylistic: those are the passes where a miss is expensive AND invisible —
the fail-open sweep, a spend ledger that under-counted with every row present, a map that
repeats its own error and looks identical to a correct one from the inside.'
    ;;

  codex-seat.sh)
    # The header names a hook that exists on the author's machine as one of the seats
    # the wrapper protects. Anchored short of the hook's name.
    redact_block 'seat/stop-hook-mention' \
      '^# spent, `codex exec` dies with "You'\''ve hit your usage limit" and every seat that pinned$' \
      '^# Astra — the /council seat, the ' \
      '# spent, `codex exec` dies with "You'\''ve hit your usage limit" and every seat that pinned
# Astra — the /council seat, any hook you point at Codex, ad-hoc `codex exec` calls —'
    ;;

  *)
    if pair_known "$name"; then
      : # A published file with no redaction rules of its own. It still gets the
        # deny-list scan below, so it cannot leak a known-private token just by being
        # unruled.
    elif [ "$no_rules" -eq 1 ]; then
      : # The caller vouched that this file needs no rules; the scan still runs.
    else
      fail "unknown file '$name': this repo publishes no file by that name (see tests/pairs.sh),
  so no redaction rules exist for it and it would ship with only the deny-list between
  it and the public. Either:
    1. add the pair to tests/pairs.sh and its rules above (a renamed live file); or
    2. re-run with --no-rules if the file genuinely carries nothing to redact.
  Nothing was written."
    fi
    ;;
esac

# Deny-list scan — runs for every file, whether or not any rule fired.
# An unreadable list is a REFUSAL, not a skip: a redaction tool with no idea what is
# private must not be the thing that decides a file is safe to publish.
if [ ! -r "$DENY_FILE" ]; then
  fail "no deny-list at $DENY_FILE

  This is the list of strings that must never reach the published copy. It is
  machine-local by design — committing it here would publish them.
  Next step:
    cp $here_tests/publicise-deny.example \"$DENY_FILE\"
  then edit it to name your own private projects, repos and usernames.
  Override the path with PUBLICISE_DENY=/some/other/file."
fi

# Normalise before use. CR: a list saved with CRLF endings makes every token end in a
# carriage return and match nothing. Surrounding whitespace: a trailing space on a token
# turns "ACME" into "ACME " and misses "ACME.md". Then comments (with or without leading
# indentation) and blank lines go, and what survives is counted.
tr -d '\r' < "$DENY_FILE" \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^#/d; /^$/d' > "$work/deny"
ntokens=$(grep -c '' "$work/deny" || true)
[ "$ntokens" -gt 0 ] || fail "deny-list at $DENY_FILE has no tokens

  Only comments and blank lines survived normalisation. An empty idea of \"private\"
  would pass every file, so this is a refusal. Add the names that only mean something
  inside your own setup — see tests/publicise-deny.example."

while IFS= read -r token; do
  # NB: `grep | head` would report head's exit status (always 0) and fire on every
  # file. Capture first, test the string.
  hit=$(grep -n -i -F -- "$token" "$cur" || true)
  if [ -n "$hit" ]; then
    fail "a deny-list token is present in the output for $live:

$(printf '%s\n' "$hit" | head -3 | sed 's/^/    /')

  This text would have been published. Either add a redaction rule above for it,
  or change the wording in the live file. Nothing was written."
  fi
done < "$work/deny"

cat "$cur"
