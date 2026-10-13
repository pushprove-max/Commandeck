#!/usr/bin/env bash
# A resume injection of 10240 bytes or more reaches main as a 2 KB preview, so
# the checkpoint had to be re-read by hand. Every case stays under 10240 bytes:
# persona, RESUMED line and run binding first, then the checkpoint, board.sh and
# The owner's prompts, and each part that does not fit becomes one pointer line that
# the RESUMED line names and allows reading once.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/main" "$BOX/bin" "$BOX/transcripts" \
  "$BOX/home/.claude/checkpoints" "$BOX/home/.config/orca"
git init -q "$BOX/main"
PSLUG=$(printf '%s' "$(git -C "$BOX/main" rev-parse --show-toplevel)" | tr -c 'A-Za-z0-9' '-')  # the marker is per repo
printf '# Checkpoint previous\n- [ ] Resume pending work\n' \
  > "$BOX/home/.claude/checkpoints/previous.md"
printf '%s\n' "$BOX/home/.claude/checkpoints/previous.md" \
  > "$BOX/home/.claude/checkpoints/resume-pending.$PSLUG"
mkdir -p "$BOX/home/.commandeck/scratch/$PSLUG" && printf 'run_fixture\n' > "$BOX/home/.commandeck/scratch/$PSLUG/current-run"
printf '#!/bin/sh\n[ "${RUNUSE_FAIL:-}" = 1 ] && { echo refused; exit 1; }\nprintf '\''{"ok":true}\\n'\''\n' > "$BOX/bin/orca-ide"
chmod +x "$BOX/bin/orca-ide"
python3 -c '
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({
        "type": "user",
        "message": {"role": "user", "content": "x" * 11000}
    }) + "\n")
' "$BOX/transcripts/previous.jsonl"
OUT=$(
  cd "$BOX/main"
  printf '{"session_id":"new","transcript_path":"%s/new.jsonl"}' \
    "$BOX/transcripts" |
    env -u COMMANDECK_REVIEWER HOME="$BOX/home" PATH="$BOX/bin:$PATH" \
      COMMANDECK_BOARD_CMD=/usr/bin/true \
      COMMANDECK_HOOK_FIRE_LOG="$BOX/fire.jsonl" \
      bash "$ROOT/hooks/resume-context.sh"
)

PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
has() { grep -qF -- "$1" <<<"$2" && echo 1 || echo 0; }
under() { [ "$(printf '%s\n' "$OUT" | wc -c | tr -d ' ')" -lt 10240 ] && echo 1 || echo "$(printf '%s\n' "$OUT" | wc -c | tr -d ' ') bytes"; }
CUTNOTE='read each of their pointer lines below once (allowed)'

# 1. An 11,000-byte prompt alone used to push the injection to ~12 KB.
check "an 11,000-byte prompt keeps the injection under 10240 bytes" 1 "$(under)"
check "the prompts become one pointer naming the transcript" 1 "$(grep -cF "read them in $BOX/transcripts/previous.jsonl" <<<"$OUT")"
check "and no prompt text arrives" 0 "$(has '<<< prompt' "$OUT")"
check "the RESUMED line names the prompts as cut" 1 "$(has "cut to fit 10 KB: the owner's prompts" "$OUT")"
check "and allows reading the pointer once" 1 "$(has "$CUTNOTE" "$OUT")"
check "and no longer forbids fetching them" 0 "$(has 'do not fetch them again' "$OUT")"

CPD=$BOX/home/.claude/checkpoints
# A checkpoint in the template's shape: every section N bytes of 2-byte
# characters (so a character count would under-measure it) and a sentinel last.
mkcp() { # name filler-chars
  python3 - "$CPD/$1.md" "$2" <<'PY'
import sys
path, n = sys.argv[1], int(sys.argv[2])
secs = ["Goal", "Live units (one line each)", "Waiting on", "Rulings this session not yet in memory or a rule file",
        "Queue (in order)", "Gotchas learned this session", "Resume"]
with open(path, "w", encoding="utf-8") as f:
    f.write("# Checkpoint test\n\nTITLE-SENTINEL\n")
    for s in secs:
        f.write(f"\n## {s}\n- " + "é" * n + f"\n- END-{s.split()[0].upper()}\n")
PY
}
resume() { # checkpoint name, prompt bytes (0 = one short prompt), board bytes
  python3 - "$BOX/transcripts/$1.jsonl" "$2" <<'PY'
import json, sys
n = int(sys.argv[2])
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": "PROMPT-" + "p" * n}}) + "\n")
PY
  printf '%s\n' "$CPD/$1.md" > "$CPD/resume-pending.$PSLUG"
  printf 'head -c %s /dev/zero | tr "\\0" b; echo; echo BOARD-END\n' "$3" > "$BOX/board"
  OUT=$(cd "$BOX/main" && printf '{"session_id":"s%s","transcript_path":"%s/new-%s.jsonl"}' "$1" "$BOX/transcripts" "$1" |
    env -u COMMANDECK_REVIEWER HOME="$BOX/home" PATH="$BOX/bin:$PATH" COMMANDECK_BOARD_CMD="sh $BOX/board" \
      COMMANDECK_HOOK_FIRE_LOG="$BOX/fire.jsonl" bash "$ROOT/hooks/resume-context.sh")
}

# 2. Everything fits: nothing is cut and nothing needs fetching.
mkcp small 50; resume small 0 200
check "a small resume is whole" 11 "$(has '<<< prompt 1 of 1' "$OUT")$(has BOARD-END "$OUT")"
check "and still says do not fetch them again" 1 "$(has 'do not fetch them again' "$OUT")"
check "and names no cut" 0 "$(has 'cut to fit' "$OUT")"

# 3. A checkpoint alone over the budget keeps Goal, Live units, Waiting on and
#    Resume whole and points at the file for the rest.
mkcp big 800; resume big 0 200
check "an oversized checkpoint stays under 10240 bytes" 1 "$(under)"
for s in GOAL LIVE WAITING RESUME; do check "and keeps its $s section whole" 1 "$(has "END-$s" "$OUT")"; done
check "and its title" 1 "$(has TITLE-SENTINEL "$OUT")"
for s in RULINGS QUEUE GOTCHAS; do check "and drops its $s section" 0 "$(has "END-$s" "$OUT")"; done
check "behind one pointer naming the file and the dropped sections" 1 \
  "$(has "Read $CPD/big.md for: Rulings this session not yet in memory or a rule file; Queue (in order); Gotchas learned this session" "$OUT")"
check "and the RESUMED line names the checkpoint cut" 1 "$(has 'the checkpoint past Goal, Live units, Waiting on and Resume' "$OUT")"

# 4. The checkpoint fits whole but board.sh then does not: board.sh is one
#    pointer to the command, and the checkpoint is not squeezed for it.
mkcp mid 400; resume mid 0 3900
check "a full board stays under 10240 bytes" 1 "$(under)"
check "the checkpoint arrives whole" 1 "$([[ $OUT == *"$(cat "$CPD/mid.md")"* ]] && echo 1 || echo 0)"
check "board.sh is left out" 0 "$(has BOARD-END "$OUT")"
check "behind one pointer naming its command" 1 "$(has "## board.sh: left out to fit the resume budget; run \`sh $BOX/board\` for it" "$OUT")"
check "and the RESUMED line names board.sh as cut" 1 "$(has 'cut to fit 10 KB: board.sh' "$OUT")"

# 5. Full size: a big checkpoint, an 11,000-byte prompt and a 4000-byte board.
mkcp full 800; resume full 11000 4000
check "the full-size case stays under 10240 bytes" 1 "$(under)"
check "and keeps the Resume section" 1 "$(has END-RESUME "$OUT")"
check "and names all three cuts" 1 "$(has "cut to fit 10 KB: the checkpoint past Goal, Live units, Waiting on and Resume; board.sh; the owner's prompts" "$OUT")"
check "and allows reading their pointers once" 1 "$(has "$CUTNOTE" "$OUT")"

# 6. A refused binding prints more lines and still fits, naming its cuts.
mkcp unb 800; RUNUSE_FAIL=1 resume unb 11000 4000
check "an unbound full-size resume stays under 10240 bytes" 1 "$(under)"
check "and says NOT BOUND" 1 "$(has 'NOT BOUND' "$OUT")"
check "and names its cuts" 1 "$(has "$CUTNOTE" "$OUT")"

# 7. Warning output obeys the budget too: a missing transcript's warning names
#    a long path twice, past the one-path room the hook holds back.
check "a missing transcript's warning stays within the prompts budget" ok "$(cd "$ROOT" && python3 -c '
import runpy
p = "/" + "/".join(["a" * 50] * 6) + "/previous.jsonl"
b = 200 + len(p.encode()) + 1
out = "\n".join(runpy.run_path("scripts/checkpoint-context.py")["messages"](p, b)) + "\n"
print("ok" if len(out.encode()) <= b and p in out else f"{len(out.encode())} bytes for a {b}-byte budget")')"

echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
