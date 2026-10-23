#!/usr/bin/env python3
"""search-log-report.py [log...] -- per-tool numbers from the search log (issue 298).

Default logs: $COMMANDECK_SEARCH_LOG, else $COMMANDECK_SCRATCH/search-log.jsonl (~/.commandeck/scratch), and its .1.
Per tool: calls, median and p90 result size (chars), empty %, follow-up %. Then the same for symbol-shaped
searches only, serena against Grep and bash-grep.

Follow-up % for tool T = distinct search rows of T that a later row followed, over the search rows of T. The window is
the session's next 3 LOGGED rows (Edit and Write are not logged); one search followed by two reads counts once. A
follow-up row names the search row it follows (follow_id), so the symbol-shaped lines show that tool's overall
follow-up %. Aggregates only: the log holds no query text, and this prints no fingerprint or path.
"""
import json, os, sys

def load(paths):
    rows = []
    for p in paths:
        try:
            for line in open(p):
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
        except OSError:
            pass
    return rows

def pct(n, d):
    return round(100 * n / d) if d else 0

def report(name, calls, members, rows):
    """members: the tool names this line stands for (all serena tools for the serena line)."""
    sizes = sorted(r["size"] for r in calls)
    mid = len(sizes) // 2
    med = sizes[mid] if len(sizes) % 2 else (sizes[mid - 1] + sizes[mid]) // 2
    p90 = sizes[-(-9 * len(sizes) // 10) - 1]
    searches = [r for r in rows if r["tool"] in members and r["kind"] == "search"]
    ids = {r.get("id") for r in searches} - {None}
    followed = len({r["follow_id"] for r in rows if r.get("follow_id") in ids})
    print(f"{name:<36} calls={len(calls)} median={med} p90={p90} "
          f"empty={pct(sum(r['empty'] for r in calls), len(calls))}% followup={pct(followed, len(searches))}%")

if __name__ == "__main__":
    log = os.environ.get("COMMANDECK_SEARCH_LOG") or os.path.join(
        os.environ.get("COMMANDECK_SCRATCH") or os.path.expanduser("~/.commandeck/scratch"), "search-log.jsonl")
    rows = load(sys.argv[1:] or [log, log + ".1"])
    if not rows:
        print("no rows")
        sys.exit(0)
    print("per tool")
    for t in sorted({r["tool"] for r in rows}):
        report(t, [r for r in rows if r["tool"] == t], {t}, rows)
    print("symbol-shaped searches")
    serena = {r["tool"] for r in rows if r["tool"].startswith("mcp__serena__")}
    for name, members in (("serena", serena), ("Grep", {"Grep"}), ("bash-grep", {"bash-grep"})):
        calls = [r for r in rows if r["tool"] in members and r["kind"] == "search" and r["symbol_shaped"]]
        if calls:
            report(name, calls, members, rows)
