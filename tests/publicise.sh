#!/bin/sh
# publicise — the only sanctioned difference between the live commands and the published ones.
#
# This repo is a PUBLIC release of commands that live at ~/.claude on one machine.
# Almost all of the payload is identical; the exceptions are a handful of spots that are
# true on the author's machine and misleading (or private) in public: a fold-in of local
# review-dimension files, one of which names a private project; a routing line pointing
# at a private source repo; two "installed" parentheticals that read as claims about the
# reader's machine; and a precedent citation naming a private repo and a file in it.
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
# WHY THE ASSERTIONS (added after the transform was tested against an ordinary edit):
# every rule below is anchored on live wording. Reword the anchor upstream — "also fold"
# to "fold in" is enough — and an unguarded rule silently does nothing, exits 0, and
# emits the private paragraph. The sync gate then reports STALE, and its prescribed fix,
# refresh-from-live.sh, WRITES that paragraph into the public repo and goes green. A
# guard whose repair step launders the leak is worse than no guard. So:
#
#   1. Every rule ASSERTS its anchor. A missing anchor exits non-zero and names the rule.
#      refresh-from-live.sh runs `set -eu`, so a failed assertion kills the write.
#   2. Every output is scanned against a DENY-LIST regardless of which rules fired. This
#      catches private tokens no rule has been written for yet — which is exactly how
#      a private repo name reached the public copy in v1.1.0.
#
# The residual hole, named rather than papered over: if private content is renamed such
# that BOTH the anchor and its deny-list entry stop matching, no mechanism here can see
# it. Update the deny-list whenever you rename a private file, repo or project.
#
# NOT IDEMPOTENT, deliberately: the assertions mean this script only accepts a LIVE file.
# Feeding it an already-published copy fails loudly instead of silently doing nothing.
#
# Usage: publicise.sh <live-file>   # writes the public form to stdout
set -eu
[ $# -eq 1 ] || { echo "usage: publicise.sh <live-file>" >&2; exit 2; }
[ -f "$1" ] || { echo "publicise: no such file: $1" >&2; exit 2; }

live=$1
name=$(basename "$live")
here_tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tmp=${TMPDIR:-/tmp}/publicise.$$
trap 'rm -f "$tmp"' EXIT INT TERM

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

require() {  # <anchor-BRE> <rule-name>
  grep -q "$1" "$live" && return 0
  fail "rule '$2': anchor not found in $live

  The live wording changed, or this is not a live file.
  Next step, in order:
    1. Re-anchor rule '$2' in tests/publicise.sh to the new live wording; or
    2. delete the rule, if the live file intentionally no longer carries that content.
  Do NOT run tests/refresh-from-live.sh until one of those is done — it would
  publish the un-redacted text."
}

case "$name" in
  council.md)
    require '^For security-scoped councils, also fold the infra-first dimensions from$' \
            'council/local-dimensions'
    # Replace the local-dimensions paragraph with a portable equivalent. Matching is
    # anchored on the sentence that opens it, so an edit anywhere else in the file
    # flows through untouched and the gate still sees it.
    awk '
      /^For security-scoped councils, also fold the infra-first dimensions from$/ { skip = 1 }
      skip && /pixels-or-payload evidence floor\)\.$/ {
        print "If the repo (or your own setup) carries a file of domain-specific review"
        print "dimensions — infra and secrets for a security-scoped council, spend and"
        print "provider-contract surfaces for one over generative-media code — fold it into"
        print "the brief and state its confidence floor. Seats cannot see your machine, so"
        print "any such dimensions have to travel in the brief itself."
        skip = 0
        next
      }
      skip { next }
      { print }
    ' "$live" > "$tmp"
    ;;

  MODEL-PLAYBOOK.md)
    require '^Routing guide for multi-model work across all ~/Projects repos\. The overseer (the main$' \
            'playbook/routing-header'
    require '^### Codex — GPT-5\.x (`codex exec`, installed)$' \
            'playbook/codex-installed'
    require '^### Gemini via Antigravity CLI (`agy`, installed)$' \
            'playbook/gemini-installed'
    # Anchored short of the parenthetical on purpose: an anchor that spells the private
    # name would publish it, which is the same mistake the deny-list is kept off-repo to
    # avoid. Everything before the '(' is portable prose and stays.
    require '^scored against the call log it reads as true (' \
            'playbook/judge-precedent'
    # The header names the author's project root and private source repo; the two
    # "installed" parentheticals state what is true on that machine, which a reader
    # will take as a claim about their own.
    awk '
      /^Routing guide for multi-model work across all ~\/Projects repos\. The overseer \(the main$/ { skip = 1 }
      skip && /; source of truth:/ {
        print "Routing guide for multi-model work across your repos. The overseer (the main"
        print "Claude Code session) reads this when deciding whether to delegate and to whom."
        print "Install it at `~/.claude/MODEL-PLAYBOOK.md` so that `/council` can read it."
        skip = 0
        next
      }
      skip { next }
      { sub(/^### Codex — GPT-5\.x \(`codex exec`, installed\)$/, "### Codex — GPT-5.x (`codex exec`)")
        sub(/^### Gemini via Antigravity CLI \(`agy`, installed\)$/, "### Gemini via Antigravity CLI (`agy`)")
        sub(/^scored against the call log it reads as true \(.*$/, "scored against the call log it reads as true (from a judging harness, 2026-08-22).")
        print }
    ' "$live" > "$tmp"
    ;;

  *)
    # No redaction rules for this file. It still gets the deny-list scan below, so a
    # newly synced file cannot leak a known-private token just by being unlisted.
    cat "$live" > "$tmp"
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

while IFS= read -r token || [ -n "$token" ]; do
  case $token in ''|'#'*) continue ;; esac
  # NB: `grep | head` would report head's exit status (always 0) and fire on every
  # file. Capture first, test the string.
  hit=$(grep -n -i -F -- "$token" "$tmp" || true)
  if [ -n "$hit" ]; then
    fail "a deny-list token is present in the output for $live:

$(printf '%s\n' "$hit" | head -3 | sed 's/^/    /')

  This text would have been published. Either add a redaction rule above for it,
  or change the wording in the live file. Nothing was written."
  fi
done < "$DENY_FILE"

cat "$tmp"
