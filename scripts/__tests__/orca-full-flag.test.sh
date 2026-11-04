#!/usr/bin/env bash
# covers: scripts/ask-main.sh
# Orca 1.4.246's concise views drop fields the plugin reads: an inbox row has no read, to_handle, created_at or
# from_handle; a check row no body, thread_id or from_handle, and its result no dispatchId; a task-list row no spec,
# display_name or task_title. A reader of a dropped field sees null and acts as if nothing came (issue 588: ask-main
# missed main's answer, the drain showed messages with no body). Pinned: every read of such a field passes --full.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
cd "$REAL" || exit 1
# reads <verb> <field regex> -- file:line of each `orca-ide orchestration <verb>` command (not a comment, not a hint in
# quoted text) whose command line or the 60 lines after it (a python reader can sit that far down) read a full-only
# field, and whose command lacks --full. pp_worker_done_since reads created_at and from_handle from its stdin.
reads() {
  awk -v verb="$1" -v fre="$2" '
    FNR == 1 { delete L; n = 0 }
    { L[++n] = $0 }
    ENDFILE {
      for (i = 1; i <= n; i++) {
        if (L[i] ~ /^[ \t]*#/ || L[i] !~ ("(^[ \t]*|[$][(]|[|&;({] *|timeout [0-9]+ )orca-ide orchestration " verb "( |$)")) continue
        w = ""; for (j = i; j <= i + 60 && j <= n; j++) w = w "\n" L[j]
        if (w ~ fre && L[i] !~ /--full/) print FILENAME ":" i
      }
    }' scripts/*.sh hooks/*.sh | paste -sd' ' -
}
check "an inbox read that uses a full-only field passes --full" "" \
  "$(reads inbox 'to_handle|from_handle|created_at|[.]read[ )]|thread_id|payload|pp_worker_done_since')"
check "a task-list read that uses spec or display_name passes --full" "" "$(reads task-list '[.]spec[^a-z_]|display_name|task_title')"
check "a check read that uses body, thread_id or from_handle passes --full" "" \
  "$(reads check '[.]body[^a-z_]|"body"|thread_id|from_handle')"
# Two reads keep their output for later lines: the wake's task list (orca-wait.sh, read for .spec past the window) and
# the awareness hook's (written to a file, read for .spec and .task_title), and orca-wait's check is built in BASE.
check "the wake's and the awareness hook's task-list reads pass --full" "1 1" \
  "$(grep -c 'tj=$(orca-ide orchestration task-list --full --json' scripts/orca-wait.sh) $(grep -c 'orca-ide orchestration task-list --full --json >"$OT/tasks"' hooks/agent-awareness.sh)"
check "the wake's check reads pass --full" 1 "$(grep -c '^BASE=(orchestration check --full)$' scripts/orca-wait.sh)"
check "a worker brief that names check's dispatchId names --full" "" \
  "$(grep -n 'result.dispatchId of `orca-ide orchestration check' scripts/*.sh | grep -v -- '--full' | cut -d: -f1-2 | paste -sd' ' -)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
