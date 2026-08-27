#!/bin/sh
# refresh-from-live — the fix half of check-upstream-sync's gate.
#
# Deliberately the same transform the gate uses, so "the check is green" and "running
# the fixer changes nothing" are the same statement. Review the diff before committing:
# this repo is public and the live files are not written with an audience in mind.
#
# ALL-OR-NOTHING, and not merely for tidiness. The obvious form —
#     sh publicise.sh "$LIVE/commands/council.md" > "$here/commands/council.md"
# — has the shell truncate the published file BEFORE publicise runs, so a transform
# that correctly refuses (a moved redaction anchor, a deny-list hit) still leaves the
# public copy emptied, and `set -eu` aborts before the remaining files are written.
# The repair step must not be able to damage what it repairs, so every file is
# transformed to a temp first and nothing is moved into place until all of them pass.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LIVE=${LIVE:-$HOME/.claude}
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT INT TERM

# <live-relative-path>  <published-relative-path>
set -- \
  "commands/council.md"         "commands/council.md" \
  "commands/audit-claude-md.md" "commands/audit-claude-md.md" \
  "MODEL-PLAYBOOK.md"           "docs/MODEL-PLAYBOOK.md"

n=0
while [ $# -gt 0 ]; do
  src=$LIVE/$1; dst=$2; shift 2
  if [ ! -f "$src" ]; then
    echo "refresh: live source not found: $src — nothing written." >&2
    exit 2
  fi
  n=$((n + 1))
  # Transform into the staging area. A refusal here exits non-zero under `set -e`
  # with every published file still untouched.
  sh "$here/tests/publicise.sh" "$src" > "$stage/$n"
  eval "dst_$n=\$dst"
done

# Every transform passed. Only now is anything in the repo allowed to change.
i=0
while [ "$i" -lt "$n" ]; do
  i=$((i + 1))
  eval "dst=\$dst_$i"
  cat "$stage/$i" > "$here/$dst"
done

echo "refreshed $n file(s) from $LIVE — review 'git diff' before committing"
