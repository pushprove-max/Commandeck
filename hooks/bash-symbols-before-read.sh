#!/usr/bin/env bash
# codex: skip -- gates on this session's serena calls, which Codex has no tool for.
# PreToolUse hook on Bash: the shell twin of symbols-before-read.sh. A `cat`,
# `head`, `tail`, `sed -n`, `awk`, `nl` or `less` on project TypeScript or Python pulls it whole
# into context exactly as a Read does, and workers used that door 887 times on
# one large build (2026-09-07) against 1,680 Reads, so the Read-only gate
# covered half the traffic. Same rule, same tracker: blocked until serena
# answers for the file, no retry pass-through.
#
# In a worker pane even a cleared file is read in slices only: a trivial
# overview used to unlock a whole-file cat. Past these the refusal names the
# serena call that answers the question.
MAX_READ_LINES=60
MAX_CONTEXT_LINES=20
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict && pp_serena; } 2>/dev/null || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0
printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)(cat|head|tail|sed|awk|nl|less|rg|grep)\b' || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty'); CWD=${CWD:-$PWD}
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
KEY="${SID:-${CLAUDE_SESSION_ID:-${PPID}}}"
SERENA_TRACKER="/tmp/claude-serena-tracker-${KEY}"
SERENA_DOWN="/tmp/claude-serena-down-${KEY}"

# Full test logs belong on disk, not in a pane. An explicit line bound is the
# escape hatch for the small diagnostic slice the user actually needs.
LOG_ROOT="${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch}"
while IFS= read -r simple; do
  printf '%s' "$simple" | grep -qE '^[[:space:]]*(cat|head|tail|sed)\b' || continue
  for tok in $(printf '%s' "$simple" | grep -oE '[A-Za-z0-9_./~-]+\.log\b'); do
    case "$tok" in /*) f=$tok ;; ~/*) f="$HOME/${tok#\~/}" ;; *) f="$CWD/$tok" ;; esac
    [ -f "$f" ] || continue
    case "$f" in "$LOG_ROOT"/*) ;; *) continue ;; esac
    block_log=false
    if printf '%s' "$simple" | grep -qE '^[[:space:]]*cat\b'; then
      block_log=true
    elif printf '%s' "$simple" | grep -qE '^[[:space:]]*(head|tail)\b' \
      && ! printf '%s' "$simple" | grep -qE '^[[:space:]]*(head|tail)[[:space:]]+(-n[[:space:]]+|-[[:space:]]*)?[0-9]+\b'; then
      block_log=true
    elif printf '%s' "$simple" | grep -qE '^[[:space:]]*sed[[:space:]]+-n\b' \
      && ! printf '%s' "$simple" | grep -qE "^[[:space:]]*sed[[:space:]]+-n[[:space:]]+['\"]?([0-9]+,)?[0-9]+p"; then
      block_log=true
    fi
    if [ "$block_log" = true ]; then
      cat >&2 <<MSG
BLOCKED: do not load the full scratch log '$f' into context.
Use grep or tail -n 20 on the log instead.
MSG
      exit 2
    fi
  done
done < <(printf '%s\n' "$CMD" | sed -E 's/[[:space:]]*(&&|\|\||[;|])[[:space:]]*/\n/g')

# Stand down only on a real unavailability signal, as in the Read hook: an
# errored serena call this session. Silence is not unavailability.
[ -e "$SERENA_DOWN" ] && exit 0
# A session with serena switched off for the checkout cannot make the call this
# gate asks for; blocking there only costs a second turn per look. Main keeps
# serena and this gate (owner ruling 2026-09-23).
SESSION_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if jq -e --arg p "${SESSION_ROOT:-$CWD}" '((.projects[$p].disabledMcpServers // []) | index("serena")) != null
    or (.mcpServers.serena == null and .projects[$p].mcpServers.serena == null)' "$HOME/.claude.json" >/dev/null 2>&1; then
  exit 0
fi

# Only a file a read command names counts. A path quoted in a `gh issue create`
# body, or searched by `grep -n ... | head`, is not a whole-file read, and the old
# whole-command token scan blocked both. One command per line and per operator.
# Each path prints with its kind: R a read bounded to MAX_READ_LINES, U an
# unbounded read, W an rg/grep with more than MAX_CONTEXT_LINES of context.
READ_PATHS=$(CMD=$CMD CWD=$CWD MAX_READ=$MAX_READ_LINES MAX_CTX=$MAX_CONTEXT_LINES python3 - <<'PY'
import os, re, shlex
MAX_READ, MAX_CTX = int(os.environ["MAX_READ"]), int(os.environ["MAX_CTX"])
READERS = ("cat", "head", "tail", "sed", "awk", "nl", "less")

def bounded(cmd, args):
    if cmd in ("head", "tail"):
        n, it = 10, iter(args)
        for a in it:
            m = re.fullmatch(r"-n(.*)|--lines(?:=(.*))?", a)
            if m:
                v = m.group(1) or m.group(2) or next(it, "")
                n = int(v) if v.isdigit() else None  # tail +N and head -N reach the end
            elif re.fullmatch(r"-\d+", a):
                n = int(a[1:])
            elif re.fullmatch(r"-c.*|--bytes.*", a):
                n = None
            if n is None:
                return False
        return n <= MAX_READ
    if cmd == "sed":
        quiet, scripts, rest, it = False, [], [], iter(args)
        for a in it:
            if re.fullmatch(r"-[A-Za-z]*i.*|--in-place.*", a):
                return True  # an in-place edit prints nothing
            if a in ("-n", "--quiet", "--silent"):
                quiet = True
            elif a in ("-e", "--expression"):
                scripts.append(next(it, ""))
            elif re.fullmatch(r"-[A-Za-z]+", a):
                quiet = quiet or "n" in a
                if a.endswith("e"):
                    scripts.append(next(it, ""))
            else:
                rest.append(a)
        if not scripts and rest:
            scripts.append(rest[0])
        # Several ranges of one file count as their sum; anything that
        # is not a closed `A,Bp` range makes the read unbounded.
        total = 0
        for part in ";".join(scripts).split(";") if quiet and scripts else [""]:
            m = re.fullmatch(r"(\d+)(?:,(\+?)(\d+))?p", part.strip())
            if not m:
                return False
            a, plus, b = int(m.group(1)), m.group(2), m.group(3)
            total += 1 if b is None else int(b) + 1 if plus else max(int(b) - a + 1, 1)
        return total <= MAX_READ
    return False  # cat, awk, nl and less print the whole file

def context(args):
    widest, it = 0, iter(args)
    for a in it:
        m = re.fullmatch(r"-[A-Za-z]*?[ABC](\d*)|--(?:after-|before-)?context(?:=(\d*))?", a)
        if m:
            v = m.group(1) or m.group(2) or next(it, "")
            widest = max(widest, int(v) if v.isdigit() else 0)
    return widest

def filters_exclude_source(args):
    # True when every narrowing file filter names non-source files only; a
    # negated glob does not narrow, and an unrecognised shape counts as source.
    vals, it = [], iter(args)
    for a in it:
        m = re.fullmatch(r"(-g|--i?glob|-t|--type|--include)(?:=(.*))?", a) or re.fullmatch(r"(-[gt])(.+)", a)
        if m:
            v = m.group(2) or next(it, "")
            if not v.startswith("!"):
                vals.append((m.group(1), v))
    # Test and declaration files are exempt from this gate, as below.
    tests = r"__tests__|__mocks__|(^|/)tests/|\.test\.tsx?$|_test\.py$|(^|/)test_[^/]*\.py$|\.d\.ts$"
    return bool(vals) and all(
        v not in ("ts", "py") if f in ("-t", "--type")
        else bool(re.search(tests, v)) or (bool(re.search(r"\.\w+$", v)) and not re.search(r"\.(tsx?|py)$", v))
        for f, v in vals)

def search_operands(cmd, args):
    # (paths, recursive, stdin_redirect): the path operands of an rg/grep call.
    # Flags that take a value swallow it, and the first positional is the
    # pattern unless -e/-f supplied one.
    short_val = set("ABCEefgjMmrTtd") if cmd == "rg" else set("ABCefmdD")
    long_val = {"after-context", "before-context", "context", "regexp", "file", "glob", "iglob",
                "type", "type-not", "type-add", "type-clear", "max-count", "max-depth", "replace",
                "encoding", "threads", "max-filesize", "pre", "pre-glob", "sort", "sortr", "color",
                "colors", "engine", "ignore-file", "max-columns", "path-separator", "context-separator",
                "include", "exclude", "exclude-dir", "devices", "directories", "binary-files", "label"}
    pos, pattern_given, recursive, redirected, it = [], False, cmd == "rg", False, iter(args)
    for a in it:
        if a and set(a) <= set("<>"):
            redirected = redirected or a.startswith("<")
            next(it, None)
        elif a == "--":
            pos.extend(it)
        elif a == "-" or not a.startswith("-"):
            pos.append(a)
        elif a.startswith("--"):
            name = a[2:].split("=", 1)[0]
            pattern_given = pattern_given or name in ("regexp", "file")
            recursive = recursive or name in ("recursive", "dereference-recursive")
            if "=" not in a and name in long_val:
                next(it, None)
        else:
            for i, c in enumerate(a[1:], 1):
                recursive = recursive or (cmd == "grep" and c in "rR")
                if c in short_val:
                    pattern_given = pattern_given or c in "ef"
                    if i == len(a) - 1:
                        next(it, None)
                    break
    return (pos if pattern_given else pos[1:]), recursive, redirected

# Paths resolve from where an inline `cd` left the shell, not the payload cwd.
# A cd whose target is missing now may fail and stay put, or reach a directory
# the command creates first, so every directory the shell could be in is kept.
cwds = [os.environ["CWD"]]
def at(p, cwd):
    return p if p.startswith(("/", "~")) else os.path.normpath(os.path.join(cwd, p))

for line in os.environ["CMD"].splitlines():
    try:
        lex = shlex.shlex(line, posix=True, punctuation_chars=";&|<>")
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        toks = line.split()
    segs, seg, op = [], [], ""
    for t in toks:
        if t and set(t) <= set(";&|"):
            segs.append((op, seg)); seg, op = [], t
        else:
            seg.append(t)
    segs.append((op, seg))
    for i, (op, words) in enumerate(segs):
        while words and re.match(r"^[A-Za-z_]\w*=", words[0]):
            words = words[1:]
        cmd = os.path.basename(words[0]) if words else ""
        if cmd == "cd" and len(words) == 2 and not words[1].startswith("-"):
            # A cd in a pipeline or sent to the background moves only its own
            # subshell.
            nxt = segs[i + 1][0] if i + 1 < len(segs) else ""
            if op not in ("|", "|&") and nxt not in ("|", "|&", "&"):
                moved = []
                for c in cwds:
                    target = os.path.normpath(os.path.join(c, os.path.expanduser(words[1])))
                    moved += [target] if os.path.isdir(target) else [c, target]
                cwds = list(dict.fromkeys(moved))
            continue
        if cmd in READERS:
            kind = "R" if bounded(cmd, words[1:]) else "U"
        elif cmd in ("rg", "grep") and context(words[1:]) > MAX_CTX:
            # An explicit file is searched whatever the filters say; a filter
            # narrows only the directories a recursive search walks. With no
            # path rg searches the cwd, as does grep -r, unless stdin is fed.
            paths, recursive, redirected = search_operands(cmd, words[1:])
            narrowed = filters_exclude_source(words[1:])
            for cwd in cwds:
                for p in paths:
                    full = os.path.join(cwd, os.path.expanduser(p))
                    if os.path.isfile(full) or (os.path.isdir(full) and recursive and not narrowed):
                        print("W", at(p, cwd))
                if not paths and recursive and not narrowed and op != "|" and not redirected:
                    print("W", cwd)
            continue
        else:
            continue
        after_redirect = False
        for t in words[1:]:
            if after_redirect:
                after_redirect = False
                continue
            if t in (">", ">>"):
                after_redirect = True
                continue
            for m in re.findall(r"[A-Za-z0-9_./~-]+\.(?:tsx?|py)\b", t, re.I):
                for cwd in cwds:
                    print(kind, at(m, cwd))
PY
)

# A serena call naming any file in a directory clears every gated file in that
# same directory, not its subdirectories. Two spellings that differ
# only in letter case are one directory. Keep in parity with
# symbols-before-read.sh.
# Letter case is ignored only where the disk ignores it: on a disk that tells
# src/Auth from src/auth they are two directories, and one does not clear the other.
folds_case() { local u; u=$(tr 'a-zA-Z' 'A-Za-z' <<<"$CWD"); [ "$u" != "$CWD" ] && [ "$CWD" -ef "$u" ]; }
dir_cleared() {
  local d=; [[ $1 != */* ]] || d=${1%/*}/   # a file at the repo root has no folder: its neighbours are the entries with no slash
  awk -v d="$d" -v fold="$(folds_case && echo 1)" 'BEGIN { if (fold) d = tolower(d) } fold { $0 = tolower($0) } (d == "" || index($0, d) == 1) && length($0) > length(d) && index(substr($0, length(d) + 1), "/") == 0 { f = 1; exit } END { exit !f }' \
    "$SERENA_TRACKER" 2>/dev/null
}
WORKER=0
[ "${COMMANDECK_REVIEWER:-}" != "1" ] \
  && [ "$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)" != "$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)" ] \
  && WORKER=1

# Every unread file goes in ONE refusal: stopping at the first cost a command
# naming five files five refusals.
UNREAD=(); UNREAD_ABS=(); WIDE=()
. "${BASH_SOURCE[0]%/*}/lib/symbol-outline.sh"
while read -r kind tok; do
  [ -n "$tok" ] || continue
  case "$tok" in /*) f=$tok ;; ~/*) f="$HOME/${tok#\~/}" ;; *) f="$CWD/$tok" ;; esac
  [ -f "$f" ] || { [ "$kind" = W ] && [ -d "$f" ]; } || continue
  # Letter case is not compared, as in the Read gate: on the Mac SRC/x.ts opens src/x.ts.
  lf=${f,,}
  [ -d "$f" ] || case "$lf" in *.ts|*.tsx|*.py) ;; *) continue ;; esac
  if [ -d "$f" ]; then
    # A directory counts when a recursive search of it reaches gated source,
    # so `.` and a checkout root count.
    find "$f" \( -name node_modules -o -name .git \) -prune -o -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.py' \) -print 2>/dev/null \
      | grep -viqE '__tests__|/tests/|/test_[^/]*\.py$|_test\.py$|\.test\.tsx?$|\.d\.ts$|/__mocks__/' || continue
  fi
  case "$lf" in *__tests__*|*/tests/*|*/test_*.py|*_test.py|*.test.ts|*.test.tsx|*.d.ts|*/__mocks__/*|*/node_modules/*) continue ;; esac
  ROOT=$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null)
  REL="$f"; [ -n "$ROOT" ] && REL="${f#"$ROOT"/}"
  if [ "$WORKER" = 1 ] && [ "$kind" != R ]; then
    [[ " ${WIDE[*]} " == *" $REL "* ]] || WIDE+=("$REL")
  fi
  [ "$kind" = W ] && continue
  dir_cleared "$REL" && continue
  # A file the branch created has no shape to learn; same test as the Read gate.
  [ -f "$f" ] && new_in_branch "$f" && continue
  [[ " ${UNREAD[*]} " == *" $REL "* ]] || { UNREAD+=("$REL"); UNREAD_ABS+=("$f"); }
done <<< "$READ_PATHS"
[ "${#UNREAD[@]}" -eq 0 ] && [ "${#WIDE[@]}" -eq 0 ] && exit 0
{
  if [ "${#UNREAD[@]}" -gt 0 ]; then
    echo "BLOCKED once: read the shape of these before reading them from the shell. Top-level symbols:"
    for n in "${!UNREAD[@]}"; do
      [ -f "${UNREAD_ABS[n]}" ] || continue
      printf '  %s: %s\n' "${UNREAD[n]}" "$(symbol_outline "${UNREAD_ABS[n]}")"
      clear_dir_for "$SERENA_TRACKER" "${UNREAD[n]}"
    done
    cat <<MSG
Their directories are now cleared: retry the command, or pull one symbol with
mcp__serena__find_symbol (include_body); a shell read costs the same context as a Read.
Serena is a deferred tool: load it with ToolSearch, query
select:mcp__serena__get_symbols_overview,mcp__serena__find_symbol,mcp__serena__find_referencing_symbols
MSG
  fi
  if [ "${#WIDE[@]}" -gt 0 ]; then
    echo "BLOCKED: a worker pane reads source from the shell in slices of at most $MAX_READ_LINES lines (sed -n 'A,Bp', head/tail -n N) or $MAX_CONTEXT_LINES lines of rg/grep context:"
    printf '  %s\n' "${WIDE[@]}"
    echo "Ask serena instead: mcp__serena__get_symbols_overview for the file's shape, or mcp__serena__find_symbol with include_body for the one symbol you need."
  fi
} >&2
exit 2
