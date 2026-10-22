#!/usr/bin/env bash
# builder-launch.sh [--risky] [--dry-run] [--small] [--keep <billing|all|a keep word>[,...]] [--model <alias> --reason '<one line>'] [--effort medium|high --reason '<one line>'] <unit> <batch-brief>
# -- open one Builder:
# a NEW worktree, or the unit's planning one it takes over (plan-worktree-close.sh --adopt), on local main, fast-forwarded from origin first (pp_sync_main), with the Builder profile (worktree-setup.sh
# --builder), the one-page brief rendered from
# templates/_builder-brief-template.md into <wt>/.claude/briefs/<unit>.md,
# and one roles.builder pane (seat.sh launch). --dry-run prints the rendered
# brief and creates nothing. The pass script (builder-codex-pass.sh, on the
# reviewer's agent) runs its --preflight first, so a launch that could not run
# its passes fails before anything is created.
# --risky: the batch is one main marks risky. The brief gets a "## Risky launch"
# section, which the merge gate reads to ask for three reviewers; one call opens the Builder.
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
# as the builderModel key in /plugin config takes); the pick and its reason go to
# $COMMANDECK_ROUTING_LOG, default <main>/.claude/routing-log, as one
# routing-override line, written by the call that opens the Builder.
# --effort raises this one Builder above the setup default (medium unless set-up chose another): medium or high
# only, with a reason. The brief and the evidence file get one line, "effort override: builder <default> -> <used>:
# <reason>", which the dashboard reads to mark the build raised. Every launch prints the effort it uses, on stderr.
# A plan is written before every build (owner's order 2026-10-17): every launch, a dry run included, is refused unless
# the batch has a "## Plan" section naming a .claude/plans/<file>.md, a nonempty file committed on local main (checked
# again once main is fast-forwarded from origin). --skip-plan, with a reason, launches without one: the skip is printed
# on stderr, written into the brief and the evidence file as "plan skipped: <reason>", and logged as a routing-override
# line.
# A new unit opens only on an order that names it: the batch's "## Launch" section has "Launch: new unit <unit>" and
# "Order: <the owner's words>". A batch that adds work to a unit (Launch: add to <unit>) goes to builder-add-work.sh.
# --from-plan <unit> [<batch>] (issue 256): from a judged plan to a live Builder in one call. The batch defaults to
# <wt>/.claude/briefs/<unit>-batch.md. The plan <wt>/.claude/plans/<unit>.md must be the one the plan judge's record
# hashed at launch (a GO), or the plan author's revision collected PLAN-DONE after the judge's NO-GO; it is committed
# alone to main as "plan(<unit>): plan", then the launch runs as above. A GO with another judge's NO-GO on the same
# plan bytes is refused. A judge records a plan only when its spec names it (seat.sh). --dry-run checks the same and
# installs nothing.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
USAGE="usage: builder-launch.sh [--risky] [--dry-run] [--small] [--keep <billing|all|a keep word>[,...]] [--model <alias> --reason '<one line>'] [--effort medium|high --reason '<one line>'] [--skip-plan --reason '<one line>'] <unit> <batch-brief> | --from-plan <unit> [<batch-brief>]"
KEEP=
RISKY=0 DRY=0 SMALL=0 PICK=0 BMODEL='' REASON='' RAISE=0 EFFORT='' WHY='' SKIP=0 FROM=0
while :; do
  case ${1:-} in
    --risky) RISKY=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --small) SMALL=1; shift ;;
    --skip-plan) SKIP=1; shift ;;
    --from-plan) FROM=1; shift ;;
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
BATCH=${2-}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
[ "$FROM" = 0 ] || BATCH=${BATCH:-$PP_WORKSPACES/$UNIT/.claude/briefs/$UNIT-batch.md}
: "${BATCH:?$USAGE}"
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad unit name: $UNIT" >&2; exit 2; }
pp_unit_name "$UNIT" || exit 2
[ -s "$BATCH" ] || { echo "empty batch brief: $BATCH" >&2; exit 2; }
# Read once: adopting the planning worktree below can move a batch kept there.
BT=$(cat "$BATCH"; echo .) BT=${BT%.}
# Every batch says which standard governs it, what library or service already does it, and why we build if we do.
grep -qiE '^#+[[:space:]]+Prior art' "$BATCH" || { echo "REFUSED: $BATCH has no Prior art section (a '## Prior art' heading): name the governing standard and the library or service the project's .claude/paved-road.md approves, and why we build instead if we do" >&2; exit 2; }
WT=$PP_WORKSPACES/$UNIT
# A new unit opens only on an order that names it (issue 234): the batch's ## Launch section quotes the order.
LAUNCH=$(sed -n 's/^Launch:[[:space:]]*//p' "$BATCH" | head -1 | sed 's/[[:space:]]*$//')
case $LAUNCH in
  "new unit $UNIT") ;;
  '') echo "REFUSED: $BATCH has no Launch line (a '## Launch' section with 'Launch: new unit $UNIT' and 'Order: <the owner's words>'): a new unit opens only on an order that names it; the Order line must quote the owner's yes naming this unit or its issues" >&2; exit 2 ;;
  "add to "*) echo "REFUSED: $BATCH adds work to ${LAUNCH#add to }: run builder-add-work.sh ${LAUNCH#add to } instead; nothing was opened" >&2; exit 2 ;;
  *) echo "REFUSED: $BATCH's Launch line names ${LAUNCH#new unit }, not $UNIT ('$LAUNCH'); nothing was opened" >&2; exit 2 ;;
esac
# The plan is read where the worktree is cut from, local main (pp_worktree_new): a nonempty regular file there.
PLANS=$(awk '/^#+[[:space:]]/ { on = $0 ~ /^#+[[:space:]]+Plan([[:space:]:]|$)/ } on' "$BATCH" | grep -oE '\.claude/plans/[A-Za-z0-9._-]+\.md' | awk '!seen[$0]++' | paste -sd' ' -) || PLANS=
PLAN=${PLANS%% *}
plan_ok() {
  # A --from-plan dry run checked the plan against the judge above and installs nothing.
  [ -n "$SKIPPED" ] || [ "$FROM$DRY" = 11 ] || [[ $PLAN && $(git -C "$PP_MAIN" ls-tree -l refs/heads/main -- "$PLAN" 2>/dev/null) =~ ^100(644|755)\ blob\ [0-9a-f]+\ +[1-9][0-9]*$'\t'"$PLAN"$ ]] \
    || { echo "REFUSED: $BATCH names no plan committed on main in $PP_MAIN (a '## Plan' section naming .claude/plans/<file>.md${PLAN:+; $PLAN is not a nonempty file in the last commit of main}): write and commit the plan the owner reads before the build, or launch with --skip-plan --reason '<one line>'" >&2; exit 2; }
}
SKIPPED=
if [ "$SKIP" = 1 ]; then
  # Logged as a routing-override line, read as key=value words: one line, no = sign.
  [[ -n $REASON && $REASON != *[=$'\n']* ]] || { echo "REFUSED: --skip-plan needs --reason '<one line, no = sign>'; the brief, the evidence and the routing log record why the build has no plan" >&2; exit 2; }
  SKIPPED="plan skipped: $REASON"
fi
# Issue 256: --from-plan installs the plan in the unit's planning worktree on main, then launches as below. Only the
# plan the judge's record hashed at launch (a GO), or the plan author's revision collected after that judge's NO-GO,
# is installed: a frozen copy, this call's own, is checked and committed, so an edit made meanwhile cannot slip in.
FROZEN=
if [ "$FROM" = 1 ]; then
  nope() { echo "REFUSED: $1; nothing was installed on main and no Builder was launched" >&2; exit 2; }
  rv() { sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1 || true; }
  # The batch reaches the Builder as it is, so its Plan section names this unit's plan and no other.
  [ "$PLANS" = ".claude/plans/$UNIT.md" ] || nope "$BATCH names ${PLANS:-no plan} in its Plan section, not .claude/plans/$UNIT.md alone"
  PLAN=.claude/plans/$UNIT.md WP=$WT/.claude/plans/$UNIT.md J= JAT=-1 WANT= AT=-1 A=
  for r in "$PP_SCRATCH/seat-$UNIT-plan-judge-"*.txt; do
    c=$(rv "$r" collected); c=${c:-0}
    [ "$(rv "$r" plan)" = "$WP" ] && [ -n "$(rv "$r" verdict)" ] && [ "$c" -gt "$JAT" ] || continue
    J=$r JAT=$c
  done
  # Both judges off in /plugin config (issue 312): the plan installs unjudged, the author's PLAN-DONE plan below.
  # Off is exit 1 alone: a value an Enabled key does not take (2) stops the launch, naming the key.
  if [ -z "$J" ]; then
    for r in plan-judge-sol plan-judge-astra; do
      rc=0; OFF=$(pp_role_enabled "$r" 2>&1) || rc=$?
      [ "$rc" != 2 ] || nope "${OFF#REFUSED: }"
      [ "$rc" = 1 ] || nope "no plan judge's verdict on $WP in $PP_SCRATCH; run the plan judge on it first"
    done
  fi
  # A copy per call: a shared one could be replaced by another call between this one's check and its commit.
  FROZEN=$(mktemp "$PP_SCRATCH/$UNIT-plan-frozen.XXXXXX") || nope "cannot make a copy of $WP in $PP_SCRATCH"
  trap 'rm -f "$FROZEN"' EXIT
  cp "$WP" "$FROZEN" 2>/dev/null || nope "cannot read $WP"
  if [[ $(rv "$J" verdict) == "VERDICT: GO"* ]]; then
    WANT=$(rv "$J" planhash)
    # A Panel's other judge said NO-GO on these same bytes: its findings stand until a revision answers them.
    for r in "$PP_SCRATCH/seat-$UNIT-plan-judge-"*.txt; do
      [ "$(rv "$r" plan)" = "$WP" ] && [ "$(rv "$r" planhash)" = "$WANT" ] && [[ $(rv "$r" verdict) != "VERDICT: GO"* ]] \
        && nope "$r judged this same plan $(rv "$r" verdict) and $J judged it GO; revise the plan with the NO-GO's findings and judge it again, or launch with --skip-plan --reason '<main's ruling>'"
    done
  else
    # The newest author record after the NO-GO is the revision: a PLAN-BLOCKED one left a plan not finished.
    for r in "$PP_SCRATCH/seat-$UNIT-plan-author"*.txt; do
      c=$(rv "$r" collected); c=${c:-0}
      [ "$(rv "$r" plan)" = "$WP" ] && [ "$c" -gt "$JAT" ] && [ "$c" -gt "$AT" ] || continue
      A=$r AT=$c
    done
    [ -z "$A" ] || [[ $(rv "$A" verdict) != PLAN-DONE* ]] || WANT=$(rv "$A" planhash)
  fi
  [ -n "$WANT" ] && [ "$(sha256sum < "$FROZEN" | cut -d' ' -f1)" = "$WANT" ] \
    || nope "$WP is not the plan the judge read ($(rv "$J" verdict) in $J), nor the plan author's revision collected PLAN-DONE after a NO-GO${A:+ ($(rv "$A" verdict) in $A)}; judge this plan again"
  if [ "$DRY" = 0 ]; then
    pp_sync_main "$PP_MAIN" || exit 1
    # A retry after a later failure finds the plan on main byte for byte and goes on.
    if ! git -C "$PP_MAIN" show "refs/heads/main:$PLAN" 2>/dev/null | cmp -s - "$FROZEN"; then
      [ "$(git -C "$PP_MAIN" branch --show-current)" = main ] || nope "$PP_MAIN is not on main, where the plan is committed"
      # mkdir -p and cp go through a link, so one here would overwrite a file outside the plan, even a clean tracked one.
      for x in .claude .claude/plans "$PLAN"; do [ ! -L "$PP_MAIN/$x" ] || nope "$PP_MAIN/$x is a symbolic link; the plan is written on main only as a plain file"; done
      [ -z "$(git -C "$PP_MAIN" status --porcelain -- "$PLAN")" ] || cmp -s "$PP_MAIN/$PLAN" "$FROZEN" || nope "$PP_MAIN/$PLAN has changes of its own"
      mkdir -p "$PP_MAIN/.claude/plans" && cp "$FROZEN" "$PP_MAIN/$PLAN" && git -C "$PP_MAIN" add -- "$PLAN" \
        && git -C "$PP_MAIN" commit -q -m "plan($UNIT): plan" -- "$PLAN" >&2 || { echo "could not commit $PLAN on main; no Builder was launched" >&2; exit 1; }
    fi
  fi
fi
plan_ok
# Two Builders never share a worktree: a reused one carries another batch's diff and event log. The unit's planning
# worktree, adopted below, is the one exception.
ADOPT=0
if [ -e "$WT" ]; then
  KEPT=$(bash "$HERE/plan-worktree-close.sh" "$UNIT" --adopt --dry-run ${FROZEN:+--plan "$FROZEN"} 2>&1 >/dev/null) \
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

BY=$(pp_pass) || exit 2
PRE=$(bash "$HERE/builder-codex-pass.sh" --preflight) || exit 2
MODEL=${PRE%%$'\t'*}
DESIGN=""
[ "$RISKY" = 1 ] && DESIGN=$'\n'"## Risky launch"$'\n\n'"Main marked this batch risky: its merge waits on three reviewers."$'\n'

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
T=${T//'{pass-script}'/"builder-codex-pass.sh"}
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
if [ "$DRY" = 1 ]; then printf '%s\n' "$T"; bash "$HERE/plan-worktree-close.sh" "$UNIT" $([ "$ADOPT" = 0 ] || echo --adopt) --dry-run ${FROZEN:+--plan "$FROZEN"} >&2 || true; exit 0; fi

pp_sync_main "$PP_MAIN" || exit 1
# Fast-forwarding main from origin may have removed the plan the worktree is about to be cut without.
plan_ok
if [ "$ADOPT" = 1 ]; then
  # After every other check, so a launch refused earlier leaves the planner and its mark as they were. Adoption
  # proved nothing in it differs from local main, so the reset to main, as pp_worktree_new bases a new one, loses nothing.
  bash "$HERE/plan-worktree-close.sh" "$UNIT" --adopt ${FROZEN:+--plan "$FROZEN"} >&2 || { echo "the Builder was not launched: $WT was not taken over (above)" >&2; exit 1; }
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
    for f in "$WT/.claude/briefs/$UNIT"{,-evidence}.md; do git -C "$WT" checkout -q HEAD -- "$f" 2>/dev/null || rm -f "$f"; done
    if [ -f "$SAVED" ]; then mv -f "$SAVED" "$SET"; else rm -f "$SET"; fi
    echo "$UNIT" > "$GD/commandeck-plan-of"
  }
  trap '[ $? = 0 ] && rm -f "$SAVED" || undo; rm -f "$FROZEN"' EXIT
  # A batch kept in the planning worktree is planning scratch adoption moved out; it goes back where it was given, so
  # a retry of a failed launch, the same command, reads it there.
  [ -e "$BATCH" ] || { mkdir -p "$(dirname "$BATCH")" && printf '%s' "$BT" > "$BATCH"; } \
    || { echo "could not put the batch back at $BATCH after adoption; the Builder was not launched" >&2; exit 1; }
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
open_builder
