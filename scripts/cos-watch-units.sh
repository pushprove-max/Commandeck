#!/usr/bin/env bash
# cos-watch-units.sh -- waits until a unit has gone idle without a closing GO, prints "IDLE <unit>: ..." and exits,
# which wakes the pane (run it in the background). A unit is a git worktree under the workspaces folder, not a
# standing seat (Chief-of-Staff, Fast-lane, Research-lane), that has: a last commit under 24 h old; a newest round
# (by number: r10 after r9) that is not a GO at or after that commit, its verdict being the round file's last line;
# and no change for 12 minutes to its merge log or its files (the hook-written .claude/builder-events.jsonl aside).
# <state>/<project>.units-idle-seen holds one "<unit> <short sha>" line for each idle unit this watcher printed: a
# unit is told once per commit. cos_wait (cos-lib.sh) also writes, as for every watcher: <state>/<project>.cos-watch-units.pid
# at start (overwritten each start; no reader, the Stop hook does not hold this watcher); one
# <state>/<project>.cos-watch-units-wake-<epoch>-<pid>.txt per poll, removed when the poll finds nothing, kept (never
# pruned) when it wakes; and on a wake one line to $PP_SCRATCH/wake-log.jsonl (rotated at 1 MB). A stop at any point
# leaves only those; a restart rewrites the pid and polls afresh. Nothing else is written; the worktrees and logs are
# read only (issue 461).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
SEEN=$COS_KEY.units-idle-seen
touch "$SEEN"
# mtime <file>: seconds since the epoch (GNU stat, else BSD stat).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
poll() {
  local now wt u sha ct f n top="" topf="" why found=0 quiet=720
  now=$(date +%s)
  for wt in "$PP_WORKSPACES"/*/; do
    wt=${wt%/}; [ -e "$wt/.git" ] || continue
    u=${wt##*/}
    ! pp_standing_wt "$u" || continue
    ct=$(git -C "$wt" log -1 --format=%ct 2>/dev/null) || continue
    [ -n "$ct" ] && [ $((now - ct)) -lt 86400 ] || continue
    sha=$(git -C "$wt" rev-parse --short HEAD 2>/dev/null) || continue
    ! grep -qxF "$u $sha" "$SEEN" || continue
    # The newest round by number, then its verdict at or after the commit (an equal second counts as after).
    top="" topf=""
    for f in "$wt/.claude/briefs/$u-r"[0-9]*-reports.md; do
      [ -e "$f" ] || continue
      n=${f##*/}; n=${n#"$u-r"}; n=${n%-reports.md}
      [[ $n =~ ^[0-9]+$ ]] || continue
      if [ -z "$top" ] || [ "$n" -gt "$top" ]; then top=$n topf=$f; fi
    done
    if [ -n "$topf" ] && [ "$(tail -n 1 "$topf" | tr -d '[:space:]')" = "VERDICT:GO" ] && [ "$(mtime "$topf")" -ge "$ct" ]; then continue; fi
    # Quiet: the merge log and every file but .git, node_modules and the events file untouched for 12 minutes.
    f=$PP_SCRATCH/merge-$u.log
    [ ! -e "$f" ] || [ $((now - $(mtime "$f"))) -ge $quiet ] || continue
    [ -z "$(find "$wt" \( -name .git -o -name node_modules \) -prune -o -type f ! -path "$wt/.claude/builder-events.jsonl" -mmin -12 -print -quit 2>/dev/null)" ] || continue
    echo "$u $sha" >> "$SEEN"
    why="no round file yet"; [ -z "$top" ] || why="newest round r$top is not a GO at or after it"
    echo "IDLE $u: last commit $sha $(( (now - ct) / 60 )) min ago; $why; nothing changed for 12 min"
    found=1
  done
  [ "$found" = 1 ]
}
cos_wait 60 poll
