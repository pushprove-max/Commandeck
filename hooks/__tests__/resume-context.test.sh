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
    | env -u CLAUDE_PROJECT_DIR HOME="$H" PATH="${RPATH:-$PATH}" COMMANDECK_BOARD_CMD=true COMMANDECK_SCRATCH="$T" bash "$REAL/hooks/resume-context.sh" 2>&1)
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
# A done item is deleted, never marked completed: the list the owner reads shows open items only.
check "the resumed TODO line says a done task is deleted, not completed" 1 \
  "$(grep -c '^TODO LIST: .*A task done is deleted (TaskUpdate status deleted), never marked completed; the checkpoint.s Closed section keeps it\.' <<<"$OUT")"
# #381: a seat run the checkpoint names that is not running and left no result is posted as one GONE line.
mkdir -p "$T/ps-live" "$T/ps-fail" "$T/ps-none"; printf "#!/bin/sh\nexit 0\n" > "$T/ps-none/ps"; chmod +x "$T/ps-none/ps"
printf '#!/bin/sh\necho "bash /x/scripts/seat.sh run builder gz /x/spec.md --marker DONE"\n' > "$T/ps-live/ps"
printf '#!/bin/sh\nexit 1\n' > "$T/ps-fail/ps"; chmod +x "$T/ps-live/ps" "$T/ps-fail/ps"
printf '## Goal\n- waiting on bash scripts/seat.sh run plan-author gx /x/spec.md\n' > "$CPD/gx.md"
OUT=$(RPATH="$T/ps-none:$PATH" resume "$CPD/gx.md")
check "a seat run the checkpoint names that is not running and left no result is posted as one GONE line" "1 0" \
  "$(grep -c '^GONE: seat run gx-plan-author is named in the checkpoint but is not running and left no result; relaunch it$' <<<"$OUT") $(grep -c 'runs not checked' <<<"$OUT")"
printf 'collected=1\n' > "$T/seat-gx-plan-author.txt"
OUT=$(RPATH="$T/ps-none:$PATH" resume "$CPD/gx.md")
check "a run with a collected record is not posted gone" 0 "$(grep -c '^GONE:' <<<"$OUT")"
rm -f "$T/seat-gx-plan-author.txt"
printf '## Goal\n- seat.sh run builder gz /x/spec.md, and seat-gy-builder running\n' > "$CPD/gz.md"
printf 'seat=builder unit=gy VERDICT: GO report=none\n' > "$T/run-gy-builder.log"
OUT=$(RPATH="$T/ps-live:$PATH" resume "$CPD/gz.md")
check "a running run and one whose log holds its result line are not posted gone" 0 "$(grep -c '^GONE:' <<<"$OUT")"
printf '## Goal\n- the record is seat-gq-builder.txt and seat-gq-builder.md\n' > "$CPD/gq.md"
OUT=$(RPATH="$T/ps-none:$PATH" resume "$CPD/gq.md")
check "a seat record's file name is not a run name" 0 "$(grep -c '^GONE:' <<<"$OUT")"
OUT=$(RPATH="$T/ps-fail:$PATH" resume "$CPD/gx.md")
check "a process list that cannot be read prints one runs-not-checked line and no GONE line" "1 0" \
  "$(grep -c '^runs not checked: the process list could not be read' <<<"$OUT") $(grep -c '^GONE:' <<<"$OUT")"
OUT=$(RPATH="$T/ps-none:$PATH" resume "$CPD/small.md")
check "a checkpoint that names no run adds nothing to the block" 0 "$(grep -c '^GONE:\|^runs not checked' <<<"$OUT")"
# The GONE block is bounded: 90 gone runs leave room for the checkpoint, keep the print under 10 KB, and the runs past
# the bound are counted in one line that points at the checkpoint.
{ printf '## Goal\n- keep this goal\n'; for i in $(seq 1 90); do printf -- '- bash scripts/seat.sh run plan-author unit-%s\n' "$i"; done; } > "$CPD/many.md"
OUT=$(RPATH="$T/ps-none:$PATH" resume "$CPD/many.md")
check "many gone runs: the GONE block is bounded, the rest counted in one line naming the checkpoint, the goal kept, the print under 10 KB" "yes 1 1 yes" \
  "$([ "$(grep -c '^GONE: seat run ' <<<"$OUT")" -le 10 ] && echo yes) $(grep -c "^GONE: [0-9]* more seat runs named in $CPD/many.md " <<<"$OUT") $(grep -c 'keep this goal' <<<"$OUT") $([ "$(printf '%s\n' "$OUT" | LC_ALL=C wc -c)" -le 10240 ] && echo yes)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
