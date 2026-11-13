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
# otherwise certify a subject set of nothing. Tags that are visible but were not read are
# UNKNOWN for the same reason.
#
#   sh tests/check-release.sh              # this checkout
#   REPO=/path sh tests/check-release.sh   # another checkout
#   sh tests/check-release.sh --selftest   # throwaway repo: red on a mislabelled tag, green
#                                          # on a labelled one, advisory on a badge ahead of
#                                          # the tags, UNKNOWN with no tags, and never a
#                                          # pass for a mislabelled tag when the shell
#                                          # cannot write a temp file (macOS only: needs
#                                          # sandbox-exec, NOT EXERCISED elsewhere)
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
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
  # How many tags git listed, counted apart from the loop, so the loop is held to it.
  listed=$(( $(printf '%s\n' "$tags" | wc -l) ))
  rc=0; n=0; latest=""
  # A plain word list, not a here-document. /bin/sh on macOS (bash 3.2) writes a
  # here-document to a temp file; where that file cannot be created it skips the loop,
  # and `set -e` does not stop it there, so this function went on to print RELEASE CLEAN
  # for tags it never read. A word list needs no file. Splitting on whitespace is safe:
  # git allows no whitespace in a tag name. Pathname expansion is switched off first,
  # because git does allow names a shell can read as a pattern (v@(1|2) under bash's
  # extglob), and with nullglob such a name would drop out of the list unseen.
  set -f
  for tag in $tags; do
    n=$((n + 1)); latest=$tag
    want=${tag#v}; got=$(badge_at "$tag")
    if [ "$got" = "$want" ]; then
      echo "ok       $tag  README badge $got"
    else
      echo "FAIL     $tag  README badge says '${got:-<none>}', the tag says $want"
      rc=1
    fi
  done
  # The verdict below is about the tags that were read. If that is not every tag git
  # listed, whatever the cause, the answer is UNKNOWN, the same as no tags at all.
  if [ "$n" -ne "$listed" ]; then
    echo "RELEASE UNKNOWN — $REPO lists $listed v* tag(s), but $n of them were checked. This is not a pass."
    return 2
  fi
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
  pass=0; fail=0; skipped=0
  ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
  bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
  skip() { skipped=$((skipped + 1)); echo "  NOT EXERCISED  $1"; }
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

  echo "6. a mislabelled tag is never a pass when the shell cannot create a temp file"
  # The fixture now holds one good tag and two bad ones. This row runs the checker where
  # every file write is denied, as in a read-only sandbox or on a full disk. A shell that
  # needs a temp file to feed the tag loop skips the loop there, and a checker that then
  # carries on certifies the two bad tags it never looked at.
  # sandbox-exec (macOS) is the only way this selftest has to deny writes. Where the
  # denial cannot be built or shown to work, the row is counted apart: it is not a pass.
  deny='(version 1)(allow default)(deny file-write*)(allow file-write* (literal "/dev/null"))'
  nowrite() { sandbox-exec -p "$deny" "$@"; }
  if ! command -v sandbox-exec > /dev/null 2>&1; then
    skip "no sandbox-exec on this machine, so file writes cannot be denied"
  elif ! nowrite sh -c ':' > /dev/null 2>&1; then
    skip "sandbox-exec is here but would not run a shell under the no-write profile"
  elif nowrite sh -c ': > "$1"' sh "$work/probe" 2> /dev/null || [ -e "$work/probe" ]; then
    skip "the no-write profile did not stop a file from being created"
  else
    # Its own output file: if the run never started, an earlier row's verdict must not
    # be standing where this row looks.
    st=$(REPO="$work/repo" nowrite sh "$0" > "$work/out6" 2>&1 && echo 0 || echo $?)
    [ "$st" -ne 0 ] && ! grep -q "^RELEASE CLEAN" "$work/out6" \
      && ok "writes denied, two mislabelled tags: not a pass (exit $st)" \
      || bad "writes denied, two mislabelled tags: exited $st: $(cat "$work/out6" | tr '\n' '|')"
    [ "$st" -eq 1 ] && grep -q "^ok       v1.0.0" "$work/out6" && grep -q "^FAIL     v1.1.0" "$work/out6" \
      && grep -q "^FAIL     v1.1.1" "$work/out6" && grep -q "^RELEASE MISLABELLED" "$work/out6" \
      && ok "writes denied: all three tags are still read, and the two bad ones are named" \
      || bad "writes denied: the three tags were not all read: exited $st: $(cat "$work/out6" | tr '\n' '|')"
  fi

  echo "7. the tag list is not fed through a here-document"
  # Supporting check for row 6, for machines where that row cannot run: a here-document
  # is where the temp file comes from. It reads the text, so it is a heuristic and not
  # the proof: an operator split across two lines gets past it, and one inside a comment
  # or a string trips it. The pattern is split so this line is not a match.
  # grep -c: exit 1 with a count of 0 is the one clean answer; exit 2 is a failed grep.
  hd=$(grep -c '<''<' "$0") && hd_st=0 || hd_st=$?
  [ "$hd_st" -eq 1 ] && [ "$hd" = 0 ] && ok "no here-document in this script" \
    || bad "grep exit $hd_st: this script has ${hd:-an unknown number of} line(s) with a here-document"

  echo "8. a tag whose name the shell can read as a pattern is still checked"
  # git allows v@(1|2) as a tag name. Under bash with extglob and nullglob that word is
  # a pattern, and one that matches no file is dropped, so a loop over the unquoted tag
  # list would lose the tag while the good one beside it kept the run looking complete.
  g2() { git -C "$work/repo2" -c user.name=selftest -c user.email=selftest@example.invalid \
             -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
  mkdir -p "$work/repo2"; g2 init -q
  printf '[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://example.invalid)\n' > "$work/repo2/README.md"
  g2 add README.md; g2 commit -q -m "1.0.0"; g2 tag v1.0.0; g2 tag 'v@(1|2)'
  if ! command -v bash > /dev/null 2>&1; then
    skip "no bash on this machine, so the pattern options cannot be switched on"
  elif ! bash -O extglob -O nullglob -c ':' > /dev/null 2>&1; then
    skip "this bash does not take -O extglob -O nullglob"
  elif ! bash -O extglob -O nullglob -c 'cd "$1" && set -- v@(1|2) && [ "$#" -eq 0 ]' bash "$work" 2> /dev/null; then
    skip "with extglob and nullglob on, the pattern v@(1|2) was not dropped here"
  else
    st=$(REPO="$work/repo2" bash -O extglob -O nullglob "$0" > "$work/out8" 2>&1 && echo 0 || echo $?)
    [ "$st" -ne 0 ] && ! grep -q "^RELEASE CLEAN" "$work/out8" \
      && ok "pattern options on, one mislabelled pattern-named tag: not a pass (exit $st)" \
      || bad "pattern options on: exited $st: $(cat "$work/out8" | tr '\n' '|')"
    [ "$st" -eq 1 ] && grep -q "^ok       v1.0.0" "$work/out8" \
      && grep -qF "FAIL     v@(1|2)  README badge says '1.0.0'" "$work/out8" \
      && ok "pattern options on: the pattern-named tag is read and named as mislabelled" \
      || bad "pattern options on: the pattern-named tag was not read: exited $st: $(cat "$work/out8" | tr '\n' '|')"
  fi

  echo
  [ "$skipped" -eq 0 ] || echo "$skipped row(s) NOT EXERCISED on this machine (see above). That is not a pass for those rows."
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --selftest) selftest ;;
  "")         check_repo ;;
  *)          echo "usage: check-release.sh [--selftest]" >&2; exit 2 ;;
esac
