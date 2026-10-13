#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source <(sed -n '/^hu_take() {/,/^}/p' scripts/main-watch.sh)
hu_cwd() { printf '/fixture/worktree'; }
hu_save() { saved=$1; }
HU_WINDOW_MS=300000 ST=/nonexistent HU_DONE=/nonexistent/handled HU_LOG=/nonexistent/log
led='{"pairs":{},"groups":{}}'
saved=untouched
hu_take '{"id":"aaaa0000-0000-0000-0000-000000000001","at":1e100,"line":"Claim","explanation":"Explanation","archived":true}'
[ "$saved" = untouched ] ||
  { echo "FAIL: invalid timestamp overwrote persisted state"; exit 1; }
