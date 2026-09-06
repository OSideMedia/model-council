#!/usr/bin/env bash
# codex-seat.sh — the ONE place the Codex model IDs live, plus the usage-limit fallback.
#
# WHY. GPT-6 Astra landed 2026-09-06 as the priority-1 slug in ~/.codex/models_cache.json
# and, on a ChatGPT subscription, it draws down the usage window faster than the 5.6
# tiers. Codex CLI (0.153.4) has no user-facing model fallback: when the window is
# spent, `codex exec` dies with "You've hit your usage limit" and every seat that pinned
# Astra — the /council seat, the second-opinion Stop hook, ad-hoc `codex exec` calls —
# would simply go empty. This wrapper runs the primary model and, on that specific
# failure, re-runs the same call on the fallback model, saying so on stderr.
#
# Every caller goes through here and NEVER passes `-m`/`--model` itself, so a model
# bump is an edit to the two lines below and nothing else (CLAUDE.md § Model IDs: one
# file per repo). `--check` proves both slugs are still served by the local models
# cache; run it when a seat starts rejecting its model.
#
#   ~/.claude/codex-seat.sh [codex exec args...]      # e.g. --sandbox read-only -C <repo> - < brief
#   ~/.claude/codex-seat.sh --check                   # both slugs present in ~/.codex/models_cache.json
#   ~/.claude/codex-seat.sh --selftest                # model-free: fallback proven to fire AND to stay quiet
#
# Environment overrides (tests and one-off experiments only — do not bake into callers):
#   CODEX_SEAT_PRIMARY, CODEX_SEAT_FALLBACK, CODEX_SEAT_BIN (the codex executable),
#   CODEX_SEAT_MODELS_CACHE (path for --check).
set -uo pipefail

CODEX_PRIMARY_MODEL="${CODEX_SEAT_PRIMARY:-gpt-6-astra}"
CODEX_FALLBACK_MODEL="${CODEX_SEAT_FALLBACK:-gpt-5.6-sol}"

CODEX_BIN="${CODEX_SEAT_BIN:-codex}"
MODELS_CACHE="${CODEX_SEAT_MODELS_CACHE:-$HOME/.codex/models_cache.json}"

# The text Codex prints when the ChatGPT usage window is spent, verbatim from the
# 0.146.0 binary ("You've hit your usage limit. Upgrade to Pro…", "…purchase more
# credits", "…send a request to your admin"), plus the app-server error code and the
# plan-state token that accompany it. Matched case-insensitively.
USAGE_LIMIT_RE="hit your usage limit|usageLimitExceeded|usage_limit_reached"

say() { printf 'codex-seat: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------- --check
# The cache is FILTERED BY THE CLIENT VERSION THAT FETCHED IT (the server drops models
# whose minimal_client_version the caller cannot meet), and the file records that
# version. Measured 2026-09-06: the desktop app's 0.153.4 fetch listed gpt-6-astra; the
# 0.146.0 CLI's fetch six minutes later, same etag, did not. So a slug missing from a
# cache stamped by a different client than the installed CLI is UNKNOWN, never a FAIL —
# the definitive check is a live run, and `-m gpt-6-astra` answered on 0.153.4 while the
# cache on disk still said otherwise.
check_models() {
  if [[ ! -f "$MODELS_CACHE" ]]; then
    say "UNKNOWN — no models cache at $MODELS_CACHE (run any codex command once to fetch it). This is not a pass."
    return 2
  fi
  local cli_ver cache_ver
  cli_ver="$("$CODEX_BIN" --version 2>/dev/null | sed -E 's/^[^0-9]*([0-9][0-9.]*).*/\1/')"
  cache_ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("client_version",""))' "$MODELS_CACHE" 2>/dev/null)"
  local bad=0 slug
  for slug in "$CODEX_PRIMARY_MODEL" "$CODEX_FALLBACK_MODEL"; do
    if python3 - "$MODELS_CACHE" "$slug" <<'PY'
import json, sys
cache, slug = sys.argv[1], sys.argv[2]
models = json.load(open(cache)).get("models", [])
sys.exit(0 if any(m.get("slug") == slug for m in models) else 1)
PY
    then say "ok   $slug is served by the models cache"
    elif [[ -n "$cli_ver" && "$cache_ver" != "$cli_ver" ]]; then
      say "UNKNOWN $slug is not in the cache, but the cache was fetched by client $cache_ver and the installed CLI is $cli_ver — the list is filtered per client, so this is not evidence either way. Prove it live: printf 'Reply OK' | $0 --sandbox read-only --skip-git-repo-check -C /tmp -"
      [[ $bad -eq 0 ]] && bad=2
    else
      say "FAIL $slug is NOT in $MODELS_CACHE (fetched by this CLI, $cli_ver) — pick a listed slug (priority 1 is the frontier) and edit the two model lines in this file; a stale CLI serves a stale list, so 'npm i -g @openai/codex@latest' first"; bad=1
    fi
  done
  return $bad
}

# ----------------------------------------------------------------------- the seat run
# Runs `codex exec -m <model> "$@"` with stdin replayed from a file, capturing stdout
# and stderr to files so the decision can read them. Returns codex's exit status.
run_once() { # <model> <stdin-file> <stdout-file> <stderr-file> [args...]
  local model="$1" in="$2" out="$3" err="$4"; shift 4
  "$CODEX_BIN" exec -m "$model" "$@" < "$in" > "$out" 2> "$err"
}

# The decision, isolated so the selftest can drive it without a process. A run is
# "usage-limited" when the phrase appears in EITHER stream and the run did not also
# produce a real answer with exit 0 — a model that merely TALKS about usage limits in
# a successful reply must not trigger a re-run.
usage_limited() { # <exit-status> <stdout-file> <stderr-file>
  local status="$1" out="$2" err="$3"
  if ! cat "$out" "$err" | grep -Eiq "$USAGE_LIMIT_RE"; then return 1; fi
  if [[ "$status" -eq 0 ]] && grep -q '[^[:space:]]' "$out"; then return 1; fi
  return 0
}

seat() {
  local a
  for a in "$@"; do
    case "$a" in
      -m|--model|-m=*|--model=*)
        say "refusing: callers never pass -m/--model — the model IDs live in this file, and a caller-supplied model has no fallback"
        return 2 ;;
    esac
  done
  # Not `local`: the EXIT trap runs after the function's locals are gone.
  SEAT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-seat.XXXXXX")" || return 1
  trap 'rm -rf "$SEAT_TMP"' EXIT
  local tmp="$SEAT_TMP"
  # stdin is read exactly once here and replayed per attempt; a prompt passed as `-`
  # would otherwise be consumed by the primary run and reach the fallback empty.
  if [[ -t 0 ]]; then : > "$tmp/in"; else cat > "$tmp/in"; fi

  local status
  run_once "$CODEX_PRIMARY_MODEL" "$tmp/in" "$tmp/out1" "$tmp/err1" "$@"; status=$?
  if usage_limited "$status" "$tmp/out1" "$tmp/err1"; then
    say "$CODEX_PRIMARY_MODEL hit its usage limit (exit $status) — falling back to $CODEX_FALLBACK_MODEL"
    run_once "$CODEX_FALLBACK_MODEL" "$tmp/in" "$tmp/out2" "$tmp/err2" "$@"; status=$?
    if usage_limited "$status" "$tmp/out2" "$tmp/err2"; then
      say "$CODEX_FALLBACK_MODEL is ALSO usage-limited (exit $status) — the window is shared or both pools are spent; the seat is empty, not silent"
    fi
    cat "$tmp/err2" >&2; cat "$tmp/out2"
    return $status
  fi
  cat "$tmp/err1" >&2; cat "$tmp/out1"
  return $status
}

# ------------------------------------------------------------------------- --selftest
# Model-free. A fake `codex` on PATH plays four roles; every branch is proven BOTH
# ways (fires / stays quiet), and the stdin replay is proven by having the fake echo
# what it read on the SECOND attempt.
selftest() {
  local work; work="$(mktemp -d "${TMPDIR:-/tmp}/codex-seat-selftest.XXXXXX")"
  local fails=0
  ok()   { echo "  ok    $1"; }
  fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

  cat > "$work/codex" <<'FAKE'
#!/usr/bin/env bash
# fake codex: role from $FAKE_ROLE; records the model it was asked for.
[[ "${1:-}" == "--version" ]] && { echo "codex-cli 9.9.9"; exit 0; }
model=""; while [[ $# -gt 0 ]]; do case "$1" in -m) model="$2"; shift 2;; *) shift;; esac; done
echo "$model" >> "$FAKE_LOG"
body="$(cat)"
case "$FAKE_ROLE" in
  limit-then-ok)   # primary spent, fallback answers and echoes the replayed stdin
    if [[ "$model" == "$FAKE_PRIMARY" ]]; then
      echo "ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro)" >&2; exit 1
    fi
    echo "answer from $model: [$body]"; exit 0 ;;
  always-ok)       echo "answer from $model"; exit 0 ;;
  other-error)     echo "ERROR: stream disconnected before completion" >&2; exit 1 ;;
  talks-about-it)  echo "The usage_limit_reached error means you hit your usage limit; here is the fix."; exit 0 ;;
  both-limited)    echo "You've hit your usage limit." >&2; exit 1 ;;
esac
FAKE
  chmod +x "$work/codex"

  local log="$work/calls"
  run_role() { # <role> [args...] ; prints "exit=<n>" then stdout, stderr to $work/last.err
    : > "$log"
    FAKE_ROLE="$1" FAKE_LOG="$log" FAKE_PRIMARY="$CODEX_PRIMARY_MODEL" \
      CODEX_SEAT_BIN="$work/codex" bash "$0" "${@:2}" > "$work/last.out" 2> "$work/last.err"
    echo "exit=$?"
  }

  # 1. primary limited -> fallback runs, gets the SAME stdin, its answer is what we print
  local r; r="$(printf 'the brief' | run_role limit-then-ok --sandbox read-only -)"
  if [[ "$r" == "exit=0" && "$(cat "$log")" == "$CODEX_PRIMARY_MODEL"$'\n'"$CODEX_FALLBACK_MODEL" \
        && "$(cat "$work/last.out")" == "answer from $CODEX_FALLBACK_MODEL: [the brief]" \
        && "$(grep -c "falling back to $CODEX_FALLBACK_MODEL" "$work/last.err")" == 1 ]]; then
    ok "usage limit on $CODEX_PRIMARY_MODEL -> re-run on $CODEX_FALLBACK_MODEL with stdin replayed, announced on stderr"
  else fail "fallback path: exit/$r calls/[$(tr '\n' ' ' < "$log")] out/[$(cat "$work/last.out")] err/[$(cat "$work/last.err")]"; fi

  # 2. primary answers -> exactly one call, no fallback line
  r="$(printf 'x' | run_role always-ok -)"
  if [[ "$r" == "exit=0" && "$(cat "$log")" == "$CODEX_PRIMARY_MODEL" && ! -s "$work/last.err" ]]; then
    ok "healthy primary: one call, silent"
  else fail "healthy primary: $r calls/[$(tr '\n' ' ' < "$log")] err/[$(cat "$work/last.err")]"; fi

  # 3. a DIFFERENT error must not fall back (it would mask the real failure), exit passes through
  r="$(printf 'x' | run_role other-error -)"
  if [[ "$r" == "exit=1" && "$(cat "$log")" == "$CODEX_PRIMARY_MODEL" && "$(cat "$work/last.err")" == *"stream disconnected"* ]]; then
    ok "other error: no fallback, exit and stderr pass through"
  else fail "other error: $r calls/[$(tr '\n' ' ' < "$log")]"; fi

  # 4. a successful answer that merely mentions the phrase must not trigger a re-run
  r="$(printf 'x' | run_role talks-about-it -)"
  if [[ "$r" == "exit=0" && "$(cat "$log")" == "$CODEX_PRIMARY_MODEL" ]]; then
    ok "answer that talks about usage limits: no fallback"
  else fail "talks-about-it: $r calls/[$(tr '\n' ' ' < "$log")]"; fi

  # 5. both pools spent -> two calls, non-zero exit, and it SAYS the seat is empty
  r="$(printf 'x' | run_role both-limited -)"
  if [[ "$r" == "exit=1" && "$(wc -l < "$log" | tr -d ' ')" == 2 && "$(cat "$work/last.err")" == *"ALSO usage-limited"* ]]; then
    ok "both limited: two calls, exit 1, empty seat named"
  else fail "both limited: $r calls/[$(tr '\n' ' ' < "$log")] err/[$(cat "$work/last.err")]"; fi

  # 6. a caller that pins its own model is refused before any call
  r="$(printf 'x' | run_role always-ok -m gpt-5.6-terra -)"
  if [[ "$r" == "exit=2" && ! -s "$log" ]]; then
    ok "caller-supplied -m refused, no call made"
  else fail "caller -m: $r calls/[$(tr '\n' ' ' < "$log")]"; fi

  # 7. --check reads the cache three ways: present slugs pass; a slug missing from a
  #    cache THIS client fetched fails; a slug missing from a cache ANOTHER client
  #    fetched is UNKNOWN (exit 2) — the filtered-list trap measured 2026-09-06.
  printf '{"client_version":"9.9.9","models":[{"slug":"%s"},{"slug":"%s"}]}' "$CODEX_PRIMARY_MODEL" "$CODEX_FALLBACK_MODEL" > "$work/cache-ok.json"
  printf '{"client_version":"9.9.9","models":[{"slug":"%s"}]}' "$CODEX_FALLBACK_MODEL" > "$work/cache-missing.json"
  printf '{"client_version":"0.146.0","models":[{"slug":"%s"}]}' "$CODEX_FALLBACK_MODEL" > "$work/cache-other-client.json"
  chk() { CODEX_SEAT_BIN="$work/codex" CODEX_SEAT_MODELS_CACHE="$1" bash "$0" --check > /dev/null 2> "$work/chk.err"; echo $?; }
  [[ "$(chk "$work/cache-ok.json")" == 0 ]] && ok "--check passes when both slugs are in the cache" || fail "--check on a complete cache"
  [[ "$(chk "$work/cache-missing.json")" == 1 && "$(cat "$work/chk.err")" == *"FAIL $CODEX_PRIMARY_MODEL"* ]] \
    && ok "--check FAILS when the primary slug is missing from a cache this CLI fetched" || fail "--check did not go red on a missing slug: $(cat "$work/chk.err")"
  [[ "$(chk "$work/cache-other-client.json")" == 2 && "$(cat "$work/chk.err")" == *"UNKNOWN $CODEX_PRIMARY_MODEL"* ]] \
    && ok "--check is UNKNOWN (exit 2) when the cache came from a different client version" || fail "--check mis-judged the other-client cache: $(cat "$work/chk.err")"
  [[ "$(chk "$work/nope.json")" == 2 ]] && ok "--check with no cache is UNKNOWN (exit 2), not a pass" || fail "--check passed with no cache file"

  # 8. the predicate itself, driven directly, on the exact live phrasing
  printf '' > "$work/e"; printf "ERROR: You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits\n" > "$work/o"
  usage_limited 1 "$work/o" "$work/e" && ok "predicate fires on the 0.146.0 wording (stdout, exit 1)" || fail "predicate missed the live wording"
  printf 'real answer\n' > "$work/o"; printf 'usageLimitExceeded\n' > "$work/e"
  usage_limited 0 "$work/o" "$work/e" && fail "predicate fired on exit 0 with a real answer" || ok "predicate quiet on exit 0 + non-empty answer even with the token on stderr"
  printf '' > "$work/o"; printf 'usageLimitExceeded\n' > "$work/e"
  usage_limited 0 "$work/o" "$work/e" && ok "predicate fires on exit 0 with EMPTY stdout and the token on stderr" || fail "predicate missed exit-0-empty-stdout"

  rm -rf "$work"
  if [[ $fails -eq 0 ]]; then echo "codex-seat --selftest: every branch proven both ways"; return 0; fi
  echo "codex-seat --selftest: $fails failure(s)"; return 1
}

case "${1:-}" in
  --check)    check_models ;;
  --selftest) selftest ;;
  -h|--help)  sed -n '2,24p' "$0" ;;
  *)          seat "$@" ;;
esac
