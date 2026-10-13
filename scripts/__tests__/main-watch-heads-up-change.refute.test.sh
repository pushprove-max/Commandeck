#!/usr/bin/env bash
set -euo pipefail
MAIN_WATCH_TEST_HALF=setup source "$(dirname "$0")/main-watch.test.sh"

sid=face0000-0000-0000-0000-000000000001
transcript "$sid" "$T/ws/wt-changed-note"
: > "$T/sends"

offers "$sid" 60000000 "Same claim." "Original explanation"
tick 60000
[ "$(hu)" = 1 ] || fail "the original note was not delivered"

offers "$sid" 60060000 "Same claim." "Changed explanation"
tick 60060
[ "$(hu)" = 2 ] || fail "new explanation was swallowed by a delivered group"
has "changed note" "Changed explanation"
