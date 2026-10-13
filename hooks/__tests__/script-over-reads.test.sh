#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test script-over-reads.sh, the read-sweep nudge.
# Run: bash hooks/__tests__/script-over-reads.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/script-over-reads.sh"
PASS=0; FAIL=0
SID="sweeptest-$$"
TALLY="/tmp/claude-read-families-${SID}"
WARNED="/tmp/claude-read-families-warned-${SID}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" "$TALLY" "$WARNED"' EXIT

mkdir -p "$TMP/briefs" "$TMP/src"
for i in 1 2 3 4 5 6; do touch "$TMP/briefs/unit-$i.md"; done
for i in 1 2 3 4 5 6; do touch "$TMP/src/mod-$i.ts"; done
touch "$TMP/briefs/notes.txt"

reset() { rm -f "$TALLY" "$WARNED"; }

# ADVISORY MEANS EXIT 0. A non-zero advisory shows a Codex seat
# `Script failed` with no text, so the seat redoes the work it was being advised
# about. Any non-zero rc is printed as itself and fails whichever case expects
# `nudge` or `quiet`, which is how this test catches a regression to exit 2.
verdict() {  # reads a hook invocation on stdin-less form; prints nudge/quiet/rc=<n>
  local out=$1 rc=$2
  [ "$rc" -eq 0 ] || { echo "rc=$rc"; return; }
  case "$out" in *"READ SWEEP:"*) echo nudge ;; *) echo quiet ;; esac
}
read_file() {
  local out rc
  out=$(printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$SID" "$1" \
    | "$GATE" 2>&1 >/dev/null); rc=$?
  verdict "$out" "$rc"
}
bash_cmd() {
  local out rc
  out=$(printf '{"session_id":"%s","tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$SID" "$TMP" "$1" \
    | "$GATE" 2>&1 >/dev/null); rc=$?
  verdict "$out" "$rc"
}
ok() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 (got $2, want $3)"; FAIL=$((FAIL+1)); fi; }

# The whole point: four files of one kind are ordinary work, the fifth is a
# sweep. A hook that fired earlier would block every normal multi-file task.
reset
for i in 1 2 3 4; do LAST=$(read_file "$TMP/briefs/unit-$i.md"); done
ok "four files of one kind stay silent" "$LAST" quiet
ok "the fifth file of one kind nudges" "$(read_file "$TMP/briefs/unit-5.md")" nudge

# The advice must reach the model, not just the terminal: on exit 0 the stdout
# JSON is the only channel a session actually reads.
reset
for i in 1 2 3 4; do read_file "$TMP/briefs/unit-$i.md" >/dev/null; done
JSON=$(printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}}' \
  "$SID" "$TMP/briefs/unit-5.md" | "$GATE" 2>/dev/null)
ok "the nudge is native additionalContext" \
  "$(jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"
            and (.hookSpecificOutput.additionalContext | contains("READ SWEEP:"))' \
     <<<"$JSON" >/dev/null 2>&1 && echo 0 || echo 1)" 0

# Once per family: a session that decided to keep reading is not re-nagged on
# every remaining file, which is what makes an advisory nudge tolerable here.
ok "the sixth file does not nudge again" "$(read_file "$TMP/briefs/unit-6.md")" quiet

# Re-reading one file is not a sweep. Counting reads instead of DISTINCT files
# would fire on an agent legitimately re-checking one file after an edit.
reset
for i in 1 2 3 4 5 6; do LAST=$(read_file "$TMP/briefs/unit-1.md"); done
ok "the same file six times is not a sweep" "$LAST" quiet

# Family is directory AND extension. Five files spread over two kinds is a
# mixed handful, which is ordinary work; only one kind piling up is the waste.
reset
for i in 1 2 3; do read_file "$TMP/briefs/unit-$i.md" >/dev/null; done
for i in 1 2 3; do LAST=$(read_file "$TMP/src/mod-$i.ts"); done
ok "three plus three across two families stays silent" "$LAST" quiet
ok "the fourth of one family still stays silent" "$(read_file "$TMP/briefs/unit-4.md")" quiet
ok "the fifth of that family nudges" "$(read_file "$TMP/briefs/unit-5.md")" nudge

# Same directory, different extension is a different family: an extension that
# collapsed into the directory would count a stray .txt toward a .md sweep.
reset
for i in 1 2 3 4; do read_file "$TMP/briefs/unit-$i.md" >/dev/null; done
ok "a different extension does not complete the family" "$(read_file "$TMP/briefs/notes.txt")" quiet

# Shell reads count. Under bypass-permissions workers read with cat/sed/head,
# and a hook blind to those is blind in the seats it exists for.
reset
for i in 1 2 3 4; do bash_cmd "cat briefs/unit-$i.md" >/dev/null; done
ok "the fifth shell read nudges" "$(bash_cmd "sed -n 1,20p briefs/unit-5.md")" nudge

# A shell read and a Read of the same file are one file, not two: double
# counting would fire the nudge halfway through an ordinary task.
reset
for i in 1 2 3 4; do bash_cmd "cat briefs/unit-$i.md" >/dev/null; done
for i in 1 2 3 4; do LAST=$(read_file "$TMP/briefs/unit-$i.md"); done
ok "the same four files by two routes are four files" "$LAST" quiet

# One parallel block can carry the whole sweep, so the check must look at every
# family the call touched, not only the last path in it.
reset
ok "five files in one shell call nudge" \
  "$(bash_cmd "cat briefs/unit-1.md briefs/unit-2.md briefs/unit-3.md briefs/unit-4.md briefs/unit-5.md")" nudge

# A failed read shows the agent nothing, so counting it would push a family
# over the line on files that never entered context.
reset
for i in 1 2 3 4; do read_file "$TMP/briefs/unit-$i.md" >/dev/null; done
ERR=$(printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{"is_error":true}}' \
  "$SID" "$TMP/briefs/unit-5.md" | "$GATE" >/dev/null 2>&1; echo $?)
ok "a failed read does not count" "$ERR" 0

# A write is not a read.
reset
ok "a non-reading tool is ignored" \
  "$(printf '{"session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$SID" "$TMP/briefs/unit-1.md" \
     | "$GATE" >/dev/null 2>&1; echo $?)" 0

# A shell command that is not a read is ignored, or every grep and git call
# would tally the paths it names.
reset
for i in 1 2 3 4 5 6; do LAST=$(bash_cmd "rg pattern briefs/unit-$i.md"); done
ok "a search is not a read" "$LAST" quiet

# The wrapper that runs every self-test in the push gate asserts `0 failed` on
# stdout, so this summary is worded the way its siblings word it.
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
