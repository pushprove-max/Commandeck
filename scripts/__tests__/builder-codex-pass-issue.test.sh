#!/usr/bin/env bash
# builder-codex-pass-issue.test.sh -- issue 486: the per-issue review workflow. Main sets it with one `Review workflow:`
# line in the builder brief; the readers, the plan check and the unit's file list are tested first, the pass kind after.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

PCK=$REAL/scripts/plan-check.sh
rw() { local o rc; o=$(. "$REAL/scripts/paths.sh" && pp_review_workflow "$1" 2>/dev/null); rc=$?; echo "[$o]$rc"; } # <file>: the reader's output and exit code
rwline() { printf 'Fix it.\n%s\n## Steps\n' "$1" > "$TMP/wf.md"; rw "$TMP/wf.md"; }

# Catches a near-miss line read as default, which would drop the per-issue reviews with no sign, and a line that is
# read from a worktree. Also: the shipped perIssueRegular is 3 and a per-issue round file is the unit's own file.
WF="none=$(rw "$TMP/absent.md")"; printf 'Fix it.\n' > "$TMP/wf.md"; WF+=" noline=$(rw "$TMP/wf.md")"
WF+=" default=$(rwline 'Review workflow: default') per=$(rwline 'Review workflow: per-issue #12 #7')"
WF+=" lower=$(rwline 'review workflow: per-issue #1') nonum=$(rwline 'Review workflow: per-issue') twice=$(rwline 'Review workflow: per-issue #1 #1')"
printf 'Fix it.\nReview workflow: default\nReview workflow: per-issue #1\n' > "$TMP/wf.md"; WF+=" doubled=$(rw "$TMP/wf.md")"
LIM=$(. "$REAL/scripts/paths.sh" && pp_review_limit perIssueRegular)
mkdir -p "$TMP/ub"; touch "$TMP/ub/u.md" "$TMP/ub/u-issue-7-round-2.md" "$TMP/ub/u-issue-x-round-2.md"
UB=$(. "$REAL/scripts/paths.sh" && pp_unit_briefs "$TMP/ub" u | sed 's#.*/##' | tr '\n' ' ')
check "workflow_line_rules: only the exact line sets per-issue; a near-miss, a doubled line or a repeat refuses; limit 3; round files listed" \
  "none=[default]0 noline=[default]0 default=[default]0 per=[per-issue #12 #7]0 lower=[]2 nonum=[]2 twice=[]2 doubled=[]2 | 3 | u.md u-issue-7-round-2.md " \
  "$WF | $LIM | $UB"

# Catches a Closes issue left off the per-issue line: its fix would reach the merge with no review of its own.
plan() { printf 'Goal: x.\n\n- Planned size: 1 files, 10 changed lines\n%s\n\n## What can go wrong\n\n- a case: t-one\n\n## Steps\n\n- modify src/x.ts -- the one change\n\n## Facts\n\n- code.sh holds three lines -- code.sh:1-3 (observed: 2026-10-01)\n\n## Acceptance test\n\n- t-one\n' "$1" > "$TMP/p/c.md"; }
mkdir -p "$TMP/p"; printf 'a\nb\nc\n' > "$TMP/p/code.sh"
batch() { printf 'Fix the issues.\n\nTier: Standard\n%s\n\n## Prior art\n\nInternal tooling; no outside library.\n\n## Data design\n\nNo stored data.\n\n## What can go wrong\n\n- Nothing new can break: fixture.\n' "$1" > "$TMP/p/batch.md"; }
pck() { PLAN_CHECK_ROOT=$TMP/p bash "$PCK" "$TMP/p/c.md" "$TMP/p/batch.md" >/dev/null 2>"$TMP/err"; echo $?; }
plan 'Closes: #1 #2'; batch 'Review workflow: per-issue #1'; OFF=$(pck); OFFN=$(grep -c 'names #2 and .* Review workflow line does not' "$TMP/err")
# A full line is not this check's refusal (the fixture has no gh issue for the later cases check, so the exit stays 2).
batch 'Review workflow: per-issue #1 #2'; pck >/dev/null; ALLN=$(grep -c 'Review workflow line does not' "$TMP/err")
plan 'Closes: none'; batch 'Review workflow: per-issue #1'; NONE=$(pck)
check "closes_issue_off_line_refused: a Closes issue missing from the per-issue line is refused; a full line and a plan closing none pass" "2:1 0 0" "$OFF:$OFFN $ALLN $NONE"

# A per-issue unit: a worktree whose main brief carries the workflow line. ipass runs one `--issue` pass of it.
iunit() { # <unit> <workflow line>
  git -C "$REPO" worktree add -q "$TMP/ws/$1" -b "builder/$1" main && mkdir -p "$TMP/ws/$1/.claude/briefs"
  echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$TMP/ws/$1/.claude/settings.local.json"
  printf 'Fix #1 and #2.\n%s\nbash x/builder-codex-pass.sh %s 1 adversarial\n' "$2" "$1" > "$REPO/.claude/briefs/$1-builder-brief.md"
  cp "$REPO/.claude/briefs/$1-builder-brief.md" "$TMP/ws/$1/.claude/briefs/$1.md"
}
ipass() { # <unit> <issue> <reply>: one --issue pass; prints its exit code; output in $TMP/out and $TMP/err
  local n; n=$(($(cat "$TMP/seq" 2>/dev/null || echo 0) + 1)); echo "$n" > "$TMP/seq"
  (cd "$TMP/ws/$1" && env TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-i$n "STUB_REPLY=$3" \
    bash "$PASS_SH" --issue "$2" "$1" >"$TMP/out" 2>"$TMP/err"); echo $?
}
fix() { printf 'echo %s\n' "$2" > "$TMP/ws/$1/$2.sh"; } # <unit> <name>: a change for the next review to read
GO=$'Fine.\nVERDICT: GO'

# Catches a number off main's list opening a review no gate would ever ask about.
iunit offl 'Review workflow: per-issue #1 #2'; fix offl f1
check "issue_pass_refused_off_list: an issue number off the line is refused before any reviewer starts" "2:1:0" \
  "$(ipass offl 9 "$GO"):$(grep -c 'issue #9 is not on offl' "$TMP/err"):$(ls "$TMP"/ws/offl/.claude/briefs/offl-issue-9-* 2>/dev/null | wc -l | tr -d ' ')"

# Catches a clean regular review that must wait for more rounds: one GO after the adversarial ends the issue.
iunit ends 'Review workflow: per-issue #1 #2'; fix ends f1
A1=$(ipass ends 1 "$GO"); S1=$(grep -c 'PER-ISSUE NEXT: issue #1 needs a review review' "$TMP/err" "$TMP/out" | paste -sd, -)
A2=$(ipass ends 1 "$GO")
check "clean_regular_ends_early: an adversarial GO asks for a regular review, and one regular GO ends the issue" "0 0 1" \
  "$A1 $A2 $(grep -c 'PER-ISSUE DONE: issue #1 ended GO' "$TMP/out")"

# Catches issue 2's review reading issue 1's fix: its range must start where issue 1's last review ended.
fix ends f2
B1=$(ipass ends 2 "$GO"); P=$TMP/ws/ends/.claude/briefs/ends-issue-2-round-1-prompt-1.md
check "review_reads_only_that_fix: the second issue's prompt holds its own change and not the first's" "0 1 0" \
  "$B1 $(grep -c '^+echo f2$' "$P") $(grep -c '^+echo f1$' "$P")"

# Catches issue sessions landing in the final record: a plain first pass would be handed them and count them.
iunit solo 'Review workflow: per-issue #1'; fix solo f1
ipass solo 1 "$GO" >/dev/null; ipass solo 1 "$GO" >/dev/null
(cd "$TMP/ws/solo" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-plain STUB_REPLY="$GO" bash "$PASS_SH" solo 1 adversarial >"$TMP/out" 2>"$TMP/err"); PRC=$?
check "issue_rounds_not_on_final_record (a plain pass after the issue rounds is handed none of them and counts none)" "0 0 0" \
  "$PRC $(grep -c 'thr-i' "$TMP/ws/solo/.claude/briefs/solo-r1-prompt-1.md") $(grep -c 'Earlier pass' "$TMP/ws/solo/.claude/briefs/solo-r1-prompt-1.md")"

# Catches a perIssueRegular of 0 reading as no limit: the per-issue reader must refuse it where pp_review_limit accepts it.
iunit zero 'Review workflow: per-issue #1'; fix zero f1
jq '."review-limits".perIssueRegular = 0' "$TMP/routing.json" > "$TMP/routing0.json"
ZRC=$(cd "$TMP/ws/zero" && env TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing0.json STUB_THREAD=thr-z "STUB_REPLY=$GO" bash "$PASS_SH" --issue 1 zero >"$TMP/out" 2>"$TMP/err"; echo $?)
check "regular_zero_refused: a perIssueRegular of 0 refuses the pass" "2:1" "$ZRC:$(grep -c 'whole number of 1 or more for review-limits.perIssueRegular' "$TMP/err")"

# Catches --issue changing a unit that never chose the workflow, or a plain pass changing its own record.
iunit dflt ''; fix dflt f1
DRC=$(ipass dflt 1 "$GO"); DREF=$(grep -c 'default review workflow' "$TMP/err")
(cd "$TMP/ws/dflt" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-d STUB_REPLY="$GO" bash "$PASS_SH" dflt 1 adversarial >"$TMP/out" 2>"$TMP/err")
check "default_unit_unchanged: a unit with no workflow line refuses --issue and runs the usual pass as before" "2:1 1" \
  "$DRC:$DREF $(grep -c '^Pass: adversarial$' "$TMP/ws/dflt/.claude/briefs/dflt-r1-reports.md")"

# pass_threads out of a script's text: the heads it names and the function, run on a Claude reviewer's sessions in a worktree.
git -C "$REAL" show HEAD:scripts/builder-codex-pass.sh > "$TMP/base-pass.sh"
pt() { # <script> <ISSUE_SET value>: pass_threads over $TMP/crh
  ( BY=claude HERE=$REAL/scripts RHOME=$TMP/crh; [ -z "$2" ] || export ISSUE_SET=$2
    eval "$(grep -E '^HEAD_[A-Z_]*=' "$1")"; eval "$(sed -n '/^pass_threads() {/,/^}/p' "$1")"; pass_threads "$TMP/ws/cr" ) 2>&1
}
mkdir -p "$TMP/crh/projects/p" "$TMP/ws/cr"
crrow() { printf '{"type":"user","cwd":"%s","message":{"content":"%s Reviewer 1 of 1, round %s."}}\n' "$TMP/ws/cr" "$2" "$3" > "$TMP/crh/projects/p/$1.jsonl"; }
crrow plainA 'Review input: the whole branch diff against main (git diff main...HEAD).' 1
crrow issueA 'Review input: a per-issue adversarial review of issue #7 alone, not the closing review (git diff main...HEAD).' 2
# Catches the default listing changing: the unit's plain reading must be the base script's, byte for byte, and must not list an issue session.
BASEOUT=$(pt "$TMP/base-pass.sh" ""); NEWOUT=$(pt "$PASS_SH" "")
check "default_unit_unchanged: pass_threads default output equals the base script's byte for byte" "plainA 1" "$BASEOUT"
check "default_unit_unchanged: pass_threads default output of this script equals the base" "$BASEOUT" "$NEWOUT"
# Catches a Claude reviewer's issue row losing its issue: without the third word the issue's rounds are nobody's.
check "claude_row_carries_issue: with the issue reading on, a Claude reviewer's per-issue session lists its round and issue and the plain one is left out" "issueA 2 7" "$(pt "$PASS_SH" 1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
