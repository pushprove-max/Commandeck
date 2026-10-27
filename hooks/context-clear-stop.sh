#!/usr/bin/env bash
# Stop hook (main session only): past the clear line, main does not idle with
# a bloated context. The owner, 2026-09-12: "the hook did not clear the session" --
# the UserPromptSubmit line only nags, and a /clear typed INTO a running turn
# arrives as text, not as a command. A Stop hook runs when the turn has ended
# and the pane is idle, which is the one moment a queued /clear executes.
#
# Past the line: with a checkpoint written in the last 30 minutes it restarts
# main in a fresh pane with the resume prompt and lets the stop through;
# without one it blocks the stop once, so main writes the checkpoint first
# (stop_hook_active guards the loop: a second stop in the same chain passes).
# Worker panes (linked worktrees) and reviewer panes are exempt.
input=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$input"
# Every run leaves one line, so a stop that clears nothing can be explained.
echo "$(date +%FT%T) stop-hook: pid=$$ ppid=$PPID cwd=$PWD handle=${ORCA_TERMINAL_HANDLE:-unset} $(printf '%s' "$input" | jq -c '{session_id,stop_hook_active,transcript_path}' 2>/dev/null)" >> "$HOME/.claude/checkpoints/clear-hook.log"
[ "${COMMANDECK_REVIEWER:-}" = "1" ] && exit 0
if [ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then exit 0; fi
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "$sid" ] || exit 0
LINE=$(pp_clear_line 2>/dev/null) || LINE=
LINE=${LINE:-${COMMANDECK_CLEAR_LINE:-200000}}   # the helper did not load
# shellcheck source=lib/context-size.sh
. "$(dirname "$0")/lib/context-size.sh"
ctx=$(context_size "$transcript") || ctx=0
# /handoff (skills/handoff) leaves this marker to restart below the line.
handoff="$HOME/.claude/checkpoints/$sid.handoff"
[ "${ctx:-0}" -gt "$LINE" ] 2>/dev/null || [ -f "$handoff" ] || exit 0
cp="$HOME/.claude/checkpoints/$sid.md"
fresh=0
[ -f "$cp" ] && [ "$(( $(date +%s) - $(stat -c %Y "$cp") ))" -lt 1800 ] && fresh=1
# Issue 283: the checkpoint's size against the 10,240-byte resume budget. Issue 300: minutes since this project's last
# restart, from the newest resumed-from record of a session whose transcript sits beside this one.
cp_bytes=$(wc -c < "$cp" 2>/dev/null | tr -d ' '); cp_bytes=${cp_bytes:-0}
since=$(for f in "$HOME"/.claude/checkpoints/*.resumed-from; do s=${f##*/}; [ -e "${transcript%/*}/${s%.resumed-from}.jsonl" ] && stat -c %Y "$f"; done 2>/dev/null | sort -n | tail -1)
since=${since:+$(( ($(date +%s) - since) / 60 ))}
echo "$(date +%FT%T) stop-hook: ctx=$ctx line=$LINE fresh=$fresh cp=$cp cp_bytes=$cp_bytes$([ "$cp_bytes" -gt 10240 ] && echo ' over=1') since_restart_min=${since:--} orca=$(command -v orca-ide || echo missing)" >> "$HOME/.claude/checkpoints/clear-hook.log"
# One restart per checkpoint write: the marker holds the checksum of the
# checkpoint it restarted for, so a second write of the same path restarts again
#. Content, not mtime: two writes in one second share an mtime. A pinned
# tab refuses the close, the old main keeps stopping, and without this every
# stop opened another main (two appeared on 2026-09-12 within two minutes).
if [ "$fresh" = 1 ] && [ -f "$cp.restarted" ] && [ "$(cksum < "$cp")" = "$(cat "$cp.restarted")" ]; then
  echo "$(date +%FT%T) stop-hook: already restarted for $cp; this pane must be closed by hand (unpin the tab)" >> "$HOME/.claude/checkpoints/clear-hook.log"
  HOOK_FIRE_ADVISE=1
  echo "context-clear: main was already restarted for this checkpoint; close this pane by hand (its tab is pinned)" >&2
  exit 0
fi
# #409: the automatic first-crossing snapshot is a skeleton, and only the flagged state-snapshot.sh call fills it. A
# checkpoint still holding a Goal placeholder (the generator's "TODO one line:" or the hand template's "<one line:") or
# a unit's TODO cell is no restart point, whether or not it resumed from another. The other sections' TODO prompts
# are main's notes, not restart fields. The first stop blocks once, naming the fields and the call; the second logs
# and leaves main where it is.
if [ "$fresh" = 1 ]; then
  unfilled=""
  grep -qE '^(TODO one line:|<one line:)' "$cp" && unfilled="Goal"
  grep -qE '^\| .*\| TODO \|' "$cp" && unfilled+="${unfilled:+ and }unit stage/next cells"
  if [ -n "$unfilled" ]; then
    echo "$(date +%FT%T) stop-hook: $cp still has unfilled fields ($unfilled); main is not restarted" >> "$HOME/.claude/checkpoints/clear-hook.log"
    if [ "$active" != true ]; then
      HOOK_FIRE_BLOCK=1
      snap="$(cd "$(dirname "$0")/../scripts" && pwd)/state-snapshot.sh"
      jq -n --arg r "CHECKPOINT NOT READY: ${cp/#$HOME/\~} has unfilled $unfilled. Fill them in one call: bash ${snap/#$HOME/\~} --out ${cp/#$HOME/\~} --goal '<one line>' --stage <unit>=<text> --next <unit>=<text>; then end the turn." '{decision:"block", reason:$r}'
      exit 0
    fi
    HOOK_FIRE_ADVISE=1
    echo "context-clear: $cp still has unfilled fields; main is not restarted" >&2
    exit 0
  fi
fi
# A resumed main keeps, or closes with a reason, every open item of the
# checkpoint it resumed from: a restart that drops one loses that work
# for good. Checked before anything is published or launched. Issue 252: the
# first stop blocks once, naming the count and the command that lists them (the
# whole list on every block stranded main); the second stop of the chain copies
# what is still missing into the checkpoint and restarts. An unreadable file of
# the chain is a missing item of its own; an unreadable base or new checkpoint
# (exit 2) is one item naming it, blocked and copied as the others are.
anc="$HOME/.claude/checkpoints/$sid.resumed-from"
CC="$(cd "$(dirname "$0")/../scripts" && pwd)/checkpoint-context.py"
if [ "$fresh" = 1 ] && [ -e "$anc" ]; then
  base=$(head -1 "$anc" 2>/dev/null)
  miss=$(python3 "$CC" carry "$base" "$cp" 2>&1); rc=$?
  if [ "$rc" = 2 ]; then
    echo "$(date +%FT%T) stop-hook: carry-over check could not read the chain of $cp against ${base:-<empty $anc>}: $(head -1 <<<"$miss")" >> "$HOME/.claude/checkpoints/clear-hook.log"
    miss="- carry chain: $(head -1 <<<"$miss")"
  fi
  n=$(grep -c '^- ' <<<"$miss")
  if [ "$rc" != 0 ] && [ "$active" != true ]; then
    echo "$(date +%FT%T) stop-hook: carry-over check failed for $cp against ${base:-<empty $anc>}: $n items" >> "$HOME/.claude/checkpoints/clear-hook.log"
    HOOK_FIRE_BLOCK=1
    first=$(grep -m1 '^- ' <<<"$miss"); first=${first#- }
    head="CARRY-OVER: $n inherited open item$([ "$n" = 1 ] || echo s): "
    tail=". List: python3 ${CC/#$HOME/\~} carry ${base/#$HOME/\~} ${cp/#$HOME/\~}. Restate or close each (Closed: one line per item, its own reason); then end the turn."
    # The first item gets what is left under 400 bytes, at most 150 and at least 20 (a long install path takes the rest).
    room=$((398 - ${#head} - ${#tail})); [ "$room" -le 150 ] || room=150; [ "$room" -ge 20 ] || room=20
    jq -n --arg r "$head${first:0:room}$tail" '{decision:"block", reason:$r}'
    exit 0
  elif [ "$rc" != 0 ]; then
    # Issue 281: under the one unresolved Queue heading, which a later restart reuses; awk reads the list from a file.
    head='## Queue (left unresolved at the restart: restate or close each, one line per item, with its own reason)'
    if grep '^- ' <<<"$miss" > "$cp.carry.$$" && awk -v list="$cp.carry.$$" -v head="$head" '
        function dump(l) { while ((getline l < list) > 0) print l; done = 1 }
        on && /^## / { dump(); on = 0 }
        { print }
        $0 == head { on = 1 }
        END { if (on) dump(); else if (!done) { print ""; print head; dump() } }' "$cp" > "$cp.new.$$" && mv "$cp.new.$$" "$cp"; then
      echo "$(date +%FT%T) stop-hook: $n items carried automatically into the checkpoint $cp" >> "$HOME/.claude/checkpoints/clear-hook.log"
      # Issue 283: the stop line's cp_bytes was measured before the carry; this one is the size the restart takes.
      echo "$(date +%FT%T) stop-hook: cp=$cp cp_bytes=$(wc -c < "$cp" | tr -d ' ') after carry" >> "$HOME/.claude/checkpoints/clear-hook.log"
      rm -f "$cp.carry.$$"
    else
      rm -f "$cp.carry.$$" "$cp.new.$$"
      echo "$(date +%FT%T) stop-hook: could not copy $n missing items into $cp; main is not restarted" >> "$HOME/.claude/checkpoints/clear-hook.log"
      echo "context-clear: could not copy $n missing items into $cp; main is not restarted" >&2
      exit 0
    fi
  fi
fi
# Issue 283: what the ten-generation carry walk cuts is written beside the checkpoint before the restart, and the
# resume names that file instead of loading it. Not listed or not written, main is not restarted: the items would be lost.
if [ "$fresh" = 1 ]; then
  if ! aged=$(python3 "$CC" aged "$cp"); then
    echo "$(date +%FT%T) stop-hook: could not list the items $cp carries past ten generations; main is not restarted" >> "$HOME/.claude/checkpoints/clear-hook.log"
    echo "context-clear: could not list the items $cp carries past ten generations; main is not restarted" >&2
    exit 0
  fi
  if [ -n "$aged" ] && ! printf '%s\n' "$aged" > "$cp.aged-out.md"; then
    echo "$(date +%FT%T) stop-hook: could not write $cp.aged-out.md; main is not restarted" >> "$HOME/.claude/checkpoints/clear-hook.log"
    echo "context-clear: could not write $cp.aged-out.md; main is not restarted" >&2
    exit 0
  fi
fi
# In-harness background agents live in this pane and die with it: hold
# the restart while any async launch has no task-notification yet, and let the
# stop pass so their notifications wake main. Past the ceiling (under the
# auto-compact point, lib/project.sh) a hung agent cannot hold main any longer: restart and name it.
CEILING=$(pp_clear_ceiling 2>/dev/null) || CEILING=
CEILING=${CEILING:-${COMMANDECK_CLEAR_CEILING:-480000}}   # the helper did not load
# A launch is this pane's own only when it is the result of a tool call that
# is not a shell command and its text opens with the launch line: main prints
# Builders' session logs, and a launch quoted there is another pane's agent,
# whose notification never arrives here.
running=$(comm -23 \
  <(grep -F 'Async agent launched' "$transcript" | jq -Rr 'fromjson? | select(.type == "user" and ((.toolUseResult | type) != "object" or (.toolUseResult | has("stdout") | not)))
      | .message.content | arrays | .[] | select(.type == "tool_result") | .content
      | if type == "array" then (.[] | select(.type == "text") | .text) elif type == "string" then . else empty end
      | select(startswith("Async agent launched")) | (capture("agentId: (?<id>[0-9a-f]+)") | .id)' 2>/dev/null | sort -u) \
  <(grep -F '<task-notification>' "$transcript" | grep -F '<status>' | grep -o '<task-id>[0-9a-f][0-9a-f]*</task-id>' | sed 's/<[^>]*>//g' | sort -u) | tr '\n' ' ')
if [ "$fresh" = 1 ] && [ -n "$running" ]; then
  if [ "${ctx:-0}" -le "$CEILING" ] 2>/dev/null; then
    echo "$(date +%FT%T) stop-hook: held: $(wc -w <<< "$running" | tr -d ' ') background agents running ($running)" >> "$HOME/.claude/checkpoints/clear-hook.log"
    exit 0
  fi
  echo "$(date +%FT%T) stop-hook: ceiling $CEILING passed at ctx=$ctx; restart kills background agents: $running" >> "$HOME/.claude/checkpoints/clear-hook.log"
fi
if [ "$fresh" = 1 ] && [ -n "${ORCA_TERMINAL_HANDLE:-}" ] && command -v orca-ide >/dev/null 2>&1; then
  # One restart in flight per pane: the helper needs 12 s or more, and a
  # second stop inside that window, with the checkpoint edited since the first,
  # is past the checksum marker above and opened a second main. The lock is taken
  # here, before anything is published or launched, and freed when the helper
  # ends, whatever its outcome: a failed restart retries on the next stop, and a
  # new checkpoint written after a finished one restarts again.
  # shortcut: a lock older than 10 minutes belongs to a helper that was killed (it runs for under five) and is taken over.
  inflight="$HOME/.claude/checkpoints/restart-inflight.$(printf '%s' "$ORCA_TERMINAL_HANDLE" | tr -c 'A-Za-z0-9' '-')"
  [ -d "$inflight" ] && [ "$(( $(date +%s) - $(stat -c %Y "$inflight") ))" -gt 600 ] && rmdir "$inflight" 2>/dev/null
  if ! mkdir "$inflight" 2>/dev/null; then
    echo "$(date +%FT%T) stop-hook: a restart of this pane is already in flight ($inflight); this stop launches nothing" >> "$HOME/.claude/checkpoints/clear-hook.log"
    exit 0
  fi
  # The helper consumes $handoff only once the new pane takes the prompt: below
  # the line it is the only trigger, and a failed create must retry. The helper
  # itself writes $cp.restarted once it runs, so a launch that never starts
  # leaves no marker and the next stop retries.
  # resume-context.sh (SessionStart, main only) consumes this once and injects
  # the checkpoint, board.sh and the run binding: typed, they fail past ~9 KB.
  # The marker is named for this checkout: ~/.claude/checkpoints is shared by
  # every project on the machine, and another project's main must not take it.
  # Its second line is a one-time token the replacement is started with: any
  # other main session that starts in this checkout first leaves it alone.
  token=$$-$(date +%s)-$RANDOM
  printf '%s\n%s\n' "$cp" "$token" > "$HOME/.claude/checkpoints/resume-pending.$(printf '%s' "$(git rev-parse --show-toplevel 2>/dev/null)" | tr -c 'A-Za-z0-9' '-')"
  # Keystrokes sent to main's own pane never reach its input box (proved with a
  # probe on 2026-09-12: the same send lands in any other Claude pane), so a
  # typed /clear cannot work at any moment. owner ruling 2026-09-12: "you can do
  # it as a restart". A detached helper opens a fresh pane in the main checkout
  # running the same command, types the resume prompt there once its TUI is
  # idle, and only then closes this pane. A failed create leaves this pane up.
  # A session adopted from Claude Code's background spare runs as the internal
  # `claude bg-spare --bg-spare <sock>`, which the CLI rejects when replayed.
  # A main started with --resume/--continue (as after a crash) must not pass
  # them on: the "fresh" pane would reopen this same over-the-line session.
  cmd=$(printf '%s\n' "${COMMANDECK_PARENT_ARGS:-$(ps -o args= -p "$PPID" 2>/dev/null)}" | sed -E 's#^[^ ]*/claude( |$)#claude\1#' | grep '^claude' | grep -v -- '--bg-spare' \
    | sed -E ':a; s/ (--resume|-r|--session-id)(=[^ ]*| +[^- ][^ ]*)?( |$)/\3/; ta; :b; s/ (--continue|-c|--fork-session)( |$)/\2/; tb')
  # ps returns the arguments as one flat line, their quoting lost, and the
  # helper types the line into a shell: only plain flag text is replayed. A
  # command that cannot be rebuilt restarts as bare `claude`, permission checks on.
  # shortcut: braces and quotes (a --settings JSON value) fall back to plain claude, widen when a main runs with such a flag.
  [[ $cmd =~ ^[]A-Za-z0-9\ _./:=,@%+[-]+$ ]] || {
    echo "$(date +%FT%T) stop-hook: the parent command could not be replayed safely; restarting as plain claude" >> "$HOME/.claude/checkpoints/clear-hook.log"
    cmd=claude
  }
  log="$HOME/.claude/checkpoints/clear-hook.log"
  # macOS has no setsid; perl's POSIX::setsid detaches the same way there.
  if command -v setsid >/dev/null 2>&1; then detach=(setsid); else detach=(perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec $ARGV[0]: $!\n"'); fi
  # The lock goes when the helper does, so one that never starts holds nothing.
  "${detach[@]}" bash -c 'bash "$@"; rc=$?; rmdir "$0"; exit $rc' "$inflight" "${COMMANDECK_RESTART_HELPER:-$(dirname "$0")/lib/context-clear-restart.sh}" \
    "$ORCA_TERMINAL_HANDLE" "$cp" "COMMANDECK_RESUME_TOKEN=$token $cmd" "$log" </dev/null >/dev/null 2>>"$log" &
  disown
  HOOK_FIRE_ADVISE=1
  echo "context-clear: $((ctx / 1000))K over the $((LINE / 1000))K line, checkpoint fresh: main restarts in a fresh pane (log $log)" >&2
  exit 0
fi
[ "$fresh" = 1 ] && { HOOK_FIRE_ADVISE=1; echo "context-clear: checkpoint fresh but no ORCA_TERMINAL_HANDLE; type /clear by hand" >&2; exit 0; }
[ "$active" = "true" ] && exit 0
HOOK_FIRE_BLOCK=1
# The template's headings ride in the reason: reading the 4.5 KB template
# first cost 3.5 turns a block. Builtins only, read from the template itself.
heads=""
while IFS= read -r l; do [[ $l == '## '* ]] && heads+="${heads:+; }$l"; done < "$(dirname "$0")/../templates/checkpoint.md"
jq -n --arg r "CONTEXT $((ctx / 1000))K is over the $((LINE / 1000))K line (or /handoff was run) and no checkpoint under 30 minutes old exists at $cp. Write it now with these headings, in order: ${heads:-see $(cd "$(dirname "$0")/../templates" && pwd)/checkpoint.md} Queue items start Q-<n> (the next free number, never reused). -- do not Read the template; one Write, then end the turn: this hook restarts main in a fresh pane with the resume prompt itself." '{decision:"block", reason:$r}'
