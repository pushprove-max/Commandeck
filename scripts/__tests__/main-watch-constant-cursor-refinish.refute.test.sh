#!/usr/bin/env bash
# Orca 1.4.220 never moves an agent pane's output cursor, so a follow-up turn
# that starts and finishes between ticks shows only as session-log growth. The
# service first sees this pane already `done`, so no `working` tick ever
# located its log before the first finish settled.
set -euo pipefail
MAIN_WATCH_TEST_HALF=setup source "$(dirname "$0")/main-watch.test.sh"

: > "$T/sends"
seat wt-logfast term_logfast task_logfast 23000
LOG=$T/session.jsonl
printf '{}\n' > "$LOG"
printf 'session=%s\n' "$LOG" > "$F/state-wt-logfast"
echo 'VERDICT: GO' > "$F/verdict-term_logfast"
# No out-term_logfast file: the fake pane cursor stays at 0 throughout.
state term_logfast done
tick 23060
[ "$(posts wt-logfast)" = 1 ] || fail "first finish was not posted"

sed -i 's/^task_logfast running$/task_logfast completed/' "$F/tasks"
printf '{"followup":"completed"}\n' >> "$LOG"
tick 23120
[ "$(posts wt-logfast)" = 2 ] || fail "session-log growth did not post the second finish"

# The pane is seen `working` before its session log can be located, so a growth
# record exists with no log in it; the log appears by the time it finishes.
: > "$T/sends"
seat wt-latelog term_latelog task_latelog 24000
state term_latelog working
tick 24000
LOG=$T/late-session.jsonl
printf '{}\n' > "$LOG"
printf 'session=%s\n' "$LOG" > "$F/state-wt-latelog"
echo 'VERDICT: GO' > "$F/verdict-term_latelog"
state term_latelog done
tick 24060
[ "$(posts wt-latelog)" = 1 ] || fail "first finish was not posted"

sed -i 's/^task_latelog running$/task_latelog completed/' "$F/tasks"
printf '{"followup":"completed"}\n' >> "$LOG"
tick 24120
[ "$(posts wt-latelog)" = 2 ] ||
  fail "late-discovered session log did not post second finish"
