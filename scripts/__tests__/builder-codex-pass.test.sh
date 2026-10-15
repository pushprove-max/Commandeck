#!/usr/bin/env bash
# builder-codex-pass.sh is all a Builder and its reviewer hear of a round: what
# the pass prints and what its prompt carries. What this pins: the model id a
# family resolves to stays one id when a warning goes to stderr; a pass prints
# the files and lines the round changed and flags a round that changed no code;
# a narrowed pass after main changed the brief reads the whole branch, so the
# new part is reviewed with the old before the closing pass; and the evidence
# file's "Different fix r<N>:" and "Other cases checked r<N>:" lines reach the
# reviewer of round N, and of no other round.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS_SH=$REAL/scripts/builder-codex-pass.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
export HOME=$TMP/home CODEX_HOME=$TMP/codex COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
unset COMMANDECK_MAIN COMMANDECK_ROUTING
REPO=$TMP/proj U=unit
mkdir -p "$HOME" "$TMP/ws" "$TMP/cli" "$TMP/py" "$CODEX_HOME"

# A stub of the Codex plugin that leaves the session record Codex would (as in
# merge-unit-local.test.sh); STUB_THREAD names each pass's threads.
PLUG=$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0
mkdir -p "$PLUG/scripts" "$PLUG/prompts"
printf 'Target: {{TARGET_LABEL}}\nUser focus: {{USER_FOCUS}}\nPrefer one strong finding over several weak ones.\n<structured_output_contract>\nReturn only valid JSON matching the provided schema.\n</structured_output_contract>\n{{REVIEW_COLLECTION_GUIDANCE}}\n{{REVIEW_INPUT}}\n' > "$PLUG/prompts/adversarial-review.md"
cat > "$PLUG/scripts/codex-companion.mjs" <<'JS'
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
const args = process.argv.slice(2);
const cwd = args[args.indexOf("--cwd") + 1], promptFile = args[args.indexOf("--prompt-file") + 1];
const id = `${process.env.STUB_THREAD}-${promptFile.match(/-prompt-(\d+)\.md$/)[1]}`;
const reply = "Clean.\nVERDICT: GO";
const sha = execFileSync("git", ["-C", cwd, "rev-parse", "HEAD"]).toString().trim();
const dir = `${process.env.CODEX_HOME}/sessions/2026/10/14`;
mkdirSync(dir, { recursive: true });
writeFileSync(`${dir}/rollout-2026-10-14T00-00-00-${id}.jsonl`, [
  { type: "session_meta", timestamp: new Date().toISOString(), payload: { id, cwd, git: { commit_hash: sha } } },
  { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: readFileSync(promptFile, "utf8") }] } },
  { type: "event_msg", timestamp: new Date().toISOString(), payload: { type: "task_complete", last_agent_message: reply } },
].map((r) => JSON.stringify(r)).join("\n") + "\n");
process.stdout.write(JSON.stringify({ threadId: id, status: 0, rawOutput: reply }));
JS
printf 'import { writeFileSync } from "node:fs";\nconst a = process.argv.slice(2);\nwriteFileSync(a[a.indexOf("--endpoint") + 1].replace(/^unix:/, ""), "");\nsetInterval(() => {}, 1000);\n' > "$PLUG/scripts/app-server-broker.mjs"
echo 1 > "$PLUG/scripts/commandeck-test-waits"
printf '#!/bin/sh\n[ "$*" = "login status" ]\n' > "$TMP/cli/codex"; chmod +x "$TMP/cli/codex"
# routing.json names the family; the account's model list holds its ids.
printf 'model = "x"\n' > "$CODEX_HOME/config.toml"
printf '{"models":[{"slug":"gpt-5.2-sol"},{"slug":"gpt-6.1-sol"}]}\n' > "$CODEX_HOME/models_cache.json"
jq '.roles["codex-reviewer"].model = "sol"' "$REAL/config/routing.json" > "$TMP/routing.json"
export COMMANDECK_ROUTING=$TMP/routing.json

# A Python with no tomllib (3.10): the proxy check warns on stderr and the cache answers.
printf '#!/usr/bin/env bash\n[ "$*" != "-c import tomllib" ] || exit 1\nexec %q "$@"\n' "$(command -v python3)" > "$TMP/py/python3"; chmod +x "$TMP/py/python3"
OUT=$(PATH=$TMP/py:$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --preflight 2>"$TMP/err")
check "a family resolved from the cache beside a stderr warning is the bare model id" "gpt-6.1-sol" "$(cut -f1 <<<"$OUT")"
check "the warning still goes to stderr" 1 "$(grep -c 'tomllib' "$TMP/err")"

git init -q -b main "$REPO"
git -C "$REPO" config user.name t; git -C "$REPO" config user.email t@t; git -C "$REPO" config core.hooksPath /dev/null
printf 'echo base\n' > "$REPO/a.sh"; git -C "$REPO" add a.sh; git -C "$REPO" commit -qm base
printf '%s\n' .claude/settings.local.json .claude/builder-events.jsonl >> "$REPO/.git/info/exclude"
git -C "$REPO" worktree add -q "$TMP/ws/$U" -b "builder/$U"
W=$TMP/ws/$U B=$TMP/ws/$U/.claude/briefs MAINBRIEF=$REPO/.claude/briefs/$U-builder-brief.md
mkdir -p "$B" "${MAINBRIEF%/*}"; echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$W/.claude/settings.local.json"
# The launcher's brief in main's checkout: a first pass of one reviewer, a small build not launched risky.
printf 'Fix #1.\nbash x/builder-codex-pass.sh %s 1 adversarial\n' "$U" > "$MAINBRIEF"; cp "$MAINBRIEF" "$B/$U.md"
pass() { # <N> <kind>: one pass of the real pass script; what it printed is in $TMP/out
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1 \
    bash "$PASS_SH" "$U" "$1" "$2" >"$TMP/out" 2>"$TMP/err") || { echo "FAIL the $2 pass r$1 did not run: $(cat "$TMP/err")"; FAIL=$((FAIL+1)); }
}
input() { sed -n '/^Review input: /,$p' "$B/$U-r$1-prompt-1.md"; } # <N>: what reviewer 1 of round N was handed below the template

printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
check "a first pass has no earlier pass to count a round from" 0 "$(grep -c '^Changed since' "$TMP/out")"

# A round of one comment line: the pass names the file and its count, and says no code changed.
printf '# fixed: the finding\n' >> "$W/a.sh"
pass 2 review
check "a pass prints the files and line counts the round changed" 1 "$(grep -cx '  a.sh +1 -0' "$TMP/out")"
check "a round of comments only is flagged" 1 "$(grep -c '^No code changed in this round' "$TMP/out")"
check "the round file is a narrowed pass" 1 "$(grep -cx 'Pass: review' "$B/$U-r2-reports.md")"

# Main adds scope to the brief during the fix round; the Builder's evidence says why it took
# another fix than the named one and which other cases it checked, for round 3 only.
printf 'Fix #2, added in the fix round.\n' >> "$MAINBRIEF"
printf 'echo two\n' > "$W/a.sh"
printf 'Different fix r2: an older note.\nDifferent fix r3: the named fix broke the caller in b.sh.\nOther cases checked r3: a.sh and c.sh read the same input.\n' > "$B/$U-evidence.md"
pass 3 review
check "a code round is not flagged" 0 "$(grep -c '^No code changed' "$TMP/out")"
check "after the brief gained scope, the review pass runs as a whole-branch pass and says why" "1 1" \
  "$(grep -cx 'Pass: final' "$B/$U-r3-reports.md") $(grep -c 'changed since the last pass' "$TMP/out")"
check "its prompt is the whole branch against main" "1 1" \
  "$(input 3 | grep -c '^Review input: the closing pass, the whole branch diff') $(input 3 | grep -c '^-echo base$')"
check "the prompt carries this round's different-fix and other-cases lines, and not another round's" "1 1 0" \
  "$(input 3 | grep -cx 'Different fix r3: the named fix broke the caller in b.sh.') $(input 3 | grep -cx 'Other cases checked r3: a.sh and c.sh read the same input.') $(input 3 | grep -c 'r2: an older note')"

# The brief unchanged since: the next review pass is narrowed again.
printf 'echo three\n' > "$W/a.sh"
pass 4 review
check "with the brief unchanged since the last pass, a review pass stays narrowed" "1 0" \
  "$(grep -cx 'Pass: review' "$B/$U-r4-reports.md") $(input 4 | grep -c '^-echo base$')"
check "a pass with no notes for its round carries none" 0 "$(input 4 | grep -cE '^(Different fix|Other cases checked) ')"

# The record of what the brief held is gone after an earlier pass: the pass cannot tell, so it reads the whole branch.
printf 'Fix #3, added in the fix round.\n' >> "$MAINBRIEF"
rm -f "$(git -C "$W" rev-parse --absolute-git-dir)/builder-pass-scope"
printf 'echo four\n' > "$W/a.sh"
pass 5 review
check "with the scope record deleted, a review pass reads the whole branch" 1 "$(grep -cx 'Pass: final' "$B/$U-r5-reports.md")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
