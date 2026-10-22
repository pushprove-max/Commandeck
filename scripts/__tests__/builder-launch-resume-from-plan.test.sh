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
echo "plan of f1" > "$WS/f1/.claude/plans/f1.md"; fp --dry-run f1
check "--dry-run checks the plan against the judge and installs nothing, opens nothing, keeps the mark" "0:none:0:f1" \
  "$RC:$(onmain f1):$(grep -c . "$T/seats"):$(mark f1)"
B=$(git -C "$P" rev-parse main); fp f1
check "a full run commits that plan alone to main and opens one Builder in the adopted worktree" "0:plan of f1:plan(f1): plan:.claude/plans/f1.md:1:" \
  "$RC:$(onmain f1):$(git -C "$P" log -1 --format=%s main):$(git -C "$P" diff --name-only "$B" main):$(grep -cx 'launch builder f1' "$T/seats"):$(mark f1)"
fp f1
check "a second call while that Builder is live is refused and opens nothing" "2:1:0" "$RC:$(grep -c "^REFUSED: $WS/f1 already exists" "$T/out"):$(grep -c . "$T/seats")"
fpunit f2; judged f2 NO-GO 200; echo 'the revision' > "$WS/f2/.claude/plans/f2.md"
author() { printf 'role=plan-author\nplan=%s\nplanhash=%s\nverdict=PLAN-DONE\ncollected=%s\n' "$WS/f2/.claude/plans/f2.md" "$(hash f2)" "$1" > "$SCR/seat-f2-plan-author.txt"; }
author 150; fp f2
check "a NO-GO and a revision collected before it: refused" "2:none" "$RC:$(onmain f2)"
author 300; fp f2
check "a NO-GO and the plan author's revision collected after it: installed, the Builder opens" "0:the revision:1" "$RC:$(onmain f2):$(grep -cx 'launch builder f2' "$T/seats")"
author() { printf 'role=plan-author\nplan=%s\nplanhash=%s\nverdict=%s\ncollected=%s\n' "$WS/$2/.claude/plans/$2.md" "$(hash "$2")" "$3" "$1" > "$SCR/seat-$2-plan-author.txt"; }
# A Panel's judge whose NO-GO is newer than nothing but older than the other judge's GO, on the same plan bytes: its
# findings are unresolved (no revision came after them), so the later GO does not carry the launch.
fpunit f4; judged f4 NO-GO 100 sol; judged f4 GO 101 astra; fp f4
check "a GO beside another judge's NO-GO on the same plan is refused, nothing on main, no Builder" "2:1:none:0" \
  "$RC:$(grep -c '^REFUSED: .*NO-GO' "$T/out"):$(onmain f4):$(grep -c . "$T/seats")"
echo 'the revision of f4' > "$WS/f4/.claude/plans/f4.md"; author 150 f4 PLAN-DONE; judged f4 GO 160 astra; fp --dry-run f4
check "a NO-GO answered by a revision the other judge then passed is not a conflict" 0 "$RC"
# A plan author that stopped PLAN-BLOCKED left a partial plan: not a revision to build.
fpunit f5; judged f5 NO-GO 200; echo 'half a plan' > "$WS/f5/.claude/plans/f5.md"; author 300 f5 PLAN-BLOCKED; fp f5
check "a revision collected PLAN-BLOCKED after a NO-GO is refused, nothing on main" "2:none:0" "$RC:$(onmain f5):$(grep -c . "$T/seats")"
# Two launches of one unit never share the checked copy: a launch paused after its check (here, in hashing its copy)
# while a dry run reads an edited plan and is refused still commits the bytes it checked.
REAL_SHA=$(command -v sha256sum)
printf '#!/usr/bin/env bash\n%s "$@"; r=$?\n! mv "%s/pause" "%s/paused" 2>/dev/null || while [ -e "%s/paused" ]; do sleep 0.1; done\nexit $r\n' \
  "$REAL_SHA" "$T" "$T" "$T" > "$T/bin/sha256sum"; chmod +x "$T/bin/sha256sum"
fpunit f6; judged f6 GO 200; touch "$T/pause"
(cd "$P" && "${E[@]}" bash "$T/plug/scripts/builder-launch.sh" --from-plan f6 </dev/null >"$T/out-a" 2>&1) & A=$!
for _ in $(seq 100); do [ -e "$T/paused" ] && break; sleep 0.1; done
echo 'unchecked B' > "$WS/f6/.claude/plans/f6.md"; fp --dry-run f6; RCB=$RC; rm -f "$T/paused"; wait "$A"; RCA=$?
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
mkdir -p "$HOME/.claude"; echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolEnabled": false, "planJudgeAstraEnabled": false}}}}' > "$HOME/.claude/settings.json"
fp f10
check "both judges off: the author's PLAN-DONE plan installs unjudged and the Builder opens" "0:plan of f10:1" "$RC:$(onmain f10):$(grep -cx 'launch builder f10' "$T/seats")"
fpunit f11; author 100 f11 PLAN-BLOCKED; fp --dry-run f11
check "both judges off: a PLAN-BLOCKED plan is still refused" 2 "$RC"
# A value an Enabled key does not take is no answer that the judges are off: the launch stops, as plan-tier.sh does.
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"planJudgeSolEnabled": "disabled", "planJudgeAstraEnabled": "disabled"}}}}' > "$HOME/.claude/settings.json"
fpunit f12; author 100 f12 PLAN-DONE; fp f12
check "judges' Enabled keys holding a value they do not take: refused naming the key, nothing on main, no Builder" "2:1:none:0" \
  "$RC:$(grep -c '^REFUSED: /plugin config planJudgeSolEnabled = disabled' "$T/out"):$(onmain f12):$(grep -cx 'launch builder f12' "$T/seats")"
rm -f "$HOME/.claude/settings.json"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
