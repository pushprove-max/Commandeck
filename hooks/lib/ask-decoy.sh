#!/usr/bin/env bash
# Sourced by worker-ask-guard.sh, ruling-log.sh and ask-records-decision.sh
# (which skips recording a picker the guard refuses): the one home of the decoy
# label main puts first on every AskUserQuestion picker. Orca's inbox
# alert starts with a line break, which acts as Enter on an open picker and
# picks the highlighted first option; with the decoy first, that stray Enter
# picks nothing that counts. Change it here only: the guard demands it and the
# log voids it, so the two must never disagree.
ASK_DECOY="— don't pick: ask me again —"

# ask_decoy_first <hook input> -- 0 when every question's first option is the
# decoy. worker-ask-guard.sh refuses a main picker on 1; ask-records-decision.sh
# records nothing for it. One test, so the two can never disagree.
ask_decoy_first() {
  jq -e --arg d "$ASK_DECOY" 'all(.tool_input.questions[]?; .options[0].label == $d)' <<<"$1" >/dev/null 2>&1
}
