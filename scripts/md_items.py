"""The one Markdown reader for plan-check.sh --issue-cases.

  python3 -I md_items.py cases   -- issue body in $PC_BODY; prints `<Fix|Done|Body> <k> <first 80 chars>` per case

It reads ATX and setext headings and list items (`-`, `+`, `*`, 1-9 digits then `.` or `)`), top-level by the open
item's content column, and keeps no fence state: a fence line is never a block, so no heading is ever swallowed.
Fail closed: a shape it does not model where it could hide or reset a case is a refusal (exit 2) naming the line,
never a lost case. Inside a list item only plain text, blank lines and nested sub-bullets are taken; in a Fix or
Done means section only items, sub-bullets, plain text, blank lines and the level 1-2 heading that ends it.
"""
import os
import re
import sys

ATX = re.compile(r' {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$')
FENCELINE = re.compile(r' *(`{3,}|~{3,})')
SETEXT = re.compile(r' {0,3}(=+|-+)[ \t]*$')
BREAK = re.compile(r' {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$')
ITEM = re.compile(r'( *)([-+*]|\d{1,9}[.)])([ \t]+|$)(.*)')
HTML = re.compile(r'<[A-Za-z/!?]')
# Marker-like: 1-3 characters with no letter, digit or Markdown block opener, or one letter or a digit run, maybe in
# parentheses, then `.` or `)`; followed by a space and text.
LOOKS = re.compile(r' {0,3}(?:[^\sA-Za-z0-9>|<\[!`#~=_\\]{1,3}|\(?(?:[A-Za-z]|\d+)[.)])[ \t]+\S')
IN_SECTION = 'in a Fix or Done means section, which this reader does not parse'


def opener(rest, prev_para):
    """The block a line starts once its indentation is removed, or None for plain text."""
    if FENCELINE.match(rest):
        return 'code fence'
    if ATX.match(rest):
        return 'heading'
    if prev_para and SETEXT.match(rest):
        return 'setext underline'
    if BREAK.match(rest):
        return 'thematic break'
    if rest.startswith('>'):
        return 'quote line'
    if rest.startswith('|'):
        return 'table row'
    if HTML.match(rest):
        return 'HTML line'
    return None


def blocks(lines):
    """Yields (kind, n, text, extra) per line: ('heading', n, text, level), ('setext', n, line, level),
    ('item', n, text, top), ('blank', n, '', None), ('text', n, line, None), ('odd', n, line, None) for a marker-like
    line at top-level indent that is no item, ('tab', n, line, None) for a tab in the indentation, ('nested', n, line,
    kind) for any block inside an open list item but a sub-bullet, and ('shape', n, line, kind) for a top-level line
    the reader does not model (a fence line, a level 3+ heading, a quote, a table row, an HTML line, a setext
    underline, a thematic break, indented code). Callers decide where 'shape' and 'tab' are refused."""
    opencol = None
    prev_blank = True
    prev_para = False
    for n, line in enumerate(lines, 1):
        if not line.strip():
            yield ('blank', n, '', None)
            prev_blank, prev_para = True, False
            continue
        lead = re.match(r'[ \t]*', line).group(0)
        m = ITEM.match(line)
        if '\t' in lead or (m and '\t' in m.group(3)):
            yield ('tab', n, line, None)
            prev_blank, prev_para = False, True
            continue
        indent = len(lead)
        if opencol is not None and indent < opencol and prev_blank:
            opencol = None
        inside = opencol is not None and indent >= opencol
        if inside:
            rest = line[opencol:]
            if prev_blank and indent >= opencol + 4:
                kind = 'indented code'
            elif m:
                yield ('item', n, m.group(4), False)
                prev_blank, prev_para = False, False
                continue
            else:
                kind = opener(rest.lstrip(' '), prev_para)
            if kind:
                yield ('nested', n, line, kind)
                prev_blank, prev_para = False, False
                continue
            yield ('text', n, line, None)
            prev_blank, prev_para = False, True
            continue
        if indent >= 4:
            yield ('shape', n, line, 'indented code' if prev_blank else 'indented line')
            prev_blank, prev_para = False, True
            continue
        a = ATX.match(line)
        if a:
            opencol = None
            yield ('heading', n, (a.group(2) or '').strip(), len(a.group(1)))
            prev_blank, prev_para = False, False
            continue
        s = SETEXT.match(line)
        if s and prev_para:
            yield ('setext', n, line, 1 if s.group(1)[0] == '=' else 2)
            prev_blank, prev_para = False, False
            continue
        kind = opener(line.lstrip(' '), False)
        if kind:
            yield ('shape', n, line, kind)
            prev_blank, prev_para = False, False
            continue
        if m:
            pad = len(m.group(3)) if m.group(4) else 1
            opencol = indent + len(m.group(2)) + (pad if pad <= 4 else 1)
            yield ('item', n, m.group(4), True)
            prev_blank, prev_para = False, False
            continue
        yield ('odd' if LOOKS.match(line) else 'text', n, line, None)
        prev_blank, prev_para = False, True


def flat(lines):
    """blocks() with each setext underline folded into the line above it as a heading; the underline is kept as a
    'shape' when the heading it makes would fall inside a counted section."""
    out = []
    for b in blocks(lines):
        if b[0] == 'setext':
            if out and out[-1][0] in ('text', 'odd'):
                k, n, text, _ = out.pop()
                out.append(('heading', n, text.strip(), b[3], b))
            continue
        out.append(b)
    return out


def cases(body):
    lines = body.replace('\r\n', '\n').split('\n')
    bl = flat(lines)
    secs, cur = [], None
    for b in bl:
        if b[0] == 'heading':
            if cur is not None and len(b) > 4:
                n = b[4][1]
                return None, 'line %d: a setext underline %s: %s' % (n, IN_SECTION, lines[n - 1].strip()[:60])
            if cur is not None and b[3] > 2:
                return None, 'line %d: a heading %s: %s' % (b[1], IN_SECTION, lines[b[1] - 1].strip()[:60])
            m = re.match(r'(fix|done means)', b[2], re.I) if b[3] == 2 else None
            cur = [('Fix' if m.group(1).lower() == 'fix' else 'Done'), []] if m else None
            if cur:
                secs.append(cur)
            continue
        if cur is not None:
            cur[1].append(b)
    counted = secs or [['Body', [b for b in bl if b[0] != 'heading']]]
    # A block inside a list item is refused wherever it is; the rest only where its section counts cases.
    for b in bl:
        if b[0] == 'nested':
            return None, 'line %d: a %s inside a list item, which this reader does not parse: %s' % (b[1], b[3], b[2].strip()[:60])
    count, out = {}, []
    for kind, body_blocks in counted:
        for b in body_blocks:
            if b[0] == 'tab':
                return None, 'line %d: a tab in the indentation, which this reader does not measure: %s' % (b[1], b[2].strip()[:60])
            if b[0] == 'shape' and kind != 'Body':
                return None, 'line %d: a %s %s: %s' % (b[1], b[3], IN_SECTION, b[2].strip()[:60])
            if b[0] == 'odd':
                return None, 'line %d under %s looks like a list item this reader does not know: %s' % (b[1], kind, b[2].strip()[:60])
        items = [b[2] for b in body_blocks if b[0] == 'item' and b[3]]
        if not items:
            items = [b[2] for b in body_blocks if b[0] in ('text', 'shape')][:1]
        if not items:
            return None, '%s has no case' % kind
        for item in items:
            count[kind] = count.get(kind, 0) + 1
            out.append('%s %d %s' % (kind, count[kind], ' '.join(item.split())[:80]))
    return out, None


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else ''
    if mode == 'cases':
        res, why = cases(os.environ['PC_BODY'])
        if why:
            print(why, file=sys.stderr)
            sys.exit(2)
        print('\n'.join(res))
    else:
        print('usage: md_items.py cases', file=sys.stderr)
        sys.exit(2)
