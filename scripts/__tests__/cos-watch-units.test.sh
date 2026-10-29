#!/usr/bin/env bash
# Issue 461: a unit that idles after its closing GO woke the relay (or nothing did, for a unit left with a NO-GO).
# cos-watch-units.sh prints "IDLE <unit>: ..." once for a unit worktree whose last commit is under 24 h old, whose
# newest round (by number: r10 after r9) is not a GO at or after that commit, and which nothing has touched for 12
# minutes (its merge log and its files, bar the hook-written events file). One <unit> <sha> line in
# <state>/<project>.units-idle-seen makes it once. A standing seat (Chief-of-Staff) is never a unit.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ws" "$T/scratch" "$T/home"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
E=(env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR HOME="$T/home" COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch")
watch() { (cd "$T/p" && "${E[@]}" COMMANDECK_WATCH_ONCE=1 bash "$REAL/scripts/cos-watch-units.sh" 2>&1); }
# ts <epoch>: the time as touch -t reads it (GNU date, else BSD date).
ts() { date -d "@$1" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$1" +%Y%m%d%H%M.%S; }
# unit <name> <commit epoch>: a git worktree of the project whose one commit and one file carry that time.
unit() {
  git -C "$T/p" worktree add -q -b "$1" "$T/ws/$1"
  echo x > "$T/ws/$1/f.txt"; git -C "$T/ws/$1" add f.txt
  GIT_AUTHOR_DATE="$2 +0000" GIT_COMMITTER_DATE="$2 +0000" git -C "$T/ws/$1" -c user.name=t -c user.email=t@t commit -q -m c
  touch -t "$(ts "$2")" "$T/ws/$1/f.txt"
}
# round <unit> <N> <GO|NO-GO> <mtime epoch>: the unit's round file, the verdict its last line.
round() {
  mkdir -p "$T/ws/$1/.claude/briefs"
  printf 'a finding\nVERDICT: %s\n' "$3" > "$T/ws/$1/.claude/briefs/$1-r$2-reports.md"
  touch -t "$(ts "$4")" "$T/ws/$1/.claude/briefs/$1-r$2-reports.md"
}
SEENF() { find "$T/home/.commandeck/chief-of-staff" -name '*.units-idle-seen' 2>/dev/null; }
NOW=$(date +%s); C=$((NOW - 1200))   # every commit and file is 20 minutes old
# u1: r9 NO-GO, then r10 GO whose mtime is the commit's own second (r10 sorts before r9 as text).
unit u1 $C; round u1 9 NO-GO $((C + 60)); round u1 10 GO $C
# u2: its newest round is a NO-GO, newer than the commit.  u3: its GO is older than the commit.
unit u2 $C; round u2 1 NO-GO $((C + 300))
unit u3 $C; round u3 1 GO $((C - 600))
# A standing seat idles by design.
unit Chief-of-Staff $C
OUT=$(watch)
check "a unit whose newest GO is newer than its last commit is not idle (issue 461)" "0:0" \
  "$(grep -c '^IDLE u1:' <<<"$OUT"):$(grep -c '^IDLE Chief-of-Staff:' <<<"$OUT")"
check "a NO-GO or older-GO unit is reported idle once (issue 461)" "1:1:2:" \
  "$(grep -c '^IDLE u2:' <<<"$OUT"):$(grep -c '^IDLE u3:' <<<"$OUT"):$(grep -c '^u[23] [0-9a-f]\{7,\}$' "$(SEENF)"):$(watch)"

# Not quiet yet, and not old enough: a file changed 5 minutes ago, or a commit over 24 h old, is not reported; the
# hook-written events file alone does not keep a unit awake.
unit u4 $C; touch -t "$(ts $((NOW - 300)))" "$T/ws/u4/f.txt"
unit u5 $C; mkdir -p "$T/ws/u5/.claude"; echo '{}' > "$T/ws/u5/.claude/builder-events.jsonl"
unit u6 $((NOW - 90000))
OUT=$(watch)
check "a unit with a file changed 5 minutes ago, or a commit over a day old, is not reported; a fresh events file alone is (issue 461)" "0:1:0" \
  "$(grep -c '^IDLE u4:' <<<"$OUT"):$(grep -c '^IDLE u5:' <<<"$OUT"):$(grep -c '^IDLE u6:' <<<"$OUT")"

# The header is the watcher's data design: every kind of file the runs above left (a finding run and a silent one) is
# named there, so no state is written that its readers and reset are not stated for.
HEAD=$(sed -n '2,/^[^#]/p' "$REAL/scripts/cos-watch-units.sh")
KINDS=$(find "$T/home" "$T/scratch" -type f | sed -E 's|.*/||; s/^[^.]+\.[0-9]+\.//; s/-wake-[0-9]+-[0-9]+\.txt$/-wake-/' | sort -u)
check "every file the idle watcher writes is named in its header" "" \
  "$(while read -r k; do grep -qF -- "$k" <<<"$HEAD" || printf '%s ' "$k"; done <<<"$KINDS")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
