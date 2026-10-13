#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source <(sed -n '/^heads_up_capture() {/,/^}/p; /^hu_take() {/,/^}/p' scripts/main-watch.sh)
hu_cwd() { :; }
hu_save() { saved=$1; }
HU_LEDGER=/dev/null/ledger HU_STORE=/dev/null
HU_WINDOW_MS=300000 ST=/nonexistent HU_DONE=/nonexistent/handled
saved=
record='{"id":"aaaa0000-0000-0000-0000-000000000001","shownAt":40000000,"cwd":"/fixture/known-worktree","line":"Claim","explanation":"Explanation"}'
replay() { HU_LOG=$1; heads_up_capture; }
replay <(printf '%s\n' "$record")
printf '%s\n' "$saved" |
  jq -e '.groups[].members[0].cwd == "/fixture/known-worktree"' >/dev/null ||
  { echo "FAIL: recovery discarded known provenance"; exit 1; }
