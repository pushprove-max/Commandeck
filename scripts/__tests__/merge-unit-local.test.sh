#!/usr/bin/env bash
# timeout: 300
# merge-unit-local.sh is the only gate between a Builder's branch and main:
# nothing is pushed and no chain runs, so what it lets through IS main. It must
# merge a branch whose last round file is the pass script's GO for the tip, and
# refuse every other one: no round file, a hand-written one, a GO for an older
# commit. The Builder cannot switch the proof off from its own settings file. A
# Codex plugin or CLI update never refuses work that already passed review
# (owner ruling 2026-10-11). The project's check command runs once on
# the merged tree, and a red check leaves main untouched.
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
echo '{}' > "$TMP/ws/noproof/.claude/settings.local.json"
check "a worktree whose settings drop the Builder flag still owes the proof" 1 "$(merge noproof)"

mk hand
printf 'Reviewed: %s\nCodex thread: thr-none\n\nVERDICT: GO\n' "$(git -C "$TMP/ws/hand" rev-parse HEAD)" > "$TMP/ws/hand/.claude/briefs/hand-r1-reports.md"
check "a hand-written round file naming no real session is refused" 1 "$(merge hand)"
printf 'VERDICT: GO\n' > "$TMP/ws/hand/.claude/briefs/hand-r2-reports.md"
check "a hand-written round file with no session id is refused" 1 "$(merge hand)"

mk stale; go stale
echo more > "$TMP/ws/stale/stale.txt"; git -C "$TMP/ws/stale" commit -qam "fix: after the review"
check "a GO for an older commit is refused" 1 "$(merge stale)"
check "no refused merge moved main, staged anything or closed a pane" "$BASE 0 0" \
  "$(head_main) $(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ') $(grep -c 'terminal close\|worktree remove' "$TMP/orca-calls")"

mk red; go red
mkdir -p "$REPO/.claude"
jq -n --arg c "echo ran >> '$TMP/check.log'; false" '{testCommand: $c}' > "$REPO/.claude/commandeck.json"
check "a red check command fails the merge" 1 "$(merge red)"
check "the red check ran once, and main is where it was with nothing staged and no new file" "1 $BASE 0 no" \
  "$(wc -l < "$TMP/check.log" | tr -d ' ') $(head_main) $(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ') $([ -e "$REPO/red.txt" ] && echo yes || echo no)"
check "the red unit keeps its worktree for the fix" yes "$([ -d "$TMP/ws/red" ] && echo yes || echo no)"
# Git names the squash's paths from the checkout's root. Undone from a
# subfolder, the same names would point at the owner's files in that folder.
mkdir -p "$REPO/sub"; echo mine > "$REPO/sub/red.txt"
check "a red check fails the merge from a subfolder too" 1 "$( (cd "$REPO/sub" && bash "$MERGE" red) > "$TMP/out" 2>&1; echo $?)"
check "and the undo takes the squash's file, not the subfolder's of the same name" "mine no 0" \
  "$(cat "$REPO/sub/red.txt" 2>/dev/null) $([ -e "$REPO/red.txt" ] && echo yes || echo no) $(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ')"
rm -rf "$REPO/sub"

mk green; go green
rm -f "$TMP/check.log"
jq -n --arg c "test -f green.txt && echo ran >> '$TMP/check.log'" '{testCommand: $c}' > "$REPO/.claude/commandeck.json"
check "a dry run passes a proven unit" 0 "$(merge green --dry-run)"
check "a dry run merges nothing, runs no check and keeps the worktree" "$BASE no yes" \
  "$(head_main) $([ -e "$TMP/check.log" ] && echo yes || echo no) $([ -d "$TMP/ws/green" ] && echo yes || echo no)"
# A Codex update after the review: a newer, broken companion and a CLI that fails.
mkdir -p "$HOME/.claude/plugins/cache/openai-codex/codex/9.9.9/scripts" "$TMP/newcodex"
echo 'process.exit(1)' > "$HOME/.claude/plugins/cache/openai-codex/codex/9.9.9/scripts/codex-companion.mjs"
printf '#!/bin/sh\nexit 1\n' > "$TMP/newcodex/codex"; chmod +x "$TMP/newcodex/codex"
check "no refused merge and no dry run wrote a finished-builds record" no "$([ -e "$REC" ] && echo yes || echo no)"
check "the proof of a reviewed GO does not read the installed Codex plugin or CLI" 0 \
  "$(PATH=$TMP/newcodex:$PATH bash "$PASS_SH" --verify "$TMP/ws/green" green HEAD >/dev/null 2>&1; echo $?)"
check "a proven unit merges, with that Codex update in place" 0 "$(PATH=$TMP/newcodex:$PATH merge green)"
check "main gains one squash commit titled after the unit" "1 feat(green): the unit" \
  "$(git -C "$REPO" rev-list --count "$BASE..main") $(git -C "$REPO" log -1 --format=%s main)"
check "the merge records the finished build on one line: the checkout, the unit, how it ended, the commit, when, and nothing open" "1 $REPO green merged $(head_main) true 0 0 0" \
  "$(wc -l < "$REC" 2>/dev/null | tr -d ' ') $(jq -r '[.main, .unit, .how, .sha, (.at | test("^20[0-9-]+T[0-9:]+Z$")), .open.P1, .open.P2, .open.P3] | join(" ")' "$REC" 2>&1)"
check "the check ran once, on the merged tree" 1 "$(wc -l < "$TMP/check.log" | tr -d ' ')"
check "the commit holds the unit's code and none of its papers, which are in the plugin's archive" \
  "green.txt|green-evidence.md green-r1-reports.md green.md" \
  "$(git -C "$REPO" show --pretty= --name-only main | paste -sd' ' -)|$(tar -tf "$HOME/.commandeck/briefs/proj/green.tar" | sort | paste -sd' ' -)"
check "the unit's pane is closed and its worktree removed" "1 no" \
  "$(grep -c '^terminal close --terminal t_green ' "$TMP/orca-calls") $([ -e "$TMP/ws/green" ] && echo yes || echo no)"
check "the project gains no file but the commit's" "?? .claude/commandeck.json" "$(git -C "$REPO" status --porcelain -uall | paste -sd'|' -)"
check "the merge pushes nothing: no push in either script" 0 "$(grep -c 'git push' "$MERGE" "$QUEUE" | awk -F: '{ n += $2 } END { print n }')"

# The proof names the rule the tip merges under and each finding still open,
# in a dry run as in the merge: main reads those lines and files what stays
# open. Here a closing pass left a P2, and the one narrowed pass after it too.
mk tail
STUB_REPLY=$'- [P1] a blocker -- tail.txt:1\nVERDICT: NO-GO' pass tail 1 adversarial
echo fix-1 > "$TMP/ws/tail/tail.txt"; STUB_REPLY=$'- [P2] a small thing -- tail.txt:1\nVERDICT: NO-GO' pass tail 2 final
echo fix-2 > "$TMP/ws/tail/tail.txt"; STUB_REPLY=$'- [P2] still open -- tail.txt:1\nVERDICT: NO-GO' pass tail 3 review
check "a dry run prints the rule and each finding open at merge" "0 1 1" \
  "$(merge tail --dry-run) $(grep -c '^Builder proof: .*; rule: P2 tail' "$TMP/out") $(grep -cx 'Open at merge: - \[P2\] still open -- tail.txt:1' "$TMP/out")"
# The build review reads the worktree, so it runs after the commit and before
# the cleanup; a review that fails never fails the merge, and a dry run makes none.
PLUGC=$TMP/plug; mkdir -p "$PLUGC/skills/worktreereview/scripts"
for d in scripts hooks config templates; do cp -R "$REAL/$d" "$PLUGC/"; done
printf 'import os, sys\nopen(sys.argv[0] + ".ran", "w").write(str(os.path.isdir(sys.argv[1])))\nopen(sys.argv[0] + ".args", "w").write(" ".join(sys.argv[2:]))\nsys.exit(3)\n' > "$PLUGC/skills/worktreereview/scripts/review.py"
RAN=$PLUGC/skills/worktreereview/scripts/review.py.ran
check "a dry run makes no build review" "0 no" "$(MERGE=$PLUGC/scripts/merge-unit-local.sh merge tail --dry-run) $([ -e "$RAN" ] && echo yes || echo no)"
# The gh here answers nothing, as on a machine with no gh login or a project with no GitHub remote: the
# finding left open cannot be filed as an issue. The merge is made all the same and ends with code 4.
check "a dry run says the open finding could not be looked up, and still passes" 1 "$(grep -c '^step 4 issues: could not look up: - \[P2\] still open' "$TMP/out")"
check "the merge prints the same lines, a build review that fails does not fail it, and an unfiled finding gives code 4" "4 1 1 True" \
  "$(MERGE=$PLUGC/scripts/merge-unit-local.sh merge tail) $(grep -c '^Builder proof: .*; rule: P2 tail' "$TMP/out") $(grep -cx 'Open at merge: - \[P2\] still open -- tail.txt:1' "$TMP/out") $(cat "$RAN" 2>/dev/null)"
check "the squash commit is made before anything is filed, and stands" "feat(tail): the unit" "$(git -C "$REPO" log -1 --format=%s main)"
check "the unfiled finding is the last line printed, under the command that files it without merging again" "1 1" \
  "$(tail -1 "$TMP/out" | grep -c '^NOT FILED: - \[P2\] still open -- tail.txt:1 (the lookup for an open issue failed') $(grep -c '^MERGED, but 1 finding(s) left open have no issue. File them from the main checkout with: printf .*file-open-findings.sh tail ' "$TMP/out")"
check "a finding open at merge is counted on the build's line, and the dry runs before it added none" "2 tail 0 1 0" \
  "$(wc -l < "$REC" | tr -d ' ') $(tail -1 "$REC" | jq -r '[.unit, .open.P1, .open.P2, .open.P3] | join(" ")' 2>&1)"
# A step after the commit that fails (here Orca will not remove the worktree) is
# not a refused merge: the commit stands, and what was not filed is still the
# last thing printed, with the code for it. The finding carries a failing
# command with two spaces in it: it is one finding, answered once.
mk tailc
STUB_REPLY=$'- [P1] a blocker -- tailc.txt:1\nVERDICT: NO-GO' pass tailc 1 adversarial
echo fix-1 > "$TMP/ws/tailc/tailc.txt"; STUB_REPLY=$'- [P2] a small thing -- tailc.txt:1\nVERDICT: NO-GO' pass tailc 2 final
echo fix-2 > "$TMP/ws/tailc/tailc.txt"; STUB_REPLY=$'- [P2] left open -- tailc.txt:1 -- it breaks -- printf \'a  b\' | sh tailc.sh\nVERDICT: NO-GO' pass tailc 3 review
touch "$TMP/remove-fails"
check "a clean-up step that fails after the commit still ends with the code for merged, not all filed" "4 feat(tailc): the unit" "$(merge tailc) $(git -C "$REPO" log -1 --format=%s main)"
check "it says the merge stands, and the unfiled finding is the last line, once" "1 1 1 1" \
  "$(grep -c '^FAILED step 5 cleanup' "$TMP/out") $(grep -c "^MERGED as $(git -C "$REPO" rev-parse --short=8 main), but a step after the merge commit failed" "$TMP/out") $(tail -1 "$TMP/out" | grep -c '^NOT FILED: - \[P2\] left open -- tailc.txt:1 -- it breaks -- printf .a  b. | sh tailc.sh (the lookup') $(grep -c '^NOT FILED: ' "$TMP/out")"
rm "$TMP/remove-fails"; git -C "$REPO" worktree remove --force "$TMP/ws/tailc"
# The merge's review opens no tab. Without a relay worktree review.py tells no one:
# the merge names the relay's worktree when there is one, and nothing when there is not.
check "with no relay worktree the build review is given none, and is asked to open no tab" "--no-open" "$(cat "${RAN%.ran}.args")"
mk rl; go rl; mkdir -p "$TMP/ws/Chief-of-Staff"
check "the build review is given the relay's worktree for a flagged run, and still opens no tab" "0 --open-in $TMP/ws/Chief-of-Staff --no-open" "$(MERGE=$PLUGC/scripts/merge-unit-local.sh merge rl) $(cat "${RAN%.ran}.args")"
rmdir "$TMP/ws/Chief-of-Staff"
check "a first pass's GO on the unchanged tip merges under its own rule" 1 "$(mk fp; go fp; merge fp --dry-run >/dev/null; grep -c '^Builder proof: .*; rule: first-pass GO' "$TMP/out")"

# The queue merges in order and stops at the first refusal. q2 was reviewed
# before green merged, so its merge also proves a clean rebase keeps the proof.
mk q1; mk q2; go q2
AFTER=$(head_main)
echo q1 > "$TMP/unit"; (cd "$REPO" && bash "$QUEUE" q1 q2) > "$TMP/qout" 2>&1
check "the queue stops at an unproven unit" 1 "$?"
check "the unit behind it is not merged, and the log is in scratch" "$AFTER yes" "$(head_main) $([ -s "$TMP/scratch/merge-q1.log" ] && echo yes || echo no)"
echo q2 > "$TMP/unit"; (cd "$REPO" && bash "$QUEUE" q2) > "$TMP/qout" 2>&1
check "the queue merges a proven unit rebased onto the earlier merge" "0 feat(q2): the unit" "$? $(git -C "$REPO" log -1 --format=%s main)"
# A unit that merged and could not file its open finding does not stop the queue: the next unit merges, and the queue ends 4.
mk qf; STUB_REPLY=$'- [P1] a blocker -- qf.txt:1\nVERDICT: NO-GO' pass qf 1 adversarial
echo fix-1 > "$TMP/ws/qf/qf.txt"; STUB_REPLY=$'- [P2] a small thing -- qf.txt:1\nVERDICT: NO-GO' pass qf 2 final
echo fix-2 > "$TMP/ws/qf/qf.txt"; STUB_REPLY=$'- [P2] still open -- qf.txt:1\nVERDICT: NO-GO' pass qf 3 review
mk qg; go qg
echo qf > "$TMP/unit"; (cd "$REPO" && bash "$QUEUE" qf qg) > "$TMP/qout" 2>&1
check "the queue goes on past a unit whose finding was not filed, and ends with code 4" "4 feat(qg): the unit 1" \
  "$? $(git -C "$REPO" log -1 --format=%s main) $(grep -c '^merge-queue: qf merged; 1 finding(s) NOT FILED as issues' "$TMP/qout")"

# Another unit whose name merely starts the same keeps its briefs: the archive
# step deletes what it archives, and "pre" must not take "prefab" or "pre-other".
mk pre; go pre
mkdir -p "$REPO/.claude/briefs"
echo other > "$REPO/.claude/briefs/prefab.md"; echo other > "$REPO/.claude/briefs/pre-other.md"; echo other > "$REPO/.claude/briefs/pre-other-r1-reports.md"
echo stray > "$TMP/ws/pre/.claude/briefs/prefab-evidence.md"
check "a unit whose name is a prefix of another's merges" 0 "$(merge pre)"
check "the other units' briefs are still in the project" "pre-other-r1-reports.md pre-other.md prefab.md" "$(cd "$REPO/.claude/briefs" && ls pre-other* prefab* 2>/dev/null | paste -sd' ' -)"
check "and the archive holds only this unit's files" "pre-evidence.md pre-r1-reports.md pre.md" "$(tar -tf "$HOME/.commandeck/briefs/proj/pre.tar" | sort | paste -sd' ' -)"
rm -f "$REPO/.claude/briefs"/pre-other* "$REPO/.claude/briefs/prefab.md"

# A build's papers are never committed (main's ruling 3): main's own untracked
# files of the unit, its rulings among them, go to the archive with the
# worktree's and leave the project; the commit holds none of them.
mk held; go held
mkdir -p "$REPO/.claude/briefs"; echo "main's rulings" > "$REPO/.claude/briefs/held-main-rulings.md"
# A file of main's own under the evidence's name is not the Builder's: archived beside it, one would hide the other.
echo "main's own notes" > "$REPO/.claude/briefs/held-evidence.md"
check "a unit merges with main's rulings file for it in the project" 0 "$(merge held)"
check "the rulings are archived with the unit's papers and gone from main, and the commit holds only the code" \
  "held-evidence.md held-main-rulings.md held-r1-reports.md held.md|no|held.txt" \
  "$(tar -tf "$HOME/.commandeck/briefs/proj/held.tar" | sort | paste -sd' ' -)|$([ -e "$REPO/.claude/briefs/held-main-rulings.md" ] && echo yes || echo no)|$(git -C "$REPO" show --pretty= --name-only main | paste -sd' ' -)"
check "main's own file under the evidence's name stays in main as it was" "main's own notes" "$(cat "$REPO/.claude/briefs/held-evidence.md" 2>/dev/null)"
rm -f "$REPO/.claude/briefs/held-evidence.md"
# With no paper committed, a branch with no commit of its own has nothing to merge.
git -C "$REPO" worktree add -q "$TMP/ws/nocode" -b builder/nocode
mkdir -p "$TMP/ws/nocode/.claude/briefs"; echo brief > "$TMP/ws/nocode/.claude/briefs/nocode.md"; echo evidence > "$TMP/ws/nocode/.claude/briefs/nocode-evidence.md"
AFTER=$(head_main)
check "a unit with papers and no commit is refused" 1 "$(merge nocode)"
check "the refusal says why, and main did not move" "1|$AFTER" "$(grep -c 'has no commit of its own' "$TMP/out")|$(head_main)"
git -C "$REPO" worktree remove --force "$TMP/ws/nocode"

# A brief git tracks in main (a project set up before the papers left git) is
# main's to untrack: the merge neither deletes it nor commits main's edit to it.
mkdir -p "$REPO/.claude/briefs"; echo "brief for edited" > "$REPO/.claude/briefs/edited.md"
git -C "$REPO" add -f .claude/briefs/edited.md; git -C "$REPO" commit -qm "docs: the edited unit's brief"
mk edited; go edited
echo "main's later note" >> "$REPO/.claude/briefs/edited.md"
check "a unit merges past main's uncommitted edit to a brief git tracks" 0 "$(merge edited)"
check "the edit is still there, uncommitted, and the commit holds only the code" "1| M .claude/briefs/edited.md|edited.txt" \
  "$(grep -c "main's later note" "$REPO/.claude/briefs/edited.md")|$(git -C "$REPO" status --porcelain -- .claude/briefs | paste -sd'|' -)|$(git -C "$REPO" show --pretty= --name-only main | paste -sd' ' -)"
git -C "$REPO" checkout -q -- .claude/briefs/edited.md

# A project may ignore .claude/ whole, as setup makes it ignore .claude/briefs/.
mk ign; go ign
echo '.claude/' >> "$REPO/.git/info/exclude"
check "a proven unit merges in a project that ignores .claude/" 0 "$(merge ign)"
# A unit's papers are told from another unit's by name alone (u-evidence.md is
# u's evidence), so no unit may be named like a paper: neither launched nor merged.
echo batch > "$TMP/batch.md"; : > "$TMP/orca-calls"; SHAPES="u-evidence u-design u-design-spec u-main-rulings u-r2-reports u-cut1-audit"
check "a launch under a name shaped like a paper is refused, each shape, with the rule and the suffix" "2:-evidence 2:-design 2:-design-spec 2:-main-rulings 2:-r2-reports 2:-cut1" \
  "$(for u in $SHAPES; do (cd "$REPO" && bash "$REAL/scripts/builder-launch.sh" "$u" "$TMP/batch.md") >/dev/null 2>"$TMP/err"; printf '%s:%s ' $? "$(sed -n 's/.*may not be named like a paper.*(it has \([^)]*\)).*/\1/p' "$TMP/err")"; done | sed 's/ $//')"
check "before anything is created" "0|" "$(wc -l < "$TMP/orca-calls" | tr -d ' ')|$(cd "$TMP/ws" && ls -d $SHAPES 2>/dev/null | paste -sd' ' -)"
check "and a merge under such a name is refused the same way" "1:1" "$(merge u-main-rulings):$(grep -c 'may not be named like a paper.*(it has -main-rulings)' "$TMP/out")"
check "and the commit holds only the code" "ign.txt" "$(git -C "$REPO" show --pretty= --name-only main | paste -sd' ' -)"

# The check runs on a copy of exactly the tree the commit will hold
# (owner ruling 2026-10-12): main's own uncommitted edit to a tracked
# file is not tested, not committed and not touched. node_modules, which a
# copy would lose, are linked from main as in a unit's worktree.
WTS=$(git -C "$REPO" worktree list | wc -l | tr -d ' ')
mk dirt; go dirt
echo "main's own edit" >> "$REPO/green.txt"
mkdir -p "$REPO/node_modules/dep"; echo dep > "$REPO/node_modules/dep/index.js"; echo node_modules >> "$REPO/.git/info/exclude"
jq -n --arg t "$TMP" '{testCommand: "pwd > \($t)/check.pwd; git write-tree > \($t)/check.tree; git status --porcelain > \($t)/check.status; test -f dirt.txt && test -f node_modules/dep/index.js && ! grep -q own green.txt"}' > "$REPO/.claude/commandeck.json"
check "a unit merges past main's uncommitted edit to a tracked file, which the check does not see" 0 "$(merge dirt)"
check "the check ran outside main's checkout" 0 "$(grep -cxF "$(cd "$REPO" && pwd -P)" "$TMP/check.pwd")"
check "the check ran on exactly the tree of the commit the merge made" "$(git -C "$REPO" rev-parse 'main^{tree}')" "$(cat "$TMP/check.tree")"
check "the copy held no file that is not in that tree, but the linked node_modules (ignored)" "" \
  "$(grep -v '^[AMD]  ' "$TMP/check.status" | paste -sd'|' -)"
check "main's edit is still there, uncommitted, and not in the commit" "1|green.txt|0" \
  "$(grep -c "main's own edit" "$REPO/green.txt")|$(git -C "$REPO" diff --name-only | paste -sd' ' -)|$(git -C "$REPO" show main:green.txt | grep -c own)"
check "the copy is gone, and main's node_modules are whole" "no|$WTS|dep" \
  "$([ -e "$(cat "$TMP/check.pwd")" ] && echo yes || echo no)|$(git -C "$REPO" worktree list | wc -l | tr -d ' ')|$(cat "$REPO/node_modules/dep/index.js")"
# A red check on the copy still refuses, leaves no copy behind and main's edit alone.
mk dirt2; go dirt2
jq -n --arg t "$TMP" '{testCommand: "pwd > \($t)/check.pwd; false"}' > "$REPO/.claude/commandeck.json"
AFTER=$(head_main)
check "a red check on the copy refuses the merge" 1 "$(merge dirt2)"
check "main did not move, its edit is still there, and the copy is gone" "$AFTER|1|no|$((WTS + 1))" \
  "$(head_main)|$(grep -c "main's own edit" "$REPO/green.txt")|$([ -e "$(cat "$TMP/check.pwd")" ] && echo yes || echo no)|$(git -C "$REPO" worktree list | wc -l | tr -d ' ')"
check "nothing of the unit is left in main but what was there" " M green.txt" "$(git -C "$REPO" status --porcelain | paste -sd'|' -)"
git -C "$REPO" checkout -q -- green.txt; rm -rf "$REPO/node_modules"

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
# The undo of a refused merge removes the files the squash added. A file of
# the owner's that the check staged is not one of them.
rm -f "$REPO/made.txt"; echo mine > "$REPO/mine.txt"
jq -n '{testCommand: "git add mine.txt"}' > "$REPO/.claude/commandeck.json"
check "a merge whose check stages the owner's untracked file is refused" 1 "$(merge rewr)"
check "the owner's file is still there, unstaged, and the squash's own file is gone" "mine|0|no" \
  "$(cat "$REPO/mine.txt" 2>/dev/null)|$(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ')|$([ -e "$REPO/rewr.txt" ] && echo yes || echo no)"
# With no testCommand main may hold its own uncommitted edits to tracked files.
# A commit hook that stages one and then refuses the commit is not the squash:
# the undo put the file back from HEAD and the owner's edit was gone.
rm -f "$REPO/mine.txt"; echo '{}' > "$REPO/.claude/commandeck.json"
echo "owner edit" >> "$REPO/green.txt"
HK=$TMP/hk; mkdir -p "$HK"; git -C "$REPO" config core.hooksPath "$HK"
printf '#!/bin/sh\ngit add green.txt\nexit 1\n' > "$HK/pre-commit"; chmod +x "$HK/pre-commit"
check "a merge whose commit hook refuses is refused" 1 "$(merge rewr)"
check "the owner's edit to a tracked file is still there, unstaged, and the squash's own file is gone" "1|0|no" \
  "$(grep -c 'owner edit' "$REPO/green.txt")|$(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ')|$([ -e "$REPO/rewr.txt" ] && echo yes || echo no)"
# A commit hook that passes but edits and stages code makes a commit nobody
# reviewed or checked: it is taken back, like a check that rewrote the tree.
git -C "$REPO" checkout -q -- green.txt; AFTER=$(head_main)
printf '#!/bin/sh\necho hooked >> rewr.txt && git add rewr.txt\n' > "$HK/pre-commit"
check "a merge whose commit hook changes the commit is refused" 1 "$(merge rewr)"
check "main did not move, nothing is staged, the squash's file is gone, and the cause is named" "$AFTER|0|no|1" \
  "$(head_main)|$(git -C "$REPO" diff --cached --name-only | wc -l | tr -d ' ')|$([ -e "$REPO/rewr.txt" ] && echo yes || echo no)|$(grep -c 'a commit hook changed what was committed (rewr.txt)' "$TMP/out")"
check "a merge refused by its check or its commit hook, or taken back after the hook, is never listed as finished" "0 yes" \
  "$(grep -c '"unit":"rewr"' "$REC") $([ -s "$REC" ] && echo yes || echo no)"
git -C "$REPO" config core.hooksPath /dev/null
# A check that unstages everything (`git reset`) and fails leaves nothing
# staged: the squash's edits and new files are still on disk and still go.
mk rst; echo "the unit's edit" >> "$TMP/ws/rst/green.txt"; git -C "$TMP/ws/rst" commit -qam "feat(rst): edit"; go rst
jq -n '{testCommand: "git reset -q; exit 1"}' > "$REPO/.claude/commandeck.json"
AFTER=$(head_main)
check "a merge whose check unstages the squash and fails is refused" 1 "$(merge rst)"
check "main did not move, its tracked file is as it was, and the squash's new file is gone" "$AFTER|0|no" \
  "$(head_main)|$(git -C "$REPO" diff --name-only | wc -l | tr -d ' ')|$([ -e "$REPO/rst.txt" ] && echo yes || echo no)"
echo '{}' > "$REPO/.claude/commandeck.json"
# Run from a subdirectory with git's diff.relative on, `git diff --name-only`
# lists only that folder's paths: main's edit to a file the merge touches,
# outside it, went unseen, and the refused squash's undo put it back from HEAD.
git -C "$REPO" config diff.relative true; mkdir -p "$REPO/sub"
echo "owner edit" >> "$REPO/green.txt"; AFTER=$(head_main)
check "from a subdirectory, a merge over main's uncommitted edit is refused" 1 \
  "$(echo rst > "$TMP/unit"; (cd "$REPO/sub" && bash "$MERGE" rst) > "$TMP/out" 2>&1; echo $?)"
check "the edit is still there, main did not move, and the refusal names the file" "1|$AFTER|1" \
  "$(grep -c 'owner edit' "$REPO/green.txt")|$(head_main)|$(grep -c 'uncommitted work in green.txt' "$TMP/out")"
git -C "$REPO" checkout -q -- green.txt; git -C "$REPO" config --unset diff.relative; rmdir "$REPO/sub"
# Git overwrites an ignored file without a word. A branch that adds a path the
# owner keeps here ignored (.env) would replace it, and a refused merge's undo
# would then delete it.
echo secret.env >> "$(git -C "$REPO" rev-parse --absolute-git-dir)/info/exclude"; echo mine > "$REPO/secret.env"
mk envu; echo theirs > "$TMP/ws/envu/secret.env"; git -C "$TMP/ws/envu" add -f secret.env; git -C "$TMP/ws/envu" commit -qm "feat(envu): env"; go envu
AFTER=$(head_main)
check "a merge that would overwrite an ignored local file is refused" 1 "$(merge envu)"
check "the owner's ignored file is as it was, main did not move, and the file is named" "mine|$AFTER|1" \
  "$(cat "$REPO/secret.env" 2>/dev/null)|$(head_main)|$(grep -c 'the branch adds secret.env' "$TMP/out")"
echo theirs > "$REPO/secret.env"
check "the same file with the branch's own content is no loss: the merge goes through" 0 "$(merge envu)"

# The dashboard lists what the merge recorded, for the project it merged in and no other. A second project merges
# a unit of the same name under the same home; the collector runs once for each, and the page is run on both.
OTHER=$TMP/other; mkdir -p "$TMP/ws-other"
# A unit name longer than a layout id (80) is a legal name: its merge is recorded and listed like any other.
LONG=$(printf 'u%.0s' $(seq 1 90)); mk "$LONG"; go "$LONG"
check "a unit with a 90-character name merges" 0 "$(merge "$LONG")"
# A checkout elsewhere under the same folder name writes the same file: its line names its own path.
TWIN=$TMP/twin/proj; mkdir -p "$TMP/twin" "$TMP/ws-twin"
for r in "$OTHER" "$TWIN"; do
  git init -q -b main "$r"
  git -C "$r" config user.name t; git -C "$r" config user.email t@t; git -C "$r" config core.hooksPath /dev/null
  echo base > "$r/a.txt"; git -C "$r" add a.txt; git -C "$r" commit -qm base
  printf '%s\n' .claude/settings.local.json .claude/builder-events.jsonl >> "$r/.git/info/exclude"
done
check "a checkout elsewhere with the same folder name merges a unit, into the same record file under its own path" "0 $TWIN" \
  "$(REPO=$TWIN; export COMMANDECK_WORKSPACES=$TMP/ws-twin; mk twin >/dev/null; pass twin 8 adversarial; merge twin) $(tail -1 "$REC" | jq -r 'select(.unit == "twin") | .main')"
# Uninstall rewrites this file for a same-named checkout; the append and the rewrite take one lock, on the home folder.
# While another holds it the merge stands and the line is not written, rather than written into a file being replaced.
BEFORE=$(cksum < "$REC")
flock "$HOME" bash -c "touch '$TMP/held'; while [ ! -e '$TMP/release' ]; do sleep 0.2; done" & HOLDER=$!
while [ ! -e "$TMP/held" ]; do sleep 0.1; done
mk locked >/dev/null; go locked
check "the record's lock held by another: the merge still stands, the record is as it was, and the merge says the build is unlisted" "0 $BEFORE 1" \
  "$(merge locked) $(cksum < "$REC") $(grep -c 'finished-builds record not written' "$TMP/out")"
touch "$TMP/release"; wait "$HOLDER"; rm -f "$TMP/held" "$TMP/release"
check "a second project merges a unit of the same name" 0 \
  "$(REPO=$OTHER; export COMMANDECK_WORKSPACES=$TMP/ws-other; mk green >/dev/null; pass green 7 adversarial; merge green)"
check "it is recorded in the second project's own file, with its own commit, and the first project's record is as it was" "green $(git -C "$OTHER" rev-parse main) $BEFORE" \
  "$(jq -r '[.unit, .sha] | join(" ")' "$HOME/.commandeck/builds/other.jsonl" 2>&1) $(cksum < "$REC")"
# An empty decision ledger in each, so the needs panel has a fresh source and nothing waiting.
snapshot() { # <checkout> <workspaces>: the collector's own reading of one project
  mkdir -p "$1/.claude/metrics"; : > "$1/.claude/metrics/decisions.jsonl"
  env -u COMMANDECK_SCRATCH COMMANDECK_MAIN="$1" COMMANDECK_WORKSPACES="$2" COMMANDECK_DASHBOARD_DIR="$TMP/dash" DASH_NOW="$(date +%s)" \
    bash "$REAL/scripts/dashboard.sh" --project "$TMP/dash/${1##*/}" > "$TMP/dash.out" 2>&1 || { echo "FAIL the collector did not run on $1: $(tail -3 "$TMP/dash.out")"; FAIL=$((FAIL+1)); }
}
mkdir -p "$TMP/dash"; snapshot "$REPO" "$TMP/ws"; snapshot "$OTHER" "$TMP/ws-other"
jq -cs '{updatedAt: (now | todate), sources: {}, home: "proj", projects: add}' "$TMP/dash/proj/project.json" "$TMP/dash/other/project.json" > "$TMP/finished.json"
check "the collector lists each checkout's merged units from its own lines, one row a unit, and the finding the tail left open" \
  "$(jq -r --arg m "$REPO" 'select(.main == $m) | .unit' "$REC" | sort -u | paste -sd' ' -)|green|1" \
  "$(jq -r '[.projects.proj.units.finishedBuilds[].unit] | sort | join(" ")' "$TMP/finished.json")|$(jq -r '[.projects.other.units.finishedBuilds[].unit] | join(" ")' "$TMP/finished.json")|$(jq -r '.projects.proj.units.finishedBuilds[] | select(.unit == "tail") | .open.P2' "$TMP/finished.json")"
# The page on that snapshot needs jsdom, which the plugin does not ship (dashboard-view.test.sh has the rule).
if [ -d "${COMMANDECK_TEST_NODE_MODULES:-}/jsdom" ]; then
  check "the page lists, clears and keeps apart what the merges recorded (merge-unit-local.finished-view.mjs)" 0 \
    "$(COMMANDECK_TEST_FINISHED=$TMP/finished.json node --max-old-space-size=4096 --test "$REAL/scripts/__tests__/merge-unit-local.finished-view.mjs" > "$TMP/view.out" 2>&1; echo $?)"
  [ "$FAIL" = 0 ] || grep -E '^(✖|not ok)|Error|expected|actual' "$TMP/view.out" | head -30
elif [ -n "${CI:-}" ]; then echo "FAIL no jsdom in CI: the page was not run on the merge's record"; FAIL=$((FAIL+1))
else echo "SKIPPED the page on the merge's record: no jsdom; set COMMANDECK_TEST_NODE_MODULES to a node_modules folder that has it"; fi
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
