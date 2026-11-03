#!/usr/bin/env bash
# Self-test for main-script-card.sh: main's SessionStart card of script usage lines, each taken from the script's own
# --help. The card reads scripts from its plugin folder, so cases run a copy of the hook in a scratch plugin tree.
# Run: bash hooks/__tests__/main-script-card.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/main-script-card.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }

MAIN=$(mktemp -d); git -C "$MAIN" init -q
git -C "$MAIN" -c user.name=t -c user.email=t@t.t commit -q --allow-empty -m base
WT=$MAIN-wt; git -C "$MAIN" worktree add -q --detach "$WT"
FAKE=$(mktemp -d); mkdir -p "$FAKE/hooks" "$FAKE/scripts"
cp "$ROOT/hooks/main-script-card.sh" "$FAKE/hooks/"; cp -R "$ROOT/hooks/lib" "$FAKE/hooks/lib"
trap 'git -C "$MAIN" worktree remove --force "$WT" 2>/dev/null; rm -rf "$MAIN" "$WT" "$FAKE"' EXIT
card_in() { local D=$1 H=$2; shift 2; (cd "$D" && env -u COMMANDECK_REVIEWER -u ORCA_TERMINAL_HANDLE "$@" bash "$H" </dev/null 2>/dev/null); }

# Stubs print the usage lines the card keeps; seat.sh's collect form is an indented continuation line.
stub() { printf '#!/bin/sh\n%s\n' "$2" > "$FAKE/scripts/$1.sh"; }
stub peek 'echo "usage: peek.sh <file>[:a-b]"; echo "not a usage line"'
stub long-job 'echo "usage: long-job.sh start|wait|list"'
stub seat 'echo "usage: seat.sh launch <role> <unit>"; echo "       seat.sh collect <role> <unit>"'
stub merge-unit-local 'echo "usage: merge-unit-local.sh <unit> <sha>"'

# Catches: the card shown to a worker or a reviewer pane.
check "worker and reviewer panes get no card" "|" "$(card_in "$WT" "$FAKE/hooks/main-script-card.sh")|$(card_in "$MAIN" "$FAKE/hooks/main-script-card.sh" COMMANDECK_REVIEWER=1)"
OUT=$(card_in "$MAIN" "$FAKE/hooks/main-script-card.sh")
# Catches: a signature script missing from the card, or a non-usage line leaking into it.
check "main output carries one usage line each for peek, seat, merge-unit-local, long-job" "4" "$(grep -c '^usage: ' <<<"$OUT")"
check "the card holds seat.sh launch and seat.sh collect" "1 1" \
  "$(grep -c 'seat.sh launch <role>' <<<"$OUT") $(grep -c 'seat.sh collect <role>' <<<"$OUT")"
check "no other line of a --help reaches the card" 0 "$(grep -c 'not a usage line' <<<"$OUT")"
# Catches: a script with a long usage block overflowing the card.
{ echo 'echo "usage: peek.sh x"'; for i in $(seq 1 60); do echo "echo \"  peek.sh form$i\""; done; } > "$FAKE/body"
stub peek "$(cat "$FAKE/body")"
check "the card is at most 40 lines" yes "$([ "$(sed -n '/^# Script signatures/,$p' <<<"$(card_in "$MAIN" "$FAKE/hooks/main-script-card.sh")" | tail -n +2 | wc -l)" -le 40 ] && echo yes || echo no)"

# Catches: one failing or slow --help dropping the whole card, or holding the hook for the slow script's full run.
rm -f "$FAKE/scripts/long-job.sh"
printf '#!/bin/sh\necho "usage: peek.sh OK"\n' > "$FAKE/scripts/peek.sh"
printf '#!/bin/sh\necho "usage: merge-unit-local.sh BAD"\nexit 1\n' > "$FAKE/scripts/merge-unit-local.sh"
printf '#!/bin/sh\nsleep 30\necho "usage: seat.sh SLOW"\n' > "$FAKE/scripts/seat.sh"
START=$SECONDS; OUT=$(card_in "$MAIN" "$FAKE/hooks/main-script-card.sh"); TOOK=$((SECONDS - START))
check "a failing --help adds no line, a slow --help holds nothing up" "1 0 0" \
  "$(grep -c 'peek.sh OK' <<<"$OUT") $(grep -c 'merge-unit-local.sh BAD' <<<"$OUT") $(grep -c 'seat.sh SLOW' <<<"$OUT")"
check "and the card is not held up by it (2 s each, never the 30 s sleep)" yes "$([ "$TOOK" -lt 12 ] && echo yes || echo no)"

# Catches: the card over the 10,240-byte preview limit.
OUT=$(card_in "$MAIN" "$HOOK")
check "main-script-card output is under the 10240-byte preview limit" yes "$([ "$(printf '%s\n' "$OUT" | wc -c | tr -d ' ')" -lt 10240 ] && echo yes || echo no)"
# Catches: the hook written but never registered, so no session shows the card.
check "the card is wired" 1 "$(jq '[.hooks.SessionStart[] | select(.matcher == null) | .hooks[].command | select(test("main-script-card.sh"))] | length' "$ROOT/hooks/hooks.json")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
