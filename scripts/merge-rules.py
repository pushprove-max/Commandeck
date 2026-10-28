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
FENCE = re.compile(r"\s*(`{3,}|~{3,})(.*)")
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
# own id: that answer is newer. Add a line per reworded rule. A line carries the owner's keep mine to the
# reworded rule and is not an exemption: the owner's own wording stays loaded from their file.
MADE_FROM = {
    # 0.7.2 main-session.md
    "607f18a2": ("18cd2c62", "8fc96d58"), "06c5d1a6": ("58d81ff4", "8fc96d58"), "1cf7c669": ("1f85d44e",),
    "2fac1916": ("57eadb12",), "f949bcf5": ("32d46d9b",), "8aa8b56d": ("c99218c7",), "0c39c843": ("f0729b8f",),
    "8ecde936": ("00709c21",), "0a0832e3": ("f0558144",),
    # 0.10.0 main-session.md
    "38ccaed2": ("6743a4ac",),
    # 0.13.2 main-session.md
    "d3ad81e3": ("871dfc54",),
    # 0.14.0 main-session.md
    "f652f9a1": ("d3ad81e3",), "ea79fcf3": ("2fac1916",), "3ca43de1": ("0a0832e3",), "487d3e9e": ("04adb41d",),
    # 0.14.1 startup trim: reworded, or several moved below Details into one pointer rule
    "c3227972": ("f652f9a1",), "42145c44": ("06c5d1a6",), "5c61b810": ("34ec1023",), "d96617b8": ("3ca43de1",),
    "1cf4ae22": ("1cf7c669", "6d119e42", "c89a261a", "ea79fcf3", "f949bcf5", "0c39c843", "8ecde936"),
    "95273f82": ("f652f9a1",), "c16a1020": ("f949bcf5",), "5f729572": ("0c39c843",), "cd93267c": ("8ecde936",),
    "a726a12f": ("8361fb71", "1cf7c669"), "6398c17f": ("8ade2fb3", "c89a261a"), "6a82c4ab": ("2848b779", "6d119e42"),
    # 0.18.0 main-session.md and AGENT_STARTUP.md: planning in the unit's own worktree; the lean helper agents
    "4fd3af2e": ("95273f82",), "ae5d50a4": ("a4d1bca5",), "77c5016d": ("1bc6a1b6",),
    # 0.21.0 startup trim (issue 228): reworded, or split with a part moved below Details; step 0 a pointer
    "918c136f": ("1cf4ae22",), "57db6b3a": ("4fd3af2e",), "f36e6d57": ("5bde6db4",), "8265905f": ("6398c17f",),
    "1b13979f": ("d96617b8",), "5a0821ee": ("d96617b8",), "f4e12488": ("77c5016d",),
    # 0.23.0 main-session.md: seat.sh run (issue 257); the owner's yes that names the unit (issue 287); below
    # Details, the planning rule (issues 256, 257, 287), added work (issue 304) and the class stop (issue 303)
    "8e991ec1": ("93e2b611",), "31119f58": ("c3227972",), "3e6a70f8": ("57db6b3a",), "b1a45843": ("5f729572",),
    "45c2952e": ("deb6fc19",),
    # 0.25.0 main-session.md: main-watch's merge gate (issue 254), the plan judge's GO (issue 306), the ceiling (issue 267)
    "2bb3342e": ("f36e6d57",), "e2240999": ("3e6a70f8",), "3e156378": ("c539053c",),
    # 0.26.0 main-session.md: the seven-role cut reworded the planning and helper-agent rules
    "953565b7": ("e2240999",), "b2577b20": ("ae5d50a4",),
    # 0.27.0 main-session.md: only actionable messages wake main (issue 318)
    "7c87d0bb": ("42145c44",),
    # 0.29.0 main-session.md: every review finding blocks the merge (issue 322)
    "e6963680": ("2bb3342e",), "70e51fcc": ("45c2952e",),
    # 0.39.0 global-rules.md: a finding blocks the merge only when normal use would hit the bug (issue 325)
    "13e9906d": ("c8e23316",),
    # 0.44.x main-session.md: the relay-pane Details rule reworded (issue 333); the Checkpoint rule points to its template
    "b2a85a66": ("48b02596",), "4439c5bf": ("487d3e9e",),
    # 0.46.0 main-session.md and AGENT_STARTUP.md: the plan is picked from settings with no question (issue 345); the
    # class rule split in two (second NO-GO, third return); the planning, checklist and "Do not" rules reworded
    "1b63993c": ("31119f58",), "31f8b10f": ("953565b7",), "5686234d": ("f4e12488",),
    "399b22b8": ("70e51fcc",), "45cd53bc": ("70e51fcc",), "71c7e94b": ("607f18a2",),
    "0b0b3a70": ("a726a12f",), "ed48665e": ("8e991ec1",),
    # 0.48.0 main-session.md: main may make a small code fix (issue 364); every test run starts in the background
    "b1471fa8": ("ed48665e",), "401e8893": ("71c7e94b",),
    # and the plan judges: the second judge runs on Fable (issue 349 follow-up); the plan's claims block (issue 359)
    "f45e894e": ("31f8b10f",),
    # 0.48.0 global-rules.md: the review threshold (issue 366), the reviewers' scope, the ponytail add-on removed
    # (issue 365), units and duplicate agents, planning by size
    "26b6b2b9": ("13e9906d",), "cb6056f9": ("9243900d",), "41d1d566": ("e38a2639",), "e7926841": ("e6c9ac28",),
    "3b129248": ("516a9bd8",), "2424eeef": ("56860db4",),
    # 0.51.0 main-session.md: a Builder whose pane is gone (issue 382) in the "Do not" list; the plan judge names the
    # established practice and rejects a flow step with no Catches: line
    "4083592b": ("b1471fa8",), "bbe121f7": ("f45e894e",),
    # 0.51.0 global-rules.md: a plan's `file ~line`, the sibling dry run, and the flexibility finding's severity
    "eff13cd5": ("64f32653",), "faea5cd0": ("71b6b9ca",), "a935667e": ("2fe4fdf9",),
    # 0.52.0 main-session.md: added work names its probes (issue 385); unit-close.sh after a hand merge (issue 396);
    # unit-hold.sh joined to the no-redundant-steps rule (issue 387)
    "9ed773b1": ("b1a45843",), "b5d1e56b": ("69cb8485",), "6ae3b0ac": ("4b66daaa",),
    # 0.56.0 global-rules.md: the closing pass gets no earlier findings; a fixer's passing test does not end a finding;
    # a zero diff reported done is a failure
    "0daaf070": ("cb6056f9",), "b1915c88": ("ecd4b33d",), "0d7babbc": ("e7926841",),
    # 0.57.0 main-session.md: the restart waits for a helper agent however long, and a failed restart is not retried
    "d2e4dc5b": ("3e156378",),
}


def dropped(i, drop, keep):
    return i not in keep and (i in drop or (i in MADE_FROM and all(dropped(o, drop, keep) for o in MADE_FROM[i])))


def parse(text):
    """[(kind, lines)]: kind is h (heading), u (a rule) or b (a blank line)."""
    out, cur, fence = [], None, ""

    def flush():
        nonlocal cur
        if cur:
            out.append(("u", cur))
        cur = None

    # The fence rule of fence.sh: backticks or tildes, indented or not, closed by the same character at least as long.
    for line in text.split("\n"):
        run = FENCE.match(line)
        if fence:
            cur.append(line)
            if run and run.group(1)[0] == fence[0] and len(run.group(1)) >= len(fence) and not run.group(2).strip():
                fence = ""
                flush()
            continue
        if run:
            flush()
            cur, fence = [line], run.group(1)
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
    theirs, earlier = {}, set()
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
        # Setup's own block from an earlier run is not the owner's: only named in the report (issue 209).
        for b in BLOCK.finditer(text):
            earlier.update(norm(lines) for kind, lines in parse(re.sub(r"<!-- commandeck:[^>]*-->", "", b.group(0))) if kind == "u")
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
        k = sum(1 for j, (kind, lines) in enumerate(items) if kind == "u" and j not in gone and norm(lines) in earlier)
        was = f" ({k} already in setup's block from an earlier run)" if k else ""
        print(f"{n} plugin rules kept{was}, {len(same)} already in your files (left out), {len(mine)} where you keep your own (left out)")
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
