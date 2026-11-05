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
templates/main-session.md|Main never compacts: write the checkpoint, the hook restarts main|A restart at the line is routine: do not propose moving the line.
templates/main-session.md|Working rules (standing instruction 2026-08-07; orchestrator and advisor ruling 2026-09-12)|(`rg` for symbols; serena is for Builder seats only)
templates/main-session.md|Details (not injected)|Announce a worker once, at dispatch (agent, model, worktree, task)
templates/main-session.md|Details (not injected)|A lookup one `rg` answers stays in main
templates/global-rules.md|Working and review|No old-data support by default: write no migration, compatibility branch, legacy fallback, dual read or write, or old-shape case.
templates/global-rules.md|Working and review|Ask the owner only when a live old-shape row, token or record is known to exist, and give the count.
templates/global-rules.md|Agents and tokens|Tag only a claim you did not verify: [likely] (inferred, not run) or [uncertain]; a claim you ran or read needs no tag.
templates/global-rules.md|Working and review|Done is one of the pass's stop lines: a closing pass that ends GO (P3 findings alone are GO); passes run until clean.
templates/global-rules.md|Tests and planning|main finds them with rg; a symbol tool is for Builder seats only
templates/global-rules.md|Tests and planning|A plan step that adds an abstraction, a config surface or a dependency names the simplest alternative it considered and why that loses.
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

folded() { tr -s ' \n' '  ' < "$SOURCE/$1"; }
# removed rules gone from templates. Catches: a rule the owner removed from the reference project left in a plugin
# template, so every pane keeps obeying it (one status line, the restart-report ban, serena in main, tagging every
# claim, asking before old-data support, and the alternatives rule's "a dependency or a file").
LEFT=""
for f in "$SOURCE"/templates/*.md; do
  for old in 'End each turn with one status line' 'do not report how often main restarts' 'serena for symbols' \
    'A lookup serena or one' 'Tag each claim' 'Ask before building backward compatibility' 'a dependency or a file' \
    'Announce every worker'; do
    folded "templates/${f##*/}" | grep -qF -- "$old" && LEFT="$LEFT [${f##*/}: $old]"
  done
done
check "removed rules gone from templates" "" "$LEFT"
# host-only items stay single. Catches: a rule the reference project keeps in one home copied into a second plugin
# template, where the two drift apart: the compaction keep-list (the startup file only, which Codex reads too), the
# inbox wake bullet (main's card only), the smallest-change rule (the global rules only), and no product fallbacks
# section in any template (a product rule, not the plugin's).
count() { local n=0 f; for f in "$SOURCE"/templates/*.md; do folded "templates/${f##*/}" | grep -qF -- "$1" && n=$((n + 1)); done; echo $n; }
check "host-only items stay single" "1 1 1 1 1 0" \
  "$(count 'When this conversation is compacted, keep:') $(folded templates/AGENT_STARTUP.md | grep -cF 'When this conversation is compacted, keep:') \
$(count 'Orca inbox: wait on it, never a poll loop') $(count 'Pick the smallest change that FULLY solves the problem') \
$(folded templates/global-rules.md | grep -cF 'Pick the smallest change that FULLY solves the problem') \
$(cat "$SOURCE"/templates/*.md | grep -ciE '^#+ .*fallback')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
