#!/usr/bin/env bash
# covers: scripts/merge-unit-local.sh
# merge-unit-local.sh and a plan built a cut at a time (#545). A merge of a plan with 2+ `- C<n>` cuts under `## Cuts`
# marks the cuts the evidence says `C<n>: built`, and with a cut left keeps that cut's issues open and the Builder's
# task open, so a part merge never reads as a finished unit. Its own file: merge-unit-local.test.sh runs near its cap.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-unit-local-setup.sh"

# Two stubs in the copied scripts: the task create logs its words (and fails while task-fails exists), and unit-close
# logs the call that would complete the Builder's task.
printf '#!/usr/bin/env bash\necho "$*" >> "%s/task-calls"\n[ ! -e "%s/task-fails" ] || { echo "no longer bound to Run" >&2; exit 1; }\necho task_1\n' "$TMP" "$TMP" > "$REAL/scripts/orca-task-create.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/close-calls"\n' "$TMP" > "$REAL/scripts/unit-close.sh"
chmod +x "$REAL/scripts/orca-task-create.sh" "$REAL/scripts/unit-close.sh"
: > "$TMP/task-calls"; : > "$TMP/close-calls"; : > "$TMP/gh-calls"

# cutunit <unit> <plan body under ## Cuts> <issue numbers, comma list> <evidence text> -- the plan committed on main,
# a Builder worktree whose brief (the optional 5th argument, else one naming the plan in backticks) names it, and a first pass that ends GO
cutunit() {
  mkdir -p "$REPO/.claude/plans"; printf '# plan\n\n## Cuts\n\n%s\n\n## Breaks\n\nnone\n' "$2" > "$REPO/.claude/plans/$1.md"
  git -C "$REPO" add .claude/plans; git -C "$REPO" commit -qm "plan $1"
  mk "$1" "feat($1): the unit"; local w=$COMMANDECK_WORKSPACES/$1
  printf '# %s\n\n%s\n' "$1" "${5:-Follow \`.claude/plans/$1.md\`.}" > "$w/.claude/briefs/$1.md"
  printf '%s\n' "$4" > "$w/.claude/briefs/$1-evidence.md"
  mkdir -p "$REPO/.claude/briefs"; printf '[%s]\n' "$3" > "$REPO/.claude/briefs/$1-issues.json"
  go "$1"
}
done_line() { grep '^DONE unit=' "$TMP/out"; }
plan() { cat "$REPO/.claude/plans/$1.md"; }
reset() { : > "$TMP/task-calls"; : > "$TMP/close-calls"; : > "$TMP/gh-calls"; rm -f "$TMP/task-fails"; }

# Cuts 1 and 2 are small; the evidence says only cut 1 is built.
reset; cutunit ca $'- C1 first cut #101\n- C2 second cut #102\n- C3 third cut #103' '101,102' $'## Per issue\n\n| Issue | Status |\n|---|---|\n| #101 | built |\n| #102 | built |\n\nC1: built'
rc=$(merge ca)
check "a merge with a cut left marks the built cut, names the next and tasks it" \
  "0|- C1 first cut #101 -- done|1|1|1" \
  "$rc|$(plan ca | grep '^- C1 ')|$(grep -c 'unit open: next Cut 2' <<<"$(done_line)")|$(grep -c 'next cut: ca Cut 2, plan .claude/plans/ca.md' "$TMP/task-calls")|$(wc -l < "$TMP/task-calls" | tr -d ' ')"
SHA_A=$(done_line | sed -n 's/^DONE .* sha=\([0-9a-f]\{8\}\);.*/\1/p')
check "an issue named on an open cut stays open and reads Refs in the squash message" "Closes #101 Refs #102|1|0" \
  "$(git -C "$REPO" log -1 --format=%b "$SHA_A" | grep . | paste -sd' ' -)|$(grep -c '^issue close 101 ' "$TMP/gh-calls")|$(grep -c '^issue close 102 ' "$TMP/gh-calls")"
check "a merge with a cut left keeps the Builder's task open" "0|1" \
  "$(grep -c 'merged' "$TMP/close-calls")|$(grep -c '^STEP 5 task kept open: Cut 2' "$TMP/out")"
check "the DONE line names the merge commit, not the plan commit" "$SHA_A|chore(plan): mark the cuts ca built|plan commit $(git -C "$REPO" rev-parse --short=8 HEAD)|feat(ca): the unit" \
  "$(git -C "$REPO" rev-parse --short=8 HEAD~1)|$(git -C "$REPO" log -1 --format=%s)|$(done_line | grep -o 'plan commit [0-9a-f]*')|$(git -C "$REPO" log -1 --format=%s "$SHA_A")"

# One cut or none: the plan is not a series, so it stays byte for byte and the merge closes as before.
reset; cutunit cb '- C1 only cut #101' '101' 'C1: built'
cp "$REPO/.claude/plans/cb.md" "$TMP/cb.before"; H=$(git -C "$REPO" rev-parse HEAD); rc=$(merge cb)
cutunit cc 'no bullets here' '102' 'C1: built'
cp "$REPO/.claude/plans/cc.md" "$TMP/cc.before"; rc2=$(merge cc)
check "a plan with one cut or none is left byte for byte" "0 0|0 0|0|2|0" \
  "$rc $rc2|$(cmp -s "$TMP/cb.before" "$REPO/.claude/plans/cb.md"; echo $?) $(cmp -s "$TMP/cc.before" "$REPO/.claude/plans/cc.md"; echo $?)|$(wc -l < "$TMP/task-calls" | tr -d ' ')|$(grep -c ' merged$' "$TMP/close-calls")|$(done_line | grep -c 'unit open')"

# Every cut built: the bullets are marked, nothing is left to name, and the Builder's task closes.
reset; cutunit cd $'- C1 first #101\n- C2 second #102' '101,102' $'C1: built\nC2: built'
rc=$(merge cd)
check "a plan whose every cut is built is marked and names nothing" "0|2|0|0|1" \
  "$rc|$(plan cd | grep -c ' -- done$')|$(done_line | grep -c 'unit open')|$(wc -l < "$TMP/task-calls" | tr -d ' ')|$(grep -c '^cd merged$' "$TMP/close-calls")"

# A task Orca cannot create is named, and the merge is not undone for it.
reset; touch "$TMP/task-fails"; cutunit ce $'- C1 first #101\n- C2 second #102' '101' 'C1: built'
rc=$(merge ce); rm -f "$TMP/task-fails"
check "a failed task create is named on the DONE note and the merge goes on" "0|1" \
  "$rc|$(done_line | grep -c 'next-cut task NOT created: no longer bound to Run')"

# A cut line inside a code fence is an example, not a cut: with cuts 1 and 2 built nothing is left.
reset; cutunit cf $'- C1 first #101\n- C2 second #102\n\n```\n- C3 example #103\n```' '101,102' $'C1: built\nC2: built'
rc=$(merge cf)
check "a fenced cut line is not counted" "0|0|2|1" \
  "$rc|$(done_line | grep -c 'unit open')|$(plan cf | grep -c ' -- done$')|$(plan cf | grep -c '^- C3 example #103$')"

# A plan someone is editing on main is theirs: not rewritten, not committed, and the note says so.
reset; cutunit cg $'- C1 first #101\n- C2 second #102' '101' 'C1: built'
echo '- C9 my edit' >> "$REPO/.claude/plans/cg.md"; cp "$REPO/.claude/plans/cg.md" "$TMP/cg.before"; rc=$(merge cg)
check "a plan with uncommitted edits on main is not touched" "0|0|$(git -C "$REPO" rev-parse --short=8 HEAD)|1" \
  "$rc|$(cmp -s "$TMP/cg.before" "$REPO/.claude/plans/cg.md"; echo $?)|$(done_line | sed -n 's/^DONE .* sha=\([0-9a-f]\{8\}\);.*/\1/p')|$(done_line | grep -c 'NOT marked: it has uncommitted edits')"
git -C "$REPO" checkout -q -- .claude/plans/cg.md

# `- C1-C2` is cut 1 and cut 2, built only by each cut's own line (`C1-C2: built` builds neither); `- C3-C2`-style
# reversed ranges read the same.
reset; cutunit ch $'- C1-C2 the pair #101\n- C3 the last #103' '101,103' $'C1: built\nC1-C2: built'
rc=$(merge ch)
check "a range cut bullet counts as each cut in it" "0|0|1|Refs #101|1" \
  "$rc|$(plan ch | grep -c ' -- done$')|$(done_line | grep -c 'unit open: next Cut 2')|$(git -C "$REPO" log -1 --format=%b "$(done_line | sed -n 's/^DONE .* sha=\([0-9a-f]\{8\}\);.*/\1/p')" | grep -o 'Refs #101')|$(git -C "$REPO" log -1 --format=%b "$(done_line | sed -n 's/^DONE .* sha=\([0-9a-f]\{8\}\);.*/\1/p')" | grep -c 'Refs #103')"
reset; cutunit ci $'- C2-C1 the pair #101\n- C3 the last #103' '101,103' $'C1: built\nC2: built'
rc=$(merge ci)
check "a range cut bullet counts as each cut in it" "0|1|1" \
  "$rc|$(plan ci | grep -c '^- C2-C1 the pair #101 -- done$')|$(done_line | grep -c 'unit open: next Cut 3')"

# Pass 3 (class markdown-fence-drift): both cut readers follow fence.sh's one rule. An example in an indented fence,
# or behind a shorter or other-character delimiter inside a fence, is fixture text: it never builds a cut (the evidence)
# or adds one (the plan). Run on cut_scan alone, as the merge sources it, so every fence form is one fast case.
SCAN=$(sed -n '/^cut_scan() {/,/^# cut_plan --/p' "$REAL/scripts/merge-unit-local.sh")
scan() { # <evidence> <plan body under ## Cuts> -- prints CUT_COUNT|CUT_NEXT|CUT_ISSUES|done bullets
  local d; d=$(mktemp -d "$TMP/scan.XXXXXX"); mkdir -p "$d/.claude/briefs"
  printf '%s\n' "$1" > "$d/.claude/briefs/u-evidence.md"; printf '# plan\n\n## Cuts\n%s\n' "$2" > "$d/plan.md"
  (. "$REAL/scripts/fence.sh"; eval "$SCAN"; WT=$d UNIT=u; cut_scan "$d/plan.md" "$d/out.md" || exit 1
   echo "$CUT_COUNT|$CUT_NEXT|${CUT_ISSUES# }|$(grep -c ' -- done$' "$d/out.md")")
}
got="" want=""
for ex in $'  ```text\nC2: built\n  ```' $'````text\n```\nC2: built\n````' $'~~~text\n```\nC2: built\n~~~' $'```\n~~~\nC2: built\n```'; do
  got+="$(scan "C1: built"$'\n'"$ex" $'- C1 first #101\n- C2 second #102') "; want+="2|2|102|1 "
done
for ex in $'  ```\n- C3 example #103\n  ```' $'````\n```\n- C3 example #103\n````' $'~~~\n```\n- C3 example #103\n~~~'; do
  got+="$(scan $'C1: built\nC2: built' $'- C1 first #101\n- C2 second #102\n'"$ex") "; want+="2|||2 "
done
got+="$(scan $'C1: built\nC2: built' $'- C1 first #101\n- C2 second #102\n````\n```\n- C9 x #109\n````\n- C3 third #103')"; want+="3|3|103|2"
check "a fenced example in the evidence or the plan builds or adds no cut, in every fence form; a cut after the fence counts" "$want" "$got"

# Pass 4 (class plan-reference-format): a launched brief names its plan as a plain path on its own line under `#### Plan`,
# not in backticks. The one reader of plan references is paths.sh's pp_brief_plans: the paths under a Plan section
# (backticks optional) and every backticked path; a fenced line is an example; a plan named only in prose outside a Plan
# section authorises nothing: it is not read and it does not stop the merge. Were a plain path unread, CUT_NEXT and
# CUT_ISSUES would stay empty and the merge would close the issues of cuts not yet built.
PBP=$(sed -n '/^pp_plan_section_paths() {/,/^}/p; /^pp_brief_plans() {/,/^}/p' "$REAL/scripts/paths.sh")
CPLAN=$(sed -n '/^cut_plan() {/,/^}/p' "$REAL/scripts/merge-unit-local.sh")
refs() { # <brief text> -- prints the plan paths pp_brief_plans finds (comma list)
  local d; d=$(mktemp -d "$TMP/refs.XXXXXX"); printf '%s\n' "$1" > "$d/brief.md"
  (. "$REAL/scripts/fence.sh"; eval "$PBP"; paste -sd, - < <(pp_brief_plans "$d/brief.md"))
}
check "a plain own-line path, a backticked path and a padded path under Plan are each read once" ".claude/plans/u.md,.claude/plans/v.md,.claude/plans/w.md" \
  "$(refs $'#### Plan\n\n.claude/plans/u.md\nSee `.claude/plans/v.md` and `.claude/plans/u.md`.\n  \t.claude/plans/w.md  ')"
check "a plain path inside a fence is an example and is not read" "" "$(refs $'```\n.claude/plans/u.md\n```\nno plan')"
check "a prose line with a bare plan path outside a Plan section is not read, and is not refused" "" "$(refs $'.claude/plans/u.md\n\nsee .claude/plans/u.md here')"
check "a path with a suffix in prose outside a Plan section is not read as the plan" "" "$(refs '.claude/plans/u.md.bak')"
check "a backticked plan path anywhere is read, and so is one under a later Plan heading" ".claude/plans/u.md,.claude/plans/v.md" \
  "$(refs $'Do `.claude/plans/v.md`.\n## Plan\n.claude/plans/u.md\n## Other\n.claude/plans/x.md')"
# The reviewer's repro: the brief names the plan on its own line, and cut_plan finds the open cut and its issue.
d=$(mktemp -d "$TMP/plain.XXXXXX"); mkdir -p "$d/main/.claude/plans" "$d/wt/.claude/briefs"
printf '#### Plan\n\n.claude/plans/u.md\n' > "$d/brief.md"; printf '## Cuts\n- C1 first #101\n- C2 second #102\n' > "$d/main/.claude/plans/u.md"
printf 'C1: built\n' > "$d/wt/.claude/briefs/u-evidence.md"
got=$(. "$REAL/scripts/fence.sh"; eval "$SCAN"; eval "$PBP"; eval "$CPLAN"; ROOT=$d/main WT=$d/wt UNIT=u BRIEF=$d/brief.md CUT_TMP=$d/scanned; cut_plan; echo "$CUT_PLAN|$CUT_NEXT|$CUT_ISSUES")
check "a plan named on its own line is the plan: its open cut and that cut's issue are found" ".claude/plans/u.md|2| 102" "$got"
# End to end: the merge of a plain-referenced plan with a cut left keeps that cut's issue open.
reset; cutunit cj $'- C1 first cut #101\n- C2 second cut #102' '101,102' 'C1: built' $'#### Plan\n\n.claude/plans/cj.md\n'
rc=$(merge cj)
check "a plain-referenced plan with a cut left keeps that cut's issue open and names the next cut" "0|1|0|1" \
  "$rc|$(grep -c '^issue close 101 ' "$TMP/gh-calls")|$(grep -c '^issue close 102 ' "$TMP/gh-calls")|$(done_line | grep -c 'unit open: next Cut 2')"
# A plan named only in prose authorises nothing: the merge goes on, and with no plan read no cut is left, so both issues close.
reset; cutunit ck $'- C1 first cut #101\n- C2 second cut #102' '101,102' 'C1: built' $'see .claude/plans/ck.md here'
rc=$(merge ck)
check "a plan named only in prose is not read: the merge goes on and is not refused for it" "0|0|2" \
  "$rc|$(grep -c 'cannot read\|not readable' "$TMP/out")|$(grep -c '^issue close' "$TMP/gh-calls")"
# The deletion check reads plans through the same function, on main's copy of the brief: a directory named with its
# trailing slash in a plain-referenced plan authorises its deletion.
mkdir -p "$REPO/dz/sub"; echo old > "$REPO/dz/f.js"; echo old > "$REPO/dz/sub/g.js"; printf 'Cut the old pages: `dz/`.\n' > "$REPO/.claude/plans/pz.md"
git -C "$REPO" add -A dz .claude/plans/pz.md; git -C "$REPO" commit -qm "main: dz and its plan"
reset; mk cl; w=$COMMANDECK_WORKSPACES/cl; printf '# cl\n\n#### Plan\n\n.claude/plans/pz.md\n' > "$w/.claude/briefs/cl.md"
mkdir -p "$REPO/.claude/briefs"; cp "$w/.claude/briefs/cl.md" "$REPO/.claude/briefs/cl-builder-brief.md"
git -C "$w" rm -qr dz && git -C "$w" commit -qm "cut dz"; go cl; rc=$(merge cl)
check "a directory named in a plain-referenced plan lets every file under it go" "0|0" "$rc|$(ls "$REPO/dz" 2>/dev/null | wc -l | tr -d ' ')"
# The issues to close are read before the squash, so they come from the plan the merge brings in: a cut the branch adds
# to the plan (main's copy has one cut, so no series yet) keeps its issue open and is tasked next.
reset; mkdir -p "$REPO/.claude/plans"; printf '# plan\n\n## Cuts\n\n- C1 first cut #101\n' > "$REPO/.claude/plans/cm.md"
git -C "$REPO" add .claude/plans; git -C "$REPO" commit -qm "plan cm"
mk cm; w=$COMMANDECK_WORKSPACES/cm; printf '# cm\n\nFollow `.claude/plans/cm.md`.\n' > "$w/.claude/briefs/cm.md"
printf 'C1: built\n' > "$w/.claude/briefs/cm-evidence.md"; printf '[101,102]\n' > "$REPO/.claude/briefs/cm-issues.json"
printf -- '- C2 second cut #102\n' >> "$w/.claude/plans/cm.md"; git -C "$w" commit -qam "plan: add C2"; go cm; rc=$(merge cm)
check "a cut the incoming plan adds keeps its issue open, reads Refs, and is tasked next" "0|1|0|1|1" \
  "$rc|$(grep -c '^issue close 101 ' "$TMP/gh-calls")|$(grep -c '^issue close 102 ' "$TMP/gh-calls")|$(git -C "$REPO" log -1 --format=%b HEAD~1 | grep -c '^Refs #102$')|$(done_line | grep -c 'unit open: next Cut 2')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
