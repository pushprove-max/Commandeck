#!/usr/bin/env bash
# builder-launch-brief.test.sh -- the Builder brief the launch writes (issue 448). Where main tracks the unit's brief,
# the launch rewrote that tracked file and left it modified, so the pass's rebase of the unit branch onto a moved main
# refused until someone committed it by hand. A brief main does not track (ignored) stays out of every commit.
set -u
. "$(dirname "$0")/fixtures/builder-launch-resume-setup.sh"
# mainhas <path> <text> -- a commit on main writing <path>.
mainhas() { mkdir -p "$P/$(dirname "$1")"; printf '%s\n' "$2" > "$P/$1"; git -C "$P" add -f -- "$1"; git -C "$P" -c user.name=t -c user.email=t@t commit -q -m "$1"; }
subjects() { git -C "$WS/$1" log --format=%s main..HEAD; }

mainhas .claude/briefs/bt1.md 'an older brief'
build bt1
mainhas moved.txt 'main moved'
RB=$(git -C "$WS/bt1" -c user.name=t -c user.email=t@t rebase -q main >/dev/null 2>&1; echo $?)
check "a brief main tracks is committed at launch, so the unit branch rebases onto a moved main with no manual commit (issue 448)" \
  "0 chore(bt1): install the Builder brief 0 0" \
  "$RC $(subjects bt1) $RB $(git -C "$WS/bt1" status --porcelain | wc -l | tr -d ' ')"

mainhas .gitignore '.claude/briefs/'
build bt2
check "an ignored brief stays uncommitted at launch (issue 448)" "0 0 written" \
  "$RC $(subjects bt2 | wc -l | tr -d ' ') $([ -s "$WS/bt2/.claude/briefs/bt2.md" ] && echo written)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
