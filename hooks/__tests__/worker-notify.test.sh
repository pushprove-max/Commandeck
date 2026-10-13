#!/usr/bin/env bash
# The turn-complete hooks wake main once per finished turn. The harness can
# fire a hook twice for one turn, so a repeat is dropped; but a pane is reused,
# and its next task often ends on the same line ("VERDICT: GO"). Dropping that
# as a repeat leaves main waiting on a seat that has already answered.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.config/orca" "$TMP/scratch"
# The machine-wide file names another project's run: each project reads its own.
echo run_foreign > "$TMP/home/.config/orca/current-run"
mkdir -p "$TMP/scratch" && echo run_1 > "$TMP/scratch/current-run"
printf '#!/bin/sh\ncase "$*" in *"orchestration send"*) echo sent >> "%s/sends"; echo "{\\"ok\\":true}" ;; *) echo "{}" ;; esac\n' "$TMP" > "$TMP/bin/orca-ide"
chmod +x "$TMP/bin/orca-ide"
git init -q "$TMP/main" && git -C "$TMP/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
  && git -C "$TMP/main" worktree add -q "$TMP/wt" -b unit >/dev/null 2>&1
sends() { wc -l < "$TMP/sends" 2>/dev/null | tr -d ' ' || true; }
env_run() { ( cd "$TMP/wt" && PATH="$TMP/bin:$PATH" HOME="$TMP/home" COMMANDECK_SCRATCH="$TMP/scratch" COMMANDECK_MAIN="$TMP/main" \
  ORCA_TERMINAL_HANDLE="$1" ORCA_WORKTREE_ID=repo/unit "${@:2}" ) >/dev/null 2>&1; }

codex() { env_run term_cx bash "$REAL/hooks/codex-notify.sh" "$(jq -cn --arg t "$1" '{type: "agent-turn-complete", "turn-id": $t, "last-assistant-message": "Fine.\nVERDICT: GO"}')"; }
codex turn-1; codex turn-1
check "Codex: one turn fired twice wakes main once" 1 "$(sends)"
codex turn-2
check "Codex: the pane's next turn ending on the same verdict wakes main again" 2 "$(sends)"

rm -f "$TMP/sends"; T=$TMP/transcript.jsonl
turn() { jq -cn --arg u "$1" '{type: "assistant", uuid: $u, message: {role: "assistant", content: [{type: "text", text: "Fine.\nVERDICT: GO"}]}}' >> "$T"; }
claude() { jq -cn --arg t "$T" '{transcript_path: $t}' | env_run term_cl bash "$REAL/hooks/claude-worker-notify.sh"; }
turn u1; claude; claude
check "Claude: one turn fired twice wakes main once" 1 "$(sends)"
turn u2; claude
check "Claude: the pane's next turn ending on the same verdict wakes main again" 2 "$(sends)"

# A seat.sh wait that saw the marker is that turn's report, and one turn's only:
# a follow-up sent with no wait ends on the same line minutes later.
: > "$TMP/sends"; rm -f "$TMP/scratch"/notified-*
for h in term_cx term_cl; do printf '1\nseen %s VERDICT: GO\n' "$(date +%s)" > "$TMP/scratch/waiting-$h"; done
codex turn-3; codex turn-3; turn u3; claude; claude
check "a turn its wait reported wakes nobody, fired twice or not" 0 "$(sends)"
codex turn-4
check "Codex: a follow-up ending on the wait's marker wakes main" 1 "$(sends)"
turn u4; claude
check "Claude: a follow-up ending on the wait's marker wakes main" 2 "$(sends)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
