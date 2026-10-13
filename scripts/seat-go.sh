#!/usr/bin/env bash
# seat-go.sh <handle> <agent-command> -- after a Claude pane's first prompt,
# type a bare `go` + Enter. Every first-prompt path calls this once.
#
# WHY. A Claude pane receives an injected or long sent prompt as PASTED text,
# and a model may refuse to act on pasted instructions alone: on 2026-09-21 a
# cold Fable brief-review seat answered "should I start?" and its driver
# waited. A short send arrives TYPED, so this line is the user's own
# word. On a pane already working it lands as a queued note and costs nothing.
# Codex panes never refused, so they get nothing typed.
set -uo pipefail
H=${1:?usage: seat-go.sh <handle> <agent-command>}
case " ${2:-} " in *" claude "*) ;; *) exit 0 ;; esac
orca-ide terminal send --terminal "$H" --text go --enter --json >/dev/null 2>&1 \
  || echo "seat-go: could not type go into $H; if its first turn asks to start, answer it" >&2
exit 0
