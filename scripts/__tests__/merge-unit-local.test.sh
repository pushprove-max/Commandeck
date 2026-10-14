#!/usr/bin/env bash
# merge-unit-local.sh is the only gate between a Builder's branch and main:
# nothing is pushed and no chain runs, so what it lets through IS main. What
# this pins: a branch with no review pass, or a hand-written GO, is refused, a branch whose pass ended
# NO-GO with a P0 or P1 is refused, a GO for an older commit is refused, a red check
# refuses the merge and leaves main as it was, and a branch whose pass ended GO at its tip merges
# as one squash commit after the project's check command ran on it. A check that
# rewrites or stages a file, and a branch that would overwrite an ignored local
# file, are refused.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
MERGE=$REAL/scripts/merge-unit-local.sh QUEUE=$REAL/scripts/merge-queue.sh PASS_SH=$REAL/scripts/builder-codex-pass.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
# An empty HOME: no Codex plugin, no model list, no signed-in CLI.
export HOME=$TMP/home CODEX_HOME=$TMP/codex COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
unset COMMANDECK_MAIN COMMANDECK_ROUTING
REPO=$TMP/proj
mkdir -p "$HOME" "$TMP/ws" "$TMP/bin"; : > "$TMP/orca-calls"
git init -q -b main "$REPO"
git -C "$REPO" config user.name t; git -C "$REPO" config user.email t@t; git -C "$REPO" config core.hooksPath /dev/null
echo base > "$REPO/a.txt"; git -C "$REPO" add a.txt; git -C "$REPO" commit -qm base
printf '%s\n' .claude/settings.local.json .claude/builder-events.jsonl >> "$REPO/.git/info/exclude"
cat > "$TMP/bin/orca-ide" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$TMP/orca-calls"
case "\$1 \$2" in
  "terminal list") echo '{"result":{"terminals":[{"handle":"t_'"\$(cat "$TMP/unit")"'","worktreePath":"$TMP/ws/'"\$(cat "$TMP/unit")"'"}]}}' ;;
  "worktree remove") [ ! -e "$TMP/remove-fails" ] || { echo "orca: the worktree is busy" >&2; exit 1; }
    git -C "\$(git -C "\${4#path:}" rev-parse --path-format=absolute --git-common-dir)" worktree remove --force "\${4#path:}" ;;
  *) echo '{"ok":true}' ;;
esac
STUB
# gh is never the real one: here it has no answer, so the P1 count is not measured.
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/orca-ide" "$TMP/bin/gh"
PATH=$TMP/bin:$PATH

# A proven unit is one the pass script itself ran a first pass on: three
# reviewers ending GO. The pass runs under a home of its own, with a stub of the
# Codex plugin that leaves the session record Codex would; the merge then runs
# under the empty home above. STUB_REPLY is what each reviewer answers.
PH=$TMP/passhome PLUG=$TMP/passhome/.claude/plugins/cache/openai-codex/codex/1.0.0
mkdir -p "$PLUG/scripts" "$PLUG/prompts" "$CODEX_HOME" "$TMP/cli"
printf 'Target: {{TARGET_LABEL}}\nUser focus: {{USER_FOCUS}}\nPrefer one strong finding over several weak ones.\n<structured_output_contract>\nReturn only valid JSON matching the provided schema.\n</structured_output_contract>\n{{REVIEW_COLLECTION_GUIDANCE}}\n{{REVIEW_INPUT}}\n' > "$PLUG/prompts/adversarial-review.md"
cat > "$PLUG/scripts/codex-companion.mjs" <<'JS'
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
const args = process.argv.slice(2);
const cwd = args[args.indexOf("--cwd") + 1], promptFile = args[args.indexOf("--prompt-file") + 1];
const id = `${process.env.STUB_THREAD}-${promptFile.match(/-prompt-(\d+)\.md$/)[1]}`;
const reply = process.env.STUB_REPLY || "Clean.\nVERDICT: GO";
const sha = execFileSync("git", ["-C", cwd, "rev-parse", "HEAD"]).toString().trim();
const dir = `${process.env.CODEX_HOME}/sessions/2026/10/11`;
mkdirSync(dir, { recursive: true });
writeFileSync(`${dir}/rollout-2026-10-11T00-00-00-${id}.jsonl`, [
  { type: "session_meta", timestamp: new Date().toISOString(), payload: { id, cwd, git: { commit_hash: sha } } },
  { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: readFileSync(promptFile, "utf8") }] } },
  { type: "event_msg", timestamp: new Date().toISOString(), payload: { type: "task_complete", last_agent_message: reply } },
].map((r) => JSON.stringify(r)).join("\n") + "\n");
process.stdout.write(JSON.stringify({ threadId: id, status: 0, rawOutput: reply }));
JS
printf 'import { writeFileSync } from "node:fs";\nconst a = process.argv.slice(2);\nwriteFileSync(a[a.indexOf("--endpoint") + 1].replace(/^unix:/, ""), "");\nsetInterval(() => {}, 1000);\n' > "$PLUG/scripts/app-server-broker.mjs"
echo 1 > "$PLUG/scripts/commandeck-test-waits"
printf 'model = "x"\nservice_tier = "fast"\n' > "$CODEX_HOME/config.toml"
jq '.roles["codex-reviewer"].model = "gpt-9.9-probe"' "$REAL/config/routing.json" > "$TMP/routing.json"
printf '#!/bin/sh\n[ "$*" = "login status" ]\n' > "$TMP/cli/codex"; chmod +x "$TMP/cli/codex"
mk() { # <unit>: a Builder worktree with one commit, its brief and its evidence
  local w=$COMMANDECK_WORKSPACES/$1
  git -C "$REPO" worktree add -q "$w" -b "builder/$1"
  mkdir -p "$w/.claude/briefs"; echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$w/.claude/settings.local.json"
  echo "brief for $1" > "$w/.claude/briefs/$1.md"; echo "evidence for $1" > "$w/.claude/briefs/$1-evidence.md"
  echo built > "$w/$1.txt"; git -C "$w" add "$1.txt"; git -C "$w" commit -qm "feat($1): the unit"
}
pass() { # <unit> <N> <kind>: one pass of the real pass script on the unit's worktree
  (cd "$COMMANDECK_WORKSPACES/$1" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-$1-$2 \
    bash "$PASS_SH" "$1" "$2" "$3" >/dev/null 2>"$TMP/pass.err") || { echo "FAIL the $3 pass on $1 did not run: $(cat "$TMP/pass.err")"; FAIL=$((FAIL+1)); }
}
go() { pass "$1" 1 adversarial; } # <unit>: a first pass that ends GO at the unit's tip
merge() { echo "$1" > "$TMP/unit"; (cd "$REPO" && bash "$MERGE" "$@") > "$TMP/out" 2>&1; echo $?; }
head_main() { git -C "$REPO" rev-parse main; }
BASE=$(head_main)
# The finished-builds record: one line a merge, written only once the squash commit stands.
REC=$HOME/.commandeck/builds/proj.jsonl

mk noproof
check "a branch with no round file is refused" 1 "$(merge noproof)"
check "the refusal names the proof step" 1 "$(grep -c '^FAILED step 3 proof' "$TMP/out")"

mk hand
printf 'Reviewed: %s\nCodex thread: thr-none\n\nVERDICT: GO\n' "$(git -C "$TMP/ws/hand" rev-parse HEAD)" > "$TMP/ws/hand/.claude/briefs/hand-r1-reports.md"
check "a hand-written round file naming no real session is refused" 1 "$(merge hand)"
printf 'VERDICT: GO\n' > "$TMP/ws/hand/.claude/briefs/hand-r2-reports.md"
check "a hand-written round file with no session id is refused" 1 "$(merge hand)"

mk nogo
STUB_REPLY=$'- [P1] a blocker -- nogo.txt:1\nVERDICT: NO-GO' pass nogo 1 adversarial
check "a branch whose pass ended NO-GO with a P1 is refused" 1 "$(merge nogo)"
check "the refusal names the proof step" 1 "$(grep -c '^FAILED step 3 proof' "$TMP/out")"
mk nogo0
STUB_REPLY=$'- [P0] a break -- nogo0.txt:1\nVERDICT: NO-GO' pass nogo0 1 adversarial
check "a branch whose pass ended NO-GO with a P0 is refused" 1 "$(merge nogo0)"
check "no refused merge moved main or staged anything" "$BASE 0" \
  "$(head_main) $(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ')"

mk stale; go stale
echo more > "$TMP/ws/stale/stale.txt"; git -C "$TMP/ws/stale" commit -qam "fix: after the review"
check "a GO for an older commit is refused" 1 "$(merge stale)"
check "no refused merge moved main, staged anything or closed a pane" "$BASE 0 0" \
  "$(head_main) $(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ') $(grep -c 'terminal close\|worktree remove' "$TMP/orca-calls")"

mk red; go red
mkdir -p "$REPO/.claude"
jq -n --arg c "echo ran >> '$TMP/red.log'; false" '{testCommand: $c}' > "$REPO/.claude/commandeck.json"
check "a red check command fails the merge" 1 "$(merge red)"
check "the red check ran once, and main is where it was with nothing staged and no new file" "1 $BASE 0 no" \
  "$(wc -l < "$TMP/red.log" | tr -d ' ') $(head_main) $(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ') $([ -e "$REPO/red.txt" ] && echo yes || echo no)"
check "the red unit keeps its worktree for the fix" yes "$([ -d "$TMP/ws/red" ] && echo yes || echo no)"

mk green; go green
mkdir -p "$REPO/.claude"
jq -n --arg c "test -f green.txt && echo ran >> '$TMP/check.log'" '{testCommand: $c}' > "$REPO/.claude/commandeck.json"
check "a proven unit merges" 0 "$(merge green)"
check "main gains one squash commit titled after the unit" "1 feat(green): the unit" \
  "$(git -C "$REPO" rev-list --count "$BASE..main") $(git -C "$REPO" log -1 --format=%s main)"
check "the check ran once, on the merged tree" 1 "$(wc -l < "$TMP/check.log" | tr -d ' ')"


# A check that rewrites a tracked file or stages one (a formatter, a
# generator) was green on a tree the commit would not hold.
mk rewr; go rewr
jq -n '{testCommand: "echo checked >> green.txt"}' > "$REPO/.claude/commandeck.json"
AFTER=$(head_main)
check "a merge whose check rewrites a tracked file is refused" 1 "$(merge rewr)"
check "the refusal names the file, and main did not move" "1|$AFTER" "$(grep -c 'the check command changed tracked files or what is staged (green.txt)' "$TMP/out")|$(head_main)"
git -C "$REPO" checkout -q -- green.txt
jq -n '{testCommand: "echo made > made.txt && git add made.txt"}' > "$REPO/.claude/commandeck.json"
check "a merge whose check stages a file is refused" 1 "$(merge rewr)"
check "main did not move, and nothing is left staged" "$AFTER|0" "$(head_main)|$(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ')"
rm -f "$REPO/made.txt"
# Git overwrites an ignored file without a word. A branch that adds a path the
# owner keeps here ignored (.env) would replace it, and a refused merge's undo
# would then delete it.
echo secret.env >> "$(git -C "$REPO" rev-parse --absolute-git-dir)/info/exclude"; echo mine > "$REPO/secret.env"
mk envu; echo theirs > "$TMP/ws/envu/secret.env"; git -C "$TMP/ws/envu" add -f secret.env; git -C "$TMP/ws/envu" commit -qm "feat(envu): env"; go envu
AFTER=$(head_main)
check "a merge that would overwrite an ignored local file is refused" 1 "$(merge envu)"
check "the owner's ignored file is as it was, main did not move, and the file is named" "mine|$AFTER|1" \
  "$(cat "$REPO/secret.env" 2>/dev/null)|$(head_main)|$(grep -c 'the branch adds secret.env' "$TMP/out")"

# The review loop the owner chose at setup (reviewLoop in the project config).
# With no closing pass, a narrowed GO merges once narrowed passes read every
# commit after the first pass; the default still asks for the closing pass.
jq -n '{}' > "$REPO/.claude/commandeck.json"
mk nofin
STUB_REPLY=$'- [P1] a blocker -- nofin.txt:1\nVERDICT: NO-GO' pass nofin 1 adversarial
echo fixed > "$TMP/ws/nofin/nofin.txt"; git -C "$TMP/ws/nofin" commit -qam "fix(nofin): the blocker"
pass nofin 2 review
AFTER=$(head_main)
check "by default a narrowed GO with no closing pass is refused" "1|$AFTER" "$(merge nofin)|$(head_main)"
jq -n '{reviewLoop: {closingPass: "no"}}' > "$REPO/.claude/commandeck.json"
check "with no closing pass chosen, the same narrowed GO merges" 0 "$(merge nofin)"
check "under its own rule" 1 "$(grep -c 'rule: no closing pass' "$TMP/out")"
mk nofin2
STUB_REPLY=$'- [P1] a blocker -- nofin2.txt:1\nVERDICT: NO-GO' pass nofin2 1 adversarial
echo fixed > "$TMP/ws/nofin2/nofin2.txt"; git -C "$TMP/ws/nofin2" commit -qam "fix(nofin2): one"
pass nofin2 2 review
echo again > "$TMP/ws/nofin2/nofin2.txt"; git -C "$TMP/ws/nofin2" commit -qam "fix(nofin2): unreviewed"
check "with no closing pass, a commit after the last narrowed pass is still refused" 1 "$(merge nofin2)"
jq -n '{reviewLoop: {closingPass: "no"}}' > "$REPO/.claude/commandeck.json"
mk nofin3
STUB_REPLY=$'- [P1] a blocker -- nofin3.txt:1\nVERDICT: NO-GO' pass nofin3 1 adversarial
echo one > "$TMP/ws/nofin3/nofin3.txt"; git -C "$TMP/ws/nofin3" commit -qam "fix(nofin3): one"
STUB_REPLY=$'- [P1] still broken -- nofin3.txt:1\nVERDICT: NO-GO' pass nofin3 2 review
check "with no closing pass, a narrowed pass that ends NO-GO does not merge" 1 "$(merge nofin3)"
echo two > "$TMP/ws/nofin3/nofin3.txt"; git -C "$TMP/ws/nofin3" commit -qam "fix(nofin3): two"
pass nofin3 3 review
check "and the narrowed GO that was handed its finding does" 0 "$(merge nofin3)"
mk cap
jq -n '{reviewLoop: {maxRounds: "2"}}' > "$REPO/.claude/commandeck.json"
STUB_REPLY=$'- [P1] a blocker -- cap.txt:1\nVERDICT: NO-GO' pass cap 1 adversarial
(cd "$TMP/ws/cap" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-cap-3 \
  bash "$PASS_SH" cap 3 review >/dev/null 2>"$TMP/pass.err"); RC=$?
check "a pass over the project's round cap is refused, and says so" "2:1" "$RC:$(grep -c 'round 3 is over the 2 rounds this project allows' "$TMP/pass.err")"
jq -n '{reviewLoop: {smallBuild: "lots"}}' > "$REPO/.claude/commandeck.json"
(cd "$TMP/ws/cap" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-cap-2 \
  bash "$PASS_SH" cap 2 review >/dev/null 2>"$TMP/pass.err"); RC=$?
check "a saved setting that is not a number stops the pass, naming the key" "2:1" "$RC:$(grep -c 'reviewLoop.smallBuild' "$TMP/pass.err")"
jq -n '{reviewLoop: {maxRounds: false}}' > "$REPO/.claude/commandeck.json"
(cd "$TMP/ws/cap" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-cap-2 \
  bash "$PASS_SH" cap 2 review >/dev/null 2>"$TMP/pass.err"); RC=$?
check "a round cap saved as false is no cap: it stops the pass, naming the key" "2:1" "$RC:$(grep -c 'reviewLoop.maxRounds = "false"' "$TMP/pass.err")"
jq -n '{reviewLoop: false}' > "$REPO/.claude/commandeck.json"
(cd "$TMP/ws/cap" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-cap-2 \
  bash "$PASS_SH" cap 2 review >/dev/null 2>"$TMP/pass.err"); RC=$?
check "a review loop saved as false is no setting: it stops the pass" "2:1" "$RC:$(grep -c 'reviewLoop' "$TMP/pass.err")"
check "and stops the build review" 1 \
  "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import collect
try: collect.loop_limits(sys.argv[2])
except SystemExit as e: print(int("reviewLoop" in str(e)))' "$REAL/skills/worktreereview/scripts" "$REPO")"
jq -n '{reviewLoop: {maxReviewMinutes: "NaN"}}' > "$REPO/.claude/commandeck.json"
check "a threshold that is not a finite number stops the build review" 1 \
  "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import collect
try: collect.loop_limits(sys.argv[2])
except SystemExit as e: print(int("reviewLoop" in str(e)))' "$REAL/skills/worktreereview/scripts" "$REPO")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
