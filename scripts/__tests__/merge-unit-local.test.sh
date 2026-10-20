#!/usr/bin/env bash
# A Builder's seat ends with its merge, so merge-unit-local.sh writes its token ledger row. Two seats launched
# together in one worktree each have a session log after the launch, and only the seat record's tag tells them
# apart: without it the row could name the sibling's session and count its tokens as the Builder's. Pinned: after a
# GO merge, the Builder's ledger row names the session whose prompt carries the Builder's own tag.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
# An empty HOME: no Codex plugin, no model list, no signed-in CLI.
export HOME=$TMP/home CODEX_HOME=$TMP/codex COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
# Run by hand from a Claude session the merge would detach itself (issue 230); the case for that unsets this.
export COMMANDECK_FOREGROUND=1
unset COMMANDECK_MAIN COMMANDECK_ROUTING
REPO=$TMP/proj
mkdir -p "$HOME" "$TMP/ws" "$TMP/bin"; : > "$TMP/orca-calls"
git init -q -b main "$REPO"
MERGE=$REAL/scripts/merge-unit-local.sh PASS_SH=$REAL/scripts/builder-codex-pass.sh
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
# gh is never the real one: it records its calls and answers only `issue close`, and that fails once gh-fails exists.
printf '#!/usr/bin/env bash\necho "$*" >> "%s/gh-calls"\n[ "$1 $2" = "issue close" ] && [ ! -e "%s/gh-fails" ]\n' "$TMP" "$TMP" > "$TMP/bin/gh"
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
# Signed in, and answers the pass's one-word sign-in probe (codex exec).
printf '#!/bin/sh\n[ "$*" = "login status" ] || [ "$1" = exec ]\n' > "$TMP/cli/codex"; chmod +x "$TMP/cli/codex"
mk() { # <unit> [subject]: a Builder worktree with one commit, its brief and its evidence
  local w=$COMMANDECK_WORKSPACES/$1
  git -C "$REPO" worktree add -q "$w" -b "builder/$1"
  mkdir -p "$w/.claude/briefs"; echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$w/.claude/settings.local.json"
  echo "brief for $1" > "$w/.claude/briefs/$1.md"; echo "evidence for $1" > "$w/.claude/briefs/$1-evidence.md"
  echo built > "$w/$1.txt"; git -C "$w" add "$1.txt"; git -C "$w" commit -qm "${2:-feat($1): the unit}"
}
pass() { # <unit> <N> <kind>: one pass of the real pass script on the unit's worktree
  (cd "$COMMANDECK_WORKSPACES/$1" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-$1-$2 \
    bash "$PASS_SH" "$1" "$2" "$3" >/dev/null 2>"$TMP/pass.err") || { echo "FAIL the $3 pass on $1 did not run: $(cat "$TMP/pass.err")"; FAIL=$((FAIL+1)); }
}
go() { pass "$1" 1 adversarial; } # <unit>: a first pass that ends GO at the unit's tip
merge() { echo "$1" > "$TMP/unit"; (cd "$REPO" && bash "$MERGE" "$@") > "$TMP/out" 2>&1; echo $?; }

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
# A Builder that went on in a fresh session (builder-fresh-round.sh) has a record with one session= line per session;
# its ledger row counts them all, or the tokens of every later phase vanish from the unit's cost.
mk v; PV=$HOME/.claude/projects/$(printf '%s' "$COMMANDECK_WORKSPACES/v" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$PV"
printf 'handle=t_v\ntask=task_v\nunit=v\nrole=builder\nlaunched=%s\ntag=SEAT-TAG-V\nsession=first\nsession=second\n' "$LA" > "$COMMANDECK_SCRATCH/seat-v-builder.txt"
use() { jq -nc --arg t "$(date -u -d "@$2" +%FT%TZ)" --argjson i "$3" '{type: "assistant", timestamp: $t, message: {id: "m\($i)", model: "claude-x", usage: {input_tokens: $i, output_tokens: 10}}}'; }
{ jq -nc --arg t "$(date -u -d "@$((LA + 30))" +%FT%TZ)" '{type: "user", timestamp: $t, message: {content: "Seat tag SEAT-TAG-V: read the brief."}}'; use x $((LA + 31)) 100; } > "$PV/first.jsonl"
use x $((LA + 40)) 200 > "$PV/second.jsonl"
go v
check "a GO merge of v ends 0" 0 "$(merge v)"
check "a Builder's ledger row sums the tokens of every session its record names" "300:20" \
  "$(jq -r 'select(.unit == "v" and .role == "builder") | "\(.tokens.input):\(.tokens.output)"' "$REPO/.claude/metrics/seat-events.jsonl" 2>/dev/null)"

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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
