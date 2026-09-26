#!/bin/sh
# check-upstream-sync — is this published repo still the live command, or has it rotted?
#
# Why this exists: between v1.0.0 (2026-07-31) and 2026-08-26 the live /council gained
# the falsification gate, the AUDIT-PRECEDENTS fold-in, the domain-passes fold-in, the
# two sovereignty rules and per-finding dispositions. This repo shipped none of them for
# four weeks and said nothing, because nothing was watching the pair. A published tool
# that quietly teaches an older, weaker process is worse than one that is obviously old.
#
# The gate is the canonicaliser form: publicise(live) must equal the published file,
# byte for byte. There is therefore no such thing as an "acceptable small difference" —
# any difference is either stale content or a transform that needs updating, and the
# diff says which.
#
# FOUR VERDICTS PER FILE, and the exit code follows the worst of them:
#   ok       publicise(live) == published                                  exit 0
#   STALE    they differ — regenerate with tests/refresh-from-live.sh      exit 1
#   REFUSED  publicise itself refused (a moved anchor, a deny-list hit)    exit 1
#   UNKNOWN  no live source on this machine — cannot say either way       exit 2
# REFUSED is its own verdict because it used to masquerade as STALE: `publicise | diff`
# under POSIX sh has no pipefail, so a refusal's exit 3 was lost and its stderr swallowed,
# and the gate printed "regenerate with refresh-from-live.sh" — the one command a refusal
# forbids, since the fixer would publish exactly what the transform had refused. And
# UNKNOWN is never a pass, whether one file is missing or all of them: the old form
# exited 0 and said "SYNC CLEAN" with three of four checked.
#
# The pair set comes from tests/pairs.sh, shared with the fixer and the selftest.
#
# LIVE is where the commands actually run. Override for a different machine:
#   LIVE=/path/to/.claude sh tests/check-upstream-sync.sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LIVE=${LIVE:-$HOME/.claude}
pub="$here/tests/publicise.sh"
# shellcheck source=pairs.sh
. "$here/tests/pairs.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
checked=0; stale=0; refused=0; missing=0; absent=""

check() {  # <live-rel> <published-rel>
  src=$LIVE/$1; dst=$here/$2
  if [ ! -f "$src" ]; then
    echo "UNKNOWN  $2 — live source not found at $src"
    missing=$((missing + 1)); absent="$absent $1"
    return
  fi
  checked=$((checked + 1))
  # Run the transform to a file, not into a pipe: the exit code and stderr are the
  # verdict when it refuses, and a pipe drops both.
  sh "$pub" "$src" > "$work/out" 2> "$work/err" && st=0 || st=$?
  if [ "$st" -ne 0 ]; then
    echo "REFUSED  $2 — publicise exit $st:"
    sed 's/^/           /' "$work/err"
    echo "           Fix the anchor or the live wording (see above); do NOT run"
    echo "           tests/refresh-from-live.sh — it would publish what was refused."
    refused=$((refused + 1))
    return
  fi
  if diff -u "$work/out" "$dst" > "$work/diff" 2>&1; then
    echo "ok       $2"
  else
    echo "STALE    $2 — published copy differs from publicise(live)"
    sed -n '1,40p' "$work/diff" | sed 's/^/           /'
    stale=$((stale + 1))
  fi
}

for_each_pair check

echo
if [ "$refused" -gt 0 ]; then
  echo "SYNC REFUSED — $refused file(s) refused by the transform; fix the anchor or wording first, do not refresh"
  rc=1
elif [ "$stale" -gt 0 ]; then
  echo "SYNC DRIFTED — $stale file(s) stale; regenerate with: sh tests/refresh-from-live.sh"
  rc=1
elif [ "$missing" -gt 0 ]; then
  echo "SYNC UNKNOWN — $missing live source(s) not found:$absent — this is not a pass."
  rc=2
else
  echo "SYNC CLEAN — $checked file(s) reproduce from live"
  rc=0
fi
[ "$missing" -eq 0 ] || [ "$rc" -eq 2 ] || echo "($missing file(s) UNCHECKED — see UNKNOWN rows above:$absent)"
exit $rc
