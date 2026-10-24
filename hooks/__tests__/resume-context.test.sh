#!/usr/bin/env bash
# covers: hooks/resume-context.sh
# resume-context.test.sh -- the checkpoint a resumed main is handed is a summary: past 3,000 bytes it is cut, and its
# last line names the full file, so the new main reads the rest only when it needs it. A short checkpoint is whole.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
H=$T/home CPD=$T/home/.claude/checkpoints R=$T/repo
mkdir -p "$CPD" && git init -q -b main "$R" && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
echo '{}' > "$T/transcript.jsonl"
# resume <checkpoint file> -- the block the replacement main is started with.
resume() {
  printf '%s\n' "$1" > "$CPD/resume-pending.$(printf '%s' "$R" | tr -c 'A-Za-z0-9' '-')"
  (cd "$R" && printf '{"session_id":"new-sid","transcript_path":"%s"}' "$T/transcript.jsonl" \
    | env -u CLAUDE_PROJECT_DIR HOME="$H" COMMANDECK_BOARD_CMD=true COMMANDECK_SCRATCH="$T" bash "$REAL/hooks/resume-context.sh" 2>&1)
  rm -f "$CPD/new-sid.resumed-from"
}
# ckpt <output> -- the checkpoint part: from its heading to the to-do rule that follows it.
ckpt() { awk '/^## checkpoint /{p=1} /^TODO LIST:/{p=0} p' <<<"$1"; }
{ printf '## Goal\n'; for i in $(seq 1 400); do printf -- '- goal line %s of a long checkpoint body\n' "$i"; done; } > "$CPD/big.md"
OUT=$(resume "$CPD/big.md")
check "a 10 KB checkpoint is injected as at most 3,000 bytes, ending with the line naming the full file" "yes $CPD/big.md" \
  "$([ "$(ckpt "$OUT" | LC_ALL=C wc -c)" -le 3000 ] && echo yes) $(ckpt "$OUT" | tail -1 | grep -o "$CPD/big.md")"
printf '## Goal\n- one short goal\n\n## Queue (in order)\n- one item\n' > "$CPD/small.md"
OUT=$(resume "$CPD/small.md")
check "a short checkpoint is injected whole" "1 1 0" \
  "$(grep -c 'one short goal' <<<"$OUT") $(grep -c 'one item' <<<"$OUT") $(grep -c 'checkpoint cut to fit' <<<"$OUT")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
