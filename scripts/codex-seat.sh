#!/usr/bin/env bash
# codex-seat.sh — the ONE place the Codex model IDs live, plus the usage-limit fallback.
#
# WHY. GPT-6 Astra landed 2026-09-06 as the priority-1 slug in ~/.codex/models_cache.json
# and, on a ChatGPT subscription, it draws down the usage window faster than the 5.6
# tiers. Codex CLI (0.153.4) has no user-facing model fallback: when the window is
# spent, `codex exec` dies with "You've hit your usage limit" and every seat that pinned
# Astra — the /council seat, any hook you point at Codex, ad-hoc `codex exec` calls —
# would simply go empty. This wrapper runs the primary model and, on that specific
# failure, re-runs the same call on the fallback model, saying so on stderr.
#
# PRIMARY became GPT-6.1 Sol because, on a subscription, review rounds on Astra at high
# effort spend the usage window fast, and at Standard rates
# (developers.openai.com/codex/pricing) the same tokens cost ~6x less on 6.1 Sol. That
# needed CLI >= 0.163.0: 0.153.4's catalog did not list it.
#
# PRIMARY is now GPT-6.2 Sol: the
# same Standard credit rate as 6.1 Sol on that pricing page. CLI 0.163.0's catalog does
# not list it and 0.170.0's does, so the model line and the VERIFIED_CLI line moved
# together. Use Astra only when you ask for it by name; it is now GPT-6.2 Astra: for that
# one run, `CODEX_SEAT_PRIMARY=gpt-6.2-astra` in front of the wrapper. Nothing selects
# it otherwise.
#
# Every caller goes through here and NEVER passes `-m`/`--model` itself, so a model
# bump is an edit to the model lines below and nothing else (CLAUDE.md § Model IDs: one
# file per repo). `--check` proves every slug is still served by the local models
# cache; run it when a seat starts rejecting its model. `--light` swaps the primary for
# the light tier (docs-only reviews, simple checks: MODEL-PLAYBOOK's tier table); the
# fallback is the same. The council seat and any review hook never pass it.
#
#   ~/.claude/codex-seat.sh [seat args...] -           # e.g. --sandbox read-only -C <repo> - < brief
#   ~/.claude/codex-seat.sh --light [seat args...] -   # the same, on the light tier
#   ~/.claude/codex-seat.sh --check                   # every slug present in ~/.codex/models_cache.json
#   ~/.claude/codex-seat.sh --selftest                # model-free: every branch proven both ways
#
# A READ-ONLY SEAT since 2026-11. The arguments are NOT handed to `codex
# exec`. The wrapper builds the argv itself (see "the read-only argv" below) and accepts
# only these, as separate words, each at most once, ending in the one `-`:
#   -s|--sandbox read-only    --ignore-user-config    --color never     (already fixed; accepted so callers need not change)
#   -C|--cd DIR               --skip-git-repo-check   --ephemeral
#   --disable NAME (a known feature name)   --output-schema FILE    -o|--output-last-message FILE
#   -c|--config model_reasoning_effort=low|medium|high|xhigh    -c|--config web_search=disabled
# Anything else exits 2 before any process starts: a writable sandbox, a
# --dangerously-bypass flag, any other -c (an MCP server, a provider), --enable,
# --add-dir, a profile, an image, a positional prompt, a repeated flag. The brief comes
# on stdin. It also exits 2 unless `codex --version` answers exactly VERIFIED_CLI.
#
# A SHORT ENVIRONMENT since 2026-11-17. codex is started with a fixed list of variable
# names and nothing else (see "the seat's environment" below): the launching session's
# API keys, tokens, SSH agent socket and proxy URLs reach neither codex nor the commands
# the model runs, and the shell those commands run in reads none of the account's zsh
# profile files. It is also started with the `apps` feature off, which is what offered
# the model the account's remote connector tools.
#
# Environment overrides (tests and one-off experiments only — do not bake into callers):
#   CODEX_SEAT_PRIMARY, CODEX_SEAT_LIGHT, CODEX_SEAT_FALLBACK, CODEX_SEAT_BIN (the codex
#   executable), CODEX_SEAT_MODELS_CACHE (path for --check). The wrapper reads them;
#   codex is not handed them.
set -uo pipefail

CODEX_PRIMARY_MODEL="${CODEX_SEAT_PRIMARY:-gpt-6.2-sol}"
CODEX_LIGHT_MODEL="${CODEX_SEAT_LIGHT:-gpt-6-luna}"
CODEX_FALLBACK_MODEL="${CODEX_SEAT_FALLBACK:-gpt-5.6-sol}"

CODEX_BIN="${CODEX_SEAT_BIN:-codex}"
# The one CLI version the read-only guarantees were measured on (tests/codex-seat-probe.py).
VERIFIED_CLI="0.170.0"
MODELS_CACHE="${CODEX_SEAT_MODELS_CACHE:-$HOME/.codex/models_cache.json}"

# The text Codex prints when the ChatGPT usage window is spent, verbatim from the
# 0.146.0 binary ("You've hit your usage limit. Upgrade to Pro…", "…purchase more
# credits", "…send a request to your admin"), plus the app-server error code and the
# plan-state token that accompany it. Matched case-insensitively.
USAGE_LIMIT_RE="hit your usage limit|usageLimitExceeded|usage_limit_reached"

say() { printf 'codex-seat: %s\n' "$*" >&2; }

# ------------------------------------------------------------- the seat's environment
# Every start of the codex executable goes through seat_codex, the --version question
# included, and gets the variables named here and nothing else (env -i). So the session
# that launched the seat cannot hand codex, or the commands the model runs, a variable it
# happens to hold: an API key, a session or messaging token, SSH_AUTH_SOCK, a proxy URL,
# OPENAI_BASE_URL, the CODEX_SEAT_* overrides. Measured 2026-11-17 on codex-cli 0.163.0
# with a made-up workspace and two made-up variables: before, the model's shell printed
# both; after, neither, and the review, the sign-in and git still worked.
#
# The names are the seat allowlist of another tool of the author's (its own evidence
# was read earlier, and is not published here), which real Codex seats
# have run on since then. Each is here for a reader that was found:
#   PATH        the launcher is `#!/usr/bin/env node`; codex, git and rg are found by name
#   HOME        the sign-in is ~/.codex/auth.json
#   TMPDIR      codex's own work files (the account's folder, not the shared /tmp)
#   SHELL       the shell codex runs the model's commands in
#   LOGNAME, LANG, LC_*, TERM   codex hands them to its children; it warns without a
#               UTF-8 locale and drops colour for TERM=dumb
#   CODEX_HOME  moves codex's config and sign-in (the author's probe relies on it
#               for a private home with no login)
#   SSL_CERT_FILE, CODEX_CA_CERTIFICATE   a certificate bundle, on a machine that has one
# A name is passed only when the seat inherited it, with its value unchanged. LC_* is the
# closed POSIX list, not a prefix: a prefix would pass LC_ANYTHING.
# Not passed, on purpose: USER (no reader found); every proxy variable (a proxy URL can
# hold a password; a machine that needs a proxy adds the name here
# with its evidence); OPENAI_API_KEY and OPENAI_BASE_URL (the seat signs in with the
# ChatGPT login and pins the provider); PWD and OLDPWD (codex is given its folder as
# the working directory and by -C).
#
# One variable is SET, not passed: ZDOTDIR, to an empty folder only root can write. zsh
# reads its per-account files (.zshenv, .zprofile, .zshrc, .zlogin) from $ZDOTDIR, so
# the shell codex runs the model's commands in reads none of the account's. Without it
# the short list is undone one step later. Measured 2026-11-17, same CLI, a made-up HOME
# with a made-up export in each of .zshenv, .zprofile and .zshrc: all three names reached
# the model's command without ZDOTDIR, none with it, and the review, git and the
# read-only sandbox behaved as before. Two codex switches were measured as well and each
# stops only part of it (--disable shell_snapshot: .zshrc; with allow_login_shell=false
# also .zprofile; .zshenv neither).
# The cost: those commands get no alias, function or PATH entry the profile would add.
# PATH is the one the seat was started with, in its order (allow_login_shell=false in the
# fixed flags below is what keeps the order). A caller's own ZDOTDIR is not passed.
# ponytail: zsh only, which is the account shell on macOS; an account whose shell is
# bash reads ~/.bash_profile whatever this says, and needs its own answer.
# Not claimed: the system's own zsh files under /etc are still read (zshenv by every
# zsh). Code that runs INSIDE this wrapper before its first line (a caller's BASH_ENV
# file) can change anything here, the list included: this is a guard against variables
# a session happens to hold, not against a caller that runs its own code in the seat.
# And all of this limits what is INHERITED, not what can be READ: under the read-only
# sandbox a command can still read any file the account can, ~/.zshrc included.
SEAT_ZDOTDIR="/var/empty"
SEAT_ENV_NAMES="PATH HOME TMPDIR SHELL LOGNAME LANG LC_ALL LC_COLLATE LC_CTYPE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME TERM CODEX_HOME SSL_CERT_FILE CODEX_CA_CERTIFICATE"
# env reads a leading word that holds '=' as a variable, so such a path would not be run
# as the program; refused here rather than misread there.
if [[ "$CODEX_BIN" == *=* ]]; then
  say "refusing: the codex executable's path, $(printf '%q' "$CODEX_BIN"), holds '=', which env would read as a variable and not as a program. Nothing was run."
  exit 2
fi
seat_codex() { # [codex args...]
  # Exported names only: a bash started without SHELL or TERM sets them for itself, and
  # a plain "is it set" test would hand codex a variable the caller never had.
  local n kept=() exported; exported=" $(compgen -e | tr '\n' ' ')"
  for n in $SEAT_ENV_NAMES; do
    if [[ "$exported" == *" $n "* ]]; then kept+=("$n=${!n}"); fi
  done
  # bash 3.2 (macOS): an empty array under `set -u` is "unbound", hence the ${a[@]+…} form.
  /usr/bin/env -i ${kept[@]+"${kept[@]}"} ZDOTDIR="$SEAT_ZDOTDIR" "$CODEX_BIN" "$@"
}

# ---------------------------------------------------------------------------- --check
# The cache is FILTERED BY THE CLIENT VERSION THAT FETCHED IT (the server drops models
# whose minimal_client_version the caller cannot meet), and the file records that
# version. Measured 2026-09-06: the desktop app's 0.153.4 fetch listed gpt-6-astra; the
# 0.146.0 CLI's fetch six minutes later, same etag, did not. So a slug missing from a
# cache stamped by a different client than the installed CLI is UNKNOWN, never a FAIL —
# the definitive check is a live run, and `-m gpt-6-astra` answered on 0.153.4 while the
# cache on disk still said otherwise.
check_models() {
  # The absent BINARY is judged first (r2): with no codex and no cache, "no models
  # cache — run any codex command" sent the reader to a CLI that is not installed.
  if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
    say "UNKNOWN — the codex binary '$CODEX_BIN' is not on PATH (or not executable), so the cache cannot be judged against the installed CLI and there is no seat to prove live. This is not a pass; install the version this wrapper was verified on: 'npm i -g @openai/codex@$VERIFIED_CLI'."
    return 2
  fi
  if [[ ! -f "$MODELS_CACHE" ]]; then
    say "UNKNOWN — no models cache at $MODELS_CACHE (run any codex command once to fetch it). This is not a pass."
    return 2
  fi
  # The two ways the reader itself can fail are judged FIRST, as UNKNOWN naming the
  # reason. They used to fall through to the per-slug loop, where a python3 that is
  # not there or a cache that will not parse looks exactly like "slug missing"
  # (2026-09-26 audit) — a tooling failure reported as a model-catalogue fact.
  if ! command -v python3 >/dev/null 2>&1; then
    say "UNKNOWN — python3 is not on PATH, so the models cache cannot be read. This is not a pass; install python3 or prove the seat live."
    return 2
  fi
  if ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["models"]' "$MODELS_CACHE" >/dev/null 2>&1; then
    say "UNKNOWN — the models cache at $MODELS_CACHE is malformed (not JSON, or no \"models\" key). This is not a pass; delete it and run any codex command to refetch."
    return 2
  fi
  local cli_ver cache_ver
  cli_ver="$(seat_codex --version 2>/dev/null | sed -E 's/^[^0-9]*([0-9][0-9.]*).*/\1/')"
  cache_ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("client_version",""))' "$MODELS_CACHE" 2>/dev/null)"
  local bad=0 slug
  for slug in "$CODEX_PRIMARY_MODEL" "$CODEX_LIGHT_MODEL" "$CODEX_FALLBACK_MODEL"; do
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
      say "FAIL $slug is NOT in $MODELS_CACHE (fetched by this CLI, $cli_ver) — the three model lines in this file (primary, light, fallback) need listed slugs (priority 1 is the frontier), changed through the normal review. Do not upgrade the CLI to get a newer list: the seat runs only on codex-cli $VERIFIED_CLI, and a newer CLI needs tests/codex-seat-probe.py to hold on it, an independent review and explicit approval before the VERIFIED_CLI line changes"; bad=1
    fi
  done
  return $bad
}

# ----------------------------------------------------------------------- the seat run
# Runs `codex exec -m <model> "$@"` with stdin replayed from a file, capturing stdout
# and stderr to files so the decision can read them. Returns codex's exit status.
run_once() { # <model> <stdin-file> <stdout-file> <stderr-file> [args...]
  local model="$1" in="$2" out="$3" err="$4"; shift 4
  seat_codex exec -m "$model" "$@" < "$in" > "$out" 2> "$err"
}

# What the CLI itself said. `codex exec` writes its whole TRANSCRIPT to stderr (the
# banner, the prompt WITH the brief or diff, every command the model ran and its
# output), so the phrase anywhere is not a verdict: a review of code that QUOTES
# "hit your usage limit" read as a spent seat, re-ran on the fallback and announced
# an empty seat (2026-10-05). The CLI's own words sit BEFORE the
# "OpenAI Codex v" banner, or in the run of ERROR:/Error: lines that ENDS the stream,
# read from the bottom past any trailer: `tokens used` and its count, or the indented
# or bracketed lines of a JSON error body (fourth fallback read). A diff line never
# starts with "ERROR:", and the scan stops at the first ordinary line above the run,
# so neither a quoted diff nor earlier command output can pass for the CLI.
# ponytail: a failed run with NO closing error that ends in indented command output
# under a quoted ERROR line is still misread; not seen in any real capture.
# Any hook that re-implements cli_words() (in Python, say) must keep the two in step.
cli_words() { # <stderr-file>
  awk '/^OpenAI Codex v/ { banner = 1; n = 0; next }
       !banner { print; next }
       { sub(/\r$/, "") }
       /^[[:space:]]*$/ { next }
       { last[++n] = $0 }
       END {
         i = n
         while (i >= 1 && (last[i] ~ /^tokens used$/ || last[i] ~ /^[0-9][0-9,]*$/ || last[i] ~ /^[]{}"[:space:]]/)) i--
         j = i
         while (j >= 1 && last[j] ~ /^(ERROR|Error):/) j--
         for (m = j + 1; m <= i; m++) print last[m]
       }' "$1" 2>/dev/null
}

# The decision, isolated so the selftest can drive it without a process. A run is
# "usage-limited" when the CLI's own words carry the phrase and the run did not also
# produce a real answer with exit 0 — a model that merely TALKS about usage limits in
# a successful reply must not trigger a re-run. stdout is read WHOLE: the 0.146.0 CLI
# printed the error there (test 8), and exec-mode stdout carries only the final
# answer, never the transcript. Only stderr is cut down to the CLI's own words.
usage_limited() { # <exit-status> <stdout-file> <stderr-file>
  local status="$1" out="$2" err="$3" words
  # Read into a variable and test THAT — never `cat … | grep -q`. With pipefail,
  # grep -q exiting on an early match sends cat SIGPIPE on a stream larger than the
  # pipe buffer, the pipeline reports 141, and the negation read "no match": the
  # predicate inverted on exactly the big-output runs it exists for (2026-09-26).
  words="$(cat "$out" 2>/dev/null; cli_words "$err")"
  if ! grep -Eiq "$USAGE_LIMIT_RE" <<< "$words"; then return 1; fi
  if [[ "$status" -eq 0 ]] && grep -q '[^[:space:]]' "$out"; then return 1; fi
  return 0
}

# ------------------------------------------------------------- the read-only argv
# The seat is a READ-ONLY reviewer. It does not pass the caller's words to
# `codex exec`: it reads them, refuses anything it does not know, and builds the argv
# itself. Measured on the real CLI at VERIFIED_CLI (tests/codex-seat-probe.py):
#   --sandbox read-only        beats a trusted project's sandbox_mode; only the
#                              --dangerously-bypass flags beat it, and those are refused
#   --ignore-user-config       drops the user's config.toml (its MCP servers, its
#                              openai_base_url) AND project trust, so a project .codex/
#                              config, MCP server or hook does not load
#   --disable hooks            a user hooks.json is not covered by --ignore-user-config
#   --disable plugins          the only switch seen to change startup (no plugin fetches)
#   --disable apps             measured 2026-11-17 on a live seat run: with it the model's
#                              tool list held none of the account's remote connector tools
#                              (without it the list held mcp__codex_apps__ names). Whether the
#                              model could CALL one with approvals off was not tested
#   -c model_provider="openai" the built-in provider, which no config may redefine
#   -c allow_login_shell=false the model's commands run in a plain shell, not a login one.
#                              A login zsh runs the system's path_helper, which puts the
#                              system folders FIRST in PATH; a profile may then
#                              put its own back in front, and the seat no longer lets that
#                              profile be read (ZDOTDIR above). Measured 2026-11-17 on a
#                              live run: without this one tool resolved differently
#                              than in the caller, with it every tool resolved as before
#   -c web_search="disabled"   chosen for the review seat; its effect on the real
#                              provider is not measured
# Not claimed: system, MDM or cloud-managed Codex policy; which built-in tools the model
# is offered (its own shell, patch and image-viewing tools stay); what a sandboxed
# command reads or sends; the CODEX_SEAT_* and CODEX_HOME overrides; any other CLI
# version (refused below).
DISABLE_NAMES="apps plugins remote_plugin browser_use browser_use_external browser_use_full_cdp_access computer_use in_app_browser image_generation multi_agent hooks skill_mcp_dependency_install tool_suggest"
refuse() { say "refusing: $*"; }
shown() { printf '%q' "$1"; }   # an argument, safe to print (control characters escaped)
unsafe_path() { [[ -z "$1" || "$1" == -* || "$1" == *[[:cntrl:]]* ]]; }

# Reads the caller's arguments into SEAT_ARGV (everything after `exec -m <model>`).
# Returns 2, having said why, on anything outside the list. Separate-word spellings only.
build_argv() {
  local sandbox=0 ignore=0 color=0 skip=0 eph=0 dash=0 web=0
  local have_cd=0 cd_dir="" have_out=0 out_file="" have_schema=0 schema="" effort="" v
  local seen_disables=" " extra_disables=()
  once() { # <count so far> <name>
    if [[ "$1" -ne 0 ]]; then refuse "$2 given more than once"; return 2; fi
  }
  while [[ $# -gt 0 ]]; do
    if [[ $dash -eq 1 ]]; then refuse "$(shown "$1") comes after the final '-'; '-' is the last word, once"; return 2; fi
    case "$1" in
      -) dash=1; shift; continue ;;
      -s|--sandbox|--color|-C|--cd|--disable|--output-schema|-o|--output-last-message|-c|--config)
        if [[ $# -lt 2 ]]; then refuse "$1 needs a value"; return 2; fi
        v="$2" ;;
    esac
    case "$1" in
      -s|--sandbox)
        if [[ "$v" != read-only ]]; then refuse "$1 $(shown "$v"): the seat runs read-only and nothing else"; return 2; fi
        once $sandbox "--sandbox" || return 2; sandbox=1; shift 2 ;;
      --ignore-user-config) once $ignore "$1" || return 2; ignore=1; shift ;;
      --color)
        if [[ "$v" != never ]]; then refuse "--color $(shown "$v"): the seat prints no colour codes (--color never)"; return 2; fi
        once $color "--color" || return 2; color=1; shift 2 ;;
      --skip-git-repo-check) once $skip "$1" || return 2; skip=1; shift ;;
      --ephemeral) once $eph "$1" || return 2; eph=1; shift ;;
      -C|--cd)
        once $have_cd "-C/--cd" || return 2
        if unsafe_path "$v"; then refuse "-C $(shown "$v"): the directory is empty, starts with '-' or holds a control character"; return 2; fi
        if [[ ! -d "$v" ]]; then refuse "-C $(shown "$v"): not an existing directory"; return 2; fi
        have_cd=1; cd_dir="$v"; shift 2 ;;
      -o|--output-last-message)
        once $have_out "-o/--output-last-message" || return 2
        if unsafe_path "$v"; then refuse "-o $(shown "$v"): the path is empty, starts with '-' or holds a control character"; return 2; fi
        have_out=1; out_file="$v"; shift 2 ;;
      --output-schema)
        once $have_schema "--output-schema" || return 2
        if unsafe_path "$v"; then refuse "--output-schema $(shown "$v"): the path is empty, starts with '-' or holds a control character"; return 2; fi
        if [[ ! -f "$v" ]]; then refuse "--output-schema $(shown "$v"): not an existing file"; return 2; fi
        have_schema=1; schema="$v"; shift 2 ;;
      --disable)
        # Only the names the verified CLI was seen to accept (probe row d1). A name the
        # CLI does not know would be answered with an error that ECHOES the name, and a
        # name such as usage_limit_reached would then read as a spent usage window.
        # The character test comes first: "apps plugins" (two names, one word) is a
        # substring of the list and would otherwise pass the membership test.
        case "$v" in *[!a-z0-9_]*|"") refuse "--disable $(shown "$v"): not one of the feature names the seat knows"; return 2 ;; esac
        case " $DISABLE_NAMES " in
          *" $v "*) : ;;
          *) refuse "--disable $(shown "$v"): not one of the feature names the seat knows ($DISABLE_NAMES)"; return 2 ;;
        esac
        if [[ "$seen_disables" == *" $v "* ]]; then refuse "--disable $v given more than once"; return 2; fi
        seen_disables+="$v "
        [[ "$v" == hooks || "$v" == plugins || "$v" == apps ]] || extra_disables+=("$v")
        shift 2 ;;
      -c|--config)
        case "$v" in
          model_reasoning_effort=low|model_reasoning_effort=medium|model_reasoning_effort=high|model_reasoning_effort=xhigh|\
          'model_reasoning_effort="low"'|'model_reasoning_effort="medium"'|'model_reasoning_effort="high"'|'model_reasoning_effort="xhigh"')
            if [[ -n "$effort" ]]; then refuse "-c model_reasoning_effort given more than once"; return 2; fi
            effort="${v#model_reasoning_effort=}"; effort="${effort#\"}"; effort="${effort%\"}" ;;
          web_search=disabled|'web_search="disabled"')
            once $web "-c web_search" || return 2; web=1 ;;
          *) refuse "-c $(shown "$v"): the only settings a caller may pass are model_reasoning_effort (low|medium|high|xhigh) and web_search=disabled"; return 2 ;;
        esac
        shift 2 ;;
      -m|--model|-m=*|--model=*)
        refuse "$(shown "$1"): callers never pass -m/--model — the model IDs live in this file, and a caller-supplied model has no fallback"; return 2 ;;
      --light) refuse "--light is the first word or it is not given"; return 2 ;;
      "") refuse "an empty argument"; return 2 ;;
      *) refuse "$(shown "$1") is not an argument the read-only seat accepts (see the header of $0; separate-word spellings only, no positional prompt)"; return 2 ;;
    esac
  done
  if [[ $dash -ne 1 ]]; then refuse "the argument list must end with '-': the brief comes on stdin"; return 2; fi

  SEAT_ARGV=(--sandbox read-only --ignore-user-config --color never -c 'model_provider="openai"' -c 'web_search="disabled"' -c 'allow_login_shell=false' --disable hooks --disable plugins --disable apps)
  # bash 3.2 (macOS): an empty array under `set -u` is "unbound", hence the ${a[@]+…} form.
  for v in ${extra_disables[@]+"${extra_disables[@]}"}; do SEAT_ARGV+=(--disable "$v"); done
  [[ -n "$effort" ]] && SEAT_ARGV+=(-c "model_reasoning_effort=\"$effort\"")
  [[ $have_cd -eq 1 ]] && SEAT_ARGV+=(-C "$cd_dir")
  [[ $skip -eq 1 ]] && SEAT_ARGV+=(--skip-git-repo-check)
  [[ $eph -eq 1 ]] && SEAT_ARGV+=(--ephemeral)
  [[ $have_schema -eq 1 ]] && SEAT_ARGV+=(--output-schema "$schema")
  [[ $have_out -eq 1 ]] && SEAT_ARGV+=(-o "$out_file")
  SEAT_ARGV+=(-)
  return 0
}

# The guarantees above were measured on ONE CLI version. Any other answer from
# `codex --version` — a different version, a failure, nothing, more than the one line —
# refuses: a flag that changed meaning would otherwise fail open and look the same.
verified_cli() {
  local out rc
  # $(…) strips every trailing newline, so "the one line" would also match the line
  # followed by blank ones. The x keeps them; the answer must be the line and ONE newline.
  out="$(seat_codex --version 2>/dev/null; rc=$?; printf x; exit $rc)"; rc=$?
  out="${out%x}"
  if [[ $rc -eq 0 && "$out" == "codex-cli $VERIFIED_CLI"$'\n' ]]; then return 0; fi
  refuse "the read-only guarantees were measured on codex-cli $VERIFIED_CLI, and '$CODEX_BIN --version' answered exit $rc, $(shown "${out:0:80}"). Nothing was run. After a CLI upgrade: this published copy cannot be re-verified from here, because the probe the guarantees were measured with (codex-seat-probe.py) is kept with the wrapper's source and not in this repository. Install the verified version ('npm i -g @openai/codex@$VERIFIED_CLI') or take a later release of this wrapper that was verified on the newer CLI."
  return 2
}

seat() {
  # Order matters: the arguments are judged before any process starts, the version
  # before any `codex exec`. A refusal is exit 2 and is never retried or fallen back from.
  build_argv "$@" || return 2
  verified_cli || return 2
  # Not `local`: the EXIT trap runs after the function's locals are gone.
  SEAT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-seat.XXXXXX")" || return 1
  trap 'rm -rf "$SEAT_TMP"' EXIT
  local tmp="$SEAT_TMP"
  # stdin is read exactly once here and replayed per attempt; a prompt passed as `-`
  # would otherwise be consumed by the primary run and reach the fallback empty.
  if [[ -t 0 ]]; then : > "$tmp/in"; else cat > "$tmp/in"; fi

  local status
  run_once "$CODEX_PRIMARY_MODEL" "$tmp/in" "$tmp/out1" "$tmp/err1" "${SEAT_ARGV[@]}"; status=$?
  if usage_limited "$status" "$tmp/out1" "$tmp/err1"; then
    say "$CODEX_PRIMARY_MODEL hit its usage limit (exit $status) — falling back to $CODEX_FALLBACK_MODEL"
    run_once "$CODEX_FALLBACK_MODEL" "$tmp/in" "$tmp/out2" "$tmp/err2" "${SEAT_ARGV[@]}"; status=$?
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
# Model-free. A fake `codex`, handed in via CODEX_SEAT_BIN (never on PATH — the real
# one may be), plays five roles; every branch is proven BOTH ways (fires / stays
# quiet), and the stdin replay is proven by having the fake echo what it read on the
# SECOND attempt. The fake's settings are a file beside it (fake.conf), not variables:
# the seat hands codex none of its caller's variables, so a FAKE_* one would not arrive.
selftest() {
  local work; work="$(mktemp -d "${TMPDIR:-/tmp}/codex-seat-selftest.XXXXXX")"
  # Not `local`: the EXIT trap fires after the function's locals are gone.
  SELFTEST_TMP="$work"
  trap 'rm -rf "$SELFTEST_TMP"' EXIT
  local fails=0
  ok()   { echo "  ok    $1"; }
  fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

  cat > "$work/codex" <<'FAKE'
#!/usr/bin/env bash
# fake codex: its settings from fake.conf beside it (plain assignments, not exported);
# records the exported names it was started with, then the model it was asked for.
. "${0%/*}/fake.conf"
seen_env() { # <version|exec> : the names, and (when asked) the values, of THIS start; appended, never overwritten
  printf '%s %s\n' "$1" "$(compgen -e | LC_ALL=C sort | tr '\n' ' ')" >> "${FAKE_ENVLOG:-/dev/null}"
  [[ -n "${FAKE_VALUES:-}" ]] || return 0
  for _n in $FAKE_VALUE_NAMES; do printf '%s %s=%s\n' "$1" "$_n" "${!_n-<unset>}"; done >> "$FAKE_VALUES"
}
if [[ "${1:-}" == "--version" ]]; then
  seen_env version
  echo version >> "${FAKE_VLOG:-/dev/null}"
  if [[ -n "${FAKE_VERSION_OUT+x}" ]]; then printf '%s' "$FAKE_VERSION_OUT"; else echo "codex-cli $FAKE_CLI"; fi
  exit "${FAKE_VERSION_RC:-0}"
fi
seen_env exec
{ echo CALL; printf '%s\n' "$@"; } >> "${FAKE_ARGV:-/dev/null}"
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
  banner-limited)  # real 0.153.4 shape: banner, header, prompt, then the ERROR that ends it
    if [[ "$model" == "$FAKE_PRIMARY" ]]; then
      printf 'OpenAI Codex v0.153.4\n--------\nmodel: %s\n--------\nuser\n%s\n' "$model" "$body" >&2
      echo "ERROR: You've hit your usage limit. Upgrade to Pro" >&2; exit 1
    fi
    echo "answer from $model"; exit 0 ;;
  midreview-limited)  # the limit hit after model turns, the token count printed after the ERROR
    if [[ "$model" == "$FAKE_PRIMARY" ]]; then
      printf 'OpenAI Codex v0.153.4\n--------\nuser\n%s\ncodex\nlooking\nexec\nls\n' "$body" >&2
      printf 'ERROR: You'"'"'ve hit your usage limit.\ntokens used\n12,345\n' >&2; exit 1
    fi
    echo "answer from $model"; exit 0 ;;
  transcript-quotes-it)  # a review of code that QUOTES the phrase, failing for another reason
    printf 'OpenAI Codex v0.153.4\n--------\nuser\n+ USAGE_LIMIT_RE="hit your usage limit"\n' >&2
    printf 'exec\nERROR: You'"'"'ve hit your usage limit.\ncodex\nERROR: stream disconnected before completion\n' >&2
    exit 1 ;;
esac
FAKE
  chmod +x "$work/codex"

  local log="$work/calls" argv="$work/argv" vlog="$work/version-calls" envlog="$work/env-seen"
  conf() { # NAME=value... : the fake's settings, the whole file replaced each time
    local kv; : > "$work/fake.conf"
    for kv in "$@"; do printf '%s=%q\n' "${kv%%=*}" "${kv#*=}" >> "$work/fake.conf"; done
  }
  run_role() { # <role> [args...] ; prints "exit=<n>" then stdout, stderr to $work/last.err
    : > "$log"; : > "$argv"; : > "$vlog"; : > "$envlog"
    conf FAKE_ROLE="$1" FAKE_LOG="$log" FAKE_ARGV="$argv" FAKE_VLOG="$vlog" FAKE_ENVLOG="$envlog" FAKE_CLI="$VERIFIED_CLI" \
      FAKE_PRIMARY="${FAKE_PRIMARY_AS:-$CODEX_PRIMARY_MODEL}"
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

  # 5b. the real banner-shaped quota failure still falls back (the trailing ERROR counts)
  r="$(printf 'brief' | run_role banner-limited -)"
  if [[ "$r" == "exit=0" && "$(wc -l < "$log" | tr -d ' ')" == 2 ]]; then
    ok "banner-shaped quota failure: the ERROR ending the transcript triggers the fallback"
  else fail "banner-limited: $r calls/[$(tr '\n' ' ' < "$log")] err/[$(cat "$work/last.err")]"; fi

  # 5b2. the limit hit mid-review, the token count AFTER the ERROR: still the fallback
  r="$(printf 'brief' | run_role midreview-limited -)"
  if [[ "$r" == "exit=0" && "$(wc -l < "$log" | tr -d ' ')" == 2 ]]; then
    ok "quota ERROR followed by the token count: still triggers the fallback"
  else fail "midreview-limited: $r calls/[$(tr '\n' ' ' < "$log")]"; fi

  # 5c. a failed review whose TRANSCRIPT quotes the phrase is NOT a spent seat:
  # one call, no fallback, no "ALSO usage-limited", the real error passes through
  r="$(printf 'x' | run_role transcript-quotes-it -)"
  if [[ "$r" == "exit=1" && "$(cat "$log")" == "$CODEX_PRIMARY_MODEL" \
        && "$(cat "$work/last.err")" != *"falling back"* && "$(cat "$work/last.err")" == *"stream disconnected"* ]]; then
    ok "transcript that quotes the phrase: no fallback, the real error passes through"
  else fail "transcript-quotes-it: $r calls/[$(tr '\n' ' ' < "$log")] err/[$(head -c 300 "$work/last.err")]"; fi

  # 6. a caller that pins its own model is refused before any call
  r="$(printf 'x' | run_role always-ok -m gpt-5.6-terra -)"
  if [[ "$r" == "exit=2" && ! -s "$log" ]]; then
    ok "caller-supplied -m refused, no call made"
  else fail "caller -m: $r calls/[$(tr '\n' ' ' < "$log")]"; fi

  # 6b. --light: one call on the light model, the fallback unchanged, -m still refused
  r="$(printf 'x' | run_role always-ok --light -)"
  if [[ "$r" == "exit=0" && "$(cat "$log")" == "$CODEX_LIGHT_MODEL" && ! -s "$work/last.err" ]]; then
    ok "--light: one call on $CODEX_LIGHT_MODEL, silent"
  else fail "--light: $r calls/[$(tr '\n' ' ' < "$log")] err/[$(cat "$work/last.err")]"; fi
  r="$(printf 'the brief' | FAKE_PRIMARY_AS="$CODEX_LIGHT_MODEL" run_role limit-then-ok --light -)"
  if [[ "$r" == "exit=0" && "$(cat "$log")" == "$CODEX_LIGHT_MODEL"$'\n'"$CODEX_FALLBACK_MODEL" \
        && "$(cat "$work/last.out")" == "answer from $CODEX_FALLBACK_MODEL: [the brief]" ]]; then
    ok "--light usage-limited -> the same fallback, stdin replayed"
  else fail "--light fallback: $r calls/[$(tr '\n' ' ' < "$log")] out/[$(cat "$work/last.out")]"; fi
  r="$(printf 'x' | run_role always-ok --light -m gpt-5.6-terra -)"
  if [[ "$r" == "exit=2" && ! -s "$log" ]]; then
    ok "--light with a caller-supplied -m: refused, no call made"
  else fail "--light -m: $r calls/[$(tr '\n' ' ' < "$log")]"; fi

  # 7. --check reads the cache three ways: present slugs pass; a slug missing from a
  #    cache THIS client fetched fails; a slug missing from a cache ANOTHER client
  #    fetched is UNKNOWN (exit 2) — the filtered-list trap measured 2026-09-06.
  printf '{"client_version":"'"$VERIFIED_CLI"'","models":[{"slug":"%s"},{"slug":"%s"},{"slug":"%s"}]}' "$CODEX_PRIMARY_MODEL" "$CODEX_LIGHT_MODEL" "$CODEX_FALLBACK_MODEL" > "$work/cache-ok.json"
  printf '{"client_version":"'"$VERIFIED_CLI"'","models":[{"slug":"%s"},{"slug":"%s"}]}' "$CODEX_LIGHT_MODEL" "$CODEX_FALLBACK_MODEL" > "$work/cache-missing.json"
  printf '{"client_version":"'"$VERIFIED_CLI"'","models":[{"slug":"%s"},{"slug":"%s"}]}' "$CODEX_PRIMARY_MODEL" "$CODEX_FALLBACK_MODEL" > "$work/cache-no-light.json"
  printf '{"client_version":"0.146.0","models":[{"slug":"%s"}]}' "$CODEX_FALLBACK_MODEL" > "$work/cache-other-client.json"
  chk() { conf FAKE_CLI="$VERIFIED_CLI"; CODEX_SEAT_BIN="$work/codex" CODEX_SEAT_MODELS_CACHE="$1" bash "$0" --check > /dev/null 2> "$work/chk.err"; echo $?; }
  [[ "$(chk "$work/cache-ok.json")" == 0 ]] && ok "--check passes when both slugs are in the cache" || fail "--check on a complete cache"
  [[ "$(chk "$work/cache-missing.json")" == 1 && "$(cat "$work/chk.err")" == *"FAIL $CODEX_PRIMARY_MODEL"* ]] \
    && ok "--check FAILS when the primary slug is missing from a cache this CLI fetched" || fail "--check did not go red on a missing slug: $(cat "$work/chk.err")"
  [[ "$(chk "$work/cache-no-light.json")" == 1 && "$(cat "$work/chk.err")" == *"FAIL $CODEX_LIGHT_MODEL"* ]] \
    && ok "--check FAILS when the light slug is missing" || fail "--check did not go red on a missing light slug: $(cat "$work/chk.err")"
  [[ "$(chk "$work/cache-other-client.json")" == 2 && "$(cat "$work/chk.err")" == *"UNKNOWN $CODEX_PRIMARY_MODEL"* ]] \
    && ok "--check is UNKNOWN (exit 2) when the cache came from a different client version" || fail "--check mis-judged the other-client cache: $(cat "$work/chk.err")"
  # R13 (r3): assert the REASON, not just the exit — a missing file also fails the
  # malformed-cache parse, so exit 2 alone passed even with this branch deleted.
  [[ "$(chk "$work/nope.json")" == 2 && "$(cat "$work/chk.err")" == *"no models cache"* ]] \
    && ok "--check with no cache is UNKNOWN (exit 2) and says 'no models cache', not a pass" || fail "--check with no cache: err=[$(cat "$work/chk.err")]"
  # 7b. (2026-09-26 audit) a MALFORMED cache and a missing python3 are UNKNOWN too,
  #     and say WHICH — they used to fall into the slug-missing branch and misreport.
  printf '{"client_version": "0.163.0", "models": [' > "$work/cache-broken.json"
  [[ "$(chk "$work/cache-broken.json")" == 2 && "$(cat "$work/chk.err")" == *"UNKNOWN"* && "$(cat "$work/chk.err")" == *"malformed"* ]] \
    && ok "--check on a malformed cache is UNKNOWN (exit 2) and names the reason" || fail "--check mis-judged a malformed cache: rc=$(chk "$work/cache-broken.json") err=[$(cat "$work/chk.err")]"
  # 7c. (model-council read, 2026-09-26) the codex BINARY absent: cli_ver came back
  #     empty, a missing slug took the FAIL branch and printed "fetched by this CLI, )".
  #     UNKNOWN (exit 2), naming the binary — the cache cannot be judged against a CLI
  #     that is not there, and a seat with no binary is not a seat.
  CODEX_SEAT_BIN="$work/no-such-codex" CODEX_SEAT_MODELS_CACHE="$work/cache-missing.json" bash "$0" --check > /dev/null 2> "$work/chk.err"; local nobin_rc=$?
  [[ $nobin_rc == 2 && "$(cat "$work/chk.err")" == *"UNKNOWN"* && "$(cat "$work/chk.err")" == *"no-such-codex"* ]] \
    && ok "--check with the codex binary absent is UNKNOWN (exit 2) and names the binary" || fail "--check with codex absent: rc=$nobin_rc err=[$(cat "$work/chk.err")]"
  # 7d. (r2) codex absent AND no cache: the binary is the first thing wrong, so it is
  #     the reason named — "no models cache" sent the reader to refetch with a CLI
  #     that is not installed.
  CODEX_SEAT_BIN="$work/no-such-codex" CODEX_SEAT_MODELS_CACHE="$work/nope.json" bash "$0" --check > /dev/null 2> "$work/chk.err"; local nobin2_rc=$?
  [[ $nobin2_rc == 2 && "$(cat "$work/chk.err")" == *"no-such-codex"* && "$(cat "$work/chk.err")" != *"no models cache"* ]] \
    && ok "--check with codex absent AND no cache names the absent binary first" || fail "--check absent binary + no cache: rc=$nobin2_rc err=[$(cat "$work/chk.err")]"
  mkdir -p "$work/nopy"; local t; for t in sed grep cat mktemp rm wc tr; do ln -sf "$(command -v "$t")" "$work/nopy/$t"; done
  PATH="$work/nopy" CODEX_SEAT_BIN="$work/codex" CODEX_SEAT_MODELS_CACHE="$work/cache-ok.json" "$BASH" "$0" --check > /dev/null 2> "$work/chk.err"; local nopy_rc=$?
  [[ $nopy_rc == 2 && "$(cat "$work/chk.err")" == *"UNKNOWN"* && "$(cat "$work/chk.err")" == *"python3"* ]] \
    && ok "--check with python3 absent is UNKNOWN (exit 2) and names python3" || fail "--check with python3 absent: rc=$nopy_rc err=[$(cat "$work/chk.err")]"

  # 8. the predicate itself, driven directly, on the exact live phrasing
  printf '' > "$work/e"; printf "ERROR: You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits\n" > "$work/o"
  usage_limited 1 "$work/o" "$work/e" && ok "predicate fires on the 0.146.0 wording (stdout, exit 1)" || fail "predicate missed the live wording"
  printf 'real answer\n' > "$work/o"; printf 'usageLimitExceeded\n' > "$work/e"
  usage_limited 0 "$work/o" "$work/e" && fail "predicate fired on exit 0 with a real answer" || ok "predicate quiet on exit 0 + non-empty answer even with the token on stderr"
  printf '' > "$work/o"; printf 'usageLimitExceeded\n' > "$work/e"
  usage_limited 0 "$work/o" "$work/e" && ok "predicate fires on exit 0 with EMPTY stdout and the token on stderr" || fail "predicate missed exit-0-empty-stdout"
  # 8b. (2026-09-26 audit) a >64 KB stream with the token at the START: `cat … |
  #     grep -q` let grep exit early, cat took SIGPIPE, and under pipefail the
  #     negated pipeline read as "no match" — the predicate INVERTED on big output.
  { printf "ERROR: You've hit your usage limit.\n"; head -c 1200000 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$work/o"; printf '' > "$work/e"
  usage_limited 1 "$work/o" "$work/e" && ok "predicate fires on a >1 MB stream with the token at the start (no SIGPIPE inversion)" || fail "predicate INVERTED on a big stream"

  # 9. READ-ONLY SEAT. The wrapper builds the argv itself: the fixed flags
  #    reach codex exactly once whatever the caller passed, the caller's accepted options
  #    arrive in one canonical form, and anything else is refused (exit 2) before ANY
  #    process starts — no exec call and no --version call recorded.
  mkdir -p "$work/repo"; : > "$work/schema.json"
  expect_argv() { # <model> [the caller's options in canonical form...]
    printf 'CALL\n'
    printf '%s\n' exec -m "$1" --sandbox read-only --ignore-user-config --color never \
      -c 'model_provider="openai"' -c 'web_search="disabled"' -c 'allow_login_shell=false' --disable hooks --disable plugins --disable apps "${@:2}" -
  }
  same_argv() { # <label> <run_role result> <expected argv text>
    if [[ "$2" == "exit=0" && "$(cat "$argv")" == "$3" ]]; then ok "$1"
    else fail "$1: $2 argv/[$(tr '\n' ' ' < "$argv")] err/[$(head -c 200 "$work/last.err")]"; fi
  }
  # 9a. each real caller's argument list, unchanged
  r="$(printf 'x' | run_role always-ok --sandbox read-only -c model_reasoning_effort=high -C "$work/repo" -)"
  same_argv "council argv (bare effort spelling): fixed flags once, effort quoted, -C kept" "$r" \
    "$(expect_argv "$CODEX_PRIMARY_MODEL" -c 'model_reasoning_effort="high"' -C "$work/repo")"
  r="$(printf 'x' | run_role always-ok --sandbox read-only --skip-git-repo-check -c 'model_reasoning_effort="medium"' -C "$work/repo" -o "$work/o.md" -)"
  same_argv "blind-read argv (quoted effort spelling): one form, -o kept" "$r" \
    "$(expect_argv "$CODEX_PRIMARY_MODEL" -c 'model_reasoning_effort="medium"' -C "$work/repo" --skip-git-repo-check -o "$work/o.md")"
  local thirteen="apps plugins remote_plugin browser_use browser_use_external browser_use_full_cdp_access computer_use in_app_browser image_generation multi_agent hooks skill_mcp_dependency_install tool_suggest"
  local dis=() exp=() n
  for n in $thirteen; do dis+=(--disable "$n"); [[ "$n" == hooks || "$n" == plugins || "$n" == apps ]] || exp+=(--disable "$n"); done
  r="$(printf 'x' | run_role always-ok --sandbox read-only --ephemeral --skip-git-repo-check --color never --ignore-user-config \
        -c 'model_reasoning_effort="high"' -c 'web_search="disabled"' "${dis[@]}" --output-schema "$work/schema.json" -o "$work/o.json" -)"
  same_argv "review-hook argv: nothing fixed is emitted twice, the 13 switches merged with the fixed three" "$r" \
    "$(expect_argv "$CODEX_PRIMARY_MODEL" "${exp[@]}" -c 'model_reasoning_effort="high"' --skip-git-repo-check --ephemeral --output-schema "$work/schema.json" -o "$work/o.json")"
  r="$(printf 'x' | run_role always-ok --sandbox read-only -C "$work/repo" -)"
  same_argv "ad-hoc argv" "$r" "$(expect_argv "$CODEX_PRIMARY_MODEL" -C "$work/repo")"
  r="$(printf 'x' | run_role always-ok -)"
  same_argv "a caller that passes no --sandbox still gets --sandbox read-only and every fixed flag" "$r" "$(expect_argv "$CODEX_PRIMARY_MODEL")"
  r="$(printf 'x' | run_role always-ok --light --sandbox read-only -C "$work/repo" -)"
  same_argv "--light: the same fixed flags on $CODEX_LIGHT_MODEL" "$r" "$(expect_argv "$CODEX_LIGHT_MODEL" -C "$work/repo")"
  r="$(printf 'x' | run_role limit-then-ok --sandbox read-only -c model_reasoning_effort=high -C "$work/repo" -)"
  same_argv "usage-limit fallback re-runs the SAME built argv on $CODEX_FALLBACK_MODEL" "$r" \
    "$(expect_argv "$CODEX_PRIMARY_MODEL" -c 'model_reasoning_effort="high"' -C "$work/repo"; expect_argv "$CODEX_FALLBACK_MODEL" -c 'model_reasoning_effort="high"' -C "$work/repo")"
  # an accepted path reaches codex as ONE word, byte for byte, whatever it holds
  local odd="$work/odd dir 'q\" *,=\$x [a]"; mkdir -p "$odd"; : > "$odd/sch ema*.json"
  r="$(printf 'x' | run_role always-ok -C "$odd" --output-schema "$odd/sch ema*.json" -o "$odd/out, =*.md" -)"
  same_argv "paths with spaces, quotes, glob characters, a comma, '=' and '\$' arrive as single unchanged words" "$r" \
    "$(expect_argv "$CODEX_PRIMARY_MODEL" -C "$odd" --output-schema "$odd/sch ema*.json" -o "$odd/out, =*.md")"
  r="$(printf 'x' | run_role always-ok --disable hooks --disable plugins --disable apps -)"
  same_argv "a caller's --disable hooks/plugins/apps is not emitted a second time" "$r" "$(expect_argv "$CODEX_PRIMARY_MODEL")"
  r="$(printf 'x' | run_role always-ok --disable tool_suggest -)"
  same_argv "a caller's other --disable name is added after the fixed three" "$r" "$(expect_argv "$CODEX_PRIMARY_MODEL" --disable tool_suggest)"
  r="$(printf 'x' | run_role limit-then-ok --sandbox read-only -c model_reasoning_effort=high -C "$work/repo" -)"
  [[ "$(cat "$vlog")" == version ]] && ok "the CLI version is asked once per seat run, not once per attempt" \
    || fail "version calls on a fallback run: [$(tr '\n' ' ' < "$vlog")]"

  # 9b. refusals: exit 2, the argument named, and NOTHING started
  refused() { # <label> <text the refusal must carry> [args...]
    local rr; rr="$(printf 'x' | run_role always-ok "${@:3}")"
    if [[ "$rr" == "exit=2" && ! -s "$log" && ! -s "$argv" && ! -s "$vlog" && "$(cat "$work/last.err")" == *"$2"* ]]; then ok "refused, nothing started: $1"
    else fail "not refused: $1: $rr calls/[$(tr '\n' ' ' < "$argv")] version-calls/[$(tr '\n' ' ' < "$vlog")] err/[$(head -c 200 "$work/last.err")]"; fi
  }
  refused "--sandbox workspace-write"            "workspace-write"        --sandbox workspace-write -
  refused "--sandbox danger-full-access"         "danger-full-access"     --sandbox danger-full-access -
  refused "-s danger-full-access"                "danger-full-access"     -s danger-full-access -
  refused "=-joined --sandbox=read-only"         "--sandbox=read-only"    --sandbox=read-only -
  refused "attached short -sread-only"           "-sread-only"            -sread-only -
  refused "--dangerously-bypass-approvals-and-sandbox" "--dangerously-bypass-approvals-and-sandbox" --sandbox read-only --dangerously-bypass-approvals-and-sandbox -
  refused "--dangerously-bypass-hook-trust"      "--dangerously-bypass-hook-trust" --sandbox read-only --dangerously-bypass-hook-trust -
  refused "--full-auto"                          "--full-auto"            --full-auto -
  refused "--approve-for-me"                     "--approve-for-me"       --approve-for-me -
  refused "-c mcp_servers (a program outside the sandbox)" "mcp_servers"  --sandbox read-only -c 'mcp_servers.x.command="/usr/bin/touch"' -
  refused "-c model_provider"                    "model_provider"         -c 'model_provider="other"' -
  refused "-c sandbox_mode"                      "sandbox_mode"           -c 'sandbox_mode="danger-full-access"' -
  refused "-c web_search=live"                   "web_search"             -c 'web_search="live"' -
  refused "-c model_reasoning_effort=ultra"      "ultra"                  -c model_reasoning_effort=ultra -
  refused "-c with a second key smuggled after the effort" "model_reasoning_effort" -c 'model_reasoning_effort="high",sandbox_mode="x"' -
  refused "--config=… joined"                    "--config="              '--config=model_reasoning_effort="high"' -
  refused "--enable"                             "--enable"               --enable hooks -
  refused "--disable with a bad name"            "Bad-Name"               --disable Bad-Name -
  refused "--disable with a name the CLI does not know (it would echo it in an error)" "usage_limit_reached" --disable usage_limit_reached -
  refused "--disable with a comma list"          "not one of"             --disable apps,hooks -
  refused "--disable with a glob"                "not one of"             --disable 'app*' -
  refused "--disable with a newline"             "not one of"             --disable "apps"$'\n'"hooks" -
  refused "--disable with two names in one word" "not one of"             --disable "apps hooks" -
  refused "--disable with two ADJACENT list names in one word" "not one of" --disable "apps plugins" -
  refused "--disable with an empty value"        "not one of"             --disable "" -
  refused "--disable hooks twice"                "more than once"         --disable hooks --disable hooks -
  refused "--disable plugins twice"              "more than once"         --disable plugins --disable plugins -
  refused "-C with an empty value"               "-C"                     -C "" -
  refused "-o with an empty value"               "-o"                     -o "" -
  refused "--output-schema with an empty value"  "--output-schema"        --output-schema "" -
  refused "--output-schema value that starts with '-'" "--output-schema"  --output-schema --json -
  refused "--output-schema value holding a newline"    "--output-schema"  --output-schema "$work/schema.json"$'\n'"x" -
  refused "--add-dir"                            "--add-dir"              --add-dir "$work/repo" -
  refused "--worktree"                           "--worktree"             --worktree -
  refused "-p profile"                           "-p"                     -p other -
  refused "--profile"                            "--profile"              --profile other -
  refused "--oss"                                "--oss"                  --oss -
  refused "--local-provider"                     "--local-provider"       --local-provider ollama -
  refused "-i image"                             "-i"                     -i "$work/schema.json" -
  refused "--json"                               "--json"                 --json -
  refused "--strict-config"                      "--strict-config"        --strict-config -
  refused "--ignore-rules"                       "--ignore-rules"         --ignore-rules -
  refused "--color always"                       "always"                 --color always -
  refused "--model=… joined"                     "--model="               --model=gpt-5.6-terra -
  refused "--light anywhere but first"           "--light"                --sandbox read-only --light -
  refused "a positional prompt"                  "stray-prompt"           --sandbox read-only stray-prompt -
  refused "the -- separator"                     "--"                     --sandbox read-only -- -
  refused "an empty argument"                    "empty"                  --sandbox read-only "" -
  refused "no final '-'"                         "must end with"          --sandbox read-only -C "$work/repo"
  refused "no arguments at all"                  "must end with"
  refused "'-' twice"                            "after the final"        --sandbox read-only - -
  refused "an option after the final '-'"        "after the final"        - --ephemeral
  # duplicates and conflicts
  refused "--sandbox twice"                      "more than once"         --sandbox read-only -s read-only -
  refused "--ignore-user-config twice"           "more than once"         --ignore-user-config --ignore-user-config -
  refused "--color never twice"                  "more than once"         --color never --color never -
  refused "--skip-git-repo-check twice"          "more than once"         --skip-git-repo-check --skip-git-repo-check -
  refused "--ephemeral twice"                    "more than once"         --ephemeral --ephemeral -
  refused "-C twice"                             "more than once"         -C "$work/repo" --cd "$work" -
  refused "-o twice"                             "more than once"         -o "$work/a" --output-last-message "$work/b" -
  refused "--output-schema twice"                "more than once"         --output-schema "$work/schema.json" --output-schema "$work/schema.json" -
  refused "two reasoning efforts that conflict"  "more than once"         -c model_reasoning_effort=high -c 'model_reasoning_effort="low"' -
  refused "the same reasoning effort twice"      "more than once"         -c model_reasoning_effort=high -c model_reasoning_effort=high -
  refused "web_search twice"                     "more than once"         -c web_search=disabled -c 'web_search="disabled"' -
  refused "the same --disable twice"             "more than once"         --disable apps --disable apps -
  # operands
  refused "-C as the last word (no operand)"     "needs a value"          --sandbox read-only -C
  refused "-o as the last word"                  "needs a value"          --sandbox read-only -o
  refused "-c as the last word"                  "needs a value"          --sandbox read-only -c
  refused "--disable as the last word"           "needs a value"          --disable
  refused "--sandbox as the last word"           "needs a value"          --sandbox
  refused "-C value that starts with '-'"        "-C"                     -C --dangerously-bypass-approvals-and-sandbox -
  refused "-C value holding a newline"           "-C"                     -C "$work/repo"$'\n'"x" -
  refused "-C that is not a directory"           "not an existing directory" -C "$work/no-such-dir" -
  refused "-o value that starts with '-'"        "-o"                     -o --json -
  refused "-o value holding a newline"           "-o"                     -o "$work/a"$'\n'"b" -
  refused "--output-schema that is not a file"   "not an existing file"   --output-schema "$work/no-such-schema.json" -

  # 9c. the CLI version: only the verified one runs; any other answer refuses with no exec call
  version_refused() { # <label> [FAKE_NAME=value...]
    local rr
    : > "$log"; : > "$argv"; : > "$vlog"
    conf FAKE_ROLE=always-ok FAKE_LOG="$log" FAKE_ARGV="$argv" FAKE_VLOG="$vlog" FAKE_CLI="$VERIFIED_CLI" "${@:2}"
    rr="$(printf 'x' | CODEX_SEAT_BIN="${SEAT_BIN_FOR_TEST:-$work/codex}" bash "$0" --sandbox read-only - > "$work/last.out" 2> "$work/last.err"; echo "exit=$?")"
    if [[ "$rr" == "exit=2" && ! -s "$argv" && "$(cat "$work/last.err")" == *"$VERIFIED_CLI"* && "$(cat "$work/last.err")" == *"codex-seat-probe.py"* ]]; then ok "version refused, no exec call: $1"
    else fail "version not refused: $1: $rr calls/[$(tr '\n' ' ' < "$argv")] err/[$(head -c 240 "$work/last.err")]"; fi
  }
  version_refused "a newer CLI (0.171.0)"              FAKE_VERSION_OUT=$'codex-cli 0.171.0\n'
  version_refused "the CLI the seat ran on before (0.163.0)" FAKE_VERSION_OUT=$'codex-cli 0.163.0\n'
  version_refused "--version exits non-zero"           FAKE_VERSION_RC=1
  version_refused "--version prints nothing"           FAKE_VERSION_OUT=
  # The rows below are the VERIFIED version with one thing wrong, so they are written from
  # the VERIFIED_CLI line. As literals they named 0.163.0, and once the line moved every
  # one of them would have been refused for being another version, whatever the check did
  # with a suffix, a second line or a missing newline.
  version_refused "malformed: no codex-cli prefix"     FAKE_VERSION_OUT="$VERIFIED_CLI"$'\n'
  version_refused "malformed: a suffix on the version" FAKE_VERSION_OUT="codex-cli $VERIFIED_CLI-beta.1"$'\n'
  version_refused "unexpected: a second line"          FAKE_VERSION_OUT="codex-cli $VERIFIED_CLI"$'\nupdate available\n'
  version_refused "unexpected: a leading line"         FAKE_VERSION_OUT=$'warning: x\n'"codex-cli $VERIFIED_CLI"$'\n'
  version_refused "unexpected: blank lines after the version" FAKE_VERSION_OUT="codex-cli $VERIFIED_CLI"$'\n\n\n'
  version_refused "unexpected: no newline after the version"  FAKE_VERSION_OUT="codex-cli $VERIFIED_CLI"
  version_refused "unexpected: a trailing space"       FAKE_VERSION_OUT="codex-cli $VERIFIED_CLI "$'\n'
  SEAT_BIN_FOR_TEST="$work/no-such-codex" version_refused "the codex binary is absent"

  # 10. THE SEAT'S ENVIRONMENT. The seat is started under a KNOWN environment (env -i):
  #     the names it may pass, made-up secrets, proxy URLs, its own overrides. The fake
  #     records the exported names of every start. Judged on names, by equality: one
  #     name too many or one missing fails.
  # ponytail: PWD, OLDPWD, SHLVL and _ are not judged. The fake is a bash script, and a
  # bash started with nothing sets them itself, so they cannot be told from inherited
  # ones; a recorder that is not a shell is the upgrade. None of them holds a secret.
  local ehome="$work/home dir" etmp="$work/tmp" ecx="$work/cx 'q\" *,=\$x [a]"
  mkdir -p "$ehome" "$etmp" "$ecx"
  local planted=(SYNTH_FAKE_API_KEY=FAKE-SECRET-ENV-1 OPENAI_API_KEY=FAKE-SECRET-ENV-2 ANTHROPIC_API_KEY=FAKE-SECRET-ENV-3
                 GEMINI_API_KEY=FAKE-SECRET-ENV-4 SYNTH_FAKE_SESSION_TOKEN=FAKE-SECRET-ENV-5 AWS_SECRET_ACCESS_KEY=FAKE-SECRET-ENV-6
                 GITHUB_TOKEN=FAKE-SECRET-ENV-7 SSH_AUTH_SOCK=/nowhere/agent.sock GIT_ASKPASS=/nowhere/askpass
                 HTTPS_PROXY=http://fake:FAKE-SECRET-ENV-8@proxy.invalid:1 https_proxy=http://proxy.invalid:1
                 ALL_PROXY=http://proxy.invalid:1 NO_PROXY=x OPENAI_BASE_URL=http://codex-dead.invalid/v1
                 USER=fake LC_FAKE_TOKEN=FAKE-SECRET-ENV-9 LC_PAPER=x NODE_OPTIONS=--fake NODE_EXTRA_CA_CERTS=/nowhere/ca.pem
                 ZDOTDIR=/nowhere/planted-profile)
  seen() { # the fake's record, one line per start, less the four names its own bash sets
    local kind rest w line
    while read -r kind rest; do
      line="$kind"
      for w in $rest; do case "$w" in PWD|OLDPWD|SHLVL|_) ;; *) line+=" $w" ;; esac; done
      printf '%s\n' "$line"
    done < "$envlog"
  }
  values_on() { # <kind>... -- <NAME=value>... ; what the fake's value record must read: every value, on every start
    local kinds=() k
    while [[ "$1" != -- ]]; do kinds+=("$1"); shift; done; shift
    for k in "${kinds[@]}"; do printf '%s\n' "${@/#/$k }"; done
  }
  env_run() { # <role> [NAME=value...] ; the seat under exactly these variables and its overrides
    : > "$log"; : > "$argv"; : > "$vlog"; : > "$envlog"; : > "$work/values"
    conf FAKE_ROLE="$1" FAKE_LOG="$log" FAKE_ARGV="$argv" FAKE_VLOG="$vlog" FAKE_ENVLOG="$envlog" FAKE_VALUES="$work/values" \
      FAKE_VALUE_NAMES="$value_names" FAKE_CLI="$VERIFIED_CLI" FAKE_PRIMARY="$CODEX_PRIMARY_MODEL"
    printf 'x' | /usr/bin/env -i "${@:2}" CODEX_SEAT_BIN="$work/codex" CODEX_SEAT_PRIMARY="$CODEX_PRIMARY_MODEL" \
      CODEX_SEAT_LIGHT="$CODEX_LIGHT_MODEL" CODEX_SEAT_FALLBACK="$CODEX_FALLBACK_MODEL" CODEX_SEAT_MODELS_CACHE="$work/cache-ok.json" \
      "$BASH" "$0" --sandbox read-only - > "$work/last.out" 2> "$work/last.err"
    echo "exit=$?"
  }
  # 10a. three allowed names set, everything else planted: codex is started with the three
  #      and the seat's own ZDOTDIR, on the version question and on BOTH attempts of a
  #      fallback run; the planted ZDOTDIR does not survive
  local three="HOME PATH TMPDIR ZDOTDIR" value_names="HOME PATH TMPDIR ZDOTDIR"
  r="$(env_run limit-then-ok PATH="$PATH" HOME="$ehome" TMPDIR="$etmp" "${planted[@]}")"
  if [[ "$r" == "exit=0" && "$(seen)" == "version $three"$'\n'"exec $three"$'\n'"exec $three" \
        && "$(cat "$work/values")" == "$(values_on version exec exec -- "HOME=$ehome" "PATH=$PATH" "TMPDIR=$etmp" ZDOTDIR=/var/empty)" ]]; then
    ok "environment: of 3 allowed and 20 planted variables and the seat's own overrides, codex is started with the 3 and the seat's ZDOTDIR, not the planted one (version call, primary run, fallback run)"
  else fail "environment, planted: $r seen/[$(seen | tr '\n' '|')] values/[$(tr '\n' '|' < "$work/values" | head -c 400)] err/[$(head -c 200 "$work/last.err")]"; fi
  # 10b. every name on the list set: all of them arrive, none else, values unchanged.
  #      The names are written out here, not read from SEAT_ENV_NAMES: a name added to
  #      the list fails this row until it is added here too.
  local listed="CODEX_CA_CERTIFICATE CODEX_HOME HOME LANG LC_ALL LC_COLLATE LC_CTYPE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME LOGNAME PATH SHELL SSL_CERT_FILE TERM TMPDIR"
  #      Every value is checked, each name with a value of its own (LC_ALL=C keeps the
  #      fake's own bash from complaining about the made-up locales under it).
  local all="$listed ZDOTDIR"; value_names="$all"
  local given=(CODEX_CA_CERTIFICATE=/nowhere/b.pem CODEX_HOME="$ecx" HOME="$ehome" LANG=xx_LANG LC_ALL=C LC_COLLATE=xx_COLLATE
               LC_CTYPE=xx_CTYPE LC_MESSAGES=xx_MESSAGES LC_MONETARY=xx_MONETARY LC_NUMERIC=xx_NUMERIC LC_TIME=xx_TIME
               LOGNAME=fake-logname PATH="$PATH" SHELL=/bin/sh SSL_CERT_FILE=/nowhere/a.pem TERM=dumb TMPDIR="$etmp")
  r="$(env_run always-ok "${given[@]}" "${planted[@]}")"
  if [[ "$r" == "exit=0" && "$(seen)" == "version $all"$'\n'"exec $all" \
        && "$(cat "$work/values")" == "$(values_on version exec -- "${given[@]}" ZDOTDIR=/var/empty)" \
        && "$(printf '%s\n' $SEAT_ENV_NAMES | LC_ALL=C sort | tr '\n' ' ')" == "$listed " ]]; then
    ok "environment: all 17 listed names arrive when set, with the seat's ZDOTDIR, and nothing else does; every value arrives unchanged on both starts, one with spaces, quotes, '=' and '\$' among them"
  else fail "environment, full list: $r seen/[$(seen | tr '\n' '|')] values/[$(tr '\n' '|' < "$work/values" | head -c 600)]"; fi
  # 10c. the counterexample: the same fake started WITHOUT the seat, under the same planted
  #      variables, must fail the same reading, or the reading could not see a leak
  : > "$envlog"; : > "$work/values"; conf FAKE_ROLE=always-ok FAKE_LOG="$log" FAKE_ENVLOG="$envlog" FAKE_VALUES="$work/values" FAKE_VALUE_NAMES=ZDOTDIR
  printf 'x' | /usr/bin/env -i PATH="$PATH" HOME="$ehome" TMPDIR="$etmp" "${planted[@]}" "$work/codex" exec -m x - > /dev/null 2>&1
  if [[ "$(seen)" != "exec $three" && " $(seen) " == *" SYNTH_FAKE_API_KEY "* && " $(seen) " == *" HTTPS_PROXY "* \
        && "$(cat "$work/values")" == "exec ZDOTDIR=/nowhere/planted-profile" ]]; then
    ok "environment, control: started without the seat, the same fake is handed the planted variables and the planted ZDOTDIR, and the same reading shows them"
  else fail "environment, control: the reading did not show a planted variable: [$(seen | tr '\n' '|')]"; fi
  # 10e. --check asks codex its version too: the same short environment
  : > "$envlog"; : > "$work/values"; conf FAKE_ENVLOG="$envlog" FAKE_CLI="$VERIFIED_CLI" FAKE_VALUES="$work/values" FAKE_VALUE_NAMES="$three"
  /usr/bin/env -i PATH="$PATH" HOME="$ehome" TMPDIR="$etmp" "${planted[@]}" CODEX_SEAT_BIN="$work/codex" \
    CODEX_SEAT_MODELS_CACHE="$work/cache-ok.json" "$BASH" "$0" --check > /dev/null 2> "$work/chk.err"; local echk_rc=$?
  if [[ $echk_rc == 0 && "$(seen)" == "version $three" \
        && "$(cat "$work/values")" == "$(values_on version -- "HOME=$ehome" "PATH=$PATH" "TMPDIR=$etmp" ZDOTDIR=/var/empty)" ]]; then ok "environment: --check asks codex its version with the same 3 and the seat's ZDOTDIR"
  else fail "environment, --check: rc=$echk_rc seen/[$(seen | tr '\n' '|')] err/[$(head -c 200 "$work/chk.err")]"; fi
  # 10d. a codex path that env would misread is refused before anything starts
  #      (the copy gets the fake's settings as well: without them a start would be recorded nowhere)
  mkdir -p "$work/a=b"; cp "$work/codex" "$work/a=b/codex"
  : > "$log"; : > "$argv"; : > "$vlog"; conf FAKE_ROLE=always-ok FAKE_LOG="$log" FAKE_ARGV="$argv" FAKE_VLOG="$vlog" FAKE_CLI="$VERIFIED_CLI"
  cp "$work/fake.conf" "$work/a=b/fake.conf"
  r="$(printf 'x' | CODEX_SEAT_BIN="$work/a=b/codex" bash "$0" --sandbox read-only - > "$work/last.out" 2> "$work/last.err"; echo "exit=$?")"
  if [[ "$r" == "exit=2" && ! -s "$log" && ! -s "$vlog" && "$(cat "$work/last.err")" == *"holds '='"* ]]; then
    ok "refused, nothing started: a codex path holding '='"
  else fail "codex path holding '=': $r err/[$(head -c 200 "$work/last.err")]"; fi

  if [[ $fails -eq 0 ]]; then echo "codex-seat --selftest: every branch proven both ways"; return 0; fi
  echo "codex-seat --selftest: $fails failure(s)"; return 1
}

case "${1:-}" in
  --check)    check_models ;;
  --selftest) selftest ;;
  --light)    shift; CODEX_PRIMARY_MODEL="$CODEX_LIGHT_MODEL"; seat "$@" ;;
  -h|--help)  awk 'NR > 1 && /^set -uo pipefail/ { exit } NR > 1' "$0" ;;
  *)          seat "$@" ;;
esac
