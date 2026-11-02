#!/usr/bin/env bash
# template-sections.test.sh -- issue 544: the reference project's changed rule sections are ported into the plugin's
# templates. Each line of PORTED is: template | section heading | one sentence of the ported rule. A section is read
# from its "## <heading>" line to the next "## " line, with line breaks folded, so a rewrap does not fail the test.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

PORTED=$(cat <<'EOF'
templates/global-rules.md|Working and review|may come with its failing test as a fenced diff
templates/global-rules.md|Working and review|lists each reviewer test path under `## Reviewer tests`
templates/global-rules.md|Agents and tokens|Author, review and triage-only worktrees never use a build slot
templates/global-rules.md|Agents and tokens|Record a unit parked on purpose with `unit-hold.sh
templates/global-rules.md|Agents and tokens|the worktree head, the main head and `origin/main` are unchanged
templates/global-rules.md|Agents and tokens|Never launch an agent by hand with `setsid` or `nohup`
templates/global-rules.md|Agents and tokens|When a worker must name many test files, run two per invocation
templates/global-rules.md|Tests and planning|One map per unit, explored once
templates/global-rules.md|Tests and planning|A script that changes many records pastes its dry-run output
templates/global-rules.md|Tests and planning|A pass never waits for green
templates/global-rules.md|Tests and planning|A test killed at its time limit gave no result
templates/global-rules.md|Agents and tokens|A closing reply over about 3,000 characters
templates/main-session.md|Main never compacts: write the checkpoint, the hook restarts main|`decision.sh add` and `TaskStop`
templates/main-session.md|Main never compacts: write the checkpoint, the hook restarts main|do not report how often main restarts
templates/_builder-brief-template.md|How to work|A plan reviewer may print its inputs with `peek.sh --unit
templates/_builder-brief-template.md|How to work|do not start or restart Orca
templates/_batch-brief-template.md|The batch (done criteria)|every file of the item is .json, .yaml, .yml, .toml, .md or .txt
EOF
)

section() { awk -v h="## $2" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$SOURCE/$1" | tr -s ' \n' '  '; }

# Catches: a rule section the reference project changed that the plugin's template still lacks, so a user who installs
# the plugin gets the older rule.
MISSING=""
while IFS='|' read -r tpl head key; do
  section "$tpl" "$head" | grep -qF -- "$key" || MISSING="$MISSING [$tpl#$head: $key]"
done <<<"$PORTED"
check "each ported rule section is in its template" "" "$MISSING"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
