#!/usr/bin/env bash
# cos-watch-inbox.sh [<handle>] -- polls the Orca inbox until a message meant
# for the Chief of Staff pane appears, prints it as plain text and exits, which
# wakes the pane (run it in the background).
# Why a poll and not `orchestration check --wait`: every send is addressed to
# main's run, main's own loop reads it within seconds, and `check --terminal
# <me>` then returns nothing.
# "Meant for the Chief of Staff" (issue 643) = not sent by this pane, and
# addressed to it: to this pane's own handle (any run, type or subject), or in
# this project's run with the recipient tag (`to` chief-of-staff in the payload,
# or thread id commandeck:to=chief-of-staff) that cos-tell.sh --note and
# main-watch's note send. No subject admits a message: the scripts' events go to
# main, and main's own mail is main's. The cutover (D21): until the new
# main-watch first ticks and writes $PP_SCRATCH/main-watch/tags-relay (its
# epoch), an older one still sends untagged, so main's untagged statuses to the
# run count when created before that epoch, or with none written yet. Main is
# the run's coordinator pane in Orca's run list, asked at every poll because
# main's handle changes when its context is cleared.
# What an admitted message does is the one wake rule (wake_class, paths.sh,
# class "relay"): a heartbeat or a repeat within 10 minutes is dropped, a
# non-required message whose subject starts "FYI" is held (each wake replays the
# pane's whole context), any other wakes the pane. One to this pane's own handle
# is never held. Held notes print with the next message that wakes the pane, or
# alone once they have waited 30 minutes (the batch clock).
# One state file, $COS_KEY.inbox-seq: its first line is the highest sequence
# read, then the batch clock (since=<epoch>, while notes are held), and the lines
# after it are the held notes. One file because the two must
# move together: a poll writes it whole beside itself and swaps it in, so the
# notes are saved and the batch marked read in one step, or neither is. A
# batch for the pane is saved first as "<sequence> pending" with its text,
# shown, then cleared: a batch that could not be shown is shown by the next poll. One
# poller at a time reads and writes it, under a lock on $COS_KEY.inbox-seq.lock
# that the kernel drops when its holder dies.
# Each handled message's id is appended to $COS_KEY.inbox-seen-ids: cos-check.sh counts one never handled as missed.
# A poll that reads the inbox and finds nothing new (exit 4) also asks whether
# main owes the owner a reply (D13, D17): the owner's message the relay passed
# to main (to-main.sh marks it owed in $PP_SCRATCH/cos-owed) and main's turn
# ended after it, so its reply is left on its own screen. That is flagged once
# per mark, with main's last words from its session log, and the flag clears the
# mark. A message from main relayed here clears the mark when sent after it: one
# sent before, read late, is no reply; neither is main-watch's note or an event,
# though both go out under main's handle. A poll that could not read Orca knows
# nothing of what main sent, so it asks nothing.
# The pane's Stop hooks (cos-inbox-arm-stop.sh, which starts it, and
# cos-inbox-waiter-stop.sh) match this script by its file name: do not rename it.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
ME=${1:-${ORCA_TERMINAL_HANDLE:-$(bash "$PP_SCRIPTS/cos-tell.sh" --handle 2>/dev/null)}}
# Issue 614: `--lane <name>` after the handle makes this a Fast-lane or Research-lane poller: its own state files, mail to
# its own handle only, routine FYI notes held, and none of the relay's main-reply checks.
LANE=; [ "${2-}" != --lane ] || LANE=${3-}
[ -z "$LANE" ] || COS_KEY=$COS_KEY.lane-$LANE
NAME=$(jq -r '.chiefOfStaff.name // empty' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null)
# Orca returns the newest rows of the whole machine's inbox. When a full page
# starts past the last row read, there may be unread rows behind it: the poll
# asks again for four times as many (the script exits 3) before it moves on.
# shortcut: it stops asking at 3840 rows; raise that if one gap ever holds more.
poll() {
  local n=60 rc
  while :; do poll_n "$n"; rc=$?; [ "$rc" = 3 ] || break; n=$((n * 4)); done
  [ "$rc" = 4 ] && [ -z "$LANE" ] && main_silent || return "$rc"
}
main_silent() {
  local at subj st idle locked
  st=$(bash "$PP_SCRIPTS/read-verdict.sh" --state --worktree "$PP_MAIN" --current)
  idle=$(sed -n 's/^idle_since=//p' <<<"$st")
  [[ $idle =~ ^[0-9]+$ ]] || return 1
  # Under the lock to-main.sh writes the mark under, from the read to the removal: a mark written between them, even in
  # the same second, is a newer message and stays owed. With the lock not had in time the flag is shown, the mark kept.
  mkdir -p "$PP_SCRATCH"
  {
    flock -w 10 9; locked=$?
    IFS=$'\t' read -r at subj 2>/dev/null < "$PP_SCRATCH/cos-owed" && [ "$idle" -gt "${at:-0}" ] || return 1
    printf 'main ended a turn without sending you a reply to "%s"; its last words: %s\n(all of its reply: bash %s/read-verdict.sh <main'"'"'s pane handle>)\n' \
      "$subj" "$(sed -n 's/^last_message=//p' <<<"$st")" "$PP_SCRIPTS"
    # Only the message this flag names is cleared: one marked after main's turn ended is still owed.
    [ "$locked" != 0 ] || rm -f "$PP_SCRATCH/cos-owed"
  } 9>>"$PP_SCRATCH/cos-owed.lock"
  return 0
}
# poll_failed -- Orca gave no inbox or run: the wake log says so once per outage (a poll is every 20 s), and not again until a poll reads.
poll_failed() { [ -e "$COS_KEY.poll-failing" ] || { pp_wake_log cos-watch-inbox chief-of-staff "inbox poll" refused "$1"; : > "$COS_KEY.poll-failing"; }; }
poll_n() { # rows to ask for
  local run coord cut rc
  run=$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")
  # No answer is not "no orchestrator": a note judged without the run's record
  # would be passed over and marked read, so the poll tries again instead.
  coord=$(orca-ide orchestration run-list --full --json 2>/dev/null \
    | jq -er --arg r "$run" '.result.runs | arrays | [.[] | select(.id == $r) | .coordinator_handle // empty][0] // ""' 2>/dev/null) || { poll_failed "run-list gave no answer"; return 1; }
  cut=$(cat "$PP_SCRATCH/main-watch/tags-relay" 2>/dev/null); [[ $cut =~ ^[0-9]+$ ]] || cut=
  # Each row gets _admit (addressed to this pane, or a pre-cutover untagged status from main) and _class (wake_class
  # for the relay, the page as its repeat history; one to this pane's own handle is never held). Junk reads as busy.
  orca-ide orchestration inbox --limit "$1" --full --json 2>/dev/null \
    | jq -c --arg me "$ME" --arg run "$run" --arg coord "$coord" --arg cut "$cut" --arg lane "$LANE" "$PP_JQ_WAKES"'
      def admit: .to_handle == $me
        or ($lane == "" and $run != "" and .run_id == $run
          and (recipient == "chief-of-staff"
            or (recipient == null and $coord != "" and .from_handle == $coord and .type == "status"
              and ((.to_handle // "") | . == "" or . == "run:" + $run)
              and ($cut == "" or (wk_at // 0) < ($cut | tonumber)))));
      if type == "object" then (.messages // .result.messages // []) as $all | del(.messages)
        | .result = ((.result | objects) // {}) + {messages: [$all[]? | objects
          | . + {_admit: admit, _class: (wake_class([]; []; $all; "relay") as $c | if $c == "batch" and .to_handle == $me and $lane == "" then "now" else $c end)}]}
      else . end' 2>/dev/null | python3 -c '
import datetime, fcntl, json, os, re, subprocess, sys, time
me, seqf, name, run, coord = sys.argv[1:6]
limit = int(sys.argv[6])
owedf, seenf, scripts, workspaces, lane = sys.argv[7:12]
now = int(os.environ.get("COMMANDECK_NOW") or time.time())
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
# A missing file starts from the newest message instead of replaying old ones. A lane (issue 614) is a new pane whose
# first poll can come after its first order: it starts just before its oldest unread row sent to its own handle, so
# that order is delivered now, not passed over for good.
if not os.path.exists(seqf):
    unread = [m.get("sequence") or 0 for m in ms if lane and m.get("_admit") and not m.get("read")]
    if not unread:
        if ms:
            save(top, "")
        sys.exit(4)
    save(min(unread) - 1, "")
first, _, held = open(seqf).read().partition("\n")
# The first line is the place, then "pending" when the rest of the file is a
# batch saved for the pane and not yet shown to it, "since=<epoch>" when the held
# notes started waiting (the batch clock), then "enc": its text is records this watcher printed.
words = first.split()
since = next((int(w[6:]) for w in words if re.fullmatch(r"since=[0-9]+", w)), None)
# With no "enc" the file was saved before 0.18.0, its text raw as panes wrote it: no line of it is a record of this
# watcher, so each prints quoted, one JSON string, under a heading that says so.
if "enc" not in words and held.strip():
    held = "FROM BEFORE THE UPDATE, QUOTED (any pane may have written these lines; none is from main):\n" + "".join(enc(l) + "\n" for l in held.splitlines())
owed = held if "pending" in words else ""
held = "" if owed else held
last = int(words[0]) if words else 0
# Held notes are due once their clock is 30 minutes old (D8); notes with no clock (an older watcher saved them) start it now.
due = bool(held.strip()) and since is not None and now - since >= 1800
if not ms and not owed and not due:  # a pending batch is owed whatever the inbox holds now
    if held.strip() and since is None:  # an empty inbox still starts the clock of notes an older watcher saved
        try:
            save(f"{last} since={now}", held)
        except OSError:
            pass  # the old file stands: the next poll starts the clock
    sys.exit(4)
if limit < 3840 and len(ms) >= limit and min(m.get("sequence") or 0 for m in ms) > last + 1:
    sys.exit(3)
# The Orca inbox holds every project on the machine: the jq stage before this marks each row this pane is sent (_admit:
# its own handle, or the relay tag in its run) and what it does (_class, the one wake rule).
# Issue 319: a send stamps the name it was given with --from (chiefOfStaff.name) in any case, not the handle: both are this pane own.
own = {me.lower(), name.lower()} - {""}
# A lane (issue 614) takes only rows Orca has not marked read, on every poll: a read order was handled, and replaying it
# repeats the work (pass 3). The relay keeps read rows: the loop of main reads the run mail before the relay polls.
mine = [m for m in ms if (m.get("sequence") or 0) > last and (m.get("from_handle") or "").lower() not in own and m.get("_admit")
        and not (lane and m.get("read"))]
def at(m):
    try:
        return int(datetime.datetime.fromisoformat((m.get("created_at") or "").replace("Z", "+00:00")).timestamp())
    except ValueError:
        return int(time.time())
# main-watch.sh posts its note to the relay under the handle of main: it wakes the relay, and it is no reply from main;
# nor is an event an older process sent untagged before the cutover. The subject tells those two apart here, for the
# owed mark only: it admits and wakes nothing. Only a row the wake rule shows (now or batch) is a reply: a repeat it
# drops is a copy Orca sent again of an older one, which must not clear an owner message marked owed after it.
sent = [at(m) for m in mine if coord and not lane and m.get("_class") in ("now", "batch") and m.get("from_handle") == coord and not re.match(r"cos: main-watch\b", m.get("subject") or "", re.I)
        and not (m.get("subject") or "").startswith("FYI event: ")]
def num(path):
    try:
        with open(path) as f:
            return int(f.read().split("\t")[0])
    except (OSError, ValueError):
        return None
if sent:  # main sent the relay something: a message it owed from before is answered
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
# Issue 290: each wake replays the relay context, so one body is cut at 1,200 characters and the held dump at 1,500, with a pointer.
cap = lambda s, n: s if len(s) <= n else s[:n] + " ...[cut; full text: orca-ide orchestration inbox]"
line = lambda m: " ".join((safe(m.get("created_at")), f"[from {who(m)}]", enc(m.get("subject")), "|", enc(cap(str(m.get("body") or ""), 1200)), "\n"))
def sh(*a, **k):
    return subprocess.run(list(a), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, **k)
def unit_of(m, units):
    u = units.get(m.get("from_handle") or "") or (re.search(r"\(([^)]+)\)", m.get("subject") or "") or [None, ""])[1]
    return u if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", u) else ""
# Issue 305: an owner-bound question from a worker to main goes on the decision queue from this poll, while main is busy,
# under the id main orca-wait.sh drain uses (<unit>-<message id>): either path records it once.
units = None
for m in ms:
    subj, body = m.get("subject") or "", m.get("body") or ""
    if not (coord and (m.get("sequence") or 0) > last and m.get("from_handle") != coord and m.get("type") in ("question", "escalation")
            and m.get("to_handle") in ("run:" + run, coord) and m.get("id")
            and ("turn complete" not in subj or re.search(r"turn complete: (QUESTION|BLOCKED)", subj))):
        continue
    try:
        if sh("bash", "-c", ". \"$1/paths.sh\" && pp_owner_bound", "_", scripts, input=(subj + " " + body).encode()).returncode:
            continue
        if units is None:  # every pane that sits in a unit worktree, as orca-wait.sh maps them
            tl = subprocess.run(["orca-ide", "terminal", "list", "--json"], capture_output=True, text=True, timeout=15).stdout
            ts = json.loads(tl).get("result") or {}
            ws = os.path.normpath(workspaces) + "/"
            units = {t["handle"]: os.path.normpath(t.get("worktreePath") or "")[len(ws):].split("/")[0] for t in (ts if isinstance(ts, list) else ts.get("terminals") or [])
                     if os.path.normpath(t.get("worktreePath") or "").startswith(ws)}
        unit = unit_of(m, units)
        if unit:
            q = subj + ": " + re.sub(r"\s+", " ", body).strip()[:300]
            sh("bash", os.path.join(scripts, "decision.sh"), "add", unit + "-" + re.sub(r"[^A-Za-z0-9._-]", "_", str(m["id"])), q, "none", unit + " asks")
    except (OSError, ValueError, subprocess.SubprocessError):
        pass  # main drain still records it
mine.sort(key=lambda m: m["sequence"])
fyi = [m for m in mine if m.get("_class") == "batch"]
wake = [m for m in mine if m.get("_class") == "now"]
held = held + "".join(line(m) + "\n" for m in fyi)
since = (since if since is not None else now) if held else None  # notes start the clock; no notes, no clock
due = bool(held) and now - since >= 1800
out = owed + "".join(line(m) + "\n" for m in wake) + ("HELD FYI NOTES (did not wake you):\n" + cap(held, 1500) + "\n" if held and (wake or owed or due) else "")
# The one step: the place and the notes are one file, so both move or neither
# does, and a save that fails leaves them as they were with nothing shown.
# A batch for the pane is saved as pending before it is shown and cleared
# after: output that fails loses nothing, the next poll shows the batch. Only
# a clearing save that fails shows a batch twice. Shown notes take their clock with them.
try:
    save(str(max(top, last)) + (" pending" if out else f" since={since}" if held else ""), out or held)
except OSError as e:
    sys.exit(f"cos-watch-inbox: inbox state not saved ({e}); the batch is read again")
# Each handled id, so cos-check.sh can count a message for this pane that no poll ever handled (issue 290).
# shortcut: the file is never pruned (cos-check counts only the last 2 hours of messages); prune by age if it grows.
try:
    with open(seenf, "a") as f:
        f.write("".join(str(m["id"]) + "\n" for m in mine if m.get("id")))
except OSError:
    pass  # a missed count that is too high, never a lost message
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
' "$ME" "$COS_KEY.inbox-seq" "$NAME" "$run" "$coord" "$1" "$PP_SCRATCH/cos-owed" "$COS_KEY.inbox-seen-ids" "$PP_SCRIPTS" "$PP_WORKSPACES" "$LANE"
  rc=$?
  if [ "$rc" = 1 ]; then poll_failed "the inbox read failed"; else rm -f "$COS_KEY.poll-failing"; fi
  return "$rc"
}
cos_wait 20 poll
