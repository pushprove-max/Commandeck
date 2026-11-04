#!/usr/bin/env bash
# covers: hooks/context-clear-stop.sh
# Issue 615: main ran past its restart line and nothing said why. When the hook cannot read main's context size, it
# must say so in one line, on stderr and in clear-hook.log, not stop silently: a silent stop looks like "below the line".
# Another session in main's checkout stays silent, as before. Its own file: context-clear-stop.test.sh runs near the
# 500-line cap.
set -u
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
HOOK="$(cd "$(dirname "$0")/.." && pwd)/context-clear-stop.sh"
mkdir -p "$BOX/bin" "$BOX/home/.claude/checkpoints" "$BOX/repo"
git -C "$BOX/repo" init -q
for t in bash sh env jq git date stat dirname basename cat ps grep perl touch printf rm rmdir sleep head tr cut sed awk mkdir ls wc tail sort python3 cksum mv paste timeout iconv comm; do
  p=$(command -v "$t") && ln -s "$p" "$BOX/bin/$t"
done
# Orca names run_a as the current run and <coordinator file> as its coordinator.
cat > "$BOX/bin/orca-ide" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration run-current") echo '{"result":{"run":{"id":"run_a"}}}' ;;
  "orchestration run-list") printf '{"result":{"runs":[{"id":"run_a","coordinator_handle":"%s"}]}}\n' "\$(cat "$BOX/coordinator")" ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$BOX/bin/orca-ide"
LOG="$BOX/home/.claude/checkpoints/clear-hook.log"
# A transcript with no usage row: context_size returns 1.
echo '{}' > "$BOX/transcript.jsonl"
unreadable() { # <coordinator>: "<stderr lines> <log lines>" naming an unreadable context size, for one stop of old-pane
  echo "$1" > "$BOX/coordinator"; : > "$LOG"
  local err
  err=$(cd "$BOX/repo" && printf '{"session_id":"sid","transcript_path":"%s","stop_hook_active":false}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" ORCA_TERMINAL_HANDLE=old-pane COMMANDECK_SCRATCH="$BOX" bash "$HOOK" 2>&1 >/dev/null)
  echo "$(grep -c 'context size cannot be read' <<<"$err") $(grep -c 'context size cannot be read' "$LOG")"
}

check "an unreadable context size on main says why in one line" "1 1" "$(unreadable old-pane)"
check "an unreadable context size in another session of main's checkout says nothing" "0 0" "$(unreadable other-pane)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
