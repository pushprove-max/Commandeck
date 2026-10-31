#!/usr/bin/env bash
# review-pass-report.sh -- how often each later review pass found something, by kind of unit (issue 514).
# Reads <main>/.claude/metrics/unit-ledger.jsonl. A pass found something when its round has a P0, P1 or P2 line,
# whether or not main later cleared it. "Later" is every pass after the first (n >= 2). Kind of unit is the Tier word
# of the unit's plan, <main>/.claude/plans/<unit>.md; `unknown` when the plan or its Tier line is absent. A row with
# no `passes` (from before the key, or a round that could not be read) shows its verdicts only and says so.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -5; exit 0 ;; esac
set -uo pipefail
HERE=$(dirname "${BASH_SOURCE[0]}")
. "$HERE/paths.sh" || exit 1
FILE=$PP_MAIN/.claude/metrics/unit-ledger.jsonl
[ -s "$FILE" ] || { echo "review-pass-report: no unit ledger at $FILE: no unit was merged since it was added" >&2; exit 1; }
TIERS=$(for u in $(jq -Rr 'fromjson? // empty | select(.mergeSha and (.unit | test("^[A-Za-z0-9._-]+$"))) | .unit' "$FILE" | sort -u); do
  jq -n --arg u "$u" --arg t "$(sed -n 's/^Tier: *\([A-Za-z]*\).*/\1/p' "$PP_MAIN/.claude/plans/$u.md" 2>/dev/null | head -1)" \
    '{($u): ($t | if . == "" then "unknown" else . end)}'
done | jq -s 'add // {}')
jq -Rnr --argjson tiers "$TIERS" '
  [inputs | fromjson? // empty | select(.mergeSha)] as $rows
  | ($rows | map(select(.passes | type == "array"))) as $with
  | ($with | group_by($tiers[.unit] // "unknown")[]
      | [.[].passes[] | select(.n >= 2)] as $later
      | ($later | map(select(.p0 + .p1 + .p2 > 0)) | length) as $found
      | "\(.[0] | $tiers[.unit] // "unknown") (\(length) units): later passes \($later | length), found something \($found)"
        + (if ($later | length) > 0 then " (\($found * 100 / ($later | length) | round)%)" else "" end)),
    ($rows[] | select(.passes | type != "array")
      | "\(.unit): \(.verdict // "?"), \(.goRounds // "?") GO / \(.noGoRounds // "?") NO-GO, no pass data")' "$FILE"
