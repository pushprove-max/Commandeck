#!/usr/bin/env bash
# PreToolUse hook: enforce the 4 GB heap cap on node's test runner.
# Tool-steering rules (use Read instead of cat, Glob instead of find) were
# dropped: they cost a fork on every Bash call to restate a preference no
# incident traces to, and Codex has neither tool.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Issue 247, in a Builder and in any tier: a python3/perl/node script in the command (-c/-e, a here-document, a
# pipe) that writes a tracked file goes around Edit and the guards on it. Each write call's destination is read:
# a quoted path git tracks is refused; a scratch path passes, whatever tracked file the script also reads. A
# destination or mode the text does not spell out (a variable) cannot be screened, so it is refused when the
# script quotes a tracked path at all. perl -i edits the files named on the command line.
# Known gaps: a write call this list does not name (subprocess, os.write on a descriptor), a path built from
# pieces, a script file run by name, and writes by shell (>, sed -i, cp): the Edit guards never see those either.
if [ "${COMMANDECK_BUILDER-}" = 1 ]; then
  IW=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
  if [[ $IW =~ (^|[^[:alnum:]_.-])(python[0-9.]*|perl|node)([[:space:]]|$) ]]; then  # r2: /usr/bin/python3 too
    IW_OUT=$(cd "$(jq -r '.cwd // "."' <<<"$INPUT")" 2>/dev/null && IW=$IW python3 -I - <<'PY'
import os, re, shlex, subprocess
s = os.environ["IW"].replace('\\"', '"').replace("\\'", "'").replace("\\`", "`")
def lit(a):  # the text of a plain quoted string (a template literal or f-string without a hole too), else None
    m = re.match(r"""\s*([rbufRBUF]{0,2})(['"`])([^'"`\n]*)\2\s*$""", a or "")
    return None if not m or "{" in m.group(3) and (m.group(2) == "`" or "f" in m.group(1).lower()) else m.group(3)
def args(i):  # s[i] is "(": its top-level arguments, and the index after ")"
    depth, cur, out, q = 0, "", [], None
    for j in range(i + 1, len(s)):
        c = s[j]
        if q:
            cur += c; q = None if c == q else q; continue
        if c in "'\"`": q = c
        elif c in "([{": depth += 1
        elif c in ")]}":
            if depth == 0: return out + [cur], j + 1
            depth -= 1
        elif c == "," and depth == 0: out.append(cur); cur = ""; continue
        cur += c
    return out + [cur], len(s)
def writes(mode):  # True, False, or None when the mode is not a plain string
    v = lit(mode)
    return None if v is None else bool(re.search(r"[wax+]", v))
LANG = set(re.findall(r"(?:^|[^\w.-])(python|perl|node)[0-9.]*(?=\s|$)", s))
PY, JS = "python" in LANG, "node" in LANG
def may_write(b, i, py, js):  # an open call's mode, argument i: True unless each reading of it is read-only
    modes = []
    if py:  # mode=, else argument i unless it is a keyword, else read
        k = next((x.split("=", 1)[1] for x in b if re.match(r"\s*mode\s*=(?!=)", x)), None)
        modes.append(k if k is not None else b[i] if len(b) > i and not re.match(r"\s*(\w+\s*=(?!=)|$)", b[i]) else "'r'")
    if js:  # r5: in JavaScript flags='w' is an assignment, and its value is the mode
        modes.append(re.sub(r"^(\s*[\w$]+\s*=(?!=))+", "", b[i]) if len(b) > i and b[i].strip() else "'r'")
    return any(writes(x) is not False for x in modes)
dests = []  # each a literal path, or None for one that cannot be read
seen = set()  # where a Path(...) method call starts
for m in re.finditer(r"\bPath\s*\(", s):
    a, end = args(m.end() - 1)
    t = re.match(r"\s*\.\s*(\w+)\s*\(", s[end:])
    if not t: continue
    seen.add(end + t.start(1))
    b = args(end + t.end() - 1)[0]
    if t.group(1) in ("write_text", "write_bytes", "touch", "unlink", "rename", "replace", "symlink_to", "hardlink_to", "chmod", "rmdir") \
       or (t.group(1) == "open" and may_write(b, 0, True, False)):
        dests.append(lit(a[0]))
        if t.group(1) in ("rename", "replace"): dests.append(lit(b[0]))
TO = "copy|copy2|copyfile|copytree|move|rename|renameSync|replace|copyFile|copyFileSync|cp|cpSync|symlink|symlinkSync|link|linkSync"
AT = ("writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|outputFile|outputFileSync|truncate|truncateSync"
      "|unlink|unlinkSync|rm|rmSync|rmdir|rmdirSync|remove|rmtree|removedirs|chmod|chmodSync")
for m in re.finditer(r"(?<![\w$])(open|openSync|" + TO + "|" + AT + r")\s*\(", s):
    name, (a, _) = m.group(1), args(m.end() - 1)
    if name in ("open", "openSync"):
        if m.start() in seen: continue  # Path(...).open: read above
        recv = re.search(r"\.\s*$", s[:m.start()])
        # r5: perl's open has no receiver; a bare uppercase name is a perl handle only in a perl command
        if name == "open" and not recv and len(a) >= 2 and (re.match(r"\s*(my\s|\$)", a[0]) or "perl" in LANG and re.match(r"\s*[A-Z]\w*\s*$", a[0])):
            v = lit(a[1])  # perl: open(F, '>x') or open(my $f, '>', 'x')
            if len(a) == 2:
                if v is None: dests.append(None)
                elif re.match(r"\s*(\+<|>)", v): dests.append(re.sub(r"^\s*[+<>]+\s*", "", v))
            elif v is None or re.search(r"[>+]", v): dests.append(lit(a[2]))
            if not (PY or JS): continue  # else it is read as their open as well
        js = name == "openSync" or JS and bool(recv)  # JavaScript's open is a method (fs.open, fsp.open)
        if may_write(a, 1, name == "open" and (PY or not JS), js): dests.append(lit(a[0]))
    elif re.fullmatch(TO, name):
        dests.append(lit(a[1]) if len(a) > 1 else None)
        if name in ("move", "rename", "renameSync", "replace"): dests.append(lit(a[0]))
    else: dests.append(lit(a[0]))
# r2: a Path method on any other receiver (p = Path('x'); p.write_bytes(...)) writes where the text does not say.
for m in re.finditer(r"\.\s*(write_text|write_bytes|touch|symlink_to|hardlink_to|open)\s*\(", s):
    if m.start(1) in seen: continue
    b = args(m.end() - 1)[0]
    # r5: a quoted path first is a module's open(path, mode) (io.open, fsp.open), which the open( loop read; the
    # receiver's name proves nothing (io = Path('x')), so any other first argument is read as a Path mode
    if m.group(1) == "open" and lit(b[0]) is not None and not re.fullmatch(r"[rwabxtU+]*", lit(b[0])): continue
    r = re.search(r"(?<![\w$.])(\w+)\s*$", s[:m.start()])  # a module the script imports and never rebinds
    if m.group(1) == "open" and r and re.search(r"\bimport\s+([\w.]+\s*,\s*)*" + r[1] + r"\b(?!\s*as)|\b" + r[1] + r"\s*=\s*require\s*\(", s) \
       and len(re.findall(r"(?<![\w$.])" + r[1] + r"\s*=(?!=)", s)) <= len(re.findall(r"\b" + r[1] + r"\s*=\s*require\s*\(", s)): continue
    if m.group(1) != "open" or may_write(b, 0, True, False): dests.append(None)  # r3: m='w'; p.open(m) may write
try: words = shlex.split(s)
except ValueError: words = s.split()
for i, w in enumerate(words):  # perl -i edits in place the files after the script
    if re.fullmatch(r"(.*/)?perl", w) and any(re.fullmatch(r"-[a-zA-Z]*i\S*", x) for x in words[i + 1:]):
        dests += [x for x in words[i + 1:] if not x.startswith("-")]
def tracked(p):
    return subprocess.run(["git", "ls-files", "--error-unmatch", "--", p], capture_output=True).returncode == 0
for d in dests:
    if d and tracked(d): print("W " + d); raise SystemExit
if None in dests:
    for q in sorted(set(re.findall(r"""(?:['"`]|\bqq?\s*[({\[<])([A-Za-z0-9_./-]+)[)}\]>'"`]""", s))):
        if tracked(q): print("U " + q); raise SystemExit
PY
)
    case $IW_OUT in
      "W "*) echo "BLOCKED: an inline script writes ${IW_OUT#W }, a tracked file. Make the change with the \`Edit\` tool, which the guards on Edit see; an inline script may write a scratch path (\$TMPDIR, the unit's scratch folder)." >&2; exit 2 ;;
      "U "*) echo "BLOCKED: an inline script writes to a path or with a mode it does not spell out, and names ${IW_OUT#U }, a tracked file. Make the change with the \`Edit\` tool, or write to a quoted scratch path (\$TMPDIR, the unit's scratch folder) so the write can be screened." >&2; exit 2 ;;
    esac
  fi
fi
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# A here-document's end word is one plain word (letters, digits, _ . -): bare,
# in one pair of quotes, or after one backslash. Every other `<<` is refused
# here, above every other rule and exit, so no rule in this or any other hook
# has to read an odd end word; each misread one hid the command after the note.
# A `<<<` here-string has no body and passes. Only a `<<` bash reads as an
# operator is judged: strip_quoted reports each one outside quotes, comments
# and earlier bodies (strip_odd_end). git-safety.sh asks the same question for
# itself: this hook is off in a project that did not turn the strict tier on.
. "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null
# Without the helper no end word is checked and every bare node --test would pass.
type strip_quoted >/dev/null 2>&1 || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/strip-quoted.sh, so it cannot screen this command. Restore it (git checkout hooks/lib/strip-quoted.sh) and retry." >&2; exit 2; }
ODD=$(strip_odd_end "$CMD")
[ -z "$ODD" ] || { echo "BLOCKED: a here-document's end word is not plain: $ODD -- use one plain word such as EOF, as in \`cat <<'EOF'\` (letters, digits, _ . -), bare or in one pair of quotes." >&2; exit 2; }

# Block node's test runner without the 4 GB heap cap.
# Root cause of four WSL crashes on 2026-08-24: one uncapped
# `node --test` child grew at 1.45 GB/s to 29 GB and took the workstation.
# `npm run test:*` carries the cap in the script itself, so it never matches
# here -- only a bare `node`/`npx tsx` invocation does.
#
# `--test` must be followed by whitespace or end-of-command: `--test-concurrency`
# and `--test-reporter` are companion flags, not the runner switch, and matching
# them would fire on capped commands that spell the cap correctly.
#
# The check is PER SEGMENT, not per command line. A command-wide cap search
# passed `node --max-old-space-size=4096 --test a.ts && node --test b.ts`: the
# first invocation's flag vouched for the second, uncapped one.
# Quoted text is data, not a command: `rg 'node --test src/x.ts' .claude` is a
# search, and blocking it made the hook fire on ordinary work -- including on
# the report that described it. Quoted spans and heredoc bodies come out BEFORE
# the split, in one pass over the whole command: a per-line sed left a
# multi-line commit message whole. A `;` or `&&` inside a string cannot
# manufacture a segment either. A heredoc fed to a shell (`bash <<EOF`) is
# read as data too; that is an accepted gap.
# The strip walks the command a character at a time; only a `--test` can match
# (quote and backslash characters dropped first, so `--te''st` is still seen).
# A quoted span that is one word stays the word node gets (`node "--test"`,
# a quoted heap flag); a span holding a space is prose and reads as QUOTED, so
# a cap inside a multi-word quoted NODE_OPTIONS value is not seen and blocks.
HQ=$'\x01'
HEAP_CMD=""; P=${CMD//[\'\"\\]/}; case "$P" in *--test*) HEAP_CMD=$(strip_quoted "$CMD" "$HQ" | sed -E "s/${HQ}([;&|()[:space:]]|\$)/QUOTED\1/g; s/${HQ}//g") ;; esac

while IFS= read -r SEG; do
  # An `npm` segment carries the cap inside the script it runs, and its
  # arguments may legitimately spell out a node invocation
  # (`npm run test:unit -- node --test x.ts`). Leading `VAR=value` assignments
  # and `env` are prefixes, not the command: `CI=1 npm run test:unit` is npm.
  SEG_HEAD=$(echo "$SEG" | sed -E ':a; s/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env)[[:space:]]+//; ta')
  [ "$(echo "$SEG_HEAD" | awk '{print $1}')" = "npm" ] && continue

  echo "$SEG" | grep -qE '(^|[[:space:]])(node|npx[[:space:]]+tsx)([[:space:]]+[^[:space:]]+)*[[:space:]]+--test([[:space:]]|$)' || continue

  # Allow only an explicit cap of 4096 or lower, IN THIS SEGMENT. A LARGER
  # number is still a block: the point of the cap is that a runaway dies in
  # seconds. EVERY heap flag in the segment is read, in either spelling (node
  # takes `-` and `_` alike, and `=N` or a space) and wherever it sits:
  # node honours the last one, so `--max-old-space-size=4096
  # --max_old_space_size=8192` ran at 8 GB behind a guard that read one spelling.
  HEAPS=$(echo "$SEG" | grep -oE -- '--max[-_]old[-_]space[-_]size(=|[[:space:]]+)[0-9]+' | grep -oE '[0-9]+$')
  if [ -z "$HEAPS" ] || [ -n "$(awk '$1 > 4096' <<<"$HEAPS")" ]; then
    echo "BLOCKED: bare node --test without --max-old-space-size=4096, or with a larger heap flag beside it. Add the flag (\`node --max-old-space-size=4096 --test\`) and drop any larger one, or run the project's own test script when it carries the cap." >&2
    exit 2
  fi
done < <(printf '%s\n' "$HEAP_CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/&/\n/g' -e 's/|/\n/g' -e 's/;/\n/g')

# Split a command line into segments at `;`, `&`, `|` and newlines, one per
# line, each prefixed 1 when it reads a pipe, 2 when it is the `||` alternative
# of the segment before, and 0 otherwise. Quotes count only
# for segment boundaries (`rg 'a|b' src` is one segment). `$2 = \0` ends each
# segment with NUL instead, for a reader that must keep a multi-line quote whole.
split_search_segments() {
  local TEXT=$1 SEG="" QUOTE="" CHAR NEXT PIPE=0 I END=${2:-\\n} OP="" # OP = the last char if it is an unescaped, unquoted < or >
  for ((I=0; I<${#TEXT}; I++)); do
    CHAR=${TEXT:I:1}; NEXT=${TEXT:I+1:1}
    # A backslash escapes the next character everywhere except inside single
    # quotes, so `"[^ \"]*|b"` stays one quoted span and its `|` is pattern
    # text, not a pipe. Without this the escaped quote closed the span early.
    if [ "$CHAR" = '\' ] && [ "$QUOTE" != "'" ]; then SEG+=$CHAR$NEXT; I=$((I+1)); OP=""; continue; fi
    if [ -n "$QUOTE" ]; then SEG+=$CHAR; [ "$CHAR" = "$QUOTE" ] && QUOTE=""; continue; fi
    case "$CHAR" in
      "'"|'"') QUOTE=$CHAR; SEG+=$CHAR; OP="" ;;
      '|') [ "$OP" = '>' ] && { SEG+=$CHAR; OP=""; continue; } # `>|` is the clobber redirect
           printf "%s%s$END" "$PIPE" "$SEG"; SEG=""; PIPE=1
           if [ "$NEXT" = '|' ]; then PIPE=2; I=$((I+1)); elif [ "$NEXT" = '&' ]; then I=$((I+1)); fi ;;
      '&'|';'|$'\n')
        # `2>&1`, `>&2` and `&>` are redirections, not a background `&`: cutting
        # there made `cmd 2>&1 | jq` read as a stray `1` piped into jq.
        if [ "$CHAR" = '&' ] && { [ -n "$OP" ] || [ "$NEXT" = '>' ]; }; then SEG+=$CHAR; OP=""; continue; fi
        printf "%s%s$END" "$PIPE" "$SEG"; SEG=""; PIPE=0; [ "$NEXT" = '&' ] && I=$((I+1)) ;;
      *) SEG+=$CHAR; OP=${CHAR//[!<>]/} ;;
    esac
  done
  printf "%s%s$END" "$PIPE" "$SEG"
}

# Split one segment into words the way the shell would, expanding nothing:
# quotes group and are removed, and a backslash escapes as it does in bash.
# Deleting every quote and splitting on spaces turned `rg 'foo bar' src` into
# a pattern plus a stray `bar` path. An unquoted `>` also ends a word unless an
# fd number, `&`, `<` or `>` leads it: `foo>src/x` is `foo` plus a redirect.
seg_words() {
  local TEXT=$1 W="" QUOTE="" HAVE=0 CHAR NEXT I
  for ((I=0; I<${#TEXT}; I++)); do
    CHAR=${TEXT:I:1}; NEXT=${TEXT:I+1:1}
    if [ "$CHAR" = '\' ] && [ "$QUOTE" != "'" ]; then
      HAVE=1
      if [ "$QUOTE" = '"' ] && [[ $NEXT != [\"\\\$\`] ]]; then W+=$CHAR; else W+=$NEXT; I=$((I+1)); fi
      continue
    fi
    if [ -n "$QUOTE" ]; then
      if [ "$CHAR" = "$QUOTE" ]; then QUOTE=""; else W+=$CHAR; fi
      continue
    fi
    case "$CHAR" in
      "'"|'"') QUOTE=$CHAR; HAVE=1 ;;
      ' '|$'\t') [ "$HAVE" = 1 ] && printf '%s\n' "$W"; W=""; HAVE=0 ;;
      '>') [[ $HAVE = 1 && ! $W =~ ^([0-9]*|&)$ && $W != *[\<\>] ]] && { printf '%s\n' "$W"; W=""; }; W+=$CHAR; HAVE=1 ;;
      *) W+=$CHAR; HAVE=1 ;;
    esac
  done
  [ "$HAVE" = 1 ] && printf '%s\n' "$W"
}

# WORDS = the segment's words, minus a leading `(`/`{` and the shell keywords
# that open a compound command, so `do rg x` and `(curl ...` read as the tool.
load_words() {
  mapfile -t WORDS < <(seg_words "$1")
  while [ ${#WORDS[@]} -gt 0 ]; do
    WORDS[0]=${WORDS[0]#"${WORDS[0]%%[!({]*}"}
    case "${WORDS[0]}" in
      ''|do|then|else|elif|if|while|until|'!'|time) WORDS=("${WORDS[@]:1}") ;;
      *) break ;;
    esac
  done
}

shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# SUBST = $1 with every `$NAME` / `${NAME}` (name $2) replaced by $3.
subst_var() {
  local RE='^(.*)\$'"$2"'([^A-Za-z0-9_].*)?$'
  SUBST=${1//"\${$2}"/"$3"}
  while [[ $SUBST =~ $RE ]]; do SUBST=${BASH_REMATCH[1]}$3${BASH_REMATCH[2]}; done
}

# Resolve the literal aliases a call sets for ITSELF: `WT=/path; git -C "$WT" log`
# and `for f in /tmp/x/*.log; do rg y "$f"; done`. Only a bare literal
# assignment, a one-word for-list and $HOME resolve; nothing is executed. Any
# other `$` stays in the text, and every check below still refuses it. The
# search check reads SRCH_TEXT, so an alias is judged exactly like the path it
# names.
ASSIGN_RE='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|'"'[^']*'"'|\$\(.*\)|[^[:space:]"'"'"']*)[[:space:]]*$'
FOR_RE='^[[:space:]]*for[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+in[[:space:]]+(.+)$'
# `[while] [IFS=] read [-r] VAR`: VAR takes the fed-in lines one at a time.
# search_text puts these two lines round each substitution it lifts out. A substitution runs in its own
# shell, so what it assigns and where it cds end with it: the state is kept at the first and put back at the second.
SUB_OPEN=$'\001(' SUB_CLOSE=$'\001)'
READ_RE='^[[:space:]]*(while[[:space:]]+)?(IFS=[^[:space:]]*[[:space:]]+)?read([[:space:]]+-r)?[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(<[[:space:]]*[^[:space:]]+[[:space:]]*)?$'
load_segments() { # $1 = a command text, $2 = the prefix of the four arrays to fill
  local -n L_PIPE=$2_PIPE L_TEXT=$2_TEXT L_FOR=$2_FOR L_READ=$2_READ
  local -A ALIAS=() FORLIST=() READVAR=()
  local LINE TEXT NAME VAL
  local -a KEPT=() # one entry per open substitution: a nested one puts back the outer one's state, not the call's
  L_PIPE=(); L_TEXT=(); L_FOR=(); L_READ=()
  while IFS= read -r LINE; do
    TEXT=${LINE:1}
    subst_var "$TEXT" HOME "$HOME"; TEXT=$SUBST
    for NAME in "${!ALIAS[@]}"; do
      subst_var "$TEXT" "$NAME" "${ALIAS[$NAME]}"
      [ "$SUBST" = "$TEXT" ] && continue
      TEXT=$SUBST
    done
    if [ "$TEXT" = "$SUB_OPEN" ]; then KEPT+=("$(declare -p ALIAS FORLIST READVAR)")
    elif [ "$TEXT" = "$SUB_CLOSE" ]; then [ ${#KEPT[@]} -eq 0 ] || { eval "${KEPT[-1]}"; unset 'KEPT[-1]'; }
    elif [[ $TEXT =~ $ASSIGN_RE ]] || [[ $TEXT =~ $FOR_RE ]]; then
      NAME=${BASH_REMATCH[1]}; VAL=${BASH_REMATCH[2]}
      VAL=${VAL%"${VAL##*[![:space:]]}"}
      unset "ALIAS[$NAME]" "FORLIST[$NAME]" "READVAR[$NAME]"
      case "$VAL" in
        # A multi-word for-list of literals stays unsubstituted; the search check
        # below judges every word it can take.
        *'$'*|*'`'*) ;;
        *[[:space:]]*) [[ $TEXT =~ $FOR_RE ]] && { VAL=${VAL//\"/}; FORLIST[$NAME]=${VAL//\'/}; } ;;
        *) VAL=${VAL//\"/}; ALIAS[$NAME]=${VAL//\'/} ;;
      esac
    elif [[ $TEXT =~ $READ_RE ]]; then
      NAME=${BASH_REMATCH[4]}
      unset "ALIAS[$NAME]" "FORLIST[$NAME]"
      READVAR[$NAME]=1
    fi
    # The loop bindings in force at THIS segment, so a later reassignment of the
    # variable does not change how an earlier search is judged.
    L_FOR+=("$(for NAME in "${!FORLIST[@]}"; do printf '%s\t%s\n' "$NAME" "${FORLIST[$NAME]}"; done)")
    L_READ+=(" ${!READVAR[*]} ")
    L_PIPE+=("${LINE:0:1}"); L_TEXT+=("$TEXT")
  done < <(split_search_segments "$1")
}

# Block a repo-wide text search:
# every path an `rg`, or a `grep` with a recursive flag, names must be bounded,
# and one with no path must read a pipe. Bounded is any path, relative ones
# resolved against the command's own `cd`, that does not normalize to the
# filesystem root, a checkout root, a parent of one, or a bare wildcard; a glob
# is judged again per match(a top-level folder off an old allowlist, a
# glob and a path after a `cd` were all refused). An unresolved variable is not
# bounded. The pattern and option values are not paths, so a slash in the
# pattern proves nothing and `-g '*.ts'` is not an operand.
# Root cause: a whole-repo `rg` from main took the session down on 2026-09-10.
SEARCH_BASE=$PWD
RG_SHORT_VALUED=ABCEefgjMmrtT
GREP_SHORT_VALUED=ABCDdefm
RG_LONG_VALUED=" --glob --iglob --type --type-not --type-add --type-clear --max-count --context --after-context --before-context --max-depth --maxdepth --threads --sort --sortr --encoding --max-columns --max-filesize --replace --path-separator --pre --pre-glob --ignore-file --colors --color --context-separator --field-match-separator --field-context-separator --dfa-size-limit --regex-size-limit --engine --hyperlink-format "
GREP_LONG_VALUED=" --include --exclude --exclude-dir --exclude-from --max-count --context --after-context --before-context --devices --directories --label --binary-files --group-separator "
SEARCH_ROOTS=""

root_like() { # $1 = normalized absolute path
  local P=$1 R Q=${1%/*}
  [ "$P" = / ] && return 0
  # Home holds every checkout even when this one lives elsewhere (a Mac /tmp checkout).
  [ "$P" = "$(realpath -m -- "$HOME")" ] && return 0
  case "$Q" in *[*?[{]*) return 0 ;; esac
  # A bare wildcard is every entry of its folder: as wide as that folder.
  case "${P##*/}" in *[!*?]*) ;; *) root_like "${Q:-/}"; return ;; esac
  [ -e "$P/.git" ] && return 0
  compgen -G "$P/*/.git" >/dev/null && return 0
  [ -n "$SEARCH_ROOTS" ] || SEARCH_ROOTS="$(git rev-parse --show-toplevel 2>/dev/null) $(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  for R in $SEARCH_ROOTS; do
    case "${R%/.git}/" in "$P"/*) return 0 ;; esac
  done
  return 1
}

search_bounded() {
  local OP=$1 P M
  # The `)` that closes a subshell is not part of the path, unless a path has
  # it. A file on disk does not say which the shell meant, so both readings
  # must be bounded.
  if [[ $OP == *')' ]]; then
    search_bounded "${OP%"${OP##*[!)]}"}" || return 1
    [ -e "$OP" ] || [ -e "$SEARCH_BASE/$OP" ] || return 0
  fi
  # A HOME-ROOTED PATH IS A REAL PATH. A session's own transcripts live
  # under ~/.claude/projects/<project>/, outside every checkout, and `~/...` or
  # `$HOME/...` was refused as unbounded before it was ever resolved. Expand the
  # two home forms, then judge the result exactly like any other absolute path:
  # a bare `~` still fails, because the checkout itself lives under it.
  case "$OP" in
    '~'|'$HOME') OP=$HOME ;;
    '~/'*) OP=$HOME/${OP#'~/'} ;;
    '$HOME/'*) OP=$HOME/${OP#'$HOME/'} ;;
  esac
  # A variable is judged as a glob from its first `$` on (/tmp/logs/x-$n.log
  # as /tmp/logs/x-*), so the glob rules below bound it. A bare `$X` has no
  # fixed prefix and stays refused.
  case "$OP" in *'$'*|*'`'*)
    OP=${OP%%[\$\`]*}
    [ -n "$OP" ] || return 1
    OP="$OP*"
  esac
  case "$OP" in
    /*) P=$OP ;;
    *) [ -n "$SEARCH_BASE" ] || return 1; P=$SEARCH_BASE/$OP ;;
  esac
  # GNU realpath never fails under -m, so a failure is a realpath that cannot judge any path.
  P=$(realpath -m -- "$P" 2>/dev/null) || { echo "BLOCKED: realpath -m failed (a realpath without -m, such as the Mac's own, is first on this hook's PATH), so no search path can be judged. Put GNU realpath first: brew install coreutils, or run /commandeck:setup." >&2; exit 2; }
  root_like "$P" && return 1
  case "$P" in *[*?[]*)
    while IFS= read -r M; do root_like "$(realpath -m -- "$M")" && return 1; done < <(compgen -G "$P")
  esac
  return 0
}

# The search rule reads its own text: the command with every live
# `$( )` and backtick span lifted out to a line of its own after the command
# that holds it (a `$()` stays in its place), so a search inside one is judged
# as the command it is; and with a note's text taken out, so prose that names
# a search is not. A note is a here-document cat or tee reads, alone on its
# line, with nothing after its end word and no process substitution on or before
# that line (`cat <<EOF > >(bash)` and `exec > >(bash)` before a plain
# `cat <<EOF` run its body); under an end word with no quote its
# substitutions still run and are judged. Any other here-document is read as
# commands, since a shell may be fed it or a later line may run the file. So a
# note whose text names a search, followed by another command in the same
# call, is still refused: write the note in its own call or with the Write tool.
# A substitution inside another is lifted the same way inside the outer one's
# own lines, so it is judged after the outer commands before it and its state
# ends where it closes.
# A seat belt against an honest mistake, not a wall. Not followed: `eval`, a
# command held in a variable, `bash -c '...'` text, process substitution, and
# nesting deeper than the self-test covers.
_st_open() { BUF+=("$OUT"); RET+=("$MODE"); DEP+=("$D"); KIND+=("$1"); HELD+=("$PEND"); OUT=""; PEND=""; D=0; MODE=code; }
_st_close() {
  case "$MODE" in sq|asq) OUT+="'" ;; dq) OUT+='"' ;; esac
  PEND=${HELD[-1]}$SUB_OPEN$NL$OUT$NL$PEND$SUB_CLOSE$NL; OUT=${BUF[-1]}'$()'; MODE=${RET[-1]}; D=${DEP[-1]}
  unset 'BUF[-1]' 'RET[-1]' 'DEP[-1]' 'KIND[-1]' 'HELD[-1]'
}
_st_sub() { # opens or closes a substitution at I; fails when none starts or ends there
  if [ "$C$N" = '$(' ]; then I=$((I+1)); _st_open p
  elif [ "$C" != '`' ]; then return 1
  elif [ ${#KIND[@]} -gt 0 ] && [ "${KIND[-1]}" = b ]; then _st_close
  else _st_open b; fi
}
NOTE_RE='(^|[;&|])[[:space:]]*(cat|tee)([[:space:]][^;&|]*)?$'
search_text() {
  # Plain arithmetic goes first, as for the end-word check: its `<<` is a shift.
  local TEXT; TEXT=$(sed -E 's/\$\(\([A-Za-z0-9_ +*\/%()<>-]*\)\)/0/g' <<<"$1")
  local OUT="" PEND="" MODE=code NL=$'\n' C N I J T R D=0 LS=0 TAG="" TQ="" DASH="" NOTE=0 BODY="" BQ="" BASE=0 BD=0
  local -a BUF=() RET=() DEP=() KIND=() HELD=()
  for ((I=0; I<${#TEXT}; I++)); do
    C=${TEXT:I:1}; N=${TEXT:I+1:1}
    if [ "$C" = "$NL" ]; then
      # A body ends where bash ends it, whatever its text left open.
      if [ -n "$BODY" ]; then
        T=${TEXT:LS:I-LS}; [ -z "$DASH" ] || T=${T#"${T%%[!	]*}"}
        if [ "$T" = "$TAG" ]; then
          while [ ${#BUF[@]} -gt "$BASE" ]; do _st_close; done
          OUT+=$BQ; BQ="" BODY="" TAG="" MODE=code D=$BD
        fi
      fi
      LS=$((I+1))
    fi
    if [ "$MODE" = comment ]; then [ "$C" = "$NL" ] || continue; MODE=code; fi
    case "$MODE" in
      sq) OUT+=$C; [ "$C" = "'" ] && MODE=code ;;
      # `$'...'`: a `\'` does not end it, so it goes on as a plain quoted span.
      asq) if [ "$C" = '\' ] && [ "$N" != "$NL" ]; then OUT+=_; I=$((I+1))
           else OUT+=$C; [ "$C" = "'" ] && MODE=code; fi ;;
      dq)
        if [ "$C" = '\' ] && [ "$N" != "$NL" ]; then OUT+=$C$N; I=$((I+1))
        elif _st_sub; then :
        else OUT+=$C; [ "$C" = '"' ] && MODE=code; fi ;;
      # A note under an end word with no quote: only what it runs is kept.
      nbody) if [ "$C" = '\' ]; then [ "$N" = "$NL" ] || I=$((I+1)); else _st_sub; fi ;;
      # Any other body is commands: BQ follows its quotes as the segment split
      # will, to close an open one at the end word. With no quote on the end
      # word bash runs every substitution in it, single quotes or not.
      sbody)
        if [ "$C" = '\' ] && [ "$N" != "$NL" ] && { [ "$BQ" != "'" ] || { [ -z "$TQ" ] && [[ $N == [\$\`\\] ]]; }; }; then OUT+=$C$N; I=$((I+1))
        elif { [ -z "$TQ" ] || [ "$BQ" != "'" ]; } && _st_sub; then :
        else
          OUT+=$C
          if [ -n "$BQ" ]; then [ "$C" = "$BQ" ] && BQ=""; else case "$C" in "'"|'"') BQ=$C ;; esac; fi
        fi ;;
      code)
        case "$C" in
          '\') I=$((I+1)); [ "$N" = "$NL" ] || OUT+=$C$N ;;
          "'") MODE=sq; OUT+=$C ;;
          '"') MODE=dq; OUT+=$C ;;
          '#') if [ "$I" -gt 0 ] && [[ ${TEXT:I-1:1} != [[:space:]\;\&\|\(] ]]; then OUT+=$C; else MODE=comment; fi ;;
          '$') if [ "$N" = "'" ]; then MODE=asq; OUT+=$N; I=$((I+1)); else _st_sub || OUT+=$C; fi ;;
          '`') _st_sub ;;
          '(') D=$((D+1)); OUT+=$C ;;
          ')') if [ "$D" -gt 0 ]; then D=$((D-1)); OUT+=$C
               elif [ ${#KIND[@]} -gt 0 ] && [ "${KIND[-1]}" = p ]; then _st_close
               else OUT+=$C; fi ;;
          '<') if [ "$N" != '<' ]; then OUT+=$C
               elif [ "${TEXT:I+2:1}" = '<' ]; then OUT+='<<<'; I=$((I+2))
               else
                 # The end word is plain here: every other one was refused above.
                 J=$((I+2)) T="" R=""
                 [ "${TEXT:J:1}" = '-' ] && { J=$((J+1)); R=1; }
                 while [[ ${TEXT:J:1} == [[:blank:]] ]]; do J=$((J+1)); done
                 TQ=""; case "${TEXT:J:1}" in "'"|'"'|'\') TQ=1 ;; esac
                 while [[ -n ${TEXT:J:1} && ${TEXT:J:1} != [[:space:]\;\&\|\(\)\<\>] ]]; do T+=${TEXT:J:1}; J=$((J+1)); done
                 T=${T//[\'\"\\]/}
                 if [ -n "$T" ]; then
                   TAG=$T DASH=$R NOTE=0
                   R=${TEXT:I}; R=${TEXT:0:I}${R%%"$NL"*}
                   [ ${#BUF[@]} -eq 0 ] && [ -z "$DASH" ] && [[ ${TEXT:LS:I-LS} =~ $NOTE_RE && $R != *[\<\>]\(* ]] && NOTE=1
                 fi
                 OUT+='<<'; I=$((I+1))
               fi ;;
          ';'|'|'|'&'|"$NL")
            [ "$C" = "$NL" ] || NOTE=0
            # A lifted span is judged where it ran: after the command that holds it.
            if [ -n "$PEND" ] && [ "$C$N" != '&>' ] && [[ $C != '&' || $N == '&' || ${OUT: -1} != [\<\>] ]]; then OUT+=$NL$PEND; PEND=""; fi
            OUT+=$C
            if [ "$C" = "$NL" ] && [ -n "$TAG" ]; then
              R=${TEXT:I+1}; R=${R%"${R##*[![:space:]]}"}; T=${R##*"$NL"}
              if [ "$NOTE" = 1 ] && [ "$T" = "$TAG" ] && [[ $NL${R%"$T"} != *"$NL$TAG$NL"* ]]; then
                [ -z "$TQ" ] || break
                MODE=nbody TAG=""
              else BODY=1 MODE=sbody BASE=${#BUF[@]} BD=$D BQ=""; fi
            fi ;;
          *) OUT+=$C ;;
        esac ;;
    esac
  done
  while [ ${#BUF[@]} -gt 0 ]; do _st_close; done
  printf '%s\n%s' "$OUT" "$PEND"
}
SRCH_PIPE=(); SRCH_TEXT=(); SRCH_FOR=(); SRCH_READ=()
load_segments "$(search_text "$CMD")" SRCH

KEPT_BASE=()
for i in "${!SRCH_TEXT[@]}"; do
  case "${SRCH_TEXT[i]}" in
    "$SUB_OPEN") KEPT_BASE+=("$SEARCH_BASE"); continue ;;
    "$SUB_CLOSE") [ ${#KEPT_BASE[@]} -eq 0 ] || { SEARCH_BASE=${KEPT_BASE[-1]}; unset 'KEPT_BASE[-1]'; }; continue ;;
  esac
  load_words "${SRCH_TEXT[i]}"; set -- "${WORDS[@]}"
  TOOL=${1-}; [ $# -gt 0 ] && shift
  # Follow the command's own `cd`; one this cannot resolve leaves relative
  # paths unbounded. A cd into a directory that does not exist fails and
  # leaves the shell where it was, so the base stays put: `cd <root>/missing;
  # rg x .` searches the root. With `&&` the rg never runs, so judging it from
  # the old base only over-blocks.
  if [ "$TOOL" = cd ] || [ "$TOOL" = pushd ]; then
    # Stated limit: a cd that moves nothing after it is still followed -- one inside a pipeline, one
    # put in the background with `&`, one under a condition that does not run. A search after such
    # a cd is judged against the wrong directory. This guards against an accidental checkout-wide
    # search; it is not a parser of every shell form.
    NEW_BASE=""
    case "${1-}" in
      ''|'~') NEW_BASE=$HOME ;;
      '~/'*) NEW_BASE=$HOME/${1#'~/'} ;;
      -*|*'$'*|*'`'*) SEARCH_BASE=""; continue ;;
      /*) NEW_BASE=$(realpath -m -- "$1") ;;
      *) [ -n "$SEARCH_BASE" ] && NEW_BASE=$(realpath -m -- "$SEARCH_BASE/$1") ;;
    esac
    [ -n "$NEW_BASE" ] && [ -d "$NEW_BASE" ] && SEARCH_BASE=$NEW_BASE
    continue
  fi
  case "$TOOL" in
    rg) SHORT_VALUED=$RG_SHORT_VALUED; LONG_VALUED=$RG_LONG_VALUED ;;
    grep) printf '%s\n' "$@" | grep -qE '^-[a-zA-Z]*[rR]|^--(dereference-)?recursive$' || continue
          SHORT_VALUED=$GREP_SHORT_VALUED; LONG_VALUED=$GREP_LONG_VALUED ;;
    *) continue ;;
  esac
  PATTERN=""; HAVE_PATTERN=0; FILES_MODE=0; STDIN=${SRCH_PIPE[i]}; PATHS=(); OPTS_DONE=0
  while [ $# -gt 0 ]; do
    W=$1; shift
    case "$W" in
      '<'|'<<'|'<<<'|[0-9]'<') STDIN=1; shift; continue ;;
      '<'*|[0-9]'<'*) STDIN=1; continue ;;
      '>'|'>>'|[0-9]'>'|[0-9]'>>'|'&>') shift; continue ;;
      '>'*|[0-9]'>'*|'&>'*) continue ;;
    esac
    if [ "$OPTS_DONE" = 0 ]; then
      case "$W" in
        --) OPTS_DONE=1; continue ;;
        -) STDIN=1; continue ;;
        --regexp=*|--file=*) HAVE_PATTERN=1; PATTERN=${W#*=}; continue ;;
        --regexp|--file) HAVE_PATTERN=1; PATTERN=${1-}; shift; continue ;;
        --files|--type-list) HAVE_PATTERN=1; FILES_MODE=1; continue ;;
        --*=*) continue ;;
        --*) case "$LONG_VALUED" in *" $W "*) shift ;; esac; continue ;;
        -?*)
          for ((J=1; J<${#W}; J++)); do
            C=${W:J:1}
            case "$SHORT_VALUED" in *"$C"*)
              V=${W:J+1}; [ -n "$V" ] || { V=${1-}; shift; }
              case "$C" in e|f) HAVE_PATTERN=1; PATTERN=$V ;; esac
              break ;;
            esac
          done
          continue ;;
      esac
    fi
    PATHS+=("$W")
  done
  # The first operand is the pattern only when no -e/-f/--files names one, wherever that flag sits.
  [ "$HAVE_PATTERN" = 0 ] && [ ${#PATHS[@]} -gt 0 ] && PATTERN=${PATHS[0]} && PATHS=("${PATHS[@]:1}")
  BAD=""
  if [ ${#PATHS[@]} -eq 0 ]; then
    [ "$STDIN" = 1 ] && [ "$TOOL" = rg ] && continue
    BAD="(no path)"
  else
    for P in "${PATHS[@]}"; do
      LOOP_LIST=""
      if [[ $P =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]]; then
        # A read-bound variable is one fed-in path per search: bounded.
        [[ ${SRCH_READ[i]} == *" ${BASH_REMATCH[1]} "* ]] && continue
        LOOP_LIST=$(printf '%s\n' "${SRCH_FOR[i]}" | awk -F'\t' -v n="${BASH_REMATCH[1]}" '$1 == n { print $2 }')
      fi
      if [ -n "$LOOP_LIST" ]; then
        read -ra LOOP_WORDS <<< "$LOOP_LIST"
        for V in "${LOOP_WORDS[@]}"; do search_bounded "$V" || { BAD=$V; break 2; }; done
      else
        search_bounded "$P" || { BAD=$P; break; }
      fi
    done
    [ -z "$BAD" ] && continue
  fi
  # The advice names a directory that is there: the first one of the checkout.
  TRYDIR=$(cd "$SEARCH_BASE" 2>/dev/null && ls -d */ 2>/dev/null | head -1); TRYDIR=${TRYDIR%/}; TRYDIR=${TRYDIR:-src}
  if [ "$FILES_MODE" = 1 ]; then TRY="rg --files $TRYDIR"
  elif [ "$TOOL" = grep ]; then TRY="grep -rn -e $(shq "$PATTERN") $TRYDIR"
  else TRY="rg -n -e $(shq "$PATTERN") $TRYDIR"; fi
  echo "BLOCKED: $TOOL over an unbounded path: $BAD. Name a directory relative to the checkout (\`rg <pattern> scripts/\`), an existing file, or an absolute log path such as /tmp/<unit>-*.log -- never the checkout root, a parent of it, or an unresolved variable. A repo-wide search took main down on 2026-09-10." >&2
  # The rule never said how to ask the whole-repo question, which is sometimes
  # the real one: 19 of 51 blocks were followed by another block of this same
  # rule. Both sanctioned answers are named here.
  echo "Whole repo: codebase-memory search_code answers it without a filesystem walk. To search the tree anyway, name its top-level directories: $TOOL ... <dir> <dir>" >&2
  echo "Try: $TRY" >&2
  exit 2
done

# Block a kill that can reach main's own session (owner ruling 2026-09-17).
# Main cleared two stray waiters with `kill -TERM -<pid>`. The negative form
# signals a PROCESS GROUP; those waiters were started by a Monitor inside the
# CLI's own process tree, so the signal killed the Claude Code session. Twice in
# one evening, and a memory did not stop the second one. Three shapes refuse
# here: a negative-pid target, a pid in this hook's own ancestor chain, and a
# pkill/killall pattern naming the binaries main itself runs.
KILL_ANCESTORS=""
KILL_PID=$$
while [ -n "$KILL_PID" ] && [ "$KILL_PID" -gt 1 ] 2>/dev/null; do
  KILL_ANCESTORS="$KILL_ANCESTORS $KILL_PID"
  # ps, not /proc: the Mac has no /proc, so the chain stopped at this hook.
  KILL_PID=$(ps -o ppid= -p "$KILL_PID" 2>/dev/null | tr -d ' ')
done
KILL_MSG="BLOCKED: this kill can reach main's own session. Kill a stray waiter by BARE literal pid only (kill -TERM 123 456) -- never pid 0 or the negative process-group form, never an unexpanded \$VAR, \$(...) or backtick target, except a job this same command started: a plain NAME=\$! before the kill, with NAME appearing nowhere else in the command but as \$NAME (sleep 30 & W=\$!; kill \$W) -- never a pid from main's own tree, never pkill/killall by user (-u), and never pkill on claude/node/orca in any case or behind a regex. scripts/board.sh prints the waiter ROOT pids."
# A job the same command started: `$!` is a child of the command's own
# shell, never main or an ancestor. Nothing is evaluated, so name $1 passes only
# when every mention of it in the command is a plain `NAME=$!` or a `$NAME` /
# `${NAME}`: any other mention -- `read W`, `W=$PPID`, `${W:=1}`, the name in
# quoted prose -- may be another assignment and refuses. The mentions are
# counted with quotes and backslashes dropped, so `read \W` is one; the plain
# assignments must also be whole segments of the stripped view, so one that
# sits in a string, a comment or a heredoc, or carries a quoted or escaped
# tail, counts as a mention only.
# A text check cannot tell that an assignment RAN: in a dead branch or a
# subshell the name keeps the value it already had, and `PIPESTATUS`, `SECONDS`
# or zsh's `status` can be 0 -- the caller's own group. So a name the
# environment sets, or the shell sets by itself, is refused; a name unset
# everywhere expands to nothing and kills nothing.
# ponytail: the list is kept by hand, from what a clean bash 5.3 and a clean
# zsh 5.9 report as set (`env -i bash -c 'compgen -v'`, zsh's `parameters`)
# plus the names they set later (PIPESTATUS, REPLY, MATCH, COLUMNS, ...). A
# name a newer shell starts setting needs a row here and a case in the self-test.
kill_child_ok() {
  local N=$1 T=" ${CMD//[\'\"\\]/} " PLAIN=0 CODE=0 SEG
  case "$N" in
    BASH*|ZSH*|zsh_*|COMP_*|EPOCH*|PROMPT*|PS[0-4]|TRY_BLOCK_*|dis_*|HIST*|MAIL*) return 1 ;;
    PPID|UID|EUID|GID|EGID|GROUPS|RANDOM|SRANDOM|SECONDS|LINENO|OPTIND|OPTERR|OPTARG|SHLVL) return 1 ;;
    PIPESTATUS|pipestatus|status|COLUMNS|LINES|REPLY|reply|MAPFILE|COPROC|FUNCNAME|FUNCNEST) return 1 ;;
    DIRSTACK|dirstack|ARGC|argv|ERRNO|TTY|TTYIDLE|MATCH|MBEGIN|MEND|match|mbegin|mend|_) return 1 ;;
    IFS|PATH|path|PWD|OLDPWD|HOME|SHELL|SHELLOPTS|TERM|HOSTNAME|HOSTTYPE|HOST|MACHTYPE|OSTYPE) return 1 ;;
    CPUTYPE|VENDOR|USERNAME|LOGNAME|KEYBOARD_HACK|KEYTIMEOUT|LISTMAX|SAVEHIST|NULLCMD|READNULLCMD) return 1 ;;
    SPROMPT|TIMEFMT|TMPPREFIX|WORDCHARS|WATCH|watch|PSVAR|psvar|prompt|CDPATH|cdpath|FIGNORE|fignore) return 1 ;;
    FPATH|fpath|MANPATH|manpath|MODULE_PATH|module_path|aliases|galiases|saliases|builtins|commands) return 1 ;;
    functions|functions_source|funcfiletrace|funcsourcetrace|funcstack|functrace|histchars|history) return 1 ;;
    historywords|jobdirs|jobstates|jobtexts|keymaps|mailpath|modules|nameddirs|options|parameters) return 1 ;;
    patchars|reswords|signals|termcap|terminfo|userdirs|usergroups|widgets) return 1 ;;
  esac
  printenv "$N" >/dev/null && return 1
  local REF='^(.*)\$'"$N"'([^A-Za-z0-9_].*)$' ASG='^(.*[[:space:];&|({])'"$N"'=\$!([[:space:];&|)}].*)$'
  local ANY='(^|[^A-Za-z0-9_])'"$N"'([^A-Za-z0-9_]|$)' WHOLE='^[[:space:]]*'"$N"'=\$![[:space:]]*$'
  T=${T//"\${$N}"/-}
  while [[ $T =~ $REF ]]; do T=${BASH_REMATCH[1]}-${BASH_REMATCH[2]}; done
  while [[ $T =~ $ASG ]]; do T=${BASH_REMATCH[1]}-${BASH_REMATCH[2]}; PLAIN=$((PLAIN+1)); done
  [[ $T =~ $ANY ]] && return 1
  while IFS= read -r SEG; do
    [[ ${SEG:1} =~ $WHOLE ]] && CODE=$((CODE+1))
  done < <(split_search_segments "$(strip_quoted "$CMD" $'\x01')")
  [ "$PLAIN" -gt 0 ] && [ "$PLAIN" = "$CODE" ]
}
KILL_CHILD_RE='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=\$![[:space:]]*$'
KILL_TARGET_RE='^\$([A-Za-z_][A-Za-z0-9_]*)$|^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$'
KILL_SEEN=" "
while IFS= read -r LINE; do
  # Order: only an assignment in an EARLIER segment vouches for a target.
  [[ ${LINE:1} =~ $KILL_CHILD_RE ]] && KILL_SEEN+="${BASH_REMATCH[1]} "
  case "${LINE//[\'\"\\]/}" in *kill*) ;; *) continue ;; esac
  # seg_words expands nothing, so `$PPID` and `$(pgrep x)` arrive as typed.
  load_words "${LINE:1}"
  set -- "${WORDS[@]}"
  case "${1-}" in env|bash|sh|sudo) shift ;; esac
  [ $# -gt 0 ] || continue
  case "$(basename -- "${1-}")" in
    kill)
      shift
      # Only the FIRST argument can be the signal, and a signal number is at
      # most 64: that is what tells `kill -9 1234` (fine) apart from
      # `kill -3786748` (a process group wearing a signal's clothes). -s and -n
      # take the signal as the NEXT word, so `kill -s 0 123` is not target 0.
      KILL_FIRST=1 KILL_SKIP=0
      for KILL_T in "$@"; do
        if [ "$KILL_SKIP" = 1 ]; then KILL_SKIP=0; continue; fi
        # A `-` before an unexpanded value is a process group nobody has read
        #, in first place too: `-s "$SIG"` is the signal's safe spelling.
        case "$KILL_T" in -*\$*|-*\`*) echo "$KILL_MSG" >&2; exit 2 ;; esac
        if [ "$KILL_FIRST" = 1 ]; then
          KILL_FIRST=0
          case "$KILL_T" in
            -s|-n) KILL_SKIP=1; continue ;;
            -[0-9]*) [ "${KILL_T#-}" -le 64 ] 2>/dev/null && continue ;;
            -*) continue ;;
          esac
        fi
        case "$KILL_T" in
          -[0-9]*) echo "$KILL_MSG" >&2; exit 2 ;;
          -*) continue ;;
          # Unexpanded: nobody has read which pid this is, unless it is a job
          # this command started.
          *\$*|*\`*)
            if [[ $KILL_T =~ $KILL_TARGET_RE ]]; then
              KILL_N=${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}
              case "$KILL_SEEN" in *" $KILL_N "*) kill_child_ok "$KILL_N" && continue ;; esac
            fi
            echo "$KILL_MSG" >&2; exit 2 ;;
        esac
        # Pid 0 is every process in the caller's own group.
        [[ $KILL_T =~ ^\+?0+$ ]] && { echo "$KILL_MSG" >&2; exit 2; }
        case " $KILL_ANCESTORS " in *" $KILL_T "*) echo "$KILL_MSG" >&2; exit 2 ;; esac
      done ;;
    pkill|killall)
      shift
      for KILL_T in "$@"; do
        case "$KILL_T" in
          # Every process the user owns includes main. -USR1 is a signal, not -U.
          -u*|-U|--uid|--uid=*|--euid|--euid=*|--user|--user=*) echo "$KILL_MSG" >&2; exit 2 ;;
          -*) continue ;;
        esac
        # The name in any case, and with `[a]` read as `a`.
        KILL_NAME=$(printf '%s' "${KILL_T,,}" | sed -E 's/\[(.)\]/\1/g')
        case "$KILL_NAME" in *claude*|*node*|*orca*) echo "$KILL_MSG" >&2; exit 2 ;; esac
        # ponytail: a pattern is tried against the three bare names only, so a
        # regex needing more of the command line than the name can still pass;
        # match it against main's live `ps` lines if that ever bites.
        # Only "no match" (1) passes: an unreadable pattern (2) is not a pass.
        printf 'claude\nnode\norca\n' | grep -qiE -- "$KILL_T" 2>/dev/null
        [ $? = 1 ] || { echo "$KILL_MSG" >&2; exit 2; }
      done ;;
  esac
done < <(split_search_segments "$CMD")

# Block a raw accumulated pane read (owner ruling 2026-09-13, orchestrator
# invariant 5: keep main's context lean). A pane buffer runs to ~190 KB of TUI
# repaint fragments; one `--limit 400 | tail -130` on 2026-09-13 still put
# 73 KB into main for about forty useful lines, because the fragments are one
# enormous line each and `tail` counts lines. read-verdict.sh and
# `seat.sh collect` do the filtering outside main's context and print the
# findings and the verdict. EVERY variant is blocked, including `--screen` and a
# small `--limit`: the viewport is still TUI fragments, and `terminal list`
# already answers liveness from `lastOutputAt` plus a preview without a pane
# read at all (owner ruling 2026-09-13, "block all variants").
# Match the COMMAND, never the phrase: a commit message or a doc edit that names
# `orca-ide terminal read` is text, and a substring match on the whole command
# line blocked exactly that.
#
# A CLI's options can sit before its subcommand and between the subcommand's
# words (`orca-ide --json terminal read`, `gh run -R owner/repo watch`), so a
# check that reads fixed word positions misses the call. Every check on an
# Orca subcommand reads it through this. $1 = the flags whose value is the NEXT
# word, space-separated; the rest = the words after the command name. Sets SUBCMD to the first two
# non-option words, GLOBALS to the option words and values met on the way, and
# REST to everything after.
# ORCA_VALUED = the Orca options that take a separate value word: the two
# connection options its help lists for every command, and the ones the
# screened commands themselves take. One missing from here hides the
# subcommand behind its value, so a new one is added here, not at a call site.
ORCA_VALUED="--pairing-code --environment --terminal --worktree --repo --cursor --limit --run --timeout-ms"
cli_subcommand() {
  local VALUED=" $1 " W; shift
  GLOBALS=(); SUBCMD=""; REST=("$@")
  while [ ${#REST[@]} -gt 0 ] && [[ $SUBCMD != *' '* ]]; do
    W=${REST[0]}; REST=("${REST[@]:1}")
    if [[ $W != -* ]]; then SUBCMD+=${SUBCMD:+ }$W; continue; fi
    GLOBALS+=("$W")
    if [[ $VALUED == *" $W "* ]] && [ ${#REST[@]} -gt 0 ]; then GLOBALS+=("${REST[0]}"); REST=("${REST[@]:1}"); fi
  done
}
while IFS= read -r LINE; do
  set -f; set -- $(printf '%s' "${LINE:1}" | tr -d "'\""); set +f
  while [ $# -gt 0 ] && [[ ${1-} == *=* && ${1-} != */* ]]; do shift; done
  case "${1-}" in *orca-ide|orca|*/orca) ;; *) continue ;; esac
  shift; cli_subcommand "$ORCA_VALUED" "$@"
  [ "$SUBCMD" = "terminal read" ] || continue
  echo "BLOCKED: raw pane read. Use scripts/read-verdict.sh <handle> [lines] or seat.sh collect for content -- they filter outside main's context. For liveness use scripts/board.sh, or the state block orca-wait.sh prints with every wake." >&2
  exit 2
done < <(split_search_segments "$CMD")
exit 0
