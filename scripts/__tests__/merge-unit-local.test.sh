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
check "a GO merge of u ends 0" 0 "$(merge u)"
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
check "a GO merge of v ends 0" 0 "$(merge v)"
check "a refused ledger writer prints its line, and the merge of v still ends 0" "1 1 1" \
  "$(grep -c '^DONE unit=v merged=local' "$TMP/out") $(grep -c "^unit-ledger: cannot write $UL" "$TMP/out") $(grep -c "no unit ledger row written for v (ignored)" "$TMP/out")"
rmdir "$UL"; mv "$TMP/ul.kept" "$UL"
check "a Builder's ledger row sums the tokens of every session its record names" "300:20" \
  "$(jq -r 'select(.unit == "v" and .role == "builder") | "\(.tokens.input):\(.tokens.output)"' "$REPO/.claude/metrics/seat-events.jsonl" 2>/dev/null)"
# A closing pass that leaves P2s only merges under the P2 tail rule: its row says so, never CONVERGED-GO.
mk t; go t; STUB_REPLY=$'- [P2] A small thing -- t.txt:1 -- say it plainly\nVERDICT: NO-GO' pass t 2 final
# (It exits 4: with no gh here, its open P2 cannot be filed.)
check "a P2-tail merge of t merges" 1 "$(merge t >/dev/null; grep -c '^DONE unit=t merged=local' "$TMP/out")"
check "its unit ledger row records the P2 tail, not a converged GO" "P2-TAIL|P2 tail|1|1" \
  "$(jq -sr 'map(select(.unit == "t")) | .[0] | "\(.verdict)|\(.mergeRule)|\(.goRounds)|\(.noGoRounds)"' "$UL" 2>/dev/null)"

# Issue 239: the merge closes each issue the brief lists that its commit names, with the commit and the version; one
# the commit does not name stays open and is named. Issue 227: main-watch's item task about the unit's seat is
# closed by the merge, another unit's is left open.
mk w "feat(w): the unit (#5)"; printf '# w\n\n## The issues\n\n1. #5: one\n2. #6: two\n' > "$COMMANDECK_WORKSPACES/w/.claude/briefs/w.md"
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
# A dry run closes nothing; a close GitHub refuses ends the merge with code 3 and the command that closes it.
mk x "feat(x): the unit (#7)"; printf '# x\n\n## The issues\n\n1. #7: one\n' > "$COMMANDECK_WORKSPACES/x/.claude/briefs/x.md"
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
git -C "$REAL" show b15d8ee:ci/leak-test.sh > "$REPO/ci/leak-test.sh"
check "a leak-test.sh older than --text: the merge goes on and says the word list was not applied" "0 1" \
  "$(merge z) $(grep -c 'the project.s word list was not applied' "$TMP/out")"
rm -rf "$REPO/ci"
# Issue 230: run in main's foreground (a Claude session), the merge returns at once with its log and pid; the merge
# then completes detached and its result reaches main as a status message.
mk d; go d
OUT=$(cd "$REPO" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 bash "$MERGE" d </dev/null 2>&1); RC=$?
PID=$(sed -n 's/.*running detached, pid \([0-9]*\);.*/\1/p' <<<"$OUT")
check "in main's foreground the merge returns 0 at once, naming its log" "0 1" "$RC $(grep -c "log $COMMANDECK_SCRATCH/merge-d.log" <<<"$OUT")"
[ -z "$PID" ] || tail --pid="$PID" -f /dev/null
check "the detached merge completed, and main heard its result" "1 1" \
  "$(grep -c '^DONE unit=d merged=local' "$COMMANDECK_SCRATCH/merge-d.log" 2>/dev/null) $(cat "$TMP/orca-calls" "$COMMANDECK_SCRATCH"/queue/*.jsonl 2>/dev/null | grep -c 'merge-unit-local.sh d: exit 0')"
# r1: the queue waits on each merge, so in main's foreground the queue detaches itself and runs its merges in its
# own foreground: a detached merge's exit 0 is no merge.
OUT=$(cd "$REPO" && env -u COMMANDECK_FOREGROUND CLAUDECODE=1 bash "$REAL/scripts/merge-queue.sh" no-such-a no-such-b </dev/null 2>&1); RC=$?
PID=$(sed -n 's/.*running detached, pid \([0-9]*\);.*/\1/p' <<<"$OUT")
check "in main's foreground the merge queue returns 0 at once, naming its log" "0 1" "$RC $(grep -c "log $COMMANDECK_SCRATCH/merge-queue.log" <<<"$OUT")"
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
# waited, or a proof whose rule is not a GO, refuses --auto with main unchanged.
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
mk at; go at; STUB_REPLY=$'- [P2] (class: probe) a tail finding -- at.txt:1 -- it reads wrong -- cat at.txt\nVERDICT: NO-GO' pass at 2 final
check "--auto on a P2 tail is refused as the owner's call, and main is unchanged" "1 1 $H0" \
  "$(merge at --auto "$(tipof at)") $(grep -c "^FAILED step 3 proof: --auto merges a GO only, and the proof's rule is P2 tail" "$TMP/out") $(git -C "$REPO" rev-parse HEAD)"
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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
