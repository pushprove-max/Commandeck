#!/usr/bin/env bash
# cos-supervise.sh [<handle>] -- the one background command that runs the relay's watchers (issue 655): cos-watch-decisions,
# -alerts, -limit, -units and the inbox poller cos-watch-inbox <handle> (issue 584), each in its own loop and process group.
# A find (a watcher's wake file, cos-lib.sh cos_wait) is classed by the one wake rule (wake_class, paths.sh, for the
# relay): `now` is typed into the pane <handle> (default $ORCA_TERMINAL_HANDLE) and counts only when the receipt holds
# turn_started, or is accepted into a busy pane's queue (never typed again); `batch` joins the held FYI notes in <state>.inbox-seq; `drop` is logged. Each wake file is acked by name
# in <state>.supervise.acked after its own delivery, and the supervisor keeps running. A send refused, or with a receipt of
# another shape, three tries 20 s apart (COMMANDECK_SUPERVISE_RETRY replaces the 20, self-tests) prints the line and exits; the next start
# publishes, oldest first, every unacked non-empty wake file whose writer is dead (the first start ever acks all old
# ones instead, except the find of a hand-armed watcher it stopped, which it publishes). A find in a watcher's wake file is delivered whatever its exit status; a watcher that exits non-zero, or with no find, is dead: it is started again and one line goes to
# <state>.supervise.log; three deaths of one within 10 minutes print `cos-supervise: <watcher> died 3 times in 10 min;
# log <file>` and exit. One supervisor runs per project: a second start prints `already running (pid <p>)` and exits 0.
# Every exit path stops the children. Its pid is in <state>.cos-supervise.pid (cos-check.sh and the Stop hook read it).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
ME=${1:-${ORCA_TERMINAL_HANDLE:-}}
WATCHERS=(cos-watch-decisions cos-watch-alerts cos-watch-limit cos-watch-units cos-watch-inbox)
LOG=$COS_KEY.supervise.log ACKED=$COS_KEY.supervise.acked
exec 9>>"$COS_KEY.cos-supervise.lock"
if ! flock -n 9; then echo "cos-supervise: already running (pid $(cat "$COS_KEY.cos-supervise.pid" 2>/dev/null))"; exit 0; fi
echo $$ > "$COS_KEY.cos-supervise.pid"
# A watcher armed by hand before this start would run twice: stop it first. STOPPED names each one stopped; the drain
# waits up to 2 s for them to end, so a find one wrote before the stop is read whole and with its writer dead.
STOPPED=" "
for w in "${WATCHERS[@]}"; do
  p=$(cat "$COS_KEY.$w.pid" 2>/dev/null) || continue
  case $(ps -o command= -p "$p" 2>/dev/null) in *"/$w.sh"*) kill "$p" 2>/dev/null && STOPPED+="$p " ;; esac
done
for ((i = 0; i < 20; i++)); do
  for p in $STOPPED; do kill -0 "$p" 2>/dev/null && { sleep 0.1; continue 2; }; done
  break
done
PGS=()
stop() {
  # The exit line printed before this is the one line the relay reads last, so bash's notice of a watcher it kills
  # ("Killed ...") must not follow it; each watcher gets 2 s after TERM before KILL.
  trap - EXIT; exec 2>/dev/null; local g i
  for g in "${PGS[@]}"; do kill -TERM -- "-$g" 2>/dev/null; done
  for ((i = 0; i < 20; i++)); do
    for g in "${PGS[@]}"; do kill -0 -- "-$g" 2>/dev/null && { sleep 0.1; continue 2; }; done
    break
  done
  for g in "${PGS[@]}"; do kill -KILL -- "-$g" 2>/dev/null; done
  for w in "${WATCHERS[@]}"; do rm -f "$COS_KEY.$w.pid"; done
  rm -f "$COS_KEY.cos-supervise.pid"
}
trap stop EXIT; trap 'exit 143' INT TERM
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }
# text <wake file>: what the watcher printed for it (cos_wait): whole up to 600 bytes, else one line naming the file.
text() {
  local w=${1#"$COS_KEY."}; w=${w%%-wake-*}
  if [ "$(wc -c < "$1")" -le 600 ]; then cat "$1"
  else echo "$w woke: $(grep -c . "$1") records, $(wc -c < "$1" | tr -d ' ') bytes; whole text: $1"; fi
}
# klass <wake file>: now, batch or drop, by wake_class for the relay on a message built from the watcher and its text.
# The poller already applied wake_class to its own messages, so what it prints is now. An alert wakes only when crit.
klass() {
  local w=${1#"$COS_KEY."} m; w=${w%%-wake-*}
  case $w in
    cos-watch-inbox) echo now; return ;;
    cos-watch-decisions) m='{"type":"question"}' ;;
    cos-watch-alerts) m='{"type":"status","subject":"FYI alert"}'; ! grep -q '"severity": *"crit"' "$1" || m='{"type":"escalation"}' ;;
    *) m='{"type":"escalation"}' ;;
  esac
  jq -r "$PP_JQ_WAKES"' wake_class([]; []; []; "relay")' <<<"$m"
}
# deliver <wake file>: publish it by its class, then ack it by name; status 1 after a third unproven send (line printed).
deliver() {
  local f=$1 w line c try r
  w=${f#"$COS_KEY."}; w=${w%%-wake-*}; line=$(text "$f"); c=$(klass "$f")
  # With no inbox state yet the poller has not seeded it: a held note there could replay the inbox, so it wakes instead.
  [ "$c" != batch ] || [ -f "$COS_KEY.inbox-seq" ] || c=now
  case $c in
    now)
      # The receipt, by the only shapes read: stages holding turn_started (a turn started), or ok with accepted true (the
      # text sits in a busy pane's queue, which submits it when its turn ends: typing it again repeats the wake, pass 4).
      # Anything else, accepted false (nothing typed) or a receipt of another shape, is not delivered and is retried,
      # its receipt named in the log.
      for try in 1 2 3; do
        r=$(orca-ide terminal send --terminal "$ME" --text "$line" --enter --wait-submit 10 --json 2>/dev/null)
        jq -e '[.. | objects | .stages? // empty | .[]?] | index("turn_started") != null' <<<"$r" >/dev/null 2>&1 && break
        if jq -e '.ok == true and .result.accepted == true' <<<"$r" >/dev/null 2>&1; then
          log "send of ${f##*/} queued in the busy pane (accepted, no turn yet)"; break
        fi
        log "send of ${f##*/} not proven (try $try): $(printf '%s' "$r" | tr -s '\n' ' ' | cut -c1-200)"
        [ "$try" != 3 ] || { printf '%s\n' "$line"; return 1; }
        sleep "${COMMANDECK_SUPERVISE_RETRY:-20}"
      done ;;
    # A held note is one record line, as cos-watch-inbox.sh writes them: cos-check.sh counts lines that start with a digit.
    batch) { flock -w 10 7; printf '%s [from %s] "FYI alert" | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$w" \
        "$(jq -Rsc 'rtrimstr("\n")' <<<"$line")" >> "$COS_KEY.inbox-seq"; } 7>>"$COS_KEY.inbox-seq.lock" ;;
    *) log "dropped ${f##*/}" ;;
  esac
  echo "${f##*/}" >> "$ACKED"
}
# Drain, oldest first: a later start publishes every wake file left unacked by an earlier exit. The first start ever
# (no ledger) acks every old wake file, whose writer woke the pane by its own exit, except the find of a watcher it
# stopped above: that writer was killed before its exit could wake anyone, so it is published (pass 14).
shopt -s nullglob
FIRST=; [ -e "$ACKED" ] || FIRST=1
: >> "$ACKED"
while IFS= read -r f; do
  case ${f#"$COS_KEY."} in lane-*) continue ;; esac  # a lane poller's, not the relay's
  p=${f%.txt}; p=${p##*-}
  if [ -n "$FIRST" ] && [[ $STOPPED != *" $p "* ]]; then echo "${f##*/}" >> "$ACKED"; continue; fi
  [ -s "$f" ] && ! grep -qxF "${f##*/}" "$ACKED" || continue
  ! kill -0 "$p" 2>/dev/null || continue
  deliver "$f" || exit 0
done < <(ls -tr "$COS_KEY".*-wake-*.txt 2>/dev/null)
# run <watcher> [<arg>]: deliver each find and start it again; start it again when it dies; return on an unproven
# send or on the third death in 10 minutes.
run() {
  local w=$1 c rc f now deaths=()
  while :; do
    # Through bash, whatever the file's mode: cos-watch-units.sh ships as 644, and run directly it exits 126.
    bash "$PP_SCRIPTS/$w.sh" ${2:+"$2"} >/dev/null 2>&1 & c=$!
    wait "$c"; rc=$?
    f=$(ls "$COS_KEY.$w-wake-"*"-$c.txt" 2>/dev/null | tail -1)
    # A find is delivered whatever the watcher's exit: one that died after printing it and setting its mark leaves the
    # find only in this file (pass 5). One delivery at a time: two typed lines must not interleave in the pane.
    if [ -s "$f" ]; then
      { flock 8; deliver "$f"; } 8>>"$ACKED" || return 0
      [ "$rc" != 0 ] || continue
    fi
    now=$(date +%s); deaths=("${deaths[@]}" "$now")
    while [ $((now - deaths[0])) -ge 600 ]; do deaths=("${deaths[@]:1}"); done
    log "$w died (status $rc); restarted"
    if [ "${#deaths[@]}" -ge 3 ]; then echo "cos-supervise: $w died 3 times in 10 min; log $LOG"; return 0; fi
  done
}
set -m
for w in "${WATCHERS[@]}"; do
  a=; [ "$w" != cos-watch-inbox ] || a=$ME
  run "$w" "$a" & PGS+=($!)
done
set +m
wait -n
