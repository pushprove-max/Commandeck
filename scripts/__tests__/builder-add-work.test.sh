#!/usr/bin/env bash
# builder-add-work.sh hands a running Builder the work main just added, in a fresh session of the same pane: the
# old session's whole context was replayed on every call of the new work. What this pins: nothing is sent before
# main has written the work down, or with no live Builder pane; the hand-off stands alone (brief, evidence, main's
# rulings inlined, the acknowledgement the next pass needs); the Builder is told to stop before the pane is
# cleared; a note that fails to send hands nothing over. The pane is the one the launch's seat record names: no
# session start may have recorded it since, and add-work found no Builder after any launch.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
U=u1 W=$T/ws/u1 SC=$T/scratch; mkdir -p "$W/.claude/briefs" "$SC/handles" "$T/bin" "$T/home" "$T/proj/.claude/briefs"
PROJ=$T/home/.claude/projects/$(printf '%s' "$W" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PROJ"
printf 'handle=term_aw\ntask=task_aw\nsession=old-sid\n' > "$SC/seat-$U-builder.txt"
# Logs every call; the pane list holds term_aw in the worktree (none with AW_DOWN=1); typing the pointer starts the new session's log.
cat > "$T/bin/orca-ide" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$AW_CALLS"
case "$*" in
  "terminal list --json") [ "${AW_DOWN:-}" = 1 ] && echo '{"result":[]}' || printf '{"result":[{"handle":"term_aw","worktreePath":"%s"}]}\n' "$AW_WT" ;;
  *"orchestration send"*) exit "${AW_SEND_RC:-0}" ;;
  *"Your task spec is the file"*) printf '%s\n' "$*" > "$AW_PROJ/new-sid.jsonl" ;;
esac
exit 0
SH
chmod +x "$T/bin/orca-ide"
add() { (cd "$T/proj" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_SCRATCH="$SC" COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 AW_CALLS="$T/calls" AW_WT="$W" AW_PROJ="$PROJ" "$@" \
  bash "$REAL/scripts/builder-add-work.sh" "$U" >"$T/out" 2>"$T/err"); echo $?; }
calls() { cat "$T/calls" 2>/dev/null | wc -l | tr -d ' '; }

check "with no work written to main's rulings file, nothing is sent" "1 1 0" "$(add) $(grep -c 'write the added work to' "$T/err") $(calls)"
printf '## 5. ADDED-PROBE: also build the export\n' > "$T/proj/.claude/briefs/$U-main-rulings.md"
check "with no live Builder pane, nothing is sent" "3 0" "$(add AW_DOWN=1) $(cat "$T/calls" 2>/dev/null | grep -c 'orchestration send')"
check "after a launch, with only its seat record naming the live pane, the work is handed over" "0 0" "$(add) $(ls "$SC/handles" | wc -l | tr -d ' ')"
HAND=$(ls "$W/.claude/briefs/$U-added-"*.md 2>/dev/null | head -1)
check "the hand-off stands alone: brief, evidence, main's rulings inlined, the acknowledgement" "1 1 1 1" \
  "$(grep -c "$W/.claude/briefs/$U.md\$" "$HAND") $(grep -c "$W/.claude/briefs/$U-evidence.md\$" "$HAND") $(grep -c 'ADDED-PROBE' "$HAND") $(grep -c -- "--ack-rulings $U" "$HAND")"
for _ in $(seq 100); do grep -q 'now names' "$SC/$U-added.log" 2>/dev/null && break; sleep 0.1; done
check "the Builder is told to stop, then the pane is cleared and handed the file" "orchestration send,--text /clear,Your task spec is the file" \
  "$(grep -oE 'orchestration send|--text /clear|Your task spec is the file' "$T/calls" | uniq | paste -sd, -)"
check "and main's seat record names the new session" "session=new-sid" "$(grep '^session=' "$SC/seat-$U-builder.txt" | tail -1)"
rm -f "$T/calls" "$W/.claude/briefs/$U-added-"*.md
check "a note that fails to send hands nothing over" "1 0 0" \
  "$(add AW_SEND_RC=1) $(ls "$W/.claude/briefs/$U-added-"*.md 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'terminal send' "$T/calls")"
# A Builder relaunched after a session start recorded its old pane: the dead record must not hide the new one.
printf 'term_old\n' > "$SC/handles/unit-$U"
check "a dead handle from an earlier session does not hide the pane the launch names" 0 "$(add)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
