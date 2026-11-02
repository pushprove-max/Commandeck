#!/usr/bin/env python3
"""shell_reads.py <command> <cwd> [proof] -- which files a shell command reads.

Prints one line per file, tab separated, to standard output:
  dump<TAB><path>    a file the command prints whole: cat and the other DUMP tools
                     (which print every line in another form), a head, tail or sed
                     whose window is not understood or covers the file, tail +N,
                     a search whose pattern matches every line, jq ., json.tool,
                     git show <rev>:<file>
  read<TAB><path>    an existing file another reading tool shows part of: a head,
                     tail or `sed -n a,bp` window shorter than the file, `sed Nq`,
                     a search, jq <filter>, diff
  saved<TAB><path><TAB><program><TAB><bound>
                     a word under */tool-results/* in a stage that is no echo or
                     printf; a quoted word is kept whole, spaces included. The
                     bound is the digits of rg/grep `-m N` or head/tail `-n N`
                     over one regular file, else `-`

Run it as `python3 -I shell_reads.py`. Users: generated-read-guard.sh (dump,
saved) and read-record.sh (dump, read, with `proof`). It judges the command text
only: a path held in a variable or read by a script the command runs is not seen,
and a search's pattern only for the shapes that match every line. A command the
lexer cannot read (an open quote) gives no paths, and so does any failure: a guard
that wraps this must not stop every Bash call on a crash.

A guard asks what the command could read, so a branch counts. `proof` asks what the
agent saw: a command with a branch, a substitution or a here-document gives no
paths, nor does a stage whose output goes to a file or a pipe. Only the text of the
command is read, so proof is an allowlist of what that text can settle: a SHOW tool
with no flag but -n on a non-empty file, or a window that overlaps a non-empty file.
A search, jq, diff, git show and every other tool may print nothing and prove
nothing, nor does a word with a glob, $ or ~, or a cd the reader cannot follow.
A lost proof costs one more read.
"""
import glob
import os
import re
import shlex
import subprocess
import sys

DUMP = {'cat', 'nl', 'tac', 'less', 'more', 'bat', 'batcat', 'awk', 'gawk', 'mawk',
        'cut', 'sort', 'uniq', 'od', 'xxd', 'strings', 'column'}
SHOW = {'cat', 'nl', 'tac', 'less', 'more', 'bat', 'batcat'}
SEARCH = {'grep', 'egrep', 'fgrep', 'rg'}
QUIET = {'echo', 'printf'}
PREFIX = ('env', 'command', 'time', 'exec', 'builtin', 'if', 'elif', 'then', 'else', 'while', 'until', 'do', '!', '{')
CONTROL = {'if', 'elif', 'then', 'else', 'fi', 'for', 'while', 'until', 'do', 'done', 'case', 'esac', 'function',
           '{', '}', '!', 'exit', 'return', 'break', 'continue', 'exec'}
EVERY_LINE = re.compile(r'\^?(\.\*?)?\$?')
SHORT = {'-n': 'l', '--lines': 'l', '-c': 'c', '--bytes': 'c'}


def segments(cmd):
    """Each stage of the command: (its words, the operator after it)."""
    lex = shlex.shlex(cmd.replace('\n', ' ; '), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    toks = list(lex)  # ValueError on an open quote: the caller reads no paths
    segs, cur = [], []
    for t in toks:
        if t and set(t) <= set(';&|()'):
            segs.append((cur, t))
            cur = []
        else:
            cur.append(t)
    segs.append((cur, ''))
    return segs


def top(d):
    out = subprocess.run(['git', '-C', d, 'rev-parse', '--show-toplevel'],
                         capture_output=True, text=True).stdout.strip()
    return out or d


def expand(w):
    return os.path.expandvars(os.path.expanduser(w))


def emit(kind, path, *extra):
    if '\n' not in path and '\t' not in path:
        print(kind, path, *extra, sep='\t')


# Search flags that change neither which lines print nor how many: with them and -m N, the output is at most N lines.
SEARCH_PLAIN = {'-i', '--ignore-case', '-S', '--smart-case', '-F', '--fixed-strings', '-w', '--word-regexp',
                '-n', '--line-number', '-N', '--no-line-number', '-H', '--with-filename', '--no-heading', '-s', '--no-messages'}


def line_bound(tool, words, cwd):
    """The line cap a rg/grep `-m N` or a head/tail `-n N` puts on the output, as digits; '-' for any other shape.
    An allowlist: only shapes read in full are bounded. head/tail take their last count (as the tools do) and no
    byte or +N form; a search takes the last -m and refuses any flag outside SEARCH_PLAIN, so a context flag
    (-A/-B/-C) or an unknown one cannot print past the cap. Both caps count per file, so the one operand must be
    a single regular file (one_file)."""
    if tool in ('head', 'tail'):
        window = head_tail_window(words)
        counted = any(w.startswith('-') and w != '-' for w in words)  # a bare head/tail keeps no bound, as before
        if not (counted and window and window[2] == 'l'):
            return '-'
        # head_tail_window took the word after each -n/-c/--lines/--bytes as its count, so it is no operand
        operands = [w for j, w in enumerate(words) if not w.startswith('-') and not (j and words[j - 1] in SHORT)]
        return str(window[1]) if one_file(operands, cwd) else '-'
    if tool not in SEARCH:
        return '-'
    bound, i, opts, positional, pattern_given = '-', 0, True, [], False
    while i < len(words):
        w = words[i]
        i += 1
        if not opts or not w.startswith('-') or w == '-':
            positional.append(w)
            continue
        if w == '--':
            opts = False
            continue
        m = re.fullmatch(r'-m(\d+)|--max-count=(\d+)', w)
        if m:
            bound = m[1] or m[2]
        elif w in ('-m', '--max-count') and i < len(words) and words[i].isdigit():
            bound, i = words[i], i + 1
        elif w in ('-e', '--regexp') and i < len(words):
            i, pattern_given = i + 1, True
        elif w not in SEARCH_PLAIN:
            return '-'
    operands = positional if pattern_given else positional[1:]
    return bound if one_file(operands, cwd) else '-'


def one_file(operands, cwd):
    """A per-file cap bounds the command only over one regular file named literally. A glob, brace, variable or
    tilde (which the shell may expand to many words), a directory, a second operand or none (rg then searches
    the folder it runs in) repeats the cap per file."""
    return (len(operands) == 1 and not any(c in operands[0] for c in '*?[{$`~')
            and os.path.isfile(os.path.join(cwd, operands[0])))


def head_tail_window(words):
    """(first, last, unit): last is a count from the start or the end. None for any shape not fully understood."""
    n, unit, i = 10, 'l', 0
    while i < len(words):
        w = words[i]
        i += 1
        if w.startswith('+'):
            return None
        if not w.startswith('-'):
            continue
        m = re.fullmatch(r'-(\d+)', w)
        if m:
            n, unit = int(m[1]), 'l'
            continue
        m = re.fullmatch(r'(-[nc]|--lines|--bytes)(?:=|(?<=-[nc]))(\d+)', w)
        if m:
            n, unit = int(m[2]), SHORT[m[1]]
            continue
        if w in SHORT and i < len(words) and words[i].isdigit():
            n, unit = int(words[i]), SHORT[w]
            i += 1
            continue
        return None
    return 1, n, unit


def sed_window(words):
    """(first, last, 'l') for `sed -n a[,b]p` and `sed Nq`, the two scripts that bound the output; else None."""
    flags = [w for w in words if w.startswith('-')]
    rest = [w for w in words if not w.startswith('-')]
    if not rest or not set(flags) <= {'-n', '--quiet', '--silent', '-e', '-ne'} or flags.count('-e') + flags.count('-ne') > 1:
        return None
    if set(flags) - {'-e'}:
        m = re.fullmatch(r'(\d+)(?:,(\d+))?p', rest[0])
        return (int(m[1]), max(int(m[1]), int(m[2] or m[1])), 'l') if m else None
    m = re.fullmatch(r'(\d+)q', rest[0])
    return (1, int(m[1]), 'l') if m else None


def size_of(path, unit):
    with open(path, 'rb') as f:
        data = f.read()
    return len(data) if unit == 'c' else data.count(b'\n') + (0 if data.endswith(b'\n') or not data else 1)


def covers(window, path):
    """The window prints the whole file, as a Read whose limit reaches its end."""
    first, last, unit = window
    return first <= 1 and last >= size_of(path, unit)


def shown(tool, words, window, path, nfiles):
    """The command text alone shows some of this file reached the agent."""
    if os.path.getsize(path) == 0:
        return False
    if tool in SHOW:
        return set(w for w in words if w.startswith('-')) <= {'-n'}
    if not window or (tool == 'sed' and nfiles != 1):  # sed numbers its lines across all its files
        return False
    first, last, unit = window
    return 1 <= first <= size_of(path, unit) and last >= 1


def search_kind(words):
    flags = [w for w in words if w.startswith('-')]
    rest = [w for w in words if not w.startswith('-')]
    pattern = rest[0] if rest else 'x'
    for i, w in enumerate(words[:-1]):
        if w in ('-e', '--regexp'):
            pattern = words[i + 1]
    invert = any(re.fullmatch(r'-[A-Za-z]*v[A-Za-z]*|--invert-match', f) for f in flags)
    return 'dump' if invert or EVERY_LINE.fullmatch(pattern) else 'read'


def unproved(segs, cmd):
    return (any(x in cmd for x in ('$(', '`', '<<'))
            or re.search(r'(^|\s)\d+\s+[<>]', cmd)  # `2 >x` is stdout to a file, and the lexer reads it as `2>x`
            or any(seg[:1] in (['cd'], ['pushd'], ['popd']) and (seg[0] != 'cd' or len(seg) != 2) for seg, _ in segs)
            or any('&&' in op or '||' in op or '(' in op for _, op in segs)
            or any(seg and seg[0] in CONTROL for seg, _ in segs))


def main(cmd, cwd, proof=False):
    all_segs = segments(cmd)
    if proof and unproved(all_segs, cmd):
        return
    for seg, after in all_segs:
        while seg and (re.match(r'^[A-Za-z_]\w*=', seg[0]) or seg[0] in PREFIX):
            seg = seg[1:]
        if not seg:
            continue
        tool, args = os.path.basename(seg[0]), seg[1:]
        if tool == 'cd' and len(args) == 1:
            cwd = os.path.join(cwd, expand(args[0]))
            continue
        words, skip, hidden = [], False, '|' in after
        for i, a in enumerate(args):
            if skip:
                skip = False
                continue
            if a and set(a) <= set('<>&'):
                skip = '>' in a or a in ('<<', '<<<')
                to_stderr = i > 0 and args[i - 1] == '2'
                to_stdout = a == '>&' and args[i + 1:i + 2] == ['1']
                hidden = hidden or ('>' in a and not to_stderr and not to_stdout)
                continue
            words.append(a)
        if proof and (hidden or any(c in w for w in words for c in '*?[$~')):
            continue  # the lexer drops quotes, so a word the shell may not expand is a guess at the path
        if tool not in QUIET and not proof:
            for w in words:
                if '/tool-results/' in expand(w) and not w.startswith('-'):
                    emit('saved', os.path.normpath(os.path.join(cwd, expand(w))), tool, line_bound(tool, words, cwd))
        window = None
        if tool in DUMP:
            kind = 'dump'
        elif tool == 'sed':
            if any(w.startswith(('-i', '--in-place')) for w in words):
                continue  # writes the file and prints none of it
            window = sed_window(words)
            kind = 'read' if window else 'dump'
        elif tool in ('head', 'tail'):
            window = head_tail_window(words)
            kind = 'read' if window else 'dump'
        elif tool == 'jq':
            kind = 'dump' if {'.', '.[]', '..'} & set(words) else 'read'
        elif tool.startswith('python'):
            kind = 'dump' if 'json.tool' in words else None
        elif tool == 'git' and words[:1] and words[0] in ('show', 'cat-file'):
            if proof:
                continue  # an older revision says nothing of the file on disk
            root = top(cwd)
            for w in words[1:]:
                if ':' in w and not w.startswith('-'):
                    p = w.split(':', 1)[1]
                    emit('dump', os.path.realpath(os.path.join(cwd if p.startswith(('./', '../')) else root, p)))
            continue
        elif tool in SEARCH:
            kind = search_kind(words)
        elif tool == 'diff':
            kind = 'read'
        else:
            kind = None
        if kind is None:
            continue
        files = []
        for w in words:
            if w.startswith('-'):
                continue
            hits = glob.glob(os.path.join(cwd, w)) if any(c in w for c in '*?[') else [os.path.join(cwd, expand(w))]
            files += [p for p in hits if os.path.isfile(p)]
        for p in files:
            if not proof or shown(tool, words, window, p, len(files)):
                emit('dump' if window and covers(window, p) else kind, os.path.realpath(p))


if __name__ == '__main__':
    try:
        main(sys.argv[1], sys.argv[2], sys.argv[3:] == ['proof'])
    except Exception:
        pass
    sys.exit(0)
