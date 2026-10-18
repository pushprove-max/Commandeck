#!/usr/bin/env bash
# plan-tier.sh picks the Auto answer to "Write a plan first?" from the batch brief's "The issues" and "The batch"
# sections. A panel trigger in a sub-heading of those sections (### Authentication) is a trigger as much as one in a
# line of text: it picked nothing, so a security batch got one tier too low. The words of the section's own
# heading ("The batch") pick nothing.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd -P)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
tier() { printf '%s\n' "$@" > "$T/brief.md"; (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/scratch" \
  bash "$REAL/scripts/plan-tier.sh" "$T/brief.md" 2>/dev/null | sed -n 's/^tier: \([^(]*\) (.*/\1/p'); }
check "a panel word in a sub-heading of The batch picks Panel" "Panel" "$(tier '## The batch' '### Authentication' '1. rework the screen')"
check "the same brief with a plain sub-heading does not" "Plan + judge" "$(tier '## The batch' '### The screen' '1. rework the screen')"
check "a panel word in a sub-heading of The issues picks Panel" "Panel" "$(tier '## The issues' '### Password reset' '1. rework the screen')"
check "a panel word in a heading outside those sections picks nothing" "Plan + judge" "$(tier '## Notes' '### Authentication' '## The batch' '1. rework the screen')"
check "a panel word in an item line still picks Panel" "Panel" "$(tier '## The batch' '1. tighten the login check')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
