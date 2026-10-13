#!/usr/bin/env bash
# file-open-findings.sh <unit> <merge-sha> [--area <area>] [--milestone <name>] [--dry-run]
#
# Files ONE GitHub issue per finding a unit merged with. Stdin is the proof
# builder-codex-pass.sh --verify prints: its "Open at merge: " lines are the
# findings, its "Builder proof: " line names the round file. merge-unit-local.sh
# runs this after the squash commit; run by hand with the same lines it files
# what a GitHub failure left unfiled, without merging again.
#
# Each issue is created with a type label (bug), the finding's own level (P2 or
# P3) and the area label --area names. Without --area it is filed without one
# and "ADD AN AREA LABEL to #n" is printed.
# Needs the gh CLI, logged in, in a checkout with a GitHub remote. Without any
# of the three every finding is answered NOT FILED and the exit code is 4.
#
# No duplicate: the body carries a key made of the finding's file and title,
# not the unit, and an OPEN issue holding that key is named instead of filed.
# A lookup that fails files nothing: the finding may be open already.
#
# Answers as it goes, so a caller that outlives this script knows what it
# owes: first one "KEY <key>: <finding>" line per finding, before any call to
# GitHub, then one answer per finding in that order, failures included, each
# ending with " [<key>]": "FILED #n: ", "ALREADY OPEN #n: ", "WOULD FILE " or
# "NOT FILED: ". A finding with a KEY line and no answer was never reached.
# Last, "Issues: <n>..." for the merge's output. Exit 0; 2 usage; 4 when a finding
# could not be filed.
# shortcut: the key changes when a reviewer rewords the title, and that finding is filed again; match on the file alone if that happens often.
set -uo pipefail
usage() { sed -n '2p' "$0" | sed 's/^# /usage: /' >&2; exit 2; }
UNIT=${1:-} SHA=${2:-}
[ -n "$UNIT" ] && [ -n "$SHA" ] && [ "${SHA#--}" = "$SHA" ] || usage
shift 2
AREA="" MILESTONE="" DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --area) AREA=${2:-}; shift 2 || usage ;;
    --milestone) MILESTONE=${2:-}; shift 2 || usage ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done
PROOF=$(cat)
ROUND_FILE=$(sed -n 's/^Builder proof: \([^:]*\):.*/\1/p' <<<"$PROOF" | head -1)
FINDINGS=$(sed -n 's/^Open at merge: //p' <<<"$PROOF")
[ -n "$FINDINGS" ] || { echo "Issues:"; exit 0; }

git cat-file -e "$SHA^{commit}" 2>/dev/null || { echo "file-open-findings: $SHA is not a commit of this repository" >&2; exit 2; }
[ -z "$AREA" ] || AREA=area:${AREA#area:}

parse() { # <finding line>: sets LEVEL, TITLE, WHERE, TEXT, REPRO (the failing input or command, when the line has one) and KEY
  local REST
  LEVEL=$(grep -oE '\[P[0-3]\]' <<<"$1" | head -1 | tr -d '[]')
  REST=$(sed -E 's/^[[:space:]]*([-*][[:space:]]*)?\[P[0-3]\][[:space:]]*//' <<<"$1")
  TITLE=${REST%% -- *}; REST=${REST#"$TITLE"}; REST=${REST# -- }
  WHERE=${REST%% -- *}; REST=${REST#"$WHERE"}; REST=${REST# -- }
  # The first separator ends the reason: a command may hold " -- " itself.
  TEXT=${REST%% -- *}; REPRO=${REST#"$TEXT"}; REPRO=${REPRO# -- }
  KEY=pp-finding-$(printf '%s|%s' "${WHERE%%:*}" "$(tr '[:upper:]' '[:lower:]' <<<"$TITLE" | tr -cs 'a-z0-9' ' ')" | shasum | cut -c1-16)
}
KEYS=""
while IFS= read -r LINE; do parse "$LINE"; KEYS+="KEY $KEY: $LINE"$'\n'; done <<<"$FINDINGS"
printf '%s' "$KEYS"
ISSUES=() RC=0
while IFS= read -r LINE; do
  parse "$LINE"
  LABELS=(--label bug --label "${LEVEL:-P2}" ${AREA:+--label "$AREA"})
  if ! FOUND=$(gh issue list --state open --search "\"$KEY\" in:body" --json number --jq '.[0].number // empty' 2>&1); then
    echo "NOT FILED: $LINE (the lookup for an open issue failed: ${FOUND##*$'\n'}) [$KEY]"; RC=4; continue
  fi
  if [ -n "$FOUND" ]; then echo "ALREADY OPEN #$FOUND: $TITLE [$KEY]"; ISSUES+=("$FOUND"); continue; fi
  if [ "$DRY_RUN" = 1 ]; then echo "WOULD FILE (bug, ${LEVEL:-P2}${AREA:+, $AREA}${MILESTONE:+, milestone $MILESTONE}): $TITLE [$KEY]"; continue; fi
  BODY="$UNIT was merged with this review finding still open.

- Unit: $UNIT
- Merge commit: $SHA
- Where: $WHERE
- Level: ${LEVEL:-P2}
- Round file: ${ROUND_FILE:-not named in the proof}

$TEXT
${REPRO:+
Failing input or command:

    $REPRO
}
Finding key: $KEY"
  if ! URL=$(gh issue create --title "$TITLE" --body "$BODY" "${LABELS[@]}" ${MILESTONE:+--milestone "$MILESTONE"} 2>&1); then
    echo "NOT FILED: $LINE (gh issue create failed: ${URL##*$'\n'}) [$KEY]"; RC=4; continue
  fi
  N=${URL##*/}
  echo "FILED #$N: $TITLE [$KEY]"; ISSUES+=("$N")
  [ -n "$AREA" ] || echo "ADD AN AREA LABEL to #$N"
done <<<"$FINDINGS"
echo "Issues:${ISSUES[*]:+ ${ISSUES[*]}}"
exit "$RC"
