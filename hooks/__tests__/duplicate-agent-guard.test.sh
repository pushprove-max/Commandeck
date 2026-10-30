#!/usr/bin/env bash
# Self-test for duplicate-agent-guard.sh. The two duplicates the
# scripted guard could not see on 2026-09-23 were typed by hand: a second
# implementer pane opened 44 s after the first (tooling-3e-static), and a
# round-2 job sent into a pane still busy with round 1 (guest-seamless-sol6).
set -uo pipefail
HOOK=$(cd "$(dirname "$0")/.." && pwd)/duplicate-agent-guard.sh
BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi; }

mkdir -p "$BOX/bin"
cat > "$BOX/bin/orca-ide" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$BOX/calls"
case "\$1 \$2" in
  "terminal list") cat "$BOX/list.json" ;;
  "worktree ps") cat "$BOX/ps.json" ;;
esac
EOF
chmod +x "$BOX/bin/orca-ide"
export PATH="$BOX/bin:$PATH" COMMANDECK_SCRATCH="$BOX/scratch"
# The duplicate cases run from a linked worktree: in the main checkout every
# hand-made agent pane is refused before the live-agent check.
git init -q "$BOX/main" && git -C "$BOX/main" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m init \
  && git -C "$BOX/main" worktree add -q "$BOX/wt" >/dev/null 2>&1 || { echo "FAIL fixture: no linked worktree"; exit 1; }
DIR=$BOX/wt
run() { : > "$BOX/calls"; jq -cn --arg c "$1" --arg d "$DIR" '{tool_input:{command:$c},cwd:$d}' | CLAUDE_PROJECT_DIR="$DIR" "$HOOK" 2>"$BOX/err"; echo $?; }
run_main() { local DIR=$BOX/main; run "$1"; }
pane() { # agentIdentity state
  jq -nc --argjson a "$1" '{ok:true,result:{terminals:[{handle:"term_w",tabId:"t1",leafId:"l1",title:"Implementer — unit-x",connected:true,orphaned:false,agentIdentity:$a}]}}' > "$BOX/list.json"
  jq -nc --arg s "$2" '{ok:true,result:{worktrees:[{agents:[{paneKey:"t1:l1",state:$s}]}]}}' > "$BOX/ps.json"
}
LAUNCH='orca-ide terminal create --worktree "path:/ws/unit-x" --title "Implementer — unit-x" --command "codex --profile sol" --json'

pane '"codex"' working
check "a hand launch beside a live agent is blocked"   2 "$(run "$LAUNCH")"
check "the block names the live pane"                   1 "$(grep -c 'term_w (codex, Implementer — unit-x)' "$BOX/err")"
check "a plain shell pane is not an agent"              0 "$(run 'orca-ide terminal create --worktree path:/ws/unit-x --command "tail -f ship.log"')"
pane null done
check "a hand launch with no live agent is allowed"     0 "$(run "$LAUNCH")"

pane '"claude"' working
check "a hand new-job send into a busy pane is blocked" 2 "$(run 'orca-ide terminal send --terminal term_w --text "Read the round-2 brief" --enter')"
check "a keystroke with no Enter is not a job"          0 "$(run "orca-ide terminal send --terminal term_w --text \$'\\x15'")"
check "a same-job 'go' nudge to a busy pane is allowed" 0 "$(run 'orca-ide terminal send --terminal term_w --text go --enter')"

pane '"claude"' done
check "a send into an idle pane is allowed"             0 "$(run 'orca-ide terminal send --terminal term_w --text "Read the brief" --enter')"

pane '"claude"' working
check "a script launcher is not a hand launch"          0 "$(run 'bash scripts/seat.sh launch certifier unit-x spec.md')"

# Owner ruling 2026-10-11: main opens an agent pane only
# through builder-launch.sh or seat.sh, live agent or not.
pane null done
for agent in claude codex; do
  check "main: a hand-made $agent pane is blocked" 2 "$(run_main "orca-ide terminal create --worktree path:/ws/unit-x --command '$agent --model m' --json")"
done
check "main: a plain shell pane is allowed"           0 "$(run_main 'orca-ide terminal create --worktree path:/ws/unit-x --command "tail -f ship.log"')"
check "main: builder-launch.sh is the scripted path" 0 "$(run_main 'bash scripts/builder-launch.sh unit-x .claude/briefs/unit-x.md')"

# Issue 447: an order sent by hand to a Builder's inbox, or to a dispatch inbox, is read only by a pane parked in a wait,
# so it sat unread while the Builder built what the order cancelled. answer-worker.sh reads the pane and picks the way.
mkdir -p "$BOX/scratch"
printf 'handle=term_w\ntask=t1\nrole=builder\nunit=unit-x\n' > "$BOX/scratch/seat-unit-x-builder.txt"
SEND='orca-ide orchestration send --type status --subject "answer" --body "go with ruling 4"'
pane '"claude"' working
check "a hand inbox send to a Builder is blocked and names answer-worker.sh (issue 447)" "2 1" \
  "$(run "$SEND --to term_w") $(grep -c 'term_w is mid-turn and reads its inbox only while parked in a wait; send it with scripts/answer-worker.sh' "$BOX/err")"
check "main's hand send to a dispatch inbox is blocked; a worker's is not checked (issue 447)" "2 0" \
  "$(run_main "$SEND --to dispatch:ctx_1") $(run "$SEND --to dispatch:ctx_1")"

# Issue 485: a plan seat at its prompt reads no inbox, and a hand send starts no task; seat.sh revise does. A working seat
# may be parked in a wait, so it passes.
rm -f "$BOX/scratch/seat-unit-x-builder.txt"
printf 'handle=term_w\ntask=t1\nrole=plan-author\nunit=unit-x\n' > "$BOX/scratch/seat-unit-x-plan-author.txt"
pane '"claude"' done
check "an idle seat send is refused (issue 485)" "2 1 0" \
  "$(run "$SEND --to term_w") $(grep -c 'seat.sh revise plan-author unit-x' "$BOX/err") $(pane '"claude"' working; run "$SEND --to term_w")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
