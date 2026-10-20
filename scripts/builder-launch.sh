#!/usr/bin/env bash
# builder-launch.sh [--risky] [--dry-run] [--small] [--keep <billing|all|a keep word>[,...]] [--model <alias> --reason '<one line>'] [--effort medium|high --reason '<one line>'] <unit> <batch-brief>
# -- open one Builder:
# a NEW worktree, or the unit's planning one it takes over (plan-worktree-close.sh --adopt), on local main, fast-forwarded from origin first (pp_sync_main), with the Builder profile (worktree-setup.sh
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
# no Builder; the same command run again, once the note exists, opens it. With no --effort that second call keeps the
# effort the first recorded; with one it rewrites the brief's override and adds an "effort changed at Builder launch"
# line to the evidence before the pane opens, refused while that Builder already runs; two second calls of one unit, or one and a
# Builder opened by hand with seat.sh, run one at a time, and each record is replaced whole. Any other change to the brief
# between the calls is refused.
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
# An independent issue the batch's Size lines estimate over setup's issue sizing line (40K tokens by default) is
# named on stderr before anything is created, the split proposed; main splits it or launches as is.
# --keep <billing|all|a keep word> keeps what a Builder pane drops by default (Stripe; all: the whole cut; a word in
# commandeck.json's keeps: its skills and plugins) and is stored in the worktree for reruns; see worktree-setup.sh.
# --model puts this one Builder on another model routing.json names (an alias,
# as set-up's --builder-model takes); the pick and its reason go to
# $COMMANDECK_ROUTING_LOG, default <main>/.claude/routing-log, as one
# routing-override line, written by the call that opens the Builder.
# --effort raises this one Builder above the setup default (medium unless set-up chose another): medium or high
# only, with a reason. The brief and the evidence file get one line, "effort override: builder <default> -> <used>:
# <reason>", which the dashboard reads to mark the build raised. Every launch prints the effort it uses, on stderr.
# A plan is written before every build (owner's order 2026-10-17): every launch, a dry run included, is refused unless
# the batch has a "## Plan" section naming a .claude/plans/<file>.md, a nonempty file committed on local main (checked
# again once main is fast-forwarded from origin). --skip-plan, with a reason, launches without one: the skip is printed
# on stderr, written into the brief and the evidence file as "plan skipped: <reason>", and logged as a routing-override
# line. A risky launch's second call is not checked again, so one begun before this rule still opens its Builder.
# A new unit opens only on an order that names it: the batch's "## Launch" section has "Launch: new unit <unit>" and
# "Order: <the owner's words>". A batch that adds work to a unit (Launch: add to <unit>) goes to builder-add-work.sh.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
USAGE="usage: builder-launch.sh [--risky] [--dry-run] [--small] [--keep <billing|all|a keep word>[,...]] [--model <alias> --reason '<one line>'] [--effort medium|high --reason '<one line>'] [--skip-plan --reason '<one line>'] <unit> <batch-brief>"
KEEP=
RISKY=0 DRY=0 SMALL=0 PICK=0 BMODEL='' REASON='' RAISE=0 EFFORT='' WHY='' SKIP=0
while :; do
  case ${1:-} in
    --risky) RISKY=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --small) SMALL=1; shift ;;
    --skip-plan) SKIP=1; shift ;;
    --keep) KEEP=${2:-}; shift $(($# > 1 ? 2 : 1)) ;;
    --model) PICK=1 BMODEL=${2:-}; shift $(($# > 1 ? 2 : 1)) ;;
    --effort) RAISE=1 EFFORT=${2:-}; shift $(($# > 1 ? 2 : 1)) ;;
    --reason) REASON=${2:-}; shift $(($# > 1 ? 2 : 1)) ;;
    *) break ;;
  esac
done
# A reason with no --effort or --skip-plan is the model pick's, checked as it always was.
[ -z "$REASON" ] || [ "$RAISE" = 1 ] || [ "$SKIP" = 1 ] || PICK=1
UNIT=${1:?$USAGE}
BATCH=${2:?$USAGE}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad unit name: $UNIT" >&2; exit 2; }
pp_unit_name "$UNIT" || exit 2
[ -s "$BATCH" ] || { echo "empty batch brief: $BATCH" >&2; exit 2; }
# Every batch says which standard governs it, what library or service already does it, and why we build if we do.
grep -qiE '^#+[[:space:]]+Prior art' "$BATCH" || { echo "REFUSED: $BATCH has no Prior art section (a '## Prior art' heading): name the governing standard and the library or service the project's .claude/paved-road.md approves, and why we build instead if we do" >&2; exit 2; }
# A new unit opens only on an order that names it (issue 234): the batch's ## Launch section quotes the order.
LAUNCH=$(sed -n 's/^Launch:[[:space:]]*//p' "$BATCH" | head -1 | sed 's/[[:space:]]*$//')
case $LAUNCH in
  "new unit $UNIT") ;;
  '') echo "REFUSED: $BATCH has no Launch line (a '## Launch' section with 'Launch: new unit $UNIT' and 'Order: <the owner's words>'): a new unit opens only on an order that names it" >&2; exit 2 ;;
  "add to "*) echo "REFUSED: $BATCH adds work to ${LAUNCH#add to }: run builder-add-work.sh ${LAUNCH#add to } instead; nothing was opened" >&2; exit 2 ;;
  *) echo "REFUSED: $BATCH's Launch line names ${LAUNCH#new unit }, not $UNIT ('$LAUNCH'); nothing was opened" >&2; exit 2 ;;
esac
WT=$PP_WORKSPACES/$UNIT
# The second call of a risky launch: the first made the worktree, wrote the brief and evidence and opened the design pane.
RESUME=0
[ "$RISKY" = 1 ] && [ "$DRY" = 0 ] && [ -f "$WT/.claude/briefs/$UNIT-design-spec.md" ] && RESUME=1
# The plan is read where the worktree is cut from, local main (pp_worktree_new): a nonempty regular file there.
PLAN=$(awk '/^#+[[:space:]]/ { on = $0 ~ /^#+[[:space:]]+Plan([[:space:]:]|$)/ } on' "$BATCH" | grep -oE '\.claude/plans/[A-Za-z0-9._-]+\.md' | head -1) || PLAN=
plan_ok() {
  [ -n "$SKIPPED" ] || [ "$RESUME" = 1 ] || [[ $PLAN && $(git -C "$PP_MAIN" ls-tree -l refs/heads/main -- "$PLAN" 2>/dev/null) =~ ^100(644|755)\ blob\ [0-9a-f]+\ +[1-9][0-9]*$'\t'"$PLAN"$ ]] \
    || { echo "REFUSED: $BATCH names no plan committed on main in $PP_MAIN (a '## Plan' section naming .claude/plans/<file>.md${PLAN:+; $PLAN is not a nonempty file in the last commit of main}): write and commit the plan the owner reads before the build, or launch with --skip-plan --reason '<one line>'" >&2; exit 2; }
}
SKIPPED=
if [ "$SKIP" = 1 ]; then
  # Logged as a routing-override line, read as key=value words: one line, no = sign.
  [[ -n $REASON && $REASON != *[=$'\n']* ]] || { echo "REFUSED: --skip-plan needs --reason '<one line, no = sign>'; the brief, the evidence and the routing log record why the build has no plan" >&2; exit 2; }
  SKIPPED="plan skipped: $REASON"
fi
# A risky launch's second call is not asked again: its first call checked the plan, or ran before the rule, and the
# brief it wrote, which the Builder opens with, must match this call's (checked below).
plan_ok
# Two Builders never share a worktree: a reused one carries another batch's diff and event log. A risky launch's own
# worktree, made by its first call, is one exception; the unit's planning worktree, adopted below, is the other.
ADOPT=0
if [ -e "$WT" ] && [ "$RESUME" = 0 ]; then
  KEPT=$(bash "$HERE/plan-worktree-close.sh" "$UNIT" --adopt --dry-run 2>&1 >/dev/null) \
    || { echo "REFUSED: $WT already exists and is not $UNIT's planning worktree to take over (${KEPT:-no reason given}); a Builder starts in a new worktree" >&2; exit 2; }
  ADOPT=1
fi

if [ "$PICK" = 1 ]; then
  pp_builder_model_ok "$BMODEL" || exit 2
  # A log line is read as key=value words, so the reason holds no = and is one line.
  [[ -n $REASON && $REASON != *[=$'\n']* ]] || { echo "REFUSED: --model needs --reason '<one line, no = sign>'; the pick is logged with it" >&2; exit 2; }
fi
if [ "$RAISE" = 1 ]; then
  [[ -n $REASON && $REASON != *$'\n'* ]] || { echo "REFUSED: --effort needs --reason '<one line>'; the brief records why the build was raised" >&2; exit 2; }
fi
SEAT=$(pp_route_json builder "" "$BMODEL") || exit 2
DEFAULT=$(jq -r '.effort // "none"' <<<"$SEAT")
OVERRIDE=
if [ "$RAISE" = 1 ]; then
  pp_builder_effort_ok "$EFFORT" "$DEFAULT" || exit 2
  OVERRIDE="effort override: builder $DEFAULT -> $EFFORT: $REASON" WHY=$REASON
fi
REC=
if [ "$RESUME" = 1 ]; then
  # A record there but unreadable (or a directory) stops the launch: read as empty, its rewrite would lose its history.
  rd() { [ ! -e "$1" ] || cat "$1" || { echo "could not read $1; the Builder was not launched and no record was changed." >&2; return 1; }; }
  # One second call of a unit at a time, from reading its records to the pane's launch: a concurrent one saw no
  # Builder and rewrote the records of the one opening. the lock is held until this script exits.
  pp_builder_lock "$UNIT" || exit 1
  WB=$(rd "$WT/.claude/briefs/$UNIT.md") || exit 1
  REC=$(awk '/^## The batch/ { exit } /^effort override: / { print; exit }' <<<"$WB")
  # With no --effort it opens at what the first call recorded, never the setup default (main's ruling 1).
  if [ "$RAISE" = 0 ] && [ -n "$REC" ]; then
    EFFORT=${REC#* -> } WHY=${REC#effort override: builder * -> *: }; RAISE=1 EFFORT=${EFFORT%%:*} OVERRIDE=$REC
  fi
fi
ADVISOR=0 RULE='none (the default Builder has no advisor)'
if [ -n "$(jq -r '.advisor // empty' <<<"$SEAT")" ]; then
  if [ "$SMALL" = 1 ]; then RULE='none (the advisor routing.json names; marked small)'
  else ADVISOR=1 RULE='kept (routing.json names it)'; fi
fi
OPTS=()
[ "$PICK" = 0 ] || OPTS+=(--model "$BMODEL")
[ "$RAISE" = 0 ] || OPTS+=(--effort "$EFFORT")
[ "$ADVISOR" = 1 ] || OPTS+=(--no-advisor)
# The Builder opens here, after its worktree and brief exist: the one place the pick is logged.
open_builder() {
  if [ "$PICK" = 1 ]; then
    printf '%s unit=%s note=routing-override builder %s: %s\n' "$(date +%F)" "$UNIT" "$BMODEL" "$REASON" >> "${COMMANDECK_ROUTING_LOG:-$PP_MAIN/.claude/routing-log}" \
      || { echo "could not write the routing log; the Builder was not launched" >&2; exit 1; }
  fi
  if [ -n "$SKIPPED" ]; then
    printf '%s unit=%s note=routing-override %s\n' "$(date +%F)" "$UNIT" "$SKIPPED" >> "${COMMANDECK_ROUTING_LOG:-$PP_MAIN/.claude/routing-log}" \
      || { echo "could not write the routing log; the Builder was not launched" >&2; exit 1; }
  fi
  bash "$HERE/seat.sh" launch builder "$UNIT" "$WT/.claude/briefs/$UNIT.md" ${OPTS[@]+"${OPTS[@]}"} || exit $?
  # The plan is on main and the Builder runs: a unit planned before 0.18.0, in <unit>-plan, has that worktree closed.
  # A refusal is printed and never fails the launch.
  [ ! -d "$WT-plan" ] || bash "$HERE/plan-worktree-close.sh" "$UNIT" >&2 || true
  exit 0
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
# Above the batch, where the dashboard reads no issue numbers: a reason that names one stays out of the issue list.
[ -z "$OVERRIDE" ] || T=${T/$'\n## The batch'/$'\n'"$OVERRIDE"$'\n\n## The batch'}
[ -z "$SKIPPED" ] || T=${T/$'\n## The batch'/$'\n'"$SKIPPED"$'\n\n## The batch'}
# The review loop the owner chose at setup; with every default taken the brief reads as it always did.
SMALL=$(pp_review_loop smallBuild 200 '^(off|[1-9][0-9]*)$') && MAXR=$(pp_review_loop maxRounds '' '^[1-9][0-9]*$') \
  && CLOSING=$(pp_review_loop closingPass yes '^(yes|no)$') || exit 2
LOOP=
[ -z "$MAXR" ] || LOOP+="This project allows at most $MAXR rounds: a pass numbered over $MAXR is refused. Before that, stop and report to main what is still open."$'\n'
[ "$CLOSING" != no ] || LOOP+="This project runs no closing pass: skip step 3. The narrowed pass that ends \`VERDICT: GO\` is the one the merge takes, once narrowed passes have read every commit after the first pass; change nothing after it."$'\n'
# Small build off: no build is small, so the first pass is always three reviewers.
[ "$SMALL" != off ] || T=${T//$'or one when the build\n   is under {small-build} changed lines and main did not launch it with `--risky` (the\n   pass prints which)'/'never one: this project turned the small build off'}
T=${T//'{small-build}'/"$SMALL"}
T=${T//$'{loop-rules}\n'/"$LOOP"}
# Issue sizing (setup's issueSizing: tokens, or off; default 40000): an independent issue the batch's "Size:" line
# estimates over the line is cheaper as its own unit, so main hears of it before the launch and decides.
SIZING=$(pp_issue_sizing) || exit 2
[ "$SIZING" = off ] || awk -v max="$SIZING" '
  /^#+ / { l = length($1); if (on && l <= lv) on = 0; if (!on && $0 ~ /^#+ The issues/) { on = 1; lv = l }; next }
  !on { next }
  /^[0-9]+\. / { n = $1; sub(/\.$/, "", n); i = $2; sub(/:$/, "", i); name[n] = i ~ /^#[0-9]+$/ ? " (" i ")" : ""; order[++k] = n; next }
  /^[[:space:]]*Size:/ && k { size[order[k]] = $0 }
  END { for (j = 1; j <= k; j++) { n = order[j]; s = size[n]
    if (s == "") print "sizing: item " n name[n] " has no Size line (its files, shared or independent, ~<n>K tokens to read); add one so the batch can be sized"
    else if (s ~ /independent/ && match(s, /~[0-9]+K/) && substr(s, RSTART + 1, RLENGTH - 2) * 1000 > max)
      print "sizing: item " n name[n] " is independent and ~" substr(s, RSTART + 1, RLENGTH - 2) "K tokens to read, over this project'"'"'s " max / 1000 "K line: propose it as its own unit, or the small Builder (--small --model sonnet), and launch on the split main accepts or overrides" } }' "$BATCH" >&2
# Its headings go two levels down, so a batch with a level-1 title of its own stays inside "## The batch": the
# dashboard reads the issues from that section, and its reader takes any "# " line as a heading.
T=${T//'{batch}'/"$(sed -E 's/^(#+ )/##\1/' "$BATCH")"}
echo "advisor: $RULE" >&2
if [ "$RAISE" = 1 ]; then echo "effort: $EFFORT, raised by main: $WHY" >&2; else echo "effort: $DEFAULT (the setup default)" >&2; fi
[ -z "$SKIPPED" ] || echo "$SKIPPED" >&2
# The dashboard's "Issue by issue" list is read from the brief (brief-issues.sh): said here, before a build starts with an empty one.
[ "$DRY" = 0 ] || [ "$(bash "$HERE/brief-issues.sh" <(printf '%s\n' "$T"))" != '[]' ] \
  || echo "issues: this brief names no work item, so the dashboard will list none for the build. Start the batch file as templates/_batch-brief-template.md does: a section '## The issues' with one numbered line per item ('1. #12: title')." >&2
if [ "$DRY" = 1 ]; then printf '%s\n' "$T"; bash "$HERE/plan-worktree-close.sh" "$UNIT" $([ "$ADOPT" = 0 ] || echo --adopt) --dry-run >&2 || true; exit 0; fi

# The second call of a risky launch: the first made the worktree and opened the
# design pane. The Builder opens only once the note is written; nothing waits.
NOTE=$WT/.claude/briefs/$UNIT-design.md
if [ "$RESUME" = 1 ]; then
  # Only the effort may change between the two calls (main's ruling 1); the advisor, batch and review loop the
  # first call's brief states are what this Builder opens with, so any other difference is refused.
  ON=$WB NOW=$T
  [ -z "$REC" ] || ON=${ON/$'\n'"$REC"$'\n'/}
  [ -z "$OVERRIDE" ] || NOW=${NOW/$'\n'"$OVERRIDE"$'\n'/}
  [ "$ON" = "$NOW" ] || { echo "REFUSED: this call renders another brief than the first call of this risky launch wrote, other than its effort. Run it again with the first call's --small and --skip-plan, on the same batch file; the Builder was not launched." >&2; exit 2; }
  [ -s "$NOTE" ] || { echo "no design note at $NOTE yet; the Builder was not launched. Run this again once the design pane has written it." >&2; exit 1; }
  # A changed effort is rewritten into both briefs and logged in the evidence before the pane opens, so the records
  # match what runs. Each record is checked on its own: a retry after a failed write finishes what is still owed.
  EV=$WT/.claude/briefs/$UNIT-evidence.md MB=$PP_MAIN/.claude/briefs/$UNIT-builder-brief.md
  EVT=$(rd "$EV") && MBT=$(rd "$MB") || exit 1
  # "<effort>|<reason>" the evidence last recorded: the first call's override line, then each change after it.
  GOT=$(printf '%s\n' "$EVT" | awk -v d="$DEFAULT" '
    /^effort override: builder [a-z]+ -> [a-z]+: / { e = $6; sub(/:$/, "", e); r = $0; sub(/^effort override: builder [a-z]+ -> [a-z]+: /, "", r) }
    /^effort changed at Builder launch: [a-z]+ -> [a-z]+, reason: / { e = $8; sub(/,$/, "", e); r = $0; sub(/^effort changed at Builder launch: [a-z]+ -> [a-z]+, reason: /, "", r) }
    END { print (e == "" ? d : e) "|" r }')
  LINE=; [ "$RAISE" = 0 ] || [ "$GOT" = "$EFFORT|$WHY" ] || LINE="effort changed at Builder launch: ${GOT%%|*} -> $EFFORT, reason: $WHY"
  if [ "$WB" != "$T" ] || [ "$MBT" != "$T" ] || [ -n "$LINE" ]; then
    # A running Builder keeps the effort it opened with, so its records are not rewritten under it.
    . "$HERE/codex-helpers.sh"
    LIVE=$(live_pane_with_title "path:$WT" "$(pane_title builder "$UNIT")") || LIVE="(its pane list could not be read)"
    [ -z "$LIVE" ] || { echo "REFUSED: a Builder for $UNIT is already running $LIVE; its brief and evidence were left as they are. Close it, then launch again." >&2; exit 2; }
    # Each record is replaced whole, never cut short in place: a half-written brief would refuse the retry. mv would
    # put it inside a directory at that path and succeed, so one is refused.
    put() { [ ! -d "$1" ] && printf '%s\n' "$2" > "$(dirname "$1")/.$(basename "$1").tmp" && mv -f "$(dirname "$1")/.$(basename "$1").tmp" "$1"; }
    { put "$WT/.claude/briefs/$UNIT.md" "$T" && put "$MB" "$T" && { [ -z "$LINE" ] || put "$EV" "${EVT:+$EVT$'\n'}$LINE"; }; } \
      || { echo "could not record the changed effort for $UNIT; the Builder was not launched. Run the same command again to finish." >&2; exit 1; }
  fi
  # An explicit --keep reaches the settings before the pane opens, as on a first call; seat.sh reruns setup without it.
  [ -z "$KEEP" ] || bash "$HERE/worktree-setup.sh" "$WT" --builder --keep "$KEEP" || exit 1
  open_builder
fi

pp_sync_main "$PP_MAIN" || exit 1
# Fast-forwarding main from origin may have removed the plan the worktree is about to be cut without.
plan_ok
if [ "$ADOPT" = 1 ]; then
  # After every other check, so a launch refused earlier leaves the planner and its mark as they were. Adoption
  # proved nothing in it differs from local main, so the reset to main, as pp_worktree_new bases a new one, loses nothing.
  bash "$HERE/plan-worktree-close.sh" "$UNIT" --adopt >&2 || { echo "the Builder was not launched: $WT was not taken over (above)" >&2; exit 1; }
  # Adoption took the mark, and the launch writes the Builder's settings and brief into the planner's worktree: a
  # launch that fails from here on gives the mark back, takes back the briefs it writes and puts the planner's
  # settings back as they were, or every later launch refused the unmarked worktree or the files it found there.
  GD=$(git -C "$WT" rev-parse --absolute-git-dir) SET=$WT/.claude/settings.local.json
  SAVED=$GD/commandeck-adopt-settings; rm -f "$SAVED"; [ ! -f "$SET" ] || cp -p "$SET" "$SAVED"
  undo() {
    local f live
    # seat.sh can fail after its pane opened (a screen read after the dispatch): a pane in the worktree runs on what
    # the launch wrote, so all of it stays and no mark comes back. A list that cannot be read is no proof of none.
    live=$(orca-ide terminal list --worktree "path:$WT" --json 2>/dev/null | jq -er '.result | if type == "array" then . else .terminals end
      | map(select(.connected != false and .orphaned != true) | .handle) | join(" ")' 2>/dev/null) || live="its pane list could not be read"
    if [ -n "$live" ]; then
      rm -f "$SAVED"; echo "kept: $WT has a pane open ($live) on what this launch wrote; its brief and settings stay, and it is not the planner's again. Read the pane before launching again." >&2; return
    fi
    for f in "$WT/.claude/briefs/$UNIT"{,-evidence,-design-spec}.md; do git -C "$WT" checkout -q HEAD -- "$f" 2>/dev/null || rm -f "$f"; done
    if [ -f "$SAVED" ]; then mv -f "$SAVED" "$SET"; else rm -f "$SET"; fi
    echo "$UNIT" > "$GD/commandeck-plan-of"
  }
  trap '[ $? = 0 ] && rm -f "$SAVED" || undo' EXIT
  git -C "$WT" reset --hard "$(git -C "$PP_MAIN" rev-parse refs/heads/main)" >/dev/null || { echo "could not base $UNIT on local main; the Builder was not launched" >&2; exit 1; }
else
  pp_worktree_new "$UNIT" || exit 1
fi
bash "$HERE/worktree-setup.sh" "$WT" --builder ${KEEP:+--keep "$KEEP"}
mkdir -p "$WT/.claude/briefs"
printf '%s\n' "$T" > "$WT/.claude/briefs/$UNIT.md"
[ -z "$OVERRIDE" ] || printf '%s\n' "$OVERRIDE" > "$WT/.claude/briefs/$UNIT-evidence.md"
[ -z "$SKIPPED" ] || printf '%s\n' "$SKIPPED" >> "$WT/.claude/briefs/$UNIT-evidence.md"
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
