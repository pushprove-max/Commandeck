#!/usr/bin/env bash
# cos-check.test.sh -- cos-check.sh, the relay pane's 50-minute timer check (issue 290), with stubbed orca-ide and
# ps and the sleep cut to 0. The relay is deaf when a watcher dies, and a message the inbox watcher never handled
# was lost without a trace. What this pins: a watcher that is down is named and a live one is not; a message to the
# pane from the last 2 hours that the inbox watcher handled (cos-watch-inbox.sh appends its id to the seen-ids file)
# is not missed, and one it never handled is; held FYI notes print once and are cleared; the owner's quiet minutes
# come from the rulings log; the line is appended to the timer log.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
mkdir -p "$T/bin" "$T/home" "$T/scratch"
git init -q -b main "$T/p"
# ps -p <pid> answers from $T/pids ("<pid> <command>").
cat > "$T/bin/ps" <<EOF
#!/usr/bin/env bash
p=\${@: -1}; sed -n "s/^\$p //p" "$T/pids"
EOF
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ) OLD=$(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-3H +%Y-%m-%dT%H:%M:%SZ)
# Orca's inbox: m1 and m2 to the relay now, m3 to it three hours ago, m4 to another pane.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "orchestration run-list") echo '{"ok":true,"result":{"runs":[{"id":"run_1","coordinator_handle":"term_main"}]}}' ;;
  "orchestration inbox") jq -n --arg now "$NOW" --arg old "$OLD" '{ok: true, result: {messages: [
    {id: "m1", sequence: 1, run_id: "run_1", from_handle: "term_main", to_handle: "term_cos", subject: "s1", body: "b", type: "status", created_at: \$now},
    {id: "m2", sequence: 2, run_id: "run_1", from_handle: "term_main", to_handle: "term_cos", subject: "s2", body: "b", type: "status", created_at: \$now},
    {id: "m3", sequence: 3, run_id: "run_1", from_handle: "term_main", to_handle: "term_cos", subject: "s3", body: "b", type: "status", created_at: \$old},
    {id: "m4", sequence: 4, run_id: "run_1", from_handle: "term_main", to_handle: "term_x", subject: "s4", body: "b", type: "status", created_at: \$now}]}}' ;;
esac
EOF
chmod +x "$T/bin/ps" "$T/bin/orca-ide"
E=(env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/scratch" PATH="$T/bin:$PATH"
  COMMANDECK_RULING_LOG="$T/rulings.jsonl" COMMANDECK_COS_CHECK_SLEEP=0)
KEY=$(cd "$T/p" && "${E[@]}" bash -c '. "$1/hooks/lib/project.sh"; pp_cos_key; printf %s "$COS_KEY"' _ "$REAL")
mkdir -p "${KEY%/*}"
cc() { (cd "$T/p" && "${E[@]}" bash "$REAL/scripts/cos-check.sh" term_cos 2>&1); }

# The inbox watcher handles m1 (a message to the pane always counts) and records its id.
printf '0 enc\n' > "$KEY.inbox-seq"
(cd "$T/p" && "${E[@]}" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-inbox.sh" term_cos >/dev/null 2>&1)
check "the inbox watcher appends each message it handled to the seen-ids file" "m1 m2 m3" "$(paste -sd' ' - < "$KEY.inbox-seen-ids" 2>/dev/null)"
printf 'm1\n' > "$KEY.inbox-seen-ids"
# decisions and limit live; inbox and alerts down (alerts' pid now runs something else).
echo 11 > "$KEY.cos-watch-decisions.pid"; echo 12 > "$KEY.cos-watch-limit.pid"; echo 13 > "$KEY.cos-watch-alerts.pid"
printf '11 bash /x/scripts/cos-watch-decisions.sh\n12 /x/scripts/cos-watch-limit.sh\n13 vim /x/scripts/cos-watch-alerts.sh\n' > "$T/pids"
printf '9 enc\n2026 [from main] "FYI one" | "x"\n\n' > "$KEY.inbox-seq"
# The rulings log is shared with every worker pane: a worker's prompt (main-watch's Signal WARM to a Builder) is not
# the owner, who types only in main and in the Chief-of-Staff worktree. It read "owner quiet 0 min" here.
jq -cn --arg u "$(date -u -d '-45 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-45M +%Y-%m-%dT%H:%M:%SZ)" --arg c "$T/p" '{utc: $u, cwd: $c, source: "prompt"}' > "$T/rulings.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/p" '{utc: $u, cwd: $c, source: "prompt", void: true}' >> "$T/rulings.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/home/orca/workspaces/p/unit-a" '{utc: $u, cwd: $c, source: "prompt", answer: "Signal WARM: keep-alive while you wait. Reply with one . and end your turn."}' >> "$T/rulings.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/p/.claude/worktrees/agent-1" '{utc: $u, cwd: $c, source: "prompt", answer: "a subagent worktree nested in main"}' >> "$T/rulings.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/p-other" '{utc: $u, cwd: $c, source: "prompt", answer: "a pane outside main sharing its path prefix"}' >> "$T/rulings.jsonl"
check "the fixture holds each worker row at now, by its cwd" "$T/home/orca/workspaces/p/unit-a $T/p/.claude/worktrees/agent-1 $T/p-other" \
  "$(jq -r --arg u "$NOW" 'select(.utc == $u and .void != true) | .cwd' "$T/rulings.jsonl" | paste -sd' ' -)"
OUT=$(cc); RC=$?; LINE=$(tail -1 <<<"$OUT")
check "exit 0 with one line last: inbox and alerts down, m2 missed (m1 seen, m3 too old, m4 not this pane's), owner quiet 45 min" \
  "0:cos-check: watchers down: inbox alerts | missed messages: 1 | held FYI notes: 1 (above, now cleared) | owner quiet 45 min" "$RC:$LINE"
check "the held FYI note is printed above the line" 1 "$(grep -c 'FYI one' <<<"$OUT")"
check "and cleared: the inbox state keeps its place line only" "9 enc" "$(cat "$KEY.inbox-seq")"
check "the line is appended to the timer log" 1 "$(grep -c 'missed messages: 1' "$KEY.cos-check.log")"
check "its own pid is recorded for the Stop hook" 1 "$([ -s "$KEY.cos-check.pid" ] && echo 1)"
LINE=$(cc | tail -1)
check "a second check prints no FYI note" "held FYI notes: 0" "$(grep -o 'held FYI notes: [0-9]*' <<<"$LINE")"
# Workspaces set inside main: a Builder there is a worker, not the owner; the Chief-of-Staff worktree there is the owner.
jq -cn --arg u "$NOW" --arg c "$T/p/workspaces/unit-a" '{utc: $u, cwd: $c, source: "prompt", answer: "Signal WARM"}' >> "$T/rulings.jsonl"
check "a Builder in workspaces nested in main is not owner activity" "owner quiet 45 min" \
  "$(cd "$T/p" && "${E[@]}" COMMANDECK_WORKSPACES="$T/p/workspaces" bash "$REAL/scripts/cos-check.sh" term_cos 2>&1 | tail -1 | grep -o 'owner quiet.*')"
jq -cn --arg u "$NOW" --arg c "$T/p/workspaces/Chief-of-Staff" '{utc: $u, cwd: $c, source: "prompt", answer: "go"}' >> "$T/rulings.jsonl"
check "and the Chief-of-Staff worktree in those workspaces is" "owner quiet 0 min" \
  "$(cd "$T/p" && "${E[@]}" COMMANDECK_WORKSPACES="$T/p/workspaces" bash "$REAL/scripts/cos-check.sh" term_cos 2>&1 | tail -1 | grep -o 'owner quiet.*')"
jq -cn --arg u "$NOW" --arg c "$T/home/orca/workspaces/p/Chief-of-Staff/sub" '{utc: $u, cwd: $c, source: "prompt", answer: "go"}' >> "$T/rulings.jsonl"
check "a subfolder of the Chief-of-Staff worktree is not owner activity (only its root is)" "owner quiet 45 min" "$(cc | tail -1 | grep -o 'owner quiet.*')"
jq -cn --arg u "$NOW" --arg c "$T/home/orca/workspaces/p/Chief-of-Staff" '{utc: $u, cwd: $c, source: "prompt", answer: "go"}' >> "$T/rulings.jsonl"
check "the owner typing in the Chief-of-Staff worktree is owner activity" "owner quiet 0 min" "$(cc | tail -1 | grep -o 'owner quiet.*')"
# The relay reads the last 600 characters of the output: notes past that go to a file the line names, never lost.
{ echo '9 enc'; for i in $(seq 1 100); do echo "2026 [from main] \"FYI note $i\" | \"x\""; done; } > "$KEY.inbox-seq"
OUT=$(cc); LINE=$(tail -1 <<<"$OUT"); F=$(sed -n 's/.*whole text: \([^)]*\)).*/\1/p' <<<"$LINE")
check "100 held notes: the output stays within 600 characters and names the file" "yes 100" \
  "$([ "${#OUT}" -le 600 ] && echo yes) $(grep -o 'held FYI notes: [0-9]*' <<<"$LINE" | grep -o '[0-9]*$')"
check "the file holds every note, the first one too, and the state is cleared" "100 1 9 enc" \
  "$(grep -c 'FYI note' "$F" 2>/dev/null) $(grep -c '"FYI note 1"' "$F" 2>/dev/null) $(cat "$KEY.inbox-seq")"
# Pass 25: the archive was named for the epoch second only, so a second check in the same second emptied the first's
# archive and deleted it, and the first line's pointer named a lost file. date +%s is pinned to one second here.
printf '#!/usr/bin/env bash\n[ "$1" = +%%s ] && [ -e "%s/same-second" ] && { echo 1700000000; exit; }\nexec "%s" "$@"\n' "$T" "$(command -v date)" > "$T/bin/date"; chmod +x "$T/bin/date"; touch "$T/same-second"
{ echo '9 enc'; for i in $(seq 1 100); do echo "2026 [from main] \"FYI note $i\" | \"x\""; done; } > "$KEY.inbox-seq"
F=$(cc | tail -1 | sed -n 's/.*whole text: \([^)]*\)).*/\1/p'); cc >/dev/null; rm "$T/same-second"
check "a second check in the same second keeps the first check's archive whole" 100 "$(grep -c 'FYI note' "$F" 2>/dev/null)"
printf '9 pending\nsome batch\n' > "$KEY.inbox-seq"; cc >/dev/null
check "a batch saved for the pane and not yet shown is the inbox watcher's, never cleared here" "9 pending some batch" "$(paste -sd' ' - < "$KEY.inbox-seq")"
# Pass r2: workspaces set to main's parent excluded main itself as a worker checkout, so the owner read as quiet.
# A worker there is a sibling of main; main stays the owner's.
jq -cn --arg u "$(date -u -d '-45 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-45M +%Y-%m-%dT%H:%M:%SZ)" --arg c "$T/p" '{utc: $u, cwd: $c, source: "prompt"}' > "$T/rul-parent.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/unit-a" '{utc: $u, cwd: $c, source: "prompt", answer: "Signal WARM"}' >> "$T/rul-parent.jsonl"
qp() { (cd "$T/p" && "${E[@]}" COMMANDECK_WORKSPACES="$T" COMMANDECK_RULING_LOG="$T/rul-parent.jsonl" bash "$REAL/scripts/cos-check.sh" term_cos 2>&1 | tail -1 | grep -o 'owner quiet.*'); }
check "workspaces holding main: a Builder beside main is not owner activity" "owner quiet 45 min" "$(qp)"
jq -cn --arg u "$NOW" --arg c "$T/p/src" '{utc: $u, cwd: $c, source: "prompt", answer: "go"}' >> "$T/rul-parent.jsonl"
check "a subfolder of main is not owner activity (only main's root is)" "owner quiet 45 min" "$(qp)"
jq -cn --arg u "$NOW" --arg c "$T/p" '{utc: $u, cwd: $c, source: "prompt", answer: "go"}' >> "$T/rul-parent.jsonl"
check "and the owner typing in main is" "owner quiet 0 min" "$(qp)"
# Pass r3: the resolver keeps inner // and /./ in main and workspaces, and the selector compared raw paths, so a Builder
# read as the owner ("owner quiet 0 min"). A row is the owner's only when its cwd, after pnorm, is main or the
# Chief-of-Staff worktree exactly: every spelling of main, workspaces and cwd is tested here.
jq -cn --arg u "$(date -u -d '-45 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-45M +%Y-%m-%dT%H:%M:%SZ)" --arg c "$T/p" '{utc: $u, cwd: $c, source: "prompt"}' > "$T/rul-sp.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/p/workspaces/unit-a" '{utc: $u, cwd: $c, source: "prompt", answer: "Signal WARM"}' >> "$T/rul-sp.jsonl"
jq -cn --arg u "$NOW" --arg c "$T//p/./workspaces//unit-b/" '{utc: $u, cwd: $c, source: "prompt", answer: "Signal WARM"}' >> "$T/rul-sp.jsonl"
qs() { (cd "$T/p" && "${E[@]}" COMMANDECK_MAIN="$1" COMMANDECK_WORKSPACES="$2" COMMANDECK_RULING_LOG="$T/rul-sp.jsonl" bash "$REAL/scripts/cos-check.sh" term_cos 2>&1 | tail -1 | grep -o 'owner quiet.*'); }
for m in "$T/p" "$T//p" "$T/./p/"; do for w in "$T/p/workspaces" "$T/p//workspaces" "$T/p/./workspaces"; do
  check "main $m, workspaces $w: Builders in any spelling are not owner activity" "owner quiet 45 min" "$(qs "$m" "$w")"
done; done
cp "$T/rul-sp.jsonl" "$T/rul-sp-workers.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/p//workspaces/./Chief-of-Staff/" '{utc: $u, cwd: $c, source: "prompt", answer: "go"}' >> "$T/rul-sp.jsonl"
check "the Chief-of-Staff worktree spelled with // and /./ is owner activity" "owner quiet 0 min" "$(qs "$T//p" "$T/p/./workspaces")"
cp "$T/rul-sp-workers.jsonl" "$T/rul-sp.jsonl"
jq -cn --arg u "$NOW" --arg c "$T/./p//" '{utc: $u, cwd: $c, source: "prompt", answer: "go"}' >> "$T/rul-sp.jsonl"
check "main spelled with /./ and // is owner activity" "owner quiet 0 min" "$(qs "$T/p" "$T/p//workspaces")"
# Two ticks on one log: between them the owner's row goes and workspaces is respelled; the second tick reads the log
# alone (no state kept between runs), so the Builders still never read as the owner.
cp "$T/rul-sp-workers.jsonl" "$T/rul-sp.jsonl"
check "tick 1: owner 45 min ago, Builders now" "owner quiet 45 min" "$(qs "$T/p" "$T/p//workspaces")"
grep -v "\"cwd\":\"$T/p\"," "$T/rul-sp-workers.jsonl" > "$T/rul-sp.jsonl"
check "tick 2: the owner's row removed, workspaces respelled: Builders alone read unknown" "owner quiet unknown" "$(qs "$T/p" "$T/p/./workspaces")"
# Issue 309: main given by a link, the owner's prompt logged under the folder the link points to (/private/tmp for /tmp).
ln -s "$T/p" "$T/plink"
jq -cn --arg u "$NOW" --arg c "$T/p" '{utc: $u, cwd: $c, source: "prompt"}' > "$T/rul-link.jsonl"
check "owner quiet reads a ruling logged under /private/tmp spelling" "owner quiet 0 min" \
  "$(cd "$T/p" && "${E[@]}" COMMANDECK_MAIN="$T/plink" COMMANDECK_RULING_LOG="$T/rul-link.jsonl" bash "$REAL/scripts/cos-check.sh" term_cos 2>&1 | tail -1 | grep -o 'owner quiet.*')"
# Issue 319: with every watcher up, nothing missed and no held note, a wake has nothing for the owner: the line says to
# end the turn silently, so the relay does not spend a reply on a clean check.
printf '11 bash /x/scripts/cos-watch-decisions.sh\n12 /x/scripts/cos-watch-limit.sh\n13 /x/scripts/cos-watch-alerts.sh\n14 /x/scripts/cos-watch-inbox.sh\n' > "$T/pids"
echo 14 > "$KEY.cos-watch-inbox.pid"
printf 'm1\nm2\n' > "$KEY.inbox-seen-ids"; printf '9 enc\n' > "$KEY.inbox-seq"
check "nothing down, missed or held: prints the end-silently line only" "cos-check: nothing for the owner: end silently; re-arm" "$(cc)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
