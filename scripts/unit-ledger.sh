#!/usr/bin/env bash
# unit-ledger.sh <unit> local [--append] -- print a merged unit's row, or with --append add it once per unit and
# merge sha to <main>/.claude/metrics/unit-ledger.jsonl (issue 271).
# unit-ledger.sh --escaped <unit> <issue> -- add {unit, escaped: [issue], recordedAt}: a defect the unit's review
# passed and something later found (issue 272).
#
# The dashboard's review panels read what a unit's review loop cost and how it ended long after its worktree, round
# files and panes are gone; seat-events.jsonl holds what each seat spent, never how the loop ended. The merge passes
# the outcome, read from the round files it already checks: UNIT_LEDGER_MERGE_SHA, UNIT_LEDGER_VERDICT,
# UNIT_LEDGER_ROUNDS, UNIT_LEDGER_GO_ROUNDS, UNIT_LEDGER_NO_GO_ROUNDS, and
# UNIT_LEDGER_MERGE_RULE. Seats are the unit's seat-events.jsonl rows; tokens
# are the unit's Claude transcripts, from its first launch on (seat-event.sh --usage); Codex passes are not in them.
# A metric with no source is null and named in gaps, never 0. findings and fixRounds always are: the plugin keeps
# no per-round finding counts, and its Builder fixes its own rounds, with no fixer seat to count.
# The file is append-only: an --append with no merge sha or no verdict is refused, as that row could never be joined
# to an outcome. An escape is a row of its own, and a unit with no merged row is tagged all the same (an escape can
# outlive its entry).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -4; exit 0 ;; esac
set -uo pipefail
HERE=$(dirname "${BASH_SOURCE[0]}")
. "$HERE/paths.sh" || exit 1
FILE=$PP_MAIN/.claude/metrics/unit-ledger.jsonl
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# append <row> <jq test> <jq args>... -- under a lock, so two merges cannot both find a row missing, add the row
# unless an earlier one passes the test (returns 3).
append() {
  local row=$1 test=$2; shift 2
  mkdir -p "${FILE%/*}" 2>/dev/null; { : >> "$FILE"; } 2>/dev/null || { echo "unit-ledger: cannot write $FILE" >&2; return 1; }
  {
    flock -w 10 9 || { echo "unit-ledger: $FILE stayed locked for 10 s" >&2; return 1; }
    [ "$(jq -Rn "$@" "any(inputs | fromjson? // empty; $test)" "$FILE")" != true ] || return 3
    printf '%s\n' "$row" >&9
  } 9>> "$FILE"
}

if [ "${1-}" = --escaped ]; then
  UNIT=${2-} N=${3-}
  [[ $UNIT =~ ^[A-Za-z0-9._-]+$ ]] || { echo "unit-ledger: invalid unit: $UNIT" >&2; exit 2; }
  [[ $N =~ ^[1-9][0-9]*$ ]] || { echo "unit-ledger: an escape is an issue number, not '$N'" >&2; exit 2; }
  append "$(jq -cn --arg unit "$UNIT" --argjson n "$N" --arg at "$NOW" '{unit: $unit, escaped: [$n], recordedAt: $at}')" \
    '.unit == $u and ([.escaped[]?] | any(. == $n))' --arg u "$UNIT" --argjson n "$N"
  case $? in 0) echo "recorded unit=$UNIT escaped=$N" ;; 3) echo "already recorded unit=$UNIT escaped=$N" ;; *) exit 1 ;; esac
  exit 0
fi

UNIT=${1-} MODE=${3-}
[[ $UNIT =~ ^[A-Za-z0-9._-]+$ ]] && [ "${2-}" = local ] && { [ -z "$MODE" ] || [ "$MODE" = --append ]; } \
  || { echo "usage: unit-ledger.sh <unit> local [--append] | --escaped <unit> <issue>" >&2; exit 2; }
SHA=${UNIT_LEDGER_MERGE_SHA:-} VERDICT=${UNIT_LEDGER_VERDICT:-}
if [ "$MODE" = --append ] && { [ -z "$SHA" ] || [ -z "$VERDICT" ]; }; then
  echo "unit-ledger: refusing to append unit=$UNIT: no merge sha or no verdict was passed (UNIT_LEDGER_MERGE_SHA, UNIT_LEDGER_VERDICT)" >&2
  exit 1
fi
SEATS=${COMMANDECK_SEAT_EVENTS:-$PP_MAIN/.claude/metrics/seat-events.jsonl}
[ -f "$SEATS" ] || SEATS=/dev/null
# The first launch on record: the dispatch the wall time runs from, and the start of the transcripts' count (an
# earlier worktree of the same name was another unit).
FIRST=$(jq -Rnr --arg u "$UNIT" '[inputs | fromjson? // empty | select(.unit == $u) | .launchedAt | fromdate?] | min // empty' "$SEATS")
TOKENS=null
for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(pp_slug "$PP_WORKSPACES/$UNIT")"/*.jsonl; do
  [ -f "$f" ] || continue
  # A log that cannot be read leaves the sum unknown, never short.
  U=$(bash "$HERE/seat-event.sh" --usage claude "$f" ${FIRST:+"$FIRST"} 2>/dev/null) || { TOKENS=unread; break; }
  [ -n "$U" ] && [ "$U" != null ] || continue
  TOKENS=$(jq -cn --argjson a "$TOKENS" --argjson b "$U" '$b.tokens as $t | if $a == null then $t else $a | with_entries(.value += $t[.key]) end')
done
[ "$TOKENS" != unread ] || TOKENS=null
MERGED=$([ -z "$SHA" ] || git -C "$PP_MAIN" show -s --format=%ct "$SHA" 2>/dev/null)
ROW=$(jq -Rnc --arg unit "$UNIT" --arg sha "$SHA" --arg verdict "$VERDICT" --arg merged "$MERGED" --arg first "$FIRST" \
  --arg rounds "${UNIT_LEDGER_ROUNDS:-}" --arg go "${UNIT_LEDGER_GO_ROUNDS:-}" --arg nogo "${UNIT_LEDGER_NO_GO_ROUNDS:-}" \
  --arg rule "${UNIT_LEDGER_MERGE_RULE:-}" --argjson tokens "$TOKENS" --arg at "$NOW" '
  def n: if test("^[0-9]+$") then tonumber else null end;
  def s: if . == "" then null else . end;
  [inputs | fromjson? // empty | select(.unit == $unit)] as $ev | ($merged | n) as $m | ($first | n) as $f
  | {unit: $unit, mergeSha: ($sha | s), mergedAt: ($m | if . then todate else null end),
     firstDispatchAt: ($f | if . then todate else null end),
     wallHours: (if $m and $f then (($m - $f) / 360 | round) / 10 else null end),
     rounds: ($rounds | n), goRounds: ($go | n), noGoRounds: ($nogo | n), fixRounds: null, verdict: ($verdict | s),
     mergeRule: ($rule | s),
     findings: null, expensivePasses: null,
     seats: [$ev[] | {round, role, model, tokens: (if .tokens then (.tokens.input // 0) + (.tokens.output // 0) else null end)}
       + (if .tokensReason then {tokensReason} else {} end)],
     tokens: $tokens}
  | .gaps = [to_entries[] | select(.value == null) | .key]
      + (if .seats == [] then ["seats"] elif any(.seats[]; .tokens == null) then ["seatTokens"] else [] end)
  | .recordedAt = $at' "$SEATS")
[ -n "$ROW" ] || { echo "unit-ledger: could not build the row for unit=$UNIT" >&2; exit 1; }
[ "$MODE" = --append ] || { printf '%s\n' "$ROW"; exit 0; }
append "$ROW" '.unit == $u and .mergeSha == $s' --arg u "$UNIT" --arg s "$SHA"
case $? in 0) echo "recorded unit=$UNIT mergeSha=$SHA" ;; 3) echo "already recorded unit=$UNIT mergeSha=$SHA" ;; *) exit 1 ;; esac
