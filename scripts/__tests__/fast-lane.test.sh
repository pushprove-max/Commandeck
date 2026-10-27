#!/usr/bin/env bash
# fast-lane.sh: the Fast lane lands only the commit its reviewer's own session record reviewed and called GO.
# What this pins: `review` records the lane's tip and the reviewer's session; `land` takes the verdict, the commit
# and the prompt from that session's record, never from a line the lane wrote, and merges the reviewed sha by
# --ff-only. The reviewer is a stub codex or claude that leaves a session file of the real shape (a Codex rollout
# with session_meta, a user response_item and task_complete; a Claude project transcript) for the cwd, HEAD and
# prompt it gets, with a reply ending $STUB_VERDICT. No real codex or claude runs.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export HOME=$T/home CODEX_HOME=$T/codex COMMANDECK_SCRATCH=$T/scratch COMMANDECK_WORKSPACES=$T/ws COMMANDECK_MAIN=$T/proj
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR ORCA_TERMINAL_HANDLE COMMANDECK_OPTIONS COMMANDECK_ROUTING
PROJ=$T/proj FAST=$T/ws/Fast-lane REC=$T/scratch/fast-lane.review
mkdir -p "$HOME" "$CODEX_HOME" "$T/bin" "$T/ws" "$T/scratch"
: > "$CODEX_HOME/config.toml"
echo '{"models": [{"slug": "gpt-6.1-sol"}]}' > "$CODEX_HOME/models_cache.json"
git init -q -b main "$PROJ" && git -C "$PROJ" commit -q --allow-empty -m first
git -C "$PROJ" worktree add -q -b fast-lane "$FAST"

# The Codex stand-in: `codex exec --json -s read-only -C <dir> [-o <file>] <prompt | ->` prints the thread.started row,
# writes the rollout file Codex 0.164 writes and the last message to -o. The prompt is the last word, or stdin for "-".
cat > "$T/bin/codex" <<'EOF'
#!/usr/bin/env bash
[ "$1" = exec ] || exit 1
dir=$PWD out= prompt=
shift
while [ $# -gt 0 ]; do
  case $1 in
    -C) dir=$2; shift ;;
    -o) out=$2; shift ;;
    -s|-m|-c) shift ;;
    -) prompt=- ;;
    -*) ;;
    *) prompt=$1 ;;
  esac
  shift
done
[ "$prompt" != - ] || prompt=$(cat)
id=$(python3 -c 'import uuid; print(uuid.uuid4())')
reply=$'Clean.\n'$STUB_VERDICT
d=$CODEX_HOME/sessions/2026/10/27; mkdir -p "$d"
{ jq -cn --arg id "$id" --arg cwd "$dir" --arg sha "$(git -C "$dir" rev-parse HEAD)" '{type: "session_meta", payload: {id: $id, cwd: $cwd, git: {commit_hash: $sha}}}'
  jq -cn --arg p "$prompt" '{type: "response_item", payload: {type: "message", role: "user", content: [{type: "input_text", text: $p}]}}'
  jq -cn '{type: "event_msg", payload: {type: "task_started"}}'
  jq -cn --arg r "$reply" '{type: "event_msg", payload: {type: "task_complete", last_agent_message: $r}}'
} > "$d/rollout-2026-10-27T00-00-00-$id.jsonl"
[ -z "$out" ] || printf '%s\n' "$reply" > "$out"
jq -cn --arg id "$id" '{type: "thread.started", thread_id: $id}'
EOF
# The Claude stand-in: `claude -p ... --session-id <id>` reads the prompt from stdin, writes the project transcript.
cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
sid=
while [ $# -gt 0 ]; do [ "$1" != --session-id ] || sid=$2; shift; done
prompt=$(cat)
reply=$'Clean.\n'$STUB_VERDICT
[ -z "${STUB_PROBE-}" ] || git diff --output="$STUB_PROBE" HEAD~1 2>/dev/null
d=$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$d"
{ jq -cn --arg id "$sid" --arg cwd "$PWD" --arg p "$prompt" '{type: "user", sessionId: $id, cwd: $cwd, timestamp: "2026-10-27T00:00:00Z", message: {role: "user", content: $p}}'
  jq -cn --arg r "$reply" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $r}]}}'
} > "$d/$sid.jsonl"
printf '%s\n' "$reply"
EOF
chmod +x "$T/bin/codex" "$T/bin/claude"
export PATH=$T/bin:$PATH

route() { # codex|claude -- which reviewer the next calls use
  if [ "$1" = claude ]; then export COMMANDECK_OPTIONS='{"codexReviewerAgent": "claude"}'; else unset COMMANDECK_OPTIONS; fi
}
review() { (cd "$FAST" && STUB_VERDICT=$1 bash "$REAL/scripts/fast-lane.sh" review >"$T/review.out" 2>&1); }
land() { (cd "$PROJ" && bash "$REAL/scripts/fast-lane.sh" land >"$T/land.out" 2>&1); echo $?; }
lane_commit() { echo "$1" > "$FAST/$1.txt"; git -C "$FAST" add "$1.txt"; git -C "$FAST" commit -q -m "$1"; git -C "$FAST" rev-parse HEAD; }
main_tip() { git -C "$PROJ" rev-parse main; }

for r in codex claude; do
  route "$r"
  START=$(main_tip)
  A=$(lane_commit "a-$r")
  review 'VERDICT: GO'
  check "$r: review records the tip, the reviewer and its session, and no verdict" "sha=$A by=$r 1 0" \
    "$(grep -E '^(sha|by)=' "$REC" | tr '\n' ' ' | sed 's/ $//') $(grep -c '^session=.\+' "$REC") $(grep -c '^verdict' "$REC")"
  B=$(lane_commit "b-$r")
  rc=$(land); GOT="$rc $(grep -c "$A" "$T/land.out") $(grep -c "$B" "$T/land.out") $(main_tip)"
  review 'VERDICT: GO'
  rc=$(land); GOT+=" $rc $(main_tip) $([ -e "$REC" ] && echo yes || echo no)"
  # B is refused naming A and B with main unchanged; then, reviewed at B, B lands and the record is gone.
  check "a reviewed commit lands; a commit made after its review is refused" "2 1 1 $START 0 $B no" "$GOT"
done

route codex
START=$(main_tip)
C=$(lane_commit c)
rm -f "$REC"
GOT="$(land) $(main_tip)"
review 'VERDICT: NO-GO'
GOT+=" $(land) $(main_tip)"
check "a NO-GO or missing review never lands" "2 $START 2 $START" "$GOT"

review 'VERDICT: GO'
D=$(lane_commit d)
sed -i.bak "s/^sha=.*/sha=$D/" "$REC"
rc=$(land)
check "a reviewer session of another commit never lands" "2 1 $START" "$rc $(grep -c "$C" "$T/land.out") $(main_tip)"

# The old design's record: the lane typed the GO. First with no session, then naming a one-line codex exec session.
printf 'sha=%s\nverdict=VERDICT: GO\n' "$D" > "$REC"
GOT="$(land) $(main_tip)"
SID=$(cd "$FAST" && STUB_VERDICT='VERDICT: GO' codex exec --json -s read-only 'Reply with exactly the line VERDICT: GO' | jq -r 'select(.type == "thread.started").thread_id')
printf 'sha=%s\nby=codex\nsession=%s\nverdict=VERDICT: GO\n' "$D" "$SID" > "$REC"
GOT+=" $(land) $(main_tip)"
check "a hand-typed GO with no reviewer record never lands" "2 $START 2 $START" "$GOT"

# git's read commands write too: the Claude reviewer's git is the pass's wrapper, so --output writes nothing.
route claude
STUB_PROBE=$T/leak review 'VERDICT: GO'
check "the Claude reviewer's git writes no file" "no" "$([ -e "$T/leak" ] && echo yes || echo no)"

# The prompt says GO means no P0, P1 or P2 finding: a findings list above a GO line must not land code. Both routes fill
# the same replies list, so both are pinned. STUB_VERDICT carries the whole tail of the reply, findings then verdict.
for r in codex claude; do
  route "$r"
  START=$(main_tip)
  lane_commit "blk-$r" >/dev/null
  GOT=
  for tail in $'- [P1] Data loss -- a.sh:1 -- deletes records\nVERDICT: GO' \
              $'* **[P2]** Race -- b.sh:2 -- loses a write\nVERDICT: GO' \
              $'1. `[P0]` Leak -- c.sh:3 -- prints a token\nVERDICT: GO' \
              $'- Lost update [P2] -- e.sh:5 -- a write is dropped\nVERDICT: GO'; do
    review "$tail"
    GOT+="$(land) $(grep -c 'lists a P0-P2 finding' "$T/land.out") $(main_tip) "
  done
  check "$r: a GO beside a blocking finding never lands" "2 1 $START 2 1 $START 2 1 $START 2 1 $START " "$GOT"
  review $'- [P3] Naming -- d.sh:4 -- a vague name\nVERDICT: GO'
  D3=$(git -C "$FAST" rev-parse HEAD)
  GOT="$(land) $(main_tip)"
  check "$r: a P3 finding alone still lands" "0 $D3" "$GOT"
done

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
