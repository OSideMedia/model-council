#!/bin/sh
# publicise — the one transformation between the live command and the published one.
#
# This repo is a PUBLIC release of commands that live at ~/.claude on one machine.
# Almost all of the payload is identical; the exception is that the live council.md
# folds in two local dimension files (SECURITY-PASSES.md, MEDIA-PASSES.md) that are
# not part of this repo, one of which names a private project by name.
#
# Copying blind would ship a command that tells its seats to read files nobody has.
# Hand-editing after each copy would mean the two files drift a little more every
# release and nobody could tell an intentional difference from a stale one.
#
# So the difference is a FUNCTION instead of a habit: this script is the only thing
# allowed to differ them, and tests/check-upstream-sync.sh defines the gate as "this
# transform, applied to the live file, reproduces the published file exactly". Gate
# and fix are then the same computation and cannot drift apart.
#
# Usage: publicise.sh <live-file>   # writes the public form to stdout
set -eu
[ $# -eq 1 ] || { echo "usage: publicise.sh <live-file>" >&2; exit 2; }
[ -f "$1" ] || { echo "publicise: no such file: $1" >&2; exit 2; }

awk '
  # Replace the local-passes paragraph with a portable equivalent. Matching is
  # anchored on the sentence that opens it, so an edit anywhere else in the file
  # flows through untouched and the gate still sees it.
  /^For security-scoped councils, also fold the infra-first dimensions from$/ { skip = 1 }
  skip && /pixels-or-payload evidence floor\)\.$/ {
    print "If the repo (or your own setup) carries a file of domain-specific review"
    print "dimensions — infra and secrets for a security-scoped council, spend and"
    print "provider-contract surfaces for one over generative-media code — fold it into"
    print "the brief and state its confidence floor. Seats cannot see your machine, so"
    print "any such dimensions have to travel in the brief itself."
    skip = 0
    next
  }
  skip { next }
  { print }
' "$1"
