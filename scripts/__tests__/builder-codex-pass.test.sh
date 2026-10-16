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
const reply = process.env.STUB_REPLY || "Clean.\nVERDICT: GO";
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
# The Codex stand-in: signed in by `login status`; a one-word exec request records where it ran and
# fails while $TMP/probe-fail holds a count above 0, the way a revoked sign-in does.
cat > "$TMP/cli/codex" <<EOF
#!/bin/sh
case "\$1" in
  login) [ "\$*" = "login status" ] ;;
  exec) echo "\$PWD" >> "$TMP/probe"; n=\$(cat "$TMP/probe-fail" 2>/dev/null || echo 0)
    [ "\$n" -gt 0 ] || exit 0; echo \$((n - 1)) > "$TMP/probe-fail"; echo 'ERROR: stream disconnected before completion' >&2; exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/cli/codex"
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
printf 'echo base\n' > "$REPO/a.sh"; mkdir -p "$REPO/.claude"; echo '{"reviewLoop":{"maxRounds":"5"}}' > "$REPO/.claude/commandeck.json"
git -C "$REPO" add a.sh .claude/commandeck.json; git -C "$REPO" commit -qm base
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
# A finding only main can fix goes under Main-only (deferred): every later pass is told it is known.
printf '\n## Main-only (deferred)\nthe settings.json entry for the new hook: main edits that file.\n\n## Later heading\nnot deferred.\n' >> "$B/$U-evidence.md"
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
# The pass lock sits in the worktree's git folder, which pp_rm_rf refuses: released through it, it stayed, and every
# later pass of the worktree was refused. A live holder still refuses a pass; a dead one's lock is taken over.
L=$(git -C "$W" rev-parse --absolute-git-dir)/builder-pass.lock
mkdir "$L"; echo $$ > "$L/pid"
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-4 bash "$PASS_SH" "$U" 4 review >/dev/null 2>"$TMP/err")
check "a pass while another holds the lock is refused, and the holder's lock stays" "1 1" \
  "$(grep -c "another pass of $U is still running (pid $$)" "$TMP/err") $(ls "$L/pid" | wc -l | tr -d ' ')"
echo "$(sh -c 'echo $$')" > "$L/pid"
pass 4 review
check "a dead holder's lock is taken over, and the pass releases it" "1 0" \
  "$(grep -cx 'Pass: review' "$B/$U-r4-reports.md") $(ls -d "$L" 2>/dev/null | wc -l | tr -d ' ')"
check "every later pass is handed the evidence file's main-only list as known, and nothing under the next heading" "1 1 1 0" \
  "$(input 3 | grep -c '^Known and deferred to main') $(input 3 | grep -cx 'the settings.json entry for the new hook: main edits that file.') $(input 4 | grep -cx 'the settings.json entry for the new hook: main edits that file.') $(input 4 | grep -c 'not deferred')"
check "with the brief unchanged since the last pass, a review pass stays narrowed" "1 0" \
  "$(grep -cx 'Pass: review' "$B/$U-r4-reports.md") $(input 4 | grep -c '^-echo base$')"
check "a pass with no notes for its round carries none" 0 "$(input 4 | grep -cE '^(Different fix|Other cases checked) ')"

# The record of what the brief held is gone after an earlier pass: the pass cannot tell, so it reads the whole branch.
printf 'Fix #3, added in the fix round.\n' >> "$MAINBRIEF"
rm -f "$(git -C "$W" rev-parse --absolute-git-dir)/builder-pass-scope"
printf 'echo four\n' > "$W/a.sh"
# `codex login status` still says signed in after a revoked sign-in, and the pass then ended
# with no output: a one-word request is the check. Run in the worktree it fires the repo's hooks.
echo 3 > "$TMP/probe-fail"; : > "$TMP/probe"; HEAD5=$(git -C "$W" rev-parse HEAD)
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_PROBE_BACKOFF=0 STUB_THREAD=thr-5 \
  bash "$PASS_SH" "$U" 5 review >"$TMP/out" 2>"$TMP/err"); RC=$?
check "a Codex that fails three one-word requests refuses the pass: no commit, no round file" "1 3 1 no" \
  "$([ "$RC" != 0 ] && echo 1) $(grep -c 'Codex sign-in probe: try' "$TMP/err") $(grep -c 'launch refused: Codex is not signed in' "$TMP/err") \
$([ "$(git -C "$W" rev-parse HEAD)" = "$HEAD5" ] && [ ! -e "$B/$U-r5-reports.md" ] && echo no || echo yes)"
echo 1 > "$TMP/probe-fail"; : > "$TMP/probe"
COMMANDECK_PROBE_BACKOFF=0 pass 5 review
check "one failed try then an answer runs the pass, every try outside the worktree" "2 0" \
  "$(wc -l < "$TMP/probe" | tr -d ' ') $(grep -c "^$W" "$TMP/probe")"
check "with the scope record deleted, a review pass reads the whole branch" 1 "$(grep -cx 'Pass: final' "$B/$U-r5-reports.md")"
# every reviewer is told a new required setting with no deployed-format test blocks the merge.
check "the first and later passes' prompts carry the deployed-format rule" "1 1" \
  "$(grep -c 'format already deployed' "$B/$U-r1-prompt-1.md") $(grep -c 'format already deployed' "$B/$U-r4-prompt-1.md")"
# Every pass asks whether the change hand-builds what the project's paved-road registry or a standard covers,
# and has such a finding cite the registry row.
check "the first and later passes' prompts ask the paved-road question, citing the registry row" "1 1 1 1" \
  "$(grep -c 'hand-build something .claude/paved-road.md or a published standard already covers' "$B/$U-r1-prompt-1.md") $(grep -c 'cites the registry row' "$B/$U-r1-prompt-1.md") $(grep -c 'hand-build something .claude/paved-road.md' "$B/$U-r4-prompt-1.md") $(grep -c 'cites the registry row' "$B/$U-r4-prompt-1.md")"

# the owner's extra rounds for one unit, with no edit to the tracked settings file.
printf 'echo six\n' > "$W/a.sh"
p6() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-6 bash "$PASS_SH" "$U" 6 review >"$TMP/out" 2>"$TMP/err"); echo $?; }
check "round 6 is over the project's 5" "2 1" "$(p6) $(grep -c 'over the 5 rounds' "$TMP/err")"
echo 9 > "$B/$U-review-cap.md"
check "a cap the Builder writes in its own worktree is not read" 2 "$(p6)"
check "review-cap.sh refuses in a Builder worktree" 2 "$(cd "$W" && bash "$REAL/scripts/review-cap.sh" "$U" 9 >/dev/null 2>&1; echo $?)"
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 6 >/dev/null)
check "after review-cap.sh <unit> 6 in main's checkout, round 6 runs" 0 "$(p6)"
check "and neither checkout's tracked files changed" "" \
  "$(git -C "$REPO" status --porcelain --untracked-files=no; git -C "$W" status --porcelain --untracked-files=no)"

# After a NO-GO pass the Builder's own pane takes the fix round in a fresh session (/clear, then a pointer to a
# hand-off file that stands alone): the old session carried the whole build's context into every fix call. Main's
# seat record follows the new session's log, so main-watch reads the new log and not the cleared one.
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 10 >/dev/null)
# A launch refused for a missing evidence line cost a request and a retry. --check is
# the launch's own evidence check (the same function): it names the missing line and exits non-zero, or passes, and
# in both cases stages nothing, commits nothing, never reaches Codex and leaves no pass lock.
printf 'it()\n' > "$W/x.guard.test.ts"; : > "$TMP/probe"; HEAD7=$(git -C "$W" rev-parse HEAD)
chk() { (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --check "$U" 7 review >"$TMP/out" 2>"$TMP/err"); echo $?; }
untouched() { [ "$(git -C "$W" rev-parse HEAD)" = "$HEAD7" ] && [ -z "$(git -C "$W" diff --cached --name-only)" ] && [ ! -e "$B/$U-r7-reports.md" ] \
  && [ ! -s "$TMP/probe" ] && [ ! -e "$L" ] && echo untouched; }
check "--check on an evidence file without the line: it names the line, exits 2, and nothing was staged, committed, locked or sent to Codex" "2 1 untouched" \
  "$(chk) $(grep -c 'Mutation-verified: <what you broke' "$TMP/err") $(untouched)"
echo 'Mutation-verified: emptied the guard test; it went red' >> "$B/$U-evidence.md"
check "--check on a complete evidence file passes, and still stages, commits, locks and runs nothing" "0 1 untouched" \
  "$(chk) $(grep -c '^check ok: ' "$TMP/out") $(untouched)"
SC=$TMP/scratch FB=$TMP/fb; mkdir -p "$SC" "$FB" "$W/x/__tests__"; echo t > "$W/x/__tests__/y.test.sh"
printf '## 1. RULING-PROBE: keep the probe\n' > "$REPO/.claude/briefs/$U-main-rulings.md"
(cd "$W" && COMMANDECK_MAIN=$REPO bash "$PASS_SH" --ack-rulings "$U" >/dev/null 2>&1)
printf 'handle=term_frs\ntask=task_frs\nunit=%s\nrole=builder\nsession=old-sid\n' "$U" > "$SC/seat-$U-builder.txt"
PROJ=$HOME/.claude/projects/$(printf '%s' "$W" | tr -c 'A-Za-z0-9' '-')
# The cleared session's own log names the hand-off too (it read the pass's output); it is not the new one.
mkdir -p "$PROJ"; echo "$B/$U-fix-r7.md" > "$PROJ/old-sid.jsonl"; touch -t 209901010000 "$PROJ/old-sid.jsonl"
# Logs every call; a wait answers FRS_IDLE (1 is Orca's timeout); typing the pointer starts the new session's log.
cat > "$FB/orca-ide" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FRS_CALLS"
case "$*" in
  *"terminal wait"*) exit "${FRS_IDLE:-0}" ;;
  *"--text /clear"*) [ -z "${FRS_SEND_FAILS:-}" ] || { echo "orca: PROBE-REFUSAL" >&2; exit 1; } ;;
  *"Your task spec is the file"*) printf '%s\n' "$*" > "$FRS_PROJ/new-sid.jsonl"; touch -t 209901010000 "$FRS_PROJ/new-sid.jsonl" ;;
esac
exit 0
SH
chmod +x "$FB/orca-ide"
fpass() { # <dir> <round> <kind> <reply> [env...]: one pass from <dir> as the Builder's pane; prints its exit code
  local d=$1 n=$2 k=$3 r=$4; shift 4
  (cd "$d" && env TMPDIR=$TMP PATH=$FB:$TMP/cli:$PATH COMMANDECK_MAIN=$REPO ORCA_TERMINAL_HANDLE=term_frs COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 \
    FRS_CALLS=$TMP/frs-calls FRS_PROJ=$PROJ STUB_THREAD=thr-$n "STUB_REPLY=$r" "$@" bash "$PASS_SH" "$U" "$n" "$k" >"$TMP/out" 2>"$TMP/err"); echo $?
}
helper_done() { for _ in $(seq 100); do grep -qE '^builder-fresh-round: .*(now names|stays in)' "$SC/$U-fix-r$1.log" 2>/dev/null && return; sleep 0.1; done; }
NOGO=$'- [P1] FINDING-PROBE -- a.sh:1 -- it breaks -- bash a.sh\nVERDICT: NO-GO'
printf 'echo seven\n' > "$W/a.sh"
check "a NO-GO pass from the Builder's pane ends 0 and tells the old session to stop" "0 1" \
  "$(fpass "$W" 7 review "$NOGO") $(grep -c '^FIX ROUND 7: end your turn now' "$TMP/out")"
H7=$B/$U-fix-r7.md
check "the hand-off stands alone: brief, evidence, the findings, main's rulings inlined, the task and the touched tests" "1 1 1 1 1 1" \
  "$(grep -c "$B/$U.md\$" "$H7") $(grep -c "$B/$U-evidence.md\$" "$H7") $(grep -c 'FINDING-PROBE' "$H7") $(grep -c 'RULING-PROBE' "$H7") $(grep -c 'Orca task: task_frs' "$H7") $(grep -cF 'x/__tests__/y.test.sh' "$H7")"
# Each fix-round session read the whole brief at start, about 37K cache-write tokens a
# time. The findings say what to fix; the brief stays reachable by path for the finding that needs it.
check "the hand-off does not order the brief or the evidence file read whole at start; both stay reachable by path" "0 0 1 1" \
  "$(grep -ci 'read the brief whole' "$H7") $(grep -ci 'read the evidence file whole' "$H7") $(grep -c "Open it only when a finding needs it: $B/$U.md\$" "$H7") $(grep -c "update it before the next pass: $B/$U-evidence.md\$" "$H7")"
check "the launch after a passing --check is not refused: the guard test is committed with its note" "1 1" \
  "$(git -C "$W" log -1 --format=%B | grep -c '^Mutation-verified: ') $(git -C "$W" ls-files x.guard.test.ts | wc -l | tr -d ' ')"
helper_done 7
check "the pane is waited idle, cleared, then handed the file" "terminal wait,--text /clear,terminal wait,Your task spec is the file" \
  "$(grep -oE 'terminal wait|--text /clear|Your task spec is the file' "$TMP/frs-calls" | uniq | paste -sd, -)"
check "the pointer names the hand-off file" 1 "$(grep -cF "Your task spec is the file $H7." "$TMP/frs-calls")"
check "main's seat record now names the new session, not the cleared one" "session=new-sid" "$(grep '^session=' "$SC/seat-$U-builder.txt" | tail -1)"
rm -f "$TMP/frs-calls"; printf 'echo eight\n' > "$W/a.sh"
check "a pane that never goes idle: the pass still ends 0" 0 "$(fpass "$W" 8 review "$NOGO" FRS_IDLE=1)"
helper_done 8
check "and the helper types nothing and says why" "0 1" \
  "$(grep -c 'terminal send' "$TMP/frs-calls") $(grep -c 'was not idle within 900s; nothing typed' "$SC/$U-fix-r8.log")"
rm -f "$TMP/frs-calls"; printf 'echo nine\n' > "$W/a.sh"
check "a GO pass hands nothing over" "0 0 0" \
  "$(fpass "$W" 9 review 'VERDICT: GO') $(ls "$B/$U-fix-r9.md" 2>/dev/null | wc -l | tr -d ' ') $(cat "$TMP/frs-calls" 2>/dev/null | wc -l | tr -d ' ')"
printf 'echo ten\n' > "$W/a.sh"
check "a NO-GO pass from another pane (its handle not the seat record's) hands nothing over" "0 0 0" \
  "$(fpass "$W" 10 review "$NOGO" ORCA_TERMINAL_HANDLE=term_other) $(ls "$B/$U-fix-r10.md" 2>/dev/null | wc -l | tr -d ' ') $(cat "$TMP/frs-calls" 2>/dev/null | wc -l | tr -d ' ')"
# A hand-off the pane never took reaches main, with Orca's own answer. The send's output went to /dev/null
# and the log was the only trace, so main never heard that fix round 2 of commandeck-speedups-0-7-2 had not started.
rm -f "$TMP/frs-calls"
(cd "$W" && env PATH=$FB:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 FRS_CALLS=$TMP/frs-calls FRS_PROJ=$PROJ FRS_SEND_FAILS=1 \
  timeout 30 bash "$REAL/scripts/builder-fresh-round.sh" term_frs "$H7" > "$TMP/frs.out" 2>&1); R=$?
check "a /clear Orca refuses: exit 1, Orca's answer in the log, and main is told" "1 1 1" \
  "$R $(grep -c 'typing /clear into term_frs failed (orca: PROBE-REFUSAL)' "$TMP/frs.out") $(cat "$TMP/frs-calls" "$SC/queue/main.jsonl" 2>/dev/null | grep -c "fresh round not started: ${H7##*/}")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
