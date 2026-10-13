#!/usr/bin/env bash
set -euo pipefail
MAIN_WATCH_TEST_HALF=setup source "$(dirname "$0")/main-watch.test.sh"

: > "$T/sends"
seat wt-refinish term_refinish task_refinish 23000
echo 'VERDICT: GO' > "$F/verdict-term_refinish"
state term_refinish working; tick 23000
state term_refinish done; tick 23060
[ "$(posts wt-refinish)" = 1 ] || fail "first finish was not posted"

sed -i 's/^task_refinish running$/task_refinish completed/' "$F/tasks"
printf 'follow-up completed\n' >> "$F/out-term_refinish"
# The follow-up worked and finished between ticks; Orca is still `done`.
tick 23120
[ "$(posts wt-refinish)" = 2 ] || fail "second finish was lost between ticks"
