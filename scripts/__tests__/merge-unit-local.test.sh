#!/usr/bin/env bash
# timeout: 240
# A Builder's seat ends with its merge, so merge-unit-local.sh writes its token ledger row. Two seats launched
# together in one worktree each have a session log after the launch, and only the seat record's tag tells them
# apart: without it the row could name the sibling's session and count its tokens as the Builder's. Pinned: after a
# GO merge, the Builder's ledger row names the session whose prompt carries the Builder's own tag.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

# Two seats launched together in u's worktree: the sibling's session starts first, the Builder's after it.
mk u; LA=$(( $(date +%s) - 600 )); mkdir -p "$COMMANDECK_SCRATCH"
printf 'handle=t_u\ntask=task_b\nunit=u\nrole=builder\nlaunched=%s\ntag=SEAT-TAG-BUILDER\n' "$LA" > "$COMMANDECK_SCRATCH/seat-u-builder.txt"
printf 'handle=t_s\ntask=task_s\nunit=u\nrole=brief-reviewer\nlaunched=%s\ntag=SEAT-TAG-SIBLING\n' "$LA" > "$COMMANDECK_SCRATCH/seat-u-brief-reviewer.txt"
PROJ=$HOME/.claude/projects/$(printf '%s' "$COMMANDECK_WORKSPACES/u" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PROJ"
log() { jq -nc --arg t "$(date -u -d "@$2" +%FT%TZ)" --arg p "Seat tag $3: read the brief." '{type: "user", timestamp: $t, message: {content: $p}}' > "$PROJ/$1.jsonl"; }
log sibling $((LA + 10)) SEAT-TAG-SIBLING; log builder $((LA + 20)) SEAT-TAG-BUILDER
go u
merge u > /dev/null
check "the Builder's ledger row names the Builder's own session, not its sibling's" "$PROJ/builder.jsonl" \
  "$(jq -r 'select(.unit == "u" and .role == "builder") | .session' "$REPO/.claude/metrics/seat-events.jsonl" 2>/dev/null)"
# Issue 271: the merge adds the unit's row to the unit ledger, its outcome read from the round files and the proof.
UL=$REPO/.claude/metrics/unit-ledger.jsonl
check "a merge appends one unit ledger row for the unit, with its sha, round counts and the proof's rule" \
  "1|$(git -C "$REPO" rev-parse HEAD)|1|1|0|CONVERGED-GO|$(sed -n 's/^Builder proof: .*; rule: //p' "$TMP/out")" \
  "$(jq -sr 'map(select(.unit == "u")) | "\(length)|\(.[0] | "\(.mergeSha)|\(.rounds)|\(.goRounds)|\(.noGoRounds)|\(.verdict)|\(.mergeRule)")"' "$UL" 2>/dev/null)"
# A ledger the writer cannot write refuses the row: the writer says why, and the merge stands.
mv "$UL" "$TMP/ul.kept"; mkdir "$UL"
# A Builder that went on in a fresh session (builder-fresh-round.sh) has a record with one session= line per session;
# its ledger row counts them all, or the tokens of every later phase vanish from the unit's cost.
mk v; PV=$HOME/.claude/projects/$(printf '%s' "$COMMANDECK_WORKSPACES/v" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PV"
printf 'handle=t_v\ntask=task_v\nunit=v\nrole=builder\nlaunched=%s\ntag=SEAT-TAG-V\nsession=first\nsession=second\n' "$LA" > "$COMMANDECK_SCRATCH/seat-v-builder.txt"
use() { jq -nc --arg t "$(date -u -d "@$2" +%FT%TZ)" --argjson i "$3" '{type: "assistant", timestamp: $t, message: {id: "m\($i)", model: "claude-x", usage: {input_tokens: $i, output_tokens: 10}}}'; }
{ jq -nc --arg t "$(date -u -d "@$((LA + 30))" +%FT%TZ)" '{type: "user", timestamp: $t, message: {content: "Seat tag SEAT-TAG-V: read the brief."}}'; use x $((LA + 31)) 100; } > "$PV/first.jsonl"
use x $((LA + 40)) 200 > "$PV/second.jsonl"
go v
merge v > /dev/null
check "a refused ledger writer prints its line, and the merge of v still ends 0" "1 1 1" \
  "$(grep -c '^DONE unit=v merged=local' "$TMP/out") $(grep -c "^unit-ledger: cannot write $UL" "$TMP/out") $(grep -c "no unit ledger row written for v (ignored)" "$TMP/out")"
rmdir "$UL"; mv "$TMP/ul.kept" "$UL"
check "a Builder's ledger row sums the tokens of every session its record names" "300:20" \
  "$(jq -r 'select(.unit == "v" and .role == "builder") | "\(.tokens.input):\(.tokens.output)"' "$REPO/.claude/metrics/seat-events.jsonl" 2>/dev/null)"
# Every finding, P0 to P3, blocks the merge: a closing NO-GO of any severity never merges with its findings open.
H0=$(git -C "$REPO" rev-parse HEAD)
mk t; go t; STUB_REPLY=$'- [P2] (class: probe) A small thing -- t.txt:1 -- say it plainly -- cat t.txt\nVERDICT: NO-GO' pass t 2 final
check "a closing NO-GO with P2s only does not merge, and main is unchanged" "1 1 0 $H0" \
  "$(merge t) $(grep -c '^FAILED step 1 proof' "$TMP/out") $(grep -c '^DONE unit=t' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
mk t3; go t3; STUB_REPLY=$'- [P3] (class: probe) A nit -- t3.txt:1 -- say it plainly -- cat t3.txt\nVERDICT: NO-GO' pass t3 2 final
check "a closing NO-GO with a P3 only does not merge, and main is unchanged" "1 0 $H0" \
  "$(merge t3) $(grep -c '^DONE unit=t3' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
mk p1; go p1; STUB_REPLY=$'- [P1] (class: probe) blocker -- p1.txt:1 -- wrong -- cat p1.txt\nVERDICT: NO-GO' pass p1 2 final
check "a closing NO-GO with a P1 does not merge, and main is unchanged" "1 0 $H0" \
  "$(merge p1) $(grep -c '^DONE unit=p1' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
mk cg; go cg; STUB_REPLY='VERDICT: GO' pass cg 2 final
check "a closing reply of only VERDICT: GO merges under the closing GO rule" "0 1 1" \
  "$(merge cg) $(grep -c '^DONE unit=cg merged=local' "$TMP/out") $(grep -c '^Builder proof: .*; rule: closing GO$' "$TMP/out")"
check "its unit ledger row is a converged GO under the closing GO rule" "CONVERGED-GO|closing GO" \
  "$(jq -sr 'map(select(.unit == "cg")) | .[0] | "\(.verdict)|\(.mergeRule)"' "$UL" 2>/dev/null)"

# Issue 271: round files generated by builder-codex-pass.sh u 1 adversarial (NO-GO), then u 2 final (GO), then the merge,
# record GO/NO-GO per pass kind and the review seconds, the sum of each round's Timing line.
mk tm; STUB_REPLY=$'- [P1] (class: probe) blocker -- tm.txt:1 -- wrong -- cat tm.txt\nVERDICT: NO-GO' pass tm 1 adversarial; STUB_REPLY='VERDICT: GO' pass tm 2 final
# The stand-in Codex starts and ends in the same millisecond: give the two round files known spans (a fractional start, 90 s; 30 s).
BT=$COMMANDECK_WORKSPACES/tm/.claude/briefs/tm
sed 's/^Timing: .*/Timing: 2026-10-23T10:00:00.500Z 2026-10-23T10:01:30.900Z/' "$BT-r1-reports.md" > "$BT-r1.new" && mv "$BT-r1.new" "$BT-r1-reports.md"
sed 's/^Timing: .*/Timing: 2026-10-23T10:05:00Z 2026-10-23T10:05:30Z/' "$BT-r2-reports.md" > "$BT-r2.new" && mv "$BT-r2.new" "$BT-r2-reports.md"
SECS=120
check "the merge of tm ends 0" 0 "$(merge tm)"
check "its unit ledger row counts GO and NO-GO per pass kind" '{"adversarial":{"go":0,"noGo":1},"final":{"go":1,"noGo":0}}' \
  "$(jq -sc 'map(select(.unit == "tm")) | .[0].passKinds' "$UL" 2>/dev/null)"
check "and holds the review seconds, the sum of the round files' Timing lines" "$SECS" \
  "$(jq -sc 'map(select(.unit == "tm")) | .[0].reviewSeconds' "$UL" 2>/dev/null)"
# A round file from before the Timing line leaves the seconds unknown (null, named in gaps), never 0.
mk to; go to; STUB_REPLY='VERDICT: GO' pass to 2 final
for f in "$COMMANDECK_WORKSPACES"/to/.claude/briefs/to-r[0-9]*-reports.md; do grep -v '^Timing: ' "$f" > "$f.new" && mv "$f.new" "$f"; done
check "the merge of to ends 0" 0 "$(merge to)"
check "a unit whose round files have no Timing line has null review seconds, a named gap, and still its pass kinds" "null|true|{\"adversarial\":{\"go\":1,\"noGo\":0},\"final\":{\"go\":1,\"noGo\":0}}" \
  "$(jq -sr 'map(select(.unit == "to")) | .[0] | "\(.reviewSeconds)|\(.gaps | index("reviewSeconds") != null)|\(.passKinds | tojson)"' "$UL" 2>/dev/null)"

# Issue 239: the merge closes each issue the brief lists that its commit names, with the commit and the version; one
# the commit does not name stays open and is named. Issue 227: main-watch's item task about the unit's seat is
# closed by the merge, another unit's is left open.
mk w "feat(w): the unit (#5)"; printf '# w\n\n## The issues\n\n1. #5: one\n2. #6: two\n' > "$COMMANDECK_WORKSPACES/w/.claude/briefs/w.md"
# The work items are the list builder-launch.sh wrote to main's checkout at launch, never a parse of the brief.
issues() { mkdir -p "$REPO/.claude/briefs"; printf '%s\n' "$2" > "$REPO/.claude/briefs/$1-issues.json"; }
issues w '[5,6]'
printf 'handle=t_w\ntask=task_w\nunit=w\nrole=builder\nlaunched=%s\n' "$LA" > "$COMMANDECK_SCRATCH/seat-w-builder.txt"
mkdir -p "$COMMANDECK_SCRATCH/main-watch"
printf 'posted=1\ntask=task_item_w\n' > "$COMMANDECK_SCRATCH/main-watch/item-seat-t_w-task_w"
printf 'posted=1\ntask=task_item_o\n' > "$COMMANDECK_SCRATCH/main-watch/item-seat-t_o-task_o"
go w; : > "$TMP/gh-calls"; : > "$TMP/orca-calls"
check "a GO merge of w ends 0" 0 "$(merge w)"
check "the issue the commit names is closed once, naming the merge commit" 1 "$(grep -c "^issue close 5 --comment Fixed in $(git -C "$REPO" rev-parse --short=8 HEAD)" "$TMP/gh-calls")"
check "the issue the commit does not name stays open, and is named" "0 1" "$(grep -c '^issue close 6' "$TMP/gh-calls") $(grep -c 'left open: #6' "$TMP/out")"
check "the unit's item task is completed, another unit's is not" "1 0" \
  "$(grep -c 'task-update --id task_item_w --status completed' "$TMP/orca-calls") $(grep -c 'task_item_o' "$TMP/orca-calls")"
# Issue 323: red proofs are retired. w's commit carried no Mutation-verified: line and merged above; a branch that
# still carries an old one merges too, and the squash message no longer carries it along.
mk mv $'feat(mv): the unit\n\nMutation-verified: an old note from before issue 323'; go mv
check "a commit with an old Mutation-verified: line merges, and the merge message drops it" "0 0" \
  "$(merge mv) $(git -C "$REPO" log -1 --format=%B | grep -c 'Mutation-verified')"
# A "Closes: #n" line in the batch brief is carried into the merge commit and closes that issue, though no commit
# subject names it.
mk cl "feat(cl): the unit"
# Brief text closes only the unit's work items, the list fixed at launch: a quoted example (a ``` block inside a
# ```` block, a quoted "The issues" list, an HTML comment) or a plain line naming another issue closes nothing, however
# it is quoted; each is left to close by hand (NOT CLOSED, code 3). "Close as shipped" closes a work item the commit
# does not name.
printf '# cl\n\n## The issues\n\n1. #8: one\n2. #9: two\n3. #10: three\n\nCloses: #8, #9, #13\n\n## Close as shipped\n\n- #10\n\n## Examples\n\n````markdown\n```\nCloses: #11\n```\n## The issues\n1. #11: example only\n## Close as shipped\n- #12\n````\n\n<!--\nCloses: #14\n-->\n' > "$COMMANDECK_WORKSPACES/cl/.claude/briefs/cl.md"
issues cl '[8,9,10]'
go cl; : > "$TMP/gh-calls"
check "a brief's Closes: line gives the merge commit a Closes line per work item it names" "3 Closes #8 Closes #9" \
  "$(merge cl) $(git -C "$REPO" log -1 --format=%b | grep . | paste -sd' ' -)"
check "and the merge closes each of those issues, and the work item under Close as shipped" "1 1 1" \
  "$(grep -c '^issue close 8 ' "$TMP/gh-calls") $(grep -c '^issue close 9 ' "$TMP/gh-calls") $(grep -c '^issue close 10 ' "$TMP/gh-calls")"
check "an issue that is not a work item is not closed, quoted or not, and is named and left to close by hand" "0 0 0 0 #11 #12 #13 #14 11 12 13 14" \
  "$(for n in 11 12 13 14; do grep -c "^issue close $n " "$TMP/gh-calls"; done | paste -sd' ' -) $(grep '^step 4 issues: not closed:' "$TMP/out" | grep -oE '#[0-9]+' | sort | paste -sd' ' -) $(grep -oE '^NOT CLOSED: gh issue close [0-9]+' "$TMP/out" | grep -oE '[0-9]+$' | sort -n | paste -sd' ' -)"
# One retry path, whatever the state came from: #20 is named by the commit, a Closes: line and Close as shipped, and
# is on the launch list. Between two dry runs one piece of that state is removed; #20 is still closed, or, with no
# launch list, still printed as a by-hand close: never dropped without a word.
mk ct "feat(ct): the unit (#20)"; CTB=$COMMANDECK_WORKSPACES/ct/.claude/briefs/ct.md
ctb() { printf '# ct\n\n## The issues\n\n1. #20: one\n%s' "$1" > "$CTB"; }
ctb $'\nCloses: #20\n\n## Close as shipped\n\n- #20\n'; issues ct '[20]'; go ct
tick() { merge ct --dry-run > /dev/null; { grep -c '^step 4 issues: would close #20$' "$TMP/out"; grep -c '^NOT CLOSED: gh issue close 20 ' "$TMP/out"; } | paste -sd: -; }
T0=$(tick); ctb $'\n## Close as shipped\n\n- #20\n'; T1=$(tick); ctb $'\nCloses: #20\n'; T2=$(tick); ctb ''; T3=$(tick)
rm "$REPO/.claude/briefs/ct-issues.json"; T4=$(tick); ctb $'\nCloses: #20\n\n## Close as shipped\n\n- #20\n'; T5=$(tick)
check "with each piece of state removed, #20 is still closed, or with no launch list left to close by hand" \
  "1:0 1:0 1:0 1:0 0:1 0:1" "$T0 $T1 $T2 $T3 $T4 $T5"
check "and a merge with no launch list says why it closes nothing itself" 1 "$(grep -c '^step 4 issues: no work-item list at .*ct-issues.json' "$TMP/out")"
# A dry run closes nothing; a close GitHub refuses ends the merge with code 3 and the command that closes it.
mk x "feat(x): the unit (#7)"; printf '# x\n\n## The issues\n\n1. #7: one\n' > "$COMMANDECK_WORKSPACES/x/.claude/briefs/x.md"; issues x '[7]'
go x; : > "$TMP/gh-calls"
check "a dry run closes no issue, and says which it would" "0 0 1" "$(merge x --dry-run) $(grep -c . "$TMP/gh-calls") $(grep -c 'would close #7' "$TMP/out")"
: > "$TMP/gh-fails"
check "a close GitHub refuses ends the merge with code 3 and a NOT CLOSED line" "3 1" "$(merge x) $(grep -c '^NOT CLOSED: gh issue close 7 --comment' "$TMP/out")"
rm -f "$TMP/gh-fails"
# Issue 221: the squash message is checked before anything is merged: a home path, and a word of the project's own list.
mk y "feat(y): read /home/someone/x"; go y; H0=$(git -C "$REPO" rev-parse HEAD)
check "a message holding a home path is refused, naming the line, and main is unchanged" "1 1 $H0" \
  "$(merge y) $(grep -c '^FAILED step 4 message: .*/home/someone/x' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
mkdir -p "$REPO/ci"; cp "$REAL/ci/leak-test.sh" "$REPO/ci/"; printf '# words\n(?i)zebraword\n' > "$REPO/ci/leak-words.txt"
mk z "feat(z): the Zebraword unit"; go z
check "a message holding a word of the project's ci/leak-words.txt is refused, and main is unchanged" "1 1 $H0" \
  "$(merge z) $(grep -c '^FAILED step 4 message: .*Zebraword' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
echo 'feat(q): clean' > "$TMP/clean-msg"
check "ci/leak-test.sh --text on a clean file exits 0" 0 "$(bash "$REPO/ci/leak-test.sh" --text "$TMP/clean-msg" >/dev/null 2>&1; echo $?)"
# r1: a scanner that supports --text and fails is no screening: the merge is refused, not let through.
printf '# words\n(?i)zebraword\n(\n' > "$REPO/ci/leak-words.txt"
check "a word list the scanner cannot run refuses the merge, and main is unchanged" "1 1 $H0" \
  "$(merge z) $(grep -c '^FAILED step 4 message: .*could not run' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
# A project's leak-test.sh from before --text cannot read the message: said, and the merge goes on.
git -C "$REAL_SRC" show b15d8ee:ci/leak-test.sh > "$REPO/ci/leak-test.sh"
check "a leak-test.sh older than --text: the merge goes on and says the word list was not applied" "0 1" \
  "$(merge z) $(grep -c 'the project.s word list was not applied' "$TMP/out")"
rm -rf "$REPO/ci"
# Issue 230: run in main's foreground (a Claude session), the merge returns at once with its log and pid; the merge
# then completes detached and its result reaches main as a question.
mk d; go d
OUT=$(cd "$REPO" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 bash "$MERGE" d </dev/null 2>&1); RC=$?
PID=$(sed -n 's/.*running detached as pid \([0-9]*\);.*/\1/p' <<<"$OUT")
check "in main's foreground the merge returns 0 at once, naming its log" "0 1" "$RC $(grep -c "watch $COMMANDECK_SCRATCH/merge-d.log" <<<"$OUT")"
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "the detached merge completed, and main heard its result" "1 1" \
  "$(grep -c '^DONE unit=d merged=local' "$COMMANDECK_SCRATCH/merge-d.log" 2>/dev/null) $(cat "$TMP/orca-calls" "$COMMANDECK_SCRATCH"/queue/*.jsonl 2>/dev/null | grep -c 'merge-unit-local.sh d: exit 0')"
# r1: the queue waits on each merge, so in main's foreground the queue detaches itself and runs its merges in its
# own foreground: a detached merge's exit 0 is no merge.
OUT=$(cd "$REPO" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 bash "$REAL/scripts/merge-queue.sh" no-such-a no-such-b </dev/null 2>&1); RC=$?
PID=$(sed -n 's/.*running detached as pid \([0-9]*\);.*/\1/p' <<<"$OUT")
check "in main's foreground the merge queue returns 0 at once, naming its log" "0 1" "$RC $(grep -c "watch $COMMANDECK_SCRATCH/merge-queue.log" <<<"$OUT")"
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "the detached queue stopped at the first unit that did not merge, and never says all merged" "1 0" \
  "$(grep -c 'STOPPED at no-such-a (not merged)' "$COMMANDECK_SCRATCH/merge-queue.log" 2>/dev/null) $(grep -c 'all 2 unit' "$COMMANDECK_SCRATCH/merge-queue.log" 2>/dev/null)"

# Issue 265: a behaviour the owner has an open question on is theirs to settle: while a question naming the unit is
# open, or the ledger cannot be read, the merge (a dry run too) is refused; once it is answered the unit merges.
# Another unit's name that only contains this one's does not hold it.
mk hu; go hu; LED=$REPO/.claude/metrics/decisions.jsonl; mkdir -p "${LED%/*}"; H0=$(git -C "$REPO" rev-parse HEAD)
row() { jq -nc --arg id "$1" --arg a "$2" '{id: $id, askedAt: "1999-01-01T00:00:00Z", question: "Keep the old path for hu?", proposedDefault: "keep",
  source: "builder hu", answeredAt: (if $a == "" then null else "1999-01-02T00:00:00Z" end), answer: (if $a == "" then null else $a end)}'; }
row q-1999-01-01-a "" > "$LED"; jq -c '.id = "q-1999-01-01-b" | .question = "Rename hux?" | .source = "builder hux"' <<<"$(row x "")" >> "$LED"
check "an open question naming the unit refuses the merge and a dry run, naming its id, and main is unchanged" "1 1 1 $H0" \
  "$(merge hu --dry-run) $(merge hu) $(grep -c '^FAILED step 1 preconditions: an open question to the owner names hu.*q-1999-01-01-a' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
check "the other unit's open question is not named" 0 "$(grep -c 'q-1999-01-01-b' "$TMP/out")"
cp "$LED" "$TMP/led"; echo '{"id":' >> "$LED"
check "a ledger that cannot be read refuses the merge, saying so" "1 1" "$(merge hu) $(grep -c 'decisions ledger could not be read' "$TMP/out")"
cp "$TMP/led" "$LED"; row q-1999-01-01-a keep >> "$LED"; jq -c '.question = "Rename hux?" | .source = "builder hux" | .id = "q-1999-01-01-b"' <<<"$(row x "")" >> "$LED"
# Issue 301: the merge's lock went to every child of the merge, so a test command that left a process behind held
# it after the merge ended, and every later merge waited on it.
jq --arg c "sleep 30 >/dev/null 2>&1 & echo \$! > $TMP/left" '.testCommand = $c' <<<'{}' > "$REPO/.claude/commandeck.json"
check "answered, the unit merges" 0 "$(merge hu)"
check "a process the merge's test command left behind does not hold the merge lock" 0 \
  "$([ -s "$TMP/left" ] && kill -0 "$(cat "$TMP/left")" && flock -n "$REPO/.git/merge-unit-local.lock" true; echo $?)"
kill "$(cat "$TMP/left" 2>/dev/null)" 2>/dev/null; rm -f "$REPO/.claude/commandeck.json"
# A question the owner is asked while the merge runs its check holds the unit too: the ledger is read again just
# before the commit, so it merges only once that one is answered.
mk hw; go hw; H0=$(git -C "$REPO" rev-parse HEAD)
jq --arg c "jq -nc '{id: \"q-1999-01-01-w\", askedAt: \"1999-01-01T00:00:00Z\", question: \"Keep the old path for hw?\", proposedDefault: \"keep\", source: \"builder hw\", answeredAt: null, answer: null}' >> $LED" \
  '.testCommand = $c' <<<'{}' > "$REPO/.claude/commandeck.json"
check "a question opened during the check refuses the merge, naming it, and main is unchanged" "1 1 $H0" \
  "$(merge hw) $(grep -c '^FAILED step 4 merge: an open question to the owner names hw.*q-1999-01-01-w' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
rm -f "$REPO/.claude/commandeck.json"
# With no ledger yet the lock still holds through the commit: decision.sh add starts the file and takes it exclusive,
# so a lock on anything else let a question be asked between the last read and the commit. The hook tries that lock.
mk hz; go hz; rm -f "$LED"; mkdir -p "$TMP/hooks"; git -C "$REPO" config core.hooksPath "$TMP/hooks"
printf '#!/bin/sh\nflock -n -x %s true; echo $? > %s\n' "$LED" "$TMP/hooklock" > "$TMP/hooks/pre-commit"; chmod +x "$TMP/hooks/pre-commit"
check "with no ledger, the merge commits while a question cannot be added" "0 1" "$(merge hz) $(cat "$TMP/hooklock" 2>/dev/null)"
git -C "$REPO" config core.hooksPath /dev/null
# Issue 254: main-watch merges a unit by the sha its gate passed. A tip that moved since is not what the gate passed.
mk au; GATED=$(git -C "$COMMANDECK_WORKSPACES/au" rev-parse HEAD); H0=$(git -C "$REPO" rev-parse HEAD)
echo more > "$COMMANDECK_WORKSPACES/au/au2.txt"; git -C "$COMMANDECK_WORKSPACES/au" add au2.txt; git -C "$COMMANDECK_WORKSPACES/au" commit -qm "feat(au): more"
check "--auto with a tip that moved since the gate is refused, naming it, and main is unchanged" "1 1 $H0" \
  "$(merge au --auto "$GATED") $(grep -c "^FAILED step 1 preconditions: --auto $GATED: the branch tip is now" "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
# The gate's other conditions are asked again under the merge lock: a hold or an owner question added while the merge
# waited refuses --auto with main unchanged.
tipof() { git -C "$COMMANDECK_WORKSPACES/$1" rev-parse HEAD; }
mk ah; go ah; echo 'Merge: hold' >> "$COMMANDECK_WORKSPACES/ah/.claude/briefs/ah.md"
check "--auto on a unit held since its gate passed is refused, and main is unchanged" "1 1 $H0" \
  "$(merge ah --auto "$(tipof ah)") $(grep -c '^FAILED step 1 preconditions: --auto: held since the gate passed: Merge: hold in its brief' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
mk ao; go ao; mkdir -p "$REPO/.claude/metrics"
# A whole ledger row (the ledger refuses any other) whose text names no unit, so only --auto's gate reads it.
echo '{"id":"ao-q1","askedAt":"1999-01-01T00:00:00Z","question":"which?","proposedDefault":"a","source":"builder x","answeredAt":null,"answer":null}' >> "$REPO/.claude/metrics/decisions.jsonl"
check "--auto on a unit with an owner question opened since its gate is refused, and main is unchanged" "1 1 $H0" \
  "$(merge ao --auto "$(tipof ao)") $(grep -c '^FAILED step 1 preconditions: --auto: held since the gate passed: open owner decision ao-q1' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
# The same holds, added while the merge runs its check, are read again just before the commit: entry alone missed them.
mk late; go late
jq --arg c "echo 'Merge: hold' >> '$COMMANDECK_WORKSPACES/late/.claude/briefs/late.md'" '.testCommand = $c' <<<'{}' > "$REPO/.claude/commandeck.json"
check "--auto on a unit held during its check is refused before the commit, and main is unchanged" "1 1 $H0" \
  "$(merge late --auto "$(tipof late)") $(grep -c '^FAILED step 4 merge: --auto: held since the gate passed: Merge: hold in its brief' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
mk laq; go laq
jq --arg c "echo '{\"id\":\"laq-q1\",\"askedAt\":\"1999-01-01T00:00:00Z\",\"question\":\"which?\",\"proposedDefault\":\"a\",\"source\":\"builder x\",\"answeredAt\":null,\"answer\":null}' >> '$REPO/.claude/metrics/decisions.jsonl'" \
  '.testCommand = $c' <<<'{}' > "$REPO/.claude/commandeck.json"
check "--auto on a unit with an owner question opened during its check is refused before the commit, and main is unchanged" "1 1 $H0" \
  "$(merge laq --auto "$(tipof laq)") $(grep -c '^FAILED step 4 merge: --auto: held since the gate passed: open owner decision laq-q1' "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
rm -f "$REPO/.claude/commandeck.json"
# Issue 255: the brief's Post-merge lines run once the merge stands, only the ones on the list. The plugin is a copy,
# so its dashboard.sh and main-watch.sh are stubs; the stub dashboard has a login and answers --login-check.
PLUG_COPY=$TMP/plugin; mkdir -p "$PLUG_COPY"; cp -R "$REAL/scripts" "$REAL/hooks" "$REAL/config" "$REAL/.claude-plugin" "$PLUG_COPY/"
printf '#!/usr/bin/env bash\necho "dashboard.sh $*" >> "%s/post-calls"\n[ "$1" != --login-check ] || [ -e "%s/password-set" ] || { echo "the dashboard login is on and no password is set" >&2; exit 1; }\n' "$TMP" "$TMP" > "$PLUG_COPY/scripts/dashboard.sh"
printf '#!/usr/bin/env bash\necho "main-watch.sh $*" >> "%s/post-calls"\n' "$TMP" > "$PLUG_COPY/scripts/main-watch.sh"
MERGE=$PLUG_COPY/scripts/merge-unit-local.sh
post() { printf '# %s\n\n## Post-merge\n\n%s\n' "$1" "$2" > "$COMMANDECK_WORKSPACES/$1/.claude/briefs/$1.md"; }
row() { jq -c --arg u "$1" 'select(.unit == $u) | .post' "$HOME/.commandeck/builds/proj.jsonl" 2>/dev/null; }
mk pa; post pa $'- `dashboard.sh --install`\n- rm -rf ~/x'; go pa; : > "$TMP/post-calls"
check "a dashboard step with a login and no password, and an off-list line: the merge stands and ends 5" "5 1" \
  "$(merge pa) $(git -C "$REPO" log --format=%s | grep -c '^feat(pa)')"
check "the refused dashboard step never ran --install, and the off-list line is named" "0 1" \
  "$(grep -c -- 'dashboard.sh --install' "$TMP/post-calls") $(grep -c 'not on the post-merge list (exit 5): rm -rf ~/x' "$TMP/out")"
check "the finished-builds row holds each step's exit" '[{"step":"dashboard.sh --install","exit":5},{"step":"rm -rf ~/x","exit":5}]' "$(row pa)"
mk pb; post pb $'dashboard.sh --install\nmain-watch.sh --install'; go pb; : > "$TMP/post-calls"; : > "$TMP/password-set"
check "with a password set both steps run, the merge ends 0 and the row shows exit 0 for each" \
  '0 2 [{"step":"dashboard.sh --install","exit":0},{"step":"main-watch.sh --install","exit":0}]' \
  "$(merge pb) $(grep -cE '^(dashboard|main-watch).sh --install$' "$TMP/post-calls") $(row pb)"
check "one line says what each step did" 1 "$(grep -c '^step 4 post-merge: dashboard.sh --install exit 0; main-watch.sh --install exit 0 (logs ' "$TMP/out")"
# Issue 310: the script takes its repository from the checkout it lives in, not from where it is run. Here the project's
# main checkout holds the plugin (tracked, on main); the merge is run from another repository's root, then by a relative
# path from the checkout's parent folder. An installed copy (no git behind it) keeps the cwd, as every case above.
cp -R "$PLUG_COPY/scripts" "$PLUG_COPY/hooks" "$PLUG_COPY/config" "$PLUG_COPY/.claude-plugin" "$REPO/"
git -C "$REPO" add -A scripts hooks config .claude-plugin; git -C "$REPO" commit -qm "main: the plugin"
git init -q -b main "$TMP/other"; git -C "$TMP/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m other
mk s1; go s1; echo s1 > "$TMP/unit"
check "run from another repository's root, the checkout's own script merges its unit" "0 1" \
  "$(cd "$TMP/other" && bash "$REPO/scripts/merge-unit-local.sh" s1 > "$TMP/out" 2>&1; echo $?) $(git -C "$REPO" log --format=%s | grep -c '^feat(s1)')"
mk s2; go s2; echo s2 > "$TMP/unit"
check "run by a relative path from the checkout's parent folder, the unit merges" "0 1" \
  "$(cd "$TMP" && bash "proj/scripts/merge-unit-local.sh" s2 > "$TMP/out" 2>&1; echo $?) $(git -C "$REPO" log --format=%s | grep -c '^feat(s2)')"

# Issue 352: the proof is one predicate, run at the end of step 1 and again at step 3. A unit whose last pass is narrowed
# (its GO merges nothing) is refused at step 1, before the rebase rewrites the branch: main moved, so a rebase would have.
NW=$COMMANDECK_WORKSPACES/nr
mk nr; STUB_REPLY=$'- [P2] (class: probe) a thing -- nr.txt:1 -- say it plainly -- cat nr.txt\nVERDICT: NO-GO' pass nr 1 adversarial
echo more >> "$NW/nr.txt"; git -C "$NW" commit -qam "fix: the finding"; STUB_REPLY='VERDICT: GO' pass nr 2 review
echo moved > "$REPO/moved1.txt"; git -C "$REPO" add moved1.txt; git -C "$REPO" commit -qm "main moves"
NRH=$(git -C "$NW" rev-parse HEAD); HM=$(git -C "$REPO" rev-parse HEAD)
check "a narrowed-only proof is refused at step 1, the branch is not rebased, and main is unchanged" "1 1 0 $NRH $HM" \
  "$(merge nr) $(grep -c '^FAILED step 1 proof: .*the branch is untouched' "$TMP/out") $(grep -c '^STEP 2 rebase' "$TMP/out") $(git -C "$NW" rev-parse HEAD) $(git -C "$REPO" rev-parse HEAD)"
# A reviewed commit followed by a commit that only rebuilds a generated file keeps the review, before and after the rebase.
printf '{"generatedFiles": ["gen.txt"]}\n' > "$REPO/.claude/commandeck.json"
mk gt; go gt; echo gen > "$COMMANDECK_WORKSPACES/gt/gen.txt"; git -C "$COMMANDECK_WORKSPACES/gt" add gen.txt; git -C "$COMMANDECK_WORKSPACES/gt" commit -qm "chore: rebuild generated"
echo moved > "$REPO/moved2.txt"; git -C "$REPO" add moved2.txt; git -C "$REPO" commit -qm "main moves again"
check "a reviewed commit followed by a generated-only commit passes both proof steps and merges" "0 1 1" \
  "$(merge gt) $(grep -c '^DONE unit=gt merged=local' "$TMP/out") $(grep -c 'rule: generated-only tail' "$TMP/out")"
rm -f "$REPO/.claude/commandeck.json"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
