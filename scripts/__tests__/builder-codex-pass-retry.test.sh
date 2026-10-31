#!/usr/bin/env bash
# builder-codex-pass-retry.test.sh -- issues 511 and 502: a Codex reviewer that meets Codex's capacity is run again, alone, and
# a reviewer that stops for any other reason is not; a refusal names why Codex stopped, and a third start of a pass that
# failed twice the same way on one tree is refused. Its one slow case, the session limit, is last.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# The fixture's stub has no failure modes, so this file writes its own over it. Per reviewer K, $STUB_DIR/plan-K holds one
# mode per try (the last repeats; no file means ok): ok | overloaded (the session ends at capacity, exit 1) | late (the
# same, but the end record lands 2 s after the exit, as Codex writes it) | fail (the session ends on an error message, exit 1)
# | hang (no session, no exit). Each try is logged as `K mode` in $STUB_DIR/calls.
cat > "$PLUG/scripts/codex-companion.mjs" <<'JS'
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync, spawn } from "node:child_process";
const args = process.argv.slice(2);
const cwd = args[args.indexOf("--cwd") + 1], promptFile = args[args.indexOf("--prompt-file") + 1];
const k = promptFile.match(/-prompt-(\d+)\.md$/)[1], dir0 = process.env.STUB_DIR;
const nFile = `${dir0}/n-${k}`, n = (existsSync(nFile) ? Number(readFileSync(nFile, "utf8")) : 0) + 1;
writeFileSync(nFile, String(n));
const plan = existsSync(`${dir0}/plan-${k}`) ? readFileSync(`${dir0}/plan-${k}`, "utf8").split("\n").filter(Boolean) : ["ok"];
const mode = plan[Math.min(n, plan.length) - 1];
appendFileSync(`${dir0}/calls`, `${k} ${mode}\n`);
if (mode === "hang") await new Promise((r) => setTimeout(r, 600000));
const id = `${process.env.STUB_THREAD}-${k}-t${n}`, reply = "Clean.\nVERDICT: GO";
const sha = execFileSync("git", ["-C", cwd, "rev-parse", "HEAD"]).toString().trim();
const dir = `${process.env.CODEX_HOME}/sessions/2026/10/14`;
mkdirSync(dir, { recursive: true });
const file = `${dir}/rollout-2026-10-14T00-00-00-${id}.jsonl`;
const row = (r) => JSON.stringify(r) + "\n";
const end = (payload) => row({ type: "event_msg", timestamp: new Date().toISOString(), payload });
writeFileSync(file, row({ type: "session_meta", timestamp: new Date().toISOString(), payload: { id, cwd, git: { commit_hash: sha } } })
  + row({ type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: readFileSync(promptFile, "utf8") }] } }));
const overloaded = end({ type: "task_complete", last_agent_message: null, error: { codex_error_info: "server_overloaded", message: "at capacity" } });
if (mode === "late") {
  spawn(process.execPath, ["-e", `setTimeout(() => require("fs").appendFileSync(${JSON.stringify(file)}, ${JSON.stringify(overloaded)}), 2000)`], { detached: true, stdio: "ignore" }).unref();
  process.exit(1);
}
if (mode === "overloaded") { writeFileSync(file, readFileSync(file, "utf8") + overloaded); process.exit(1); }
if (mode === "fail") {
  writeFileSync(file, readFileSync(file, "utf8") + end({ type: "task_complete", last_agent_message: null, error: { message: "boom: the stream closed" } }));
  process.exit(1);
}
writeFileSync(file, readFileSync(file, "utf8") + end({ type: "task_complete", last_agent_message: reply }));
process.stdout.write(JSON.stringify({ threadId: id, status: 0, rawOutput: reply }));
JS

STUB_DIR=$TMP/stub; mkdir -p "$STUB_DIR"
GITDIR=$(git -C "$W" rev-parse --absolute-git-dir)
printf '## Risky launch\n' >> "$MAINBRIEF" # three reviewers on a small build
calls() { local c; c=$(grep -c "^$1 " "$STUB_DIR/calls" 2>/dev/null); echo "${c:-0}"; } # <K>: how many tries reviewer K had
plan() { local k=$1; shift; printf '%s\n' "$@" > "$STUB_DIR/plan-$k"; rm -f "$STUB_DIR/n-$k"; } # <K> <mode...>
fresh() { # <tag>: no stub plan, no session or round file of an earlier case, no failure record, and a tree no case had
  rm -rf "$STUB_DIR" "$CODEX_HOME/sessions" "$CODEX_HOME/builder-pass-prompts" "$GITDIR/builder-pass-failed" "$B"/$U-r1-*; mkdir -p "$STUB_DIR"
  printf 'echo %s\n' "$1" >> "$W/a.sh"
}
rpass() { # prints the exit code of pass 1; what it printed is in $TMP/out and $TMP/err
  (cd "$W" && env TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-1 STUB_DIR=$STUB_DIR "COMMANDECK_PASS_SESSION_WAIT=$SESSION_LIMIT" \
    bash "$PASS_SH" "$U" 1 adversarial >"$TMP/out" 2>"$TMP/err"); echo $?
}
SESSION_LIMIT=180
# A record wait of 5 s: the late record of the first case lands 2 s after the companion exits. The reruns wait 0 s.
echo 5 > "$PLUG/scripts/commandeck-test-waits"

# Catches a pass lost to one overload (the host's #3327), and a retry that runs the reviewers that already answered again.
fresh one; plan 2 late ok
RC=$(rpass)
check "capacity_retry_reruns_only_failed_slot (reviewer 2's end record lands 2 s late; only reviewer 2 runs again and the pass ends GO)" "0 1 2 1 1 1" \
  "$RC $(calls 1) $(calls 2) $(calls 3) $(grep -c 'reviewer(s) 2 at capacity' "$TMP/out") $(grep -c '^VERDICT: GO$' "$B/$U-r1-reports.md")"

# Catches a retry with no end: a reviewer that stays at capacity runs 3 times (the first try and the two reruns) and then the pass refuses.
fresh two; plan 2 overloaded
RC=$(rpass)
check "capacity_retry_gives_up_after_last_try (a reviewer at capacity on every try runs 3 times, then the pass refuses naming why)" "2 3 1 1 0" \
  "$RC $(calls 2) $(grep -c 'reviewer 2: server_overloaded' "$TMP/err") $(grep -c 'failed for reviewer(s) 2' "$TMP/err") $(ls "$B"/$U-r1-reports.md 2>/dev/null | wc -l | tr -d ' ')"

# Catches a retry of a real failure: only the capacity error is retried, so another error is not hidden behind a rerun.
fresh three; plan 2 fail ok
RC=$(rpass)
check "other_failure_not_retried (a reviewer that stops on an error message runs once and the pass refuses)" "2 1 1" \
  "$RC $(calls 2) $(grep -c 'failed for reviewer(s) 2' "$TMP/err")"

# Catches a retry that runs because one reviewer was at capacity while another failed for a real reason.
fresh four; plan 1 overloaded ok; plan 2 fail ok
RC=$(rpass)
check "mixed_failure_not_retried (one reviewer at capacity beside one that failed: neither runs again)" "2 1 1" \
  "$RC $(calls 1) $(calls 2)"

# Catches a refusal that says only that a reviewer failed: the Builder must see why Codex stopped, and no advice to run it again.
fresh five; plan 1 fail
RC=$(rpass)
check "the refusal names the stop reason (the error's message, and no 'run the same pass again')" "2 1 0" \
  "$RC $(grep -c 'reviewer 1: boom: the stream closed' "$TMP/err") $(grep -c 'Run the same pass again' "$TMP/err")"

# Catches a blind third start: two failures of one pass on one tree for one reason, and the Builder runs it again.
fresh six; plan 1 fail
rpass >/dev/null; rpass >/dev/null
BEFORE=$(calls 1); RC=$(rpass)
check "a third same failure is refused (before any reviewer starts; it names the reason and ask-main.sh and prints no way past)" "2 $BEFORE 1 1 0" \
  "$RC $(calls 1) $(grep -c 'boom: the stream closed' "$TMP/err") $(grep -c 'ask-main.sh' "$TMP/err") $(grep -c 'builder-pass-failed' "$TMP/err")"

# Catches a record that outlives the tree it was made for: a changed tree is another pass and runs.
printf 'echo seven\n' >> "$W/a.sh"; plan 1 ok
RC=$(rpass)
check "a new tree runs again after a failure (the two failures belonged to the old tree)" "0" "$RC"

# Catches a refusal main cannot lift: main removes the record, and the same tree runs.
fresh eight; plan 1 fail
rpass >/dev/null; rpass >/dev/null; rm -f "$GITDIR/builder-pass-failed"; plan 1 ok
RC=$(rpass)
check "main's reset lets it run (with the record removed the same tree starts again)" "0" "$RC"

# Slowest, so last: a rerun that gets no session stops at the session limit (4 s here) and is not run a third time.
fresh nine; plan 2 overloaded hang
SESSION_LIMIT=4
RC=$(rpass)
check "retry_with_no_session_stops_at_limit (the rerun of a reviewer at capacity gets no session: the pass stops at the limit after 2 tries)" "2 2 1" \
  "$RC $(calls 2) $(grep -c 'no Codex session appeared within 4s' "$TMP/err")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
