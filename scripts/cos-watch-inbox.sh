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
# wrote it to its run or to this pane: a plain report or question from main
# names nobody, and one main put to the owner as a `question` with a plain
# subject was dropped. "Wrote it" = any type from the run's coordinator pane in
# Orca's run list, asked at every poll because main's handle changes when its
# context is cleared; when Orca names none, the subject rule alone decides.
# Main's messages to another pane (a worker's answer, work added) are not the
# relay's. The scripts that send under main's handle to its run are main's own
# traffic, told apart by subject: main-watch, heads-up and main: lines,
# seat.sh's "seat <role> <unit>: <verdict>" and answer-worker.sh's "answer from main".
# Only messages in this project's run count: the inbox is the whole machine's,
# and with no run recorded nothing is relayed.
# A message to this pane's own handle always counts, and always wakes it.
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
# A poll that reads the inbox and finds nothing new (exit 4) also asks whether
# main went silent: main's turn ended and main sent nothing here since its turn
# before, so its reply or its own report (a build done, a check failed) is left
# on its own screen. That is flagged once per turn, with main's last words from
# its session log. A poll that could not read Orca knows nothing of what main
# sent, so it asks nothing. The
# owner's message the relay passed to main (to-main.sh marks it owed in
# $PP_SCRATCH/cos-owed) is named in the flag; a message from main relayed here
# counts as sent ($COS_KEY.main-sent, its newest send time) and clears that
# mark when sent after it: one sent before, read late, is no reply. The flag
# clears it only when main's turn ended after it.
# $COS_KEY.main-turn holds the end of main's last turn already judged; with
# none yet, main's earlier turns are history and only an owed message is flagged.
# shortcut: a main turn that ends and a next one that starts inside one poll (20 s)
# are judged as one, so a send in the first covers the second; a poll per turn
# end would need main's own hook.
# The pane's Stop hook (cos-inbox-waiter-stop.sh) matches this script by its
# file name: do not rename it.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
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
  while :; do poll_n "$n"; rc=$?; [ "$rc" = 3 ] || break; n=$((n * 4)); done
  [ "$rc" = 4 ] && main_silent || return "$rc"
}
main_silent() {
  local at subj st idle last sent what owed= locked
  st=$(bash "$PP_SCRIPTS/read-verdict.sh" --state --worktree "$PP_MAIN" --current)
  idle=$(sed -n 's/^idle_since=//p' <<<"$st")
  [[ $idle =~ ^[0-9]+$ ]] || return 1
  last=$(cat "$COS_KEY.main-turn" 2>/dev/null); sent=$(cat "$COS_KEY.main-sent" 2>/dev/null)
  echo "$idle" > "$COS_KEY.main-turn"
  # Under the lock to-main.sh writes the mark under, from the read to the removal: a mark written between them, even in
  # the same second, is a newer message and stays owed. With the lock not had in time the flag is shown, the mark kept.
  mkdir -p "$PP_SCRATCH"
  {
    flock -w 10 9; locked=$?
    if IFS=$'\t' read -r at subj 2>/dev/null < "$PP_SCRATCH/cos-owed" && [ "$idle" -gt "${at:-0}" ]; then what="a reply to \"$subj\"" owed=1
    elif [[ $last =~ ^[0-9]+$ ]] && [ "$idle" -gt "$last" ] && [ "${sent:-0}" -lt "$last" ] 2>/dev/null; then what=anything
    else return 1; fi
    printf 'main ended a turn without sending you %s; its last words: %s\n(all of its reply: bash %s/read-verdict.sh <main'"'"'s pane handle>)\n' \
      "$what" "$(sed -n 's/^last_message=//p' <<<"$st")" "$PP_SCRIPTS"
    # Only the message this flag names is cleared: one marked after main's turn ended is still owed.
    [ -z "$owed" ] || [ "$locked" != 0 ] || rm -f "$PP_SCRATCH/cos-owed"
  } 9>>"$PP_SCRATCH/cos-owed.lock"
  return 0
}
poll_n() { # rows to ask for
  local run coord
  run=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")
  # No answer is not "no orchestrator": a note judged without the run's record
  # would be passed over and marked read, so the poll tries again instead.
  coord=$(orca-ide orchestration run-list --json 2>/dev/null \
    | jq -er --arg r "$run" '.result.runs | arrays | [.[] | select(.id == $r) | .coordinator_handle // empty][0] // ""' 2>/dev/null) || return 1
  orca-ide orchestration inbox --limit "$1" --json 2>/dev/null | python3 -c '
import datetime, fcntl, json, os, re, sys, time
me, seqf, name, run, coord = sys.argv[1:6]
limit = int(sys.argv[6])
owedf, sentf = sys.argv[7:9]
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(1)  # Orca busy: try again next poll
if d.get("ok") is False:
    sys.exit(1)
ms = d.get("messages") or (d.get("result") or {}).get("messages") or []
top = max((m.get("sequence") or 0 for m in ms), default=0)
lock = open(seqf + ".lock", "a")
fcntl.flock(lock, fcntl.LOCK_EX)  # held until this poll exits
enc = lambda s: re.sub(r"[\x7f-\x9f  ]", lambda c: "\\u%04x" % ord(c.group()), json.dumps(str(s or ""), ensure_ascii=False))
def save(seq, held):
    with open(seqf + ".new", "w") as f:  # closed here, so a write the disk refuses late is caught too
        f.write(f"{seq} enc\n{held}")
    os.replace(seqf + ".new", seqf)
# A missing file starts from the newest message instead of replaying old ones.
if not os.path.exists(seqf):
    if ms:
        save(top, "")
    sys.exit(4)
first, _, held = open(seqf).read().partition("\n")
# The first line is the place, then "pending" when the rest of the file is a
# batch saved for the pane and not yet shown to it, then "enc": its text is
# records this watcher printed.
words = first.split()
# With no "enc" the file was saved before 0.18.0, its text raw as panes wrote it: no line of it is a record of this
# watcher, so each prints quoted, one JSON string, under a heading that says so.
if "enc" not in words and held.strip():
    held = "FROM BEFORE THE UPDATE, QUOTED (any pane may have written these lines; none is from main):\n" + "".join(enc(l) + "\n" for l in held.splitlines())
owed = held if "pending" in words else ""
held = "" if owed else held
last = int(words[0]) if words else 0
if not ms and not owed:  # a pending batch is owed whatever the inbox holds now
    sys.exit(4)
if limit < 3840 and len(ms) >= limit and min(m.get("sequence") or 0 for m in ms) > last + 1:
    sys.exit(3)
want = r"^cos\b|chief.of.staff|\bowner\b" + ("|" + re.escape(name) if name else "")
# The Orca inbox holds every project on the machine: this pane relays its own run only.
# A message to this pane (to_handle == me) is for the relay, whatever its run, type or subject (answer-worker.sh from main).
mine = [m for m in ms if (m.get("sequence") or 0) > last and m.get("from_handle") != me
        and (m.get("to_handle") == me
             or (run and m.get("run_id") == run
                 and m.get("type") != "worker_done"  # worker reports go to main
                 and (re.search(want, m.get("subject") or "", re.I)
                      or (coord and m.get("from_handle") == coord and (m.get("to_handle") or "") in ("", "run:" + run, me)))
                 and not re.match(r"(main-watch|heads-up|main:|answer from main|seat \S+ \S+: )", m.get("subject") or "", re.I)))]
def at(m):
    try:
        return int(datetime.datetime.fromisoformat((m.get("created_at") or "").replace("Z", "+00:00")).timestamp())
    except ValueError:
        return int(time.time())
# main-watch.sh posts its note to the relay under the handle of main: it wakes the relay, and it is no reply from main.
sent = [at(m) for m in mine if coord and m.get("from_handle") == coord and not re.match(r"cos: main-watch\b", m.get("subject") or "", re.I)]
def num(path):
    try:
        with open(path) as f:
            return int(f.read().split("\t")[0])
    except (OSError, ValueError):
        return None
if sent:  # main sent the relay something: its turn is not a silent stop, and a message it owed from before is answered
    newest = max(sent + [num(sentf) or 0])  # read before "w" empties the file
    with open(sentf, "w") as f:
        f.write(str(newest))
    if os.path.exists(owedf):
        with open(owedf + ".lock", "a") as l:
            fcntl.flock(l, fcntl.LOCK_EX)  # the lock of pp_owed_clear, from the read to the removal: a newer mark stays
            if os.path.exists(owedf) and max(sent) > (num(owedf) or 0):
                os.remove(owedf)
# The sender, in brackets after the time, from the from_handle Orca sets: "main" only for the coordinator of the
# run, so no subject or body can say main sent it (the relay applies denied self-modification steps from main only).
# One record per line: the subject and body print as JSON strings (line breaks escaped, U+2028 and C1 too), the time
# and handle without spaces, so no text of a message starts a line of its own that reads as a record of this watcher.
safe = lambda s: re.sub(r"[^\w:.+-]", "_", str(s or ""))
who = lambda m: "main" if coord and m.get("from_handle") == coord else safe(m.get("from_handle"))[:14]
line = lambda m: " ".join((safe(m.get("created_at")), f"[from {who(m)}]", enc(m.get("subject")), "|", enc(m.get("body")), "\n"))
mine.sort(key=lambda m: m["sequence"])
fyi = [m for m in mine if m.get("to_handle") != me and re.match(r"\s*fyi\b", m.get("subject") or "", re.I)]
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
    sys.exit(4)
try:
    left = out.encode()
    while left:  # straight to the pipe: a buffered print reports a closed pipe only as the script ends
        left = left[os.write(1, left):]
    save(max(top, last), "")
except OSError as e:
    sys.exit(f"cos-watch-inbox: the batch was not shown or not marked shown ({e}); the next poll shows it")
sys.exit(0)
' "$ME" "$COS_KEY.inbox-seq" "$NAME" "$run" "$coord" "$1" "$PP_SCRATCH/cos-owed" "$COS_KEY.main-sent"
}
cos_wait 20 poll
