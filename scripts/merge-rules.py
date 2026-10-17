#!/usr/bin/env python3
"""merge-rules.py <template, or - for stdin> [--against <file>]... [--exclude <glob>]... [--drop <id>]...
                [--keep <id>]... [--block] [--report | --units | --sources]

The plugin's rules file <template>, less every rule the owner already has. A
rule is one unit of Markdown: a top-level bullet with its indented lines, a
paragraph, or a fenced block; headings only frame them. Two rules are the same
when their text is equal once case and spacing are set aside: code decides,
exactly, and nothing fuzzy is guessed (a path, a code span or a flag that
differs makes a different rule, so both are kept). A rule the owner chose to keep
their own wording for is named by its id (--drop), the first 8 hex digits of the
sha1 of that normalised text; one they chose to load anyway is named by --keep,
which beats a --drop of an id it was made from. Text inside a commandeck
marked block in an --against file is the plugin's own, so it never counts
as the owner's. An --against rules file whose frontmatter names `paths:` loads only for those
paths, so it counts for nothing, and so does one whose frontmatter this does
not read for sure (an indented key, a list, anything odd); of a
main-session.md only the part above "## Details (not injected)" loads, so
only that part counts. An --against file an --exclude glob matches (a
claudeMdExcludes entry: ** spans any folders, none too; * and ? stay inside
one; [...] and {a,b} as usual) is not loaded, so it counts for nothing.
--block cuts only the rules inside the template's commandeck merge block
(an owner's file setup merged into) and prints the rest as it is.

Prints the template less those rules (a heading left with no rule under it goes
too); --report prints the counts and each rule left out; --units prints every
rule of the template as "<id><TAB><its first line>"; --sources prints each
--against file that counts, one a line.
"""
import hashlib
import re
import sys

BLOCK = re.compile(r"<!-- commandeck:[^>]*?begin -->.*?<!-- commandeck:[^>]*?end -->\n?", re.S)
BULLET = re.compile(r"([-*+]|\d+[.)])\s")
FRONT = re.compile(r"\A---[ \t]*\n(.*?)\n---[ \t]*(\n|\Z)", re.S)
MERGE = re.compile(r"^<!-- commandeck:merge:begin -->\n(.*?)^<!-- commandeck:merge:end -->$", re.S | re.M)
# A root `key: value` read for sure: the key plain or quoted with no escapes, the value empty, quoted, or plain
# with no indicator, colon, bracket or comment sign in it; a trailing comment is allowed.
KEY = re.compile(r"""(?:"([^"\\]*)"|'([^']*)'|(\w[\w .-]*?))[ \t]*:"""
                 r"""(?:[ \t]+(?:"[^"\\]*"|'[^']*'|[^\s"'&*!|>%@`{}\[\]#,?:-][^:#{}\[\]]*?))?[ \t]*(?:[ \t]#.*)?$""")


def scoped(fm):
    """False only when YAML frontmatter is read for sure and has no paths key: every line blank, a comment, or a
    root key: value (KEY), no key twice. Anything else (an indented line, a list, a flow or block value, an
    anchor, a merge key) could hide a paths key, so it scopes the file: a duplicate rule beats a lost one."""
    keys = set()
    for line in fm.split("\n"):
        if not line.strip() or line.startswith("#"):
            continue
        m = KEY.match(line)
        if not m:
            return True
        key = next(g for g in m.groups() if g is not None).strip()
        if key in keys:
            return True
        keys.add(key)
    return "paths" in keys


def glob_re(p):
    """A claudeMdExcludes glob as a regex over the whole path; dot files match, which only ever counts less."""
    out, i = "", 0
    while i < len(p):
        c = p[i]
        if p.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
            continue
        if p.startswith("**", i):
            out, i = out + ".*", i + 2
            continue
        j = p.find("]", i + 2) if c == "[" else p.find("}", i) if c == "{" else -1
        if c == "*":
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        elif c == "[" and j > 0:
            body = p[i + 1:j]
            out += "[" + ("^" + body[1:] if body[:1] in "!^" else body).replace("\\", "\\\\") + "]"
            i = j
        elif c == "{" and j > 0:
            out += "(?:" + "|".join(glob_re(a) for a in p[i + 1:j].split(",")) + ")"
            i = j
        else:
            out += re.escape(c)
        i += 1
    return out


def excluded(path, globs):
    for g in globs:
        neg = g.startswith("!")
        if bool(re.fullmatch(glob_re(g[1:] if neg else g), path, re.S)) != neg:
            return True
    return False


def norm(lines):
    text = "\n".join(lines).strip()
    text = BULLET.sub("", text, count=1) if BULLET.match(text) else text
    return re.sub(r"\s+", " ", text.lower()).strip()


def rid(lines):
    return hashlib.sha1(norm(lines).encode()).hexdigest()[:8]


# A reworded rule gets a new id, and an owner's saved --drop names the old one. Each new id here is left
# out when every id it was made from is (a duplicate rule beats a lost one), unless the owner kept it by its
# own id: that answer is newer. Add a line per reworded rule.
MADE_FROM = {
    # 0.7.2 main-session.md
    "607f18a2": ("18cd2c62", "8fc96d58"), "06c5d1a6": ("58d81ff4", "8fc96d58"), "1cf7c669": ("1f85d44e",),
    "2fac1916": ("57eadb12",), "f949bcf5": ("32d46d9b",), "8aa8b56d": ("c99218c7",), "0c39c843": ("f0729b8f",),
    "8ecde936": ("00709c21",), "0a0832e3": ("f0558144",),
    # 0.10.0 main-session.md
    "38ccaed2": ("6743a4ac",),
    # 0.13.2 main-session.md
    "d3ad81e3": ("871dfc54",),
}


def dropped(i, drop, keep):
    return i not in keep and (i in drop or (i in MADE_FROM and all(dropped(o, drop, keep) for o in MADE_FROM[i])))


def parse(text):
    """[(kind, lines)]: kind is h (heading), u (a rule) or b (a blank line)."""
    out, cur, fence = [], None, False

    def flush():
        nonlocal cur
        if cur:
            out.append(("u", cur))
        cur = None

    for line in text.split("\n"):
        if fence:
            cur.append(line)
            if line.lstrip().startswith("```"):
                fence = False
                flush()
            continue
        if line.lstrip().startswith("```"):
            flush()
            cur, fence = [line], True
        elif not line.strip():
            flush()
            out.append(("b", [line]))
        elif line.startswith("#"):
            flush()
            out.append(("h", [line]))
        elif BULLET.match(line):
            flush()
            cur = [line]
        elif cur is None:
            cur = [line]
        else:
            cur.append(line)
    flush()
    return out


def main(argv):
    if not argv or (argv[0].startswith("-") and argv[0] != "-"):
        sys.exit(__doc__)
    template, against, exclude, drop, keep, mode, block = argv[0], [], [], set(), set(), "text", False
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ("--against", "--exclude", "--drop", "--keep") and i + 1 < len(argv):
            {"--against": against.append, "--exclude": exclude.append, "--drop": drop.add, "--keep": keep.add}[a](argv[i + 1])
            i += 2
        elif a in ("--report", "--units", "--sources"):
            mode = a[2:]
            i += 1
        elif a == "--block":
            block = True
            i += 1
        else:
            sys.exit(__doc__)
    theirs = {}
    for f in against:
        if excluded(f, exclude):
            continue
        try:
            text = open(f, encoding="utf-8-sig").read()
        except OSError:
            continue
        fm = FRONT.match(text)
        if fm:
            if scoped(fm.group(1)):
                continue
            text = text[fm.end():]
        elif re.match(r"\s*---[ \t]*\n", text):
            continue  # frontmatter that never closes, or not on line 1: not read for sure
        if mode == "sources":
            print(f)
            continue
        if f.endswith("main-session.md"):
            text = re.split(r"^## Details \(not injected\)", text, maxsplit=1, flags=re.M)[0]
        for kind, lines in parse(BLOCK.sub("", text)):
            if kind == "u":
                theirs.setdefault(norm(lines), f)
    if mode == "sources":
        return
    text = sys.stdin.read() if template == "-" else open(template, encoding="utf-8-sig").read()
    head = tail = ""
    if block:
        m = MERGE.search(text)
        if not m:
            sys.stdout.write(text)
            return
        head, text, tail = text[:m.start(1)], m.group(1), text[m.end(1):]
    items = parse(text)
    if mode == "units":
        for kind, lines in items:
            if kind == "u":
                print(f"{rid(lines)}\t{lines[0].strip()[:100]}")
        return
    gone, same, mine = set(), [], []
    for j, (kind, lines) in enumerate(items):
        if kind == "u" and norm(lines) in theirs:
            gone.add(j)
            same.append((theirs[norm(lines)], lines))
        elif kind == "u" and dropped(rid(lines), drop, keep):
            gone.add(j)
            mine.append(lines)
    if mode == "report":
        n = sum(1 for k, _ in items if k == "u") - len(gone)
        print(f"{n} plugin rules kept, {len(same)} already in your files (left out), {len(mine)} where you keep your own (left out)")
        for f, lines in same:
            print(f"  already in {f}: {lines[0].strip()[:90]}")
        for lines in mine:
            print(f"  you keep yours [{rid(lines)}]: {lines[0].strip()[:90]}")
        return
    # A heading goes too when every rule under it (up to the next heading of its level or above) went.
    level = lambda line: len(line) - len(line.lstrip("#"))
    for j, (kind, lines) in enumerate(items):
        if kind != "h":
            continue
        under = []
        for k in range(j + 1, len(items)):
            if items[k][0] == "h" and level(items[k][1][0]) <= level(lines[0]):
                break
            if items[k][0] == "u":
                under.append(k)
        if under and all(k in gone for k in under):
            gone.add(j)
    out = []
    for j, (kind, lines) in enumerate(items):
        if j in gone or (kind == "b" and (not out or out[-1] == "")):
            continue
        out.extend(lines)
    sys.stdout.write(head + "\n".join(out).strip("\n") + "\n" + ("\n" if block and out else "") + tail)


if __name__ == "__main__":
    main(sys.argv[1:])
