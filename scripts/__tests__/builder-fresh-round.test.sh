#!/usr/bin/env bash
# A fix round's hand-off gave up after 15 minutes while the Builder's pane was still busy on a long turn, and
# its notice to main was refused (an escalation from a pane with no dispatch), so the round stalled unseen.
# Pinned: a busy pane is waited on until it idles; a pane that is gone gets nothing typed and main gets a
# question with the command that re-runs the hand-off; two hand-offs to one pane never interleave their typing.
# An Orca that fails (no answer, or a wait error other than a timeout) is retried a bounded number of times,
# then main is told: retried for good, it held the pane's lock and stalled every later hand-off unseen.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# Issue 301: a process left running from this file outlives it; the exit kills any that still names its folder.
T=$(cd "$(mktemp -d)" && pwd -P); trap 'pkill -f "$T/" 2>/dev/null; rm -rf "$T"' EXIT
SC=$T/scratch; mkdir -p "$T/bin" "$SC"
git init -q -b main "$T/p"
# Orca: a wait times out while $T/busy holds a count above 0; one --timeout-ms 120000 wait holds until $T/release
# when $T/hold exists; the list holds term_x unless $T/gone exists; every send is logged. With $T/down every
# call fails with no answer; with $T/werr a wait fails with an error that is not a timeout, with $T/werr2 only the
# 1000-ms second wait does. While $T/blocked holds a count above 0, a wait answers as Orca does for a pane that awaits
# its user: exit 1 with ok:true and wait.satisfied:false.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
[ ! -e "$T/down" ] || exit 1
case "\$*" in
  *"terminal wait"*)
    [ ! -e "$T/werr" ] || { echo '{"ok":false,"error":{"code":"internal","message":"boom"}}'; exit 1; }
    case "\$*" in *"--timeout-ms 1000 "*) [ ! -e "$T/werr2" ] || { echo '{"ok":false,"error":{"code":"internal"}}'; exit 1; } ;; esac
    b=\$(cat "$T/blocked" 2>/dev/null || echo 0); [ "\$b" -le 0 ] || { echo \$((b - 1)) > "$T/blocked"; echo '{"ok":true,"result":{"wait":{"satisfied":false}}}'; exit 1; }
    n=\$(cat "$T/busy" 2>/dev/null || echo 0); [ "\$n" -le 0 ] || { echo \$((n - 1)) > "$T/busy"; echo '{"ok":false,"error":{"code":"timeout"}}'; exit 1; }
    case "\$*" in *"--timeout-ms 120000"*) ! rm "$T/hold" 2>/dev/null || until [ -e "$T/release" ]; do sleep 0.05; done ;; esac
    [ ! -e "$T/gone" ] || exit 1 ;;
  *"terminal list"*) [ -e "$T/gone" ] && echo '{"result":{"terminals":[]}}' || echo '{"result":{"terminals":[{"handle":"term_x","worktreePath":"/elsewhere"}]}}' ;;
  *"terminal send"*) printf '%s\n' "\$*" | grep -oE -- '--text (/clear|/model [a-z]+|/effort [a-z]+|Your task spec)' >> "$T/sends" ;;
  *"terminal set-pane-title"*) [ ! -e "$T/no-title" ] || { echo "unknown command" >&2; exit 1; }
    printf '%s\n' "\$*" | sed -n 's/.*--title \(.*\)/--text title:\1/p' >> "$T/sends" ;;
esac
exit 0
EOF
chmod +x "$T/bin/orca-ide"
frs() { (cd "$T/p" && env PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$SC" COMMANDECK_WORKSPACES="$T/ws" \
  COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 timeout 10 bash "$REAL/scripts/builder-fresh-round.sh" term_x "$T/hand-$1.md"); }

echo 3 > "$T/busy"
frs a > "$T/a.out" 2>&1; R=$?
check "a pane busy for three tries is waited on, then cleared and handed the file" "0 /clear,Your task spec" \
  "$R $(sed 's/--text //' "$T/sends" | paste -sd, -)"

rm -f "$T/sends"; touch "$T/gone"
frs b > "$T/b.out" 2>&1; R=$?
check "a pane that is gone: exit 1, nothing typed, and the reason said" "1 0 1" \
  "$R $(cat "$T/sends" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'pane term_x is gone; nothing typed' "$T/b.out")"
check "main is sent a question (Orca takes one from a pane with no dispatch), with the re-run command" "question 1" \
  "$(jq -r .type "$SC/queue/main.jsonl") $(jq -r .body "$SC/queue/main.jsonl" | grep -cxF "re-run: bash $REAL/scripts/builder-fresh-round.sh term_x $T/hand-b.md")"

rm -f "$T/sends" "$T/gone" "$T/busy"; touch "$T/hold"
frs c1 > "$T/c1.out" 2>&1 & P1=$!
for _ in $(seq 100); do [ -e "$T/hold" ] || break; sleep 0.05; done
frs c2 > "$T/c2.out" 2>&1 & P2=$!
sleep 1; touch "$T/release"; wait "$P1" "$P2"
check "two hand-offs to one pane: the second types only after the first is done" "/clear,Your task spec,/clear,Your task spec" \
  "$(sed 's/--text //' "$T/sends" | paste -sd, -)"

rm -f "$T/sends"; echo 6 > "$T/blocked"
frs blk > "$T/blk.out" 2>&1; R=$?
check "a pane blocked on its user for six tries is waited on, not taken for Orca failing" "0 /clear,Your task spec" \
  "$R $(sed 's/--text //' "$T/sends" | paste -sd, -)"

# werr2: the first wait answers idle every time, so only failures of the second wait can stop the loop.
for f in down werr werr2; do
  rm -f "$T/sends" "$T/hold" "$T/release" "$SC/queue/main.jsonl"; touch "$T/$f"
  frs "$f" > "$T/$f.out" 2>&1; R=$?; rm -f "$T/$f"
  check "Orca failing ($f): exit 1 before the timeout, nothing typed, the reason said, main sent the re-run" "1 0 1 1" \
    "$R $(cat "$T/sends" 2>/dev/null | wc -l | tr -d ' ') $(grep -c 'Orca failed 5 times in a row' "$T/$f.out") $(jq -r .body "$SC/queue/main.jsonl" 2>/dev/null | grep -c '^re-run: ')"
done

# Issue 313, the fixer: a fix round is /clear in the same pane, which keeps the model and effort it opened with. A
# build's first fix round runs on the Builder's launched model and effort (a per-build raise included), every later
# one on Opus high, a /plugin config key beating either; the count is the build's fix hand-offs, so it resets per
# build, and only a fix hand-off switches anything. Caught: a later round left on a weaker Builder model, and a GO
# continuation or added work moved to the fixer's model. Issue 278: the new session's pane gets its title back.
BR=$T/ws/u9/.claude/briefs; mkdir -p "$BR" "$T/home/.claude"
LOGS=$T/home/.claude/projects/$(printf '%s' "$T/ws/u9" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$LOGS"
opts() { jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: $o}}}' > "$T/home/.claude/settings.json"; }
# fr <hand-off name> <model> <effort> [record lines] -- one hand-off of the Builder of u9, launched on that model and
# effort, the record lines (an earlier round's switch) after the launch's; a fix hand-off is written first, as the pass
# writes it. The new session's log is there before the hand-off looks for it.
fr() { rm -f "$T/sends"; printf 'handle=term_x\nunit=u9\nrole=builder\ncmd=export COMMANDECK_SEAT=builder; claude --model %s --effort %s\n' "$2" "$3" > "$T/rec"
  [ -z "${4:-}" ] || printf '%s\n' "$4" >> "$T/rec"
  echo hand-off > "$BR/$1"; cp "$T/rec" "$T/rec.before"
  (sleep 1; echo "$BR/$1" > "$LOGS/s-$1.jsonl") &
  (cd "$T/p" && env -u CLAUDE_CONFIG_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$SC" COMMANDECK_WORKSPACES="$T/ws" \
    COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 timeout 10 bash "$REAL/scripts/builder-fresh-round.sh" term_x "$BR/$1" "$T/rec" > "$T/fr.out" 2>&1); R=$?
  SEQ=$(sed 's/--text //' "$T/sends" | paste -sd, -); NEWREC=$(diff "$T/rec.before" "$T/rec" | sed -n 's/^> //p' | grep -v '^session=' | paste -sd' ' -); }
newbuild() { rm -f "$BR"/*-fix-r*.md; }
TS="title:Builder — u9,Your task spec"
fr u9-fix-r1.md sonnet high
check "first NO-GO on a build: the fixer keeps the Builder's launched model and effort, a raised Sonnet high Builder included, and the record says fixer=first:builder" \
  "/clear,$TS|model=sonnet effort=high fixer=first:builder" "$SEQ|$NEWREC"
fr u9-fix-r2.md sonnet medium
check "second NO-GO on the same build: the fixer types /model opus and /effort high; the record says model=opus effort=high fixer=later:routing" \
  "/clear,/model opus,/effort high,$TS|model=opus effort=high fixer=later:routing" "$SEQ|$NEWREC"
newbuild; opts '{"fixerFirstModel": "opus"}'; fr u9-fix-r1.md sonnet high
check "a /plugin override wins on the first pass: fixerFirstModel=opus" "/clear,/model opus,$TS|model=opus effort=high fixer=first:config" "$SEQ|$NEWREC"
opts '{"fixerModel": "sonnet", "fixerEffort": "medium"}'; fr u9-fix-r2.md opus high
check "a /plugin override wins on the second pass: fixerModel=sonnet fixerEffort=medium" \
  "/clear,/model sonnet,/effort medium,$TS|model=sonnet effort=medium fixer=later:config" "$SEQ|$NEWREC"
opts '{"fixerEnabled": false}'; fr u9-fix-r3.md sonnet medium
check "fixer off: no /model or /effort on a later round, and the record says fixer=off" "/clear,$TS|model=sonnet effort=medium fixer=off" "$SEQ|$NEWREC"
# Off after an earlier round moved the pane to Opus high: the pane goes back to the Builder's launch settings.
fr u9-fix-r3.md sonnet medium $'model=opus\neffort=high\nfixer=later:routing'
check "fixer off after an escalation: /model and /effort put the Builder's launch settings back, and the record says so" \
  "/clear,/model sonnet,/effort medium,$TS|model=sonnet effort=medium fixer=off" "$SEQ|$NEWREC"
opts '{"fixerModel": "gpt-6.1-sol"}'; fr u9-fix-r4.md sonnet medium
check "a value the key does not take stops the hand-off naming the key, nothing switched or typed after /clear" "1|/clear|1" \
  "$R|$SEQ|$(grep -c '/plugin config fixerModel = gpt-6.1-sol is not a claude model for fixer' "$T/fr.out")"
opts '{}'; rm -f "$BR/u9-fix-r4.md"
# A new unit's first fix hand-off is its first, whatever its pass number and whatever another unit's files hold.
BR8=$T/ws/u8/.claude/briefs; mkdir -p "$BR8"; OBR=$BR; BR=$BR8; fr u8-fix-r3.md sonnet medium; BR=$OBR
check "a new unit's first fix round counts as first" "fixer=first:builder" "$(grep '^fixer=' "$T/rec")"
# The filename guard: with two fix files there and a fixer that would switch, a GO continuation and added work switch nothing.
newbuild; echo x > "$BR/u9-fix-r1.md"; echo x > "$BR/u9-fix-r2.md"; opts '{"fixerModel": "sonnet", "fixerEffort": "medium"}'
fr u9-after-r3.md opus high
check "two fix files, an Opus high pane, fixerModel=sonnet fixerEffort=medium: a GO continuation types nothing and leaves the record unchanged" \
  "/clear,$TS|" "$SEQ|$NEWREC"
fr u9-added-19990101-000000.md opus high
check "and an added-work hand-off types nothing and leaves the record unchanged" "/clear,$TS|" "$SEQ|$NEWREC"
opts '{}'; newbuild
touch "$T/no-title"; fr u9-fix-r1.md opus medium; rm -f "$T/no-title"
check "an Orca without set-pane-title: the hand-off still goes through" "0 /clear,Your task spec" "$R $SEQ"
wait
check "no hand-off of this file is left running" 0 "$(pgrep -f "$T/" | wc -l | tr -d ' ')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
