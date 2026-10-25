#!/usr/bin/env bash
# cos-unfinished-stop.sh (issue 364): a reply from the Chief of Staff (or main, when no Chief of Staff runs) that
# leaves its own work undone -- "haven't filed it", "want me to ..." -- is held once, so the pane does the work or says
# why it cannot. Why each case matters: the hold must fire where the work is lost (the relay pane, or main alone), must
# never fire a second time in one turn (a justified line would loop), and must never touch a Builder or a reviewer.
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$REAL/hooks/cos-unfinished-stop.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
git init -q -b main "$T/main" && git -C "$T/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
mkdir -p "$T/ws" "$T/bin"
git -C "$T/main" worktree add -q -b cos "$T/ws/Chief-of-Staff"
git -C "$T/main" worktree add -q -b u1 "$T/ws/u1"
cat > "$T/bin/orca-ide" <<EOS
#!/bin/sh
case "\$*" in
  "terminal list"*) [ -e "$T/cos-up" ] || exit 1; echo '{"ok":true,"result":{"terminals":[{"handle":"term_cos","worktreePath":"$T/ws/Chief-of-Staff","agentIdentity":"claude"}]}}' ;;
  *) exit 1 ;;
esac
EOS
chmod +x "$T/bin/orca-ide"
say() { jq -cn --arg t "$1" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}' > "$T/transcript.jsonl"; }
stop() { # <cwd> [extra json [env...]] -- the hook's stdout
  local cwd=$1 extra=${2:-'{}'}; shift $(($# < 2 ? $# : 2))
  jq -cn --arg d "$cwd" --arg t "$T/transcript.jsonl" --argjson x "$extra" '{cwd: $d, transcript_path: $t} + $x' \
    | env -u CLAUDE_PROJECT_DIR -u COMMANDECK_REVIEWER PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_MAIN="$T/main" \
        COMMANDECK_HOOK_FIRE_LOG="$T/fire.jsonl" "$@" bash "$HOOK" 2>/dev/null; }
blocked() { [ -n "$1" ] && jq -r '.decision' <<<"$1" || echo pass; }
OPEN="I haven't filed it yet. Want me to send it to main?"

say "$OPEN"
O=$(stop "$T/ws/Chief-of-Staff")
check "the Chief of Staff's reply that leaves its own work undone is held" block "$(blocked "$O")"
check "the hold names the matched phrase and tells the pane to do the work or say why" "1:1" \
  "$(jq -r .reason <<<"$O" | grep -c "haven't filed"):$(jq -r .reason <<<"$O" | grep -c 'say why in the same sentence')"
check "the hold is logged as a block" 1 "$(jq -s '[.[] | select(.decision == "block")] | length' "$T/fire.jsonl" 2>/dev/null)"
check "the second stop of the turn passes, so a justified line cannot loop" pass "$(blocked "$(stop "$T/ws/Chief-of-Staff" '{"stop_hook_active": true}')")"
say "Filed it and sent main the summary. Nothing is open."
check "a reply with nothing left undone passes" pass "$(blocked "$(stop "$T/ws/Chief-of-Staff")")"
say "$OPEN"
check "a Builder worktree passes" pass "$(blocked "$(stop "$T/ws/u1")")"
check "a reviewer pane passes" pass "$(blocked "$(stop "$T/ws/Chief-of-Staff" '{}' COMMANDECK_REVIEWER=1)")"
check "main with no Chief of Staff pane is held" block "$(blocked "$(stop "$T/main")")"
touch "$T/cos-up"
check "main beside a live Chief of Staff pane passes" pass "$(blocked "$(stop "$T/main")")"
rm -f "$T/transcript.jsonl"
check "a stop with no transcript passes" pass "$(blocked "$(stop "$T/ws/Chief-of-Staff")")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
