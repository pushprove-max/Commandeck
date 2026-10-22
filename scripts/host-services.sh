#!/usr/bin/env bash
# host-services.sh -- sourced, never run. The one home for the host's service
# manager: start a long job that outlives main's /clear and a closed Orca
# window, list the jobs, ask whether one is running, point at how one ended,
# and box a foreground command. Linux: transient `systemd-run --user` units and
# scopes, unchanged. Mac: launchd jobs in the gui/<uid> domain, unboxed (the owner
# 2026-09-29): macOS has no cgroup MemoryMax.
# Call sites pass the Linux box size and never branch on the OS themselves.
# COMMANDECK_HOST_OS overrides `uname -s` so a self-test drives either branch;
# a self-test whose stubs are systemd's pins it to Linux.
HS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HS_PREFIX=com.commandeck.
# A real Mac repairs PATH here, at load: callers forward PATH="$PATH" into a
# launchd job, and a login shell's PATH has /usr/bin ahead of gnubin. A failed
# repair is not fatal here; hs__mac_start's preflight then refuses the job.
[ "$(uname -s)" != Darwin ] || . "$HS_DIR/paths.sh" || true

hs_os() { printf '%s' "${COMMANDECK_HOST_OS:-$(uname -s)}"; }

# hs_load -- {load: [1m, 5m, 15m], swap: {totalMb, usedMb}}, each null when it
# cannot be read: Linux /proc, the Mac's sysctl. It branches on /proc itself,
# not hs_os, so a test pinned to Linux on a Mac still reads real numbers.
hs_load() {
  local load swap
  if [ -r /proc/loadavg ]; then
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    swap=$(awk '/^SwapTotal:/ { t = $2 } /^SwapFree:/ { f = $2 } END { if (t != "") printf "%d %d", t / 1024, (t - f) / 1024 }' /proc/meminfo)
  else
    load=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | xargs)
    swap=$(sysctl -n vm.swapusage 2>/dev/null | awk 'function mb(v) { return v ~ /G$/ ? v * 1024 : v + 0 }
      { for (i = 1; i < NF; i++) { if ($i == "total") t = $(i + 2); if ($i == "used") u = $(i + 2) } }
      END { if (t != "") printf "%d %d", mb(t), mb(u) }')
  fi
  jq -cn --arg load "$load" --arg swap "$swap" '
    def n: if . == "" then null else (try tonumber catch null) end;
    {load: (if $load == "" then null else [$load | splits(" +") | select(. != "") | n] end),
     swap: (if $swap == "" then null else ($swap | split(" ") | {totalMb: (.[0] | n), usedMb: (.[1] | n)}) end)}'
}

# hs_stamp -- {host, load1, swapUsedMb, at}: the load an event started or ended
# under, carried in its own ledger row (review rounds, replays, chain runs).
hs_stamp() {
  hs_load | jq -c --arg h "$(hostname -s 2>/dev/null)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{host: $h, load1: (.load[0]? // null), swapUsedMb: (.swap.usedMb? // null), at: $at}'
}

# hs_start <name> <box> [VAR=value...] -- <command>...
# Starts <command> as job <name> with exactly the given environment and
# returns once the manager accepted it. HS_PRINT=1 prints the launch instead;
# on the Mac the plist is still written, so the print names a real file.
hs_start() {
  local name=$1 box=$2 envs=() kv
  shift 2
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ $# -gt 1 ] || { echo "usage: hs_start <name> <box> [VAR=value...] -- <command>..." >&2; return 2; }
  shift
  if [ "$(hs_os)" = Darwin ]; then hs__mac_start "$name" "$box" ${envs[@]+"${envs[@]}"} -- "$@"; return; fi
  local args=(--user --unit="$name" --collect --quiet -p MemoryMax="$box" -p LimitNOFILE=1048576)
  for kv in ${envs[@]+"${envs[@]}"}; do args+=("--setenv=$kv"); done
  if [ -n "${HS_PRINT:-}" ]; then printf 'systemd-run %s %s\n' "${args[*]}" "$*"; return 0; fi
  ${COMMANDECK_WAKE_LAUNCHER:-systemd-run} "${args[@]}" "$@"
}

# The & is escaped: from Bash 5.2 a bare & in the replacement is the match.
# hs__sd <value> -- for a quoted value in a systemd unit: a backslash, a quote
# and a percent sign are syntax there.
hs__sd() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "${s//%/%%}"; }
hs__xml() { local s=${1//&/\&amp;}; s=${s//</\&lt;}; printf '%s' "${s//>/\&gt;}"; }

hs__mac_start() {
  local name=$1 path= kv a bad= want
  shift 2
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); case $1 in PATH=*) path=${1#PATH=} ;; esac; shift; done
  shift
  [ -n "${PP_SCRATCH:-}" ] || . "$HS_DIR/paths.sh" || return 1
  # launchd starts a job with its own bare PATH, so the forwarded one is all
  # the job has. Without Homebrew Bash first every script dies on Bash 3.2,
  # without GNU sed first the edits go wrong, and without the Node major a
  # repo pins its own tools cannot run. Refuse here, before anything starts.
  # The Node major is checked only where the repo pins one in .nvmrc.
  want=$(cut -d. -f1 "$HS_DIR/../.nvmrc" 2>/dev/null | tr -d v || true)
  [[ $want =~ ^[0-9]+$ ]] || want=
  [ "$(PATH=$path bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" -ge 4 ] 2>/dev/null || bad+=" bash-4+"
  grep -q GNU <<<"$(PATH=$path sed --version 2>/dev/null)" || bad+=" GNU-sed"
  [ -z "$want" ] || case $(PATH=$path node --version 2>/dev/null) in "v$want".*) ;; *) bad+=" node-$want" ;; esac
  [ -z "$bad" ] || { echo "host-services: $name NOT started; the PATH it would run with lacks:$bad (PATH=$path)" >&2; return 2; }

  local dir=$PP_SCRATCH/scratchpad uid label=$HS_PREFIX$name
  uid=$(id -u)
  local plist=$dir/$name.plist log=$dir/$name.launchd.log
  mkdir -p "$dir"
  # The job log catches what the command's own log cannot: a failure before
  # its redirect opens.
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0"><dict>\n<key>Label</key><string>%s</string>\n<key>ProgramArguments</key><array>\n' "$label"
    # Homebrew $BASH execs the command, so a bare `bash` resolves on the
    # forwarded PATH rather than launchd's own.
    for a in "$BASH" -c 'exec "$@"' "$name" "$@"; do printf '<string>%s</string>\n' "$(hs__xml "$a")"; done
    printf '</array>\n<key>EnvironmentVariables</key><dict>\n'
    for kv in ${envs[@]+"${envs[@]}"}; do printf '<key>%s</key><string>%s</string>\n' "$(hs__xml "${kv%%=*}")" "$(hs__xml "${kv#*=}")"; done
    printf '</dict>\n<key>WorkingDirectory</key><string>%s</string>\n<key>RunAtLoad</key><true/>\n' "$(hs__xml "$HOME")"
    printf '<key>StandardOutPath</key><string>%s</string>\n<key>StandardErrorPath</key><string>%s</string>\n</dict></plist>\n' \
      "$(hs__xml "$log")" "$(hs__xml "$log")"
  } > "$plist" || { echo "host-services: cannot write $plist" >&2; return 2; }
  if [ -n "${HS_PRINT:-}" ]; then printf 'launchctl bootstrap gui/%s %s\n' "$uid" "$plist"; return 0; fi
  # A finished job stays loaded, holding its label, until it is booted out;
  # clear finished ones first, as systemd's --collect does at exit.
  launchctl list 2>/dev/null | awk -F'\t' -v p="$HS_PREFIX" '$1 == "-" && index($3, p) == 1 {print $3}' \
    | while read -r a; do launchctl bootout "gui/$uid/$a" 2>/dev/null || true; done
  launchctl bootstrap "gui/$uid" "$plist" || { echo "host-services: launchctl refused $label; job log $log" >&2; return 1; }
}

# hs_list [systemctl list-units flags] [<glob>...] -- systemctl's plain grammar
# on both hosts: `<name>.service loaded <active> <sub> <description>`. On the
# Mac a running job is active/running and a finished one that failed is
# failed/failed; a clean finish shows only with --all, as inactive/dead.
# Both hosts return 1 when the manager gives no answer, so a caller can tell an
# unknown state from no jobs. A Linux host with no systemctl at all (exit 127)
# has no jobs: nothing could have started one.
hs_list() {
  if [ "$(hs_os)" != Darwin ]; then
    local rc=0
    timeout 8 systemctl --user list-units "$@" 2>/dev/null || rc=$?
    case $rc in 0|127) return 0 ;; esac
    echo "host-services: systemctl list-units failed; the service state is unknown" >&2; return 1
  fi
  local all= active= pats=() a out
  for a in "$@"; do
    case $a in --all) all=1 ;; --state=active) active=1 ;; -*) ;; *) pats+=("$a") ;; esac
  done
  out=$(launchctl list 2>/dev/null) || { echo "host-services: launchctl list failed; the service state is unknown" >&2; return 1; }
  while IFS=$'\t' read -r pid rc label; do
    [ "${label#"$HS_PREFIX"}" != "$label" ] || continue
    local n=${label#"$HS_PREFIX"}.service st hit= p
    if [[ $pid =~ ^[0-9]+$ ]]; then st="active running"
    elif [ -n "$active" ]; then continue
    elif [ "$rc" != 0 ]; then st="failed failed"
    elif [ -n "$all" ]; then st="inactive dead"
    else continue; fi
    [ ${#pats[@]} -gt 0 ] || hit=1
    for p in ${pats[@]+"${pats[@]}"}; do [[ $n == $p ]] && hit=1; done
    [ -z "$hit" ] || printf '%s loaded %s launchd job\n' "$n" "$st"
  done <<<"$out"
  return 0
}

hs_stop() { # <name> -- stop job <name>; the manager's own exit status
  if [ "$(hs_os)" != Darwin ]; then systemctl --user stop "${1%.service}.service"; return; fi
  launchctl bootout "gui/$(id -u)/$HS_PREFIX${1%.service}"
}

# hs_proc <name> -- `<pid>\t<start epoch>\t<command>` for a running job, the
# command as the manager launched it. Returns 1 when the job is not running and
# 2 when the manager's answer is missing or malformed: live-drift.sh compares
# the start with a commit, and an unknown start must never read as current.
hs_proc() {
  local n=${1%.service} out pid st cmd
  if [ "$(hs_os)" != Darwin ]; then
    out=$(LC_ALL=C timeout 8 systemctl --user show -p MainPID -p ActiveState -p ExecMainStartTimestamp -p ExecStart "$n.service" 2>/dev/null) || return 2
    # A missing or unknown state is malformed, never "not running".
    case $(sed -n 's/^ActiveState=//p' <<<"$out") in
      active) ;;
      inactive|failed|activating|deactivating|reloading|maintenance) return 1 ;;
      *) return 2 ;;
    esac
    pid=$(sed -n 's/^MainPID=//p' <<<"$out")
    st=$(sed -n 's/^ExecMainStartTimestamp=//p' <<<"$out")
    # argv[] runs to the next ` ; ignore_errors=`: a bash -lc wrapper has `;` of its own.
    cmd=$(sed -n 's/^ExecStart=.*argv\[\]=\(.*\) ; ignore_errors=.*/\1/p' <<<"$out" | head -1)
  else
    out=$(launchctl list 2>/dev/null) || return 2
    pid=$(awk -F'\t' -v l="$HS_PREFIX$n" '$3 == l {print $1}' <<<"$out")
    [[ $pid =~ ^[0-9]+$ ]] || return 1
    st=$(LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null) && cmd=$(ps -ww -o command= -p "$pid" 2>/dev/null) || return 2
  fi
  [[ $pid =~ ^[1-9][0-9]*$ ]] && [ -n "$st" ] && [ -n "$cmd" ] || return 2
  st=$(LC_ALL=C date -d "$st" +%s 2>/dev/null) || return 2
  printf '%s\t%s\t%s\n' "$pid" "$st" "$cmd"
}

hs_active() { # <name> -- 0 while the job runs, 1 when it ended or never was, 2 when the manager gives no answer
  local out rc
  if [ "$(hs_os)" != Darwin ]; then
    out=$(timeout 8 systemctl --user is-active "$1" 2>/dev/null); rc=$?
    [ "$rc" = 0 ] && return 0
    case $rc:$out in 127:*|*:inactive|*:failed) return 1 ;; *) return 2 ;; esac
  fi
  out=$(hs_list --state=active "${1%.service}.service") || return 2
  [ -n "$out" ]
}

# hs_driver_units -- the unit of every live drive, loop or run driver, one per
# line. A driver is `<kind>-<unit>-<epoch>.service` exactly; a chain is no
# driver. Returns 1 when the service state is unknown.
hs_driver_units() {
  local out
  out=$(hs_list --no-legend --plain --state=active 'loop-*' 'drive-*' 'run-*.service') || return 1
  sed -En 's/^(loop|drive|run)-(.+)-[0-9]+\.service .*/\2/p' <<<"$out"
}

# hs_unit_driven <unit> -- 0 only when a live driver positively owns <unit>. An
# empty unit or an unknown service state is 1, so a caller keeps its send.
hs_unit_driven() {
  local units
  [ -n "${1:-}" ] && units=$(hs_driver_units) && grep -qxF -- "$1" <<<"$units"
}

# hs_log_hint <name> -- the command that shows how job <name> ended. Not
# `systemctl status`: --collect unloads the unit the moment it exits, and that
# command then answers with property defaults -- an exit 7 reads as status 0.
# Not `launchctl list | grep` on the Mac either: bash-guardrails.sh refuses it in
# main, because orca-wait.sh already reports every driver's state with the wake.
hs_log_hint() {
  if [ "$(hs_os)" != Darwin ]; then printf 'journalctl --user -u %s.service --no-pager | tail -2' "$1"; return; fi
  printf 'tail -2 %s' "$PP_SCRATCH/scratchpad/$1.launchd.log"
}

# hs_cage <box> -- sets HS_CAGE to the prefix that runs ONE foreground command
# inside a memory box and keeps its terminal: a systemd scope on Linux, none on
# the Mac, which runs unboxed. Returns 1 with HS_CAGE empty only where Linux
# has no systemd-run.
hs_cage() {
  HS_CAGE=()
  [ "$(hs_os)" != Darwin ] || return 0
  command -v systemd-run >/dev/null || return 1
  HS_CAGE=(systemd-run --user --scope -p MemoryMax="$1" --quiet)
}
