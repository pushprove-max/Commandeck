#!/usr/bin/env bash
# PreToolUse hook (Bash): the main session waits on Orca, never on a sleep
# loop. owner ruling 2026-09-07: "waiting 10 minutes before checks can waste
# hours over long stretches". The main-session rules, Waiting:
# `orca-ide orchestration check --wait`; never poll in a loop.
#
# Blocked: a shell loop whose body sleeps (`for ...; do sleep`, `while ...;
# do sleep`, `until ...; do sleep`) and a bare `sleep N` chained with a
# check (`sleep 30; gh pr view`), when nothing in the command hands the
# wait to Orca. Allowed: `orca-ide orchestration check --wait`, and a loop
# that ENDS by sending an Orca message (a watcher that turns a file or
# process event into a message the main session can block on).
#
# Worker panes are exempt from all but two rules: they run in linked git
# worktrees and have no Orca run to block on when they wait for their own test
# runs. In every pane a bare `orca(-ide) orchestration check` is blocked: it
# returns a batch and never acknowledges it, so the batch replays on every
# check and later messages queue behind it. A worker's sleep loop is let
# through with a nudge toward run_in_background and wait-test-run.sh.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ -z "$CMD" ] && exit 0
WORKER=0
[ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] || WORKER=1

# A HEREDOC BODY IS DATA BEING WRITTEN, NOT A COMMAND BEING RUN.
# `cat >> report.md <<'EOF' ... bash scripts/orca-wait.sh ... EOF`
# documents the wait; it does not wait. Matching the literal text blocked the
# append that wrote the 2026-09-20 workflow report itself. Every check below
# reads CMD_CODE, the command with heredoc bodies dropped -- the one definition,
# which loop_wait's parse also takes. Only paid when the command has a `<<`.
CMD_CODE=$CMD
case "$CMD" in *'<<'*)
  CMD_CODE=$(CMD=$CMD python3 - <<'PY'
import os, re
# The delimiter is one whole shell word, its quoted and unquoted parts joined
# with the quotes removed: <<'END'-NOTES closes on END-NOTES. A here-string
# (<<<) has no body, so it is excluded.
HEREDOC = r"(?<!<)<<(-?)[ \t]*((?:'[^']*'|\"[^\"]*\"|[^\s;&|<>()'\"]+)+)"
lines, kept, i = os.environ["CMD"].split("\n"), [], 0
while i < len(lines):
    kept.append(lines[i])
    i += 1
    for m in re.finditer(HEREDOC, kept[-1]):
        word = "".join(q1 or q2 or bare.replace("\\", "") for q1, q2, bare
                       in re.findall(r"'([^']*)'|\"([^\"]*)\"|([^'\"]+)", m.group(2)))
        while i < len(lines) and (lines[i].lstrip("\t") if m.group(1) else lines[i]) != word:
            i += 1
        i += 1
    # The body is gone, so the operator must not announce one: strip_quoted
    # would take the code that follows as the body. A here-string has none.
    kept[-1] = re.sub(HEREDOC, lambda m: "<<<" + m.group(2), kept[-1])
print("\n".join(kept))
PY
  ) || CMD_CODE=$CMD ;;
esac

# Quoted spans and comments are data (a brief that quotes a loop, a grep for
# one, an issue body): bash runs neither. One pass over the whole command:
# the line-by-line seds left a multi-line quoted body whole. The walk costs
# about a second per 10 KB, so a command that names nothing screened below
# skips it; quote characters are dropped for that test, so `sl''eep` cannot
# slip past.
P=${CMD_CODE//[\'\"\\]/}
case "$P" in *sleep*|*orca-wait*|*orchestration*) ;; *) [ "$TOOL" = "Monitor" ] && [ "$WORKER" = 0 ] || exit 0 ;; esac
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
if type strip_quoted >/dev/null 2>&1; then
  BARE=$(strip_quoted "$CMD_CODE")
  # The same text with each quoted span kept as the word it is, for loop_wait.
  Q=$'\x01'
  # The word parser below is never handed what a quoted span holds, unless the
  # span is plain word characters (a quoted script path): a quote or a backslash
  # in it unbalanced the parser, which then read no loop at all. Any other
  # span is the one word QUOTED.
  WORDS=$(strip_quoted "$CMD_CODE" "$Q" | sed -E "s/${Q}([A-Za-z0-9_.\/:=@%+,-]+)([;&|()[:space:]]|\$)/\1\2/g; s/${Q}[^;&|()[:space:]]*/QUOTED/g")
else
  BARE=$(printf '%s' "$CMD_CODE" | sed -e "s:'[^']*'::g" -e 's:"[^"]*"::g' | sed -E 's/(^|[[:space:];&|(])#.*$/\1/')
  WORDS=$CMD_CODE
fi

# Each command of BARE, its leading assignments and wrappers dropped.
segments() {
  printf '%s\n' "$BARE" | sed -E 's/(&&|\|\||;|\||\$\()/\n/g' \
    | sed -E 's/^[[:space:]]*//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s/^((nohup|exec|time|timeout[[:space:]]+[0-9smh]+)[[:space:]]+)*//'
}
if [ "$TOOL" = "Bash" ]; then
  while IFS= read -r seg; do
    [[ $seg =~ ^orca(-ide)?[[:space:]]+orchestration[[:space:]]+check([[:space:]]|$) ]] || continue
    [[ "$seg " =~ [[:space:]]--(wait|peek|all|ack|terminal|help)[[:space:]=] ]] && continue
    printf 'BLOCKED: a bare inbox check returns a batch and never acknowledges it, so the\nbatch replays on every check and later messages queue behind it. Drain the\ninbox with\n  bash %s/orca-wait.sh\nor give check one of --wait, --peek, --all, --ack or --terminal.\n' "${BASH_SOURCE[0]%/*}/../scripts" >&2
    exit 2
  done < <(segments)
fi

# A `sleep N` in command position inside a do...done body, however the loop is
# split across lines. Depth, not a regex: a sleep after a finished loop, or a
# `done` that is only an argument (`echo done`), must not read as a poll.
sleep_loop() {
  printf '%s' "$BARE" | python3 -c '
import re, sys
toks = re.findall(r"[^\s;&|(){}]+|[;&|(){}\n]", sys.stdin.read())
depth, cmdpos, hit, skip = 0, True, 0, False
for i, w in enumerate(toks):
    if w in ";&|(){}\n":
        cmdpos = True
    elif not cmdpos:
        continue
    elif skip:
        skip = False  # the duration after `timeout`
    elif w in ("command", "builtin", "exec", "time", "nohup", "env") or re.match(r"[A-Za-z_]\w*=", w):
        pass  # a wrapper or assignment: the next word is still the command
    elif w == "timeout":
        skip = True
    elif w == "do":
        depth += 1
    elif w == "done":
        depth, cmdpos = max(depth - 1, 0), False
    elif w in ("while", "until", "for", "if", "then", "else", "elif", "!"):
        pass
    else:
        hit = hit or (w == "sleep" and depth > 0 and i + 1 < len(toks) and toks[i + 1][:1].isdigit())
        cmdpos = False
print(int(hit))'
}

if [ "$WORKER" = 1 ]; then
  # Advice, not a block: a Builder hand-wrote polls on its test log for up to 4,500 s of agent time in one build.
  [ "$TOOL" = "Bash" ] && printf '%s' "$BARE" | grep -qE '(^|[;&|[:space:]])sleep[[:space:]]+[0-9]' && [ "$(sleep_loop)" = 1 ] \
    && jq -cn --arg m 'A hand-written sleep loop waiting on output: start the run with run_in_background (you are notified when it exits); to block on it, wait only with wait-test-run.sh <runner-pid> <output-file> from the plugin scripts, which also checks the runner is still alive. Never poll.' \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
  exit 0
fi

# The Monitor tool is a poll loop by construction (owner ruling 2026-09-10,
# "figure out how you'll enforce using orca"): on 2026-09-10 main armed one
# file watcher per pane while 193 Orca "turn complete" messages sat unread,
# and 161 of 362 turns that day were watcher wake-ups. In the main session a
# Monitor is allowed only as a watcher that ends by sending an Orca message (a
# plain-shell ship pane has no agent to send).
#
# The inbox wait itself is never a Monitor: main re-armed a 30-minute
# Monitor looping orca-wait.sh 21 times in 12 hours on 2026-09-18, and 9 of its
# wake-ups were only the Monitor expiring, each a full context replay.
WAIT_RE='(^|[[:space:]/])orca-wait\.sh([[:space:]]|$)|orca-ide[[:space:]]+orchestration[[:space:]]+check[[:space:]].*--wait'
SINGLE_SHOT_FIX='Main never waits on its inbox: main-watch.sh posts every finished item and
Orca'"'"'s nudge wakes main. When the nudge lands, drain ONCE in the foreground:
  bash '"${BASH_SOURCE[0]%/*}/../scripts"'/orca-wait.sh
(The main-session rules, Waiting.)'
if [ "$TOOL" = "Monitor" ]; then
  if printf '%s' "$BARE" | grep -qE "$WAIT_RE"; then
    printf 'BLOCKED: the Orca inbox wait in a Monitor. A Monitor wakes main on its\nown timer, for nothing.\n%s\n' "$SINGLE_SHOT_FIX" >&2
    exit 2
  fi
  printf '%s' "$BARE" | grep -qE 'orca-ide[[:space:]]+orchestration[[:space:]]+send[[:space:]]' && exit 0
  cat >&2 <<'EOF'
BLOCKED: a Monitor in the main session that does not end with an Orca send.
main-watch.sh already posts every finished seat and stopped loop, and Orca's
nudge wakes main for them. For a plain shell pane (a ship script, a log), start a watcher that ENDS with
  orca-ide orchestration send --to <main's terminal handle> --type question --subject <what landed> --body <log path>
so Orca's nudge wakes main (worker_done and escalation need a live
dispatch; question and status do not). (The main-session rules,
Waiting; owner ruling 2026-09-10.)
EOF
  exit 2
fi

# A loop around the wait is the Monitor loop by another name: each pass is a
# wait main did not ask for, and it never returns to wake main. Parsed as
# shell words (WORDS), so a quoted search pattern is one argument, never a
# command, while a quoted script path in command position still is, and a
# comment is gone. Loop depth counts do/done, so a wait after an inner loop's
# `done` is still inside the outer one.
loop_wait() {
  CMD=$WORDS python3 - <<'PY'
import os, re, shlex, sys
try:
    # An unquoted newline ends a command like `;` does. Heredoc bodies, comments
    # and quotes are already gone (WORDS); shlex has no heredoc support of its own.
    lex = shlex.shlex(os.environ["CMD"], posix=True, punctuation_chars=";&|()\n")
    lex.whitespace = " \t\r"
    # shlex commenting stays off: it swallows the newline that ends the command,
    # so `while true # note` NEWLINE `do` hid the `do`.
    lex.commenters = ""
    lex.whitespace_split = True
    toks = list(lex)
except ValueError:
    # Could not be split: no loop can be ruled out, so the caller blocks it
    # when it names a wait.
    sys.exit(3)
SEP = re.compile(r"^[;&|()\n]+$")
depth, cmd = 0, []
def is_wait(words):
    while words and (re.match(r"^[A-Za-z_]\w*=", words[0]) or words[0] in ("bash", "sh", "exec", "nohup", "time")):
        words = words[1:]
    if words[:1] == ["timeout"]:
        words = words[2:]
    if not words:
        return False
    if words[0].endswith("orca-wait.sh"):
        return True
    return words[:3] == ["orca-ide", "orchestration", "check"] and "--wait" in words
for t in toks + [";"]:
    if SEP.match(t):
        if depth > 0 and is_wait(cmd):
            sys.exit(0)
        cmd = []
        continue
    if not cmd and t in ("do", "then", "else", "{"):
        depth += t == "do"
        continue
    if not cmd and t == "done":
        depth = max(depth - 1, 0)
        continue
    cmd.append(t)
sys.exit(1)
PY
}
# Not seen: a wait whose command word is quoted with anything but plain word
# characters (`"$DIR/orca-wait.sh"`).
if [ "$TOOL" = "Bash" ] && printf '%s' "$CMD_CODE" | grep -qE 'orca-wait\.sh|orchestration[[:space:]]+check'; then
  loop_wait; LW=$?
  if [ "$LW" = 0 ]; then
    printf 'BLOCKED: the Orca inbox wait inside a shell loop.\n%s\n' "$SINGLE_SHOT_FIX" >&2
    exit 2
  elif [ "$LW" != 1 ] && printf '%s' "$WORDS" | grep -qE 'orca-wait\.sh|orchestration[[:space:]]+check[[:space:]].*--wait'; then
    printf 'BLOCKED: this command names the Orca inbox wait and could not be read as shell words, so a loop around the wait cannot be ruled out. Run the wait as its own command.\n%s\n' "$SINGLE_SHOT_FIX" >&2
    exit 2
  fi
fi

# A blocking `check --wait` runs in the BACKGROUND (the owner 2026-09-10: a
# foreground wait blocks his typing for up to ten minutes). orca-wait.sh is a
# drain that never blocks, so it runs in the foreground.
# Command position only: a commit message or a rule quoting the wait is text.
is_wait_command() {
  local seg
  while IFS= read -r seg; do
    case "$seg" in orca-ide[[:space:]]*) printf '%s' "$seg" | grep -qE '^orca-ide[[:space:]]+orchestration[[:space:]]+check[[:space:]].*--wait' && return 0 ;; esac
  done < <(segments)
  return 1
}
if [ "$TOOL" = "Bash" ] && is_wait_command; then
  BG=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')
  if [ "$BG" != "true" ]; then
    printf 'BLOCKED: a foreground Orca wait blocks the owner'"'"'s typing for up to ten minutes\n(owner ruling 2026-09-10).\n%s\n' "$SINGLE_SHOT_FIX" >&2
    exit 2
  fi
  exit 0
fi

printf '%s' "$BARE" | grep -qE '(^|[;&|[:space:]])sleep[[:space:]]+[0-9]' || exit 0
printf '%s' "$BARE" | grep -qE 'orca-ide[[:space:]]+orchestration[[:space:]]+check[[:space:]].*--wait' && exit 0
printf '%s' "$BARE" | grep -qE 'orca-ide[[:space:]]+orchestration[[:space:]]+send[[:space:]]' && exit 0
printf '%s' "$BARE" | grep -qE '(^|[[:space:]/])orca-wait\.sh([[:space:]]|$)' && exit 0

LOOP=$(sleep_loop)
CHAIN=$(printf '%s' "$BARE" | tr '\n' ' ' | grep -cE 'sleep[[:space:]]+[0-9]+[[:space:]]*(;|&&|\|\|).*sleep[[:space:]]+[0-9]+[[:space:]]*(;|&&|\|\|)')
[ "$LOOP" = 0 ] && [ "$CHAIN" = 0 ] && exit 0

cat >&2 <<'EOF'
BLOCKED: sleep-loop polling in the main session. Wait on Orca instead:
  orca-ide orchestration check --run <run_id> --wait --timeout-ms <n> --json
For a file or process event, start ONE background watcher that ends with
  orca-ide orchestration send --run <run_id> --to run:<run_id> --subject ... --type heartbeat
and block on check --wait for it. (The main-session rules, Waiting;
owner ruling 2026-09-07.)
EOF
exit 2
