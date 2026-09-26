#!/bin/sh
# check-release — the README version badge and the git tags must agree.
#
# The badge is hand-edited and the tag is typed, and nothing tied them together. A tag
# whose README announces the previous version mislabels itself for as long as the tag
# exists, and tags are for practical purposes immutable. So: for every v* tag, the README
# AT THAT TAG must carry the tag's own version — red on any mismatch. HEAD gets an
# advisory only: on a release branch the badge is expected to run ahead of the latest
# tag, and the tag follows the merge.
#
# Zero visible tags is UNKNOWN (exit 2), not a pass: a shallow clone with no tags would
# otherwise certify a subject set of nothing.
#
#   sh tests/check-release.sh              # this checkout
#   REPO=/path sh tests/check-release.sh   # another checkout
#   sh tests/check-release.sh --selftest   # throwaway repo: red on a mislabelled tag, green
#                                          # on a labelled one, advisory on a badge ahead of
#                                          # the tags, UNKNOWN with no tags
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPO=${REPO:-$here}

# badge_at <git-ref | WORKTREE> — the version named by the README's badge, or nothing
badge_at() {
  if [ "$1" = WORKTREE ]; then cat "$REPO/README.md"; else git -C "$REPO" show "$1:README.md" 2>/dev/null || true; fi \
    | sed -n 's/.*img\.shields\.io\/badge\/version-\([0-9][0-9.]*\)-.*/\1/p' | head -1
}

check_repo() {
  tags=$(git -C "$REPO" tag --list 'v*' --sort=v:refname)
  if [ -z "$tags" ]; then
    echo "RELEASE UNKNOWN — no v* tags visible in $REPO (shallow clone? try: git fetch --tags). This is not a pass."
    return 2
  fi
  rc=0; n=0; latest=""
  while read -r tag; do
    [ -n "$tag" ] || continue
    n=$((n + 1)); latest=$tag
    want=${tag#v}; got=$(badge_at "$tag")
    if [ "$got" = "$want" ]; then
      echo "ok       $tag  README badge $got"
    else
      echo "FAIL     $tag  README badge says '${got:-<none>}', the tag says $want"
      rc=1
    fi
  done <<EOF
$tags
EOF
  head_badge=$(badge_at WORKTREE)
  if [ "$head_badge" = "${latest#v}" ]; then
    echo "ok       HEAD  README badge $head_badge matches the latest tag $latest"
  else
    echo "ADVISORY HEAD  README badge ${head_badge:-<none>}, latest tag $latest — if this is the next release, tag v$head_badge after the merge"
  fi
  echo
  if [ "$rc" -eq 0 ]; then
    echo "RELEASE CLEAN — $n tag(s) carry their own version"
  else
    echo "RELEASE MISLABELLED — a tag's README names another version"
  fi
  return $rc
}

selftest() {
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT INT TERM
  pass=0; fail=0
  ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
  bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
  g() { git -C "$work/repo" -c user.name=selftest -c user.email=selftest@example.invalid \
            -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
  badge() {  # <version> — write a README whose badge names it
    printf '[![Version](https://img.shields.io/badge/version-%s-blue)](https://example.invalid/releases/tag/v%s)\n\n# fixture\n' "$1" "$1" \
      > "$work/repo/README.md"
  }
  run() { REPO="$work/repo" sh "$0" > "$work/out" 2>&1 && echo 0 || echo $?; }

  mkdir -p "$work/repo"; g init -q
  badge 1.0.0; g add README.md; g commit -q -m "1.0.0"

  echo "1. no tags is UNKNOWN, not a pass"
  st=$(run)
  [ "$st" -eq 2 ] && grep -q "^RELEASE UNKNOWN" "$work/out" \
    && ok "no v* tags: exit 2, RELEASE UNKNOWN" || bad "no tags exited $st: $(tail -1 "$work/out")"

  echo "2. green — a tag whose README carries its version"
  g tag v1.0.0
  st=$(run)
  [ "$st" -eq 0 ] && grep -q "^ok       v1.0.0" "$work/out" && grep -q "^RELEASE CLEAN — 1 tag" "$work/out" \
    && ok "v1.0.0 with badge 1.0.0: exit 0, RELEASE CLEAN" || bad "labelled tag exited $st: $(tail -1 "$work/out")"

  echo "3. advisory — HEAD badge ahead of the latest tag stays green but says so"
  badge 1.2.0
  st=$(run)
  [ "$st" -eq 0 ] && grep -q "^ADVISORY HEAD  README badge 1.2.0, latest tag v1.0.0" "$work/out" \
    && ok "badge 1.2.0 over tag v1.0.0: exit 0 with the ADVISORY line" || bad "advisory case exited $st: $(cat "$work/out" | tr '\n' '|')"

  echo "4. red — a tag whose README names another version"
  g add README.md; g commit -q -m "badge 1.2.0"; g tag v1.1.0
  st=$(run)
  [ "$st" -eq 1 ] && grep -q "^FAIL     v1.1.0  README badge says '1.2.0', the tag says 1.1.0" "$work/out" \
    && grep -q "^RELEASE MISLABELLED" "$work/out" \
    && ok "v1.1.0 tagged over a 1.2.0 badge: exit 1, FAIL names both versions" || bad "mislabelled tag exited $st: $(cat "$work/out" | tr '\n' '|')"
  grep -q "^ok       v1.0.0" "$work/out" && ok "the correctly labelled tag still passes beside it" \
    || bad "the good tag was dragged down: $(cat "$work/out" | tr '\n' '|')"

  echo "5. red — a tag with no badge at all"
  printf '# no badge here\n' > "$work/repo/README.md"; g add README.md; g commit -q -m "badge lost"; g tag v1.1.1
  st=$(run)
  [ "$st" -eq 1 ] && grep -q "^FAIL     v1.1.1  README badge says '<none>'" "$work/out" \
    && ok "a tag whose README has no badge fails and says <none>" || bad "missing badge exited $st: $(cat "$work/out" | tr '\n' '|')"

  echo
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --selftest) selftest ;;
  "")         check_repo ;;
  *)          echo "usage: check-release.sh [--selftest]" >&2; exit 2 ;;
esac
