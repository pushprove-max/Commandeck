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
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
