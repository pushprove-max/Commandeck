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
[ -z "${STUB_HOOK-}" ] || eval "$STUB_HOOK"
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

# Issue 428: landed means main's index is the reviewed commit and every file the lane changes is its text on disk. A
# staged change is refused before main moves. An unstaged edit on a path the lane changes is refused, main untouched;
# one on any other path is allowed and named. STUB_HOOK edits main's checkout while the reviewer runs.
route codex
lane_commit base >/dev/null; review 'VERDICT: GO'; land >/dev/null
START=$(main_tip)
echo staged >> "$PROJ/base.txt"; git -C "$PROJ" add base.txt
lane_commit s1 >/dev/null; review 'VERDICT: GO'
check "a staged change in main's checkout is refused, main untouched" "2 1 $START" \
  "$(land) $(grep -c 'staged change' "$T/land.out") $(main_tip)"
git -C "$PROJ" reset -q --hard
echo v2 >> "$FAST/base.txt"; git -C "$FAST" commit -q -am v2
STUB_HOOK='echo edit > "$COMMANDECK_MAIN/base.txt"' review 'VERDICT: GO'
check "an edit to a lane path made while the reviewer ran never lands" "2 $START edit" \
  "$(land) $(main_tip) $(cat "$PROJ/base.txt")"
git -C "$PROJ" checkout -q -- base.txt
W=$(lane_commit u1)
STUB_HOOK='echo local >> "$COMMANDECK_MAIN/a-codex.txt"' review 'VERDICT: GO'
check "an unstaged edit on a path the lane does not change lands and is named" "0 $W 1 local" \
  "$(land) $(main_tip) $(grep -c 'unstaged edits land did not touch: a-codex.txt$' "$T/land.out") $(tail -1 "$PROJ/a-codex.txt")"
git -C "$PROJ" checkout -q -- a-codex.txt

# A refusal after the merge leaves main at the reviewed commit and keeps the record. A retry then checks the paths the
# first attempt's merge changed (the record's base=), not the empty range from main's new HEAD; with no base, or one
# that is not an ancestor of the reviewed commit, every tracked path. A post-merge hook edits a lane path after main
# moves, before land checks the checkout.
R=$(lane_commit r1); review 'VERDICT: GO'
printf '#!/usr/bin/env bash\necho hook > r1.txt\n' > "$PROJ/.git/hooks/post-merge"; chmod +x "$PROJ/.git/hooks/post-merge"
GOT="$(land) $(main_tip)"
rm -f "$PROJ/.git/hooks/post-merge"
GOT+=" $(land) $(grep -c "is not $R at: r1.txt\$" "$T/land.out")"
ROOTC=$(git -C "$PROJ" commit-tree -m unrelated "$(git -C "$PROJ" hash-object -t tree /dev/null)")
sed -i.bak "s/^base=.*/base=$ROOTC/" "$REC"
GOT+=" $(land)"
grep -v '^base=' "$REC" > "$REC.tmp"; mv "$REC.tmp" "$REC"
GOT+=" $(land) $([ -e "$REC" ] && echo kept) $(cat "$PROJ/r1.txt")"
git -C "$PROJ" checkout -q -- r1.txt
GOT+=" $(land) $([ -e "$REC" ] && echo kept || echo gone)"
check "a retry after a refusal past the merge still refuses the dirty lane path, then lands once it is clean" \
  "2 $R 2 1 2 2 kept hook 0 gone" "$GOT"

# The lane-path check must see every path the lane changes as git names it: a non-ASCII name (not quoted), a path the
# lane deletes or renames away (recreated on disk after the merge it is untracked, and a delete is not a diff), and a
# name with a glob in it (a literal path, not a pattern). Each case leaves main clean and landed, hook removed.
HOOK=$PROJ/.git/hooks/post-merge
hook() { printf '#!/usr/bin/env bash\n%s\n' "$1" > "$HOOK"; chmod +x "$HOOK"; }
reset_main() { rm -f "$HOOK"; git -C "$PROJ" reset -q --hard; git -C "$PROJ" clean -fdq; }

reset_main
lane_commit café >/dev/null; review 'VERDICT: GO'
hook 'echo dirty > café.txt'
GOT="$(land)"
rm -f "$HOOK"; git -C "$PROJ" checkout -q -- café.txt
GOT+=" $(land)"
check "a dirty non-ASCII lane path is refused, then lands once it is clean" "2 0" "$GOT"

reset_main
lane_commit removed >/dev/null; review 'VERDICT: GO'; GOT="$(land)"
git -C "$FAST" rm -q removed.txt; git -C "$FAST" commit -q -m rm
RM=$(git -C "$FAST" rev-parse HEAD); review 'VERDICT: GO'
hook 'echo back > removed.txt'
GOT+=" $(land) $(grep -c "is not $RM at: removed.txt\$" "$T/land.out")"
rm -f "$HOOK"
GOT+=" $(land)"
cp "$REC" "$T/rec.removed"
rm "$PROJ/removed.txt"
GOT+=" $(land) $([ -e "$REC" ] && echo kept || echo gone)"
check "a path the lane deletes and the checkout recreates is refused, also on a retry, then lands once it is gone" \
  "0 2 1 2 0 gone" "$GOT"
# With no base= the retry has no record of the paths the lane deleted, so it cannot see the recreated file and lands.
cp "$T/rec.removed" "$REC"; sed -i.bak '/^base=/d' "$REC"; echo back > "$PROJ/removed.txt"
GOT="$(land) $([ -e "$REC" ] && echo kept || echo gone) $([ -e "$PROJ/removed.txt" ] && echo present)"
rm -f "$PROJ/removed.txt"
check "a retry with no base= cannot see a recreated deleted path (a documented limit)" "0 gone present" "$GOT"

reset_main
lane_commit oldname >/dev/null; review 'VERDICT: GO'; GOT="$(land)"
git -C "$FAST" mv oldname.txt newname.txt; git -C "$FAST" commit -q -m mv
review 'VERDICT: GO'
hook 'echo oldname > oldname.txt'
GOT+=" $(land)"
rm -f "$HOOK"; rm "$PROJ/oldname.txt"
GOT+=" $(land)"
check "a path the lane renames away and the checkout recreates is refused, then lands once it is gone" "0 2 0" "$GOT"

reset_main
lane_commit g1 >/dev/null; review 'VERDICT: GO'; GOT="$(land)"
G=$(lane_commit 'g*')
STUB_HOOK='echo local >> "$COMMANDECK_MAIN/g1.txt"' review 'VERDICT: GO'
GOT+=" $(land) $(main_tip) $(grep -c 'unstaged edits land did not touch: g1.txt$' "$T/land.out")"
git -C "$PROJ" checkout -q -- g1.txt
check "a lane path with a glob in it is literal: an unstaged edit on a file it would match lands and is named" "0 0 $G 1" "$GOT"

# Issue 442: main moving on after the review must not force a rebase and a second review of the same work, so the
# reviewed commit itself is merged; but only when no file changed on both sides, so no auto-merged text that nobody
# reviewed can land. A refusal leaves main untouched and the lane is put back on main for the next case.
main_commit() { echo "$1" > "$PROJ/$1"; git -C "$PROJ" add -- "$1"; git -C "$PROJ" commit -q -m "$1"; git -C "$PROJ" rev-parse HEAD; }
lane_sync() { git -C "$FAST" reset -q --hard main; }
parents() { git -C "$PROJ" rev-list --parents -1 main | wc -w | tr -d ' '; }
dirty() { git -C "$PROJ" status --porcelain | wc -l | tr -d ' '; }
reset_main; lane_sync
E=$(lane_commit e); review 'VERDICT: GO'
M=$(main_commit m.txt)
GOT="$(land) $(git -C "$PROJ" merge-base --is-ancestor "$E" main && echo has-e) $(git -C "$PROJ" merge-base --is-ancestor "$M" main && echo has-m) $(parents) $([ -e "$REC" ] && echo kept || echo gone)"
check "a reviewed commit lands when main moved after the review (issue 442)" "0 has-e has-m 3 gone" "$GOT"

lane_sync; seq 1 10 > "$FAST/f.txt"; git -C "$FAST" add f.txt; git -C "$FAST" commit -q -m f; review 'VERDICT: GO'; land >/dev/null
sed -i.bak '10s/.*/lane/' "$FAST/f.txt"; rm -f "$FAST/f.txt.bak"; git -C "$FAST" commit -q -am f-lane; review 'VERDICT: GO'
sed -i.bak '1s/.*/main/' "$PROJ/f.txt"; rm -f "$PROJ/f.txt.bak"; git -C "$PROJ" commit -q -am f-main; M=$(main_tip)
check "a same-file edit git would merge cleanly still refuses, main untouched (issue 442)" "2 $M 0 1" \
  "$(land) $(main_tip) $(dirty) $(grep -c 'f.txt' "$T/land.out")"

lane_sync; lane_commit rn >/dev/null; review 'VERDICT: GO'; land >/dev/null
lane_sync; git -C "$FAST" mv rn.txt rn2.txt; git -C "$FAST" commit -q -m mv; review 'VERDICT: GO'
echo edited > "$PROJ/rn.txt"; git -C "$PROJ" commit -q -am rn-main; M=$(main_tip)
check "a lane rename that main edited on the old path refuses (issue 442)" "2 $M 0" "$(land) $(main_tip) $(dirty)"

# The first land merges and then refuses on a lane path a post-merge hook dirtied. Its retry finds the reviewed commit
# already in main: it merges nothing, still checks the lane paths from the recorded base, and lands once they are clean.
lane_sync; lane_commit rt >/dev/null; review 'VERDICT: GO'; main_commit mt.txt >/dev/null
hook 'echo hook > rt.txt'
GOT="$(land)"; MC=$(main_tip); rm -f "$HOOK"
GOT+=" $(land) $(grep -c 'at: rt.txt$' "$T/land.out") $([ "$(main_tip)" = "$MC" ] && echo same)"
git -C "$PROJ" checkout -q -- rt.txt
GOT+=" $(land) $([ "$(main_tip)" = "$MC" ] && echo same) $(parents) $([ -e "$REC" ] && echo kept || echo gone)"
check "a retry after a landed merge commit merges nothing and checks the lane paths again (issue 442)" "2 2 1 same 0 same 3 gone" "$GOT"

lane_sync; mkdir -p "$FAST/x"; echo y > "$FAST/x/y"; git -C "$FAST" add x; git -C "$FAST" commit -q -m x-dir; review 'VERDICT: GO'
M=$(main_commit x)
check "a merge git cannot finish is aborted and main is untouched (issue 442)" "2 $M 0 no" \
  "$(land) $(main_tip) $(dirty) $([ -e "$PROJ/.git/MERGE_HEAD" ] && echo yes || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
