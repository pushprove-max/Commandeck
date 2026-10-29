#!/usr/bin/env bash
# unit-drive.test.sh -- the unit driver carries a unit from tier to its Builder launch with no main turn between, refuses
# once before any seat, stops once per decision main owns, resumes without repeating a finished stage, and has one owner
# per unit. Seats are stubs that log their words and write the records seat.sh writes; plan-tier.sh, plan-check.sh and
# (in the first case) builder-launch.sh are real. The service manager is a launcher stub that runs the driver's `run`
# in the background, and a systemctl stub that answers is-active and list-units from files in $T.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
UD=$T/plug/scripts/unit-drive.sh CALLS=$T/calls
mkdir -p "$T/hs" "$T/b" "$HOME/.claude"; : > "$CALLS"; : > "$T/started"; : > "$T/to-main"; : > "$T/seats"
cp -R "$REAL/.claude-plugin" "$T/plug/"
cp "$T/plug/scripts/builder-launch.sh" "$T/plug/scripts/builder-launch.real.sh"
cat > "$T/plug/scripts/seat.sh" <<EOF
#!/usr/bin/env bash
echo "\$* DRIVER=\${COMMANDECK_DRIVER:-unset} BATCH=\${COMMANDECK_BATCH:-unset}" >> "$CALLS"
[ "\$1 \$2" != "launch builder" ] || { echo "launch builder \$3" >> "$T/seats"; exit 0; }
[ "\$1" = run ] || exit 0
role=\$2 unit=\$3 plan=$WS/\$3/.claude/plans/\$3.md
if [ "\$role" = plan-author ]; then
  [ -f "\$plan" ] || { mkdir -p "\$(dirname "\$plan")"; printf 'plan of %s\n%s\n' "\$unit" "$PSZ" > "\$plan"; }
  echo "snap \$unit launch=\$(grep -c '^Launch:' "\$COMMANDECK_BATCH") plan=\$(grep -c '^## Plan' "\$COMMANDECK_BATCH")" >> "$T/snap"
  v=PLAN-DONE
else v=\$(cat "$T/verdict-\$unit-\$role" 2>/dev/null || echo 'VERDICT: GO'); fi
printf 'role=%s\nlaunched=%s\nplan=%s\nplanhash=%s\nverdict=%s\ncollected=%s\n' "\$role" "\$((\$(wc -l < "$CALLS") + 100))" "\$plan" \
  "\$(sha256sum < "\$plan" | cut -d' ' -f1)" "\$v" "\$(date +%s)" > "$SCR/seat-\$unit-\$role.txt"
[ "\$v" = PLAN-DONE ] || [ "\$v" = 'VERDICT: GO' ]
EOF
cat > "$T/plug/scripts/builder-launch.sh" <<EOF
#!/usr/bin/env bash
echo "launch \$* DRIVER=\${COMMANDECK_DRIVER:-unset} BATCH=\${COMMANDECK_BATCH:-unset}" >> "$CALLS"
[ ! -e "$T/refuse-launch" ] || { echo "REFUSED: 3 Builders are running and the cap is 3" >&2; exit 2; }
[ ! -e "$T/real-launch" ] || exec bash "\$(dirname "\$0")/builder-launch.real.sh" "\$@"
EOF
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$T/to-main" > "$T/plug/scripts/to-main.sh"
chmod +x "$T/plug/scripts/"*.sh
# The service manager. launcher: a started `run` waits for $T/go while $T/gate exists; hold-start blocks the start inside
# its admission. systemctl: is-active answers from active-units (force-inactive and unknown-state override it; hold-active
# blocks the answer), list-units from $T/units.
cat > "$T/launcher" <<EOF
#!/usr/bin/env bash
envs=(); while [ \$# -gt 0 ]; do case \$1 in --unit=*) name=\${1#--unit=} ;; --setenv=*) envs+=("\${1#--setenv=}") ;; -p) shift ;; --*) ;; *) break ;; esac; shift; done
echo "\$name" >> "$T/started"
rm -f "$T/hs/\$name"
[ ! -e "$T/hold-start" ] || { touch "$T/in-start"; while [ -e "$T/hold-start" ]; do sleep 0.1; done; }
echo "\$name" >> "$T/active-units"
( while [ -e "$T/gate" ] && [ ! -e "$T/go" ]; do sleep 0.1; done
  # A service starts in \$HOME (launchd's WorkingDirectory, systemd's user default), never in the caller's checkout.
  cd "\$HOME" || exit 1
  env -i "\${envs[@]}" "\$@" >> "$T/hs/\$name.log" 2>&1; echo \$? > "$T/hs/\$name" ) </dev/null >/dev/null 2>&1 &
EOF
cat > "$T/bin/systemctl" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *is-active*) n=\${@: -1}
    if [ -e "$T/hold-active" ]; then touch "$T/in-active"; while [ -e "$T/hold-active" ]; do sleep 0.1; done; fi
    [ ! -e "$T/unknown-state" ] || { echo oops; exit 1; }
    [ -e "$T/force-inactive" ] || ! grep -qx "\$n" "$T/active-units" 2>/dev/null || { echo active; exit 0; }
    echo inactive; exit 3 ;;
  *list-units*) cat "$T/units" 2>/dev/null ;;
esac
EOF
chmod +x "$T/launcher" "$T/bin/systemctl"
opts() { jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: ({planJudgeSolAgent: "claude"} + $o)}}}' > "$HOME/.claude/settings.json"; }
opts '{}'
ud() { (cd "$P" && "${E[@]}" COMMANDECK_HOST_OS=Linux COMMANDECK_WAKE_LAUNCHER="$T/launcher" bash "$UD" "$@" </dev/null); }
mkb() { # <unit> [extra batch line] [no-order] -- a batch with no Launch line and no Plan section, and its two specs
  printf 'Build %s.\n\n%s\n\n## The issues\n\n1. #1: add the thing\n%s\n' "$1" "${3-Order: build issue 1}" "${2:-}" > "$T/b/$1-batch.md"
  printf 'Order: build issue 1\nLaunch: new unit %s\n' "$1" > "$T/b/author-$1.md"; echo 'judge it' > "$T/b/judge.md"
}
args() { echo "$1 $T/b/author-$1.md $T/b/judge.md $T/b/$1-batch.md"; }
waitrc() { local i; for i in $(seq 150); do [ -e "$T/hs/$1" ] && return 0; sleep 0.2; done; }
drive() { # <unit> -- start, then wait for the service it started; the start's code and stderr in $T/start-<unit>.*
  local before; before=$(($(wc -l < "$T/started")))
  ud start $(args "$1") > "$T/start-$1.out" 2> "$T/start-$1.err"; echo $? > "$T/start-$1.rc"
  [ "$(($(wc -l < "$T/started")))" -gt "$before" ] && waitrc "$(tail -1 "$T/started")"
  return 0
}
calls() { grep -c "^$1" "$CALLS" || true; }
done_of() { cat "$SCR/unit-loop-$1.done" 2>/dev/null; }


# The convergence case: the real launcher takes the driver's plan to main and opens the Builder, and the launch mark it
# writes lets main-watch settle the Builder's routine reports and merge on the closing GO, telling main only of the landing.
# The main-watch half runs in a subshell that sources only main-watch-merge-setup.sh (the fixtures share names).
u=dc; fpunit $u; touch "$T/real-launch"; mkb $u
ud start $u "$T/b/author-$u.md" "$T/b/judge.md" "$WS/$u/.claude/briefs/$u-batch.md" > "$T/start-$u.out" 2> "$T/start-$u.err"; echo $? > "$T/start-$u.rc"
waitrc "$(tail -1 "$T/started")"; rm -f "$T/real-launch"; MARK=$SCR/drive-$u.launched
MW=$(cd "$REAL" && ( . "$REAL/scripts/__tests__/fixtures/main-watch-merge-setup.sh"
  N=5000; unit dc; cp "$MARK" "$S/drive-dc.launched"; W=$T/ws/dc/.claude/briefs
  printf 'Pass: review\nVERDICT: NO-GO\n' > "$W/dc-r1-reports.md"; tick $N; printf 'Pass: final\nVERDICT: GO\n' > "$W/dc-r2-reports.md"; tick $((N + 60))
  said_done dc; tick $((N + 120)); jobwait dc; tick $((N + 180))
  echo "reports=$(posts 'main-watch: dc pass') landing=$(posts 'main-watch: dc merged into local main') all=$(grep -c . "$T/sends")" ) 2>&1 | tail -1)
check "the driver carries a unit from plan through a NO-GO, a fix round and a closing GO to the merge, main told only of the landing (issue 443)" \
  "0 1 1 1 1 1 told=0 reports=0 landing=1 all=1" \
  "$(cat "$T/start-$u.rc") $(grep -c "^run plan-author $u .*DRIVER=1 BATCH=$WS/$u/.claude/briefs/$u-batch.md\$" "$CALLS") $(calls "run plan-judge-sol $u") $(grep -c "^launch builder $u" "$T/seats") $(git -C "$P" log --format=%s main | grep -c "^plan($u): plan") $([ -s "$MARK" ] && echo 1 || echo 0) told=$(grep -c . "$T/to-main") $MW"

# A batch with no Launch line and no Plan section gets both before any seat; a batch with no Order line is refused once.
u=wl; mkb $u; cp "$T/b/$u-batch.md" "$T/b/$u.before"; ud start --dry-run $(args $u) > "$T/dry.out" 2>&1
out="dry=$(cmp -s "$T/b/$u-batch.md" "$T/b/$u.before" && echo same)$(grep -c '^would append' "$T/dry.out")"; drive $u
out+=" rc=$(cat "$T/start-$u.rc") snap=$(grep -c "^snap $u launch=1 plan=1\$" "$T/snap") launch=$(grep -cx "Launch: new unit $u" "$T/b/$u-batch.md") plan=$(grep -cx ".claude/plans/$u.md" "$T/b/$u-batch.md")"
u=wo; mkb $u '' ''; cp "$T/b/$u-batch.md" "$T/b/$u.before"; c0=$(wc -l < "$CALLS"); drive $u
out+=" order=$(cat "$T/start-$u.rc"):$(grep -c "has no 'Order:" "$T/start-$u.err"):$(cmp -s "$T/b/$u-batch.md" "$T/b/$u.before" && echo same):$(($(wc -l < "$CALLS") - c0))"
check "the driver writes a missing Launch line and Plan section into the batch before any stage (issue 443)" \
  "dry=same1 rc=0 snap=1 launch=1 plan=1 order=2:1:same:0" "$out"

# A judge NO-GO stops once, naming the fix; starting again with no rulings repeats no stage; rulings newer than the
# judge's record carry on to the launch; a refused launch is its own stop.
u=st; mkb $u; echo 'VERDICT: NO-GO' > "$T/verdict-$u-plan-judge-sol"; drive $u
out="stop=$(done_of $u | grep -c "^STOP unit=$u stage=judge: plan-judge-sol returned VERDICT: NO-GO on .*; next: main rules on the findings in .*$u-main-rulings.md, then bash .*unit-drive.sh start $u ") lines=$(done_of $u | grep -c .) told=$(grep -c "stopped at judge" "$T/to-main")"
drive $u; out+=" again=$(calls "run plan-author $u")$(calls "run plan-judge-sol $u") lines=$(done_of $u | grep -c .)"
mkdir -p "$P/.claude/briefs"; touch -t 200001010000 "$SCR/seat-$u-plan-judge-sol.txt"; echo 'Accepted F1.' > "$P/.claude/briefs/$u-main-rulings.md"; drive $u
out+=" ruled=$(calls "run plan-judge-sol $u")$(calls "run plan-author $u")$(calls "launch --from-plan $u") cleared=$([ -e "$SCR/unit-loop-$u.done" ] || echo gone)"
u=lr; mkb $u; touch "$T/refuse-launch"; drive $u; rm -f "$T/refuse-launch"
out+=" launchstop=$(done_of $u | grep -c "^STOP unit=$u stage=launch: builder-launch.sh refused: REFUSED: 3 Builders are running")"
check "the driver stops once, naming the fix, and a resume repeats no finished stage (issue 443)" \
  "stop=1 lines=1 told=1 again=11 lines=1 ruled=111 cleared=gone launchstop=1" "$out"

# Two starts overlap: the first is held inside its admission, the second must wait on the lock, then find the first
# running (its service listed) and be refused naming it, starting nothing.
u=ov; mkb $u; touch "$T/gate" "$T/hold-start"; : > "$T/started"
( ud start $(args $u) > "$T/A.out" 2> "$T/A.err"; echo $? > "$T/A.rc" ) & pa=$!
for _ in $(seq 100); do [ -e "$T/in-start" ] && break; sleep 0.1; done
( ud start $(args $u) > "$T/B.out" 2> "$T/B.err"; echo $? > "$T/B.rc" ) & pb=$!
sleep 1; rm -f "$T/hold-start"; wait $pa $pb; A=$(head -1 "$T/started"); touch "$T/go"; waitrc "$A"
check "two overlapping drive starts run one driver and the other refuses naming the owner (issue 443)" \
  "A=0 B=2 refused=1 started=1 launches=1" \
  "A=$(cat "$T/A.rc") B=$(cat "$T/B.rc") refused=$(grep -c "^REFUSED: $u is driven by $A\$" "$T/B.err") started=$(grep -c . "$T/started") launches=$(calls "launch --from-plan $u")"
rm -f "$T/gate" "$T/go" "$T/in-start" "$T/active-units"

# A starts and publishes its owner; its run has not begun, and the manager does not list it. B takes over while A's run
# is already waiting on the lock; A's run sees B's name (or none) and runs nothing. An owner whose state cannot be read is kept.
u=tk; mkb $u; touch "$T/gate" "$T/force-inactive"; : > "$T/started"; rm -f "$T/go"
ud start $(args $u) > "$T/A.out" 2> "$T/A.err"; A=$(tail -1 "$T/started")
touch "$T/hold-active"; ( ud start $(args $u) > "$T/B.out" 2> "$T/B.err"; echo $? > "$T/B.rc" ) & pb=$!
for _ in $(seq 100); do [ -e "$T/in-active" ] && break; sleep 0.1; done
touch "$T/go"; sleep 1.5; rm -f "$T/hold-active"; wait $pb; B=$(tail -1 "$T/started"); waitrc "$A"; waitrc "$B"
out="B=$(cat "$T/B.rc") started=$(grep -c . "$T/started") launches=$(calls "launch --from-plan $u") refusedA=$(grep -cE "^REFUSED: $u is driven by ($B|nobody)\$" "$T/hs/$A.log")"
rm -f "$T/gate" "$T/go" "$T/force-inactive" "$T/in-active"
u=tk2; mkb $u; echo "drive-$u-777" > "$SCR/drive-$u.owner"; touch "$T/unknown-state"; s0=$(grep -c . "$T/started"); ud start $(args $u) > "$T/C.out" 2> "$T/C.err"; rc=$?; rm -f "$T/unknown-state"
out+=" unknown=$rc:$(grep -c "^REFUSED: $u is driven by drive-$u-777 (its state cannot be read)\$" "$T/C.err"):$(($(grep -c . "$T/started") - s0)):$(cat "$SCR/drive-$u.owner")"
check "a takeover before the first run begins leaves one driver; an unknown-state owner is kept (issue 443)" \
  "B=0 started=2 launches=1 refusedA=1 unknown=2:1:0:drive-tk2-777" "$out"

# The seats the driver runs are the ones plan-tier prints, run in that order, none other.
seats() { echo "$(calls "run plan-author $1")$(calls "run plan-judge-sol $1")$(calls "run plan-judge-fable $1")$(calls "launch --from-plan $1")"; }
u=ss; mkb $u; drive $u; out="plus=$(seats $u)"
u=sp; mkb $u '2. tighten the login check'; drive $u; out+=" panel=$(seats $u)"
opts '{"planJudgeSolEnabled": false}'; u=sf; mkb $u; drive $u; out+=" solOff=$(seats $u)"
opts '{"planJudgeSolEnabled": false, "planJudgeFableEnabled": false}'; u=so; mkb $u; drive $u; out+=" onePlanner=$(seats $u)"
opts '{"planJudgeSolEnabled": "maybe"}'; u=sm; mkb $u; c0=$(wc -l < "$CALLS"); drive $u
out+=" refused=$(cat "$T/start-$u.rc"):$(done_of $u | grep -c "^STOP unit=$u stage=tier: plan-tier.sh refused (exit 2): REFUSED: /plugin config planJudgeSolEnabled"):$(($(wc -l < "$CALLS") - c0))"
check "the driver runs only the seats plan-tier prints: the Fable judge when Sol is off, no judge for One planner, a stop on a refused Enabled value (issue 443)" \
  "plus=1101 panel=1111 solOff=1011 onePlanner=1001 refused=0:1:0" "$out"

# No plan: the driver starts no seat and no Builder, and the one STOP line hands main the skip launch.
opts '{"planAuthorEnabled": false}'; u=np; mkb $u; c0=$(wc -l < "$CALLS"); t0=$(grep -c . "$T/to-main"); drive $u
check "on No plan the driver starts nothing and hands main --skip-plan (issue 443)" "0 1 1 1" \
  "$(($(wc -l < "$CALLS") - c0)) $(done_of $u | grep -c .) $(done_of $u | grep -c "^STOP unit=$u stage=tier: No plan; next: bash .*builder-launch.sh --skip-plan --reason 'plan-author is off in /plugin config' $u $T/b/$u-batch.md\$") $(($(grep -c . "$T/to-main") - t0))"

# The service reads /plugin config from the profile main started under: CLAUDE_CONFIG_DIR crosses the service boundary.
# The default home has every seat on and the profile has Sol off, so the profile's settings show as the Fable judge.
opts '{}'; mkdir -p "$T/profile"; jq -n '{pluginConfigs: {"commandeck@commandeck": {options: {planJudgeSolAgent: "claude", planJudgeSolEnabled: false}}}}' > "$T/profile/settings.json"
u=pf; mkb $u; E+=(CLAUDE_CONFIG_DIR="$T/profile"); drive $u; E=("${E[@]:0:${#E[@]}-1}")
check "the driver's service keeps the caller's CLAUDE_CONFIG_DIR, so its seats are the active profile's (issue 443)" "profile=1011" "profile=$(seats $u)"

# A start resolves the project from its directory alone (E sets no COMMANDECK_MAIN); the service starts in $HOME, where
# nothing resolves it, so it runs only on the project the start hands it.
u=pm; mkb $u; drive $u; n=$(tail -1 "$T/started")
check "the driver's service runs on the project its start resolved, though it starts in \$HOME (issue 443)" "rc=0 noproject=0 author=1" \
  "rc=$(cat "$T/hs/$n") noproject=$(grep -c 'no project here' "$T/hs/$n.log") author=$(calls "run plan-author $u")"

# The tier stage keeps no file of its own: plan-tier's refusal reaches the STOP line from memory (Data design: no other
# state is added).
check "the tier stage writes no drive-<unit>.tier file, refused or not (issue 443)" "0" "$(find "$SCR" -name 'drive-*.tier' | grep -c .)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
