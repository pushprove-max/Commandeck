#!/usr/bin/env bash
# builder-launch-resume-from-plan.test.sh -- the plan the judge read goes to main and the Builder opens, in one call.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
cp "$REAL/scripts/plan-worktree-close.sh" "$T/plug/scripts/"

# Issue 256: --from-plan takes the plan the judge read, in the unit's planning worktree, to main and opens the Builder
# in one call. Only the plan the judge's record hashed at launch (on a GO), or the plan author's revision collected
# after a NO-GO, is installed; any other is refused with nothing on main.
fpunit f1; fp f1
check "no judge's verdict on the plan: refused with the reason, nothing on main, no Builder" "2:1:none:0" \
  "$RC:$(grep -c "^REFUSED: no plan judge's verdict on $WS/f1/.claude/plans/f1.md" "$T/out"):$(onmain f1):$(grep -c . "$T/seats")"
judged f1 GO 200; echo 'an edit after the GO' >> "$WS/f1/.claude/plans/f1.md"; fp f1
check "a plan edited after the judge's GO is refused, nothing on main" "2:1:none:0" \
  "$RC:$(grep -c '^REFUSED: .* is not the plan the judge read' "$T/out"):$(onmain f1):$(grep -c . "$T/seats")"
printf 'plan of f1\n%s\n' "$PSZ" > "$WS/f1/.claude/plans/f1.md"; fp --dry-run f1
check "--dry-run checks the plan against the judge and installs nothing, opens nothing, keeps the mark" "0:none:0:f1" \
  "$RC:$(onmain f1):$(grep -c . "$T/seats"):$(mark f1)"
B=$(git -C "$P" rev-parse main); fp f1
check "a full run commits that plan alone to main and opens one Builder in the adopted worktree" "0:plan of f1:plan(f1): plan:.claude/plans/f1.md:1:" \
  "$RC:$(onmain f1):$(git -C "$P" log -1 --format=%s main):$(git -C "$P" diff --name-only "$B" main):$(grep -cx 'launch builder f1' "$T/seats"):$(mark f1)"
fp f1
check "a second call while that Builder is live is refused and opens nothing" "2:1:0" "$RC:$(grep -c "^REFUSED: $WS/f1 already exists" "$T/out"):$(grep -c . "$T/seats")"
fpunit f2; judged f2 NO-GO 200; printf 'the revision\n%s\n' "$PSZ" > "$WS/f2/.claude/plans/f2.md"
author() { printf 'role=plan-author\nplan=%s\nplanhash=%s\nverdict=PLAN-DONE\ncollected=%s\n' "$WS/f2/.claude/plans/f2.md" "$(hash f2)" "$1" > "$SCR/seat-f2-plan-author.txt"; }
author 150; fp f2
check "a NO-GO and a revision collected before it: refused" "2:none" "$RC:$(onmain f2)"
author 300; fp f2
check "a NO-GO and the plan author's revision collected after it: installed, the Builder opens" "0:the revision:1" "$RC:$(onmain f2):$(grep -cx 'launch builder f2' "$T/seats")"
author() { printf 'role=plan-author\nplan=%s\nplanhash=%s\nverdict=%s\ncollected=%s\n' "$WS/$2/.claude/plans/$2.md" "$(hash "$2")" "$3" "$1" > "$SCR/seat-$2-plan-author.txt"; }
# A Panel's judge whose NO-GO is newer than nothing but older than the other judge's GO, on the same plan bytes: its
# findings are unresolved (no revision came after them), so the later GO does not carry the launch.
fpunit f4; judged f4 NO-GO 100 sol; judged f4 GO 101 fable; fp f4
check "a GO beside another judge's NO-GO on the same plan is refused, nothing on main, no Builder" "2:1:none:0" \
  "$RC:$(grep -c '^REFUSED: .*NO-GO' "$T/out"):$(onmain f4):$(grep -c . "$T/seats")"
printf 'the revision of f4\n%s\n' "$PSZ" > "$WS/f4/.claude/plans/f4.md"; author 150 f4 PLAN-DONE; judged f4 GO 160 fable; fp --dry-run f4
check "a NO-GO answered by a revision the other judge then passed is not a conflict" 0 "$RC"
# A plan author that stopped PLAN-BLOCKED left a partial plan: not a revision to build.
fpunit f5; judged f5 NO-GO 200; printf 'half a plan\n%s\n' "$PSZ" > "$WS/f5/.claude/plans/f5.md"; author 300 f5 PLAN-BLOCKED; fp f5
check "a revision collected PLAN-BLOCKED after a NO-GO is refused, nothing on main" "2:none:0" "$RC:$(onmain f5):$(grep -c . "$T/seats")"
# Two launches of one unit never share the checked copy: a launch paused after its check (here, in hashing its copy)
# while a dry run reads an edited plan and is refused still commits the bytes it checked.
REAL_SHA=$(command -v sha256sum)
printf '#!/usr/bin/env bash\n%s "$@"; r=$?\n! mv "%s/pause" "%s/paused" 2>/dev/null || while [ -e "%s/paused" ]; do sleep 0.1; done\nexit $r\n' \
  "$REAL_SHA" "$T" "$T" "$T" > "$T/bin/sha256sum"; chmod +x "$T/bin/sha256sum"
fpunit f6; judged f6 GO 200; touch "$T/pause"
(cd "$P" && "${E[@]}" bash "$T/plug/scripts/builder-launch.sh" --from-plan f6 </dev/null >"$T/out-a" 2>&1) & A=$!
for _ in $(seq 100); do [ -e "$T/paused" ] && break; sleep 0.1; done
printf 'unchecked B\n%s\n' "$PSZ" > "$WS/f6/.claude/plans/f6.md"; fp --dry-run f6; RCB=$RC; rm -f "$T/paused"; wait "$A"; RCA=$?
# The paused launch then finds the edit in the worktree it would take over, and opens no Builder on it.
check "a dry run refused meanwhile does not swap the plan a paused launch checked: that plan reaches main, no Builder" "2:2:plan of f6:0" \
  "$RCB:$RCA:$(onmain f6):$(grep -cx 'launch builder f6' "$T/seats")"
rm -f "$T/bin/sha256sum"
check "no launch leaves its checked copy behind" 0 "$(ls "$SCR" | grep -c 'plan-frozen')"
# The batch goes to the Builder unchanged, so its Plan section names the judged plan and no other.
fpunit f7; judged f7 GO 200; sed -i.bak 's@plans/f7.md@plans/toy.md@g' "$WS/f7/.claude/briefs/f7-batch.md"; rm -f "$WS/f7/.claude/briefs/f7-batch.md.bak"; fp --dry-run f7
check "a batch naming another plan is refused" "2:1" "$RC:$(grep -c '^REFUSED: .*f7-batch.md names .claude/plans/toy.md' "$T/out")"
sed -i.bak 's@plans/toy.md@plans/f7.md .claude/plans/toy.md@' "$WS/f7/.claude/briefs/f7-batch.md"; rm -f "$WS/f7/.claude/briefs/f7-batch.md.bak"; fp --dry-run f7
check "a batch naming this plan and another is refused too" 2 "$RC"
fpunit f3; judged f3 GO 200; touch "$T/seat-fails"; fp f3; rm "$T/seat-fails"; fp f3
check "a retry after the Builder failed to open finds the plan on main byte for byte and goes on, one plan commit" "0:1:1" \
  "$RC:$(grep -cx 'launch builder f3' "$T/seats"):$(git -C "$P" log --format=%s main | grep -cx 'plan(f3): plan')"
# A clean, tracked link where the plan goes on main would have cp write through it to a file outside the plan.
fpunit f8; judged f8 GO 200; printf 'KEEP\n' > "$T/keep"; ln -s "$T/keep" "$P/.claude/plans/f8.md"
git -C "$P" add .claude/plans/f8.md; git -C "$P" commit -qm link; fp f8
check "a plan path on main that is a link is refused, its target untouched, no Builder" "2:KEEP:0" "$RC:$(cat "$T/keep"):$(grep -c 'launch builder' "$T/seats")"
# So is a link in its parents: mkdir -p and cp go through it too.
fpunit f9; judged f9 GO 200; mkdir "$T/away"; mv "$P/.claude/plans" "$T/plansdir"; ln -s "$T/away" "$P/.claude/plans"; fp f9
check "a plans folder on main that is a link is refused, nothing written through it" "2:0" "$RC:$(ls "$T/away" | wc -l | tr -d ' ')"
rm "$P/.claude/plans"; mv "$T/plansdir" "$P/.claude/plans"
# Issue 312: with both judges off in /plugin config the plan installs unjudged: the author's PLAN-DONE plan, no other.
cp -R "$REAL/.claude-plugin" "$T/plug/"   # the manifest lists the Enabled keys, as an installed plugin has it
fpunit f10; author 100 f10 PLAN-DONE; fp --dry-run f10
check "a judge on and no verdict: the author's plan alone is refused" "2:1" "$RC:$(grep -c "^REFUSED: no plan judge's verdict" "$T/out")"
mkdir -p "$HOME/.claude"; echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolEnabled": false, "planJudgeFableEnabled": false}}}}' > "$HOME/.claude/settings.json"
fp f10
check "both judges off: the author's PLAN-DONE plan installs unjudged and the Builder opens" "0:plan of f10:1" "$RC:$(onmain f10):$(grep -cx 'launch builder f10' "$T/seats")"
fpunit f11; author 100 f11 PLAN-BLOCKED; fp --dry-run f11
check "both judges off: a PLAN-BLOCKED plan is still refused" 2 "$RC"
# A value an Enabled key does not take is no answer that the judges are off: the launch stops, as plan-tier.sh does.
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolEnabled": "disabled", "planJudgeFableEnabled": "disabled"}}}}' > "$HOME/.claude/settings.json"
fpunit f12; author 100 f12 PLAN-DONE; fp f12
check "judges' Enabled keys holding a value they do not take: refused naming the key, nothing on main, no Builder" "2:1:none:0" \
  "$RC:$(grep -c '^REFUSED: /plugin config planJudgeSolEnabled = disabled' "$T/out"):$(onmain f12):$(grep -cx 'launch builder f12' "$T/seats")"
# Issue 342: a plan author may end on PLAN-WRITTEN or PLAN-REVISED, the words a plan spec can use for a finished plan or a
# revision; the launcher takes them as it takes PLAN-DONE. Any other marker is still not a finish.
rm -f "$HOME/.claude/settings.json"
for M in PLAN-WRITTEN PLAN-REVISED; do
  u=g-$(tr 'A-Z' 'a-z' <<<"${M#PLAN-}"); fpunit "$u"; judged "$u" NO-GO 200; printf "the revision of $u\n%s\n" "$PSZ" > "$WS/$u/.claude/plans/$u.md"; author 300 "$u" "$M"; fp "$u"
  check "a NO-GO and a revision collected $M after it: installed, the Builder opens" "0:the revision of $u:1" "$RC:$(onmain "$u"):$(grep -cx "launch builder $u" "$T/seats")"
done
fpunit g-other; judged g-other NO-GO 200; printf 'half a plan\n%s\n' "$PSZ" > "$WS/g-other/.claude/plans/g-other.md"; author 300 g-other PLAN-MAYBE; fp g-other
check "a revision collected under another marker is still refused, nothing on main" "2:none" "$RC:$(onmain g-other)"
rm -f "$HOME/.claude/settings.json"

# Issue 362: what a plan and its batch must hold before a Builder opens. A plan is written whole, then judged on its bytes.
planned_as() { # <unit> <plan text> -- a judged-GO plan with that text
  fpunit "$1"; printf '%s\n' "$2" > "$WS/$1/.claude/plans/$1.md"; judged "$1" GO 200; }
planned_as h1 "$(printf 'plan of h1\n%s\n\n## Decisions\n\n1. Keep the lock.\n   Test: lock.test.sh -- the lock is kept\n2. Drop the cache, no reader left.\n3. Retry twice, then stop.\n   - Test: retry.test.sh -- stops after two\n' "$PSZ")"
fp h1
check "a decision with no Test: line is refused, naming it, and nothing reaches main" "2:1:1:none:0" \
  "$RC:$(grep -c 'REFUSED: .* decisions or accepted failure modes with no Test: line' "$T/out"):$(grep -c '^  - 2\. Drop the cache' "$T/out"):$(onmain h1):$(grep -c . "$T/seats")"
check "and the decisions that carry a Test: line, on it or on a line below it, are not listed" 0 "$(grep -c '^  - [13]\.' "$T/out")"
planned_as h2 "$(printf 'plan of h2\n\n## Accepted failure modes\n\n- a lost wake: main reads the board next.\n' )"
fp h2
check "a plan with no size line is refused, nothing on main" "2:1:none" "$RC:$(grep -c 'REFUSED: .* has no size line' "$T/out"):$(onmain h2)"
planned_as h3 "$(printf 'plan of h3\n* Planned size: ~2 files, ~40 lines (tests ~20)%s\n\n## Decisions\n\n1. One thing. Test: none, a doc line.\n' "$ICASES")"
fp h3
check "a size line with a * bullet, ~ and a note, and a decision whose Test: says none, is taken" "0:plan of h3" "$RC:$(onmain h3)"
planned_as h4 "$(printf 'plan of h4\n%s\n' "$PSZ")"
sed -i.bak '/^## What can go wrong$/,/^## Plan$/{/^## Plan$/!d;}' "$WS/h4/.claude/briefs/h4-batch.md"; rm -f "$WS/h4/.claude/briefs/h4-batch.md.bak"
fp h4
check "a batch and a plan with no What can go wrong section: refused, nothing on main" "2:1:none" "$RC:$(grep -c 'REFUSED: neither .* has a What can go wrong section' "$T/out"):$(onmain h4)"
printf '\n## What can go wrong\n\nan empty list: one named test\n' >> "$WS/h4/.claude/plans/h4.md"; judged h4 GO 200
fp h4
check "the plan's own What can go wrong section stands in for the batch's" "0:plan of h4" "$RC:$(onmain h4)"

# Issue 362: a plan under 150 planned lines that one judge sent back launches when main's rulings, written after the
# judge ran, stand in for the revision; without them, or at 150 lines, or beside a second judge's record, it is refused.
small() { # <unit> <changed lines> -- a plan sol judged NO-GO, 1 hour ago, with no revision
  fpunit "$1"; printf 'plan of %s\n- Planned size: 4 files, %s changed lines%s\n' "$1" "$2" "$ICASES" > "$WS/$1/.claude/plans/$1.md"
  judged "$1" NO-GO 200 sol; touch -d '1 hour ago' "$SCR/seat-$1-plan-judge-sol.txt"; }
rulings() { mkdir -p "$P/.claude/briefs"; printf '1. accept the finding about the lock.\n' > "$P/.claude/briefs/$1-main-rulings.md"; }
small n1 80; fp n1
check "a small NO-GO plan with no rulings from main is refused, nothing on main" "2:none:0" "$RC:$(onmain n1):$(grep -c . "$T/seats")"
rulings n1; fp n1
check "a small NO-GO plan launches with main's newer rulings, and says so" "0:plan of n1:1:1" \
  "$RC:$(onmain n1):$(grep -cx 'launch builder n1' "$T/seats"):$(grep -c "^plan: plan-judge-sol returned NO-GO; main's rulings stand in for the revision (80 planned lines, under 150)" "$T/out")"
small n2 150; rulings n2; fp n2
check "a NO-GO plan at 150 planned lines is refused with the cap named, nothing on main" "2:1:none" "$RC:$(grep -c 'REFUSED: .* under 150 planned lines (this one says 150)' "$T/out"):$(onmain n2)"
small n3 149; rulings n3; fp n3
check "a NO-GO plan at 149 planned lines is taken" "0:plan of n3" "$RC:$(onmain n3)"
small n4 80; rulings n4; touch -d '2 hours ago' "$P/.claude/briefs/n4-main-rulings.md"; fp n4
check "rulings written before the judge ran do not stand in for the revision" "2:none" "$RC:$(onmain n4)"
small n5 80; rulings n5; judged n5 NO-GO 150 fable; fp n5
check "a Panel's second judge on the same plan: main's rulings do not stand in" "2:none" "$RC:$(onmain n5)"
printf '\nan edit after the judge\n' >> "$WS/n5/.claude/plans/n5.md"; rm -f "$SCR/seat-n5-plan-judge-fable.txt"; fp n5
check "a small NO-GO plan edited after the judge read it is refused, nothing on main" "2:none" "$RC:$(onmain n5)"
rm -f "$HOME/.claude/settings.json"

# Issue 444: a bundle whose every issue states its fix (a Fix case in the issue's own text) has no revise session at any
# size, so a plan over the line that one judge sent back launches on main's newer rulings. The shared fixture: a unit
# whose plan says 150 changed lines, the judge's NO-GO an hour old, main's rulings newer, and issue 1 (the batch's one)
# with the body kind given, which plan-check --issue-cases reads from the gh stub.
mkdir -p "$T/gh"
printf '#!/usr/bin/env bash\ncat "%s/gh/$3" 2>/dev/null || printf "## Fix\\n\\n- do it\\n"\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/gh"
fixstated() { # <unit> <Fix|Done means> <judge: sol|fable>
  fpunit "$1"; printf 'plan of %s\n- Planned size: 4 files, 150 changed lines\n\n## Issue cases\n\n- #1 %s 1 -- src/x.ts -- t-one\n' "$1" "${2%% *}" > "$WS/$1/.claude/plans/$1.md"
  printf '## %s\n\n- the one case\n' "$2" > "$T/gh/1"
  judged "$1" NO-GO 200 "$3"; touch -d '1 hour ago' "$SCR/seat-$1-plan-judge-$3.txt"; rulings "$1"; }
fixstated fs1 Fix sol; fp fs1
out="$RC:$(onmain fs1):$(grep -cx 'launch builder fs1' "$T/seats"):$(grep -c 'launch plan-author' "$T/seats"):$(grep -c "^plan: plan-judge-sol returned NO-GO; main's rulings stand in for the revision (every issue states its fix)" "$T/out")"
fixstated fs2 'Done means' sol; fp fs2
out+=" $RC:$(onmain fs2):$(grep -c 'or one whose every issue has a Fix case' "$T/out")"
check "a fix-stated plan over 150 lines launches on a NO-GO with main's rulings and no revise (issue 444)" \
  "0:plan of fs1:1:0:1 2:none:1" "$out"

# The selected judge's NO-GO is the one main's rulings answer: Fable's, only while Sol is off in /plugin config (plan-tier.sh
# then runs Fable alone). With Sol on, a Fable NO-GO needs its revision; a value the Sol key does not take stops the launch.
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolEnabled": false}}}}' > "$HOME/.claude/settings.json"
fixstated ff1 Fix fable; fp ff1
out="soloff=$RC:$(onmain ff1):$(grep -c "^plan: plan-judge-fable returned NO-GO; main's rulings stand in" "$T/out")"
rm -f "$HOME/.claude/settings.json"
fixstated ff2 Fix fable; fp ff2
out+=" unset=$RC:$(onmain ff2)"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolEnabled": "maybe"}}}}' > "$HOME/.claude/settings.json"
fixstated ff3 Fix fable; fp ff3
out+=" maybe=$RC:$(onmain ff3):$(grep -c '^REFUSED: /plugin config planJudgeSolEnabled = maybe' "$T/out")"
rm -f "$HOME/.claude/settings.json"
check "a sole Fable NO-GO launches on main's newer rulings only while Sol is off (issue 444)" \
  "soloff=0:plan of ff1:1 unset=2:none maybe=2:none:1" "$out"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
