#!/usr/bin/env bash
# builder-launch.sh [--risky] [--dry-run] [--small] [--model <alias> --reason '<one line>'] <unit> <batch-brief>
# -- open one Builder:
# a NEW worktree on local main, fast-forwarded from origin first (pp_sync_main), with the Builder profile (worktree-setup.sh
# --builder), the one-page brief rendered from
# templates/_builder-brief-template.md into <wt>/.claude/briefs/<unit>.md,
# and one roles.builder pane (seat.sh launch). --dry-run prints the rendered
# brief and creates nothing. The pass script of the configured profile
# (builder-codex-pass.sh or builder-claude-pass.sh) runs its --preflight
# first, so a launch that could not run its passes fails before anything is
# created.
# --risky: the batch is one main marks risky. A roles.design-coauthor pane opens
# first in the same worktree and writes <wt>/.claude/briefs/<unit>-design.md,
# which the brief tells the Builder to read before it builds. That call opens
# no Builder; the same command run again, once the note exists, opens it.
# A tooling build expected under 200 changed lines may be launched --small on the
# smaller model with --model sonnet; a risky one stays on the configured model,
# and its batch brief says to write the failing test first.
# Every Builder runs with no advisor, a risky one included (owner's order
# 2026-10-14): set-up no longer offers one, and one an older set-up stored is
# not read. Only an advisor written into routing.json's roles.builder by hand
# is given, and --small, main's word that the batch is expected under 200
# changed lines, drops even that.
# Nothing checks the word against the finished diff; the first pass counts the
# real lines. Every launch prints which rule chose, on stderr.
# --model puts this one Builder on another model routing.json names (an alias,
# as set-up's --builder-model takes); the pick and its reason go to
# $COMMANDECK_ROUTING_LOG, default <main>/.claude/routing-log, as one
# routing-override line, written by the call that opens the Builder.
set -euo pipefail
USAGE="usage: builder-launch.sh [--risky] [--dry-run] [--small] [--model <alias> --reason '<one line>'] <unit> <batch-brief>"
RISKY=0 DRY=0 SMALL=0 PICK=0 BMODEL='' REASON=''
while :; do
  case ${1:-} in
    --risky) RISKY=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --small) SMALL=1; shift ;;
    --model) PICK=1 BMODEL=${2:-}; shift $(($# > 1 ? 2 : 1)) ;;
    --reason) PICK=1 REASON=${2:-}; shift $(($# > 1 ? 2 : 1)) ;;
    *) break ;;
  esac
done
UNIT=${1:?$USAGE}
BATCH=${2:?$USAGE}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad unit name: $UNIT" >&2; exit 2; }
pp_unit_name "$UNIT" || exit 2
[ -s "$BATCH" ] || { echo "empty batch brief: $BATCH" >&2; exit 2; }
WT=$PP_WORKSPACES/$UNIT
# Two Builders never share a worktree: a reused one carries another batch's diff and event log.
# A risky launch's own worktree, made by its first call, is the one exception.
if [ -e "$WT" ] && ! { [ "$RISKY" = 1 ] && [ "$DRY" = 0 ] && [ -f "$WT/.claude/briefs/$UNIT-design-spec.md" ]; }; then echo "REFUSED: $WT already exists; a Builder starts in a new worktree" >&2; exit 2; fi

if [ "$PICK" = 1 ]; then
  pp_builder_model_ok "$BMODEL" || exit 2
  # A log line is read as key=value words, so the reason holds no = and is one line.
  [[ -n $REASON && $REASON != *[=$'\n']* ]] || { echo "REFUSED: --model needs --reason '<one line, no = sign>'; the pick is logged with it" >&2; exit 2; }
fi
ADVISOR=0 RULE='none (the default Builder has no advisor)'
if [ -n "$(pp_route_json builder "" "$BMODEL" | jq -r '.advisor // empty')" ]; then
  if [ "$SMALL" = 1 ]; then RULE='none (the advisor routing.json names; marked small)'
  else ADVISOR=1 RULE='kept (routing.json names it)'; fi
fi
OPTS=()
[ "$PICK" = 0 ] || OPTS+=(--model "$BMODEL")
[ "$ADVISOR" = 1 ] || OPTS+=(--no-advisor)
# The Builder opens here, after its worktree and brief exist: the one place the pick is logged.
open_builder() {
  if [ "$PICK" = 1 ]; then
    printf '%s unit=%s note=routing-override builder %s: %s\n' "$(date +%F)" "$UNIT" "$BMODEL" "$REASON" >> "${COMMANDECK_ROUTING_LOG:-$PP_MAIN/.claude/routing-log}" \
      || { echo "could not write the routing log; the Builder was not launched" >&2; exit 1; }
  fi
  exec bash "$HERE/seat.sh" launch builder "$UNIT" "$WT/.claude/briefs/$UNIT.md" ${OPTS[@]+"${OPTS[@]}"}
}

BY=$(pp_pass)
PRE=$(bash "$HERE/builder-$BY-pass.sh" --preflight) || exit 2
MODEL=${PRE%%$'\t'*}
DESIGN=""
[ "$RISKY" = 1 ] && DESIGN=$'\n'"## Design check"$'\n\n'"This batch is marked risky. Read \`.claude/briefs/$UNIT-design.md\` before you build and follow it; the design pane writes it, so wait for it when it is not there yet."$'\n'

# The batch goes in last, so a placeholder inside it is never substituted; the
# quoted replacements keep an & in any value literal. The advisor paragraph
# sits between two marker lines: a Builder with no advisor gets one line in
# its place, so its brief never sends it to a consult it does not have.
T=$(cat "$HERE/../templates/_builder-brief-template.md")
[[ $T == *$'\n<!-- advisor -->\n'*$'\n<!-- /advisor -->\n'* ]] || { echo "REFUSED: the brief template has lost its advisor markers" >&2; exit 2; }
if [ "$ADVISOR" = 1 ]; then
  T=${T/$'<!-- advisor -->\n'/}
  T=${T/$'<!-- /advisor -->\n'/}
else
  T="${T%%'<!-- advisor -->'*}This build has no advisor. Do not try a consult; write no consult line in the evidence file."$'\n'"${T#*$'<!-- /advisor -->\n'}"
fi
T=${T//'{unit}'/"$UNIT"}
T=${T//'{UNIT}'/"${UNIT^^}"}
T=${T//'{review-model}'/"$MODEL"}
T=${T//'{reviewer}'/"${BY^}"}
T=${T//'{pass-script}'/"builder-$BY-pass.sh"}
T=${T//'{scripts}'/"$PP_SCRIPTS_Q"}
T=${T//'{design}'/"$DESIGN"}
# The review loop the owner chose at setup; with every default taken the brief reads as it always did.
SMALL=$(pp_review_loop smallBuild 200 '^[1-9][0-9]*$') && MAXR=$(pp_review_loop maxRounds '' '^[1-9][0-9]*$') \
  && CLOSING=$(pp_review_loop closingPass yes '^(yes|no)$') || exit 2
LOOP=
[ -z "$MAXR" ] || LOOP+="This project allows at most $MAXR rounds: a pass numbered over $MAXR is refused. Before that, stop and report to main what is still open."$'\n'
[ "$CLOSING" != no ] || LOOP+="This project runs no closing pass: skip step 3. The narrowed pass that ends \`VERDICT: GO\` is the one the merge takes, once narrowed passes have read every commit after the first pass; change nothing after it."$'\n'
T=${T//'{small-build}'/"$SMALL"}
T=${T//$'{loop-rules}\n'/"$LOOP"}
# Its headings go two levels down, so a batch with a level-1 title of its own stays inside "## The batch": the
# dashboard reads the issues from that section, and its reader takes any "# " line as a heading.
T=${T//'{batch}'/"$(sed -E 's/^(#+ )/##\1/' "$BATCH")"}
echo "advisor: $RULE" >&2
# The dashboard's "Issue by issue" list is read from the brief (brief-issues.sh): said here, before a build starts with an empty one.
[ "$DRY" = 0 ] || [ "$(bash "$HERE/brief-issues.sh" <(printf '%s\n' "$T"))" != '[]' ] \
  || echo "issues: this brief names no work item, so the dashboard will list none for the build. Start the batch file as templates/_batch-brief-template.md does: a section '## The issues' with one numbered line per item ('1. #12: title')." >&2
if [ "$DRY" = 1 ]; then printf '%s\n' "$T"; exit 0; fi

# The second call of a risky launch: the first made the worktree and opened the
# design pane. The Builder opens only once the note is written; nothing waits.
NOTE=$WT/.claude/briefs/$UNIT-design.md
if [ "$RISKY" = 1 ] && [ -f "$WT/.claude/briefs/$UNIT-design-spec.md" ]; then
  [ -s "$NOTE" ] || { echo "no design note at $NOTE yet; the Builder was not launched. Run this again once the design pane has written it." >&2; exit 1; }
  open_builder
fi

pp_sync_main "$PP_MAIN" || exit 1
pp_worktree_new "$UNIT" || exit 1
bash "$HERE/worktree-setup.sh" "$WT" --builder
mkdir -p "$WT/.claude/briefs"
printf '%s\n' "$T" > "$WT/.claude/briefs/$UNIT.md"
# Main's own copy: the pass script reads the stated limits from it, never from the Builder's.
mkdir -p "$PP_MAIN/.claude/briefs" && printf '%s\n' "$T" > "$PP_MAIN/.claude/briefs/$UNIT-builder-brief.md" \
  || { echo "could not keep main's copy of the brief for $UNIT" >&2; exit 1; }
if [ "$RISKY" = 1 ]; then
  printf 'Design check for the batch below, before its Builder starts. Read the code the batch touches, then write the design note `.claude/briefs/%s-design.md`: the design to follow, what can break and how each risk is tested. Write that one file and no code. Print DESIGN-DONE on its own line when the note is written.\n\n%s\n' \
    "$UNIT" "$(cat "$BATCH")" > "$WT/.claude/briefs/$UNIT-design-spec.md"
  bash "$HERE/seat.sh" launch design-coauthor "$UNIT" "$WT/.claude/briefs/$UNIT-design-spec.md" \
    || { echo "the design pane did not open for $UNIT; the Builder was not launched" >&2; exit 1; }
  echo "design pane open for $UNIT; no Builder yet. Once it has written $NOTE, run the same command again to open the Builder."
  exit 0
fi
open_builder
