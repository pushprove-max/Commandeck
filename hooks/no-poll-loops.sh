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
# Worker panes run in linked git worktrees and have no Orca run to block on, so
# main's rules about Orca waits do not apply to them. In every pane a bare
# `orca(-ide) orchestration check` is blocked: it returns a batch and never
# acknowledges it, so the batch replays on every check and later messages queue
# behind it. A worker is held to one more thing (issue 214): a FOREGROUND call
# may not wait past the prompt cache, since the next reply then rewrites it. Its
# stated waits are summed against one budget, and a wait in a loop, which states
# no end, is refused. A background call or a Monitor ends the turn and its exit
# wakes the pane, so neither is held. The script of `bash -c`, `sh -c`, `zsh -c`,
# `eval` and `env -S` is summed by the same rules (issue 216), and `$'sleep'` is
# the word sleep (issue 215). These are cost guards for agents that cooperate,
# not a security boundary; open on purpose (issue 215): a command word built by
# expansion (`s=sleep; $s 400`), a wrapping function or alias, and the
# over-block of `"a b""sleep"`, which errs toward refusing.
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
case "$P" in *sleep*|*orca-wait*|*orchestration*|*timeout-ms*|*wait-test-run*) ;; *) [ "$TOOL" = "Monitor" ] && [ "$WORKER" = 0 ] || exit 0 ;; esac
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
if type strip_quoted >/dev/null 2>&1; then
  BARE=$(strip_quoted "$CMD_CODE")
  Q=$'\x01'
  MARKED=$(strip_quoted "$CMD_CODE" "$Q")
  # The arguments bash passes, for every parser that reads words by position: a
  # quoted token joins its neighbours (`"6""00"` is 600, `>"/dev/null"` is a
  # redirection and its target), and quoted prose is the one word QUOTED. The
  # mark stays in a quoted word, since bash reads a reserved word only unquoted
  # (`"do""ne"` is a command, not the `done` that ends a loop); run() drops it.
  JOINED=$(printf '%s' "$MARKED" | sed -E "s/${Q}([^A-Za-z0-9_.\/:=@%+,-]|\$)/QUOTED\1/g")
else
  BARE=$(printf '%s' "$CMD_CODE" | sed -e "s:'[^']*'::g" -e 's:"[^"]*"::g' | sed -E 's/(^|[[:space:];&|(])#.*$/\1/')
  JOINED=$CMD_CODE
fi

# The shell words every parser below shares, run by each with exec(). TOK splits
# text into words, separators and redirections, a redirection attached or not
# (a brace is a separator only as a word of its own, as bash reads `{` and `}`:
# `${done}` is one word, never the `done` keyword)
# (`sleep>/dev/null 400`, `2>&1`; a digit run before `>` is a file descriptor,
# as bash reads it). run() is the command a simple command runs: redirections
# and their targets dropped wherever they stand, then leading assignments and
# reserved words (both unquoted; each word's quote mark \x01 is dropped after
# them), then wrappers with their options (`env -u X`, `timeout -s TERM 600`).
# num() reads a number the way GNU sleep and JavaScript's Number() do (4e2,
# +400, 0x190, inf); None when it cannot.
export NPL_WORDS='
import math, re
TOK = re.compile(r"\d*(?:&>>?|[<>]+&?)|[^\s;&|()<>]+|[;&|()\n]")
REDIR = re.compile(r"\d*(?:&>>?|[<>]+&?)")
SEPS = set(";&|(){}\n")
# Each wrapper with the short options that take the next word.
WRAP = {"command": "", "builtin": "", "exec": "a", "time": "fo", "nohup": "", "env": "CSuaPLU", "timeout": "ks",
        "nice": "n", "setsid": "", "stdbuf": "eio", "bash": "Oo", "sh": "Oo"}
LONG_ARG = {"--unset", "--chdir", "--split-string", "--argv0", "--signal", "--kill-after", "--adjustment", "--input",
            "--output", "--error", "--format", "--rcfile", "--init-file"}
RESERVED = {"do", "then", "else", "elif", "if", "while", "until", "!", "{"}
SHELLS = ("bash", "sh", "zsh")
def opts(name, ws):
    # The option words a wrapper takes at the front of ws, each option-argument with its option.
    got, k = [], 0
    while k < len(ws) and ws[k].startswith("-") and ws[k] != "-":
        o = ws[k]
        got.append(o)
        k += 1
        if o == "--":
            break
        short = next((j for j, c in enumerate(o[1:]) if c in WRAP.get(name, "")), None) if o[1:2] != "-" else None
        if o in LONG_ARG or short == len(o) - 2:
            got.append(ws[k] if k < len(ws) else "")
            k += 1
    return got
def string_run(name, ws):
    # A wrapper that runs a string as a script (issue 216): a shell with -c, and env -S. Its script, else None.
    o = opts(name, ws)
    if name in SHELLS and any(x[:1] == "-" and x[1:2] != "-" and "c" in x[1:] for x in o):
        rest = ws[len(o):]
        return rest[0] if rest else ""
    if name == "env":
        for k, x in enumerate(o):
            if x == "--split-string":
                return o[k + 1] if k + 1 < len(o) else ""
            if x.startswith("--split-string="):
                return x.split("=", 1)[1]
            j = next((j for j, c in enumerate(x[1:]) if c in WRAP["env"]), None) if x[1:2] != "-" else None
            if j is not None and x[j + 1] == "S":
                return (o[k + 1] if k + 1 < len(o) else "") if j == len(x) - 2 else x[j + 2:]
    return None
def run(words):
    out, it = [], iter(words)
    for w in it:
        if REDIR.fullmatch(w):
            next(it, None)
        else:
            out.append(w)
    while out and (out[0] in RESERVED or re.match(r"[A-Za-z_]\w*=", out[0])):
        out = out[1:]
    out = [w.replace("\x01", "") for w in out]
    while out:
        name = out[0].rsplit("/", 1)[-1]
        if out[0] in RESERVED or re.match(r"[A-Za-z_]\w*=", out[0]):
            out = out[1:]
            continue
        if name not in WRAP or string_run(name, out[1:]) is not None:
            break
        out = out[1:]
        while out and out[0].startswith("-"):
            o = out.pop(0)
            if o == "--":
                break
            if name == "command" and o[1:2] != "-" and set(o[1:]) & set("vV"):
                return []  # a lookup (`command -v sleep`) runs nothing
            short = next((k for k, c in enumerate(o[1:]) if c in WRAP[name]), None) if o[1:2] != "-" else None
            if o in LONG_ARG or short == len(o) - 2:
                out = out[1:]
        if name == "timeout":
            out = out[1:]  # the duration
    return out
def num(s):
    try:
        v = float(s)
    except ValueError:
        try:
            v = float.fromhex(s) if re.match(r"[+-]?0[xX]", s) else None
        except ValueError:
            v = None
    return None if v is None or v != v else max(v, 0)
'
# Each command of JOINED as run() reads it, one per line.
segments() {
  printf '%s' "$JOINED" | python3 -c 'import os, sys; exec(os.environ["NPL_WORDS"])
cmd = []
for w in TOK.findall(sys.stdin.read()) + [";"]:
    if w in SEPS:
        if cmd:
            print(" ".join(run(cmd)))
        cmd = []
    else:
        cmd.append(w)'
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
# Also a chain: two sleeps with an operand, each followed by another command.
sleep_loop() {
  printf '%s' "$JOINED" | python3 -c 'import os, sys; exec(os.environ["NPL_WORDS"])
depth, cmd, hit, chain = 0, [], False, 0
for w in TOK.findall(sys.stdin.read().rstrip()) + [""]:
    if w in SEPS or not w:
        words = run(cmd)
        if len(words) > 1 and words[0].rsplit("/", 1)[-1] == "sleep":
            hit, chain = hit or depth > 0, chain + bool(w)
        cmd = []
    elif cmd:
        cmd.append(w)
    elif w == "do":
        depth += 1
    elif w == "done":
        depth = max(depth - 1, 0)
    elif w not in ("while", "until", "if", "then", "else", "elif", "!", "time", "-p"):
        cmd = [w]  # `for` too: its name word (`for done in`) is never a keyword
print(int(hit or chain > 1))'
}

if [ "$WORKER" = 1 ]; then
  [ "$TOOL" = "Bash" ] || exit 0
  [ "$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')" = "true" ] && exit 0
  # A Builder hand-wrote polls on its test log for up to 4,500 s of agent time in one build.
  # The budget is wait-test-run.sh's default wait, 270 s, under the 5-minute cache; 540 s under the 1-hour one
  # (setup writes CLAUDE_CODE_PROMPT_CACHE_TTL into each pane's settings). Summed per command, its word a path or not:
  # every operand of sleep, an orca command's --timeout-ms, a wait-test-run.sh (its max, else 270). A wait inside a
  # loop (its condition or body) repeats, so the one-pass sum bounds nothing: `loop`, refused.
  LIMIT=270; [ "${CLAUDE_CODE_PROMPT_CACHE_TTL:-}" = 1h ] && LIMIT=540
  # A shell string (`bash -c`, `eval`, `env -S`) is one quoted word in JOINED: its script is read from the raw words
  # of CMD_CODE (shlex), by the same rules and recursively (issue 216). One shlex cannot read is a wait not read.
  WAITED=$(printf '%s' "$JOINED" | NPL_RAW=$CMD_CODE python3 -I -c 'import os, shlex, sys; exec(os.environ["NPL_WORDS"])
UNIT = {"s": 1, "m": 60, "h": 3600, "d": 86400}
ESC = {"a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}
def ansi_c(m):
    e = m.group(1)
    if e[0] in "xuU":
        return chr(int(e[1:], 16))
    return chr(int(e, 8) & 255) if e[0] in "01234567" else ESC.get(e, e)
def dollar_quotes(text):
    # $'...' as its decoded text in single quotes, $"..." as "...", outside other quotes only: shlex reads neither.
    out, i, q = [], 0, None
    while i < len(text):
        c = text[i]
        if q == "\x27":
            q = None if c == "\x27" else q
        elif c == "\\":
            out.append(text[i:i + 2])
            i += 2
            continue
        elif q == "\"":
            q = None if c == "\"" else q
        elif c == "$" and text[i + 1:i + 2] == "\x27":
            m = re.compile(r"((?:[^\x27\\]|\\.)*)\x27", re.S).match(text, i + 2)
            if not m:
                raise ValueError("no closing quotation")
            body = re.sub(r"\\(x[0-9a-fA-F]{1,2}|u[0-9a-fA-F]{1,4}|U[0-9a-fA-F]{1,8}|[0-7]{1,3}|.)", ansi_c, m.group(1), flags=re.S)
            out.append(shlex.quote(body))
            i = m.end()
            continue
        elif c == "$" and text[i + 1:i + 2] == "\"":
            i += 1
            continue
        elif c in "\x27\"":
            q = c
        out.append(c)
        i += 1
    return "".join(out)
def raw_tokens(text):
    # Words with their quotes removed, separators as one ";", redirections as TOK reads them.
    lex = shlex.shlex(dollar_quotes(text), posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace = " \t\r"
    out = []
    for t in lex:
        if t and set(t) <= set(";&|()\n"):
            out.append(";")
        else:
            out.append(t)
    return out
def script_wait(text, depth=0):
    # (total, looped, unread) of a script, read as raw words; None for one that cannot be read.
    if depth > 8:
        return 0, False, True
    try:
        return walk(raw_tokens(text), True, False, depth + 1)
    except ValueError:
        return 0, False, True
STRINGS = [False]
def secs(a):
    # The whole operand first: 0x1d is hex, not 1 day.
    v = num(a)
    if v is None and a[-1:] in UNIT and len(a) > 1 and num(a[:-1]) is not None:
        v = num(a[:-1]) * UNIT[a[-1]]
    return None if v is None else math.ceil(min(v, 10**9))
def wait(words, raw, only, d):
    # (seconds, looped) for one command; seconds None when a wait cannot be read. A shell string is counted only
    # on raw words (JOINED holds it as QUOTED); `only` counts nothing else, as the JOINED walk counted it.
    if not words:
        return 0, False
    name, args = words[0].rsplit("/", 1)[-1], words[1:]
    s = " ".join(args) if name == "eval" else string_run(name, args) if name in SHELLS or name == "env" else None
    if s is not None:
        STRINGS[0] = True
        if not raw:
            return 0, False
        t, lp, un = script_wait(s, d)
        return (None if un else t), lp
    return (0 if only else plain_wait(name, args)), False
def plain_wait(name, args):
    if name == "sleep":
        n = [secs(a) for a in args]
        return None if None in n else sum(n)
    if name == "wait-test-run.sh":
        return int(args[2]) if len(args) > 2 and args[2].isdigit() else 270
    if name in ("orca", "orca-ide"):
        vals = [v for k, a in enumerate(args) for v in
                ([a.split("=", 1)[1]] if a.startswith("--timeout-ms=") else args[k + 1:k + 2] if a == "--timeout-ms" else [])]
        n = [num(v) for v in vals]
        return None if None in n else sum(math.ceil(min(v, 10**12) / 1000) for v in n)
    return 0
def walk(tokens, raw, only, d):
    depth, cmd, total, looped, unread = 0, [], 0, False, False
    for w in tokens + [";"]:
        if w in SEPS:
            n, lp = wait(run(cmd), raw, only, d)
            unread = unread or n is None
            total, looped, cmd = total + (n or 0), looped or lp or ((n is None or n > 0) and depth > 0), []
        elif cmd:
            cmd.append(w)
        elif w in ("while", "until", "for", "select"):
            depth += 1
            cmd = [w] if w in ("for", "select") else []  # its name word (`for done in`) is never a keyword
        elif w == "done":
            depth = max(depth - 1, 0)
        elif w not in ("do", "if", "then", "else", "elif", "!", "time", "-p"):
            cmd = [w]
    return total, looped, unread
total, looped, unread = walk(TOK.findall(sys.stdin.read()), False, False, 0)
if STRINGS[0]:
    t, lp, un = 0, False, False
    try:
        t, lp, un = walk(raw_tokens(os.environ["NPL_RAW"]), True, True, 0)
    except ValueError:
        un = True
    total, looped, unread = total + t, looped or lp, unread or un
print("loop" if looped else "unread" if unread else total)')
  if [ "$WAITED" = loop ]; then
    printf 'BLOCKED: a wait inside a loop in a worker pane repeats past the prompt cache. A background test run: wait-test-run.sh <runner-pid> <output-file> from the plugin scripts (ends by 270 s; exit 3 means wait again). Anything else: start it with Bash run_in_background and end the turn; its exit wakes you.\n' >&2
    exit 2
  fi
  if [ "$WAITED" = unread ]; then
    printf 'BLOCKED: this hook cannot read a wait in this call (a sleep operand or --timeout-ms that is not a number, such as $T), so it cannot hold it to the %s s prompt-cache budget. State the wait as a number, or start the call with Bash run_in_background.\n' "$LIMIT" >&2
    exit 2
  fi
  if [ "${WAITED:-0}" -gt "$LIMIT" ] 2>/dev/null; then
    printf "BLOCKED: this call can wait up to %s s in all, past the prompt cache's life, so the next reply rewrites it.\nOne wait per call, at most %s s: an ask takes \`--timeout-ms 240000\` and on a timeout reruns with \`--resume <message id>\`.\n" "$WAITED" "$LIMIT" >&2
    exit 2
  fi
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
# shell words (JOINED), so a quoted search pattern is one argument, never a
# command, while a quoted script path in command position still is, its quoted
# parts joined as bash joins them, and a comment is gone. Loop depth counts do/done, so a wait after an inner loop's
# `done` is still inside the outer one.
loop_wait() {
  CMD=$JOINED python3 - <<'PY'
import os, sys
# Heredoc bodies, comments and quotes are already gone (JOINED). TOK, not shlex:
# shlex split `2>&1` at the `&`, so the `1` read as the command.
exec(os.environ["NPL_WORDS"])
depth, cmd = 0, []
def is_wait(words):
    words = run(words)
    if not words:
        return False
    if words[0].endswith("orca-wait.sh"):
        return True
    return words[:3] == ["orca-ide", "orchestration", "check"] and "--wait" in words
for t in TOK.findall(os.environ["CMD"]) + [";"]:
    if t in SEPS:
        if depth > 0 and is_wait(cmd):
            sys.exit(0)
        cmd = []
        continue
    if not cmd and t in ("do", "then", "else"):
        depth += t == "do"
        continue
    if not cmd and t == "done":
        depth = max(depth - 1, 0)
        continue
    cmd.append(t)
sys.exit(1)
PY
}
# Not seen: a wait whose quoted command word holds a space or an operator
# (`"my dir/orca-wait.sh"`), which strip_quoted prints as prose.
if [ "$TOOL" = "Bash" ] && printf '%s' "$CMD_CODE" | grep -qE 'orca-wait\.sh|orchestration[[:space:]]+check'; then
  if loop_wait; then
    printf 'BLOCKED: the Orca inbox wait inside a shell loop.\n%s\n' "$SINGLE_SHOT_FIX" >&2
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

# JOINED, not BARE: a quoted or escaped command word (`"sleep"`, `\sleep`) runs.
printf '%s' "$JOINED" | tr -d '\001' | grep -qE '(^|[;&|[:space:]/<>])sleep([[:space:]<>]|$)' || exit 0
printf '%s' "$BARE" | grep -qE 'orca-ide[[:space:]]+orchestration[[:space:]]+check[[:space:]].*--wait' && exit 0
printf '%s' "$BARE" | grep -qE 'orca-ide[[:space:]]+orchestration[[:space:]]+send[[:space:]]' && exit 0
printf '%s' "$BARE" | grep -qE '(^|[[:space:]/])orca-wait\.sh([[:space:]]|$)' && exit 0

[ "$(sleep_loop)" = 0 ] && exit 0

cat >&2 <<'EOF'
BLOCKED: sleep-loop polling in the main session. Wait on Orca instead:
  orca-ide orchestration check --run <run_id> --wait --timeout-ms <n> --json
For a file or process event, start ONE background watcher that ends with
  orca-ide orchestration send --run <run_id> --to run:<run_id> --subject ... --type heartbeat
and block on check --wait for it. (The main-session rules, Waiting;
owner ruling 2026-09-07.)
EOF
exit 2
