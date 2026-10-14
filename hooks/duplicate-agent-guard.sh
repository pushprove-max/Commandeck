#!/usr/bin/env bash
# PreToolUse hook (Bash): no duplicate agent, of any role, ever (
# owner ruling 2026-09-24). The launchers reuse a live pane
# (open_pane) and refuse a busy one (pane_is_busy), both in
# scripts/codex-helpers.sh. This blocks the same two moves typed by hand:
#   - `orca-ide terminal create --command <claude|codex ...>`, or
#     `orchestration worker-start --agent` into an existing worktree, in a
#     worktree that already has a live agent pane
#   - `orca-ide terminal send ... --enter` of a new job, or
#     `orchestration dispatch --inject` / `worker-start --terminal`, into a
#     pane whose agent is mid-turn
# In the main checkout every typed route to a new agent pane is refused
# outright, live agent or not (owner ruling 2026-10-11):
# `terminal create|split --command <agent>`, `worker-start --agent` and
# `worktree create --agent`. Main opens an agent pane only through
# builder-launch.sh or seat.sh.
# A script's own orca-ide calls never reach a hook, which sees only the typed
# command. Bare `orca` is the same binary on the Mac and is read the same way.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
case $CMD in *orca*) ;; *) exit 0 ;; esac
# Only text bash runs can launch or send: a mention in quotes, a comment or a
# heredoc body stops here.
# The executable name is not required to survive: `"orca-ide" terminal ...` runs.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh"
# Options may sit between the two subcommand words: one `-opt` with an
# optional value, repeated, as git-safety.sh reads git's.
OPTS='([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*'
# A quoted word is still the word bash passes (`"terminal" create`), so each
# quoted span stays as its word (strip-quoted.sh, the mark form): removed, the
# subcommand was gone and the launch passed. Quoted prose is one placeholder.
Q=$'\x01'
grep -qE "(terminal${OPTS}[[:space:]]+(create|send|split)|worktree${OPTS}[[:space:]]+create|orchestration${OPTS}[[:space:]]+(dispatch|worker-start))" \
  <<<"$(strip_quoted "$CMD" "$Q" | sed -E "s/${Q}([;&|()[:space:]]|\$)/QUOTED\1/g; s/${Q}//g")" || exit 0
. "${BASH_SOURCE[0]%/*}/../scripts/codex-helpers.sh"
block() { printf 'BLOCKED: %s\n' "$1" >&2; exit 2; }
SCRIPTED="the scripted launchers (seat.sh launch, builder-launch.sh) hand back a live pane instead of opening another"

# One line per checked invocation: "create<TAB><worktree>" for an agent launch,
# "job<TAB><handle>" for a new job sent or injected into a pane. The scanner
# splits the command into words and simple commands as bash does, so quoted
# prompt text, comments and heredoc bodies never read as a command or a flag.
# ponytail: expansions are not run; an orca-ide call built through a variable
# or eval is not seen.
# A function, not $(... <<'PY'): Bash 3.2 misreads the quotes of a here-document inside $(...).
plan() { python3 - "$CMD" <<'PY'
import re, sys
def scan(s, unbalanced):
    # One shell line as its simple commands, each a list of words, split as bash does.
    n = len(s); i = 0
    cmds, cur, word, heredocs = [], [], None, []
    drop = False  # the next word is a redirection target, not an argument
    def flush():
        nonlocal word, drop
        if word is not None:
            if not drop: cur.append(word)
            word = None; drop = False
    def end_cmd():
        nonlocal cur
        flush(); cmds.append(cur); cur = []
    while i < n:
        c = s[i]
        if c in ' \t\r': flush(); i += 1
        elif c == '\n':
            end_cmd(); i += 1
            for delim, tabs in heredocs:  # bodies start after the line that opened them
                while i < n:
                    j = s.find('\n', i); line = s[i:] if j < 0 else s[i:j]; i = n if j < 0 else j + 1
                    if (line.lstrip('\t') if tabs else line) == delim: break
            heredocs = []
        elif c in ';&|()': end_cmd(); i += 1
        elif c == '#' and word is None:
            j = s.find('\n', i); i = n if j < 0 else j
        elif s.startswith('<<<', i) or (c in '<>' and not s.startswith('<<', i)):
            flush(); i += 3 if s.startswith('<<<', i) else 1
            while i < n and s[i] in '>&|': i += 1
            drop = True
        elif s.startswith('<<', i):
            flush(); i += 2; tabs = i < n and s[i] == '-'; i += tabs
            while i < n and s[i] in ' \t': i += 1
            d = ''
            while i < n and s[i] not in ' \t\r\n;&|()<>':
                if s[i] in '\'"':
                    j = s.find(s[i], i + 1)
                    if j < 0: unbalanced()
                    d += s[i + 1:j]; i = j + 1
                elif s[i] == '\\': d += s[i + 1:i + 2]; i += 2
                else: d += s[i]; i += 1
            heredocs.append((d, tabs))
        elif c == '\\':
            if s[i + 1:i + 2] != '\n': word = (word or '') + s[i + 1:i + 2]
            i += 2
        elif c == "'" or s.startswith("$'", i):
            k = i + (2 if c == '$' else 1); buf = ''
            while k < n and s[k] != "'":
                if c == '$' and s[k] == '\\': buf += s[k:k + 2]; k += 2
                else: buf += s[k]; k += 1
            if k >= n: unbalanced()
            word = (word or '') + buf; i = k + 1
        elif c == '"':
            k = i + 1; buf = ''
            while k < n and s[k] != '"':
                if s.startswith('$(', k):
                    # A substitution in double quotes still runs: queue its text as commands.
                    j, d = k + 2, 1
                    while j < n and d:
                        if s[j] in '\'"':
                            q = s.find(s[j], j + 1); j = n if q < 0 else q + 1; continue
                        d += (s[j] == '(') - (s[j] == ')'); j += 1
                    if d: unbalanced()
                    s += '\n' + s[k + 2:j - 1]; n = len(s); buf += '$()'; k = j
                elif s[k] == '\\' and k + 1 < n: buf += s[k + 1]; k += 2
                else: buf += s[k]; k += 1
            if k >= n: unbalanced()
            word = (word or '') + buf; i = k + 1
        else: word = (word or '') + c; i += 1
    end_cmd()
    return cmds
s = sys.argv[1]
def unbalanced():
    # Bash would not run it either, unless it is a launch or send this hook exists for.
    o = r'(\s+-\S+(\s+[^\s-]\S*)?)*'
    sys.exit(3 if re.search(r'orca(-ide)?' + o + r'\s+(terminal' + o + r'\s+(create|send|split)|worktree' + o + r'\s+create|orchestration' + o + r'\s+(dispatch|worker-start))', s) else 0)
cmds = scan(s, unbalanced)
def flag(words, name):
    for i, w in enumerate(words):
        if w == '--' + name and i + 1 < len(words): return words[i + 1]
        if w.startswith('--' + name + '='): return w.split('=', 1)[1]
    return None
# A hand nudge to the job a pane is already on is known by its text; a new job
# worded as one passes.
NUDGE = r'(go|continue([\s:,].*)?|/[a-z].*|Your turn ended without .*)'
def command_words(words):
    # Assignments, shell keywords and wrappers before the command word.
    while words:
        if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*=.*', words[0], re.S) or words[0] in (
                'if', 'then', 'else', 'elif', 'while', 'until', 'do', '!', '{', 'time', 'exec',
                'command', 'builtin', 'nohup', 'env', 'nice', 'setsid', 'sudo'):
            words = words[1:]
        elif words[0] == 'timeout' and len(words) > 1: words = words[2:]
        else: break
    return words
def unread(): raise ValueError
def runs_agent(text):
    # A pane command is a shell line of its own: an agent is the command word of
    # one of its commands (a `bash -c` body included), never an argument.
    try: lines = scan(text, unread)
    except ValueError: return True  # an unread pane command is not a plain one
    for w in map(command_words, lines):
        if not w: continue
        name = w[0].rsplit('/', 1)[-1]
        if name in ('claude', 'codex'): return True
        if name in ('bash', 'sh', 'zsh') and any(
                re.fullmatch(r'-[a-z]*c', a) and runs_agent(w[k + 1]) for k, a in enumerate(w[1:-1], 1)):
            return True
    return False
SUBWORDS = ('terminal', 'worktree', 'orchestration', 'create', 'send', 'split', 'dispatch', 'worker-start')
def skip_options(ws):
    # Orca's global options (--json, --environment <name>) sit before the
    # subcommand or between its two words. An option's value is dropped
    # with it, unless that word is one of the subcommand words read here.
    while ws and ws[0].startswith('-'):
        ws = ws[2:] if '=' not in ws[0] and ws[1:] and not ws[1].startswith('-') and ws[1] not in SUBWORDS else ws[1:]
    return ws
for words in cmds:
    words = command_words(words)
    if not words or not re.search(r'(^|/)orca(-ide)?$', words[0]): continue
    group = skip_options(words[1:])
    sub = ' '.join(group[:1] + skip_options(group[1:])[:1])
    if sub in ('terminal create', 'terminal split') and runs_agent(flag(words, 'command') or ''):
        print('hand\t')
        if sub == 'terminal create': print('create\t' + (flag(words, 'worktree') or ''))
    elif sub == 'worktree create' and flag(words, 'agent'): print('hand\t')
    elif sub == 'terminal send' and '--enter' in words and not re.fullmatch(NUDGE, flag(words, 'text') or '', re.I | re.S):
        print('job\t' + (flag(words, 'terminal') or ''))
    elif sub == 'orchestration dispatch' and '--inject' in words:
        print('job\t' + (flag(words, 'to') or ''))
    elif sub == 'orchestration worker-start':
        # --terminal hands a job to an existing pane; --agent opens a new one,
        # a second agent unless the worktree is new too.
        wt = flag(words, 'worktree') or ''
        if flag(words, 'terminal'): print('job\t' + flag(words, 'terminal'))
        elif flag(words, 'agent'):
            print('hand\t')
            if not wt.startswith('new-'): print('create\t' + wt)
PY
}
PLAN=$(plan) || block "an orca-ide command this hook cannot parse (unbalanced quotes?); an unchecked launch or send is not allowed. Split it into plain commands."

# Main is the session's checkout, not the cwd a `cd` left behind. Outside a
# repository nothing is main and the live-agent check below still applies.
ROOT=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // "."' <<<"$INPUT")}
GIT_DIR_OF=$(git -C "$ROOT" rev-parse --path-format=absolute --git-dir 2>/dev/null)
MAIN=""
[ -n "$GIT_DIR_OF" ] && [ "$GIT_DIR_OF" = "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ] && MAIN=1

while IFS=$'\t' read -r kind val; do
  case $kind in
    hand)
      [ -z "$MAIN" ] || block "a hand-made agent pane from the main checkout. Open it with scripts/builder-launch.sh <unit> <batch-brief> or scripts/seat.sh launch <role> <unit> <spec> (owner ruling 2026-10-11)." ;;
    create)
      WT=$val
      [ -n "$WT" ] || WT="path:$(git -C "$(jq -r '.cwd // "."' <<<"$INPUT")" rev-parse --show-toplevel 2>/dev/null)"
      case $WT in *'$'*) block "a hand-made agent pane in a worktree given as a variable ($WT): the live-agent check cannot read it. Spell the worktree out; $SCRIPTED." ;; esac
      out=$(orca-ide terminal list --worktree "$WT" --json 2>/dev/null) && jq -e 'has("result")' <<<"$out" >/dev/null 2>&1 \
        || block "a hand-made agent pane in $WT: Orca's pane list cannot be read, and an unknown state is not an absent agent."
      live=$(jq -r '[.result | if type == "array" then . else (.terminals // []) end | .[]
        | select(.connected != false and .orphaned != true and .agentIdentity != null)
        | "\(.handle) (\(.agentIdentity), \(.title))"] | join(", ")' <<<"$out")
      [ -z "$live" ] || block "a second agent in $WT, which already has a live agent pane: $live. Read or reuse that pane; $SCRIPTED." ;;
    job)
      H=$val
      [ -n "$H" ] || continue
      case $H in *'$'*) block "a job sent to a pane given as a variable ($H): the busy check cannot read it. Spell the handle out." ;; esac
      rc=0; pane_is_busy "$H" || rc=$?
      case $rc in
        0) block "a new job into ${H#terminal:}, whose agent is mid-turn: it would queue behind that turn and run as a second job. Wait for the turn to end; dispatch-task.sh refuses a busy pane the same way." ;;
        2) block "a job sent to ${H#terminal:}: Orca cannot report its agent state, and an unknown state is not an idle pane." ;;
      esac ;;
  esac
done <<<"$PLAN"
exit 0
