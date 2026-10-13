#!/usr/bin/env bash
# install-lib-link.test.sh -- a settings path that is a link to a file not made
# yet (a dotfiles checkout) is the owner's. Setup writes through it. What this
# pins: taking the install back out removes what setup wrote and leaves the
# link as it was; read as "did not exist", the link was deleted and the file
# setup made stayed behind.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

mkdir -p "$T/home" "$T/dotfiles"
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
ln -s "$T/dotfiles/settings.json" "$T/proj/settings.json"
( cd "$T/proj" && export HOME=$T/home COMMANDECK_MAIN=$T/proj COMMANDECK_SCRATCH=$T/scratch COMMANDECK_WORKSPACES=$T/ws
  . "$ROOT/scripts/paths.sh" && . "$ROOT/scripts/install-lib.sh"
  il_record "$T/m.json" own "$T/proj/settings.json" && echo '{"plugin": 1}' | il_write "$T/proj/settings.json" && il_restore "$T/m.json" ) >"$T/out" 2>&1
check "record, write and restore succeed" 0 $?
check "the owner's link is still there, pointing where it did" "$T/dotfiles/settings.json" "$(readlink "$T/proj/settings.json" 2>/dev/null)"
check "what setup wrote through it is gone" no "$([ -e "$T/dotfiles/settings.json" ] && echo yes || echo no)"

# A settings file that is there and empty (touched, or cut short) passes
# setup's check. jq prints nothing for it, and what was written was nothing.
: > "$T/proj/empty.json"
( cd "$T/proj" && export HOME=$T/home COMMANDECK_MAIN=$T/proj COMMANDECK_SCRATCH=$T/scratch COMMANDECK_WORKSPACES=$T/ws
  . "$ROOT/scripts/paths.sh" && . "$ROOT/scripts/install-lib.sh"
  il_record "$T/m2.json" own "$T/proj/empty.json" && il_allow_set "$T/m2.json" "$T/proj/empty.json" '["Bash(x:*)"]' ) >>"$T/out" 2>&1
check "the plugin's rules are added to an empty settings file" 0 $?
check "and the file is a JSON object holding them" '["Bash(x:*)"]' "$(jq -c '.permissions.allow' "$T/proj/empty.json" 2>&1)"
check "the record says which rules were added" '["Bash(x:*)"]' "$(jq -c --arg p "$T/proj/empty.json" '.entries[$p].added' "$T/m2.json" 2>&1)"

[ "$FAIL" = 0 ] || cat "$T/out"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
