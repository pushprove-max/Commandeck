#!/usr/bin/env bash
# Self-test for ruling-log-archive.sh. Run directly: bash scripts/__tests__/ruling-log-archive.test.sh
#
# Why each case matters: the ruling log is what every "owner ruling" cites, so the one-off move may take out only rows
# that were never the owner's rulings (other sessions' prompts, void rows, machine text) and must lose nothing: the live log
# plus the archive hold every row, in order and byte for byte, and every picker answer and typed prompt still
# resolves in the live log. A writer appending while it runs must not lose its row either.
set -u
SOURCE=$(git rev-parse --show-toplevel)
SCRIPT=$SOURCE/scripts/ruling-log-archive.sh
BOX=$(mktemp -d "${TMPDIR:-/tmp}/ruling-archive-test.XXXXXX")
trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi
}
MAIN=$BOX/proj COS=/u/workspaces/proj/Chief-of-Staff RES=/u/workspaces/proj/Research WT=/u/workspaces/proj/unit-a
git init -q "$MAIN"
# Run inside main's checkout: paths.sh follows COMMANDECK_MAIN only from there (project-main.sh).
run() { (cd "$MAIN" && bash "$SCRIPT"); }
export COMMANDECK_MAIN=$MAIN COMMANDECK_RULING_LOG=$BOX/log.jsonl
ARCH=$BOX/log.archive-2026-10-24.jsonl
row() { # <id> <source> <cwd> <answer> [void]
  jq -cn --arg id "$1" --arg s "$2" --arg c "$3" --arg a "$4" --arg v "${5:-}" \
    '{id:$id, utc:"2026-10-24T10:00:00Z", source:$s, cwd:$c, answer:$a} + (if $v == "" then {} else {void:true} end)'
}
{
  row r-ask-wt ask "$WT" "Keep grip"
  row r-ask-decoy ask "$MAIN" "decoy" void
  row r-p-main prompt "$MAIN" "ship it after the chain is green"
  row r-p-wt prompt "$WT" "<role> You are Codex performing a review"
  row r-p-cos prompt "$COS/sub" "relay that to main"
  row r-p-research prompt "$RES" "passport stays opt-in"
  row r-p-void prompt "$MAIN" "<task-notification>x</task-notification>" void
  row r-p-banner prompt "$MAIN" "You have 1 orchestration message. Run \`orca orchestration check --run r\`."
  row r-p-judge prompt "$MAIN" "=== Transcript of a conversation between a human and an assistant"
  row r-p-quote prompt "$MAIN" "the banner said You have 1 orchestration message -- ignore it"
  echo '{"id":"r-damaged","answer":"half a row{"id":"r-y"'
  row r-p-sibling prompt "${MAIN}-old" "a folder that only starts like main's"
} > "$COMMANDECK_RULING_LOG"
cp "$COMMANDECK_RULING_LOG" "$BOX/before.jsonl"
ids() { jq -rR 'fromjson? | .id' "$1" | paste -sd' ' -; }

out=$(run 2>&1); rc=$?
check "the move runs" "0" "$rc"
check "the live log keeps picker answers (void ones too), typed main and Chief-of-Staff prompts and unreadable lines, in order" \
  "r-ask-wt r-ask-decoy r-p-main r-p-cos r-p-quote 1" "$(ids "$COMMANDECK_RULING_LOG") $(grep -c 'half a row' "$COMMANDECK_RULING_LOG")"
check "the archive holds other sessions' prompts (a Research worktree's too: the plugin logs only main's and the Chief-of-Staff's), void prompts and machine text, in order" \
  "r-p-wt r-p-research r-p-void r-p-banner r-p-judge r-p-sibling" "$(ids "$ARCH")"
check "nothing is lost or changed: the two files hold the log's rows byte for byte" "same" \
  "$(cat "$COMMANDECK_RULING_LOG" "$ARCH" | sort | cmp -s - <(sort "$BOX/before.jsonl") && echo same)"
check "a typed ruling still resolves by its words" "r-p-main" \
  "$(jq -rR 'fromjson? | select(.source == "prompt" and (.answer | contains("chain is green"))) | .id' "$COMMANDECK_RULING_LOG")"
check "it says what it kept and moved" "1" "$(grep -c 'kept 6 of 12 rows' <<<"$out")"

# A second run moves nothing new and keeps the archive as it is.
cp "$ARCH" "$BOX/arch1"; cp "$COMMANDECK_RULING_LOG" "$BOX/live1"; run >/dev/null 2>&1
check "a second run changes neither file" "same same" \
  "$(cmp -s "$COMMANDECK_RULING_LOG" "$BOX/live1" && echo same) $(cmp -s "$ARCH" "$BOX/arch1" && echo same)"

# The rewrite happens under the log's lock: while a writer holds it nothing is replaced, and the rows that writer
# appends are split too, so none is lost.
rm -f "$ARCH"; cp "$BOX/before.jsonl" "$COMMANDECK_RULING_LOG"
( exec 9>>"$COMMANDECK_RULING_LOG"; flock -x 9; : > "$BOX/held"; until [ -e "$BOX/release" ]; do sleep 0.05; done
  { row r-late-main prompt "$MAIN" "late but typed"; row r-late-wt prompt "$WT" "late worker prompt"; } >&9 ) &
HOLDER=$!
until [ -e "$BOX/held" ]; do sleep 0.05; done
run >/dev/null 2>&1 & MOVER=$!
sleep 1
check "while another writer holds the lock the log is not rewritten" "12 no" \
  "$(grep -c . "$COMMANDECK_RULING_LOG") $([ -e "$ARCH" ] && echo yes || echo no)"
: > "$BOX/release"; wait "$HOLDER"; wait "$MOVER"
check "rows appended under the lock are split like the rest" "r-p-cos r-p-quote r-late-main|r-p-sibling r-late-wt" \
  "$(ids "$COMMANDECK_RULING_LOG" | awk '{print $(NF-2), $(NF-1), $NF}')|$(ids "$ARCH" | awk '{print $(NF-1), $NF}')"

# Two runs at once: B snapshots, then waits on the lock while A (the holder here) rewrites the log shorter and a typed
# ruling is appended. B's snapshot no longer matches the log, so B refuses and the new ruling stays.
rm -f "$ARCH" "$BOX/held" "$BOX/release"; cp "$BOX/before.jsonl" "$COMMANDECK_RULING_LOG"
( exec 9>>"$COMMANDECK_RULING_LOG"; flock -x 9; : > "$BOX/held"; until [ -e "$BOX/release" ]; do sleep 0.05; done
  grep -v '"r-p-wt"' "$BOX/before.jsonl" > "$COMMANDECK_RULING_LOG"; row r-new-main prompt "$MAIN" "typed after the other move" >&9 ) &
HOLDER=$!
until [ -e "$BOX/held" ]; do sleep 0.05; done
run >/dev/null 2>&1 & MOVER=$!
sleep 1; : > "$BOX/release"; wait "$HOLDER"
{ grep -v '"r-p-wt"' "$BOX/before.jsonl"; row r-new-main prompt "$MAIN" "typed after the other move"; } > "$BOX/expect"
wait "$MOVER"; rc=$?
check "a run whose snapshot another run rewrote refuses and leaves the log, new ruling included, as it is" "1 same no" \
  "$rc $(cmp -s "$COMMANDECK_RULING_LOG" "$BOX/expect" && echo same) $([ -e "$ARCH" ] && echo yes || echo no)"

# The rewrite truncates the live log before the kept rows are back in it, and the moved rows are in the archive only.
# A run killed in between (SIGTERM; its EXIT trap clears the scratch) must leave every row on disk: a full copy of the
# log beside it, kept until the rewrite is done, and a rerun that refuses while that copy is there (it would move from
# the half-written log and then drop the copy).
BAK=$BOX/log.before-archive.jsonl
rm -f "$ARCH"; cp "$BOX/before.jsonl" "$COMMANDECK_RULING_LOG"
mkdir -p "$BOX/bin"; CAT=$(command -v cat)
printf '#!/usr/bin/env bash\ncase "${1:-}" in */snap.keep) head -c 1 "$1"; kill -TERM "$PPID"; exit 143 ;; esac\nexec %s "$@"\n' "$CAT" > "$BOX/bin/cat"
chmod +x "$BOX/bin/cat"
(cd "$MAIN" && PATH=$BOX/bin:$PATH bash "$SCRIPT") >/dev/null 2>&1; rc=$?
check "a run killed mid-rewrite fails and leaves the whole log in the copy beside it" "nonzero same" \
  "$([ "$rc" != 0 ] && echo nonzero) $(cmp -s "$BAK" "$BOX/before.jsonl" && echo same)"
cp "$COMMANDECK_RULING_LOG" "$BOX/half"; cp "$ARCH" "$BOX/arch-half"
out=$(run 2>&1); rc=$?
check "a rerun while that copy is there refuses, names it, and changes no file" "1 1 same same same" \
  "$rc $(grep -c "$BAK" <<<"$out") $(cmp -s "$COMMANDECK_RULING_LOG" "$BOX/half" && echo same) $(cmp -s "$ARCH" "$BOX/arch-half" && echo same) $(cmp -s "$BAK" "$BOX/before.jsonl" && echo same)"
rm -f "$ARCH"; mv "$BAK" "$COMMANDECK_RULING_LOG"
run >/dev/null 2>&1; rc=$?
check "restored from the copy, a run completes and removes it" "0 r-p-main gone" \
  "$rc $(ids "$COMMANDECK_RULING_LOG" | awk '{print $3}') $([ -e "$BAK" ] && echo kept || echo gone)"

# Issue 460: the archive spelled its own seat names, so a name added only to PP_STANDING_SEATS lost its prompts here while
# ruling-log.sh still logged them. The copy of the tree has the name added to the list; nothing else changed.
TREE=$BOX/tree
mkdir -p "$TREE"; cp -R "$SOURCE/scripts" "$SOURCE/hooks" "$TREE/"
sed 's/^PP_STANDING_SEATS=(\(.*\))$/PP_STANDING_SEATS=(\1 New-seat)/' "$SOURCE/hooks/lib/project.sh" > "$TREE/hooks/lib/project.sh"
rm -f "$ARCH"
row r-new prompt /u/workspaces/proj/New-seat "a typed ruling" > "$COMMANDECK_RULING_LOG"
(cd "$MAIN" && bash "$TREE/scripts/ruling-log-archive.sh") >/dev/null 2>&1
check "a listed name keeps its prompts (issue 460)" "r-new" "$(ids "$COMMANDECK_RULING_LOG")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
