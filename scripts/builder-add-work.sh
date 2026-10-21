#!/usr/bin/env bash
# builder-add-work.sh <unit> -- hand a running Builder the work main just added to its rulings file, in a fresh
# session of the same pane, the way a fix round starts: the old session's whole context is not replayed on every
# call of the new work.
# Main writes the work to .claude/briefs/<unit>-main-rulings.md in its own checkout first. The Builder is told to
# bring its evidence file up to date and end its turn; builder-fresh-round.sh then waits for the pane to settle,
# types /clear and points the new session at a hand-off that stands alone, the rulings inlined, since a worker
# cannot read main's checkout. A pane that never settles keeps the work in its old session.
# After the unit's first review pass only a change main marks --small, with a reason, is added (issue 304).
# Exit 0 handed over (the /clear follows in the background), 1 not sent, 2 refused, 3 no live Builder pane.
# Self-test: bash scripts/__tests__/builder-add-work.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
UNIT=${1:?usage: builder-add-work.sh <unit> [--small --reason '<one line>']}
SMALL=""
[ "${2:-}" != --small ] || { [ "${3:-}" = --reason ] && [ -n "${4:-}" ] && SMALL=$4 \
  || { echo "builder-add-work: --small takes --reason '<one line>'; nothing was sent" >&2; exit 2; }; }
WT=$PP_WORKSPACES/$UNIT RUL=$PP_MAIN/.claude/briefs/$UNIT-main-rulings.md
[ -d "$WT/.claude/briefs" ] || { echo "builder-add-work: no Builder worktree at $WT" >&2; exit 1; }
# Issue 304: scope that changes behaviour after the first pass makes every later pass review a moving target.
[ ! -e "$WT/.claude/briefs/$UNIT-r1-reports.md" ] || [ -n "$SMALL" ] || { echo "builder-add-work: $UNIT has had its first review pass, and added scope after the first review pass is a follow-up unit; file it, or pass --small for a change under about 50 lines (--small --reason '<one line>'). Nothing was sent" >&2; exit 2; }
[ -s "$RUL" ] || { echo "builder-add-work: write the added work to $RUL first; nothing was sent" >&2; exit 1; }
H=$(pp_seat_pane "unit-$UNIT" "$WT")
[ -n "$H" ] || { echo "builder-add-work: no live Builder pane for $UNIT; nothing was sent" >&2; exit 3; }
HAND=$WT/.claude/briefs/$UNIT-added-$(date +%Y%m%d-%H%M%S).md
{
  printf '# %s: work added mid-build\n\n' "$UNIT"
  printf 'You are the Builder of %s, in a fresh session of the same pane: main added work, and the session that built so far was cleared, so this file and the files it names are all you have.\n\n' "$UNIT"
  printf -- '- Worktree: %s. Orca handle: %s; your dispatch id is .result.dispatchId of `orca-ide orchestration check --terminal %s --json`, which also reads your inbox.\n' "$WT" "$H" "$H"
  printf -- '- Read the brief whole, it still binds you: %s\n' "$WT/.claude/briefs/$UNIT.md"
  printf -- '- Read the evidence file whole, it says what is built, verified and left: %s\n' "$WT/.claude/briefs/$UNIT-evidence.md"
  printf -- '- Build the added work below with the rest, then acknowledge it before your next pass: builder-codex-pass.sh --ack-rulings %s\n' "$UNIT"
  [ -z "$SMALL" ] || printf -- '- Main added it after the first review pass as a small change, under about 50 lines: %s\n' "$SMALL"
  echo
  printf '## Main'"'"'s rulings, the added work included (%s)\n\n' "$RUL"; cat "$RUL"
} > "$HAND"
orca-ide orchestration send --to "$H" --type status --subject "work added to $UNIT" \
  --body "Main added work to $UNIT. Finish the step you are on, write the evidence file current (built, verified, left), then end your turn and start nothing new: a fresh session of this pane takes the added work from ${HAND##*/}." --json >/dev/null 2>&1 \
  || { rm -f "$HAND"; echo "builder-add-work: the note to $UNIT's pane failed; nothing was handed over" >&2; exit 1; }
mkdir -p "$PP_SCRATCH"
# A plain background child, as builder-codex-pass.sh starts a fix round.
bash "$HERE/builder-fresh-round.sh" "$H" "$HAND" "$PP_SCRATCH/seat-$UNIT-builder.txt" > "$PP_SCRATCH/$UNIT-added.log" 2>&1 &
echo "builder-add-work: $UNIT ($H) told to stop; a fresh session takes ${HAND##*/} once the pane settles. If nothing is typed within 15 minutes, $PP_SCRATCH/$UNIT-added.log says why, and main is told."
