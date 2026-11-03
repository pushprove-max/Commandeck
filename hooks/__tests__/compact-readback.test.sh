#!/usr/bin/env bash
# Self-test: a compacted main must still restart, and a printed checkpoint stays small.
# compact-readback.sh used to delete the checkpoint at every compaction, so the
# restart that context-clear-stop.sh had in flight lost its input and main kept
# running on a compacted context. Now a compaction of main leaves a .handoff
# marker (the below-the-line restart path) unless a replacement already took the
# checkpoint (<sid>.md.delivered is newer than it). Run directly.
set -u
export COMMANDECK_HOOK_TIER=strict ORCA_TERMINAL_HANDLE=term_t
unset CLAUDE_CONFIG_DIR
ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/hooks/compact-readback.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
CPD="$BOX/home/.claude/checkpoints"
mkdir -p "$CPD"
git -C "$BOX" init -q repo
git -C "$BOX/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$BOX/repo" worktree add -q "$BOX/wt" 2>/dev/null

run() { # <dir> <source> -> hook stdout
  (cd "$1" && printf '{"session_id":"s1","source":"%s"}' "$2" | HOME="$BOX/home" COMMANDECK_HOOK_FIRE_LOG="$BOX/fire.jsonl" bash "$HOOK" 2>&1)
}
reset() { rm -f "$CPD"/s1.* "$BOX/home/.claude/settings.json"; }
exists() { [ -e "$1" ] && echo yes || echo no; }

# Catches a compaction deleting the checkpoint a restart still needs.
reset; printf 'ckpt body\n' > "$CPD/s1.md"
run "$BOX/repo" compact >/dev/null
check "(a) checkpoint with no marker survives the compaction" yes "$(exists "$CPD/s1.md")"
check "(a) and main is asked to restart (.handoff)" yes "$(exists "$CPD/s1.handoff")"

# Catches a restart in flight (.restarted, not yet delivered) losing its checkpoint.
reset; printf 'ckpt body\n' > "$CPD/s1.md"; cksum < "$CPD/s1.md" > "$CPD/s1.md.restarted"
run "$BOX/repo" compact >/dev/null
check "(b) restart in flight (.restarted, no .delivered): checkpoint survives" yes "$(exists "$CPD/s1.md")"
check "(b) and .handoff appears" yes "$(exists "$CPD/s1.handoff")"
check "(b) and .restarted stays, unread" yes "$(exists "$CPD/s1.md.restarted")"

# Catches a delivered checkpoint asking for a second restart or staying on disk.
reset; printf 'ckpt body\n' > "$CPD/s1.md"; touch -t 202601010000 "$CPD/s1.md"; printf 'tok\ns1\n' > "$CPD/s1.md.delivered"
OUT=$(run "$BOX/repo" compact)
check "(c) a checkpoint a replacement already took is deleted" no "$(exists "$CPD/s1.md")"
check "a delivered checkpoint sets no mark (c)" no "$(exists "$CPD/s1.handoff")"
check "(c) its text was still printed" yes "$(case $OUT in *"ckpt body"*) echo yes;; *) echo no;; esac)"

# Catches a compaction with no checkpoint failing to ask main for one.
reset
run "$BOX/repo" compact >/dev/null
check "(d) no checkpoint at all: .handoff appears" yes "$(exists "$CPD/s1.handoff")"

# Catches a /clear restarting main or dropping the checkpoint the same session keeps.
reset; printf 'ckpt body\n' > "$CPD/s1.md"
run "$BOX/repo" clear >/dev/null
check "(e) source clear keeps the checkpoint" yes "$(exists "$CPD/s1.md")"
check "a clear sets no mark (e)" no "$(exists "$CPD/s1.handoff")"

# Catches a worker worktree being restarted like main.
reset; printf 'ckpt body\n' > "$CPD/s1.md"
run "$BOX/wt" compact >/dev/null
check "(f) a linked worktree gets no marker" no "$(exists "$CPD/s1.handoff")"

# Catches a checkpoint rewritten after delivery being treated as spent.
reset; printf 'old body\n' > "$CPD/s1.md"; touch -t 202601010000 "$CPD/s1.md.delivered"; printf 'rewritten body\n' > "$CPD/s1.md"
run "$BOX/repo" compact >/dev/null
check "(g) a checkpoint rewritten after .delivered is not spent: it survives" yes "$(exists "$CPD/s1.md")"
check "(g) and asks for a restart" yes "$(exists "$CPD/s1.handoff")"

# Catches the strict-only restart firing on the default tier.
reset; printf 'ckpt body\n' > "$CPD/s1.md"
(cd "$BOX/repo" && printf '{"session_id":"s1","source":"compact"}' | HOME="$BOX/home" COMMANDECK_HOOK_TIER=default bash "$HOOK" >/dev/null 2>&1)
check "a default-tier compact sets no mark (h)" no "$(exists "$CPD/s1.handoff")"
check "(h) and the checkpoint still survives" yes "$(exists "$CPD/s1.md")"

# Catches the restart firing with no Orca to relaunch main.
reset; printf 'ckpt body\n' > "$CPD/s1.md"
(cd "$BOX/repo" && printf '{"session_id":"s1","source":"compact"}' | env -u ORCA_TERMINAL_HANDLE HOME="$BOX/home" bash "$HOOK" >/dev/null 2>&1)
check "(i) a compact with no Orca sets no mark" no "$(exists "$CPD/s1.handoff")"

# Catches a huge checkpoint flooding the new context.
reset; head -c 20000 /dev/zero | tr '\0' 'x' > "$CPD/s1.md"
OUT=$(run "$BOX/repo" clear)
check "(j) a huge checkpoint prints cut" yes "$(case $OUT in *"[cut at 9000 bytes"*) echo yes;; *) echo no;; esac)"
check "(j) and prints at most 9000 bytes of it" yes "$([ "${#OUT}" -lt 9400 ] && echo yes || echo no)"

# Catches the plugin hook and the user's own readback both printing the checkpoint.
reset; printf 'ckpt body\n' > "$CPD/s1.md"
printf '{"hooks":{"SessionStart":[{"matcher":"compact|clear","hooks":[{"type":"command","command":"/u/.claude/hooks/compact-readback.sh"}]}]}}' > "$BOX/home/.claude/settings.json"
OUT=$(run "$BOX/repo" compact)
check "a user-level readback stands it down (k: no print)" "" "$OUT"
check "(k) and no mark" no "$(exists "$CPD/s1.handoff")"

# Catches the hook shipping unregistered: it would never run.
check "(l) wired at compact|clear" 1 \
  "$(jq '[.hooks.SessionStart[] | select(.matcher == "compact|clear") | .hooks[].command | select(test("compact-readback.sh"))] | length' "$ROOT/hooks/hooks.json")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
