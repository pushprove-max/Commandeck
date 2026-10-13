#!/usr/bin/env bash
# cos-watch-inbox.sh [<handle>] -- polls the Orca inbox until a message meant
# for the Chief of Staff pane appears, prints it as plain text and exits, which
# wakes the pane (run it in the background).
# Why a poll and not `orchestration check --wait`: every send is addressed to
# main's run, main's own loop reads it within seconds, and `check --terminal
# <me>` then returns nothing.
# "Meant for the Chief of Staff" = not sent by this pane, not a worker report,
# and either the subject starts with "cos:" or names the Chief of Staff, its
# configured name (chiefOfStaff.name) or the owner, or the orchestrator itself
# wrote it: a plain report from main names nobody. "Wrote it" = a `status`
# message from the run's coordinator pane in Orca's run list, asked at every
# poll because main's handle changes when its context is cleared; when Orca
# names none, the subject rule alone decides. The scripts that send under that
# same handle (seat.sh, main-watch.sh, a driver) send as `question`, never as
# `status`; orca-wait.sh tells main's own notes apart the same way.
# main-watch, heads-up and main: lines and answer-worker.sh's "answer from
# main" (a status, sent to a worker) are main's own traffic.
# Only messages in this project's run count: the inbox is the whole machine's,
# and with no run recorded nothing is relayed.
# A message whose subject starts "FYI" does not wake the pane: each wake
# replays the pane's whole context. It is held and printed, then cleared,
# with the next message that does wake the pane.
# One state file, $COS_KEY.inbox-seq: its first line is the highest sequence
# read, the lines after it are the held notes. One file because the two must
# move together: a poll writes it whole beside itself and swaps it in, so the
# notes are saved and the batch marked read in one step, or neither is. A
# batch for the pane is saved first as "<sequence> pending" with its text,
# shown, then cleared: a batch that could not be shown is shown by the next poll. One
# poller at a time reads and writes it, under a lock on $COS_KEY.inbox-seq.lock
# that the kernel drops when its holder dies.
# The pane's Stop hook (cos-inbox-waiter-stop.sh) matches this script by its
# file name: do not rename it.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
ME=${1:-${ORCA_TERMINAL_HANDLE:-$(bash "$PP_SCRIPTS/cos-tell.sh" --handle 2>/dev/null)}}
NAME=$(jq -r '.chiefOfStaff.name // empty' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null)
# Orca returns the newest rows of the whole machine's inbox. When a full page
# starts past the last row read, there may be unread rows behind it: the poll
# asks again for four times as many (the script exits 3) before it moves on.
# shortcut: it stops asking at 3840 rows; raise that if one gap ever holds more.
poll() {
  local n=60 rc
  while :; do poll_n "$n"; rc=$?; [ "$rc" = 3 ] || return "$rc"; n=$((n * 4)); done
}
poll_n() { # rows to ask for
  local run coord
  run=$(tr -d '[:space:]' < "$PP_RUN_FILE" 2>/dev/null)
  # No answer is not "no orchestrator": a note judged without the run's record
  # would be passed over and marked read, so the poll tries again instead.
  coord=$(orca-ide orchestration run-list --json 2>/dev/null \
    | jq -er --arg r "$run" '.result.runs | arrays | [.[] | select(.id == $r) | .coordinator_handle // empty][0] // ""' 2>/dev/null) || return 1
  orca-ide orchestration inbox --limit "$1" --json 2>/dev/null | python3 -c '
import fcntl, json, os, re, sys
me, seqf, name, run, coord = sys.argv[1:6]
limit = int(sys.argv[6])
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(1)  # Orca busy: try again next poll
ms = d.get("messages") or (d.get("result") or {}).get("messages") or []
top = max((m.get("sequence") or 0 for m in ms), default=0)
lock = open(seqf + ".lock", "a")
fcntl.flock(lock, fcntl.LOCK_EX)  # held until this poll exits
def save(seq, held):
    with open(seqf + ".new", "w") as f:  # closed here, so a write the disk refuses late is caught too
        f.write(f"{seq}\n{held}")
    os.replace(seqf + ".new", seqf)
# A missing file starts from the newest message instead of replaying old ones.
if not os.path.exists(seqf):
    if ms:
        save(top, "")
    sys.exit(1)
first, _, held = open(seqf).read().partition("\n")
# The first line is the place, then "pending" when the rest of the file is a
# batch saved for the pane and not yet shown to it.
words = first.split()
owed = held if "pending" in words else ""
held = "" if owed else held
last = int(words[0]) if words else 0
if not ms and not owed:  # a pending batch is owed whatever the inbox holds now
    sys.exit(1)
if limit < 3840 and len(ms) >= limit and min(m.get("sequence") or 0 for m in ms) > last + 1:
    sys.exit(3)
want = r"^cos\b|chief.of.staff|\bowner\b" + ("|" + re.escape(name) if name else "")
# The Orca inbox holds every project on the machine: this pane relays its own run only.
mine = [m for m in ms if (m.get("sequence") or 0) > last and m.get("from_handle") != me
        and run and m.get("run_id") == run
        and m.get("type") != "worker_done"  # worker reports go to main
        and (re.search(want, m.get("subject") or "", re.I) or (coord and m.get("from_handle") == coord and (m.get("type") or "status") == "status"))
        and not re.match(r"(main-watch|heads-up|main:|answer from main)", m.get("subject") or "", re.I)]
line = lambda m: " ".join(str(x) for x in (m.get("created_at"), (m.get("from_handle") or "")[:14], m.get("subject"), "|", m.get("body"), "\n"))
mine.sort(key=lambda m: m["sequence"])
fyi = [m for m in mine if re.match(r"\s*fyi\b", m.get("subject") or "", re.I)]
wake = [m for m in mine if m not in fyi]
held = held + "".join(line(m) + "\n" for m in fyi)
out = owed + "".join(line(m) + "\n" for m in wake) + ("HELD FYI NOTES (did not wake you):\n" + held + "\n" if held and (wake or owed) else "")
# The one step: the place and the notes are one file, so both move or neither
# does, and a save that fails leaves them as they were with nothing shown.
# A batch for the pane is saved as pending before it is shown and cleared
# after: output that fails loses nothing, the next poll shows the batch. Only
# a clearing save that fails shows a batch twice.
try:
    save(str(max(top, last)) + (" pending" if out else ""), out or held)
except OSError as e:
    sys.exit(f"cos-watch-inbox: inbox state not saved ({e}); the batch is read again")
if not out:
    sys.exit(1)
try:
    left = out.encode()
    while left:  # straight to the pipe: a buffered print reports a closed pipe only as the script ends
        left = left[os.write(1, left):]
    save(max(top, last), "")
except OSError as e:
    sys.exit(f"cos-watch-inbox: the batch was not shown or not marked shown ({e}); the next poll shows it")
sys.exit(0)
' "$ME" "$COS_KEY.inbox-seq" "$NAME" "$run" "$coord" "$1"
}
cos_wait 20 poll
