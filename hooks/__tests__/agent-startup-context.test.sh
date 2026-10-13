#!/usr/bin/env bash
# agent-startup-context.sh decides what a pane knows before its first turn, by
# seat. A seat that gets another seat's rules acts on them (a Builder told it
# may not run subagents, a worker handed main's rules), and output past 10240
# bytes reaches the model as a 2 KB preview: the seat then starts with almost
# none of it. Each seat's output is checked for what it must and must not carry.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
HOOK=$REAL/hooks/agent-startup-context.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
has() { grep -cF -- "$2" <<<"$1" | sed 's/^[1-9][0-9]*$/yes/; s/^0$/no/'; }
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
P=$TMP/proj
mkdir -p "$TMP/home/.claude" "$P/.claude/rules"
git init -q "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$P" worktree add -q "$TMP/unit-a" -b unit-a 2>/dev/null
git -C "$P" worktree add -q "$TMP/Chief-of-Staff" -b cos 2>/dev/null
printf -- '---\ntrigger: always_on\n---\nWORKER-RULES-BODY\n' > "$P/.claude/rules/worktree-sessions.md"
run() { # cwd [VAR=value...] -- the hook's output in that seat
  local d=$1; shift
  (cd "$d" && env -u COMMANDECK_BUILDER -u COMMANDECK_REVIEWER -u AGENT_KIND -u COMMANDECK_CLEAR_LINE HOME="$TMP/home" \
    CLAUDE_PROJECT_DIR="$P" COMMANDECK_HOOK_FIRE_LOG=/dev/null "$@" bash "$HOOK" </dev/null 2>&1)
}

OUT=$(run "$P")
check "main: the persona is the first line" "# Main persona:" "$(head -1 <<<"$OUT" | cut -c1-15)"
check "main: the plugin's startup file is injected" yes "$(has "$OUT" '## Builder flow')"
check "main: its own rules are injected" yes "$(has "$OUT" 'Main never compacts')"
check "main: the Details section stays on disk" no "$(has "$OUT" "$(sed -n '/^## Details (not injected)/,$p' "$REAL/templates/main-session.md" | sed -n 3p)")"
check "main: worker rules are not injected" no "$(has "$OUT" WORKER-RULES-BODY)"
# Main runs in the project, where `scripts/board.sh` is not a file.
check "main: a plugin script is named by its full path" yes "$(has "$OUT" "bash $REAL/scripts/board.sh")"
check "main: no plugin script is left as a bare repo path" 0 "$(grep -cE '(^|[ `])scripts/[a-z-]+\.sh' <<<"$OUT")"
check "main: the default clear line is named" yes "$(has "$OUT" 'THE CLEAR LINE IS 200K')"
# The standard-context option moves the line; a main told 200K would never checkpoint at 150K.
OUT=$(run "$P" COMMANDECK_CLEAR_LINE=150000)
check "main: a configured clear line replaces the default everywhere" "yes no" "$(has "$OUT" 'THE CLEAR LINE IS 150K') $(has "$OUT" 200K)"

OUT=$(run "$TMP/unit-a")
check "worker: the startup file and the worker rules are injected" "yes yes" "$(has "$OUT" '## Builder flow') $(has "$OUT" WORKER-RULES-BODY)"
check "worker: the rules file's frontmatter is stripped" no "$(has "$OUT" 'trigger: always_on')"
check "worker: main's rules and persona are not injected" "no no" "$(has "$OUT" 'Main never compacts') $(has "$OUT" '# Main persona')"

# The plugin's files and messages name its scripts as `scripts/...`; a session
# runs in the project, where no such folder is. Every seat is told where.
check "worker: told where the plugin's scripts, hooks and templates are" yes "$(has "$OUT" "# Commandeck plugin folder: $(cd "$(dirname "$0")/../.." && pwd).")"
OUT=$(run "$TMP/unit-a" COMMANDECK_BUILDER=1)
check "builder: told where the plugin is too" yes "$(has "$OUT" "# Commandeck plugin folder: $(cd "$(dirname "$0")/../.." && pwd).")"
check "builder: told it is a Builder and where its brief is" yes "$(has "$OUT" 'Build the batch in .claude/briefs/unit-a.md')"
check "builder: worker rules, which deny it subagents, are not injected" no "$(has "$OUT" WORKER-RULES-BODY)"

# The relay pane never reads code: it gets its persona and saved state, cut to
# whole lines with a pointer, and none of the build workflow.
mkdir -p "$TMP/home/.commandeck/chief-of-staff"
{ echo "STATE-FIRST-LINE"; for i in $(seq 1 400); do echo "state line $i padded to some length"; done; } > "$TMP/home/.commandeck/chief-of-staff/proj.md"
echo '{"chiefOfStaff": {"persona": "You are Ada, dry and brief."}, "testCommand": "make test", "buildCommand": "make"}' > "$P/.claude/commandeck.json"
OUT=$(run "$TMP/Chief-of-Staff" ORCA_TERMINAL_HANDLE=term_cos)
check "chief of staff: the configured persona leads" "# Chief of Staff: You are Ada, dry and brief." "$(head -1 <<<"$OUT" | cut -c1-45)"
check "chief of staff: the saved state is injected from its first line" yes "$(has "$OUT" STATE-FIRST-LINE)"
check "chief of staff: a long state is cut with a pointer to the file" yes "$(has "$OUT" "Read the rest from $TMP/home/.commandeck/chief-of-staff/proj.md")"
check "chief of staff: no build workflow; it is still a worker seat under the project's worker rules" "no yes" "$(has "$OUT" '## Builder flow') $(has "$OUT" WORKER-RULES-BODY)"
# It is deaf between turns unless it arms its watchers, and it has no startup
# file to learn them from: the commands must arrive here, by their full path.
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
check "chief of staff: told to arm its inbox poller by full path" yes "$(has "$OUT" "bash $PLUGIN/scripts/cos-watch-inbox.sh")"
# The Stop hook counts only a poller that names this pane: one with no handle may be another project's.
check "chief of staff: the poller is armed with the pane's own handle" yes "$(has "$OUT" "scripts/cos-watch-inbox.sh term_cos\`")"
check "chief of staff: told the other watchers" "yes yes yes" "$(has "$OUT" cos-watch-decisions.sh) $(has "$OUT" cos-watch-alerts.sh) $(has "$OUT" cos-watch-limit.sh)"
check "chief of staff: told how to record the owner's answer and mark it seen" "yes yes" \
  "$(has "$OUT" "bash $PLUGIN/scripts/decision.sh answer") $(has "$OUT" "$TMP/home/.commandeck/chief-of-staff/proj.decisions-seen")"
check "chief of staff: told how to address main" yes "$(has "$OUT" "orca-ide orchestration send")"
check "chief of staff: under the 10240-byte line with a long state" yes "$([ "$(wc -c <<<"$OUT")" -lt 10240 ] && echo yes || echo no)"

OUT=$(run "$TMP/unit-a")
check "the project's test and build commands follow the startup file" "yes yes" "$(has "$OUT" '- Test: `make test`') $(has "$OUT" '- Build: `make`')"
OUT=$(run "$TMP/unit-a" AGENT_KIND=codex)
check "codex: pointed at the file, not handed it" "yes no" "$(has "$OUT" 'read '"$REAL"'/templates/AGENT_STARTUP.md in full') $(has "$OUT" '## Builder flow')"
OUT=$(run "$P" COMMANDECK_REVIEWER=1)
check "a reviewer in the main checkout is not main" no "$(has "$OUT" 'Main never compacts')"

# A project's own files win, untouched: its paths are its own.
echo 'PROJECT-STARTUP run scripts/own.sh' > "$P/AGENT_STARTUP.md"
printf '# Main persona: project.\nPROJECT-MAIN-RULES\n## Details (not injected)\nHIDDEN\n' > "$P/.claude/main-session.md"
OUT=$(run "$P")
check "the project's startup file replaces the template, paths untouched" "yes no" "$(has "$OUT" 'PROJECT-STARTUP run scripts/own.sh') $(has "$OUT" '## Builder flow')"
check "the project's main rules replace the template" "yes no no" "$(has "$OUT" PROJECT-MAIN-RULES) $(has "$OUT" HIDDEN) $(has "$OUT" 'Main never compacts')"
check "the always-on line closes the output" "# always-on context:" "$(tail -1 <<<"$OUT" | cut -c1-20)"

# Setup writes commandeck.json in the main checkout only. A session started in
# a worktree has that worktree as its project directory, and still gets the
# project's test command and the Chief of Staff its persona.
OUT=$(run "$TMP/unit-a" CLAUDE_PROJECT_DIR="$TMP/unit-a")
check "a worker in its own worktree is told the project's test command" yes "$(has "$OUT" 'Test: `make test`')"
OUT=$(run "$TMP/Chief-of-Staff" CLAUDE_PROJECT_DIR="$TMP/Chief-of-Staff" ORCA_TERMINAL_HANDLE=term_cos)
check "the Chief of Staff in its own worktree gets the configured persona" "# Chief of Staff: You are Ada, dry and brief." "$(head -1 <<<"$OUT" | cut -c1-45)"

# The plugin's path goes into the text whole, as one shell word: a # ended the
# sed expression (no startup text at all) and a backslash or & was sed's to read.
ODD=$TMP/'pl#u\g&x y'; mkdir -p "$ODD"; cp -R "$REAL/hooks" "$REAL/templates" "$REAL/scripts" "$REAL/config" "$ODD/"
git init -q "$TMP/fresh" && git -C "$TMP/fresh" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
OUT=$(HOOK=$ODD/hooks/agent-startup-context.sh; run "$TMP/fresh" CLAUDE_PROJECT_DIR="$TMP/fresh")
check "from an odd plugin path the startup file is still injected" yes "$(has "$OUT" '## Builder flow')"
check "and names the plugin's scripts by that path, as one shell word" yes "$(has "$OUT" "$(printf '%q' "$ODD")/scripts/")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
