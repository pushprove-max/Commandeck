#!/usr/bin/env bash
# A background job on macOS starts with the PATH it is handed and nothing
# else, so the launcher refuses a PATH that lacks what the scripts need and
# names what is missing. It also demanded a Node version file, which most
# repos do not have: every launch there failed, whatever the PATH held.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/empty"
. "$REAL/scripts/paths.sh" || exit 1
. "$REAL/scripts/host-services.sh"
[ ! -e "$REAL/.nvmrc" ] || { echo "FAIL setup: this repo has a .nvmrc; the test needs a repo without one"; exit 1; }
ERR=$(COMMANDECK_SCRATCH=$TMP hs__mac_start probe unused "PATH=$TMP/empty" -- true 2>&1); rc=$?
check "a PATH without the tools is refused" 2 "$rc"
check "the refusal names what the PATH lacks" 1 "$(grep -c 'lacks:.*bash-4+.*GNU-sed' <<<"$ERR")"
check "a repo with no Node version file is not refused for that" 0 "$(grep -ci 'node' <<<"$ERR")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
