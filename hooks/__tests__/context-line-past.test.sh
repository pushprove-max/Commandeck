#!/usr/bin/env bash
# covers: hooks/context-line.sh
# Issue 592: every turn past main's restart line names how far past it main is, under the 40K mark too, and at the
# line nothing is said. The line is set to 180K here (COMMANDECK_CLEAR_LINE), the default 200K left alone (D7).
# Its own file: context-clear-stop.test.sh runs near the 500-line cap.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/bin" "$BOX/home/.claude/checkpoints" "$BOX/repo"
git -C "$BOX/repo" init -q
for t in bash sh env jq git date stat dirname basename cat ps grep perl touch printf rm rmdir sleep head tr cut sed awk mkdir ls wc tail sort python3 cksum mv paste timeout iconv comm; do
  p=$(command -v "$t") && ln -s "$p" "$BOX/bin/$t"
done
# Orca answers ok and lists nothing, as context-clear-stop.test.sh's stub does for a pane with no handle.
printf '#!/usr/bin/env bash\necho %s\n' "'{\"ok\":true}'" > "$BOX/bin/orca-ide"; chmod +x "$BOX/bin/orca-ide"
past_line() { # <tokens>: what context-line.sh tells main at that size
  printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":'"$1"',"input_tokens":0}}}' > "$BOX/transcript.jsonl"
  rm -f "$BOX/home/.claude/checkpoints"/s592.*
  (cd "$BOX/repo" && printf '{"session_id":"s592","transcript_path":"%s","prompt":"hi"}' "$BOX/transcript.jsonl" \
    | env -i PATH="$BOX/bin" HOME="$BOX/home" COMMANDECK_CLEAR_LINE=180000 bash "$ROOT/hooks/lib/run-hook.sh" "$ROOT/hooks/context-line.sh" 2>/dev/null)
}

check "main at 181K is warned 1K past the line" 1 "$(past_line 181000 | grep -c 'CONTEXT 181K is 1K past the 180K line')"
check "main at 466K is warned 286K past the line" 1 "$(past_line 466000 | grep -ic 'CONTEXT 466K is 286K past the 180K line')"
check "main at 180K is not warned" 0 "$(past_line 180000 | grep -c 'CONTEXT')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
