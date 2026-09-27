# shellcheck shell=sh
# pairs — the ONE table of live ↔ published files. Sourced, never run.
#
# Four scripts act on the pair set: publicise.sh decides which basenames carry
# redaction rules, check-upstream-sync.sh decides what to compare, refresh-from-live.sh
# decides what to write, and selftest-publicise.sh decides what to materialise. Each
# used to keep its own list, and they drifted: the fixer knew four pairs while the
# selftest's fixture tree built three and hashed two — so the "fixer writes nothing on a
# refusal" test hit the fixer's missing-fourth-source exit before the write it existed
# to catch, and stayed green against a fixer that bypassed the transform entirely.
# One table, read by all four, cannot drift.
#
# Row: <live path, relative to $LIVE>   <published path, relative to the repo root>
# shellcheck disable=SC2034  # read through the two helpers below
PAIRS='commands/council.md          commands/council.md
commands/audit-claude-md.md  commands/audit-claude-md.md
MODEL-PLAYBOOK.md            docs/MODEL-PLAYBOOK.md
codex-seat.sh                scripts/codex-seat.sh'

# for_each_pair <fn> — calls `fn <live-rel> <published-rel>` once per row, in the
# calling shell (a here-document, not a pipe, so a counter fn bumps survives the loop).
# fn's stdin is /dev/null so a callee that reads stdin cannot eat the rows still to come.
for_each_pair() {
  while read -r pair_live pair_pub; do
    [ -n "$pair_live" ] || continue
    "$1" "$pair_live" "$pair_pub" < /dev/null
  done <<EOF
$PAIRS
EOF
}

# pair_known <basename> — succeeds when some row's live file has that basename.
pair_known() {
  while read -r pair_live _; do
    [ -n "$pair_live" ] || continue
    [ "${pair_live##*/}" = "$1" ] && return 0
  done <<EOF
$PAIRS
EOF
  return 1
}
