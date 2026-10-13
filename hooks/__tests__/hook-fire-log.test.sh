#!/usr/bin/env bash
# Self-test for hooks/lib/hook-fire-log.sh and
# scripts/hook-fire-log-summary.sh.
#
# Every hook invocation leaves ONE metadata-only row saying whether it allowed,
# advised or blocked, and the hook's own stdout, stderr and status are exactly
# what they were without the log -- whatever happens to the log. Each case below
# names the change to the helper that would make it fail.
set -u
# The strict-tier hooks used as fixtures below only speak with the tier on.
export COMMANDECK_HOOK_TIER=strict
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
HOOKS=$ROOT/hooks
# The day files are named for the project (lib/project.sh): this checkout's.
. "$HOOKS/lib/project.sh"; pp_project "$ROOT"; P=$PP_PROJECT
T=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$T" /tmp/claude-read-families-hfl-"$$"*' EXIT
export HOME=$T/home
mkdir -p "$HOME"
LOG=$T/log/fires.jsonl
export COMMANDECK_HOOK_FIRE_LOG=$LOG
unset COMMANDECK_REVIEWER AGENT_KIND
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $*"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: want '$2', got '$3'"; fi; }
nrows() { cat "$LOG" 2>/dev/null | wc -l | tr -d ' '; }
last() { tail -1 "$LOG" | jq -r "$1" 2>/dev/null; }
KEYS='["agent","decision","event","hook","ms_body","session_id","timestamp","tool"]'
BKEYS='["agent","decision","event","hook","ms_body","session_id","summary","timestamp","tool","worktree"]'

sid() { # label -> a stable UUID for it: only a UUID-shaped session is stored
  printf '%08x-0000-4000-8000-000000000000' "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
}
pay() { # session-label [event] [tool] -> a hook payload
  jq -cn --arg s "$(sid "$1")" --arg e "${2:-PreToolUse}" --arg t "${3:-Bash}" \
    '{session_id:$s, hook_event_name:$e, tool_name:$t, tool_input:{command:"true"}}'
}
run() { # script payload -> status; stdout and stderr land in $T/out, $T/err
  local rc=0
  printf '%s' "$2" | "$1" >"$T/out" 2>"$T/err" || rc=$?
  echo "$rc"
}
# One row more than before, with the expected decision and the payload's own
# event/tool/session. Changing the helper to always write `allow` fails here.
expect_row() { # label before decision hook session-label event tool
  check "$1: one row" $(($2 + 1)) "$(nrows)"
  check "$1: decision" "$3" "$(last .decision)"
  check "$1: hook" "$4" "$(last .hook)"
  check "$1: metadata" "$(sid "$5")|$6|$7" "$(last '"\(.session_id)|\(.event)|\(.tool)"')"
  if [ "$3" = block ]; then
    check "$1: the six fields plus the block context" "$BKEYS" "$(tail -1 "$LOG" | jq -c 'keys')"
  else
    check "$1: exactly the six fields" "$KEYS" "$(tail -1 "$LOG" | jq -c 'keys')"
  fi
  [[ $(last .timestamp) =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ok || bad "$1: timestamp $(last .timestamp)"
}

# Fixture hooks wired exactly as the real ones are: helper beside them in lib/.
FX=$T/fx
mkdir -p "$FX"
ln -s "$HOOKS/lib" "$FX/lib"
mk() { # name body
  printf '#!/usr/bin/env bash\nINPUT=$(cat)\n. "${BASH_SOURCE[0]%%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"\n%s\n' "$2" > "$FX/$1.sh"
  chmod +x "$FX/$1.sh"
}

# --- 1/2. decisions ------------------------------------------------------------
mk allow-early 'exit 0'
mk allow-implicit 'true'
mk block-exit2 'echo no >&2; exit 2'
mk block-json 'HOOK_FIRE_BLOCK=1; echo "{\"decision\":\"block\",\"reason\":\"r\"}"; exit 0'
mk advise-zero 'HOOK_FIRE_ADVISE=1; echo careful >&2; exit 0'
mk advise-one 'echo "could not run" >&2; exit 1'
mk advise-then-block 'HOOK_FIRE_ADVISE=1; echo careful >&2; exit 2'
# A marker set in a subshell is not the hook's decision, and no subshell or
# command substitution writes a row of its own.
mk subshells '( HOOK_FIRE_BLOCK=1; exit 2 ); x=$(HOOK_FIRE_ADVISE=1; exit 3); echo a | cat >/dev/null; exit 0'
mk strict 'set -euo pipefail; x=$(echo a); ( exit 0 ); echo out; false; echo never'
while read -r name want rc; do
  before=$(nrows)
  check "$name: status" "$rc" "$(run "$FX/$name.sh" "$(pay "s-$name")")"
  expect_row "$name" "$before" "$want" "$name.sh" "s-$name" PreToolUse Bash
done <<'EOF'
allow-early allow 0
allow-implicit allow 0
block-exit2 block 2
block-json block 0
advise-zero advise 0
advise-one advise 1
advise-then-block block 2
subshells allow 0
strict advise 1
EOF
check "strict: stdout kept" out "$(cat "$T/out")"

# The row says how long the hook ran, how long it waited on a lock or a job it
# could see, and which agent ran it, so a slow guard and its agent are found in
# the log instead of by timing panes.
mk slow 'sleep 0.3; exit 0'
mk waited 'HOOK_FIRE_WAIT_MS=1500; exit 2'
mk badwait 'HOOK_FIRE_WAIT_MS=12x; exit 0'
run "$FX/slow.sh" "$(pay s-slow)" >/dev/null
[ "$(last .ms_body)" -ge 290 ] 2>/dev/null && ok || bad "ms_body: a 300 ms hook body recorded '$(last .ms_body)'"
check "agent: Claude unless told otherwise" claude "$(last .agent)"
run "$FX/waited.sh" "$(pay s-waited)" >/dev/null
check "wait_ms: the wait the hook measured" 1500 "$(last .wait_ms)"
run "$FX/badwait.sh" "$(pay s-badwait)" >/dev/null
check "wait_ms: a value that is not an integer is not stored" false "$(tail -1 "$LOG" | jq 'has("wait_ms")')"
AGENT_KIND=codex run "$FX/allow-early.sh" "$(pay s-codex)" >/dev/null
check "agent: AGENT_KIND=codex is Codex" codex "$(last .agent)"
run "$FX/allow-early.sh" '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_use_id":"exec-42"}' >/dev/null
check "agent: a Codex exec- call id is Codex" codex "$(last .agent)"

# Real hooks: exit-0 advice is advice and an exit-0 JSON refusal is a block, so
# inferring "exit 0 means allow" fails here.
before=$(nrows)
run "$HOOKS/web-fetch-blocker.sh" "$(jq -cn --arg s "$(sid w1)" '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"WebFetch",tool_input:{url:"https://example.com"}}')" >/dev/null
expect_row "web-fetch advisory" "$before" advise web-fetch-blocker.sh w1 PreToolUse WebFetch

git init -q "$T/main" && git -C "$T/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
jq -cn '{type:"assistant",message:{content:[{type:"text",text:"Done with phase 1. Shall I proceed?"}]}}' > "$T/transcript.jsonl"
before=$(nrows)
rc=0; (cd "$T/main" && jq -cn --arg t "$T/transcript.jsonl" --arg s "$(sid o1)" '{session_id:$s,hook_event_name:"Stop",transcript_path:$t}' \
  | COMMANDECK_SEAT_MODEL=opus "$HOOKS/opus-orchestrator-autonomy.sh" --stop >"$T/out" 2>"$T/err") || rc=$?
check "opus stop guard: exit 0" 0 "$rc"
check "opus stop guard: JSON block on stdout" block "$(jq -r .decision "$T/out")"
expect_row "opus JSON block" "$before" block opus-orchestrator-autonomy.sh o1 Stop ""

# Advice raised in script-over-reads.sh's parent-shell loop reaches the row.
mkdir -p "$T/sweep"
for i in 1 2 3 4 5; do
  : > "$T/sweep/f$i.txt"
  before=$(nrows)
  run "$HOOKS/script-over-reads.sh" "$(jq -cn --arg p "$T/sweep/f$i.txt" --arg s "$(sid "hfl-$$")" \
    '{session_id:$s,hook_event_name:"PostToolUse",tool_name:"Read",tool_input:{file_path:$p},tool_response:{}}')" >/dev/null
  [ "$i" = 5 ] && want=advise || want=allow
  expect_row "read sweep call $i" "$before" "$want" script-over-reads.sh "hfl-$$" PostToolUse Read
done

# new-test-file-guard.sh: node's advice is classified by its structured field,
# never by text, and node's stdout reaches the harness byte for byte.
git -C "$T/main" worktree add -q "$T/wt" 2>/dev/null
mkdir -p "$T/fakenode"
printf '#!/bin/sh\nprintf "%%s" "$FAKE_NODE_OUT"\nexit "${FAKE_NODE_RC:-0}"\n' > "$T/fakenode/node"
chmod +x "$T/fakenode/node"
NT=$(jq -cn --arg p "$T/wt/src/new.test.ts" --arg s "$(sid n1)" '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')
ADV='{"systemMessage":"ADVISORY: x","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"ADVISORY: x"}}'
while IFS='|' read -r label out want; do
  printf '%s' "$out" > "$T/want"
  before=$(nrows)
  rc=0; printf '%s' "$NT" | PATH="$T/fakenode:$PATH" CLAUDE_PROJECT_DIR="$T/wt" FAKE_NODE_OUT="$out" \
    "$HOOKS/new-test-file-guard.sh" >"$T/out" 2>/dev/null || rc=$?
  check "new-test $label: status" 0 "$rc"
  cmp -s "$T/want" "$T/out" && ok || bad "new-test $label: stdout changed: $(od -c "$T/out" | head -3)"
  expect_row "new-test $label" "$before" "$want" new-test-file-guard.sh n1 PreToolUse Write
done <<EOF
structured advice|$ADV|advise
no output||allow
the word in a message only|{"systemMessage":"additionalContext"}|allow
EOF
before=$(nrows)
printf '%s' "$NT" | PATH="$T/fakenode:$PATH" CLAUDE_PROJECT_DIR="$T/wt" FAKE_NODE_OUT="$ADV
" "$HOOKS/new-test-file-guard.sh" >"$T/out" 2>/dev/null
printf '%s\n' "$ADV" > "$T/want"
cmp -s "$T/want" "$T/out" && ok || bad "new-test: trailing newline of node's output lost"

# --- 3. the hook's own output and status never change ----------------------------
# Baseline: the same hooks with no helper on disk at all.
NOHELPER=$T/nohelper
mkdir -p "$NOHELPER"
cp "$HOOKS"/*.sh "$NOHELPER/" && cp -R "$HOOKS/lib" "$NOHELPER/lib" && rm "$NOHELPER/lib/hook-fire-log.sh"
NODEP=$T/nodep   # a hook whose OWN dependency is missing: the load-failure block
mkdir -p "$NODEP"
cp "$HOOKS"/*.sh "$NODEP/" && cp -R "$HOOKS/lib" "$NODEP/lib" && rm "$NODEP/lib/edit-payload.sh"
NODEP_BASE=$T/nodep-base
mkdir -p "$NODEP_BASE"
cp "$NODEP"/*.sh "$NODEP_BASE/" && cp -R "$NODEP/lib" "$NODEP_BASE/lib" && rm "$NODEP_BASE/lib/hook-fire-log.sh"
: > "$T/not-a-dir"
mkdir -p "$T/a-dir"
WARNSRC='const token = "abcdefghijk";'
CASES=(
  "web-fetch-blocker.sh|$(jq -cn '{session_id:"p",hook_event_name:"PreToolUse",tool_name:"WebFetch",tool_input:{url:"https://e.x"}}')|advise"
  "agent-model-guard.sh|$(jq -cn '{session_id:"p",hook_event_name:"PreToolUse",tool_name:"Agent",tool_input:{model:"sonnet",subagent_type:"debugger"}}')|allow"
  "git-safety.sh|$(pay p)|allow"
  "literal-secret-warning.sh|$(jq -cn --arg c "$WARNSRC" '{session_id:"p",hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:"/x/a.ts",content:$c}}')|advise"
)
for c in "${CASES[@]}"; do
  IFS='|' read -r hook payload want <<<"$c"
  run "$NOHELPER/$hook" "$payload" > "$T/rc0"; cp "$T/out" "$T/out0"; cp "$T/err" "$T/err0"
  for variant in healthy no-directory log-is-a-directory; do
    before=$(nrows)
    case $variant in
      healthy)            rc=$(run "$HOOKS/$hook" "$payload") ;;
      no-directory)       rc=$(COMMANDECK_HOOK_FIRE_LOG=$T/not-a-dir/fires.jsonl run "$HOOKS/$hook" "$payload") ;;
      log-is-a-directory) rc=$(COMMANDECK_HOOK_FIRE_LOG=$T/a-dir run "$HOOKS/$hook" "$payload") ;;
    esac
    check "$hook $variant: status" "$(cat "$T/rc0")" "$rc"
    cmp -s "$T/out0" "$T/out" && ok || bad "$hook $variant: stdout changed"
    cmp -s "$T/err0" "$T/err" && ok || bad "$hook $variant: stderr changed: $(head -2 "$T/err")"
    if [ "$variant" = healthy ]; then check "$hook: decision" "$want" "$(last .decision)"
    else check "$hook $variant: no row" "$before" "$(nrows)"; fi
  done
done
# The hook's own missing dependency is still a block, logged, output unchanged.
p=$(jq -cn --arg s "$(sid d)" '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:"/x/a.ts",content:"x"}}')
rc0=$(run "$NODEP_BASE/literal-secret-warning.sh" "$p"); cp "$T/err" "$T/err0"
before=$(nrows)
check "missing edit-payload: status unchanged" "$rc0" "$(run "$NODEP/literal-secret-warning.sh" "$p")"
cmp -s "$T/err0" "$T/err" && ok || bad "missing edit-payload: stderr changed"
expect_row "missing edit-payload" "$before" block literal-secret-warning.sh d PreToolUse Write

# --- 4. nothing but the six fields is ever stored --------------------------------
S=SENTINEL-HFL-7f3a
before=$(nrows)
run "$FX/allow-early.sh" "$(jq -cn --arg s "$S" '{session_id:"sess\"},{\"x\":1}\n{", hook_event_name:"PreToolUse",
  tool_name:"Bash", prompt:("p " + $s + " \"q\"\n"), tool_input:{command:("echo " + $s), content:("c\n" + $s)},
  transcript_path:("/tmp/" + $s), tool_response:{stdout:$s}, reason:("r " + $s), cwd:("/x/" + $s)}')" >/dev/null
check "injection: one physical line" $((before + 1)) "$(nrows)"
check "injection: the plain fields only" "$KEYS" "$(tail -1 "$LOG" | jq -c keys)"
check "injection: a session that is not a plain token is dropped, not escaped" "" "$(last .session_id)"
run "$FX/allow-early.sh" "$(jq -cn '{session_id:123, hook_event_name:["Stop"], tool_name:{a:1}}')" >/dev/null
check "non-string metadata is dropped" '||' "$(last '"\(.session_id)|\(.event)|\(.tool)"')"
# Each field is kept only in its own shape; anything else is stored as "".
run "$FX/allow-early.sh" '{"session_id":"real-session","hook_event_name":"preToolUse","tool_name":"9tool"}' >/dev/null
check "shapes: a non-UUID session, a lowercase event, a non-identifier tool are dropped" '||' "$(last '"\(.session_id)|\(.event)|\(.tool)"')"
run "$FX/allow-early.sh" "{\"session_id\":\"$(sid shape)\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"mcp__serena__find_symbol\"}" >/dev/null
check "shapes: a UUID, an event, an MCP tool are kept" "$(sid shape)|PostToolUse|mcp__serena__find_symbol" "$(last '"\(.session_id)|\(.event)|\(.tool)"')"
printf -v t96 'T%095d' 0
run "$FX/allow-early.sh" "{\"tool_name\":\"$t96\"}" >/dev/null
check "shapes: a 96-character tool is kept" "$t96" "$(last .tool)"
run "$FX/allow-early.sh" "{\"tool_name\":\"${t96}x\"}" >/dev/null
check "shapes: a 97-character tool is dropped" "" "$(last .tool)"
run "$FX/allow-early.sh" "$(jq -cn '{session_id:("\u0001" * 4000), hook_event_name:("é" * 4000), tool_name:("\"" * 4000)}')" >/dev/null
[ "$(tail -1 "$LOG" | wc -c)" -le 2048 ] && ok || bad "a row stays under 2 KiB: $(tail -1 "$LOG" | wc -c)"
run "$FX/allow-early.sh" 'not json at all' >/dev/null
check "malformed payload still logs" allow "$(last .decision)"
grep -l "$S" "$LOG" 2>/dev/null && bad "a sentinel reached the log" || ok

# --- 5. day files, 8-day retention, permissions -----------------------------------
ROT=$T/rot/fires.jsonl
COMMANDECK_HOOK_FIRE_LOG=$ROT run "$FX/allow-early.sh" "$(pay r0)" >/dev/null
check "new log dir is 0700" 700 "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$T/rot")"
check "new log file is 0600" 600 "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$ROT")"
age() { # file days -> its mtime moved that many days back
  python3 -c 'import os,sys,time; t = time.time() - float(sys.argv[2]) * 86400; os.utime(sys.argv[1], (t, t))' "$1" "$2"
}
writes() { # count -> that many appends through the helper's own writer, in one shell
  ( . "$HOOKS/lib/hook-fire-log.sh"; hook_fire_log_arm "$(pay w)"; trap - EXIT
    for ((i = 0; i < $1; i++)); do _hook_fire_log_write allow; done )
}
# The default log is one file per UTC day, and a day file past 8 days is
# deleted, so the log always covers the last week however busy it was. The
# delete is sampled one write in 16: 200 writes miss every sample with odds of
# (15/16)^200, about 1 in 400000.
DD=$T/days/.claude/hook-fire-log
mkdir -p "$DD"
for f in $P.2020-01-01.jsonl $P.2020-01-09.jsonl other.2020-01-01.jsonl $P.jsonl; do
  echo '{}' > "$DD/$f"; age "$DD/$f" 10
done
age "$DD/$P.2020-01-09.jsonl" 2
# The override names one exact file (every self-test uses it): nothing beside it is deleted.
COMMANDECK_HOOK_FIRE_LOG=$DD/override.jsonl writes 200
check "override: the rows go to that one file" 200 "$(wc -l < "$DD/override.jsonl" | tr -d ' ')"
[ -e "$DD/$P.2020-01-01.jsonl" ] && ok || bad "override: a day file was deleted"
( unset COMMANDECK_HOOK_FIRE_LOG; HOME=$T/days writes 200 )
DAYF=$(ls "$DD" | grep -E "^$P\.[0-9]{4}-[0-9]{2}-[0-9]{2}\.jsonl\$" | grep -v '\.2020-')
check "day file: named for the UTC day of its rows, every row in it" \
  "$P.$(jq -r '.timestamp[:10]' "$DD/$DAYF" 2>/dev/null | sort -u).jsonl|200" "$DAYF|$(wc -l < "$DD/$DAYF" | tr -d ' ')"
check "retention: a day file past 8 days is deleted; a recent one, other names and the old single log stay" \
  "$(printf '%s\n' other.2020-01-01.jsonl override.jsonl "$P.2020-01-09.jsonl" "$DAYF" "$P.jsonl" | LC_ALL=C sort | paste -sd, -)" "$(ls "$DD" | LC_ALL=C sort | paste -sd, -)"

# NO PROCESS PER HOOK: with nothing but tracing stubs on PATH, an armed hook
# starts none on the write path (the sampled retention find runs only on the
# default path, which this test never writes).
mkdir -p "$T/trace"
# One cksum per fingerprinted call is the only other process (main ruling
# 2026-10-10: hash the whole action). The npm stub only answers the summary's
# installed-command lookup, which finds it on PATH without running it.
for c in python3 python jq node cat date mkdir mv rmdir find wc stat sed awk cksum md5 shasum sha1sum npm; do
  printf '#!/bin/sh\necho %s >> "%s/calls"\ncase %s in wc|cksum) exec /usr/bin/%s "$@" ;; esac\n' "$c" "$T" "$c" "$c" > "$T/trace/$c"
done
chmod +x "$T/trace/"*
# An ordinary call with a tool_use_id, its session holding no block marker,
# spawns no hash.
printf '%s\n' "INPUT='{\"session_id\":\"$(sid np)\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"ls\"},\"tool_use_id\":\"toolu_ok\"}'" \
  '. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"' 'exit 0' > "$FX/noproc.sh"
before=$(nrows)
# A block on a call with a tool_use_id builds its context and fingerprint with
# builtins too.
printf '%s\n' "INPUT='{\"session_id\":\"np\",\"hook_event_name\":\"PreToolUse\",\"cwd\":\"/w/x\",\"tool_input\":{\"command\":\"npm test --body s\"},\"tool_use_id\":\"toolu_np\"}'" \
  '. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"' 'exit 2' > "$FX/noproc-block.sh"
for i in $(seq 1 25); do PATH=$T/trace "$BASH" "$FX/noproc.sh"; PATH=$T/trace "$BASH" "$FX/noproc-block.sh"; done
check "no process: a block row carries its context" 'x|npm|toolu_np' "$(last '"\(.worktree)|\(.summary)|\(.use)"')"
check "no process: every call wrote its row" $((before + 50)) "$(nrows)"
check "no process: nothing but the fingerprint ran" "" "$(grep -v -e '^cksum$' "$T/calls" 2>/dev/null | sort -u | paste -sd, -)"
check "no process: one cksum per block, none for an ordinary call" 25 "$(grep -c '^cksum$' "$T/calls" 2>/dev/null)"

# Concurrent writers: every committed row is whole, none interleaved.
before=$(nrows)
pids=()
for i in $(seq 1 16); do run "$FX/allow-early.sh" "$(pay "c$i")" >/dev/null & pids+=($!); done
wait "${pids[@]}"
n=$(( $(nrows) - before ))
[ "$n" -ge 1 ] && [ "$n" -le 16 ] && ok || bad "concurrent: $n rows from 16 writers"
check "concurrent: every row parses with the plain fields" "$(nrows)" "$(jq -c 'select(keys - ["call","summary","use","wait_ms","worktree"] == '"$KEYS"')' "$LOG" | wc -l | tr -d ' ')"

# (7. main and a worktree sharing one log is project-keyed-logs.test.sh's.)

# --- 9. the summary ---------------------------------------------------------------
S_ROOT=$T/sum
mkdir -p "$S_ROOT/scripts" "$S_ROOT/hooks" "$T/clock"
cp -R "$HOOKS/lib" "$S_ROOT/hooks/lib"
cp "$ROOT/scripts/hook-fire-log-summary.sh" "$S_ROOT/scripts/"
cat > "$S_ROOT/hooks/hooks.json" <<'JSON'
{ "hooks": {
  "PreToolUse": [
    { "matcher": "Bash", "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/hooks/a.sh" },
                                    { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/b.sh\" --flag" } ] },
    { "matcher": "Edit", "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/hooks/a.sh" } ] } ],
  "Stop": [ { "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/never.sh\"" } ] } ] } }
JSON
NOW=1790000000
printf '#!/bin/sh\necho %s\n' "$NOW" > "$T/clock/date" && chmod +x "$T/clock/date"
iso() { python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
CUT=$((NOW - 7 * 86400))
r() { # epoch hook decision [ms] [agent]
  jq -cn --arg t "$(iso "$1")" --arg h "$2" --arg d "$3" --arg m "${4:-}" --arg a "${5:-}" \
    '{timestamp:$t,hook:$h,event:"PreToolUse",tool:"Bash",decision:$d,session_id:"s"}
     + (if $m != "" then {ms_body: ($m | tonumber)} else {} end) + (if $a != "" then {agent: $a} else {} end)'; }
SLOG=$T/sum/fires.jsonl
{ r $((CUT - 1)) old.sh allow 500 claude; r "$CUT" a.sh block 10 codex
  r $((CUT + 10)) a.sh allow 30 claude; r $((NOW - 5)) a.sh advise 20 claude; r $((NOW - 4)) b.sh block; r $((NOW - 3)) gone.sh allow
  r $((NOW + 60)) a.sh block 999 codex; printf '{"timestamp":"2026-'; } > "$SLOG"
summary() { PATH="$T/clock:$PATH" COMMANDECK_HOOK_FIRE_LOG=$1 bash "$S_ROOT/scripts/hook-fire-log-summary.sh" "${@:2}"; }
OUT=$(summary "$SLOG" 7)
row() { jq -c --arg h "$1" '.hooks[] | select(.hook == $h) | [.registered, .fires, .blocks, .advises]' <<<"$OUT"; }
check "summary: inclusive cutoff, no future row" '[true,3,1,1]' "$(row a.sh)"
# Which guards cost the most time, and how each agent meets them: nearest-rank
# p50/p95 and the total of the window's rows that carry ms.
check "summary: ms_body p50, p95 and total over the window" '[20,30,60]' "$(jq -c '.hooks[] | select(.hook == "a.sh") | [.ms_body_p50, .ms_body_p95, .ms_body_total]' <<<"$OUT")"
check "summary: no ms_body in the window is null, never zero" '[null,null,null]' "$(jq -c '.hooks[] | select(.hook == "b.sh") | [.ms_body_p50, .ms_body_p95, .ms_body_total]' <<<"$OUT")"
check "summary: fires and blocks split by agent" '{"claude":{"fires":2,"blocks":0},"codex":{"fires":1,"blocks":1}}' \
  "$(jq -c '.hooks[] | select(.hook == "a.sh") | .by_agent' <<<"$OUT")"
# With no override the summary reads the day files whose day is in the window,
# and never the retired single log or its .1 generation.
(
  unset COMMANDECK_HOOK_FIRE_LOG
  export HOME=$T/sumhome
  D=$HOME/.claude/hook-fire-log
  mkdir -p "$D"
  r $((NOW - 2)) inday.sh allow > "$D/$P.$(iso "$CUT" | cut -c1-10).jsonl"
  { r $((CUT - 86400)) beforeday.sh allow; r $((NOW - 2)) beforeday.sh allow; } > "$D/$P.$(iso $((CUT - 86400)) | cut -c1-10).jsonl"
  r $((CUT - 9 * 86400)) legacy.sh allow | tee "$D/$P.jsonl" > "$D/$P.jsonl.1"
  PATH="$T/clock:$PATH" bash "$S_ROOT/scripts/hook-fire-log-summary.sh" 7 | jq -r '"\([.hooks[] | select(.fires > 0) | .hook] | join(","))|\(.earliest_retained)|\(.days)"'
) > "$T/sumdays.out"
# The older day file is never counted, but it is what the log still retains;
# days stays the window asked for, on the default path as on the override.
check "summary: day files from the cutoff day on are counted; earliest_retained is the oldest day file's" \
  "inday.sh|$(iso $((CUT - 86400)))|7" "$(cat "$T/sumdays.out")"
check "summary: an argument does not split a registration" '[true,1,1,0]' "$(row b.sh)"
check "summary: a registered hook that never fired is a zero row" '[true,0,0,0]' "$(row never.sh)"
check "summary: a fired hook no longer registered is listed, marked" '[false,1,0,0]' "$(row gone.sh)"
check "summary: out-of-window rows are not listed" "" "$(row old.sh)"
check "summary: registrations deduplicated" 1 "$(jq '[.hooks[] | select(.hook == "a.sh")] | length' <<<"$OUT")"
check "summary: window and retention" "$(iso "$CUT")|$(iso $((CUT - 1)))|7" "$(jq -r '"\(.window_start)|\(.earliest_retained)|\(.days)"' <<<"$OUT")"
check "summary: the zero-fire query" never.sh "$(jq -r '.hooks[] | select(.registered and .fires == 0) | .hook' <<<"$OUT")"
OUT=$(summary "$T/sum/missing.jsonl")
check "summary: no log, every registered hook at zero" '3|0|null' "$(jq -r '"\(.hooks | length)|\([.hooks[].fires] | add)|\(.earliest_retained)"' <<<"$OUT")"
summary "$SLOG" 0 >/dev/null 2>&1
check "summary: days must be a positive integer" 2 "$?"

# --- 10. after a block: the same call again, or something else -----------
# Rows from the real writer. Every hook on one call shares its tool_use_id, so
# only a row with a NEW id is the session's next call; its call fingerprint
# equal to the blocked one is an identical retry, anything else a workaround.
RLOG=$T/retry/fires.jsonl
call() { # script session-label tool_use_id command
  COMMANDECK_HOOK_FIRE_LOG=$RLOG run "$1" "$(jq -cn --arg s "$(sid "$2")" --arg u "$3" --arg c "$4" \
    '{session_id:$s, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}, tool_use_id:$u}')" >/dev/null
}
call "$FX/block-exit2.sh" ra toolu_a1 'npm test'
call "$FX/allow-early.sh" ra toolu_a1 'npm test'
call "$FX/block-exit2.sh" rb toolu_b1 'npm test'
call "$FX/allow-early.sh" ra toolu_a2 'npm test'
call "$FX/allow-early.sh" rb toolu_b2 'npm run test:changed'
call "$FX/block-exit2.sh" rc toolu_c1 'aaaa'
call "$FX/allow-early.sh" rc toolu_c2 'aaab'
COMMANDECK_HOOK_FIRE_LOG=$RLOG run "$FX/block-exit2.sh" "$(pay rd)" >/dev/null
# The id is not the action: a longer id on the same command is still a retry.
call "$FX/block-exit2.sh" re toolu_e1 'npm test'
call "$FX/allow-early.sh" re toolu_e22 'npm test'
# Past the 4 KiB head the input's end still tells two same-length calls apart.
printf -v PAD '%4100s' ''
call "$FX/block-exit2.sh" rf toolu_f1 "echo ${PAD}a"
call "$FX/allow-early.sh" rf toolu_f2 "echo ${PAD}b"
check "retry: every PreToolUse row with a tool_use_id carries its id" 11 "$(jq -c 'select(.use)' "$RLOG" | wc -l | tr -d ' ')"
check "retry: only blocks and each session's next call pay for a hash" "toolu_a1,toolu_a2,toolu_b1,toolu_b2,toolu_c1,toolu_c2,toolu_e1,toolu_e22,toolu_f1,toolu_f2" \
  "$(jq -r 'select(.call) | .use' "$RLOG" | sort | paste -sd, -)"
check "retry: the next call empties its session's marker" 0 "$(cat "$T"/retry/pending/* | wc -c | tr -d ' ')"
check "retry: a same-length command is a different call" false "$(jq -rs '[.[] | select(.use == "toolu_c1" or .use == "toolu_c2") | .call] | unique | length == 1' "$RLOG")"
OUT=$(COMMANDECK_HOOK_FIRE_LOG=$RLOG bash "$S_ROOT/scripts/hook-fire-log-summary.sh" 1)
check "retry: per guard blocks, identical retries, workarounds; no id is neither" '[6,2,3]' \
  "$(jq -c '.hooks[] | select(.hook == "block-exit2.sh") | [.blocks, .retried_identical, .worked_around]' <<<"$OUT")"

# --- A Builder's refused call. A refused call never runs, so nothing
#     else ends it in the worktree's event log: both block shapes write the end
#     by the call's id, an allowed call writes nothing, and a worktree with no
#     Builder log never gains one. ---
BW=$T/bw; mkdir -p "$BW/.claude" "$T/plain/.claude"; : > "$BW/.claude/builder-events.jsonl"
bp() { jq -cn --arg u "$1" '{session_id:"s", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"x"}, tool_use_id:$u}'; }
COMMANDECK_BUILDER='' CLAUDE_PROJECT_DIR=$BW run "$FX/block-exit2.sh" "$(bp toolu_b1)" >/dev/null
COMMANDECK_BUILDER='' CLAUDE_PROJECT_DIR=$BW run "$FX/block-json.sh" "$(bp toolu_b2)" >/dev/null
COMMANDECK_BUILDER='' CLAUDE_PROJECT_DIR=$BW run "$FX/allow-early.sh" "$(bp toolu_b3)" >/dev/null
check "builder: each refusal ends its call by id, an allowed call adds nothing" \
  'tool-refused:toolu_b1:block-exit2.sh tool-refused:toolu_b2:block-json.sh' \
  "$(jq -r '"\(.event):\(.use):\(.hook)"' "$BW/.claude/builder-events.jsonl" | paste -sd' ' -)"
COMMANDECK_BUILDER='' CLAUDE_PROJECT_DIR=$T/plain run "$FX/block-exit2.sh" "$(bp toolu_b4)" >/dev/null
[ ! -e "$T/plain/.claude/builder-events.jsonl" ] && ok || bad "builder: a block in a worktree with no Builder log created one"

# --- a hook file that no longer parses --------------------------------
# A hook broken by a shell write, a merge or a checkout exits 2 on every call, its own repair included,
# so the pane was locked out until a person fixed the file. The broken hook now stands down for one
# thing only: an Edit, Write or MultiEdit of its own file, named by its real path. Letting anything
# else through would fail open for what the hook guards, so every case below that is not that edit
# must stay refused.
GUARDED='case "$INPUT" in *FORBIDDEN*) echo "guarded: refused" >&2; exit 2 ;; esac
exit 0'
BROKEN='if then fi (
exit 0'
ep() { # tool path [content] [event] -> an edit payload
  jq -cn --arg t "$1" --arg p "$2" --arg c "${3:-x}" --arg e "${4:-PreToolUse}" \
    '{session_id:"s", hook_event_name:$e, tool_name:$t, tool_input:{file_path:$p, content:$c, old_string:"a", new_string:$c}}'
}
shp() { jq -cn --arg c "$1" '{session_id:"s", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}'; }
mk guarded "$GUARDED"
mk second "$GUARDED"
check "broken: a hook that parses refuses and allows as before" "2 0" "$(run "$FX/guarded.sh" "$(shp 'echo FORBIDDEN')") $(run "$FX/guarded.sh" "$(shp true)")"
check "broken: and a real refusal says only what the hook said" "guarded: refused" "$(run "$FX/guarded.sh" "$(shp 'echo FORBIDDEN')" >/dev/null; cat "$T/err")"
mk guarded "$BROKEN" # the shell write that breaks it
check "broken by a shell write: a Bash call is refused" 2 "$(run "$FX/guarded.sh" "$(shp true)")"
grep -q "guarded.sh does not parse" "$T/err" && grep -q "syntax error" "$T/err" && grep -qF "Edit or Write $FX/guarded.sh" "$T/err" && ok \
  || bad "broken: the refusal must name the file, bash's error and the repair, got: $(cat "$T/err")"
check "broken: an Edit of another file is refused" 2 "$(run "$FX/guarded.sh" "$(ep Edit "$FX/other.txt")")"
check "broken: a Write, an Edit and a MultiEdit of the broken file itself get through" "0 0 0" \
  "$(run "$FX/guarded.sh" "$(ep Write "$FX/guarded.sh")") $(run "$FX/guarded.sh" "$(ep Edit "$FX/guarded.sh")") $(run "$FX/guarded.sh" "$(ep MultiEdit "$FX/guarded.sh")")"
ln -s "$FX/guarded.sh" "$FX/link.sh"; ln -s "$FX" "$T/fxlink"
UPPER=${FX%/*}/$(tr '[:lower:]' '[:upper:]' <<<"${FX##*/}")
check "broken: a symlink to it, a path through a symlinked folder, a .. path, another letter case and another hook file are refused" "2 2 2 2 2" \
  "$(for p in "$FX/link.sh" "$T/fxlink/guarded.sh" "$FX/../${FX##*/}/guarded.sh" "$UPPER/guarded.sh" "$FX/second.sh"; do run "$FX/guarded.sh" "$(ep Write "$p")"; done | paste -sd' ' -)"
check "broken: a shell command is never the repair, whatever it names" "2 2" \
  "$(run "$FX/guarded.sh" "$(shp "git checkout -- $FX/guarded.sh")") $(run "$FX/guarded.sh" "$(shp "printf x > $FX/guarded.sh")")"
check "broken: a MultiEdit whose edits name paths of their own is refused" 2 \
  "$(run "$FX/guarded.sh" "$(ep MultiEdit "$FX/guarded.sh" | jq -c --arg p "$FX/second.sh" '.tool_input.edits = [{file_path: $p, old_string: "a", new_string: "b"}]')")"
check "broken: only before the call; the repair edit seen after it changes nothing" 2 "$(run "$FX/guarded.sh" "$(ep Write "$FX/guarded.sh" x PostToolUse)")"
check "broken: only that hook stands down; a second guard still refuses the same edit by its own rule" "0 2" \
  "$(run "$FX/guarded.sh" "$(ep Write "$FX/guarded.sh" FORBIDDEN)") $(run "$FX/second.sh" "$(ep Write "$FX/guarded.sh" FORBIDDEN)")"
mk marked 'case "$INPUT" in *FORBIDDEN*) HOOK_FIRE_BLOCK=1; exit 2 ;; esac
if then fi (
exit 0'
check "broken: a refusal the hook marked as its own, made above the break, holds even for the repair edit" "2 0" \
  "$(run "$FX/marked.sh" "$(ep Write "$FX/marked.sh" FORBIDDEN)") $(run "$FX/marked.sh" "$(ep Write "$FX/marked.sh")")"
before=$(nrows); run "$FX/guarded.sh" "$(shp true)" >/dev/null
check "broken: the refused call is logged as a block" "$((before + 1)) block" "$(nrows) $(last .decision)"
mk guarded "$GUARDED" # what the Write that got through does
check "repaired after a shell write: the hook guards again" "0 2" "$(run "$FX/guarded.sh" "$(shp true)") $(run "$FX/guarded.sh" "$(shp 'echo FORBIDDEN')")"
# Broken by a checkout: the file in the tree is replaced by a commit's copy that carries conflict markers.
G=$T/repo; mkdir -p "$G/hooks"; ln -s "$HOOKS/lib" "$G/hooks/lib"
gitq() { git -C "$G" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
gitq init -q -b main
FX=$G/hooks mk guarded "$GUARDED"; gitq add hooks/guarded.sh; gitq commit -q -m good
gitq checkout -q -b merged
FX=$G/hooks mk guarded "<<<<<<< HEAD
$GUARDED
=======
exit 0
>>>>>>> other"; gitq commit -q -am conflict; gitq checkout -q main
gitq checkout -q merged -- hooks/guarded.sh
check "broken by a checkout: a Bash call and an Edit elsewhere are refused, the repair gets through" "2 2 0" \
  "$(run "$G/hooks/guarded.sh" "$(shp true)") $(run "$G/hooks/guarded.sh" "$(ep Edit "$G/README")") $(run "$G/hooks/guarded.sh" "$(ep Write "$G/hooks/guarded.sh")")"
git -C "$G" show main:hooks/guarded.sh > "$G/hooks/guarded.sh"
check "repaired after a checkout: the hook guards again" "0 2" "$(run "$G/hooks/guarded.sh" "$(shp true)") $(run "$G/hooks/guarded.sh" "$(shp 'echo FORBIDDEN')")"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
