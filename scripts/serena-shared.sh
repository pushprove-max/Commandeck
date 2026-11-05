#!/usr/bin/env bash
# serena-shared.sh start|stop|status <worktree>
#   start    start the worktree's ONE Serena server unless it is already
#            answering; print its address (this machine only, a port of its own)
#   stop     stop that server and its language servers; nothing to stop is fine
#   status   print "<address> pid=<pid>", or exit 1 when none is running
#   sweep    stop a child of the server above 2 GB (start runs this every 30 s); logged in the .watch.log beside the record
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
usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in --help|-h) usage; exit 0 ;; start|stop|status|sweep|seat-args) ;; *) usage >&2; exit 2 ;; esac
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

WATCH=${REC%.txt}.watch.pid
# A language server that outgrows the cap takes the machine down. macOS does not enforce RSS limits, so the watch loop
# sums each direct child's whole process tree and stops the child above the cap. Fixed: the issue names the cap.
CAP_MB=2048 SWEEP_SECS=30
# sweep: one pass over the server's children; a pid that is not our server is never swept.
sweep() {
  running || return 0
  local c mb pids cmd
  while read -r c mb pids cmd; do
    kill ${pids//,/ } 2>/dev/null
    for _ in $(seq 1 10); do kill -0 "$c" 2>/dev/null || break; sleep 0.2; done
    ! kill -0 "$c" 2>/dev/null || kill -9 ${pids//,/ } 2>/dev/null
    printf '%s killed pid=%s cmd=%s worktree=%s rss_mb=%s cap_mb=%s\n' "$(date -u +%FT%TZ)" "$c" "$cmd" "$WT" "$mb" "$CAP_MB" >> "${REC%.txt}.watch.log"
  done < <(ps -axo pid=,ppid=,rss=,args= | awk -v root="$PID" -v cap="$((CAP_MB * 1024))" '
    { ids[NR] = $1; par[$1] = $2; rss[$1] = $3; a = $0; sub(/^ *[0-9]+ +[0-9]+ +[0-9]+ ?/, "", a); args[$1] = a }
    END {
      for (i = 1; i <= NR; i++) {
        p = ids[i]; q = p; top = ""; n = 0
        while (q != root && q != "" && n++ < 1000) { top = q; q = par[q] }
        if (q != root || top == "") continue
        tot[top] += rss[p]; list[top] = list[top] "," p
      }
      for (c in tot) if (tot[c] > cap) print c, int(tot[c] / 1024), substr(list[c], 2), substr(args[c], 1, 60)
    }')
}
# watch: a loop that sweeps every SWEEP_SECS while the server lives; none is started when one already runs.
watch() {
  local w; w=$(cat "$WATCH" 2>/dev/null)
  if [ -n "$w" ] && ps -o args= -p "$w" 2>/dev/null | grep -qF serena-shared.sh; then return 0; fi
  (
    [ -z "${fd:-}" ] || exec {fd}>&-
    while kill -0 "$PID" 2>/dev/null; do sleep "$SWEEP_SECS"; sweep; done
  ) > /dev/null 2>&1 < /dev/null &
  echo $! > "$WATCH"
}
# serena_home: the SERENA_HOME for this worktree, printed; nothing when the source home has no config. Serena keys its
# project registry by folder name, so two same-named folders in two repositories need two homes. The user's own home (or
# ~/.serena) is the source: its config is copied with the project folder pinned, the rest is linked, so nothing downloads twice.
# repo_key: K = <PP_PROJECT>-<cksum of PP_PROJECT_DIR>, the worktree's own repository (CC2), so /a/app and /b/app differ.
repo_key() {
  local PP_PROJECT PP_PROJECT_DIR
  . "$HERE/../hooks/lib/project.sh" && pp_project "$WT"
  printf '%s' "$PP_PROJECT-$(printf '%s' "$PP_PROJECT_DIR" | cksum | cut -d' ' -f1)"
}
serena_home_dir() {
  printf '%s' "$PP_SCRATCH/serena-home/$(repo_key)-$(pp_slug "${WT##*/}")-$(printf '%s' "$WT" | cksum | cut -d' ' -f1)"
}
# folder_line <source config>: the project folder line for the new home (DC7). Serena fills the template's $projectDir
# and $projectFolderName (default `$projectDir/.serena`). A template with no $projectFolderName is one folder per
# worktree path already, so its line is kept as it is and Serena finds the same folder, settings and memories as before.
# A $projectFolderName template shares a folder between same-named folders of two repositories: the name is written
# K-<folder name>, and the folder Serena used before (the filled template, else $WT/.serena) is copied there once.
# The value is read by allowlist (pass 16): a double-quoted string with no backslash, a single-quoted string with no
# quote inside, or a plain path of [A-Za-z0-9_./~$-], each with an optional ` # comment`; any other shape is refused
# naming the line, before a config is written.
folder_line() {
  local raw t f p tl='[[:space:]]*([[:space:]]#.*)?$'
  local dq='^"([^"\]*)"'$tl sq="^'([^']*)'"$tl pl='^([A-Za-z0-9_./~$-]*)'$tl
  raw=$(grep '^project_serena_folder_location:' "$1" | tail -1)
  t=${raw#project_serena_folder_location:}; t=${t#"${t%%[![:space:]]*}"}
  [[ $t != '#'* ]] || t=
  if [[ $t =~ $dq || $t =~ $sq || $t =~ $pl ]]; then
    t=${BASH_REMATCH[1]}
  else
    echo "serena-shared: BLOCKED: unsupported value in $1: $raw (use a quoted or plain path, no escapes)" >&2; return 2
  fi
  [ -n "$t" ] || t='$projectDir/.serena'
  if [[ $t != *'$projectFolderName'* ]]; then [ -z "$raw" ] || printf '%s\n' "$raw"; return 0; fi
  fill() { local s=${1//\$projectDir/$WT}; s=${s//\$projectFolderName/$2}; [[ $s != '~/'* ]] || s=$HOME/${s#'~/'}; printf '%s' "$s"; }
  f=$(fill "$t" "${WT##*/}"); [ -d "$f" ] || f=$WT/.serena
  p=$(fill "$t" "$(repo_key)-${WT##*/}")
  [ -e "$p" ] || [ ! -d "$f" ] || { mkdir -p "${p%/*}" && cp -R "$f" "$p"; } || echo "serena-shared: could not copy $f to $p; Serena starts with an empty project folder" >&2
  echo "project_serena_folder_location: \"$p\""
}
serena_home() {
  local src=${SERENA_HOME:-$HOME/.serena} h d line
  [ -f "$src/serena_config.yml" ] || return 0
  h=$(serena_home_dir)
  mkdir -p "$h" "$src/language_servers" || return 0
  line=$(folder_line "$src/serena_config.yml") || return 1
  { grep -v '^project_serena_folder_location:' "$src/serena_config.yml"; [ -z "$line" ] || printf '%s\n' "$line"; } > "$h/serena_config.yml"
  for d in language_servers prompt_templates contexts modes memories; do
    [ ! -e "$src/$d" ] || ln -sfn "$src/$d" "$h/$d"
  done
  printf '%s' "$h"
}

stop() {
  ! running || {
    kill "$PID" 2>/dev/null
    for _ in $(seq 1 50); do running || break; sleep 0.2; done
    ! running || kill -9 "$PID" 2>/dev/null
  }
  local w; w=$(cat "$WATCH" 2>/dev/null)
  [ -z "$w" ] || ! ps -o args= -p "$w" 2>/dev/null | grep -qF serena-shared.sh || kill "$w" 2>/dev/null
  rm -f "$REC" "$WATCH"
}
start() {
  if running && answering; then watch; address; return 0; fi
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
  if running && answering; then watch; address; return 0; fi
  stop
  PORT=$(python3 -c 'import socket, sys; s = socket.socket(); s.bind((sys.argv[1], 0)); print(s.getsockname()[1])' "$HOST")
  local home; home=$(serena_home) || return 1
  (cd "$WT" && { [ -z "$home" ] || export SERENA_HOME=$home; } && exec nohup "${words[@]}" --transport streamable-http --host "$HOST" --port "$PORT" --project "$WT" \
    --context claude-code --open-web-dashboard false > "${REC%.txt}.log" 2>&1 < /dev/null {fd}>&-) &
  PID=$!
  echo "$PORT $PID" > "$REC"
  # Before the answer wait: a language server that grows while starting can be what keeps the server from answering.
  watch
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
  stop) stop; pp_rm_rf "$(serena_home_dir)" ;;
  sweep) sweep ;;
  status) running && answering && echo "$(address) pid=$PID" ;;
esac
