#!/usr/bin/env python3
"""checkpoint-context.py -- what a main restart must not lose.

  messages <transcript> <budget>
                          the owner's newest genuine prompts from that transcript,
                          verbatim and oldest first, within <budget> UTF-8
                          bytes, or one pointer line when none fits.
                          Always exits 0; a problem is a WARNING line.
  carry <baseline> <new>  every open item of the checkpoint the session resumed
                          from (and every file it carries by reference) is
                          still open in the new one's own text, or closed
                          there with a reason. Exit 1 lists each miss;
                          exit 2 means a file in either chain is unreadable or
                          has no open section. An item ending "-- done when:
                          <ref>, ..." whose refs all hold is closed, one
                          auto-closed line in clear-hook.log each.
  dedupe <file>           flatten the file's carry chain into it, one line per
                          subject, behind a <file>.bak backup (refused while
                          one exists); re-stamps <file>.restarted.
  aged <checkpoint>       the open items past carry's ten generations, each
                          with a "-- carried unseen: <generation>" tail.

Callers: hooks/resume-context.sh (messages) and
hooks/context-clear-stop.sh (carry, aged). Section names follow
templates/checkpoint.md and scripts/state-snapshot.sh.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from collections import Counter

COUNT_VAR = "COMMANDECK_HANDOFF_MESSAGE_COUNT"
COUNT_DEFAULT = "8"

# User rows the owner never typed: harness, hook and orchestration text, and the
# resume prompt the restart helper types (lib/context-clear-restart.sh).
SYNTHETIC = re.compile(
    r"\s*(?:<task-notification>|<user-prompt-submit-hook>|Stop hook feedback:|<local-command-"
    r"|You have \d+ orchestration messages?\. Run `orca orchestration check"
    r"|main-watch: "
    r"|resume from the checkpoint \S+\.md \(its text, board\.sh)")
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
# A notice the harness put ahead of typed text in the same row: only the notice goes.
LEADING_NOTICE = re.compile(r"(?:\s*<task-notification>.*?</task-notification>)+\s*", re.S)


def prompt_text(row):
    if row.get("type") != "user" or row.get("isMeta") or row.get("isCompactSummary"):
        return None
    content = row.get("message", {}).get("content")
    if isinstance(content, str):
        parts = [content]
    elif isinstance(content, list):
        parts = [b.get("text") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    else:
        return None
    parts = [p for p in parts if isinstance(p, str) and REMINDER.sub("", p).strip()]
    text = "\n".join(parts)
    rest = LEADING_NOTICE.sub("", text, count=1) if LEADING_NOTICE.match(text) else text
    if rest.strip():
        text = rest
    if not text.strip() or SYNTHETIC.match(text):
        return None
    return text


def plural(n, word):
    return f"{n} {word}{'' if n == 1 else 's'}"


def messages(path, budget):
    lines = prompt_block(path, budget)
    if len(("\n".join(lines) + "\n").encode("utf-8", "replace")) <= budget:
        return lines
    # Warnings repeat the path, so they too can overflow: one pointer instead.
    return [f"## The owner's prompts before the restart: left out to fit the resume budget ({budget} bytes); read them in {path}"]


def prompt_block(path, budget):
    head = ["## The owner's prompts before the restart (oldest first, verbatim)", f"source: {path or '(unknown transcript path)'}"]
    raw = os.environ.get(COUNT_VAR, COUNT_DEFAULT)
    if not re.fullmatch(r"[1-9][0-9]*", raw):
        return head + [f"WARNING: {COUNT_VAR}={raw} is not a positive integer; no prompts shown"]
    count = int(raw)
    found, bad = [], 0
    try:
        with open(path, "rb") as f:
            for line in f:
                # Claude Code 2.1.300's api-request rows hold no prompt and a third or more of a long log's bytes.
                if not line.strip() or line.startswith(b'{"type":"api-request'):
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    row = None
                if not isinstance(row, dict) or not isinstance(row.get("message", {}), dict):
                    bad += 1
                    continue
                text = prompt_text(row)
                if text is not None:
                    found.append(text)
    except OSError as e:
        return head + [f"WARNING: cannot read the transcript {path}: {e.strerror}; the owner's prompts were not carried over"]
    if bad:
        head.append(f"WARNING: {plural(bad, 'malformed transcript line')} skipped")
    if not found:
        return head + ["(no prompts from the owner in that transcript)"]
    chosen = found[-count:]
    notes = []
    if len(found) > len(chosen):
        notes.append(f"OMITTED: {plural(len(found) - len(chosen), 'older prompt')} beyond the newest {count} ({COUNT_VAR}); read them in the source")
    # Newest contiguous suffix that fits; a prompt is never cut. The caller
    # finds a cut by "the resume budget" and reserves room for the pointer.
    for keep in range(len(chosen), 0, -1):
        shown = chosen[len(chosen) - keep:]
        dropped = len(chosen) - keep
        extra = [f"OMITTED: {plural(dropped, 'older prompt')} over the resume budget ({budget} bytes); read them in the source"] if dropped else []
        lines = head + notes + extra
        for i, text in enumerate(shown, 1):
            lines += [f"<<< prompt {i} of {keep}", text, f">>> end prompt {i}"]
        if len(("\n".join(lines) + "\n").encode("utf-8", "replace")) <= budget:
            return lines
    size = len(chosen[-1].encode("utf-8", "replace"))
    return [f"## The owner's prompts before the restart: left out whole to fit the resume budget "
            f"(newest is {size} bytes, {budget} left); read them in {path}"]


OPEN = ("waiting on", "rulings this session", "queue")
BULLET = re.compile(r"\s*(?:[-*+]|\d+[.)])\s+")
STATUS = re.compile(r"\[([ xX>])\]\s*")
# "Carries open items of: <checkpoint file>" names the file a checkpoint resumed
# from, for recovery; "none" names none. Relative paths resolve against
# the referencing file's directory.
REF = re.compile(r"Carries open items of: (\S+)\s*$")
# Issue 281: a restated item keeps its key, whatever status tail it gained. Issue 283: a Q-<n> item's key is q-<n>.
TAIL = re.compile(r" -- (?:reason|still open|closed|restated|done when|carried unseen):| = todo #")
QKEY = re.compile(r"q-\d+(?![\w-])")
POINTER = re.compile(r"(?:see|in|per|moved to|carried (?:in|to))\s+\S+")
UNRESOLVED = "## Queue (left unresolved at the restart: restate or close each, one line per item, with its own reason)"
MAX_DEPTH = 10  # generations carry takes from the walk; aged lists the rest
LOOKUP_S = 10


def section_kind(line):
    """open | todo | closed for a level-2 heading the gate reads, else None."""
    if not line.startswith("## "):
        return None
    h = line[3:].strip().lower()
    return ("closed" if h.startswith("closed since last checkpoint") else "todo" if h.startswith("todo list")
            else "open" if h.startswith(OPEN) else None)


def located(lines):
    """(section kind, line numbers, raw text, identity, todo status) per item."""
    out, kind, cur = [], None, None
    for n, line in enumerate(lines):
        # Only level-2 headings start a section; a deeper one is body text, so
        # a nested "### Todo list" under Gotchas carries nothing.
        if REF.match(line):
            cur = None
        elif line.startswith("## "):
            kind, cur = section_kind(line), None
        elif kind and not line.strip():
            cur = None
        elif kind:
            if cur is None or BULLET.match(line):
                cur = [n]
                out.append((kind, cur))
            else:
                cur.append(n)
    result = []
    for kind, at in out:
        raw = BULLET.sub("", " ".join(lines[n].strip() for n in at), count=1)
        m = STATUS.match(raw)
        status = m.group(1).lower() if m else None
        raw = raw[m.end():] if m else raw
        # Underscores stay: they belong to task ids and handles.
        ident = re.sub(r"\s+", " ", re.sub(r"[*`~]", "", raw)).lower().strip().rstrip(".,;:").strip()
        if ident.strip("\"'") not in ("", "none"):
            result.append((kind, at, raw, ident, status))
    return result


def items(text):
    """(section kind, raw text, identity, todo status) per item."""
    return [(k, raw, ident, st) for k, _, raw, ident, st in located(text.splitlines())]


def key(ident):
    """The subject an item keeps through rewording: q-<n>, or its text before the first status tail."""
    ident = re.sub(r"^open:\s*", "", ident)
    m = QKEY.match(ident)
    if m:
        return m.group(0)
    m = TAIL.search(ident)
    return (ident[:m.start()] if m else ident).strip().rstrip(".,;:").strip()


def occurs(needle, hay):
    # The substring test first: a pattern compiled per pair was most of a 302 s check.
    # A hyphen joins words: q-3 does not occur in q-3-staging.
    return needle in hay and re.search(r"(?<!\w)(?<!\w-)" + re.escape(needle) + r"(?!-?\w)", hay)


def closing_lines(idents, closures):
    """The keys the close lines close (issue 252). A line closes the longest key it names, and nothing when it
    also names another key that one does not contain; it needs a reason, which no other close line gives: one
    reason pasted on many lines closes none of them. The reason is only the text after the line's last " -- "
    (the template's "<item, verbatim> -- <what closed it>"), so a title or status tail before it never makes two
    pasted reasons differ. A line with no " -- " has none, nor does a pointer ("see <file>") or the item's own
    last " -- " part, copied with the item."""
    words = lambda s: re.sub(r"\W+", " ", s).strip()
    keys, tails = set(), {}
    for ident in idents:
        k = key(ident)
        keys.add(k)
        if " -- " in ident:
            tails.setdefault(k, set()).add(words(ident.rsplit(" -- ", 1)[1]))
    picks = []
    for c in closures:
        named = [k for k in keys if occurs(k, c)]
        top = max(named, key=len, default=None)
        if top is None or any(k not in top for k in named):
            continue
        # The line is about the key it starts with: one that only mentions a key ("Q-9 discuss Q-3") closes nothing.
        m = occurs(top, c)
        if m.start() != 0:
            continue
        reason = c.rsplit(" -- ", 1)[1].strip(" -:;,.") if " -- " in c else ""
        if re.search(r"\w", reason) and not POINTER.fullmatch(reason) and words(reason) not in tails.get(top, ()):
            picks.append((top, words(reason)))
    given = Counter(r for _, r in picks)
    return {k for k, r in picks if given[r] == 1}


def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as e:
        raise OSError(f"cannot read the checkpoint {path or '(empty ancestry record)'}: {e}") from e


def refs(path, text):
    here = os.path.dirname(os.path.abspath(path))
    return [os.path.join(here, os.path.expanduser(m.group(1)))
            for m in map(REF.match, text.splitlines()) if m and m.group(1) != "none"]  # the template's fresh start


def own(text):
    """(open (raw, identity) pairs, closure identities, Todo (identity, status) in order) of one checkpoint.
    A CLOSED: or [x] line outside the Closed section is a closure too (issue 281)."""
    opened, closures, todos = [], [], []
    for kind, raw, ident, status in items(text):
        if kind == "todo":
            todos.append((ident, status))
        if kind == "closed" or status == "x" or ident.startswith("closed:"):
            closures.append(re.sub(r"^closed:\s*", "", ident))
        else:
            opened.append((raw, ident))
    return opened, closures, todos


def load(path):
    """(open (raw, identity) pairs, closure identities, references) of one checkpoint of the chain."""
    text = read(path)
    # No open section and no reference is an empty or truncated file, never "nothing to carry".
    if not any(section_kind(l) in ("open", "todo") or REF.match(l) for l in text.splitlines()):
        raise OSError(f"the checkpoint {path} has no Waiting on, unsaved rulings, Queue or Todo list section "
                      "and no 'Carries open items of:' line; it is empty or truncated")
    opened, closures, _ = own(text)
    return opened, closures, refs(path, text)


class Items:
    """The walk's items, one index each in the order first read, so a file's result is one int with a bit per
    item: a list of (raw, identity) tuples per file held the same item once per file that reached it, and a file
    carrying many overlapping results ran past 260 MiB at 1,600 files. A key keeps a list of its indexes, not a
    mask: a mask is as long as the highest index it holds, so one per key was quadratic in the chain."""

    def __init__(self):
        self.pairs, self.at, self.keys = [], {}, {}

    def index(self, pairs):
        """The indexes of (raw, identity) pairs, adding the new ones."""
        for p in pairs:
            if p not in self.at:
                self.at[p] = len(self.pairs)
                self.pairs.append(p)
                self.keys.setdefault(key(p[1]), []).append(self.at[p])
        return [self.at[p] for p in pairs]

    def ended(self, inherited, closures):
        """The keys of the inherited items the closures end: checked once against everything inherited, from all
        references (per reference, one reason pasted on two lines closed an item in each branch). A file that
        closes nothing ends nothing: checking every inherited item at every generation was quadratic. Only a key a
        close line names can be closed, so the keys are found from the line's own words (each substring occurs()
        would match, looked up), not by testing every inherited key against each line, which was quadratic too."""
        if not closures or not inherited:
            return set()
        js = set()
        for c in closures:
            starts = [m.start() for m in re.finditer(r"(?<!\w)(?<!\w-)", c)]
            ends = [m.start() for m in re.finditer(r"(?!-?\w)", c)]
            for i in starts:
                for e in ends:
                    if e > i and c[i:e] in self.keys:
                        js.update(j for j in self.keys[c[i:e]] if inherited >> j & 1)
        return closing_lines([self.pairs[j][1] for j in sorted(js)], closures)

    def of(self, keys):
        """The mask of every item with one of <keys>."""
        return mask(j for k in keys for j in self.keys[k])


def mask(js):
    return sum(1 << j for j in set(js))


def effective(path, depth=MAX_DEPTH, errs=None):
    """Open (raw, identity, generation) items of a checkpoint plus those of every file it carries by reference;
    generation 0 is the checkpoint's own, and only generations below <depth> are returned (aged lists the rest).
    One walk for every depth, so its cost never depends on the graph's shape (Max ruled this for checkpoint
    growth): each file is read once, nearest first; each cycle of files is condensed into one node and the
    condensed graph is folded once, sinks first (Max ruled this for cycles). A file's closures end only what it
    inherits, never its own open items: an older file's closure must not erase an item a newer checkpoint
    reopened. All files of a cycle share their closures, which end only what the cycle inherits from outside it,
    never a member's own item, since inside a cycle no file is older. A result is one bit per item, freed once
    every reference to it from outside its cycle has read it. An item's generation is the fewest references from
    the checkpoint to a file owning it, along files that did not end it, so a cycle that crosses the depth closes
    as one unit and its members still keep their own distances. With errs, a referenced file within <depth> that
    cannot be read adds its error there and nothing else: the readable rest of the chain still counts. Nothing
    recurses: a chain grows a file per restart, and recursion would end in RecursionError past about a thousand."""
    root = os.path.realpath(path)
    files, bad, dist, items, todo = {}, {}, {root: 0}, Items(), [path]
    for p in todo:
        real = os.path.realpath(p)
        try:
            opened, closures, rs = load(p)
        except OSError as e:
            if real == root or errs is None and dist[real] < depth:
                raise
            bad[real] = str(e)
            continue
        files[real] = items.index(opened), closures, rs
        for r in rs:
            w = os.path.realpath(r)
            if w not in dist:
                dist[w] = dist[real] + 1
                todo.append(r)
    edges = {v: [os.path.realpath(r) for r in f[2]] for v, f in files.items()}
    # Tarjan's strongly connected components, iterative: a cycle is finished only after every cycle it carries.
    comp, order, index, low, stack, on = {}, [], {root: 0}, {root: 0}, [root], {root}
    work = [(root, iter(edges[root]))]
    while work:
        v, it = work[-1]
        for w in it:
            if w not in files:
                continue
            if w not in index:
                index[w] = low[w] = len(index)
                stack.append(w)
                on.add(w)
                work.append((w, iter(edges[w])))
                break
            if w in on:
                low[v] = min(low[v], index[w])
        else:
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])
            if low[v] == index[v]:
                members = []
                while not members or members[-1] != v:
                    members.append(stack.pop())
                    on.discard(members[-1])
                    comp[members[-1]] = len(order)
                order.append(members[::-1])
    need = Counter(comp[w] for v in comp for w in edges[v] if w in comp and comp[w] != comp[v])
    need[comp[root]] += 1
    done, ends = {}, []
    for c, members in enumerate(order):
        opened, closures, inherited = [], [], 0
        for v in members:
            opened += files[v][0]
            closures += files[v][1]
            for w in edges[v]:
                if w in bad:
                    if dist[w] < depth:
                        errs.append(bad[w])
                elif comp[w] != c:
                    inherited |= done[comp[w]]
                    need[comp[w]] -= 1
                    if not need[comp[w]]:
                        del done[comp[w]]
        ended = items.ended(inherited, closures)
        done[c] = mask(opened) | inherited & ~items.of(ended)
        # Keys, not masks: a mask is as long as the highest index it holds, whatever its count.
        ends.append(ended)
    # An item's generation is the fewest references to a file owning it along files that did not end it: its
    # owner's distance when no file ends its key. For a key some file ends, one search from the root that does not
    # leave a cycle ending it; a reference inside that cycle is still followed. No mask per file or per level: one
    # each was quadratic in the chain.
    gen = {}
    for v, f in files.items():
        if dist[v] < depth:
            for j in f[0]:
                gen.setdefault(j, dist[v])
    for k in set().union(*ends):
        want = set(items.keys[k])
        for j in want:
            gen.pop(j, None)
        level, seen, g = [root], {root}, 0
        while level and want and g < depth:
            nxt = []
            for v in level:
                for j in want.intersection(files[v][0]):
                    gen[j] = g
                want.difference_update(files[v][0])
                for w in edges[v]:
                    if w in files and w not in seen and (comp[w] == comp[v] or k not in ends[comp[v]]):
                        seen.add(w)
                        nxt.append(w)
            level, g = nxt, g + 1
    return [(*items.pairs[j], g) for j, g in sorted(gen.items(), key=lambda t: (t[1], t[0]))]


def pointed(k, ident, todos):
    """An item that says "= todo #N" is carried by the new checkpoint's open todo #N when that todo names the
    item's whole subject: its Q-key as its own key, or every word of the subject in order."""
    m = re.search(r" = todo #(\d+)", ident)
    n = int(m.group(1)) if m else 0
    if not 0 < n <= len(todos) or todos[n - 1][1] == "x":
        return False
    todo = todos[n - 1][0]
    return key(todo) == k or (not QKEY.fullmatch(k) and bool(occurs(k, todo)))


def run(argv, cwd):
    try:
        return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=LOOKUP_S)
    except (OSError, subprocess.TimeoutExpired):
        return None


def holds(ref, main):
    """The evidence a done-when ref holds now (issue 283), or None. Read only; each lookup is capped at 10 s."""
    m = re.fullmatch(r"#(\d+)", ref)
    if m:
        r = run(["gh", "issue", "view", m.group(1), "--json", "state", "-q", ".state"], main)
        return f"{ref} closed" if r and r.returncode == 0 and r.stdout.strip() == "CLOSED" else None
    if ref.startswith("decision:"):
        last = None
        try:
            with open(os.path.join(main, ".claude", "metrics", "decisions.jsonl"), encoding="utf-8") as f:
                for line in f:
                    row = json.loads(line)
                    last = row if row.get("id") == ref[9:] else last
        except (OSError, ValueError, AttributeError):
            return None
        return f"{ref[9:]} answered" if last and last.get("answer") not in (None, "") else None
    if re.fullmatch(r"[0-9a-f]{7,40}", ref):
        r = run(["git", "merge-base", "--is-ancestor", ref, "origin/main"], main)
        return f"{ref} on origin/main" if r and r.returncode == 0 else None
    r = run(["git", "log", "-F", f"--grep=feat({ref}):", "--format=%h %s", "HEAD"], main)
    hit = [l for l in (r.stdout.splitlines() if r and r.returncode == 0 else []) if l.split(" ", 1)[-1].startswith(f"feat({ref}):")]
    return f"{ref} merged ({hit[0].split()[0]})" if hit else None


def done(raw, main):
    """The evidence for an item whose every "-- done when:" ref holds, else None."""
    m = re.search(r" -- done when: (.+)$", raw)
    refs_ = [r.strip() for r in m.group(1).split(",") if r.strip()] if m else []
    got = [holds(r, main) for r in refs_]
    return ", ".join(got) if got and all(got) else None


def log(line):
    try:
        with open(os.path.expanduser("~/.claude/checkpoints/clear-hook.log"), "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {line}\n")
    except OSError:
        pass


def carry(base, new):
    try:
        errs = []
        inherited = [(r, i) for r, i, _ in effective(base, MAX_DEPTH, errs)]
        new_text = read(new)
        # Issue 252: only the new file's own text keeps an item; its reference line is for recovery, and counting
        # the referenced file's items as kept passed every restart that reworded or dropped one.
        still_open, closures, todos = own(new_text)
    except OSError as e:
        print(f"{e}; an unreadable checkpoint in the carry chain cannot show what this session inherited")
        return 2
    # The two producers' unfilled placeholders are not work; the generator's
    # text sits in a shell heredoc with its backticks escaped.
    here = os.path.dirname(os.path.abspath(__file__))
    producers = [os.path.join(here, "..", "templates", "checkpoint.md"), os.path.join(here, "state-snapshot.sh")]
    placeholders = {i[2] for p in producers for i in items(open(p, encoding="utf-8").read().replace("\\`", "`"))}
    main = run(["git", "rev-parse", "--show-toplevel"], None)
    main = main.stdout.strip() if main and main.returncode == 0 else os.getcwd()
    # A file of the chain that cannot be read is an item of its own: what it held is unknown, and the restarted
    # session must see that, not lose it while the readable items still carry.
    for e in errs:
        raw = f"carry chain: {e}; its open items were not carried: restore the file, or check them by hand"
        inherited += [(raw, i[2]) for i in items(f"## Queue (in order)\n- {raw}\n")]
    # Only the new checkpoint's own closures may end an inherited item.
    ended = closing_lines([i for _, i in inherited], closures)
    # Kept means the same subject as one of the new file's own items, not a mention inside another item.
    kept = {key(n) for _, n in still_open}
    missing = {}
    for raw, ident in inherited:
        k = key(ident)
        if ident in placeholders or k in missing or k in ended or k in kept or pointed(k, ident, todos):
            continue
        evidence = done(raw, main)
        if evidence:
            log(f"auto-closed: {raw} -- {evidence}")
            continue
        missing[k] = raw
    for raw in missing.values():
        print(f"- {raw}")
    return 1 if missing else 0


def dedupe(path):
    """Flatten the file's whole carry chain into it, one line per subject, behind a backup (issue 283)."""
    bak = path + ".bak"
    if os.path.exists(bak):
        print(f"dedupe: {bak} exists from an earlier dedupe; compare and remove it before another run", file=sys.stderr)
        return 1
    try:
        text = read(path)
        # The whole chain, not the carry walk's ten generations: the references are cut below, so an item past
        # the tenth would be lost. A file of it that cannot be read refuses the dedupe.
        chain = effective(path, sys.maxsize)
    except OSError as e:
        print(f"dedupe: {e}", file=sys.stderr)
        return 2
    lines = text.splitlines()
    drop, kept, carried = set(), set(), []
    # The unresolved Queue sections go whole: their items come back once, in one such section at the end.
    on = False
    for n, line in enumerate(lines):
        on = line == UNRESOLVED or (on and not line.startswith("## "))
        if on and not REF.match(line):
            drop.add(n)
    for kind, at, raw, ident, status in located(lines):
        if kind in ("open", "todo") and status != "x" and at[0] not in drop:
            if key(ident) in kept:
                drop.update(at)
            kept.add(key(ident))
    for raw, ident, _ in chain:
        if key(ident) not in kept:
            kept.add(key(ident))
            carried.append(raw)
    out = ["Carries open items of: none" if REF.match(l) else l for n, l in enumerate(lines) if n not in drop]
    while out and not out[-1].strip():
        out.pop()
    if carried:
        out += ["", UNRESOLVED] + [f"- {raw}" for raw in carried]
    shutil.copy2(path, bak)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    # The stop hook's marker holds the checkpoint's cksum: re-stamped, the rewrite is not a new checkpoint.
    if os.path.exists(path + ".restarted"):
        with open(path, "rb") as src, open(path + ".restarted", "wb") as dst:
            subprocess.run(["cksum"], stdin=src, stdout=dst, check=False)
    print(f"dedupe: {path}: {len(kept)} subjects; backup {bak}")
    return 0


def aged(base):
    """The open items past the walk's ten generations, each with the generation it was found at. A file past the
    walk that cannot be read is listed as an item of its own, as carry does: the readable rest still counts."""
    try:
        if not refs(base, read(base)):
            return 0  # carries nothing by reference: nothing can age out
        near, far = [], []
        cut = {key(i) for _, i, _ in effective(base, MAX_DEPTH, near)}
        found = {}
        # One walk of the whole chain: generation g is first read by the walk of depth g + 1.
        for raw, ident, g in sorted(effective(base, sys.maxsize, far), key=lambda t: t[2]):
            if key(ident) not in cut:
                found.setdefault(key(ident), f"- {raw} -- carried unseen: {g + 1}")
    except OSError as e:
        print(f"{e}", file=sys.stderr)
        return 2
    for line in found.values():
        print(line)
    # The ten-generation walk's own unreadable files are carry's items; only those past it are listed here.
    for e in dict.fromkeys(far):
        if e not in near:
            print(f"- carry chain: {e}; its open items were not carried: restore the file, or check them by hand")
    return 0


def main(argv):
    if len(argv) == 3 and argv[0] == "messages" and argv[2].isdigit():
        sys.stdout.buffer.write(("\n".join(messages(argv[1], int(argv[2]))) + "\n").encode("utf-8", "replace"))
        return 0
    if len(argv) == 3 and argv[0] == "carry":
        return carry(argv[1], argv[2])
    if len(argv) == 2 and argv[0] in ("dedupe", "aged"):
        return (dedupe if argv[0] == "dedupe" else aged)(argv[1])
    print("usage: checkpoint-context.py messages <transcript> <budget> | carry <baseline> <new> | dedupe <file>"
          " | aged <checkpoint>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
