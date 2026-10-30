#!/usr/bin/env bash
# builder-add-work.sh <unit> -- hand a running Builder the work main just added to its rulings file, in a fresh
# session of the same pane, the way a fix round starts: the old session's whole context is not replayed on every
# call of the new work.
# Main writes the work to .claude/briefs/<unit>-main-rulings.md in its own checkout first. The Builder is told to
# bring its evidence file up to date and end its turn; builder-fresh-round.sh then waits for the pane to settle,
# types /clear and points the new session at a hand-off that stands alone, the rulings inlined, since a worker
# cannot read main's checkout. A pane that never settles keeps the work in its old session.
# After the unit's first review pass only a change main marks --small, with a reason, is added (issue 304).
# Added work names one probe per item, --unless '<path>:<text>' (issue 385): the item is on the branch when <path> at
# the branch's committed HEAD holds <text>. Every probe found answers "already done" and sends nothing, so a Builder is
# never handed work it has; a send with no probe is refused; the hand-off lists the probes not yet on the branch.
# --answer <text> (issue 478) hands main's answer to a Builder whose prompt cache went cold (answer-worker.sh) the same
# way, in <unit>-answer-<epoch>.md: the rulings are inlined when they exist, the Builder is not sent the stop note, and
# an answer adds no scope, so it takes no probe and the first-pass guard does not apply.
# Exit 0 handed over (the /clear follows in the background), 1 not sent, 2 refused, 3 no live Builder pane, 4 already
# done.
# Self-test: bash scripts/__tests__/builder-add-work.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
USAGE="usage: builder-add-work.sh <unit> --unless '<path>:<text>' [--unless ...] [--small --reason '<one line>'] | builder-add-work.sh <unit> --answer <text>"
UNIT=${1:?$USAGE}; shift
SMALL="" SMALLF=0 PROBES=() ANSWER=
while [ $# -gt 0 ]; do
  case $1 in
    --answer) ANSWER=${2:?$USAGE}; shift 2 ;;
    --unless) [[ ${2:-} == ?*:?* ]] || { echo "builder-add-work: --unless takes '<path>:<text>'; nothing was sent" >&2; exit 2; }; PROBES+=("$2"); shift 2 ;;
    --small) SMALLF=1; shift ;;
    --reason) SMALL=${2:-}; shift $(($# > 1 ? 2 : 1)) ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done
[ "$SMALLF" = 0 ] || [ -n "$SMALL" ] || { echo "builder-add-work: --small takes --reason '<one line>'; nothing was sent" >&2; exit 2; }
[ "$SMALLF" = 1 ] || SMALL=""
WT=$PP_WORKSPACES/$UNIT RUL=$PP_MAIN/.claude/briefs/$UNIT-main-rulings.md
[ -d "$WT/.claude/briefs" ] || { echo "builder-add-work: no Builder worktree at $WT" >&2; exit 1; }
# Issue 304: scope that changes behaviour after the first pass makes every later pass review a moving target.
[ -n "$ANSWER" ] || [ ! -e "$WT/.claude/briefs/$UNIT-r1-reports.md" ] || [ -n "$SMALL" ] || { echo "builder-add-work: $UNIT has had its first review pass, and added scope after the first review pass is a follow-up unit; file it, or pass --small for a change under about 50 lines (--small --reason '<one line>'). Nothing was sent" >&2; exit 2; }
[ -n "$ANSWER" ] || [ -s "$RUL" ] || { echo "builder-add-work: write the added work to $RUL first; nothing was sent" >&2; exit 1; }
ABSENT=()
if [ -z "$ANSWER" ]; then
  # Issue 385: added work the branch already holds reopened a converged loop. Only committed work counts (HEAD).
  [ "${#PROBES[@]}" -gt 0 ] || { echo "builder-add-work: added work needs --unless '<path>:<text>' for each item, so work already on the branch is never sent; nothing was sent" >&2; exit 2; }
  for P in "${PROBES[@]}"; do
    git -C "$WT" grep -qF -e "${P#*:}" HEAD -- "${P%%:*}" 2>/dev/null; rc=$?
    case $rc in 0) ;; 1) ABSENT+=("$P") ;; *) echo "builder-add-work: cannot read the branch in $WT (git grep exit $rc); nothing was sent" >&2; exit 1 ;; esac
  done
  [ "${#ABSENT[@]}" -gt 0 ] || { echo "builder-add-work: already done on $(git -C "$WT" rev-parse --abbrev-ref HEAD) at $(git -C "$WT" rev-parse HEAD | cut -c1-12): ${PROBES[*]}; nothing was sent" >&2; exit 4; }
fi
H=$(pp_seat_pane "unit-$UNIT" "$WT")
[ -n "$H" ] || { echo "builder-add-work: no live Builder pane for $UNIT; nothing was sent" >&2; exit 3; }
# Issue 478: an answer is not added work. It adds no scope, so it passes the first-pass guard, the rulings check, the
# probes and the stop note; the hand-off is the answer file, the rulings inlined when main has written any.
if [ -n "$ANSWER" ]; then HAND=$WT/.claude/briefs/$UNIT-answer-$(date +%s).md
else HAND=$WT/.claude/briefs/$UNIT-added-$(date +%Y%m%d-%H%M%S).md; fi
{
  if [ -n "$ANSWER" ]; then
    printf '# %s: main answered your question\n\n' "$UNIT"
    printf 'You are the Builder of %s, in a fresh session of the same pane: your prompt cache had gone cold, so the session that built so far was cleared, and this file and the files it names are all you have.\n\n' "$UNIT"
  else
    printf '# %s: work added mid-build\n\n' "$UNIT"
    printf 'You are the Builder of %s, in a fresh session of the same pane: main added work, and the session that built so far was cleared, so this file and the files it names are all you have.\n\n' "$UNIT"
  fi
  printf -- '- Worktree: %s. Orca handle: %s; your dispatch id is .result.dispatchId of `orca-ide orchestration check --terminal %s --json`, which also reads your inbox.\n' "$WT" "$H" "$H"
  printf -- '- Read the brief whole, it still binds you: %s\n' "$WT/.claude/briefs/$UNIT.md"
  printf -- '- Read the evidence file whole, it says what is built, verified and left: %s\n' "$WT/.claude/briefs/$UNIT-evidence.md"
  if [ -n "$ANSWER" ]; then
    printf -- '- Main'"'"'s answer to your question is below, with the rulings main has written. Carry on with the task you were on and report it as before.\n'
  else
    printf -- '- Build the added work below with the rest, then acknowledge it before your next pass: builder-codex-pass.sh --ack-rulings %s\n' "$UNIT"
    printf -- '- Not yet on your branch, by main'"'"'s probes (<path>:<text>): %s\n' "${ABSENT[*]}"
  fi
  [ -z "$SMALL" ] || printf -- '- Main added it after the first review pass as a small change, under about 50 lines: %s\n' "$SMALL"
  echo
  if [ -s "$RUL" ]; then printf '## Main'"'"'s rulings, the added work included (%s)\n\n' "$RUL"; cat "$RUL"
  else printf '## Main'"'"'s rulings\n\nMain has written no rulings for %s (%s is absent), so none were left out.\n' "$UNIT" "$RUL"; fi
  [ -z "$ANSWER" ] || printf '\n## Main'"'"'s answer\n\n%s\n' "$ANSWER"
} > "$HAND"
if [ -z "$ANSWER" ]; then
  orca-ide orchestration send --to "$H" --type status --subject "work added to $UNIT" \
    --body "Main added work to $UNIT. Finish the step you are on, write the evidence file current (built, verified, left), then end your turn and start nothing new: a fresh session of this pane takes the added work from ${HAND##*/}." --json >/dev/null 2>&1 \
    || { rm -f "$HAND"; echo "builder-add-work: the note to $UNIT's pane failed; nothing was handed over" >&2; exit 1; }
fi
mkdir -p "$PP_SCRATCH"
# A plain background child, as builder-codex-pass.sh starts a fix round.
bash "$HERE/builder-fresh-round.sh" "$H" "$HAND" "$PP_SCRATCH/seat-$UNIT-builder.txt" > "$PP_SCRATCH/$UNIT-added.log" 2>&1 &
[ -n "$ANSWER" ] && STOPPED=idle || STOPPED="told to stop"
echo "builder-add-work: $UNIT ($H) $STOPPED; a fresh session takes ${HAND##*/} once the pane settles. If nothing is typed within 15 minutes, $PP_SCRATCH/$UNIT-added.log says why, and main is told."
