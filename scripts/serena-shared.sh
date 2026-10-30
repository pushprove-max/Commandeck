#!/usr/bin/env bash
# serena-shared.sh start|stop|status <worktree>
#   start    start the worktree's ONE Serena server unless it is already
#            answering; print its address (this machine only, a port of its own)
#   stop     stop that server and its language servers; nothing to stop is fine
#   status   print "<address> pid=<pid>", or exit 1 when none is running
# serena-shared.sh seat-args <claude|codex> <address>
#            print the words a seat's start-up line adds to use that server
# Exit 3 from start or seat-args: no Serena is set up on this machine.
#
# One Serena per worktree instead of one per seat: each seat's own Serena
# brings its own language servers, several hundred MB for a large repo.
# seat.sh calls `start` and `seat-args` at each launch. merge-unit-local.sh and
# the close scripts call `stop` once the unit's panes are closed, and the next
# seat launched there starts a fresh server. There is no restart under live
# seats: a seat keeps a session the new server does not know, and every later
# call of that seat fails.
# The launcher is the `serena` entry setup.sh reads from the Claude config (the
# project's, else the top-level): its `command` and `args` up to
# `start-mcp-server`. No entry, or one without that word: `serena` on PATH.
# A Claude seat takes the address itself (--mcp-config; the name `serena`
# replaces the home entry for that session). Codex cannot swap a stdio entry
# for an address from its command line ("url is not supported for stdio"), so a
# Codex seat keeps the entry and runs serena-bridge.py as its command, on the
# Python of the `serena` file's shebang, or for uvx on `<uvx words> python`.
# No file in a home directory changes. The record is one line, "<port> <pid>",
# under the scratch directory. The server listens on 127.0.0.1 only.
# Self-test: bash scripts/__tests__/serena-shared.test.sh
set -uo pipefail
usage() { sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in --help|-h) usage; exit 0 ;; start|stop|status|seat-args) ;; *) usage >&2; exit 2 ;; esac
[ $# -ge 2 ] || { usage >&2; exit 2; }
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh" || exit 1

# launcher: the words that run Serena up to and including start-mcp-server, as a JSON array; exit 3 when there is none.
launcher() {
  local cfg=${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json l
  l=$(jq -c --arg p "$PP_MAIN" '(.projects[$p].mcpServers.serena // .mcpServers.serena) as $e
    | ($e.args // []) as $a | if $e and ($a | index("start-mcp-server")) then [$e.command] + $a[:($a | index("start-mcp-server")) + 1] else empty end' "$cfg" 2>/dev/null) || l=
  if [ -n "$l" ]; then printf '%s' "$l"
  elif command -v serena >/dev/null 2>&1; then printf '["serena","start-mcp-server"]'
  else echo "serena-shared: no Serena here: no serena entry in $cfg and none on PATH" >&2; return 3; fi
}

if [ "$1" = seat-args ]; then
  URL=${3:?address}
  case $2 in
    claude) printf -- '--mcp-config %q' "$(jq -cn --arg u "$URL" '{mcpServers:{serena:{type:"http",url:$u}}}')" ;;
    codex)
      L=$(launcher) || exit $?
      # The bridge runs on Serena's own Python: it carries the MCP library.
      if [ "$(jq -r '.[0] | split("/") | last' <<<"$L")" = serena ]; then
        PY=$(sed -n '1s/^#! *//p' "$(command -v "$(jq -r '.[0]' <<<"$L")")")
        [ -x "$PY" ] || { echo "serena-shared: no Python found behind the serena file" >&2; exit 1; }
        CMD=$(jq -cn --arg v "$PY" '$v') ARGS=$(jq -cn --arg b "$HERE/serena-bridge.py" --arg u "$URL" '[$b, $u]')
      else
        # uvx: the words before `serena`, then its Python.
        CMD=$(jq -c '.[0]' <<<"$L")
        ARGS=$(jq -c --arg b "$HERE/serena-bridge.py" --arg u "$URL" '.[1:-1] | (if .[-1] == "serena" then .[:-1] else . end) + ["python", $b, $u]' <<<"$L")
      fi
      printf -- '-c %q -c %q' "mcp_servers.serena.command=$CMD" "mcp_servers.serena.args=$ARGS" ;;
    *) echo "serena-shared: seat-args takes claude or codex, not $2" >&2; exit 2 ;;
  esac
  exit 0
fi

WT=$(cd "$2" 2>/dev/null && pwd -P) || WT=$2
# The slug alone maps foo-bar and foo_bar to one name; the checksum of the path keeps them apart.
REC=$PP_SCRATCH/serena-shared-$(pp_slug "$WT")-$(printf '%s' "$WT" | cksum | cut -d' ' -f1).txt
# Loopback only: the server has no login, so it never listens on the network.
HOST=127.0.0.1
PORT= PID=
[ ! -s "$REC" ] || read -r PORT PID < "$REC"
address() { echo "http://$HOST:$PORT/mcp"; }
# The recorded pid is ours only while it is still that server, on that port, for this worktree.
running() { [ -n "$PID" ] && ps -o args= -p "$PID" 2>/dev/null | grep -qF -- "start-mcp-server --transport streamable-http --host $HOST --port $PORT --project $WT "; }
answering() { (exec 3<>"/dev/tcp/$HOST/$PORT") 2>/dev/null; }

stop() {
  ! running || {
    kill "$PID" 2>/dev/null
    for _ in $(seq 1 50); do running || break; sleep 0.2; done
    ! running || kill -9 "$PID" 2>/dev/null
  }
  rm -f "$REC"
}
start() {
  if running && answering; then address; return 0; fi
  [ -d "$WT" ] || { echo "serena-shared: no worktree at $WT" >&2; return 1; }
  local l; l=$(launcher) || return $?
  local words=(); while IFS= read -r w; do words+=("$w"); done < <(jq -r '.[]' <<<"$l")
  mkdir -p "$PP_SCRATCH"
  # Two seats launched together must not start two servers. The kernel drops a dead start's lock, so a crash blocks no
  # retry; the server closes it, or it would hold the lock for as long as it runs.
  local fd
  exec {fd}>>"$REC.lock" && flock -w 30 "$fd" || { echo "serena-shared: another start for $WT did not finish" >&2; return 1; }
  # Another start may have finished between the read above and this lock; acting on the old read would orphan its server.
  [ ! -s "$REC" ] || read -r PORT PID < "$REC"
  if running && answering; then address; return 0; fi
  stop
  PORT=$(python3 -c 'import socket, sys; s = socket.socket(); s.bind((sys.argv[1], 0)); print(s.getsockname()[1])' "$HOST")
  (cd "$WT" && exec nohup "${words[@]}" --transport streamable-http --host "$HOST" --port "$PORT" --project "$WT" \
    --context claude-code --open-web-dashboard false > "${REC%.txt}.log" 2>&1 < /dev/null {fd}>&-) &
  PID=$!
  echo "$PORT $PID" > "$REC"
  # Serena listens only after its language servers are up. The first uvx fetch can pass 60 s: the seat is then
  # refused with the start command, and the next start reads uvx's cache.
  # Liveness by pid here, not by command line: until the child reaches its
  # exec it is still this shell, and it is ours either way, so a failed start
  # kills it by pid and leaves no server behind.
  for _ in $(seq 1 300); do answering && break; kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
  if ! answering || ! running; then
    echo "serena-shared: Serena for $WT did not answer on port $PORT; log ${REC%.txt}.log" >&2
    kill "$PID" 2>/dev/null; rm -f "$REC"; return 1
  fi
  address
}

case $1 in
  start) start ;;
  stop) stop ;;
  status) running && answering && echo "$(address) pid=$PID" ;;
esac
