#!/bin/sh
# selftest-council-seat — hold the published Claude seat to its restricted definition.
#
# The Claude seat of /council is a named agent, agents/council-seat.md. What makes it a
# read-only seat is its frontmatter: Opus at high effort, and a declared tool list of
# Read, Grep and Glob. That list fails quietly. Claude Code ignores a frontmatter field
# it does not know, so a misspelled `tools:` hands the agent every tool; a `memory:`
# field re-enables Read, Write and Edit. The sync gate (check-upstream-sync.sh) cannot
# watch this on a CI runner, where it has no live source and says UNKNOWN, so a hand
# edit of the published file would pass CI. This test runs there.
#
# It does not carry a second validator. commands/council.md prints a shadow search the
# overseer runs before seating the agent, and that block already holds the installed
# definition to its exact frontmatter. The test extracts THAT block from the published
# command and runs it against fixtures, so the published agent and the published command
# are proven to agree, and the block is proven to run on this platform:
#   1. the published agent, installed in a fixture home, is CLEAR;
#   2. no installed agent is NOT-CLEAR (the seat is empty, never another agent);
#   3. each widened or reworded definition is NOT-CLEAR, and a check of the name alone
#      accepts every one of them (so the rows test the frontmatter rule, not the name);
#   4. a project file that takes the seat's name is NOT-CLEAR;
#   5. the command still names the agent, refuses every fallback, keeps the prompt
#      guard, and still seats Codex and Gemini through their wrappers.
#
# What it cannot see: whether a session obeys the command. The search is an instruction
# the overseer carries out, not a runtime boundary, and the harness can add tools of its
# own to a subagent at run time. See the README, "The Claude seat".
#
# Usage: sh tests/selftest-council-seat.sh
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
agent="$here/agents/council-seat.md"
council="$here/commands/council.md"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
finish() { echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

echo "0. the published files and the search block are there"
if [ -f "$agent" ]; then ok "agents/council-seat.md is published"
else bad "agents/council-seat.md is missing"; fi
# The block: the fenced sh block whose first line names the search.
awk '
  f && /^ *```$/ { exit }
  f { print; next }
  pending { pending = 0; if ($0 ~ /council-seat shadow search/) { f = 1; print } }
  /^ *```sh$/ { pending = 1 }
' "$council" > "$work/search.sh"
if [ -s "$work/search.sh" ] && grep -q 'council-seat shadow search: CLEAR' "$work/search.sh"; then
  ok "commands/council.md carries the shadow search block"
else
  bad "commands/council.md carries no shadow search block; nothing below can run"
  finish
fi
[ -f "$agent" ] || finish

# search <home> <cwd> — runs the block as the overseer would: from the working directory,
# with only HOME and PATH set. Leaves the output in $work/out and the status in $st.
search() {
  st=0
  ( cd "$2" && env -i HOME="$1" PATH="$PATH" sh "$work/search.sh" ) > "$work/out" 2>&1 || st=$?
  verdict=$(tail -1 "$work/out")
}
is_clear()     { [ "$st" -eq 0 ] && [ "$verdict" = "council-seat shadow search: CLEAR" ]; }
is_not_clear() { [ "$st" -ne 0 ] && [ "$verdict" = "council-seat shadow search: NOT-CLEAR" ]; }
new_home() {  # <name> — a fixture home with an empty agents folder; prints its path
  mkdir -p "$work/$1/.claude/agents" "$work/$1.cwd"
  echo "$work/$1"
}

echo "1. the published agent, installed, is CLEAR"
h=$(new_home clear)
cp "$agent" "$h/.claude/agents/council-seat.md"
search "$h" "$h.cwd"
if is_clear; then ok "CLEAR with the published definition installed"
else bad "expected CLEAR, got exit $st: $(tail -3 "$work/out" | tr '\n' '|')"; fi

echo "2. no installed agent is an empty seat"
h=$(new_home missing)
search "$h" "$h.cwd"
if is_not_clear; then ok "NOT-CLEAR when council-seat.md is not installed"
else bad "expected NOT-CLEAR with no agent installed, got exit $st: $verdict"; fi

echo "3. a widened or reworded definition is refused"
n=0; named=0
# mutant <label> <awk program> — the published agent through the program, installed.
mutant() {
  n=$((n + 1))
  h=$(new_home "mutant$n")
  awk "$2" "$agent" > "$h/.claude/agents/council-seat.md"
  if cmp -s "$agent" "$h/.claude/agents/council-seat.md"; then
    bad "$1: the mutation changed nothing, so the row tests nothing"; return
  fi
  # The naive check, on the same file: is the name still there?
  if grep -q '^name: council-seat$' "$h/.claude/agents/council-seat.md"; then named=$((named + 1)); fi
  search "$h" "$h.cwd"
  if is_not_clear; then ok "$1: NOT-CLEAR"
  else bad "$1: expected NOT-CLEAR, got exit $st: $verdict"; fi
}
mutant "tools field misspelled (the agent would inherit every tool)" \
  '{ sub(/^tools: /, "tool: "); print }'
mutant "tools field absent" \
  '!/^tools: /'
mutant "Write added to the tool list" \
  '{ sub(/^tools: Read, Grep, Glob$/, "tools: Read, Grep, Glob, Write"); print }'
mutant "Bash added to the tool list" \
  '{ sub(/^tools: Read, Grep, Glob$/, "tools: Read, Grep, Glob, Bash"); print }'
mutant "memory enabled" \
  '{ print } /^model: opus$/ { print "memory: user" }'
mutant "model changed" \
  '{ sub(/^model: opus$/, "model: sonnet"); print }'
mutant "effort changed" \
  '{ sub(/^effort: high$/, "effort: low"); print }'
mutant "an unknown field added" \
  '{ print } /^model: opus$/ { print "permissionMode: bypassPermissions" }'
if [ "$named" -eq "$n" ]; then
  ok "a check of the name alone accepts all $n of those definitions"
else
  bad "only $named of $n mutants kept the name line; the rows above no longer isolate the frontmatter rule"
fi

echo "4. a project file that takes the seat's name is refused"
h=$(new_home shadow)
cp "$agent" "$h/.claude/agents/council-seat.md"
mkdir -p "$h.cwd/.claude/agents"
printf '%s\n' '---' 'name: council-seat' 'description: a project agent with every tool' '---' 'body' \
  > "$h.cwd/.claude/agents/reviewer.md"
search "$h" "$h.cwd"
if is_not_clear; then ok "NOT-CLEAR when a project agent declares the name"
else bad "expected NOT-CLEAR with a project shadow, got exit $st: $verdict"; fi
# The control for row 4: the same project folder with an unrelated agent is CLEAR, so
# the refusal above came from the name and not from the folder being there.
printf '%s\n' '---' 'name: reviewer' 'description: an unrelated project agent' '---' 'body' \
  > "$h.cwd/.claude/agents/reviewer.md"
search "$h" "$h.cwd"
if is_clear; then ok "CLEAR when the project agent has another name"
else bad "expected CLEAR with an unrelated project agent, got exit $st: $(tail -3 "$work/out" | tr '\n' '|')"; fi

echo "5. the command names the seat, refuses fallbacks, and keeps the other seats"
# Whitespace is folded so a re-wrapped paragraph still matches.
tr -s ' \n\t' '   ' < "$council" > "$work/council.flat"
phrase() {  # <label> <text that must be in the command>
  if grep -q -F -- "$2" "$work/council.flat"; then ok "$1"
  else bad "$1: not found in commands/council.md: $2"; fi
}
phrase "seats the agent by name" 'subagent_type: "council-seat"'
phrase "a missing or unverified agent is an empty seat" 'the Claude seat is empty'
phrase "no fallback to another agent" 'never fall back to `general-purpose` or any other agent'
phrase "the prompt guard is kept" 'You are a READ-ONLY consultant: do not edit, create, or delete any files, and run no state-changing commands.'
# The two texts below are searched for in the command; they are not paths to expand.
# shellcheck disable=SC2088
phrase "the Codex seat still goes through its wrapper, read-only" '~/.claude/codex-seat.sh --sandbox read-only'
# shellcheck disable=SC2088
phrase "the Gemini seat still goes through its wrapper" '~/.claude/agy-seat.sh < <brief>'

finish
