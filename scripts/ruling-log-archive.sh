#!/usr/bin/env bash
# ruling-log-archive.sh -- the one-off move of the ruling log's non-ruling rows to <log>.archive-2026-10-24.jsonl
# beside it: prompt rows from any folder but main's checkout and the standing worktrees, Chief-of-Staff, Fast-lane and Research-lane (the panes ruling-log.sh
# logs), void prompt rows, and machine-text prompts (hooks/lib/ruling-typed.jq, the test ruling-log.sh applies to new
# prompts). Picker answers, typed prompts and unreadable lines stay, in order, byte for byte.
# Nothing is deleted. The log is rewritten in place under its own lock (the one ruling-log.sh appends under), so a
# writer waiting on that lock appends to the same file afterwards, and only once the kept and moved rows add up to
# the log's. The big pass runs on a snapshot before the lock; rows appended since are split under it, so writers wait
# only for that. Running it again moves only what was logged the old way since.
# COMMANDECK_RULING_LOG relocates the log; COMMANDECK_MAIN names main's checkout (paths.sh).
# Self-test: bash scripts/__tests__/ruling-log-archive.test.sh
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -9; exit 0 ;; esac
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
. "$HERE/../hooks/lib/project.sh" && pp_project "$PP_MAIN"
LOG=${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}
ARCH=${LOG%.jsonl}.archive-2026-10-24.jsonl
# The whole log, copied beside it before the rewrite truncates it and removed once the rewrite is done: a run killed
# in between (its EXIT trap clears $TMP) leaves every row on disk.
BAK=${LOG%.jsonl}.before-archive.jsonl
die() { echo "ruling-log-archive: $*; nothing moved" >&2; exit 1; }
[ -f "$LOG" ] || die "no log at $LOG"
[ ! -e "$BAK" ] || die "$BAK is there: a run stopped mid-rewrite, so $LOG may be missing rows. Put the copy back (check $LOG for rows appended since, and $ARCH for that run's moved rows), remove it, then run this again"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ruling-archive.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

split() { # <in> <tag>: writes $TMP/<tag>.keep and $TMP/<tag>.arch, prints the line count of <in>
  jq -rR -L "$HERE/../hooks/lib" --arg main "$PP_MAIN" --arg mainp "$PP_MAIN_P" 'include "ruling-typed";
    (try fromjson catch null) as $r
    | if ($r | type) != "object" or $r.source != "prompt" then "k"
      elif $r.void == true then "a"
      elif ($r.cwd // "" | . == $main or . == $mainp or startswith($main + "/") or startswith($mainp + "/") or test("/(Chief-of-Staff|Fast-lane|Research-lane)(/|$)")) | not then "a"
      elif ($r.answer // "" | machine_prompt) then "a"
      else "k" end' "$1" > "$TMP/$2.dec" || die "could not read $1"
  python3 -I -c '
import sys
dec, src, keep, arch = sys.argv[1:]
d = open(dec).read().split()
lines = open(src, "rb").readlines()
if len(d) != len(lines): sys.exit("%d decisions for %d lines" % (len(d), len(lines)))
with open(keep, "wb") as k, open(arch, "wb") as a:
    for t, l in zip(d, lines): (a if t == "a" else k).write(l if l.endswith(b"\n") else l + b"\n")
print(len(lines))' "$TMP/$2.dec" "$1" "$TMP/$2.keep" "$TMP/$2.arch" || die "could not split $1"
}
count() { local n; n=$(wc -l < "$1"); echo $((n)); }

# Whole lines only: a row being appended right now belongs to the part read under the lock.
python3 -I -c '
import sys
b = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(b[:b.rfind(b"\n") + 1])' "$LOG" "$TMP/snap" || die "could not snapshot $LOG"
S=$(wc -c < "$TMP/snap"); S=$((S))
N=$(split "$TMP/snap" snap)

exec 9>>"$LOG"
flock -w 60 9 || die "the log's lock was not free in 60 s"
# Writers only append, so the log must still open with the snapshot; anything else (another run of this move) rewrote it.
head -c "$S" "$LOG" | cmp -s - "$TMP/snap" || die "$LOG changed under this run other than by appends (another move?); run it again"
tail -c +$((S + 1)) "$LOG" > "$TMP/tail"
T=$(split "$TMP/tail" tail); N=$((N + T))
cat "$TMP/tail.keep" >> "$TMP/snap.keep"; cat "$TMP/tail.arch" >> "$TMP/snap.arch"
K=$(count "$TMP/snap.keep") A=$(count "$TMP/snap.arch")
[ $((K + A)) -eq "$N" ] || die "kept $K + moved $A is not the log's $N rows"
# The archive is written first: a failure after it leaves rows in both files, never in neither.
cat "$TMP/snap.arch" >> "$ARCH" || die "could not append to $ARCH (it may hold part of this run's rows)"
cp "$LOG" "$BAK" || { rm -f "$BAK"; die "could not copy $LOG to $BAK (the archive may hold part of this run's rows)"; }
cat "$TMP/snap.keep" > "$LOG" || { echo "ruling-log-archive: rewriting $LOG failed; the whole log is in $BAK" >&2; exit 1; }
rm -f "$BAK"
echo "ruling-log-archive: kept $K of $N rows in $LOG; moved $A to $ARCH"
