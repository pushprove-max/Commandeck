#!/usr/bin/env python3
"""checkpoint-context.py -- what a main restart must not lose.

  messages <transcript> <budget>
                          the owner's newest genuine prompts from that transcript,
                          verbatim and oldest first, within <budget> UTF-8
                          bytes, or one pointer line when none fits.
                          Always exits 0; a problem is a WARNING line.
  carry <baseline> <new>  every open item of the checkpoint the session resumed
                          from (and every file it carries by reference) is
                          still open in the new one or its references, or
                          closed there with a reason. Exit 1 lists each miss;
                          exit 2 means a file in either chain is unreadable or
                          has no open section.

Callers: hooks/resume-context.sh (messages) and
hooks/context-clear-stop.sh (carry). Section names follow
templates/checkpoint.md and scripts/state-snapshot.sh.
"""
import json
import os
import re
import sys

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
# "Carries open items of: <checkpoint file>" stands for that file's open items,
# so a checkpoint need not copy them. Relative paths resolve against
# the referencing file's directory.
REF = re.compile(r"Carries open items of: (\S+)\s*$")


def section_kind(line):
    """open | todo | closed for a level-2 heading the gate reads, else None."""
    if not line.startswith("## "):
        return None
    h = line[3:].strip().lower()
    return ("closed" if h.startswith("closed since last checkpoint") else "todo" if h.startswith("todo list")
            else "open" if h.startswith(OPEN) else None)


def items(text):
    """(section kind, raw text, identity, todo status) per item."""
    out, kind, cur = [], None, None
    for line in text.splitlines():
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
                cur = [line]
                out.append((kind, cur))
            else:
                cur.append(line)
    result = []
    for kind, lines in out:
        raw = BULLET.sub("", " ".join(l.strip() for l in lines), count=1)
        m = STATUS.match(raw)
        status = m.group(1).lower() if m else None
        raw = raw[m.end():] if m else raw
        # Underscores stay: they belong to task ids and handles.
        ident = re.sub(r"\s+", " ", re.sub(r"[*`~]", "", raw)).lower().strip().rstrip(".,;:").strip()
        if ident.strip("\"'") not in ("", "none"):
            result.append((kind, raw, ident, status))
    return result


def occurs(needle, hay):
    # The substring test first: a pattern compiled per pair was most of a 302 s check.
    return needle in hay and re.search(r"(?<!\w)" + re.escape(needle) + r"(?!\w)", hay)


def closed(ident, closures):
    """A closure names the item AND says something more (what closed it)."""
    for c in closures:
        m = occurs(ident, c)
        if m and re.search(r"\w", c[:m.start()] + c[m.end():]):
            return True
    return False


def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as e:
        raise OSError(f"cannot read the checkpoint {path or '(empty ancestry record)'}: {e}") from e


def refs(path, text):
    here = os.path.dirname(os.path.abspath(path))
    return [os.path.join(here, os.path.expanduser(m.group(1)))
            for m in map(REF.match, text.splitlines()) if m]


def own(text):
    """(open (raw, identity) pairs, closure identities) of one checkpoint."""
    opened, closures = [], []
    for kind, raw, ident, status in items(text):
        if kind == "closed":
            closures.append(ident)
        elif status != "x":
            opened.append((raw, ident))
    return opened, closures


def effective(path, seen, memo):
    """Open (raw, identity) pairs of a checkpoint plus, recursively, those of
    every file it carries by reference. A file's closures end only what it
    inherits, never its own open items: an older file's closure must not erase
    an item a newer checkpoint reopened. A file already on this path of the
    walk ends a cycle; siblings each get a shared file's whole result, so one
    sibling's closure cannot hide the other's open item.

    Returns (pairs, files walked). A file is walked once: its result
    is remembered in memo and reused wherever none of its files is on the
    current path, which is every walk a cycle would not have cut. A result a
    cycle did cut carries None for its files and is never remembered."""
    real = os.path.realpath(path)
    if real in seen:
        return [], None
    hit = memo.get(real)
    if hit and not hit[1] & seen:
        return hit
    seen = seen | {real}
    text = read(path)
    # No open section and no reference is an empty or truncated file, never "nothing to carry".
    if not any(section_kind(l) in ("open", "todo") or REF.match(l) for l in text.splitlines()):
        raise OSError(f"the checkpoint {path} has no Waiting on, unsaved rulings, Queue or Todo list section "
                      "and no 'Carries open items of:' line; it is empty or truncated")
    opened, closures = own(text)
    below = frozenset({real})
    for ref in refs(path, text):
        got, sub = effective(ref, seen, memo)
        opened += [i for i in got if not closed(i[1], closures)]
        below = below | sub if below and sub else None
    # A pair reached through two files is one item.
    out = list(dict.fromkeys(opened)), below
    if below:
        memo[real] = out
    return out


def carry(base, new):
    try:
        memo = {}
        inherited = effective(base, frozenset(), memo)[0]
        new_text = read(new)
        still_open, closures = own(new_text)
        for ref in refs(new, new_text):
            still_open += effective(ref, frozenset({os.path.realpath(new)}), memo)[0]
    except OSError as e:
        print(f"{e}; an unreadable checkpoint in the carry chain cannot show what this session inherited")
        return 2
    # The two producers' unfilled placeholders are not work; the generator's
    # text sits in a shell heredoc with its backticks escaped.
    here = os.path.dirname(os.path.abspath(__file__))
    producers = [os.path.join(here, "..", "templates", "checkpoint.md"), os.path.join(here, "state-snapshot.sh")]
    placeholders = {i[2] for p in producers for i in items(open(p, encoding="utf-8").read().replace("\\`", "`"))}
    # Only the new checkpoint's own closures may end an inherited item.
    missing = [raw for raw, ident in inherited
               if ident not in placeholders and not any(occurs(ident, n) for _, n in still_open)
               and not closed(ident, closures)]
    for raw in missing:
        print(f"- {raw}")
    return 1 if missing else 0


def main(argv):
    if len(argv) == 3 and argv[0] == "messages" and argv[2].isdigit():
        sys.stdout.buffer.write(("\n".join(messages(argv[1], int(argv[2]))) + "\n").encode("utf-8", "replace"))
        return 0
    if len(argv) == 3 and argv[0] == "carry":
        return carry(argv[1], argv[2])
    print("usage: checkpoint-context.py messages <transcript> <budget> | carry <baseline> <new>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
