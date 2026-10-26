#!/usr/bin/env bash
# PreToolUse hook (Bash + Edit|Write): block adding a NEW npm dependency
# without the owner's explicit approval. Rule 2: prefer the
# stdlib, an existing helper (shared/, src/utils/), or a few lines of code
# over a new package. A new dependency is the highest-signal mechanical
# proxy for over-engineering -- and a supply-chain surface.
#
# Approval flow: hooks NEVER see inline env prefixes (they are separate
# harness-spawned processes), so approval rides IN the command text, and it
# must be the DOCUMENTED PREFIX form -- anchored at the start so a compound
# command, commit message, or echo that merely mentions the token cannot
# leak approval to anything else in the same command:
#   COMMANDECK_DEP_APPROVED=1 npm install <pkg>
# A package.json edit has no command string to carry that prefix, and in a
# linked worktree node_modules is a symlink to the main checkout's copy, so the
# install form is not always available. There the approval is an EXACT name in
# the environment, the same shape flag-addition-guard uses:
#   COMMANDECK_DEP_APPROVED=<pkg>[,<pkg>]   (.claude/settings.local.json env)
# No prefixes, no wildcards, so approving one package cannot approve its
# neighbour, and an unapproved name in the same edit still blocks.
#
# Deliberately allowed: bare `npm install` / `npm ci` (lockfile-driven),
# version bumps of EXISTING deps in package.json.
# Only the code bash runs is judged (bash_code, below): quoted text and here-document
# bodies are data, so prose or a note that names an install does not block.
#
# THREAT MODEL (charter): this is a TRIPWIRE against sloppiness -- forgetting
# to ask before reaching for a package -- not a security boundary against a
# deliberately evasive operator (who could trivially bypass any text-matching
# hook). Evasion-class review findings are out of scope by design: an install
# handed to another program as text (`bash -c '...'`, `eval '...'`, a body piped
# to a shell, `ssh host '...'`) is not seen. The `i`
# alias stays out of the loose tier (there it made ordinary compounds
# false-block); `npm --prefix <dir> i <pkg>` is caught by dropping npm's valued
# flags before the tight tier reads the command.

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

block() {
  echo "BLOCKED: adding a new dependency ($1) requires the owner's explicit approval first." >&2
  echo "Rule 2: check the stdlib, an already-installed package, or an existing helper in shared/ or src/utils/ before reaching for a new package." >&2
  echo "If the owner has approved this exact package, install it with the token as the COMMAND PREFIX: COMMANDECK_DEP_APPROVED=1 npm install <pkg> (one command per approval; package.json direct edits stay blocked -- the install writes it)." >&2
  echo "If you need this package, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on without it; do not ask main." >&2
  exit 2
}

# bash_code <command> -- the code bash runs, one simple command per line, for the matchers
# below. Words are split the way bash splits them: quoted text, here-strings and here-document
# bodies are data, and `$(...)`, backticks and `<(...)`, `>(...)` are code wherever bash runs
# them (in a bare word, a double-quoted string, a `$((...))`, an unquoted end word's body).
# Code given to another program as text (`bash -c '...'`, `eval '...'`, a body a shell reads)
# is data too: the tripwire's stated limit (see THREAT MODEL). A word with a quoted part prints
# as its text when that is one plain run, else as $QUOTED; a redirection and its target are
# dropped. A command it cannot split (an unclosed quote, an unmatched `$(`, a here-document
# with no end line, python3 missing or failing) is read whole, a quote mark being a word
# break: the worst case is a false block, never a missed install. Past a false block: put the
# text in a file (--body-file, -F).
bash_code() {
  local PROG OUT
  IFS= read -r -d '' PROG <<'PY' || true
import re, sys

ANSI = {'a': '\a', 'b': '\b', 'e': '\x1b', 'E': '\x1b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t',
        'v': '\v', '\\': '\\', "'": "'", '"': '"', '?': '?'}
OUT = []


class Bad(Exception):
    pass


class Word:
    def __init__(self):
        self.text, self.quoted, self.dyn = '', False, False


def arith_end(s, i):
    # The end of the $((...)) at i; the $(...) and backticks inside it run first, so they are read as code.
    depth, j = 2, i + 3
    while j < len(s):
        if s[j] == '(':
            depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0:
                data_subst(s[i + 3:j - 1])
                return j + 1
        j += 1
    raise Bad


def ansi(s, i):
    buf, n = [], len(s)
    while i < n:
        c = s[i]
        if c == "'":
            return ''.join(buf), i + 1
        if c == '\\' and i + 1 < n:
            d = s[i + 1]
            m = re.match(r'x[0-9A-Fa-f]{1,2}|[0-7]{1,3}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}', s[i + 1:])
            if d in ANSI:
                buf.append(ANSI[d])
                i += 2
            elif m:
                g = m.group(0)
                buf.append(chr(int(g[1:], 16) if g[0] in 'xuU' else int(g, 8)))
                i += 1 + len(g)
            else:
                buf.append('\\' + d)
                i += 2
        else:
            buf.append(c)
            i += 1
    raise Bad


def tick(s, i):
    buf, j = [], i + 1
    while True:
        if j >= len(s):
            raise Bad
        if s[j] == '\\' and j + 1 < len(s) and s[j + 1] in '`\\$':
            buf.append(s[j + 1])
            j += 2
        elif s[j] == '`':
            break
        else:
            buf.append(s[j])
            j += 1
    Parser(''.join(buf)).run(None)
    return j + 1


def paren(s, i):
    p = Parser(s, i + 2)
    p.run(')')
    return p.i, p


def data_subst(b):
    i = 0
    while i < len(b):
        if b[i] == '\\':
            i += 2
        elif b.startswith('$((', i):
            i = arith_end(b, i)
        elif b.startswith('$(', i):
            i = paren(b, i)[0]
        elif b[i] == '`':
            i = tick(b, i)
        else:
            i += 1


class Parser:
    def __init__(self, s, i=0):
        self.s, self.i = s, i
        self.cmd, self.word, self.skip, self.pend = [], None, False, []

    def add(self, t, q=False, d=False):
        if self.word is None:
            self.word = Word()
        self.word.text += t
        self.word.quoted |= q
        self.word.dyn |= d

    def endword(self):
        w, self.word = self.word, None
        if w is None:
            return
        if self.skip:
            self.skip = False
        elif not w.quoted and not w.dyn and w.text in ('{', '}'):
            self.endcmd()
        else:
            self.cmd.append(w)

    def endcmd(self):
        self.skip = False
        cmd, self.cmd = self.cmd, []
        if cmd:
            OUT.append(cmd)

    def bodies(self):
        s = self.s
        for tag, quoted, dash in self.pend:
            lines = []
            while True:
                if self.i >= len(s):
                    raise Bad
                j = s.find('\n', self.i)
                line = s[self.i:] if j < 0 else s[self.i:j]
                self.i = len(s) if j < 0 else j + 1
                if (line.lstrip('\t') if dash else line) == tag:
                    break
                lines.append(line)
            if not quoted:
                data_subst('\n'.join(lines))
        self.pend = []

    def heredoc_tag(self):
        s, n = self.s, len(self.s)
        while self.i < n and s[self.i] in ' \t':
            self.i += 1
        tag, quoted = '', False
        while self.i < n and s[self.i] not in ' \t\n;|&()<>':
            c = s[self.i]
            if c == '\\' and self.i + 1 < n:
                tag += s[self.i + 1]
                quoted = True
                self.i += 2
            elif c in '\'"':
                j = s.find(c, self.i + 1)
                if j < 0:
                    raise Bad
                tag += s[self.i + 1:j]
                quoted = True
                self.i = j + 1
            else:
                tag += c
                self.i += 1
        if not tag:
            raise Bad
        return tag, quoted

    def redirect(self):
        s, i = self.s, self.i
        c = s[i]
        if s[i + 1:i + 2] == '(':
            self.i = self.procsub(i)
            return
        w = self.word
        if w is not None and not w.quoted and not w.dyn and w.text.isdigit():
            self.word = None
        else:
            self.endword()
        if s.startswith('<<<', i):
            self.i = i + 3
            self.skip = True
        elif s.startswith('<<', i):
            self.i = i + 2
            dash = s[self.i:self.i + 1] == '-'
            if dash:
                self.i += 1
            tag, quoted = self.heredoc_tag()
            self.pend.append((tag, quoted, dash))
        else:
            self.i = i + 1
            more = '>&|' if c == '>' else '&>'
            for _ in range(2 if c == '>' else 1):
                if s[self.i:self.i + 1] and s[self.i] in more:
                    self.i += 1
            self.skip = True

    def procsub(self, i):
        j = paren(self.s, i)[0]
        self.add('$SUBST', False, True)
        return j

    def dollar(self):
        s, i = self.s, self.i
        if s.startswith("$'", i):
            t, self.i = ansi(s, i + 2)
            self.add(t, True)
        elif s.startswith('$"', i):
            self.i = i + 1
            self.dquote()
        elif s.startswith('$((', i):
            self.i = arith_end(s, i)
            self.add('$ARITH', False, True)
        elif s.startswith('$(', i):
            self.i = paren(s, i)[0]
            self.add('$SUBST', False, True)
        else:
            self.add('$')
            self.i = i + 1

    def dquote(self):
        s, n = self.s, len(self.s)
        i, buf = self.i + 1, []
        self.add('', True)
        while True:
            if i >= n:
                raise Bad
            c = s[i]
            if c == '"':
                i += 1
                break
            if c == '\\' and i + 1 < n:
                d = s[i + 1]
                if d in '"\\$`':
                    buf.append(d)
                elif d != '\n':
                    buf.append('\\' + d)
                i += 2
            elif s.startswith('$((', i):
                i = arith_end(s, i)
                buf.append('$ARITH')
                self.word.dyn = True
            elif s.startswith('$(', i):
                i = paren(s, i)[0]
                buf.append('$SUBST')
                self.word.dyn = True
            elif c == '`':
                i = tick(s, i)
                buf.append('$SUBST')
                self.word.dyn = True
            else:
                buf.append(c)
                i += 1
        self.word.text += ''.join(buf)
        self.i = i

    def run(self, closer):
        s, n = self.s, len(self.s)
        depth = 0
        while True:
            if self.i >= n:
                if closer:
                    raise Bad
                self.endword()
                self.endcmd()
                if self.pend:
                    raise Bad
                return
            i = self.i
            c = s[i]
            if c in ' \t':
                self.endword()
                self.i += 1
            elif c == '\n':
                self.endword()
                self.endcmd()
                self.i += 1
                if self.pend:
                    self.bodies()
            elif c == '\\':
                if s[i + 1:i + 2] == '\n':
                    self.i += 2
                elif i + 1 >= n:
                    raise Bad
                else:
                    self.add(s[i + 1], True)
                    self.i += 2
            elif c == "'":
                j = s.find("'", i + 1)
                if j < 0:
                    raise Bad
                self.add(s[i + 1:j], True)
                self.i = j + 1
            elif c == '"':
                self.dquote()
            elif c == '$':
                self.dollar()
            elif c == '`':
                self.i = tick(s, i)
                self.add('$SUBST', False, True)
            elif c == '#' and self.word is None:
                j = s.find('\n', i)
                self.i = n if j < 0 else j
            elif c in '<>':
                self.redirect()
            elif c == '&' and s[i + 1:i + 2] == '>':
                self.endword()
                self.i = i + 2 + (s[i + 2:i + 3] == '>')
                self.skip = True
            elif c in ';|&':
                self.endword()
                self.endcmd()
                self.i += 1
                if s[self.i:self.i + 1] and s[self.i] in ';|&':
                    self.i += 1
            elif c == '(':
                self.endword()
                self.endcmd()
                depth += 1
                self.i += 1
            elif c == ')':
                self.endword()
                self.endcmd()
                self.i += 1
                if depth:
                    depth -= 1
                elif closer:
                    if self.pend:
                        raise Bad
                    return
            else:
                self.add(c)
                self.i += 1


def show(w):
    if w.dyn:
        return '$QUOTED'
    if not w.quoted:
        return w.text
    return w.text if w.text and not re.search(r'[\s;&|<>()`]', w.text) else '$QUOTED'


try:
    Parser(sys.argv[1]).run(None)
except (Bad, RecursionError):
    sys.exit(3)
for cmd in OUT:
    print(' '.join(show(w) for w in cmd))
PY
  if command -v python3 >/dev/null 2>&1 && OUT=$(python3 -I -c "$PROG" "$1" 2>/dev/null); then
    printf '%s' "$OUT"
  else
    # Read whole: a quote mark is a word break, so `bash -c 'npm ci'` reads as npm ci. A quoted
    # folder with a space becomes $QUOTED, which blocks as a folder the guard cannot read.
    printf '%s' "$1" | sed -E "s/(cd|pushd|--prefix|-C)([[:space:]=]+)\\\\?(\"[^\"']*[[:space:]][^\"']*\"|'[^\"']*[[:space:]][^\"']*')/\1\2\$QUOTED /g" \
      | tr "\"'\`" '   ' | sed 's/<<</ /g'
  fi
}

if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  [ -z "$CMD" ] && exit 0
  # Fast path: every check below needs one of these words in the text, so a command naming none (a
  # plain read) skips the readers, which cost about 50 of its 114 ms per Bash call.
  grep -qE 'npm|yarn|pip|uv' <<<"$CMD" || exit 0
  # Normalize backslash-newline continuations so a split command matches the
  # same as its single-line form.
  CMD=$(printf '%s' "$CMD" | sed -z 's/\\\n/ /g')
  RAN=$(bash_code "$CMD"); SPLIT_OF=$CMD
  # npm ci replaces node_modules. In a worker worktree that is a symlink to the
  # main checkout's shared copy, and npm ci there wiped it for every worktree.
  # Checked before the approval shortcut: no approval covers it. The guard does
  # not follow the shell's folder moves: which `cd` took effect depends on `&&`,
  # `||`, `;`, subshells and exit codes. EVERY npm ci on the line is
  # judged in every folder the line could be in by then -- the payload's cwd and
  # each `cd`/`pushd` target that exists -- or, with `--prefix <dir>`, in that
  # folder under each of them, and passes only when none holds a link. A folder
  # may be quoted. One this cannot read (`$VAR`, a command substitution,
  # `cd -`, `popd`, a pattern, an option) blocks: it could be the linked one.
  # Ceiling: CDPATH is not read, so a relative `cd` it sends elsewhere is missed.
  # It reads the code bash runs (bash_code, above).
  NPM_CI='(^|[;&|([:space:]])(\S*/)?npm([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+ci([[:space:];&|)]|$)'
  if grep -qE "$NPM_CI" <<<"$RAN"; then
    NPM_CWD=$(echo "$INPUT" | jq -r '.cwd // empty'); NPM_CWD=${NPM_CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}
    WORD="\"[^\"]*\"|'[^']*'|[^[:space:]]+"
    WAY_OUT="Run it from the folder itself, or name the folder: npm --prefix <folder> ci"
    NPM_DIRS=("$NPM_CWD"); UNREAD=""
    folders() { # <dir as written> -- every folder it could name, one per line; fails when it cannot be read
      local d=$1 b
      d=${d#[\"\']}; d=${d%[\"\']}
      case "$d" in "~"|"~/"*) d=$HOME${d#\~} ;; esac
      case "$d" in
        # Not a folder name it can look up: a variable, a substitution, another user's home, a
        # pattern, an option, or `-`/`+N`, which go where an earlier command left the shell.
        ""|*'$'*|*'`'*|"~"*|-*|+*|*[*?[{]*) return 1 ;;
        /*) printf '%s\n' "$d" ;;
        *) for b in "${NPM_DIRS[@]}"; do printf '%s\n' "$b/$d"; done ;;
      esac
    }
    while IFS= read -r SEG || [ -n "$SEG" ]; do
      if [[ $SEG =~ (^|[[:space:]])(cd|pushd)[[:space:]]+($WORD) ]]; then
        if TO=$(folders "${BASH_REMATCH[3]}"); then
          while IFS= read -r D; do [ ! -d "$D" ] || NPM_DIRS+=("$D"); done <<<"$TO"
        else
          UNREAD=${BASH_REMATCH[3]}
        fi
      elif [[ $SEG =~ (^|[[:space:]])cd[[:space:]]*$ ]]; then
        NPM_DIRS+=("$HOME")
      elif [[ $SEG =~ (^|[[:space:]])popd([[:space:]]|$) ]]; then
        UNREAD=popd
      fi
      grep -qE "$NPM_CI" <<<"$SEG" || continue
      [ -z "$UNREAD" ] || { echo "BLOCKED: npm ci after a move to $UNREAD, a folder this guard cannot read, so it cannot tell whether node_modules there is the shared copy. $WAY_OUT" >&2; exit 2; }
      CI_DIRS=$(printf '%s\n' "${NPM_DIRS[@]}")
      if [[ $SEG =~ (--prefix|-C)[=[:space:]]+($WORD) ]]; then
        CI_DIRS=$(folders "${BASH_REMATCH[2]}") \
          || { echo "BLOCKED: npm ci into ${BASH_REMATCH[2]}, a folder this guard cannot read, so it cannot tell whether node_modules there is the shared copy. Name the folder in full: \`npm --prefix <folder> ci\`." >&2; exit 2; }
      fi
      while IFS= read -r CI_DIR; do
        [ -L "$CI_DIR/node_modules" ] || continue
        echo "BLOCKED: npm ci in $CI_DIR would replace node_modules, a symlink to the shared copy at $(readlink "$CI_DIR/node_modules"); every worktree using it would lose its modules." >&2
        echo "A worker never reinstalls the shared copy. If package-lock.json changed, main installs in the main checkout." >&2
        [ "$CI_DIR" = "$NPM_CWD" ] || [ "${#NPM_DIRS[@]}" = 1 ] \
          || echo "This line could run it in more than one folder ($(printf '%s, ' "${NPM_DIRS[@]}" | sed 's/, $//')), and the guard does not follow which move took effect." >&2
        echo "For an install meant for another folder: $WAY_OUT" >&2
        exit 2
      done <<<"$CI_DIRS"
    # A redirection's `&` (2>&1, &>) is not a separator.
    done < <(printf '%s' "$RAN" | tr '\n' ';' | sed -E 's/[0-9]*[<>]&[0-9-]*//g; s/&>/>/g; s/(&&|\|\||[;|&()])/\n\1\n/g')
  fi
  # Anchored: approval must be the documented prefix of THE command, exactly
  # =1 -- `=10`, a token quoted mid-command, or a second command chained after
  # an approved one must NOT inherit approval. Approval covers ONE simple
  # command: with separators present, the approved first segment is stripped
  # and the REMAINDER re-enters matching, so `APPROVED=1 npm install ok &&
  # npm install sneaky` still blocks on sneaky.
  if echo "$CMD" | grep -qE '^[[:space:]]*COMMANDECK_DEP_APPROVED=1[[:space:]]'; then
    CMD=$(printf '%s' "$CMD" | tr '\n' ';')
    case "$CMD" in
      *';'*|*'&'*|*'|'*)
        CMD=$(printf '%s' "$CMD" | sed -E 's/^[[:space:]]*COMMANDECK_DEP_APPROVED=1[[:space:]][^;&|]*//')
        ;;
      *) exit 0 ;;
    esac
  fi
  # Two matcher tiers, both fail-closed:
  # TIGHT: manager + optional flags + subcommand (incl. `i`) + flags + pkg.
  # LOOSE: manager + ANY tokens (catches valued flags like --prefix web /
  #        --cwd web / workspace X) + install/add + flags (incl. bare --) + pkg.
  #        `i` is excluded from LOOSE -- too short to survive arbitrary tokens.
  # A redirection is not a package, and neither is what follows a separator:
  # the package position stops at `;`, `&`, `|` and `)`.
  if [ "$CMD" = "$SPLIT_OF" ]; then CMD=$RAN; else CMD=$(bash_code "$CMD"); fi
  # npm's flags that take a value: dropped with the value, so `npm install
  # --prefix web` is a bare install and `npm --prefix web i lodash` is not.
  # Read for npm only: `-w` is a switch in pnpm.
  NPM_CMD=$(sed -E 's/[[:space:]](--prefix|--workspace|-w|-C|--registry|--loglevel|--cache|--userconfig)([[:space:]]+|=)[^;&|[:space:]]+//g' <<<"$CMD")
  TRAIL='([[:space:]]+-{1,2}\S*)*'
  TIGHT_FLAGS='([[:space:]]+-{1,2}[^-[:space:]]\S*)*'
  PKG='[[:space:]]+[^-;&|)[:space:]]'
  NPM_TIGHT='(\S*/)?npm'"$TIGHT_FLAGS"'[[:space:]]+(install|i|add)'"$TRAIL$PKG"
  # LOOSE token runs must NOT cross command separators: with plain \S+ they
  # consumed `&&` and whole commands, so `npm ci && git add .` false-blocked
  # (the `add` belongs to git) -- round-4 regression, one class per tier.
  NPM_LOOSE='(\S*/)?npm([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+(install|add)'"$TRAIL$PKG"
  YARN_LOOSE='(\S*/)?yarn([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+add'"$TRAIL$PKG"
  PNPM_LOOSE='(\S*/)?pnpm([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+add'"$TRAIL$PKG"
  NPMPKG='(\S*/)?npm[[:space:]]+pkg[[:space:]]+set[[:space:]]+\S*[Dd]ependencies'
  if grep -qE "(^|[;&|([:space:]])($NPM_TIGHT|$NPM_LOOSE)" <<<"$NPM_CMD" \
    || grep -qE "(^|[;&|([:space:]])($YARN_LOOSE|$PNPM_LOOSE|$NPMPKG)" <<<"$CMD"; then
    block "via package-manager command"
  fi
  # Python installers. `-r <file>` installs what a requirements file
  # already pins, pip's lockfile-driven form, so it is dropped before matching;
  # a package named beside it still blocks.
  PY_CMD=$(sed -E 's/[[:space:]](-r|--requirement)([[:space:]]+|=)[^;&|[:space:]]+//g' <<<"$CMD")
  PY_ADD='(\S*/)?(pip3?([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+install|uv([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+add)'"$TRAIL"'[[:space:]]+[^-;&|[:space:]]'
  if grep -qE "(^|[;&|[:space:]])$PY_ADD" <<<"$PY_CMD"; then
    block "via package-manager command"
  fi
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
PY_MANIFEST=0
case "${FILE_PATH##*/}" in
  package.json) ;;
  requirements*.txt|pyproject.toml) PY_MANIFEST=1 ;;
  *) exit 0 ;;
esac
# A Codex patch that renames a manifest names the file its text comes from
# (codex-dispatch.sh, source_path); the new name is not on disk yet. Only a
# manifest of the same kind is a baseline: from any other file the edit cannot
# be applied below, and that blocks.
BASE=$FILE_PATH
SRC=$(echo "$INPUT" | jq -r '.tool_input.source_path // empty')
case "${FILE_PATH##*/}:${SRC##*/}" in
  package.json:package.json|requirements*.txt:requirements*.txt|pyproject.toml:pyproject.toml) BASE=$SRC ;;
esac

block_manifest() {
  echo "BLOCKED: adding a new dependency ('$1' in $FILE_PATH) requires the owner's explicit approval first." >&2
  echo "Rule 2: check the stdlib, an already-installed package, or an existing helper in shared/ or src/utils/ before reaching for a new package." >&2
  echo "Once the owner has approved THIS package: COMMANDECK_DEP_APPROVED=$1 (exact, comma-separated for several) in .claude/settings.local.json env, or install it with COMMANDECK_DEP_APPROVED=1 npm install <pkg> as the command prefix." >&2
  echo "If you need this package, record it as a main-only deferred item (one line under ## Main-only (deferred) in the evidence file) and go on without it; do not ask main." >&2
  exit 2
}

# MultiEdit carries an edits[] array; every new_string is concatenated so a
# dependency added through any hunk is still seen. One definition of that
# across every content-screening hook: lib/edit-payload.sh.
#
# SOURCED HERE, BELOW THE BASH BRANCH, deliberately. This hook is registered on
# Bash as well as on the file tools. A load failure must block the write it
# cannot screen -- but blocking every Bash command too would leave no way to run
# the `git checkout` that restores the helper. The Bash branch has already
# returned by this point, so it never depends on the helper.
source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh" 2>/dev/null
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/edit-payload.sh, so it cannot screen this write. Reinstall the plugin (\`claude plugin install commandeck@commandeck\`) and retry." >&2; exit 2; }
CONTENT=$(hook_new_text "$INPUT")
[ -z "$CONTENT" ] && exit 0
APPROVED=",${COMMANDECK_DEP_APPROVED:-},"
# Both readers below place an edit at the first match of its old text. A Codex
# hunk lands where its `@@` anchor says: with no anchor handed over, old text
# that is in the file more than once is refused (readers exit 3), not guessed.
ambiguous() {
  echo "BLOCKED: this edit's old text is in $FILE_PATH more than once, so where it lands cannot be told and it cannot be screened for a new dependency. Give the edit enough of its surrounding lines to match once." >&2
  exit 2
}

# Python manifests: the edit is applied to the file on disk and the
# names the result declares are compared with the names it declares now; a
# name only the result has is new. Names are PEP 503-normalised, so a case or
# separator change is not new. An option line (`-e`, `--index-url`) counts
# whole, so a new one blocks too. A manifest this cannot read blocks.
if [ "$PY_MANIFEST" = 1 ]; then
  NEW=$(printf '%s' "$INPUT" | python3 -c '
import json, os, re, sys
payload = json.load(sys.stdin)
ti = payload.get("tool_input") or {}
path = sys.argv[1]
before = open(path).read() if os.path.exists(path) else ""
def apply(after, at_anchor):
    for e in (ti.get("file_edits") or ti.get("edits") or [ti]):  # file_edits: codex-dispatch.sh, every hunk of this file
        old, new = e.get("old_string"), e.get("new_string")
        if old is None or new is None:
            continue
        at = 0
        for a in e.get("anchors") or []:  # codex-dispatch.sh: the lines a patch hunk lands after
            m = re.compile(r"^[ \t]*%s[ \t]*$" % re.escape(a.strip()), re.M).search(after, at)
            if not m:
                raise SystemExit(1)
            at = m.end()
        if old and old not in after[at:]:
            raise SystemExit(1)
        if old and not at and not e.get("replace_all") and after.count(old) > 1:
            raise SystemExit(3)
        if old:
            after = after[:at] + after[at:].replace(old, new, -1 if e.get("replace_all") else 1)
        elif at_anchor and at:
            after = after[:at] + "\n" + new + after[at:]
        else:
            after = after + new
    return after
# Lines only added have no old text to place them: they are read both at the
# end of the file and right after their anchor, and a name either reading
# declares is new. A reading that does not parse is left to the other.
if payload.get("tool_name") == "Write":
    afters = [ti.get("content") or ""]
else:
    afters = [apply(before, False), apply(before, True)]
def names(text):
    if path.endswith(".toml"):
        import tomllib
        doc = tomllib.loads(text)
        project = doc.get("project", {})
        specs = list(project.get("dependencies", [])) + list(doc.get("build-system", {}).get("requires", []))
        for group in (project.get("optional-dependencies", {}), doc.get("dependency-groups", {})):
            for v in group.values():
                specs += [s for s in v if isinstance(s, str)]
    else:
        specs = [l for l in text.splitlines() if not l.lstrip().startswith("#")]
    out = set()
    for s in specs:
        # An option line, or a requirement that is a URL or a path, has no
        # name to go by: the whole line is what it declares.
        if re.match(r"\s*(-|[./]|[A-Za-z][A-Za-z0-9+.-]*:)", s):
            out.add(s.strip())
            continue
        m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", s)
        if m:
            out.add(re.sub(r"[-_.]+", "-", m.group(1)).lower())
    return out
had, found, read = names(before), set(), False
for after in afters:
    try:
        found |= names(after) - had
        read = True
    except ValueError:
        pass
if not read:
    raise SystemExit(1)
print("\n".join(sorted(found)))
' "$BASE" 2>/dev/null) || {
    [ $? != 3 ] || ambiguous
    echo "BLOCKED: could not read the dependencies $FILE_PATH would declare after this edit, so it cannot be screened for a new one." >&2
    exit 2
  }
  while IFS= read -r NAME; do
    [ -n "$NAME" ] || continue
    case "$APPROVED" in *",$NAME,"*) continue ;; esac
    block_manifest "$NAME"
  done <<<"$NEW"
  exit 0
fi

# What the manifest will SAY once this edit lands is the question, so the edit
# is applied to the file on disk and the result's dependency maps are read.
# Guessing at a fragment's line shapes answered a different one: a "version"-
# shaped metadata key, a script name, or a URL in an unrelated section all read
# as packages, and a real addition written in a shape the regex did not know
# read as nothing.
PY_OK=1 PY_RC=0
CANDIDATES=$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
payload = json.load(sys.stdin)
ti = payload.get("tool_input") or {}
path = sys.argv[1]
def apply(text, at_anchor):
    for e in (ti.get("file_edits") or ti.get("edits") or [ti]):  # file_edits: codex-dispatch.sh, every hunk of this file
        old, new = e.get("old_string"), e.get("new_string")
        if old is None or new is None:
            continue
        at = 0
        for a in e.get("anchors") or []:  # codex-dispatch.sh: the lines a patch hunk lands after
            m = re.compile(r"^[ \t]*%s[ \t]*$" % re.escape(a.strip()), re.M).search(text, at)
            if not m:
                raise SystemExit(1)
            at = m.end()
        if old and old not in text[at:]:
            raise SystemExit(1)
        if old and not at and not e.get("replace_all") and text.count(old) > 1:
            raise SystemExit(3)
        if old:
            text = text[:at] + text[at:].replace(old, new, -1 if e.get("replace_all") else 1)
        elif at_anchor and at:
            text = text[:at] + "\n" + new + text[at:]
        else:
            text = text + new
    return text
# Lines only added are read both at the end of the file and right after their
# anchor, as in the Python reader above; a reading that is not JSON is left to
# the other, and with neither the line-shape screen below decides.
if payload.get("tool_name") == "Write":
    texts = [ti.get("content") or ""]
else:
    text = open(path).read()
    texts = [apply(text, False), apply(text, True)]
keys, read = set(), False
for text in texts:
    try:
        m = json.loads(text)
    except ValueError:
        continue
    read = True
    for k in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        v = m.get(k)
        if isinstance(v, dict):
            keys.update(v)
if not read:
    raise SystemExit(5)  # the edit applied, and what it leaves is not JSON (host issue 3029)
print("\n".join(sorted(keys)))
' "$BASE" 2>/dev/null) || { PY_RC=$?; [ "$PY_RC" != 3 ] || ambiguous; PY_OK=0; }

if [ "$PY_OK" = 0 ]; then
  # The edit could not be applied to the file on disk (its old_string is gone,
  # or the result is not JSON), so fall back to line-shape matching rather than
  # letting an unreadable manifest change through.
  # Spec shapes: semver/ranges (incl. >= <=), dist-tags as a single word,
  # *, and workspace/file/npm/link/github/git/URL forms. "version" is the
  # only same-shaped top-level key -- excluded by name. A false block on a
  # metadata fragment is fail-closed and loud; rewriting the full file via
  # Write takes the structural path above.
  CANDIDATES=$(echo "$CONTENT" \
    | grep -oE '"[@a-zA-Z0-9][@a-zA-Z0-9._/-]*"[[:space:]]*:[[:space:]]*"(workspace:|file:|npm:|link:|github:|git\+|https?:|\*|(>=|<=|[~^><])?[0-9]|[A-Za-z][A-Za-z0-9._-]*")[^"]*"?' \
    | sed -E 's/^"([^"]+)".*/\1/' \
    | grep -vxE 'version')
fi

# A brand-new package.json is a new dependency surface in itself: every
# candidate counts as new.
if [ ! -f "$BASE" ]; then
  for NAME in $CANDIDATES; do
    case "$APPROVED" in *",$NAME,"*) continue ;; esac
    block "'$NAME' in NEW file $FILE_PATH"
  done
  exit 0
fi

# With something to screen (host issue 3029), the manifest on disk and the one the edit would leave must both be JSON.
# Neither is, and the line-shape screen above then names a metadata key as a package: a block that tells the worker
# the wrong thing. A Write replaces the file, so only its own content counts.
if [ -n "$CANDIDATES" ]; then
  if [ "$TOOL" != Write ] && ! jq empty "$BASE" >/dev/null 2>&1; then
    echo "BLOCKED: $FILE_PATH is not valid JSON, so this edit cannot be screened for a new dependency; fix the file first (a Write of valid JSON is screened)." >&2
    exit 2
  fi
  if [ "$PY_RC" = 5 ]; then
    echo "BLOCKED: this edit leaves $FILE_PATH as invalid JSON; make the edit keep it valid." >&2
    exit 2
  fi
fi

# "Existing" means present in a DEPENDENCY MAP of the on-disk manifest --
# a whole-file grep counted a script or metadata key with the same name
# (e.g. "build") as an existing dependency.
for NAME in $CANDIDATES; do
  case "$APPROVED" in *",$NAME,"*) continue ;; esac
  if ! jq -e --arg n "$NAME" '
       ((.dependencies // {}) + (.devDependencies // {}) +
        (.optionalDependencies // {}) + (.peerDependencies // {})) | has($n)' \
       "$BASE" >/dev/null 2>&1; then
    block_manifest "$NAME"
  fi
done

exit 0
