#!/usr/bin/env bash
# unit-drive-watch.test.sh -- issue 651 (CE4): the unit driver watches a launched unit to its merge, stops once on what
# main must act on, and attaches to a live Builder instead of launching another. Apart from unit-drive.test.sh, which
# is near its 500-line cap. The driver's `run` is called directly, its owner file written first, so no service manager
# is stood in for. seat.sh, builder-launch.sh, to-main.sh, read-verdict.sh, builder-codex-pass.sh and orca-ide are
# stubs; plan-tier.sh is real. orca-ide lists the panes in $T/live (`<handle> <worktree>`) and the messages in $T/inbox;
# read-verdict.sh counts each read in $T/polls-<unit> and prints $T/turn-<unit> (a running turn when absent); --verify
# prints $T/verify-<unit> (a proof when absent).
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
UD=$T/plug/scripts/unit-drive.sh S=$T/plug/scripts CALLS=$T/calls
mkdir -p "$T/b" "$HOME/.claude" "$HOME/.commandeck/builds" "$SCR/main-watch"; : > "$CALLS"; : > "$T/to-main"; : > "$T/live"; : > "$T/verify"
cp -R "$REAL/.claude-plugin" "$T/plug/"
echo '{"ok":true,"result":{"messages":[]}}' > "$T/inbox"
jq -n '{pluginConfigs: {"commandeck@commandeck": {options: {planJudgeSolAgent: "claude", planJudgeSolEnabled: false, planJudgeOpusEnabled: false}}}}' > "$HOME/.claude/settings.json"
cat > "$S/seat.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"; p=$WS/\$3/.claude/plans/\$3.md; mkdir -p "\${p%/*}"; printf 'plan of %s\n' "\$3" > "\$p"
printf 'role=%s\nlaunched=1\nverdict=PLAN-DONE\n' "\$2" > "$SCR/seat-\$3-\$2.txt"
EOF
cat > "$S/builder-launch.sh" <<EOF
#!/usr/bin/env bash
echo "launch \$*" >> "$CALLS"; [ ! -e "$T/brec-\$2" ] || cp "$T/brec-\$2" "$SCR/seat-\$2-builder.txt"
EOF
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "terminal list"*) jq -Rn '{ok: true, result: {terminals: [inputs | split(" ") | {handle: .[0], worktreePath: .[1], connected: true}]}}' "$T/live" ;;
  "orchestration inbox"*) cat "$T/inbox" ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$T/to-main" > "$S/to-main.sh"
printf '#!/usr/bin/env bash\necho x >> "%s/polls-${3##*/}"\ncat "%s/turn-${3##*/}" 2>/dev/null || echo state=running\n' "$T" "$T" > "$S/read-verdict.sh"
printf '#!/usr/bin/env bash\necho "$3" >> "%s/verify"\ncat "%s/verify-$3" 2>/dev/null || echo "Builder proof: $3-r1-reports.md"\n' "$T" "$T" > "$S/builder-codex-pass.sh"
chmod +x "$T/bin/orca-ide" "$S"/*.sh
drv() { # <unit> -- the driver's run, as its service runs it: its exit in $T/rc-<unit>, its stderr in $T/log-<unit>
  echo "drive-$1-1" > "$SCR/drive-$1.owner"
  (cd "$P" && "${E[@]}" COMMANDECK_LOOP_POLL_SECONDS=1 bash "$UD" run --owner "drive-$1-1" "$1" "$T/b/author-$1.md" "$T/b/judge.md" "$T/b/$1-batch.md" </dev/null >/dev/null 2>>"$T/log-$1")
  echo $? > "$T/rc-$1"
}
mkb() { printf 'Build %s.\n\nOrder: build issue 1\n\n## The issues\n\n1. #1: add the thing\n' "$1" > "$T/b/$1-batch.md"; printf 'Order: build issue 1\nLaunch: new unit %s\n' "$1" > "$T/b/author-$1.md"; echo 'judge it' > "$T/b/judge.md"; }
wrec() { # <unit> [file] -- the Builder seat record its launch leaves, launched now; in [file], the one builder-launch.sh copies
  printf 'handle=term_w%s\nrole=builder\nunit=%s\nlaunched=%s\nphase=dispatched\n' "$1" "$1" "$(date +%s)" > "${2:-$SCR/seat-$1-builder.txt}"; }
live() { echo "term_w$1 $WS/$1" >> "$T/live"; }
quiet() { printf 'state=complete\noutstanding=\n' > "$T/turn-$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
merged() { jq -cn --arg p "$P" --arg u "$1" --arg at "$2" '{main: $p, unit: $u, how: "merged", at: $at, sha: "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"}' >> "$HOME/.commandeck/builds/proj.jsonl"; }
mrec() { # <unit> <tip> -- main-watch's record of a merge job that tried <tip> and exited 1, its log naming the refusal
  printf '%s\n%s\n' "$2" "$SCR/main-watch/mergejob-$1.log" > "$SCR/main-watch/merge-$1"
  echo "merge-queue: $1 refused: the gate is red" > "$SCR/main-watch/mergejob-$1.log"; echo 1 > "$SCR/main-watch/mergejob-$1.rc"; }
calls() { grep -c "^$1" "$CALLS" || true; }
stopped() { cat "$SCR/unit-loop-$1.done" 2>/dev/null | grep -c "^STOP unit=$1 stage=$2: $3"; }
stops() { cat "$SCR/unit-loop-$1.done" 2>/dev/null | grep -c '^STOP'; }
polls() { cat "$T/polls-$1" 2>/dev/null | grep -c x; }
until_() { local i; for i in $(seq 100); do eval "$1" && return 0; sleep 0.2; done; return 1; }

# A unit whose Builder pane is not live (its record names a pane that is gone) runs its plan stages and launches; then it
# is watched, and its merge row, written after the launch, ends it DONE with exit 0. Catches an attach to a gone pane,
# and the driver that exited at "launched its Builder" while the unit idled (before #651).
# Pass 18 (completed-driver-restart): the args file its start wrote is gone after the DONE exit, so recover-stalls.sh's R4
# never restarts a unit that ended DONE as if its driver had crashed.
u=wd; mkb $u; wrec $u; wrec $u "$T/brec-$u"; M=$(now); merged $u "$M"; printf 'a\nj\nb\ndrive-%s-1\n' "$u" > "$SCR/drive-$u.args"; drv $u
check "no live Builder runs plan stages first" "author=1 launch=1 attached=0" \
  "author=$(calls "run plan-author $u") launch=$(calls "launch --from-plan $u") attached=$(grep -c ' attached to ' "$T/log-$u")"
check "merged unit ends DONE and leaves no args file to restart from" "rc=0 DONE unit=$u stage=merge: merged into main at $M args=0" \
  "rc=$(cat "$T/rc-$u") $(tail -1 "$T/log-$u") args=$(ls "$SCR/drive-$u.args" 2>/dev/null | grep -c .)"

# A live Builder pane is attached to, the driver run twice: no plan stage and no builder-launch.sh call either time.
# Catches a re-run that launches a second Builder over a live one. Each run ends at the idle stop.
u=wa; wrec $u; live $u; quiet $u; drv $u; drv $u
check "live Builder is attached, never relaunched" "launch=0 author=0 attached=2" \
  "launch=$(calls "launch --from-plan $u") author=$(calls "run plan-author $u") attached=$(grep -cx "unit-drive: $u attached to its Builder term_w$u" "$T/log-$u")"

# A Builder quiet 3 polls in a row, with no merge and no question, is one idle stop, not one at the first quiet read.
# Catches a unit left idle with no one told, and a stop on one quiet read between two turns.
u=wi; wrec $u; live $u; quiet $u; drv $u
check "idle Builder stops after three polls" "stop=1 polls=3" \
  "stop=$(stopped $u idle "the Builder is idle and nothing merges; next: bash .*unit-drive.sh start $u ") polls=$(polls $u)"

# A question the Builder asked main after its launch, unanswered, is one stop naming it. Catches a question no one sees.
u=wq; wrec $u; live $u
jq -n --arg h "term_w$u" --arg t "$(now)" '{ok: true, result: {messages: [{id: "m1", type: "question", thread_id: null, from_handle: $h, created_at: $t, subject: "which table?"}]}}' > "$T/inbox"; drv $u
check "open Builder question stops" "1" "$(stopped $u builder-question "the Builder asked: which table?; next: answer it with decision.sh, then ")"

# --verify's REVIEW STOP is one stop line, told to main once, naming the decision to answer. Catches a REVIEW STOP no
# one is told about.
u=wr; wrec $u; live $u
echo "REFUSED: REVIEW STOP: $u-r7-reports.md holds a P0 or P1 at pass 7 or later (pass 7 on record); decision review-stop-$u-7; it waits for the owner's answer" > "$T/verify-$u"; drv $u
check "REVIEW STOP stops with one line" "lines=1 stop=1 told=1" \
  "lines=$(grep -c . "$SCR/unit-loop-$u.done") stop=$(stopped $u review "REFUSED: REVIEW STOP: $u-r7-reports.md .*; next: answer decision review-stop-$u-7, then ") told=$(grep -c "unit-drive: $u stopped at review" "$T/to-main")"

# A fix round (a new commit: a new pp_gate_key) runs --verify again and ends nothing; the merge after it ends DONE.
# Catches a driver that stops after the Builder's first round.
u=wf; planned $u; wrec $u; live $u; drv $u & D=$!; until_ "[ \$(grep -cx $u $T/verify) = 1 ]"
git -C "$WS/$u" commit -q --allow-empty -m 'fix round'; until_ "[ \$(grep -cx $u $T/verify) = 2 ]"; merged $u "$(now)"; wait $D
check "fix round does not end the driver" "verify=2 rc=0 stops=0" "verify=$(grep -cx $u "$T/verify") rc=$(cat "$T/rc-$u") stops=$(stops $u)"

# A merge main-watch ran on this HEAD after this launch and that exited non-zero is one stop naming the merge command.
# Catches a refused merge no one is told about.
u=wm; planned $u; wrec $u; live $u; mrec $u "$(git -C "$WS/$u" rev-parse HEAD)"; drv $u
check "refused merge stops with resume command" "1" "$(stopped $u merge "merge-queue: $u refused: the gate is red; next: bash .*merge-unit-local.sh $u, then bash .*unit-drive.sh start $u ")"

# A refusal of another generation is history: one whose job exited before this launch (an earlier build of a reopened
# unit), and one of a tip the Builder has since committed past. The driver polls on past both and ends at the merge.
u=wo1; planned $u; wrec $u; live $u; mrec $u "$(git -C "$WS/$u" rev-parse HEAD)"; touch -d "@$(($(date +%s) - 100))" "$SCR/main-watch/mergejob-$u.rc"
u=wo2; planned $u; wrec $u; live $u; mrec $u "$(git -C "$WS/$u" rev-parse HEAD)"; git -C "$WS/$u" commit -q --allow-empty -m newer
out=; for u in wo1 wo2; do drv $u & D=$!; until_ "[ \$(polls $u) -ge 2 ]"; merged $u "$(now)"; wait $D; out+="$(cat "$T/rc-$u"):$(stops $u) "; done
set -- $out
check "merge refusal of an older tip does not stop" "0:0" "$1"
check "merge refusal of an earlier attempted tip does not stop a newer HEAD" "0:0" "$2"

# A merged row from before this launch (a reopened unit's earlier build) is history: the driver polls on, and the row of
# this build ends it. Catches yesterday's merge ending today's driver.
u=we; wrec $u; live $u; merged $u 2000-01-01T00:00:00Z; drv $u & D=$!; until_ "[ \$(polls $u) -ge 2 ]"
out="running=$([ -e "$T/rc-$u" ] || echo yes)"; merged $u "$(now)"; wait $D
check "earlier merge of a reopened unit does not end the driver" "running=yes rc=0" "$out rc=$(cat "$T/rc-$u")"

# A squash merge: the row's sha is a new commit, no descendant of the Builder's, and cleanup removed the worktree, so the
# row's time alone binds it. Catches a driver that waits for the Builder's commit on main, which never comes.
u=wsq; wrec $u; live $u; merged $u "$(now)"; drv $u
check "squash merge row ends the driver with no ancestor commit" "rc=0 done=1" "rc=$(cat "$T/rc-$u") done=$(grep -c "^DONE unit=$u stage=merge: " "$T/log-$u")"

# The Builder's pane closes with no merge: one stop naming the relaunch. Catches a closed pane no one is told about.
u=wc; wrec $u; live $u; drv $u & D=$!; until_ "[ \$(polls $u) -ge 1 ]"
grep -v "^term_w$u " "$T/live" > "$T/live.t"; mv "$T/live.t" "$T/live"; wait $D
check "closed Builder pane stops" "1" "$(stopped $u builder "its pane term_w$u closed before the merge; next: bash .*builder-launch.sh --from-plan $u $T/b/$u-batch.md\$")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
