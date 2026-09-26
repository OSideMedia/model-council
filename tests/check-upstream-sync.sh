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
rc=0; checked=0; missing=0

check() {  # <live-rel> <published-rel>
  src=$LIVE/$1; dst=$here/$2
  if [ ! -f "$src" ]; then
    # An absent source is UNKNOWN, never a pass: this machine simply cannot say
    # whether the published copy is current.
    echo "UNKNOWN  $2 — live source not found at $src"
    missing=$((missing + 1))
    return
  fi
  checked=$((checked + 1))
  if sh "$pub" "$src" | diff -u - "$dst" > /tmp/mc-sync.$$ 2>&1; then
    echo "ok       $2"
  else
    echo "STALE    $2 — published copy differs from publicise(live)"
    sed -n '1,40p' /tmp/mc-sync.$$ | sed 's/^/           /'
    rc=1
  fi
  rm -f /tmp/mc-sync.$$
}

for_each_pair check

echo
if [ "$missing" -gt 0 ] && [ "$checked" -eq 0 ]; then
  echo "SYNC UNKNOWN — no live source reachable; this is not a pass."
  exit 2
fi
[ "$rc" -eq 0 ] && echo "SYNC CLEAN — $checked file(s) reproduce from live" \
                || echo "SYNC DRIFTED — regenerate with: sh tests/refresh-from-live.sh"
[ "$missing" -gt 0 ] && echo "($missing file(s) UNCHECKED — see UNKNOWN rows above)"
exit $rc
