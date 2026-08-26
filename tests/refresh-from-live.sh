#!/bin/sh
# refresh-from-live — the fix half of check-upstream-sync's gate.
#
# Deliberately the same transform the gate uses, so "the check is green" and "running
# the fixer changes nothing" are the same statement. Review the diff before committing:
# this repo is public and the live files are not written with an audience in mind.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LIVE=${LIVE:-$HOME/.claude}
sh "$here/tests/publicise.sh" "$LIVE/commands/council.md"         > "$here/commands/council.md"
sh "$here/tests/publicise.sh" "$LIVE/commands/audit-claude-md.md" > "$here/commands/audit-claude-md.md"
sh "$here/tests/publicise.sh" "$LIVE/MODEL-PLAYBOOK.md"           > "$here/docs/MODEL-PLAYBOOK.md"
echo "refreshed 3 file(s) from $LIVE — review 'git diff' before committing"
