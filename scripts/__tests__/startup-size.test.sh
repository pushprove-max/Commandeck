#!/usr/bin/env bash
# startup-size.sh is the measure behind "every injection under 10 KB": hook
# output past 10240 bytes reaches the model as a 2 KB preview, so a seat over
# the line starts with almost none of its rules and nothing says so. The
# measure must cover all four seats and every prompt, and fail when a project's
# own files push a hook over.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
P=$TMP/proj
mkdir -p "$TMP/home/.claude" "$TMP/bin"
git init -q "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
# No Orca in the measure: the per-prompt hooks must not reach a live one.
printf '#!/usr/bin/env bash\necho "{}"\n' > "$TMP/bin/orca-ide"; chmod +x "$TMP/bin/orca-ide"
size() { (cd "$P" && env -u CLAUDE_PROJECT_DIR PATH="$TMP/bin:$PATH" HOME="$TMP/home" COMMANDECK_SCRATCH="$TMP/scratch" bash "$REAL/scripts/startup-size.sh" "$@" 2>"$TMP/err"); }

OUT=$(size); RC=$?
check "the shipped templates fit every seat" 0 "$RC"
# agent-awareness.sh prints a state once and remembers it. A measure that used
# the owner's memory would leave it there, and a seat measured second in one
# folder would read as smaller than it starts.
mkdir -p "$TMP/busy"; printf '#!/usr/bin/env bash\necho %s\n' "'{\"result\":{\"tasks\":[{\"id\":\"task_1\",\"status\":\"pending\",\"spec\":\"a task\"}]}}'" > "$TMP/busy/orca-ide"; chmod +x "$TMP/busy/orca-ide"
# With the watcher down the hook prints every time and keeps no state: it must read as running.
printf '#!/bin/sh\necho active\n' > "$TMP/busy/systemctl"; chmod +x "$TMP/busy/systemctl"
BUSY=$(cd "$P" && env -u CLAUDE_PROJECT_DIR PATH="$TMP/busy:$PATH" HOME="$TMP/home" COMMANDECK_HOST_OS=Linux COMMANDECK_SCRATCH="$TMP/scratch" bash "$REAL/scripts/startup-size.sh" --per-prompt 2>/dev/null)
check "with an open task the awareness hook prints for main" 1 "$(awk -F'\t' '$1 == "main" && $2 == "agent-awareness.sh" && $3 > 0' <<<"$BUSY" | wc -l | tr -d ' ')"
check "the measure leaves nothing in the owner's awareness state" no "$([ -e "$TMP/home/.cache/commandeck" ] && echo yes || echo no)"
check "all four seats are measured" "builder chief-of-staff main worker" "$(awk -F'\t' '$2 == "total" {print $1}' <<<"$OUT" | sort | paste -sd' ' -)"
check "every SessionStart hook in hooks.json is run for each seat" \
  "$(jq '[.hooks.SessionStart[].hooks[]] | length' "$REAL/hooks/hooks.json")" "$(grep -c "^main	" <<<"$OUT" | awk '{print $1 - 1}')"
check "each seat's total is under 10240" "" "$(awk -F'\t' '$2 == "total" && $3 >= 10240 {print $1}' <<<"$OUT")"
# The four seats differ; a measure that ran one seat four times would not.
check "the seats are measured apart" 4 "$(awk -F'\t' '$2 == "total" {print $3}' <<<"$OUT" | sort -u | wc -l | tr -d ' ')"
check "--role measures that seat alone" "builder" "$(size --role builder | cut -f1 | sort -u)"
size --role nobody >/dev/null; check "an unknown role is a usage error" 2 "$?"

OUT=$(size --per-prompt --role main); RC=$?
check "--per-prompt runs every UserPromptSubmit hook and sums them" \
  "0 $(jq '[.hooks.UserPromptSubmit[].hooks[]] | length' "$REAL/hooks/hooks.json") 1" "$RC $(grep -vc '	total	' <<<"$OUT") $(grep -c '	total	' <<<"$OUT")"

# A project's own startup file over the line fails the measure and names the hook.
head -c 11000 /dev/zero | tr '\0' 'x' > "$P/AGENT_STARTUP.md"
size --role worker >/dev/null; RC=$?
check "a hook over 10240 bytes fails the measure" 1 "$RC"
check "the failure names the hook, the seat and the bytes" 1 "$(grep -c 'agent-startup-context.sh prints [0-9]* bytes as worker, over 10240' "$TMP/err")"

# instruction-lint.py is the doctor's first pass over the same files: two homes
# for one rule and a pinned model version are what drift first.
printf '## Review loop\nuse claude-opus-4-1 here\n' > "$P/AGENT_STARTUP.md"
printf '## Review loop\n' > "$P/CLAUDE.md"
OUT=$(python3 "$REAL/scripts/instruction-lint.py" --repo "$P" --memory-dir "$TMP/none" --global "$TMP/none.md"); RC=$?
check "instruction-lint flags a subject with two homes and a pinned model, and exits 1" "1 2 1" \
  "$RC $(grep -c 'duplicate-subject' <<<"$OUT") $(grep -c 'AGENT_STARTUP.md:2 stale-model claude-opus-4-1' <<<"$OUT")"
rm "$P/CLAUDE.md"; echo 'clean' > "$P/AGENT_STARTUP.md"
python3 "$REAL/scripts/instruction-lint.py" --repo "$P" --memory-dir "$TMP/none" --global "$TMP/none.md" >/dev/null
check "instruction-lint is quiet on clean files" 0 "$?"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
