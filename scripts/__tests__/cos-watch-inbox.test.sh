#!/usr/bin/env bash
# cos-watch-inbox.test.sh -- Orca's inbox is one list for the whole machine.
# The relay pane speaks for one project's owner: a message sent in another
# project's run, even one addressed to "the owner", is not this pane's to
# relay. What this pins: only the project's own run reaches the pane, and a
# project with no run recorded relays nothing. A report from the orchestrator's
# own pane (the run's coordinator, whatever it is called) reaches the pane
# even when its subject names nobody, and an "FYI" message is held in a file
# and shown with the next message that wakes the pane, once.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

mkdir -p "$T/bin" "$T/home/.commandeck/chief-of-staff" "$T/scratch"
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
cat > "$T/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
# The run's record names the orchestrator's pane. NOCOORD: the record names
# none. NOLIST: Orca does not answer the question at all.
case "$*" in *run-list*) [ -z "${NOLIST:-}" ] || exit 1
  [ -z "${NOCOORD:-}" ] || { echo '{"result": {"runs": [{"id": "run_mine"}]}}'; exit; }
  echo '{"result": {"runs": [
  {"id": "run_mine", "coordinator_handle": "term_main"}, {"id": "run_other", "coordinator_handle": "term_else"}]}}'; exit ;; esac
# MANY: a long inbox, of which Orca returns the newest --limit rows.
[ -z "${MANY:-}" ] || { jq --argjson n "$4" '.result.messages |= (sort_by(.sequence) | .[-$n:])' "$MANY"; exit; }
echo '{"result": {"messages": [
  {"sequence": 5, "run_id": "run_mine", "from_handle": "term_main", "type": "status", "subject": "cos: build is green", "body": "MINE", "created_at": "t1"},
  {"sequence": 6, "run_id": "run_other", "from_handle": "term_else", "type": "status", "subject": "cos: tell the owner", "body": "FOREIGN", "created_at": "t2"}]}}'
STUB
chmod +x "$T/bin/orca-ide"
# Each poll starts from sequence 0 again; the notes the state file holds stay.
STATE=$T/home/.commandeck/chief-of-staff/proj.inbox-seq
poll() { (cd "$T/proj" && PATH="$T/bin:$PATH" HOME="$T/home" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_WATCH_ONCE=1 \
    bash "$ROOT/scripts/cos-watch-inbox.sh" term_cos 2>&1); }
watch() { { echo 0; tail -n +2 "$STATE" 2>/dev/null; } > "$STATE.t"; mv "$STATE.t" "$STATE"; poll; }

echo run_mine > "$T/scratch/current-run"
OUT=$(watch); RC=$?
check "a message in the project's run wakes the relay" "0 1" "$RC $(grep -c 'MINE' <<<"$OUT")"
check "another project's message is not relayed" 0 "$(grep -c 'FOREIGN' <<<"$OUT")"
# More than one page of machine-wide traffic between two polls: the message
# behind the page is the owner's all the same.
jq -n '{result: {messages: [range(1; 71) | {sequence: ., run_id: "run_else", from_handle: "term_x", type: "status", subject: "noise", body: "n", created_at: "t"}
  | if .sequence == 3 then . + {run_id: "run_mine", subject: "cos: the early one", body: "EARLY"} else . end]}}' > "$T/many.json"
OUT=$(MANY=$T/many.json watch)
check "a message more than a page behind the newest is still relayed" 1 "$(grep -c EARLY <<<"$OUT")"

# msgs <file> <from> <run> <type> <subject> <body> ...: an inbox of those rows, sequence 1 up. An empty type is a record with none.
msgs() { local f=$1; shift
  jq -n '$ARGS.positional as $a | [range(0; $a | length; 5) | $a[.:. + 5]] | to_entries | {result: {messages: map({sequence: (.key + 1), created_at: "t",
    from_handle: .value[0], run_id: .value[1], type: (if .value[2] == "" then null else .value[2] end), subject: .value[3], body: .value[4]})}}' --args "$@" > "$f"; }
msgs "$T/orch.json" \
  term_main run_mine status "Batch f merged, two findings open" PLAIN \
  term_main run_mine question "main-watch: 2 builders idle" MWATCH \
  term_main run_mine question "main-watch: seat implementer on unit-x finished (term_w)" MWSEAT \
  term_main run_mine question "heads-up: unit x stalled" HEADSUP \
  term_main run_mine question "seat implementer unit-x: GO" SEATVERDICT \
  term_main run_mine question "drive unit-x: FYI round 2 started" DRIVERNOTE \
  term_main run_mine status "answer from main" ANSWERTOWORKER \
  term_main run_mine status "main: merged unit x" MAINLINE \
  term_main run_mine status "worktree review flagged unit-x" REVIEWFLAG \
  term_main run_mine "" "Decision needed on unit y" NOTYPE \
  term_main run_mine worker_done "unit x done" WORKERDONE \
  term_work run_mine status "progress on unit x" WORKERNOTE \
  term_else run_other status "Batch f merged over there" OTHERRUN \
  term_cos run_mine status "note to self" OWNNOTE
OUT=$(MANY=$T/orch.json watch); RC=$?
check "a report from the orchestrator's pane wakes the relay, whatever its subject" "0 1" "$RC $(grep -c PLAIN <<<"$OUT")"
# The helper scripts send under the orchestrator's handle too: one case per subject shape they send.
for auto in MWATCH MWSEAT HEADSUP SEATVERDICT DRIVERNOTE ANSWERTOWORKER MAINLINE; do
  check "automatic traffic under the orchestrator's handle does not wake the relay: $auto" 0 "$(grep -c "$auto" <<<"$OUT")"
done
# A send with no --type is stored as `status` (Orca's message table defaults the
# column to it), so the orchestrator's plain hand send and the build review's
# flagged message, sent from the orchestrator's pane with no type, both arrive.
# Orca's own reader shows a record with no type as status; so does this one.
check "the build review's flagged message, sent with no type from the orchestrator's pane, wakes the relay" 1 "$(grep -c REVIEWFLAG <<<"$OUT")"
check "an orchestrator message whose record carries no type wakes the relay" 1 "$(grep -c NOTYPE <<<"$OUT")"
check "worker reports, another run and the pane's own notes do not either" 0 "$(grep -c 'WORKERDONE\|WORKERNOTE\|OTHERRUN\|OWNNOTE' <<<"$OUT")"
# The orchestrator is known by the run's record alone: when Orca does not name
# one, the subject rule still relays, and nothing else does.
msgs "$T/nocoord.json" term_main run_mine status "Batch f merged" PLAIN term_main run_mine status "cos: decide" NAMED
OUT=$(NOCOORD=1 MANY=$T/nocoord.json watch)
check "with no orchestrator pane on record the subject rule alone decides" "0 1" "$(grep -c PLAIN <<<"$OUT") $(grep -c NAMED <<<"$OUT")"
# Orca not answering is not "no orchestrator": a note judged without the
# record would be dropped for good, so the poll waits and reads it again.
SEQ=$T/home/.commandeck/chief-of-staff/proj.inbox-seq
OUT=$(NOLIST=1 MANY=$T/nocoord.json watch); RC=$?
check "while Orca does not name the runs, nothing is printed and nothing is marked read" "1 0 0" "$RC $(grep -c 'PLAIN\|NAMED' <<<"$OUT") $(cat "$SEQ")"
OUT=$(MANY=$T/nocoord.json watch)
check "the next poll that gets an answer prints the orchestrator's note" "1 1" "$(grep -c PLAIN <<<"$OUT") $(grep -c NAMED <<<"$OUT")"

# An FYI is not worth a wake: each wake replays the pane's whole context.
# The notes are held in the same file as the place read up to, after its first
# line: one file, so the notes and the place can only move together.
msgs "$T/fyi1.json" term_main run_mine status "FYI: batch g merged" NOTEONE term_work run_mine status "fyi for the owner: disk at 80%" NOTETWO
OUT=$(MANY=$T/fyi1.json watch); RC=$?
check "an FYI message does not wake the pane" "1 0" "$RC $(grep -c 'NOTEONE\|NOTETWO' <<<"$OUT")"
check "the FYI messages are held, after the place read up to" "2 2" "$(grep -c 'NOTEONE\|NOTETWO' "$SEQ" 2>/dev/null) $(head -1 "$SEQ")"
msgs "$T/fyi2.json" term_main run_mine status "cos: a decision is needed" WAKEONE
OUT=$(MANY=$T/fyi2.json watch); RC=$?
check "the held FYI messages are printed with the next waking message" "0 1 2" "$RC $(grep -c WAKEONE <<<"$OUT") $(grep -c 'NOTEONE\|NOTETWO' <<<"$OUT")"
OUT=$(MANY=$T/fyi2.json watch)
check "a held FYI message is printed once only" "1 0" "$(grep -c WAKEONE <<<"$OUT") $(grep -c 'NOTEONE\|NOTETWO' <<<"$OUT")"

# A note that could not be saved is not marked read: the batch is read again.
msgs "$T/fyi3.json" term_main run_mine status "FYI: batch h merged" NOTETHREE term_main run_mine status "cos: another decision" WAKETWO
mkdir "$SEQ.new"
OUT=$(MANY=$T/fyi3.json watch 2>/dev/null); RC=$?
check "an FYI that cannot be saved marks nothing read and prints nothing" "1 0 0" "$RC $(grep -c 'NOTETHREE\|WAKETWO' <<<"$OUT") $(cat "$SEQ")"
rmdir "$SEQ.new"
OUT=$(MANY=$T/fyi3.json watch); RC=$?
check "once it can be saved, the same batch is printed whole" "0 1 1" "$RC $(grep -c WAKETWO <<<"$OUT") $(grep -c NOTETHREE <<<"$OUT")"

# A write the disk refuses only when the file is closed (a full disk) is a failed save too.
# The file size limit stands in for the full disk: one block (512 or 1024 bytes), and the note is longer.
msgs "$T/fyi4.json" term_main run_mine status "FYI: a long note" "NOTEFOUR $(printf 'x%.0s' $(seq 3000))"
printf '0\nan earlier note EARLIERNOTE\n' > "$SEQ"; cp "$SEQ" "$T/fyi.before"
OUT=$( (ulimit -f 1; MANY=$T/fyi4.json watch) 2>/dev/null); RC=$?
check "an FYI the disk refuses at close marks nothing read and prints nothing" "1 0 0" "$RC $(grep -c 'NOTEFOUR' <<<"$OUT") $(head -1 "$SEQ")"
# A save that fails part way must not leave a piece behind: the next poll would add the whole batch after it.
check "and the notes and the place are byte for byte what they were: both moved or neither" same "$(cmp -s "$SEQ" "$T/fyi.before" && echo same)"
OUT=$(MANY=$T/fyi4.json watch); RC=$?
check "the next poll holds the batch once, after the earlier note" "1 1 1 1" "$RC $(head -1 "$SEQ") $(grep -o NOTEFOUR "$SEQ" | wc -l | tr -d ' ') $(grep -c EARLIERNOTE "$SEQ")"

# Two pollers of one project at the same moment (a pane restarted while its old
# watcher still ran): one at a time, so no held note is lost and none is given twice.
msgs "$T/fyi5.json" term_main run_mine status "FYI: one" RACEONE term_main run_mine status "FYI: two" RACETWO
msgs "$T/fyi6.json" term_main run_mine status "FYI: one" RACEONE term_main run_mine status "FYI: two" RACETWO term_main run_mine status "FYI: three" RACETHREE term_main run_mine status "cos: decide" RACEWAKE
for round in 1 2 3; do
  echo 0 > "$SEQ"
  for i in 1 2 3 4 5 6; do MANY=$T/fyi5.json poll > "$T/race.$i" 2>&1 & done; wait
  check "six pollers at once hold each note once (round $round)" "1 1 2" "$(grep -c RACEONE "$SEQ") $(grep -c RACETWO "$SEQ") $(head -1 "$SEQ")"
  for i in 1 2 3 4 5 6; do MANY=$T/fyi6.json poll > "$T/race.$i" 2>&1 & done; wait
  check "and the next six deliver the waking message and every held note once between them (round $round)" "1 1 1 1" \
    "$(cat "$T"/race.* | grep -c RACEWAKE) $(cat "$T"/race.* | grep -c RACEONE) $(cat "$T"/race.* | grep -c RACETWO) $(cat "$T"/race.* | grep -c RACETHREE)"
  check "nothing is held after it (round $round)" "4" "$(cat "$SEQ")"
done
# The lock is the kernel's, on a file that stays: a poller that died left the
# file and holds nothing, so the inbox is never shut for good.
echo 0 > "$SEQ"; echo 999999 > "$SEQ.lock"
OUT=$(MANY=$T/fyi6.json poll); RC=$?
check "a lock file left by a dead poller does not hold the inbox" "0 1" "$RC $(grep -c RACEWAKE <<<"$OUT")"
# While a live poller holds the lock, a second one waits for it and then finds the batch delivered.
echo 0 > "$SEQ"
( exec 9>>"$SEQ.lock"; flock 9; sleep 2 ) & sleep 0.5
START=$SECONDS; OUT=$(MANY=$T/fyi6.json poll); RC=$?
check "a poller waits while another holds the lock, then delivers" "0 1 yes" "$RC $(grep -c RACEWAKE <<<"$OUT") $([ $((SECONDS - START)) -ge 1 ] && echo yes || echo no)"
wait

# A message counts as delivered when the pane has it. A batch is saved as
# pending before it is shown: output that fails (the pane's pipe is gone)
# loses nothing, and the next poll shows the batch, once.
printf '0\nHELDNOTE\n' > "$SEQ"; : > "$T/ro"
MANY=$T/fyi2.json poll 9<"$T/ro" >&9 2>/dev/null; RC=$?
check "output that fails is no delivery: the poll fails and the batch is kept as pending" "yes 1 1 1" "$([ "$RC" != 0 ] && echo yes || echo no) $(head -1 "$SEQ" | grep -c pending) $(grep -c WAKEONE "$SEQ") $(grep -c HELDNOTE "$SEQ")"
OUT=$(MANY=$T/fyi2.json poll); RC=$?
check "and the next poll shows the message and the held notes once" "0 1 1 1" "$RC $(grep -c WAKEONE <<<"$OUT") $(grep -c HELDNOTE <<<"$OUT") $(cat "$SEQ")"
OUT=$(MANY=$T/fyi2.json poll); RC=$?
check "and never again" "1 0" "$RC $(grep -c 'WAKEONE\|HELDNOTE' <<<"$OUT")"
# A pending batch waits for no new message, and a note that arrives meanwhile is not lost with it.
printf '0\nHELDNOTE\n' > "$SEQ"
MANY=$T/fyi2.json poll 9<"$T/ro" >&9 2>/dev/null
msgs "$T/fyi7.json" term_main run_mine status "cos: a decision is needed" WAKEONE term_main run_mine status "FYI: later" LATERNOTE
OUT=$(MANY=$T/fyi7.json poll); RC=$?
check "a note that arrives while a batch is pending is shown with it" "0 1 1 1" "$RC $(grep -c WAKEONE <<<"$OUT") $(grep -c HELDNOTE <<<"$OUT") $(grep -c LATERNOTE <<<"$OUT")"
# A pending batch is owed whatever the inbox holds now, an empty inbox included.
printf '1 pending\nPENDINGNOTE\n' > "$SEQ"; echo '{"result": {"messages": []}}' > "$T/none.json"
OUT=$(MANY=$T/none.json poll); RC=$?
check "a pending batch is shown when the inbox comes back empty" "0 1 1" "$RC $(grep -c PENDINGNOTE <<<"$OUT") $(cat "$SEQ")"
OUT=$(MANY=$T/none.json poll); RC=$?
check "and an empty inbox with nothing pending shows nothing and keeps the place" "1  1" "$RC $OUT $(cat "$SEQ")"

rm "$T/scratch/current-run"
OUT=$(watch); RC=$?
check "with no run recorded for the project, nothing is relayed" "1 0" "$RC $(grep -c 'MINE\|FOREIGN' <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
