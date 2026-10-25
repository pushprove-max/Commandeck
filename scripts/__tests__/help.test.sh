#!/usr/bin/env bash
# Issue 222: a script run with --help went on to do its work; to-main.sh read --help as a message type and sent it.
# What this pins: every runnable script under scripts/ prints its usage on --help or -h, exits 0, calls no Orca,
# GitHub or agent CLI, and writes nothing. The sourced libraries are skipped: their $1 is the caller's.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
mkdir -p "$T/bin" "$T/home" "$T/scratch" "$T/ws"
for c in orca-ide orca gh claude codex launchctl systemctl osascript crontab security open tmux; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$c" "$T" > "$T/bin/$c"; chmod +x "$T/bin/$c"
done
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
files() { find "$T" -path "$T/calls" -prune -o -print | sort; }
for f in "$REAL"/scripts/*.sh; do
  n=${f##*/}
  case $n in paths.sh|install-lib.sh|host-services.sh|project-main.sh|cos-lib.sh|requirements.sh|peer-offload.sh) continue ;; esac
  for a in --help -h; do
    : > "$T/calls"; before=$(files)
    out=$(cd "$T/proj" && env -u CLAUDE_PROJECT_DIR -u ORCA_TERMINAL_HANDLE HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/proj" \
      COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" timeout 20 bash "$f" "$a" 2>&1 < /dev/null); rc=$?
    check "$n $a: exits 0, prints its usage, calls nothing, writes nothing" "0:yes:0:same" \
      "$rc:$([ -n "$out" ] && echo yes || echo no):$(grep -c . "$T/calls"):$([ "$before" = "$(files)" ] && echo same || echo changed)"
  done
done
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
