#!/usr/bin/env bash
# serena-shared.sh: one Serena server per worktree, started once and stopped by its record, and the words a seat's
# start-up line takes (issue 470). `serena` and `uvx` are stubs that listen on the port they are given; no real Serena
# starts, nothing is fetched, and nothing is written outside the temp directory. The last cases run serena-bridge.py on
# the Python behind an installed Serena, and say so when there is none.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
S=$REAL/scripts/serena-shared.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
# One label per bug: a sub is one assertion under it, and a group's `check "<label>" "" "$MISS"` fails with every miss named.
MISS=
sub() { [ "$2" = "$3" ] || MISS+="$1: expected $2, got $3; "; }

TMP=$(cd "$(mktemp -d)" && pwd -P)
export COMMANDECK_SCRATCH=$TMP/scratch COMMANDECK_MAIN=$TMP/main STARTS=$TMP/starts.txt HOME=$TMP/home CLAUDE_CONFIG_DIR=$TMP/home
unset COMMANDECK_SERENA
servers() { ps -axo args= | grep -c -- "[s]tart-mcp-server --transport streamable-http .*--project $TMP/" || true; }
trap 'for w in wt other foo-bar foo_bar; do bash "$S" stop "$TMP/$w" >/dev/null 2>&1; done; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/wt" "$TMP/other" "$TMP/foo-bar" "$TMP/foo_bar" "$TMP/home"
git init -q "$TMP/main"
REALPY=$(sed -n '1s/^#! *//p' "$(command -v serena 2>/dev/null)" 2>/dev/null)
# $STARTS.fail: the server exits at once. $STARTS.slow: it takes a second to become the server, as a loaded machine makes the real one.
LISTEN='#!/bin/bash
[ ! -e "$STARTS.fail" ] || exit 1
[ ! -e "$STARTS.slow" ] || sleep 1
echo "$*" >> "$STARTS"
exec python3 -c '"'"'import socket, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((sys.argv[sys.argv.index("--host") + 1], int(sys.argv[sys.argv.index("--port") + 1]))); s.listen(8)
while True: s.accept()[0].close()'"'"' "$@"'
printf '%s\n' "$LISTEN" > "$TMP/bin/serena"; chmod +x "$TMP/bin/serena"
export PATH=$TMP/bin:$PATH

# A second seat in the worktree must get the first seat's server, not its own: that is the whole saving.
URL=$(bash "$S" start "$TMP/wt")
REC=$(echo "$TMP"/scratch/serena-shared-*wt-*.txt)
sub "start leaves one record for the worktree" 1 "$([ -s "$REC" ] && echo 1 || echo 0)"
sub "start prints a loopback address" 1 "$(grep -cE '^http://127\.0\.0\.1:[0-9]+/mcp$' <<<"$URL")"
sub "the server is started for that worktree, on the network transport" 1 \
  "$(grep -c -- "^start-mcp-server --transport streamable-http --host 127.0.0.1 --port [0-9]* --project $TMP/wt " "$STARTS")"
sub "a second start gives the same address" "$URL" "$(bash "$S" start "$TMP/wt")"
sub "a second start starts no second server" 1 "$(servers)"
sub "status names the address and the pid" 1 "$(bash "$S" status "$TMP/wt" | grep -c "^$URL pid=[0-9]*$")"
OTHER=$(bash "$S" start "$TMP/other")
sub "another worktree gets its own server" 2 "$(servers)"
sub "and its own address" 1 "$([ "$OTHER" != "$URL" ] && echo 1 || echo 0)"
check "a worktree's seats share one server and another worktree gets its own (issue 470)" "" "$MISS"; MISS=

# Two worktree names that differ only in punctuation must not share a record: the second would be handed the first's
# server, a Serena for the wrong files, and stopping either would stop the other's.
A=$(bash "$S" start "$TMP/foo-bar"); B=$(bash "$S" start "$TMP/foo_bar")
sub "foo-bar and foo_bar get a server each" "4 1" "$(servers) $([ "$A" != "$B" ] && echo 1 || echo 0)"
bash "$S" stop "$TMP/foo-bar"
sub "stopping one leaves the other running" "$B" "$(bash "$S" status "$TMP/foo_bar" | cut -d' ' -f1)"
# A record that names another worktree's live server is not this worktree's server.
bash "$S" stop "$TMP/wt"; cp "$(ls "$TMP"/scratch/serena-shared-*foo?bar-*.txt)" "$REC"
bash "$S" status "$TMP/wt" >/dev/null; sub "a record naming another worktree's server is not taken for this one's" 1 $?
bash "$S" stop "$TMP/wt"
sub "and stop on that record leaves the other worktree's server alone" "$B" "$(bash "$S" status "$TMP/foo_bar" | cut -d' ' -f1)"
bash "$S" stop "$TMP/foo_bar"; bash "$S" stop "$TMP/other"
check "foo-bar and foo_bar get separate servers and records (issue 470)" "" "$MISS"; MISS=

sub "stop ends the server" 0 "$(servers)"
sub "stop removes the record" 0 "$(ls "$TMP/scratch" | grep -c '\.txt$' || true)"
bash "$S" status "$TMP/wt" >/dev/null; sub "status fails with none running" 1 $?
bash "$S" stop "$TMP/wt"; sub "stop with nothing to stop is not an error" 0 $?
bash "$S" restart "$TMP/wt" >/dev/null 2>&1
# A restart under live seats breaks each one's session, so there is none: the merge stops, the next launch starts.
sub "there is no restart command" "2 0" "$? $(servers)"

# A record can outlive its server and the pid can be reused: stop must never kill a process that is not that server.
sleep 300 & BYSTANDER=$!
echo "1 $BYSTANDER" > "$REC"
bash "$S" stop "$TMP/wt"
sub "stop does not kill a recorded pid that is not the server" 0 "$(kill -0 "$BYSTANDER" 2>/dev/null; echo $?)"
sub "and still clears the stale record" 0 "$([ -e "$REC" ]; echo $((1 - $?)))"
kill "$BYSTANDER" 2>/dev/null
check "stop ends the server by its record and never kills another pid (issue 470)" "" "$MISS"; MISS=

# Two seats launched in the same second share one server; with no Serena at all, start exits 3 and leaves nothing.
: > "$STARTS"
bash "$S" start "$TMP/wt" > "$TMP/a" & bash "$S" start "$TMP/wt" > "$TMP/b" & wait
TWO="$(servers) $([ -s "$TMP/a" ] && cmp -s "$TMP/a" "$TMP/b" && echo 1 || echo 0)"
bash "$S" stop "$TMP/wt"
# A PATH of links to the tools the script uses and no serena: an installed real one would otherwise be found and started.
mkdir "$TMP/nobin"; for t in bash jq python3 git ps grep seq sleep cksum cut tr sed rm mkdir rmdir dirname date cat paste env awk head tail wc sort ls uname basename id mktemp readlink realpath pwd tee nohup kill; do
  ln -s "$(command -v "$t")" "$TMP/nobin/$t" 2>/dev/null; done
PATH=$TMP/nobin bash "$S" start "$TMP/wt" >/dev/null 2>&1; NONE=$?
check "two starts share one server, none if off (issue 470)" "1 1 3 0 0" \
  "$TWO $NONE $(ls "$TMP/scratch" | grep -c '\.txt$' || true) $(servers)"

# One seat's start reads "no server", then stalls while another's starts one and finishes. Acting on what it read, the
# first would drop that record and start a second server that no stop would ever find.
printf '#!/bin/bash\n[ "$1" != -p ] || [ ! -e "$STARTS.pause" ] || sleep 3\nexec /bin/mkdir "$@"\n' > "$TMP/bin/mkdir"; chmod +x "$TMP/bin/mkdir"
: > "$STARTS.pause"
bash "$S" start "$TMP/wt" > "$TMP/b" & sleep 1; rm -f "$STARTS.pause"
bash "$S" start "$TMP/wt" > "$TMP/a"; wait; rm -f "$TMP/bin/mkdir"
sub "a start that stalled while another finished starts no second server" 1 "$(servers)"
sub "and gets the running one's address" 1 "$([ -s "$TMP/a" ] && cmp -s "$TMP/a" "$TMP/b" && echo 1 || echo 0)"
bash "$S" stop "$TMP/wt"
sub "and stop then leaves none" 0 "$(servers)"

# A start killed while it holds the lock: the next one waits for no one, replaces what it left and takes the worktree.
: > "$STARTS.slow"
bash "$S" start "$TMP/wt" >/dev/null 2>&1 & KILLED=$!
for _ in $(seq 1 50); do [ ! -s "$REC" ] || break; sleep 0.1; done
kill -9 "$KILLED"; wait "$KILLED" 2>/dev/null; rm -f "$STARTS.slow"
AFTER=$(timeout 10 bash "$S" start "$TMP/wt" 2>&1); RC=$?
check "a killed start blocks no retry (issue 470)" "0 1 1" "$RC $(grep -c '^http://127' <<<"$AFTER") $(servers)"
bash "$S" stop "$TMP/wt"

# Until the child becomes the server it is still a shell: a start that judged it by its command line gave up on a
# healthy server and left it running with no record.
: > "$STARTS.slow"
SLOW=$(bash "$S" start "$TMP/wt" 2>&1); RC=$?
sub "a server slow to come up is waited for" "0 1" "$RC $(grep -c '^http://127' <<<"$SLOW")"
sub "and it is the recorded one" "$SLOW" "$(bash "$S" status "$TMP/wt" | cut -d' ' -f1)"
bash "$S" stop "$TMP/wt"; rm -f "$STARTS.slow"
sub "and stop ends it" 0 "$(servers)"

# A server that never listens is an error with the log named, not an address.
: > "$STARTS.fail"
OUT=$(bash "$S" start "$TMP/wt" 2>&1); RC=$?
sub "a server that does not come up fails the start" 1 "$RC"
sub "and names the log" 1 "$(grep -c 'did not answer on port.*log ' <<<"$OUT")"
sub "and leaves no record and no server" "0 0" "$(ls "$TMP/scratch" | grep -c '\.txt$' || true) $(servers)"
rm -f "$STARTS.fail"
check "a start waits out a stalled or slow server and fails loud on a dead one (issue 470)" "" "$MISS"; MISS=

# The seat words: a Claude seat takes the address under the name `serena`, a Codex seat keeps its `serena` entry and
# swaps only what it runs.
eval "W=($(bash "$S" seat-args claude "$URL"))"
sub "a Claude seat gets --mcp-config" "--mcp-config" "${W[0]}"
sub "naming serena at the address" "$URL" "$(jq -r '.mcpServers.serena | select(.type == "http") | .url' <<<"${W[1]}")"
eval "W=($(bash "$S" seat-args codex "$URL"))"
sub "a Codex seat gets two settings" "-c -c" "${W[0]} ${W[2]}"
sub "its serena command is the Python behind serena" 'mcp_servers.serena.command="/bin/bash"' "${W[1]}"
sub "its serena arguments are the bridge and the address" "[\"$REAL/scripts/serena-bridge.py\",\"$URL\"]" "${W[3]#mcp_servers.serena.args=}"
bash "$S" seat-args other "$URL" >/dev/null 2>&1; sub "another agent is refused" 2 $?
check "a seat's start-up words take the address for Claude and the bridge for Codex (issue 470)" "" "$MISS"; MISS=

# A uvx install: no `serena` file, the add-on's entry in the Claude config (the project's, else the top-level). `start`
# runs that entry's command and arguments through start-mcp-server, then the plugin's flags; the entry's own
# --context and --project are dropped. The Codex words run the bridge on uvx's Python.
mv "$TMP/bin/serena" "$TMP/serena.kept"
printf '#!/bin/bash\n%s\n' "$(sed 1d <<<"$LISTEN")" > "$TMP/bin/uvx"; chmod +x "$TMP/bin/uvx"
jq -n --arg p "$COMMANDECK_MAIN" '{projects: {($p): {mcpServers: {serena: {command: "uvx",
  args: ["--from", "git+https://example.test/serena", "serena", "start-mcp-server", "--context", "ide-assistant", "--project", "/elsewhere"]}}}}}' > "$TMP/home/.claude.json"
: > "$STARTS"
UV=$(bash "$S" start "$TMP/wt" 2>&1); RC=$?
sub "a uvx install gets the server" "0 1 1 0 1" \
  "$RC $(grep -c '^http://127' <<<"$UV") $(grep -c -- "^--from git+https://example.test/serena serena start-mcp-server --transport streamable-http --host 127.0.0.1 --port [0-9]* --project $TMP/wt --context claude-code" "$STARTS") $(grep -c ide-assistant "$STARTS") $(servers)"
eval "W=($(bash "$S" seat-args codex "$UV"))"
sub "and its Codex seat runs the bridge on uvx's Python" "mcp_servers.serena.command=\"uvx\" mcp_servers.serena.args=[\"--from\",\"git+https://example.test/serena\",\"python\",\"$REAL/scripts/serena-bridge.py\",\"$UV\"]" "${W[1]} ${W[3]}"
check "a uvx install gets the server (issue 470)" "" "$MISS"; MISS=
bash "$S" stop "$TMP/wt"
rm -f "$TMP/home/.claude.json" "$TMP/bin/uvx"; mv "$TMP/serena.kept" "$TMP/bin/serena"

# This repo asks for the server: its own config turns the flag on, as setup would, so seats and passes take it.
check "this repo runs the server (issue 470)" "true 0" \
  "$(jq -r '.serena' "$REAL/.claude/commandeck.json") $(mkdir -p "$TMP/repo/.claude" && git init -q "$TMP/repo" && cp "$REAL/.claude/commandeck.json" "$TMP/repo/.claude/" \
    && cd "$TMP/repo" && env -u COMMANDECK_SERENA bash -c '. "$1/hooks/lib/project.sh" && pp_serena' _ "$REAL"; echo $?)"

# The bridge. A server that answers with something that is not an answer must not leave the call waiting: the caller gets an error for it.
if [ -x "${REALPY:-}" ] && "$REALPY" -c 'import mcp' 2>/dev/null; then
  cat > "$TMP/notmcp.py" <<'PY'
import http.server, sys, time
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        asked = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/ok/mcp" or (self.path == "/stall/mcp" and b'"initialize"' in asked):
            body = b'{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-03-26","capabilities":{},"serverInfo":{"name":"t","version":"0"}}}'
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("mcp-session-id", "seat-1")
            self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
            return
        self.send_response(200); self.send_header("Content-Type", "text/plain"); self.send_header("Content-Length", "4"); self.end_headers()
        self.wfile.write(b"nope")
    def do_DELETE(self):
        if self.path == "/stall/mcp": time.sleep(60)
        open(sys.argv[1], "a").write(self.headers.get("mcp-session-id", "") + "\n")
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
PY
  python3 "$TMP/notmcp.py" "$TMP/ended.txt" > "$TMP/notmcp.port" & NOTMCP=$!
  for _ in $(seq 1 50); do [ -s "$TMP/notmcp.port" ] && break; sleep 0.1; done
  INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}'
  # The MCP client answers the call itself when the server's answer is not one, so the caller is not left waiting.
  # A real server's error looks the same, so the bridge passes it on and stays up for the seat's next call.
  { echo "$INIT"; sleep 20; } | timeout 30 "$REALPY" "$REAL/scripts/serena-bridge.py" "http://127.0.0.1:$(cat "$TMP/notmcp.port")/mcp" > "$TMP/bridge.out" 2> "$TMP/bridge.err" &
  BRIDGE=$!
  for _ in $(seq 1 100); do grep -q '"error"' "$TMP/bridge.out" 2>/dev/null && break; sleep 0.1; done
  sub "the server's broken answer reaches the caller as an error" 1 "$(grep -c '"error"' "$TMP/bridge.out")"
  sub "and the bridge stays up for the next call" 1 "$(pgrep -f "serena-bridge.py http://127.0.0.1:$(cat "$TMP/notmcp.port")/" >/dev/null && echo 1 || echo 0)"
  pkill -P "$BRIDGE" 2>/dev/null; kill "$BRIDGE" 2>/dev/null
  # The server keeps a seat's session until told it ended: a bridge that just dies leaves one behind per seat, for as
  # long as the shared server runs.
  { echo "$INIT"; sleep 2; } | timeout 30 "$REALPY" "$REAL/scripts/serena-bridge.py" "http://127.0.0.1:$(cat "$TMP/notmcp.port")/ok/mcp" > "$TMP/bridge.out" 2> "$TMP/bridge.err"
  sub "a seat that leaves gets its answer and exits clean" "0 1" "$? $(grep -c '"serverInfo"' "$TMP/bridge.out")"
  sub "and ends its session on the server" seat-1 "$(cat "$TMP/ended.txt" 2>/dev/null)"
  # Last because it ties the server up: a seat that leaves after a broken answer, and a server that never answers the
  # goodbye. The seat's exit must not wait out the goodbye.
  { echo "$INIT"; sleep 1; echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'; sleep 1; } \
    | { timeout 40 "$REALPY" "$REAL/scripts/serena-bridge.py" "http://127.0.0.1:$(cat "$TMP/notmcp.port")/stall/mcp" >/dev/null 2>&1; echo $? > "$TMP/stall.rc"; } &
  STALL=$!
  for _ in $(seq 1 150); do [ -s "$TMP/stall.rc" ] && break; sleep 0.1; done
  sub "a seat that leaves after a broken answer still ends the bridge within seconds of an unanswered goodbye" 0 "$(cat "$TMP/stall.rc" 2>/dev/null)"
  pkill -P "$STALL" 2>/dev/null; kill "$STALL" 2>/dev/null
  kill "$NOTMCP" 2>/dev/null
  "$REALPY" "$REAL/scripts/serena-bridge.py" >/dev/null 2>&1; sub "the bridge refuses to start with no address" 1 $?
  check "the bridge answers a broken reply with an error, ends its session, and never hangs a seat (issue 470)" "" "$MISS"; MISS=
else
  echo "NOT RUN: the serena-bridge.py cases need the Python behind an installed serena (none on this host)"
  SKIPPED="SKIPPED (no Serena python): the server's broken answer reaches the caller as an error; and the bridge stays up for the next call; a seat that leaves gets its answer and exits clean; and ends its session on the server; a seat that leaves after a broken answer still ends the bridge within seconds of an unanswered goodbye; the bridge refuses to start with no address"
  echo "$SKIPPED"
fi

# D26 (#540): the pane-budget gate skips its server check for Serena's read-only tools and the Codex wrapper enables only
# those same tools; one list drifting from the other would leave a read tool checked or an edit tool let through.
# Name parity only: stubs here prove no connection (A9's live Codex seat does).
GATE_NAMES=$(grep -o 'mcp__serena__[a-z_]*' "$REAL/hooks/pane-budget-gate.sh" | sed 's/^mcp__serena__//' | sort -u | paste -sd, -)
CODEX_NAMES=$(grep -o 'enabled_tools=\[[^]]*\]' "$REAL/scripts/codex-no-helpers/codex" | grep -o '[a-z_]*' | grep -vx enabled_tools | sort -u | paste -sd, -)
check "the Codex wrapper lists the same six read-only Serena tools as the gate" \
  "find_declaration,find_implementations,find_referencing_symbols,find_symbol,get_diagnostics_for_file,get_symbols_overview:$CODEX_NAMES" "$GATE_NAMES:$CODEX_NAMES"

# CC2 (#649): Serena keys its project registry by folder name, so /a/app and /b/app in two repositories collide in one
# home. The stub records the SERENA_HOME it was started with. The user's own ~/.serena is the source of each home.
unset SERENA_HOME
SH=$HOME/.serena; mkdir -p "$SH/language_servers" "$TMP/r1/app" "$TMP/r2/app" "$TMP/bin2"
echo ls-binary > "$SH/language_servers/pyright.txt"
printf 'language_backend: LSP\nproject_serena_folder_location: "%s/meta/$projectFolderName/.serena"\n' "$TMP" > "$SH/serena_config.yml"
git init -q "$TMP/r1/app"; git init -q "$TMP/r2/app"
printf '#!/bin/bash\necho "${SERENA_HOME-}" >> "$STARTS.home"\n%s\n' "$(sed 1d <<<"$LISTEN")" > "$TMP/bin2/serena"; chmod +x "$TMP/bin2/serena"
: > "$STARTS.home"
PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r1/app" >/dev/null 2>&1; PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r2/app" >/dev/null 2>&1
H1=$(sed -n 1p "$STARTS.home") H2=$(sed -n 2p "$STARTS.home")
sub "each server is started with a home of its own" 2 "$(grep -c . "$STARTS.home")"
sub "the two homes differ" 1 "$([ -n "$H1" ] && [ "$H1" != "$H2" ] && echo 1 || echo 0)"
P1=$(sed -n 's/^project_serena_folder_location: "\(.*\)"$/\1/p' "$H1/serena_config.yml" 2>/dev/null)
P2=$(sed -n 's/^project_serena_folder_location: "\(.*\)"$/\1/p' "$H2/serena_config.yml" 2>/dev/null)
sub "each home pins a project folder of its own repository" "1 1 1" \
  "$([[ $P1 == "$TMP/meta/"*-app/.serena ]] && echo 1) $([[ $P2 == "$TMP/meta/"*-app/.serena ]] && echo 1) $([ "$P1" != "$P2" ] && echo 1)"
check "same-named folders in two repos get distinct homes" "" "$MISS"; MISS=
bash "$S" stop "$TMP/r1/app"; bash "$S" stop "$TMP/r2/app"

# pass 1 (DC7): the folder Serena used before the per-unit home keeps its settings and memories. A path-keyed template
# (no $projectFolderName) is kept as it is, so Serena finds the same folder; a $projectFolderName template's old folder
# is copied once into the repository's own folder.
cp "$SH/serena_config.yml" "$TMP/cfg.keep"
printf 'project_serena_folder_location: "%s/pm$projectDir/.serena"\n' "$TMP" > "$SH/serena_config.yml"
mkdir -p "$TMP/pm$TMP/r1/app/.serena/memories"; echo 'languages: [python]' > "$TMP/pm$TMP/r1/app/.serena/project.yml"
: > "$STARTS.home"; PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r1/app" >/dev/null 2>&1; HP=$(sed -n 1p "$STARTS.home")
sub "a path-keyed template is kept as it is" 1 "$(grep -cxF "project_serena_folder_location: \"$TMP/pm\$projectDir/.serena\"" "$HP/serena_config.yml" 2>/dev/null)"
bash "$S" stop "$TMP/r1/app"
cp "$TMP/cfg.keep" "$SH/serena_config.yml"; rm -rf "$TMP/meta"
mkdir -p "$TMP/meta/app/.serena/memories"; echo 'languages: [go]' > "$TMP/meta/app/.serena/project.yml"; echo note > "$TMP/meta/app/.serena/memories/m.md"
: > "$STARTS.home"; PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r1/app" >/dev/null 2>&1; HC=$(sed -n 1p "$STARTS.home")
PC=$(sed -n 's/^project_serena_folder_location: "\(.*\)"$/\1/p' "$HC/serena_config.yml" 2>/dev/null)
sub "the shared-by-name folder is copied into the repository's own" "languages: [go] note" "$(cat "$PC/project.yml" 2>/dev/null) $(cat "$PC/memories/m.md" 2>/dev/null)"
echo 'languages: [rust]' > "$PC/project.yml"; bash "$S" stop "$TMP/r1/app"
PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r1/app" >/dev/null 2>&1
sub "and is copied once, so later edits stay" "languages: [rust]" "$(cat "$PC/project.yml" 2>/dev/null)"
# pass 16 (config-scalar-parsing): a valid single-quoted value with a trailing comment once kept the quote and the
# comment in the path, so Serena opened an empty folder; an escaped value the reader does not parse refuses the start.
bash "$S" stop "$TMP/r1/app"
printf "project_serena_folder_location: '%s/meta/\$projectFolderName/.serena' # keep configs together\n" "$TMP" > "$SH/serena_config.yml"
PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r1/app" >/dev/null 2>&1
sub "a commented single-quoted value reads as the same folder" "$PC" "$(sed -n 's/^project_serena_folder_location: "\(.*\)"$/\1/p' "$HC/serena_config.yml" 2>/dev/null)"
bash "$S" stop "$TMP/r1/app"
printf 'project_serena_folder_location: "%s/a\\"b/$projectFolderName"\n' "$TMP" > "$SH/serena_config.yml"
: > "$STARTS.home"; ERR=$(PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r1/app" 2>&1 >/dev/null); RC=$?
sub "an escaped value refuses the start, naming the line, and starts no server" "1 1 0" \
  "$([ "$RC" -ne 0 ] && echo 1 || echo 0) $([[ $ERR == *'BLOCKED: unsupported value'*'a\"b'* ]] && echo 1 || echo 0) $(grep -c . "$STARTS.home")"
cp "$TMP/cfg.keep" "$SH/serena_config.yml"
check "existing project settings carry into the new home" "" "$MISS"; MISS=
bash "$S" stop "$TMP/r1/app"; bash "$S" stop "$TMP/r2/app"

# CC2 (#652): a home of its own must not cost the downloaded language servers or the user's other settings: one repo,
# one worktree, the same servers as before.
git -C "$TMP/r1/app" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i && git -C "$TMP/r1/app" worktree add -q "$TMP/r1/app-wt"
: > "$STARTS.home"
PATH=$TMP/bin2:$PATH bash "$S" start "$TMP/r1/app-wt" >/dev/null 2>&1
HW=$(sed -n 1p "$STARTS.home")
sub "the language servers are reached through the home" ls-binary "$(cat "$HW/language_servers/pyright.txt" 2>/dev/null)"
sub "and the user's other settings carry over" 1 "$(grep -c '^language_backend: LSP$' "$HW/serena_config.yml" 2>/dev/null)"
check "single-repo worktree keeps its language servers" "" "$MISS"; MISS=
bash "$S" stop "$TMP/r1/app-wt"

# CC2 (#650): a language server that grows past 2 GB takes the machine down. The sweep reads ps; a stub ps reports the
# sizes (a real 2 GB child would take the test machine down too) and passes every other call to the real one.
mkdir "$TMP/psbin"; REALPS=$(command -v ps)
printf '#!/bin/bash\n[ "${1-}" != -axo ] || exec cat %q\nexec %q "$@"\n' "$TMP/fakeps.txt" "$REALPS" > "$TMP/psbin/ps"; chmod +x "$TMP/psbin/ps"
bash "$S" start "$TMP/wt" >/dev/null 2>&1; read -r _ SP < "$REC"
sleep 5 & BIG=$!; sleep 5 & SMALL=$!
printf '%s 1 1000 serena start-mcp-server\n%s %s 3000000 sleep 5 big\n%s %s 100000 sleep 5 small\n' "$SP" "$BIG" "$SP" "$SMALL" "$SP" > "$TMP/fakeps.txt"
PATH=$TMP/psbin:$PATH timeout 20 bash "$S" sweep "$TMP/wt" >/dev/null 2>&1
kill -0 "$SMALL" 2>/dev/null; sub "the child under the cap is left alone" 0 $?
wait "$BIG" 2>/dev/null; sub "the child above the cap is stopped" 143 $?
sub "the stop is logged with pid, size and cap" 1 "$(grep -c " killed pid=$BIG .*worktree=$TMP/wt rss_mb=2929 cap_mb=2048\$" "${REC%.txt}.watch.log" 2>/dev/null)"
kill "$SMALL" 2>/dev/null; wait "$SMALL" 2>/dev/null
check "child above cap is stopped and logged" "" "$MISS"; MISS=
bash "$S" stop "$TMP/wt"

# CC2 (#652): with no Serena python the bridge cases are skipped; the skip must name them on screen and again after the
# totals, or a green run reads as a pass of cases that never ran. SERENA_TEST_NESTED keeps the inner run from nesting again.
if [ -z "${SERENA_TEST_NESTED:-}" ]; then
  # A `serena` file whose first line names no Python that has `mcp`: the inner run finds no Serena python and skips the bridge cases.
  mkdir "$TMP/noserena"; printf '#!/bin/false\n' > "$TMP/noserena/serena"; chmod +x "$TMP/noserena/serena"
  SERENA_TEST_NESTED=1 PATH=$TMP/noserena:$PATH timeout 180 bash "$REAL/scripts/__tests__/serena-shared.test.sh" > "$TMP/nested.out" 2>&1; NRC=$?
  sub "a machine without Serena still passes" 0 "$NRC$([ "$NRC" = 0 ] || echo " $(grep -E '^(FAIL|[a-z].*: command not found)' "$TMP/nested.out" | head -3)")"
  sub "the skip is said on screen and after the totals" 2 "$(grep -c '^SKIPPED (no Serena python): ' "$TMP/nested.out")"
  sub "the last line is the skip" 1 "$(tail -n 1 "$TMP/nested.out" | grep -c '^SKIPPED (no Serena python): ')"
  for L in "the server's broken answer reaches the caller as an error" "and the bridge stays up for the next call" "a seat that leaves gets its answer and exits clean" \
    "and ends its session on the server" "a seat that leaves after a broken answer still ends the bridge within seconds of an unanswered goodbye" "the bridge refuses to start with no address"; do
    sub "both skip lines name '$L'" 2 "$(grep '^SKIPPED (no Serena python): ' "$TMP/nested.out" | grep -cF -- "$L")"; done
  check "skipped cases are named without Serena" "" "$MISS"; MISS=
fi

echo
echo "$PASS passed, $FAIL failed"
[ -z "${SKIPPED:-}" ] || echo "$SKIPPED"
[ "$FAIL" -eq 0 ]
