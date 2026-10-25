#!/usr/bin/env bash
# agy-seat.sh — the ONE place the Gemini (Antigravity CLI) model IDs live, and the one
# shape a council seat or a media check runs `agy` in.
#
# WHY. The council named `gemini-3.1-pro-high` in two docs. agy self-updates, and by
# 2026-10-18 (agy 1.4.2) `agy models` listed no Pro tier (Argon and Flash 3.8 only, though
# the Gemini app still offers 3.1 Pro). The seat had been idle, so nobody saw it break.
# Here the slugs live in one file, `--check` reads
# `agy models`, and the run shape is fixed:
#   - the brief is DATA: `--disable-slash-commands`, so `/word` tokens are not expanded;
#   - headless agy denies shell commands and reads OUTSIDE its workspace, but its file
#     viewer opens anything INSIDE the folder it starts in without asking (measured
#     2026-10-18: it read a file from its launch folder). So agy starts in a fresh, empty
#     folder: the seat sees the brief and nothing else. No caller arguments are accepted,
#     so `--dangerously-skip-permissions` and `--model` cannot get in;
#   - every way an answer can be empty or cut short exits non-zero and says so on stderr:
#     a silently empty or truncated seat reads as agreement.
# `--media` copies the named video, audio, image or PDF files (by extension) into that
# folder, and only those, for a check Claude and Codex cannot make: watching a take,
# hearing a VO. In the 2026-10-18 test Argon high read a synthetic clip exactly (colour,
# direction, speed, on-screen words and their seconds) and placed a .wav tone to the
# second and the Hz, and heard the same tone inside the mp4. Flash low misplaced the tone
# and could not hear the mp4's, so media runs on the seat model only.
# `--light` picks the Flash tier for quick text checks; the council seat never passes it.
#
#   ~/.claude/agy-seat.sh < brief                      # council seat
#   ~/.claude/agy-seat.sh --media take.mp4 vo.wav < brief   # watch / listen; brief names files by basename
#   ~/.claude/agy-seat.sh --light < brief              # quick text check
#   ~/.claude/agy-seat.sh --check                      # both slugs listed by `agy models`
#   ~/.claude/agy-seat.sh --selftest                   # model-free, with a fake agy
#
# Exit: 0 answered · 2 refused before any call · 3 agy's own model/agent error (AGY_ERROR)
# · 4 blank answer · 5 cut off by --print-timeout · anything else is agy's. Non-zero = the
# seat is empty; stderr says why.
# Interrupted (HUP/INT/TERM) or not, the workspace and its staged media are removed.
# Environment overrides (tests and one-off experiments only — do not bake into callers):
#   AGY_SEAT_MODEL, AGY_SEAT_LIGHT, AGY_SEAT_BIN (the agy executable), AGY_SEAT_TIMEOUT.
# ponytail: no usage-limit fallback (codex-seat has one): an Antigravity quota failure
# exits non-zero and the council records the seat as empty; add one if that happens.
# ponytail: the brief rides in argv (`-p`), so ARG_MAX (~1 MB on macOS) caps it; agy's
# `--input-format stream-json` reads stdin if a brief ever outgrows that.
# ponytail: --media copies each file; clone or hard-link if multi-GB takes make that slow.
set -uo pipefail

AGY_MODEL="${AGY_SEAT_MODEL:-gemini-4-argon-high}"
AGY_LIGHT_MODEL="${AGY_SEAT_LIGHT:-gemini-3.8-flash-high}"
AGY_BIN="${AGY_SEAT_BIN:-agy}"
AGY_TIMEOUT="${AGY_SEAT_TIMEOUT:-10m}"
# What --media may hand to Gemini: media only. Text belongs in the brief, and a general
# file list is how a .env leaves the machine.
MEDIA_EXT="mp4 mov m4v webm mkv wav mp3 m4a aac flac ogg png jpg jpeg webp gif pdf"

say() { printf 'agy-seat: %s\n' "$*" >&2; }

check_models() {
  if ! command -v "$AGY_BIN" >/dev/null 2>&1; then
    say "UNKNOWN — $AGY_BIN is not installed (curl -fsSL https://antigravity.google/cli/install.sh | bash)"
    return 2
  fi
  local list bad=0 slug
  if ! list="$("$AGY_BIN" models 2>&1)"; then
    say "UNKNOWN — '$AGY_BIN models' failed: ${list:0:200}"
    return 2
  fi
  for slug in "$AGY_MODEL" "$AGY_LIGHT_MODEL"; do
    # whole first field only: a listed `<slug>-preview` must not pass for `<slug>`
    if awk -F'\t' -v s="$slug" '$1 == s { found = 1 } END { exit !found }' <<< "$list"; then
      say "ok   $slug is listed by '$AGY_BIN models'"
    else
      say "FAIL $slug is NOT listed by '$AGY_BIN models' — pick a listed slug and edit the model lines in this file"
      bad=1
    fi
  done
  return $bad
}

# Globals, not locals: the EXIT trap runs after seat() has returned.
SEAT_WS=""; SEAT_ERR=""
cleanup() { rm -rf ${SEAT_WS:+"$SEAT_WS"} ${SEAT_ERR:+"$SEAT_ERR"}; }

seat() { # <model> [--media FILE...] ; the brief on stdin
  local model="$1"; shift
  local media=() f ext base seen="/"
  if [[ "${1:-}" == "--media" ]]; then
    shift
    if [[ $# -eq 0 ]]; then say "refusing: --media needs at least one file"; return 2; fi
    for f in "$@"; do
      ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"; base="${f##*/}"
      if [[ ! -f "$f" || ! -r "$f" ]]; then say "refusing: --media $f is not a readable file"; return 2; fi
      case " $MEDIA_EXT " in *" $ext "*) ;; *)
        say "refusing: --media takes media only ($MEDIA_EXT), not $base — put text in the brief"; return 2 ;;
      esac
      case "$seen" in *"/$base/"*) say "refusing: two --media files are named $base"; return 2 ;; esac
      seen="$seen$base/"; media+=("$f")
    done
    set --
  fi
  if [[ $# -gt 0 ]]; then
    say "refusing: callers pass no arguments (got: $*) — the model and the run shape live in this file"
    return 2
  fi
  if [[ -t 0 ]]; then say "refusing: the brief comes on stdin"; return 2; fi
  local brief; brief="$(cat)"
  # A glob match stops at the first non-space; ${brief//[[:space:]]/} took minutes on a long brief.
  # Not a =~ regex: under a UTF-8 locale it reads a byte that is not valid UTF-8 as blank.
  if [[ $brief != *[![:space:]]* ]]; then say "refusing: empty brief"; return 2; fi
  # Absolute before agy's subshell cds into the workspace: with a relative TMPDIR the
  # stderr redirect would land in a different file and a truncation would pass as 0.
  local tmp; tmp="$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd)" \
    || { say "refusing: TMPDIR ${TMPDIR:-/tmp} is not a folder"; return 2; }
  # bash runs the EXIT trap on HUP/INT/TERM as well (the selftest's SIGTERM case proves it
  # on whichever bash runs it), so one trap covers every way out.
  trap cleanup EXIT
  SEAT_WS="$(mktemp -d "$tmp/agy-seat-ws.XXXXXX")" || { say "refusing: no workspace folder"; return 2; }
  SEAT_ERR="$(mktemp "$tmp/agy-seat-err.XXXXXX")" || { say "refusing: no stderr file"; return 2; }
  for f in ${media[@]+"${media[@]}"}; do
    cp -- "$f" "$SEAT_WS/" || { say "refusing: could not stage $f"; return 2; }
  done
  local out status
  out="$(cd "$SEAT_WS" && "$AGY_BIN" -p "$brief" --model "$model" --disable-slash-commands --sandbox \
    --print-timeout "$AGY_TIMEOUT" 2> "$SEAT_ERR")"
  status=$?
  cat "$SEAT_ERR" >&2
  printf '%s\n' "$out"
  if grep -qF 'returning partial output' "$SEAT_ERR"; then
    status=5; say "TRUNCATED — $model hit --print-timeout $AGY_TIMEOUT mid-answer; record the seat as empty"
  elif [[ $status -eq 0 && $out != *[![:space:]]* ]]; then
    status=4; say "EMPTY answer from $model — record the seat as empty, not as agreement"
  fi
  return $status
}

# ------------------------------------------------------------------------- --selftest
# Model-free. A fake agy, handed in via AGY_SEAT_BIN (never on PATH — the real one may
# be), records its folder, what it can see there, the model, the flags and the brief;
# every branch is proven both ways.
selftest() {
  local work self; work="$(mktemp -d "${TMPDIR:-/tmp}/agy-seat-selftest.XXXXXX")"
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  SELFTEST_TMP="$work"   # not local: the EXIT trap runs after the function returns
  trap 'rm -rf "$SELFTEST_TMP"' EXIT
  local fails=0
  ok()   { echo "  ok    $1"; }
  fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

  cat > "$work/agy" <<'FAKE'
#!/usr/bin/env bash
# fake agy: `models` prints $FAKE_MODELS (or fails on FAKE_ROLE=models-fail); a run
# records ARGV= (the brief shown as <brief>), CWD=, FILES=, MODEL=, BRIEF=, then plays
# $FAKE_ROLE.
if [[ "${1:-}" == "models" ]]; then
  [[ "${FAKE_ROLE:-}" == "models-fail" ]] && { echo "auth expired" >&2; exit 1; }
  printf '%b' "$FAKE_MODELS"; exit 0
fi
model=""; brief=""; argv=""; prev=""
for a in "$@"; do
  if [[ "$prev" == "-p" ]]; then brief="$a"; argv="$argv <brief>"; else argv="$argv $a"; fi
  [[ "$prev" == "--model" ]] && model="$a"
  prev="$a"
done
{ echo "ARGV=${argv# }"; echo "CWD=$PWD"; echo "FILES=$(ls -A | sort | tr '\n' ' ')"
  echo "MODEL=$model"; echo "BRIEF=$brief"; } >> "$FAKE_LOG"
case "$FAKE_ROLE" in
  answer)  echo "answer from $model" ;;
  empty)   printf '\n  \n' ;;
  latin1)  printf '\351t\n' ;;
  fail)    echo "Agent execution terminated due to error." >&2; exit 1 ;;
  agyerr)  echo 'AGY_ERROR: {"status":"UNAVAILABLE"}' >&2; exit 3 ;;
  timeout) echo "partial answ"; echo "[agy] print timeout after 10m0s with turn in progress; returning partial output" >&2 ;;
  hang)    n=0; while [[ ! -e "$FAKE_LOG.release" && $n -lt 100 ]]; do sleep 0.1; n=$((n + 1)); done
           echo "late answer" ;;
esac
FAKE
  chmod +x "$work/agy"
  local log="$work/calls" caller="$work/caller"
  mkdir -p "$caller/d1" "$caller/d2"
  : > "$caller/secret.env"; : > "$caller/take.MP4"; : > "$caller/vo.wav"; : > "$caller/notes.txt"
  : > "$caller/d1/a.mp4"; : > "$caller/d2/a.mp4"
  run_role() { # <role> [args...] ; stdin is the brief; runs from $caller; prints "exit=<n>"
    : > "$log"
    (cd "$caller" && FAKE_ROLE="$1" FAKE_LOG="$log" AGY_SEAT_BIN="$work/agy" bash "$self" "${@:2}" \
      > "$work/last.out" 2> "$work/last.err")
    echo "exit=$?"
  }
  has() { grep -qxF -- "$1" "$log"; }
  # exactly one agy call, or nothing: two CWD records must not pass as one path
  cwd_of() { [[ "$(grep -c '^CWD=' "$log")" == 1 ]] && sed -n 's/^CWD=//p' "$log"; }
  argv_for() { echo "ARGV=-p <brief> --model $1 --disable-slash-commands --sandbox --print-timeout $AGY_TIMEOUT"; }

  local r d
  r="$(printf 'the brief /review x' | run_role answer)"; d="$(cwd_of)"
  if [[ "$r" == "exit=0" ]] && has "$(argv_for "$AGY_MODEL")" && has "BRIEF=the brief /review x" \
      && [[ "$(cat "$work/last.out")" == "answer from $AGY_MODEL" ]]; then
    ok "seat: one call, exactly: -p <brief> --model $AGY_MODEL, slash commands off, sandboxed, timeout"
  else fail "seat: $r log/[$(tr '\n' ' ' < "$log")] out/[$(cat "$work/last.out")]"; fi
  if [[ -n "$d" && "$d" != "$caller" ]] && has "FILES=" && [[ ! -e "$d" ]]; then
    ok "seat: agy runs in a fresh empty folder (not the caller's), removed afterwards"
  else fail "seat workspace: cwd=[$d] caller=[$caller] log/[$(tr '\n' ' ' < "$log")]"; fi

  r="$(printf 'b' | run_role answer --light)"
  if [[ "$r" == "exit=0" ]] && has "$(argv_for "$AGY_LIGHT_MODEL")"; then
    ok "--light: the call runs on $AGY_LIGHT_MODEL"
  else fail "--light: $r log/[$(tr '\n' ' ' < "$log")]"; fi

  r="$(printf 'b' | run_role answer --media take.MP4 vo.wav)"; d="$(cwd_of)"
  if [[ "$r" == "exit=0" ]] && has "$(argv_for "$AGY_MODEL")" && has "FILES=take.MP4 vo.wav " \
      && [[ -n "$d" && "$d" != "$caller" && ! -e "$d" ]]; then
    ok "--media: exactly the named files staged in the fresh folder, on $AGY_MODEL"
  else fail "--media: $r cwd=[$d] log/[$(tr '\n' ' ' < "$log")]"; fi

  local bad
  for bad in "--model x" "--dangerously-skip-permissions" "--light --dangerously-skip-permissions" \
      "--light --media vo.wav" "--media" "--media secret.env" "--media notes.txt" "--media missing.mp4" \
      "--media d1/a.mp4 d2/a.mp4" "--media vo.wav --model x"; do
    # shellcheck disable=SC2086  # word-splitting $bad into arguments is the point
    r="$(printf 'b' | run_role answer $bad)"
    if [[ "$r" == "exit=2" && ! -s "$log" ]]; then
      ok "refused before any call: $bad"
    else fail "caller args '$bad': $r log/[$(tr '\n' ' ' < "$log")]"; fi
  done

  r="$(printf ' \n ' | run_role answer)"
  if [[ "$r" == "exit=2" && ! -s "$log" ]]; then ok "empty brief refused, no call"
  else fail "empty brief: $r"; fi

  # A whole act's brief runs 30-60 KB. bash 3.2's ${brief//[[:space:]]/} is superlinear there
  # (8 KB took 30 s; a 41 KB act read sat in the check for over an hour before agy started).
  local big t0 dt; big="$(awk 'BEGIN { for (i = 0; i < 1200; i++) printf "the brief " }')"
  t0=$SECONDS; r="$(printf '%s' "$big" | run_role answer)"; dt=$((SECONDS - t0))
  if [[ "$r" == "exit=0" && $dt -le 5 ]] && has "BRIEF=$big"; then
    ok "a 12 KB brief clears the blank check in ${dt}s and reaches agy whole"
  else fail "12 KB brief: $r in ${dt}s (the blank check must stay linear)"; fi

  # Text with a byte that is not valid UTF-8 (Latin-1 é) is not blank, under a UTF-8 locale too.
  local utf8 ra; utf8="$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | head -n 1)"
  r="$(printf '\351t' | LC_ALL="$utf8" run_role answer)"
  ra="$(printf 'b' | LC_ALL="$utf8" run_role latin1)"
  if [[ -n "$utf8" && "$r" == "exit=0" && "$ra" == "exit=0" ]]; then
    ok "under $utf8 a Latin-1 brief is sent and a Latin-1 answer is not called empty"
  else fail "Latin-1 under [${utf8:-no UTF-8 locale}]: brief $r, answer $ra (both must be exit=0)"; fi

  r="$(printf 'b' | run_role empty)"
  if [[ "$r" == "exit=4" && "$(cat "$work/last.err")" == *"EMPTY answer"* ]]; then
    ok "blank answer: exit 4, named as an empty seat"
  else fail "blank answer: $r err/[$(cat "$work/last.err")]"; fi

  local err left
  r="$(printf 'b' | run_role timeout)"; err="$(cat "$work/last.err")"
  if [[ "$r" == "exit=5" && "$err" == *"TRUNCATED"* && "$err" == *"returning partial output"* \
      && "$(cat "$work/last.out")" == "partial answ" ]]; then
    ok "print timeout: agy's exit 0 + partial answer becomes exit 5, named as truncated"
  else fail "print timeout: $r err/[$err]"; fi

  : > "$log"
  (cd "$caller" && TMPDIR=. FAKE_ROLE=timeout FAKE_LOG="$log" AGY_SEAT_BIN="$work/agy" bash "$self" \
    <<< "b" > /dev/null 2> "$work/last.err"); r="exit=$?"
  left="$(find "$caller" -maxdepth 1 -name 'agy-seat-*')"
  if [[ "$r" == "exit=5" && -z "$left" ]]; then
    ok "relative TMPDIR: a truncation is still caught (exit 5), nothing left in the caller's folder"
  else fail "relative TMPDIR: $r left/[$left]"; fi

  local role want text
  for role in "fail|1|Agent execution terminated" "agyerr|3|AGY_ERROR"; do
    IFS='|' read -r role want text <<< "$role"
    r="$(printf 'b' | run_role "$role")"; err="$(cat "$work/last.err")"
    if [[ "$r" == "exit=$want" && "$err" == *"$text"* && "$err" != *"EMPTY"* && "$err" != *"TRUNCATED"* ]]; then
      ok "agy failure (exit $want): its exit and stderr pass through, not relabelled"
    else fail "agy failure $role: $r err/[$err]"; fi
  done

  # SIGTERM while agy runs: the staged media must not outlive the wrapper.
  : > "$log"; rm -f "$log.release"; printf 'b' > "$work/brief"
  (cd "$caller" && exec env FAKE_ROLE=hang FAKE_LOG="$log" AGY_SEAT_BIN="$work/agy" bash "$self" \
    --media vo.wav < "$work/brief" > /dev/null 2>&1) &
  local pid=$! n=0 rc
  while ! grep -q '^CWD=' "$log" && [[ $n -lt 100 ]]; do sleep 0.05; n=$((n + 1)); done
  d="$(cwd_of)"
  kill -TERM "$pid" 2>/dev/null; : > "$log.release"; { wait "$pid"; rc=$?; } 2>/dev/null
  if [[ -n "$d" && ! -e "$d" && $rc -ne 0 ]]; then
    ok "SIGTERM mid-call: exits non-zero ($rc) and the staged workspace is removed"
  else fail "SIGTERM mid-call: rc=$rc ws=[$d] still there: $([[ -n "$d" && -e "$d" ]] && echo yes || echo no)"; fi

  chk() { # <models-list> [role] ; prints the exit code
    FAKE_MODELS="$1" FAKE_ROLE="${2:-}" AGY_SEAT_BIN="$work/agy" bash "$self" --check > /dev/null 2> "$work/chk.err"
    echo $?
  }
  local both="$AGY_MODEL\tGemini\n$AGY_LIGHT_MODEL\tFlash\n"
  [[ "$(chk "$both")" == 0 ]] && ok "--check passes when both slugs are listed" \
    || fail "--check on a full list: $(cat "$work/chk.err")"
  [[ "$(chk "$AGY_LIGHT_MODEL\tFlash\n")" == 1 && "$(cat "$work/chk.err")" == *"FAIL $AGY_MODEL"* ]] \
    && ok "--check FAILS when the seat slug is missing" || fail "--check, seat slug missing: $(cat "$work/chk.err")"
  [[ "$(chk "$AGY_MODEL\tGemini\n")" == 1 && "$(cat "$work/chk.err")" == *"FAIL $AGY_LIGHT_MODEL"* ]] \
    && ok "--check FAILS when the light slug is missing" || fail "--check, light slug missing: $(cat "$work/chk.err")"
  [[ "$(chk "$AGY_MODEL-preview\tGemini\n$AGY_LIGHT_MODEL\tFlash\n")" == 1 ]] \
    && ok "--check matches whole slugs: a listed <slug>-preview does not pass for <slug>" \
    || fail "--check took a longer slug for the seat slug: $(cat "$work/chk.err")"
  [[ "$(chk "$both" models-fail)" == 2 && "$(cat "$work/chk.err")" == *"UNKNOWN"* ]] \
    && ok "--check is UNKNOWN (exit 2) when 'agy models' fails" || fail "--check, models failing: $(cat "$work/chk.err")"
  AGY_SEAT_BIN="$work/no-such-agy" bash "$self" --check > /dev/null 2> "$work/chk.err"; local nobin=$?
  [[ $nobin == 2 && "$(cat "$work/chk.err")" == *"not installed"* ]] \
    && ok "--check is UNKNOWN (exit 2) and says so when agy is absent" || fail "--check, agy absent: rc=$nobin"

  if [[ $fails -eq 0 ]]; then echo "agy-seat --selftest: every branch proven both ways"; return 0; fi
  echo "agy-seat --selftest: $fails failure(s)"; return 1
}

case "${1:-}" in
  --check)    check_models ;;
  --selftest) selftest ;;
  --light)
    shift
    if [[ "${1:-}" == "--media" ]]; then
      say "refusing: --media runs on $AGY_MODEL only (Flash misplaced the tone in the 2026-10-18 test)"; exit 2
    fi
    seat "$AGY_LIGHT_MODEL" "$@" ;;
  -h|--help)  awk 'NR > 1 && /^set -uo pipefail/ { exit } NR > 1' "$0" ;;
  *)          seat "$AGY_MODEL" "$@" ;;
esac
