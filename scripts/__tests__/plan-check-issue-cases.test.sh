#!/usr/bin/env bash
# plan-check-issue-cases.test.sh -- issue 444: every case an issue states in its own text has one `## Issue cases` row in
# the plan (or the Skip batch) whose path is a Steps path and whose test is in the Acceptance test. A plan that drops a
# case, an issue that cannot be read, and a list shape the issue reader does not know all refuse, so a case is never
# lost to a quiet pass. `gh` is a stub on PATH.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PC=$REAL/scripts/plan-check.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/gh"; printf 'a\nb\nc\n' > "$T/code.sh"
# The stub answers `gh issue view <n> --json body -q .body` with $T/gh/<n> (one Body case when absent); GH_FAIL=1 fails.
cat > "$T/bin/gh" <<EOS
#!/usr/bin/env bash
echo "\$*" >> "$T/gh-calls"
[ -z "\${GH_FAIL:-}" ] || exit 1
cat "$T/gh/\$3" 2>/dev/null || echo "A fixture issue."
EOS
chmod +x "$T/bin/gh"
pcr() { PATH="$T/bin:$PATH" PLAN_CHECK_ROOT=$T bash "$PC" "$@"; }
batch() { printf '%s\n\n%s\n\nTier: Standard\n\n## Prior art\n\nInternal tooling; no outside library.\n\n## Data design\n\nNo stored data.\n\n## What can go wrong\n\n- Nothing new can break: fixture.\n' "$1" "${2:-}" > "$T/batch.md"; }
batch 'Fix the issues.'
# plan <closes line> <rows> [<steps line>] -- a plan that passes every other check, written to $T/plan.md
plan() {
  printf 'Goal: check the issue cases.\n\n- Planned size: 1 files, 1 changed lines\n%s\n\n## What can go wrong\n\n- a case: t-one\n\n## Steps\n\n%s\n\n## Facts\n\n- code.sh holds three lines -- code.sh:1-3 (observed: 2026-10-01)\n\n## Issue cases\n\n%s\n\n## Acceptance test\n\n- t-one\n' \
    "$1" "${3:-- modify src/x.ts -- the one change}" "$2" > "$T/plan.md"
}
icp() { plan "$@"; pcr "$T/plan.md" "$T/batch.md" >/dev/null 2>"$T/ic-err"; echo $?; } # plan-check on it; prints its code
ics() { local r=0; pcr --issue-cases "$1" > "$T/ic-out" 2>"$T/ic-err" || r=$?; echo "$r:$(grep -cF -- "issue #$1 cases: check not run -- $2" "$T/ic-err")"; }

printf '## Fix\n\n- first fix\n- second fix\n\n## Done means\n\nA paragraph done.\n' > "$T/gh/101"
printf '## Fix\n\nOne paragraph fix.\n\n## Done means\n\n- d one\n' > "$T/gh/102"
# Every CommonMark list marker is a case; a list shape the reader does not know refuses rather than collapsing.
printf '## Fix\n\n+ preserve tenant isolation\n+ reject missing tenant IDs\n\n## Done means\n\n1) one\n2) two\n' > "$T/gh/104"
printf '## Fix\n\na) first\nb) second\n' > "$T/gh/105"
all=$'- #101 Fix 1 -- src/x.ts -- t-one\n- #101 Fix 2 -- src/x.ts -- t-one\n- #101 Done 1 -- src/x.ts -- t-one\n- #102 Fix 1 -- src/x.ts -- t-one\n- #102 Done 1 -- src/x.ts -- t-one'
out="cases101=$(pcr --issue-cases 101 | tr '\n' '|') cases102=$(pcr --issue-cases 102 | tr '\n' '|') cases104=$(pcr --issue-cases 104 | tr '\n' '|')"
out+=" unknown=$(ics 105 'line 3 under Fix looks like a list item')"
out+=" full=$(icp 'Closes: #101 #102' "$all")"
r=$(icp 'Closes: #101 #102' "$(grep -v '#101 Fix 2' <<<"$all")"); out+=" dropped=$r:$(grep -c '#101 Fix 2: second fix' "$T/ic-err")"
r=$(icp 'Closes: #101 #102' "${all//src\/x.ts/src\/y.ts}"); out+=" badpath=$r:$(grep -cm1 'src/y.ts is not a ## Steps path' "$T/ic-err")"
r=$(icp 'Closes: #101 #102' "${all//-- t-one/-- t-gone}"); out+=" badtest=$r:$(grep -cm1 't-gone" is not in ## Acceptance test' "$T/ic-err")"
r=$(GH_FAIL=1 icp 'Closes: #101 #102' "$all"); out+=" ghfail=$r:$(grep -c 'issue #101 cases: check not run' "$T/ic-err")"
: > "$T/gh-calls"; out+=" none=$(icp 'Closes: none' '')$(grep -c . "$T/gh-calls")"
# The Skip launch runs the same check on the batch's own Closes line and rows.
batch 'Typo fix.' $'Closes: #102\n\n## Issue cases\n\n- #102 Done 1 -- a.sh -- t-skip'
r=0; pcr '' "$T/batch.md" >/dev/null 2>"$T/ic-err" || r=$?; out+=" skip=$r:$(grep -c '#102 Fix 1: One paragraph fix.' "$T/ic-err")"
batch 'Typo fix.' $'Closes: #102\n\n## Issue cases\n\n- #102 Done 1 -- a.sh -- t-skip\n- #102 Fix 1 -- a.sh -- t-skip'
r=0; pcr '' "$T/batch.md" >/dev/null 2>"$T/ic-err" || r=$?; out+=" skipfull=$r"
check "the issue-text check refuses a plan or Skip batch that drops a case an issue names, or whose issue cannot be read (issue 444)" \
  "cases101=Fix 1 first fix|Fix 2 second fix|Done 1 A paragraph done.| cases102=Fix 1 One paragraph fix.|Done 1 d one| cases104=Fix 1 preserve tenant isolation|Fix 2 reject missing tenant IDs|Done 1 one|Done 2 two| unknown=2:1 full=0 dropped=2:1 badpath=2:1 badtest=2:1 ghfail=2:1 none=00 skip=2:1 skipfull=0" "$out"

# A prose line opening with an issue ref is text under Fix, and a table row, a quote and such a line are text in a body
# with no Fix section; a marker rule widened to them would refuse every issue that quotes or tabulates its text.
printf '## Fix\n\n#12 covers the rest\n- first\n- second\n' > "$T/gh/106"
printf '| step | why |\n> a quoted note\n#12 covers the rest\n' > "$T/gh/114"
r=0; pcr --issue-cases 106 > "$T/ic-out" 2>"$T/ic-err" || r=$?; out="$r $(tr '\n' '|' < "$T/ic-out")"
r=0; pcr --issue-cases 114 > "$T/ic-out" 2>"$T/ic-err" || r=$?; out+=" $r $(tr '\n' '|' < "$T/ic-out")"
check "the issue reader takes table rows, quotes and #<n> lines as text, never as unknown list items (issue 444)" \
  "0 Fix 1 first|Fix 2 second| 0 Body 1 | step | why ||" "$out"

# A fence nested in a list item outlived the item and hid every Fix item after it; the reader refuses it.
printf '## Fix\n\n- first\n  ~~~\n  example\n- second\n' > "$T/gh/107"
check "the issue reader refuses a code fence nested in a list item rather than dropping the items after it (issue 444)" \
  "2:1" "$(ics 107 'line 4: a code fence inside a list item')"

# Every shape the reader does not model hid Fix items or reset the section; each is refused naming its line.
printf '## Fix\n\n- first fix\n  ## Notes\n  explanation\n- second fix\n' > "$T/gh/108"
printf '## Fix\n\n- first\n  | a | b |\n- second\n' > "$T/gh/109"
printf '## Fix\n\n-\tfirst fix\n  - second fix\n' > "$T/gh/110"
printf '## Fix\n\n```bad`info\n- first required fix\n- second required fix\n' > "$T/gh/111"
printf '## Problem\n\n```bad`info\n## Fix\n\n- first required fix\n- second required fix\n' > "$T/gh/112"
printf '## Fix\n\n## Done means\n\n- d one\n' > "$T/gh/113"
out="h=$(ics 108 'line 4: a heading inside a list item') t=$(ics 109 'line 4: a table row inside a list item')"
out+=" tab=$(ics 110 'line 3: a tab in the indentation') f=$(ics 111 'line 3: a code fence in a Fix or Done means section')"
out+=" empty=$(ics 113 'Fix has no case') before=$(pcr --issue-cases 112 | tr '\n' '|')"
check "the issue reader refuses a tab, a heading, a table or a bad fence that would hide Fix items (issue 444)" \
  "h=2:1 t=2:1 tab=2:1 f=2:1 empty=2:1 before=Fix 1 first required fix|Fix 2 second required fix|" "$out"

# This batch's shape: a numbered ## The issues list of fifteen and no Closes: line. Every issue is read, so one dropped
# case, even the last issue's, refuses; pp_fix_stated reads the same fifteen, so one issue with no Fix case ends it.
nums=(429 430 433 434 435 436 439 441 442 443 444 445 446 447 448)
{ printf 'Fix the issues.\n\nTier: Standard\n\n## The issues\n\n'; i=0; for n in "${nums[@]}"; do i=$((i + 1)); printf '%d. #%s: title\n' "$i" "$n"; done
  printf '\n## Prior art\n\nInternal tooling; no outside library.\n\n## Data design\n\nNo stored data.\n\n## What can go wrong\n\n- Nothing new can break: fixture.\n'; } > "$T/batch.md"
rows=$(for n in "${nums[@]}"; do printf -- '- #%s Body 1 -- src/x.ts -- t-one\n' "$n"; done)
for n in "${nums[@]}"; do printf '## Fix\n\n- do it for %s\n' "$n" > "$T/gh/$n"; done
fixrows=${rows//Body/Fix}
: > "$T/gh-calls"; out="full=$(icp '' "$fixrows") reads=$(sort -u "$T/gh-calls" | grep -c .)"
r=$(icp '' "$(grep -v '#448 ' <<<"$fixrows")"); out+=" dropped=$r:$(grep -c '#448 Fix 1: do it for 448' "$T/ic-err")"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
fixed() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/scratch" \
  bash -c '. "$1/scripts/paths.sh" && pp_fix_stated "$2"' _ "$REAL" "$T/batch.md" >/dev/null 2>&1; echo $?); }
out+=" allfix=$(fixed)"
printf '## Done means\n\n- done\n' > "$T/gh/448"; out+=" lastnofix=$(fixed)"
printf '## Fix\n\n- do it for 448\n' > "$T/gh/448"; out+=" unread=$(GH_FAIL=1 fixed)"
check "fifteen numbered issues and no Closes: line are all checked by issue_check and pp_fix_stated (issue 444)" \
  "full=0 reads=15 dropped=2:1 allfix=0 lastnofix=1 unread=1" "$out"

# A Steps path may be a brace group: it covers each file it expands to, and a file outside the group still refuses.
batch 'Fix the issue.'
grp='- modify scripts/{setup,doctor}.sh -- both'
out="inside=$(icp 'Closes: #7' '- #7 Body 1 -- scripts/setup.sh -- t-one' "$grp") second=$(icp 'Closes: #7' '- #7 Body 1 -- scripts/doctor.sh -- t-one' "$grp")"
r=$(icp 'Closes: #7' '- #7 Body 1 -- scripts/seat.sh -- t-one' "$grp"); out+=" outside=$r:$(grep -c 'scripts/seat.sh is not a ## Steps path' "$T/ic-err")"
r=$(icp 'Closes: #7' '- #7 Body 1 -- scripts/setup.sh -- t-one' '- modify scripts/{setup}.sh -- no comma, literal'); out+=" literal=$r"
check "a Steps path written as a brace group covers each file it names, and a file outside the group still refuses (issue 444)" \
  "inside=0 second=0 outside=2:1 literal=2" "$out"

# A plan in the format before 0.55.0 passes with a warning, but not past the issue check: "every plan, at every tier".
# It has no ## Steps to check a path against, so its rows need a path and a test name, as a Skip batch's do.
batch 'Fix the issue.'
legacy() { printf '# Legacy plan\n\n- Planned size: 1 files, 1 changed lines\nCloses: #101\n\n## What can go wrong\n\n- Lost case: regression-test\n%s\n' "$1" > "$T/plan.md"
  local r=0; pcr "$T/plan.md" "$T/batch.md" >/dev/null 2>"$T/ic-err" || r=$?; echo "$r"; }
r=$(legacy ''); out="norows=$r:$(grep -c '#101 Fix 2: second fix' "$T/ic-err")"
rows=$'\n## Issue cases\n\n- #101 Fix 1 -- src/x.ts -- t-one\n- #101 Fix 2 -- src/x.ts -- t-one\n- #101 Done 1 -- src/x.ts -- t-one'
r=$(legacy "$rows"); out+=" full=$r:$(grep -c 'format before 0.55.0' "$T/ic-err")"
r=$(legacy "${rows//-- t-one/--}"); out+=" notest=$r"
check "a plan in the format before 0.55.0 still runs the issue-text check: a dropped case refuses (issue 444)" \
  "norows=2:1 full=0:1 notest=2" "$out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
