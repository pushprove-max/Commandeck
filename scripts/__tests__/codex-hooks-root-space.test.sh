#!/usr/bin/env bash
# codex-hooks-root-space.test.sh -- the plugin is installed wherever its owner
# keeps it, and that path may hold a space. Codex's hook command names the
# plugin by path. What this pins: under such a root the command still runs the
# dispatcher, setup still counts the entries as its own, and they can be trusted.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

P="$T/a root's"; mkdir -p "$T/home" "$T/cx" "$P/hooks"
printf '#!/bin/sh\ncat >/dev/null\ntouch "%s"\n' "$T/ran" > "$P/hooks/codex-dispatch.sh"; chmod +x "$P/hooks/codex-dispatch.sh"
: > "$T/cx/config.toml"
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
( cd "$T/proj" && export HOME=$T/home CODEX_HOME=$T/cx COMMANDECK_MAIN=$T/proj COMMANDECK_SCRATCH=$T/scratch COMMANDECK_WORKSPACES=$T/ws
  . "$ROOT/scripts/paths.sh" && . "$ROOT/scripts/install-lib.sh"
  il_codex_hooks "$P" && il_codex_count "$P" > "$T/count" && il_codex_count > "$T/all" ) >"$T/out" 2>&1
check "the entries are written" 0 $?
check "all five count as the plugin's, pointing at that root" "5 5" "$(cat "$T/count" 2>/dev/null) $(cat "$T/all" 2>/dev/null)"
bash -c "$(jq -r '.hooks.Stop[0].hooks[0].command' "$T/cx/hooks.json" 2>/dev/null)" </dev/null >/dev/null 2>&1
check "the command runs the dispatcher" yes "$([ -e "$T/ran" ] && echo yes || echo no)"
python3 "$ROOT/scripts/codex-hook-trust.py" "$T/cx" >/dev/null 2>&1
python3 "$ROOT/scripts/codex-hook-trust.py" --check "$T/cx" >/dev/null 2>&1; check "and its entries are trusted" 0 $?
# The dispatcher gone or not runnable (the plugin folder moved or deleted): the
# command must not read as a clean turn. Exit 1 and one line, as the
# dispatcher's own "could not run" is: not a silent 0, and not a refusal.
chmod -x "$P/hooks/codex-dispatch.sh"
echo '{}' | bash -c "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$T/cx/hooks.json" 2>/dev/null)" >/dev/null 2>"$T/err"; RC=$?
check "with no dispatcher the command exits 1 and says the hooks did not run" "1 1" "$RC $(grep -c 'did NOT run' "$T/err")"
# A plain root's command is spelled as it always was: its trust hash does not move.
( cd "$T/proj" && export HOME=$T/home CODEX_HOME=$T/cx COMMANDECK_MAIN=$T/proj COMMANDECK_SCRATCH=$T/scratch COMMANDECK_WORKSPACES=$T/ws
  . "$ROOT/scripts/paths.sh" && . "$ROOT/scripts/install-lib.sh"; il_codex_hooks /opt/plain ) >/dev/null 2>&1
check "a plain root is written unquoted, re-pointing the same five" 5 "$(jq '[.hooks[][].hooks[] | select(.command | startswith("S=/opt/plain/hooks/codex-dispatch.sh; "))] | length' "$T/cx/hooks.json" 2>/dev/null)"

[ "$FAIL" = 0 ] || cat "$T/out"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
