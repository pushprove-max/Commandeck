#!/usr/bin/env bash
# cos-check.sh [<handle>] -- the relay pane's timer check (issue 290): sleeps 50 minutes, then prints one line last
# and exits, which wakes the pane (run it in the background). The line names each watcher that is down, the messages
# Orca holds for this pane from the last 2 hours that the inbox watcher never handled (cos-watch-inbox.sh appends each
# id it handled to <state>.inbox-seen-ids), the held FYI notes, kept in a file, printed above it when they fit the
# relay's 600-character read, and cleared under the inbox watcher's lock, and the minutes since the owner last typed (the rulings log). The line is appended to <state>.cos-check.log.
# COMMANDECK_COS_CHECK_SLEEP replaces the 3000-second sleep (self-tests).
# The pane's Stop hook (cos-inbox-waiter-stop.sh) requires it running, by its pid file: do not rename it.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
ME=${1:-${ORCA_TERMINAL_HANDLE:-}}
echo $$ > "$COS_KEY.cos-check.pid"
sleep "${COMMANDECK_COS_CHECK_SLEEP:-3000}"
DOWN=
for n in cos-watch-inbox cos-watch-decisions cos-watch-alerts cos-watch-limit; do
  # Up only while the recorded pid still runs that watcher, as the Stop hook decides it.
  read -r run arg _ <<<"$(ps -o command= -p "$(cat "$COS_KEY.$n.pid" 2>/dev/null || echo 0)" 2>/dev/null)"
  case ${run##*/} in bash|sh|zsh) run=$arg ;; esac
  [[ ${run:-} == */$n.sh ]] || DOWN+=" ${n#cos-watch-}"
done
MISSED=$(orca-ide orchestration inbox --limit 200 --json 2>/dev/null | jq -r --arg me "$ME" --argjson since "$(( $(date +%s) - 7200 ))" \
  --rawfile seen <(cat "$COS_KEY.inbox-seen-ids" 2>/dev/null) '($seen | split("\n")) as $s
  | [(.messages // .result.messages // [])[] | select($me != "" and .to_handle == $me and .from_handle != $me
      and ((.created_at // "") | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch 0)) >= $since and (.id as $i | $s | index([$i]) | not))] | length' 2>/dev/null) \
  || MISSED="unknown (Orca did not answer)"
# Held notes are the inbox state's lines after its place line, unless that line says "pending": then they are a
# batch the inbox watcher owes the pane, and stay its own. They go to their own file before the state is cleared,
# and print whole only when they and the line fit the 600 characters the relay reads, as a watcher's wake does.
# Named for the second and the pid: two checks in one second shared a file, and the second emptied and deleted it.
# shortcut: the notes files are never pruned; prune by age if the folder grows.
ARCH=$COS_KEY.cos-check-notes-$(date +%s)-$$.txt
NOTES=$({ flock -w 10 9 || exit 0; f=$COS_KEY.inbox-seq; [ -f "$f" ] && IFS= read -r first < "$f" || exit 0
  case " $first " in (*" pending "*) exit 0 ;; esac
  tail -n +2 "$f" > "$ARCH" && printf '%s\n' "$first" > "$f.new" && mv "$f.new" "$f"; cat "$ARCH"; } 9>>"$COS_KEY.inbox-seq.lock")
[ -n "$NOTES" ] || rm -f "$ARCH"
# Every pane logs its prompts there, workers' too (main-watch's Signal WARM to a Builder): the owner types only in
# main and in the Chief-of-Staff, Fast-lane and Research-lane worktrees, so only rows whose cwd is exactly one of those count. Workers'
# checkouts can sit anywhere around main (inside it, beside it, under a workspaces set there), so no prefix test:
# both sides go through pnorm, as the resolver keeps inner // and /./ in main and workspaces.
QUIET=$(tail -n 500 "${COMMANDECK_RULING_LOG:-$HOME/.claude/rulings/$PP_PROJECT.jsonl}" 2>/dev/null \
  | jq -nRr --arg main "$PP_MAIN" --arg mainp "$PP_MAIN_P" --arg ws "$PP_WORKSPACES" "$PP_PNORM"'[($main | pnorm), ($mainp | pnorm)] as $own | ($ws | pnorm) as $w
      | [inputs | fromjson? | select(.void != true) | select(.cwd // "" | pnorm | IN($own[]) or (startswith($w + "/") and (.[($w | length) + 1:] | test("^(Chief-of-Staff|Fast-lane|Research-lane)$")))) | .utc // empty]
    | last | if . then "\((now - fromdateiso8601) / 60 | floor) min" else "unknown" end' 2>/dev/null)
DOWN=${DOWN:- none}
LINE="cos-check: watchers down: ${DOWN# } | missed messages: $MISSED | held FYI notes: $(grep -c '^[0-9]' <<<"$NOTES") (above, now cleared) | owner quiet ${QUIET:-unknown}"
if [ -n "$NOTES" ] && [ $(( ${#NOTES} + ${#LINE} )) -lt 600 ]; then printf '%s\n' "$NOTES"
elif [ -n "$NOTES" ]; then LINE=${LINE/(above, now cleared)/(too long to print; whole text: $ARCH)}; fi
# Issue 319: a clean check has nothing for the owner; the wake says so, and the relay ends its turn without text.
[ "$DOWN" = " none" ] && [ "$MISSED" = 0 ] && [ -z "$NOTES" ] && LINE="cos-check: nothing for the owner: end silently; re-arm"
printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LINE" >> "$COS_KEY.cos-check.log"
echo "$LINE"
