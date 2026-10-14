#!/usr/bin/env python3
"""The dashboard's 7-day limit panel, called by dashboard.sh.

  dashboard_limit.py fetch
      Claude's own usage reading (the statusline's source) as JSON on stdout;
      exit 1 with no output when there is no login token or the read fails, and
      the cause as one stderr line (dashboard.sh shows it and honours its
      `retry after <n> s`).
  dashboard_limit.py build <status> <usage-file> <now-epoch> <cache-dir> <projects-dir> [<codex-sessions-dir> [<day-projects-json>]]
      The panel's JSON. <status> is dashboard.sh's record for the usage file.
      With the Codex sessions folder it adds `codex`: Codex's own 7-day
      reading, never summed with Claude's. <day-projects-json> is an object,
      project name to its folders: `today` then holds, per project, the day's
      cost of the sessions run in those folders. Every other figure is the
      account's.

Every figure comes from that reading or from Claude Code's own transcripts; a
figure with no source is null, never 0 or an estimate. Dollars are list-price
equivalents of the transcripts' token counts (the owner, 2026-10-10): what the same
usage would cost on the pay-as-you-go API. The reading carries no
history, so each new sample is appended to <cache-dir>/limit-history.jsonl and
the chart draws from that file.
"""
import json
import os
import platform
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

WEEK = 7 * 86400
FIVE_HOURS = 5 * 3600
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
HISTORY_KEEP = 14 * 86400


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return None


def token():
    # The same stores the statusline reads: the Mac keychain, else the credentials file.
    if (os.environ.get("COMMANDECK_HOST_OS") or platform.system()) == "Darwin":
        r = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                           capture_output=True, text=True)
        raw = r.stdout if r.returncode == 0 else ""
    else:
        try:
            with open(os.path.expanduser("~/.claude/.credentials.json")) as f:
                raw = f.read()
        except OSError:
            raw = ""
    try:
        return json.loads(raw)["claudeAiOauth"]["accessToken"]
    except (ValueError, KeyError, TypeError):
        return None


def fetch():
    t = token()
    if not t:
        print("no login token", file=sys.stderr)
        return 1
    req = urllib.request.Request(USAGE_URL, headers={"Authorization": f"Bearer {t}", "anthropic-beta": "oauth-2025-04-20"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            body = json.load(r)
    except urllib.error.HTTPError as e:
        why = f"HTTP {e.code}"
        if e.code == 429:
            why = "rate limited (429)"
            wait = (e.headers.get("Retry-After") or "") if e.headers else ""
            if not wait.isdigit():
                # The header may be a date instead of seconds.
                try:
                    wait = str(max(0, round(parsedate_to_datetime(wait).timestamp() - time.time())))
                except (TypeError, ValueError):
                    wait = ""
            if wait:
                why += f"; retry after {wait} s"
        print(why, file=sys.stderr)
        return 1
    except OSError as e:
        # A connect timeout arrives wrapped in URLError.reason.
        print("timeout" if isinstance(getattr(e, "reason", e), TimeoutError) else "network error", file=sys.stderr)
        return 1
    except ValueError:
        print("malformed response", file=sys.stderr)
        return 1
    if not isinstance(body, dict) or not isinstance(body.get("seven_day"), dict):
        print("malformed response", file=sys.stderr)
        return 1
    json.dump(body, sys.stdout)
    return 0


def pace(used, reset, now):
    """Goal, pace and time left for one reading; every key None without one.

    The goal is the linear share of the elapsed week. underPts > 0 is under pace;
    paceSec is the week time those points equal, from the unrounded gap.
    """
    if used is None or reset is None or reset <= now:
        return {"usedPct": None, "goalPct": None, "underPts": None, "paceSec": None, "timeLeftSec": None}
    start = reset - WEEK
    goal = max(0.0, min(100.0, (now - start) / WEEK * 100))
    under = goal - used
    return {"usedPct": used, "goalPct": goal, "underPts": under, "paceSec": round(under / 100 * WEEK),
            "timeLeftSec": round(reset - now)}


def record(history_path, at, pct, now):
    """Append one sample unless the newest row already holds it; drop rows past HISTORY_KEEP."""
    rows = read_history(history_path)
    if rows and rows[-1][0] >= at:
        return rows
    rows = [r for r in rows if r[0] >= now - HISTORY_KEEP] + [(at, pct)]
    tmp = f"{history_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        f.writelines(json.dumps({"at": iso(a), "pct": p}) + "\n" for a, p in rows)
    os.replace(tmp, history_path)
    return rows


def read_history(path):
    rows = []
    try:
        with open(path) as f:
            for line in f:
                try:
                    r = json.loads(line)
                    a, p = epoch(r["at"]), r["pct"]
                except (ValueError, KeyError, TypeError):
                    continue
                if a is not None and isinstance(p, (int, float)):
                    rows.append((a, p))
    except OSError:
        pass
    return sorted(rows)


def request_row(r):
    """[time, model, input, 5-min cache write, 1-hour cache write, cache read, output] or None.

    A fast-mode request keeps the model name with a ":fast" suffix, so the price
    table never prices it at the standard rate. A count the usage lacks stays
    None, so a price that depends on the prompt size can tell unknown from zero.

    An advisor call is logged only as an "advisor_message" entry in
    usage.iterations: the top-level counts leave it out. Each one follows
    the seven fields as its own row of the same shape, under its own model.
    """
    rid, at, msg = r.get("requestId"), epoch(r.get("timestamp")), r.get("message")
    if r.get("type") != "assistant" or not isinstance(rid, str) or at is None or not isinstance(msg, dict):
        return None
    u = msg.get("usage") if isinstance(msg.get("usage"), dict) else {}
    n = lambda d, k: d.get(k) if isinstance(d.get(k), int) else None

    def counts(u, model):
        cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else None
        w5, w1 = (n(cc, "ephemeral_5m_input_tokens"), n(cc, "ephemeral_1h_input_tokens")) if cc else (n(u, "cache_creation_input_tokens"), 0)
        return [at, model, n(u, "input_tokens"), w5, w1, n(u, "cache_read_input_tokens"), n(u, "output_tokens")]

    its = u.get("iterations") if isinstance(u.get("iterations"), list) else []
    return counts(u, str(msg.get("model")) + (":fast" if u.get("speed") == "fast" else "")) + [
        counts(i, str(i.get("model"))) for i in its if isinstance(i, dict) and i.get("type") == "advisor_message"]


# List prices in $ per million tokens: (input, output, cache read). Cache writes
# are 1.25x input for the 5-minute TTL and 2x for 1 hour. Source:
# https://platform.claude.com/docs/en/about-claude/pricing, as cached 2026-10-06.
# The ":fast" Claude rows are that page's "Fast mode pricing" table, read
# 2026-10-12; the cache multipliers stack on the fast input price. Codex's
# models are priced by CODEX_RULES below, not here. A mode with no published
# price is priced by estimate() and its dollars are reported as estimated. A
# model with no row and nothing to estimate from is unpriced, never $0. Haiku
# 5.5 steps up for prompts over 100K tokens (input + cache read + cache write):
# PRICES holds the short-prompt rate, LONG_PRICES the rest.
PRICES = {
    "claude-fable-5-1": (10.0, 50.0, 0.25),
    "claude-opus-5-5": (4.0, 20.0, 0.20),
    "claude-opus-4-8": (5.0, 25.0, 0.50),
    "claude-sonnet-5-5": (2.0, 10.0, 0.10),
    "claude-haiku-5-5": (0.10, 0.50, 0.01),
    "claude-opus-5-5:fast": (8.0, 40.0, 0.40),
    "claude-opus-4-8:fast": (10.0, 50.0, 1.00),
}
LONG_PRICES = {"claude-haiku-5-5": (0.50, 2.50, 0.05)}
LONG_PROMPT = 100_000

# Codex's models are priced from the parts of the name, not one row per id (the owner's ruling): the
# version and the tier word, then the mode (":fast" is Codex's "priority") and the prompt size. Rates
# from the Standard and Fast tables of https://developers.openai.com/api/docs/pricing, read 2026-10-12
# (a cache write is 1.25x input there too); prompts over 272K tokens take the long rate. Only a
# (version, tier) that is published matches: another version of a known tier may cost something else,
# and a name with any other part (-mini, a date, another mode) matches nothing. Both stay unpriced.
CODEX_NAME = re.compile(r"gpt-(\d+(?:\.\d+)?)-([a-z]+)(:fast)?")
CODEX_RULES = {  # (version, tier): {mode: (short-prompt rate, long-prompt rate)}
    ("6.1", "sol"): {"": ((2.0, 10.0, 0.10), (4.0, 15.0, 0.20)), ":fast": ((4.0, 20.0, 0.20), (8.0, 30.0, 0.40))},
    ("6", "astra"): {"": ((10.0, 50.0, 1.00), (20.0, 75.0, 2.00)), ":fast": ((20.0, 100.0, 2.00), (40.0, 150.0, 4.00))},
}
CODEX_LONG_PROMPT = 272_000


def codex_rates(model):
    """(short-prompt rate, long-prompt rate) of a Codex model the rule prices by its name, or None."""
    m = CODEX_NAME.fullmatch(model)
    return CODEX_RULES.get(m.group(1, 2), {}).get(m.group(3) or "") if m else None


def listed(model):
    """Whether the model has a published price: a row of PRICES or a Codex rule."""
    return model in PRICES or codex_rates(model) is not None


def estimate(model):
    """The price of a fast mode the vendor does not publish: twice its model's standard rate, the multiple
    both vendors publish for the fast modes they do list. None when there is nothing near to estimate from."""
    base = PRICES.get(model[:-5]) if model.endswith(":fast") else None
    return tuple(2 * x for x in base) if base else None


# An estimated fast mode steps up for long prompts where its model does: the same doubling, on the long rate.
LONG_PRICES.update({f"{m}:fast": tuple(2 * x for x in p) for m, p in list(LONG_PRICES.items())
                    if not m.endswith(":fast") and f"{m}:fast" not in PRICES})


def estimated(row):
    """Whether this request, or an advisor call inside it, is priced by estimate()."""
    return any(not listed(x[1]) and estimate(x[1]) is not None for x in [row] + row[7:])


def price(row):
    codex = codex_rates(row[1])
    p = PRICES.get(row[1]) or estimate(row[1]) or (codex and codex[0])
    if p is None:
        # Every count present and 0 costs $0 at any price; a missing count is unknown, so it stays unpriced.
        return 0.0 if row[2:7] == [0, 0, 0, 0, 0] and not row[7:] else None
    # A count the usage lacks is unknown, not 0: the request is unpriced, for every model.
    if any(not isinstance(n, (int, float)) for n in row[2:7]):
        return None
    if codex and sum(row[2:6]) > CODEX_LONG_PROMPT:
        p = codex[1]
    elif row[1] in LONG_PRICES and sum(row[2:6]) > LONG_PROMPT:
        p = LONG_PRICES[row[1]]
    inp, out, read = p
    i, w5, w1, r, o = row[2:7]
    # An advisor row with no price leaves the whole request unpriced: a partial total would read as complete.
    advisors = [price(a) for a in row[7:]]
    if None in advisors:
        return None
    return (i * inp + w5 * inp * 1.25 + w1 * inp * 2 + r * read + o * out) / 1e6 + sum(advisors)


def unpriced_models(rows):
    """The models that leave these rows without a price, by name."""
    return sorted({x[1] for r in rows if price(r) is None for x in [r] + r[7:] if not listed(x[1]) and estimate(x[1]) is None})


def cost(rows, used, start, now):
    """List-price equivalent of this host's requests in the week, and what it projects to.

    perHour is the 100% projection spread over the 168-hour week, as the design
    pairs it with that tile. Requests that exist but none of which can be priced
    leave every dollar figure null: $0 would claim a price source there is not.
    """
    # Today runs from host-local midnight. Rows before the week start were never
    # loaded, so a day that began earlier has no total; nor do rows none of which price.
    midnight = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    day = [r for r in rows if r[0] >= midnight]
    day_priced = [c for c in map(price, day) if c is not None]
    today = None if midnight < start or (day and not day_priced) else sum(day_priced)
    priced = [c for c in map(price, rows) if c is not None]
    # A total with a part left out says so: how many of the day's requests, and which models.
    left = {"todayUnpriced": len(day) - len(day_priced), "unpricedModels": unpriced_models(rows)}
    if rows and not priced:
        return {"week": None, "today": today, "perHour": None, "projected": None, "perPoint": None, "unpricedRequests": len(rows), **left}
    week = sum(priced)
    projected = week / used * 100 if used > 0 else None
    return {"week": week, "today": today, "perHour": projected / (WEEK / 3600) if projected is not None else None,
            "projected": projected, "perPoint": week / used if used > 0 else None,
            "unpricedRequests": len(rows) - len(priced), **left}


def under(folder, roots):
    """Whether a session's working folder is one of `roots` or inside one. An empty root, or "/", is no root."""
    roots = [r.rstrip("/") for r in roots if isinstance(r, str) and r.rstrip("/")]
    return isinstance(folder, str) and any(folder == r or folder.startswith(r + "/") for r in roots)


def requests(projects, cache_path, since, now, folders=False):
    """Each distinct API request's row from Claude Code's transcripts (subagents included) since `since`.

    A week of transcripts runs to gigabytes, so each file is read once from the
    byte offset the last call stopped at; the cache keeps every request's row,
    and the working folder its session ran in. With `folders`, each row comes
    paired with that folder.
    None when a transcript is there and cannot be read: the rows would be short.
    """
    if not os.path.isdir(projects):
        return None
    try:
        with open(cache_path) as f:
            cache = json.load(f)
        offsets, seen, where = cache["offsets"], cache["requests"], cache["cwd"]
        # Version 4 keeps each request's working folder beside its row; an older cache is read again.
        if cache.get("version") != 4 or not all(isinstance(v, list) for v in seen.values()) or not isinstance(where, dict):
            raise ValueError("cache from before requests kept their working folder")
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        offsets, seen, where = {}, {}, {}
    live, unread, unlisted = {}, False, []
    # A folder that cannot be listed hides its transcripts: the same short count.
    for root, _, files in os.walk(projects, onerror=unlisted.append):
        for name in files:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(root, name)
            off = offsets.get(path, 0)
            try:
                st = os.stat(path)
            except FileNotFoundError:
                continue
            except OSError:
                unread = True
                continue
            if st.st_mtime < since:
                # Not read this call, and its place is kept: a later call that starts earlier reads on from it.
                if path in offsets:
                    live[path] = offsets[path]
                continue
            off = offsets.get(path, 0)
            if st.st_size < off:
                off = 0  # rewritten in place: request ids are keys, so a re-read never double counts
            # Line by line: the Linux service caps the collector at 256 MB.
            try:
                f = open(path, "rb")
            except FileNotFoundError:
                continue  # gone since the listing: the rows it gave are in the cache
            except OSError:
                unread = True  # the other transcripts are still read, for the next call
                continue
            with f:
                f.seek(off)
                for line in f:
                    if not line.endswith(b"\n"):
                        break  # a half-written last line waits for the next call
                    off += len(line)
                    if b'"requestId"' not in line or b'"usage"' not in line:
                        continue
                    try:
                        r = json.loads(line)
                    except ValueError:
                        continue
                    row = request_row(r) if isinstance(r, dict) else None
                    if row:
                        seen[r["requestId"]] = row  # a streamed request's last line carries its final usage
                        where[r["requestId"]] = r.get("cwd")
            live[path] = off
    seen = {k: v for k, v in seen.items() if v[0] >= now - 2 * WEEK}
    tmp = f"{cache_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump({"version": 4, "offsets": live, "requests": seen, "cwd": {k: where.get(k) for k in seen}}, f)
    os.replace(tmp, cache_path)
    if unread or any(not isinstance(e, FileNotFoundError) for e in unlisted):
        return None
    return [(v, where.get(k)) if folders else v for k, v in seen.items() if since <= v[0] <= now]


CODEX_TAIL = 262144  # a session file is read 256 KB at a time from its end: token_count events are frequent


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _codex_last(f, now):
    """The last 7-day reading in f not past its reset, or None.

    Read backward CODEX_TAIL bytes at a time, each byte once: one read when the
    tail holds a reading, the windows before it only on a miss.
    """
    stop = f.seek(0, os.SEEK_END)
    carry = b""  # the cut start of the window after this one: the end of this window's last line
    while stop > 0:
        start = max(0, stop - CODEX_TAIL)
        f.seek(start)
        lines = (f.read(stop - start) + carry).split(b"\n")
        carry = lines.pop(0) if start > 0 else b""
        for line in reversed(lines):
            if b'"rate_limits"' not in line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            p = r.get("payload") if isinstance(r, dict) else None
            rl = p.get("rate_limits") if isinstance(p, dict) else None
            # The week is `primary` on a plan with one window and `secondary` beside a 5-hour one.
            for p in (rl.get("primary"), rl.get("secondary")) if isinstance(rl, dict) else ():
                # A reading past its reset is no reading (pace() nulls it): the search goes on.
                if isinstance(p, dict) and p.get("window_minutes") == 10080 and _num(p.get("used_percent")) \
                        and _num(p.get("resets_at")) and p["resets_at"] > now:
                    return (p["used_percent"], p["resets_at"], epoch(r.get("timestamp")))
        stop = start
    return None


def codex(sessions_dir, now):
    """Codex's own 7-day reading: the last `rate_limits` window (`primary` or `secondary`) of 10080 minutes.

    Newest session files first, each read backward from its end until a reading
    is found. Every key is None with no reading or past its
    reset (as pace() does), never 0. The reading is only as fresh as Codex's last
    call, so readAt is the event's own time.
    """
    out = dict(pace(None, None, now), windowStart=None, resetsAt=None, readAt=None)
    if not sessions_dir or not os.path.isdir(sessions_dir):
        return out
    # As in requests(): a deleted path is gone, one that cannot be read may hold the newest reading.
    files, unread = [], []
    for root, _, names in os.walk(sessions_dir, onerror=lambda e: isinstance(e, FileNotFoundError) or unread.append(e)):
        for n in names:
            if n.endswith(".jsonl"):
                p = os.path.join(root, n)
                try:
                    files.append((os.stat(p).st_mtime, p))
                except FileNotFoundError:
                    pass
                except OSError as e:
                    unread.append(e)
    best = None
    for i, (mtime, path) in enumerate(sorted(files, reverse=True)):
        # Past the ten newest, only a file modified inside the window can hold a reading not yet reset.
        if i >= 10 and mtime < now - WEEK:
            break
        # The newest reading by its own time, not by its file's: a resumed
        # older session has the newest file and may hold only an old reading.
        # A file last written before the best reading cannot hold a newer one.
        if best and best[2] is not None and mtime < best[2]:
            break
        try:
            with open(path, "rb") as f:
                got = _codex_last(f, now)
        except OSError:
            continue
        if got and (best is None or (got[2] or 0) > (best[2] or 0)):
            best = got
    if best:
        used, reset, at = best
        out = pace(used, reset, now)
        live = out["usedPct"] is not None
        out.update(windowStart=iso(reset - WEEK) if live else None, resetsAt=iso(reset) if live else None,
                   readAt=iso(at) if live and at is not None else None)
    return out


def codex_history(cache_dir, cx, now):
    """Codex's readings over the week, stored like Claude's (one row per reading, by the reading's own time).

    None with no live reading: a past week's samples are not this week's line.
    """
    path = os.path.join(cache_dir, "codex-limit-history.jsonl")
    start, at = epoch(cx.get("windowStart")), epoch(cx.get("readAt"))
    if cx.get("usedPct") is None or start is None:
        return None
    rows = record(path, int(at), cx["usedPct"], now) if at is not None else read_history(path)
    return [{"at": iso(a), "pct": p} for a, p in rows if start <= a <= now]


def billing(cache_dir):
    """("subscription" | "api", weekly limit in dollars or None), from billing.json beside the cache folder.

    The file is {"billing": "api", "weeklyLimitUsd": 1000}. Anything else, or no file, is the subscription panel.
    """
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(cache_dir)), "billing.json")) as f:
            b = json.load(f)
    except (OSError, ValueError):
        return "subscription", None
    if not isinstance(b, dict) or b.get("billing") != "api":
        return "subscription", None
    lim = b.get("weeklyLimitUsd")
    return "api", lim if _num(lim) and lim > 0 else None


def codex_row(r, model, tier):
    """One Codex `token_usage_record` as a request_row-shaped row, or None when it cannot be used.

    The one reading of a Codex response for a price: codex_requests() below and the build review
    (collect.py) both use it, so the two cannot price the same response differently.
    """
    p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
    if not isinstance(p.get("usage"), dict) or not isinstance(p.get("response_id"), str) or epoch(r.get("timestamp")) is None:
        return None
    n = lambda d, k: d.get(k) if isinstance(d.get(k), int) else None
    u = p["usage"]
    inp, read, write = n(u, "input_tokens"), n(u, "cached_input_tokens"), n(u, "cache_write_input_tokens")
    # An unnamed tier is the standard one; any other name stays in the model name, priced only if listed.
    mode = "" if tier in (None, "default") else ":fast" if tier == "priority" else f":{tier}"
    return [epoch(r["timestamp"]), f"{model or 'unknown Codex model'}{mode}",
            None if inp is None else max(0, inp - (read or 0) - (write or 0)), write, 0, read, n(u, "output_tokens")]


def codex_requests(sessions_dir, cache_path, since, now, missed=None, folders=False):
    """Each Codex response's row, in request_row's shape, from the session files since `since`.

    A `token_usage_record` holds one response's counts. Its input count includes the cached and
    cache-written tokens, so the row's input is what is left. The model is the file's last `turn_context`
    or `thread_settings_applied`; the speed tier is logged only by the latter ("priority" is the vendor's
    fast mode). Both are kept per file beside the byte offset, so a later call that starts past them still
    knows them, as is the working folder the file's `session_meta` names, which `folders` pairs each row with
    as in requests(). The walk and the cache are requests()'s, with that state added.

    A file or folder that cannot be opened is appended to `missed`: what it spent is unknown, so the caller
    must not call the week complete. One that has gone since it was listed spent nothing unseen.
    """
    missed = [] if missed is None else missed
    lost = lambda e: None if isinstance(e, FileNotFoundError) else missed.append(e.filename)
    if not sessions_dir or not os.path.isdir(sessions_dir):
        return None
    try:
        with open(cache_path) as f:
            cache = json.load(f)
        files, seen, where = cache["files"], cache["requests"], cache["cwd"]
        # Version 3 keeps each response's working folder; an older cache is read again.
        if cache.get("version") != 3 or not isinstance(files, dict) or not isinstance(seen, dict) or not isinstance(where, dict):
            raise ValueError("not this reader's cache")
    except (OSError, ValueError, KeyError, TypeError):
        files, seen, where = {}, {}, {}
    live = {}
    for root, _, names in os.walk(sessions_dir, onerror=lost):
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(root, name)
            try:
                st = os.stat(path)
                if st.st_mtime < since:
                    if path in files:
                        live[path] = files[path]  # its place is kept, as in requests()
                    continue
                f = open(path, "rb")
            except OSError as e:
                lost(e)
                continue
            off, model, tier, cwd = files.get(path) or (0, None, None, None)
            if st.st_size < off:
                off, model, tier, cwd = 0, None, None, None  # rewritten in place: response ids are keys, so a re-read never double counts
            with f:
                f.seek(off)
                for line in f:
                    if not line.endswith(b"\n"):
                        break  # a half-written last line waits for the next call
                    off += len(line)
                    if not any(t in line for t in (b'"token_usage_record"', b'"turn_context"', b'"thread_settings_applied"', b'"session_meta"')):
                        continue
                    try:
                        r = json.loads(line)
                    except ValueError:
                        r = None
                    if not isinstance(r, dict):
                        r = {"type": "token_usage_record"} if b'"token_usage_record"' in line else {}
                    p = r.get("payload") if isinstance(r.get("payload"), dict) else {}
                    s = p.get("thread_settings") if p.get("type") == "thread_settings_applied" else None
                    if r.get("type") == "session_meta":
                        cwd = p.get("cwd") if isinstance(p.get("cwd"), str) else cwd
                    elif isinstance(s, dict):
                        model, tier = s.get("model") if isinstance(s.get("model"), str) else model, s.get("service_tier")
                    elif r.get("type") == "turn_context" and isinstance(p.get("model"), str):
                        model = p["model"]
                    elif r.get("type") == "token_usage_record" and codex_row(r, model, tier):
                        seen[p["response_id"]] = codex_row(r, model, tier)
                        where[p["response_id"]] = cwd
                    elif r.get("type") == "token_usage_record":
                        # Never dropped: a usage line this reader cannot use is spend of unknown size, kept as a
                        # request with no counts so the week reads it as unpriced. Keyed by where it sits in the file.
                        at = epoch(r.get("timestamp"))
                        seen[f"unreadable:{path}:{off}"] = [min(int(st.st_mtime), now) if at is None else at,
                                                            "unreadable Codex record", None, None, 0, None, None]
                        where[f"unreadable:{path}:{off}"] = cwd
            live[path] = [off, model, tier, cwd]
    seen = {k: v for k, v in seen.items() if v[0] >= now - 2 * WEEK}
    tmp = f"{cache_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump({"version": 3, "files": live, "requests": seen, "cwd": {k: where.get(k) for k in seen}}, f)
    os.replace(tmp, cache_path)
    return [(v, where.get(k)) if folders else v for k, v in seen.items() if since <= v[0] <= now]


def api_week(limit, rows, now, codex_rows=None, codex_partial=False, since=None):
    """Dollars against the weekly limit for a machine that pays by API.

    The week starts Monday 00:00 host-local. Spend is the PRICES table over this host's Claude and Codex
    requests together; with no Codex session folder (codex_rows None) its share is not measured and the
    total is Claude's alone. With no limit there is no goal or pace. `since` starts the window later than
    Monday: build() passes midnight for the day's spend, so the day and the week are priced by one sum.
    """
    d = datetime.fromtimestamp(now)
    mon = (d - timedelta(days=d.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    start, end = mon.timestamp() if since is None else since, (mon + timedelta(days=7)).timestamp()
    out = {"limitUsd": limit, "spentUsd": None, "goalUsd": None, "underUsd": None, "paceSec": None,
           "timeLeftSec": round(end - now), "windowStart": iso(start), "resetsAt": iso(end),
           "requests": None, "unpricedRequests": None, "history": None,
           "claudeUsd": None, "codexUsd": None, "estimatedUsd": None, "unpricedModels": None, "complete": False}
    if rows is None and codex_rows is None:
        return out
    week = sorted(((r, cx) for rs, cx in ((rows or [], False), (codex_rows or [], True)) for r in rs if start <= r[0] <= now),
                  key=lambda t: t[0][0])
    costs = [(r, cx, price(r)) for r, cx in week]
    priced = [(r[0], c) for r, _, c in costs if c is not None]
    # Complete means the total can be trusted as the whole spend: both providers read, every Codex session
    # opened (codex_partial is codex_requests' missed list, non-empty), and nothing unpriced.
    out.update(requests=len(week), unpricedRequests=len(week) - len(priced),
               complete=rows is not None and codex_rows is not None and not codex_partial and len(week) == len(priced),
               unpricedModels=unpriced_models([r for r, _, c in costs if c is None]))
    if week and not priced:
        return out
    spent, hist = 0.0, []
    for at, c in priced:
        spent += c
        # One point per hour: the running total at that hour's last request.
        if hist and int(hist[-1][0] // 3600) == int(at // 3600):
            hist.pop()
        hist.append((at, spent))

    def share(read, cx):
        # A provider not read, or with requests none of which price, has no dollar figure: $0 would claim one.
        mine = [c for _, x, c in costs if x == cx]
        return None if read is None or (mine and all(c is None for c in mine)) else sum(c for c in mine if c is not None)

    out.update(spentUsd=spent, history=[{"at": iso(a), "usd": u} for a, u in hist + [(now, spent)]],
               claudeUsd=share(rows, False), codexUsd=share(codex_rows, True),
               estimatedUsd=sum(c for r, _, c in costs if c is not None and estimated(r)))
    if limit is not None:
        goal = limit * (now - start) / (end - start)
        out.update(goalUsd=round(goal, 2), underUsd=round(goal - spent, 2), paceSec=round((goal - spent) / limit * (end - start)))
    return out


def cache_write_pct(rows, now):
    """Share of the last 24 h's input tokens (new + cache write + cache read) written to cache, in percent.

    A request with any of those four counts unknown is left out of both sides,
    never read as 0; with no fully known request in the day the share is None.
    """
    if rows is None:
        return None
    day = [r for r in rows if r[0] >= now - 86400 and None not in (r[2], r[3], r[4], r[5])]
    writes = sum(r[3] + r[4] for r in day)
    total = writes + sum(r[2] + r[5] for r in day)
    return writes * 100 / total if total > 0 else None


def build(status, usage_path, now, cache_dir, projects, sessions=None, day_projects=None):
    usage = None
    if status in ("fresh", "stale"):
        try:
            with open(usage_path) as f:
                usage = json.load(f)
        except (OSError, ValueError):
            usage = None
    seven = (usage or {}).get("seven_day") or {}
    five = (usage or {}).get("five_hour") or {}
    used = seven.get("utilization") if isinstance(seven.get("utilization"), (int, float)) else None
    reset = epoch(seven.get("resets_at"))
    out = pace(used, reset, now)
    live = out["usedPct"] is not None
    start = reset - WEEK if live else None
    hist_path = os.path.join(cache_dir, "limit-history.jsonl")
    if live:
        # The sample time is the reading's own (its cache file's), so a reused copy never re-records.
        # Whole seconds: the row stores whole-second ISO, and the duplicate check compares against it.
        rows = record(hist_path, min(int(os.stat(usage_path).st_mtime), now), used, now)
    else:
        rows = read_history(hist_path)
    # The cache write share is a rolling 24 h, so the first day after a reset reads back before the window start.
    since = min(start, now - 86400) if live else None
    loaded = requests(projects, os.path.join(cache_dir, "limit-requests.json"), since, now) if live else None
    reqs = [r for r in loaded if r[0] >= start] if loaded is not None else None
    five_reset = epoch(five.get("resets_at"))
    five_used = five.get("utilization") if isinstance(five.get("utilization"), (int, float)) else None
    out.update({
        "windowStart": iso(start) if live else None,
        "resetsAt": iso(reset) if live else None,
        "fiveHour": {"start": iso(five_reset - FIVE_HOURS), "end": iso(five_reset), "usedPct": five_used}
        if live and five_reset is not None and five_reset > now else None,
        "history": [{"at": iso(a), "pct": p} for a, p in rows if live and start <= a <= now],
        "requests": len(reqs) if reqs is not None else None,
        "cost": cost(reqs, used, start, now) if reqs is not None else None,
        "cacheWritePct24h": cache_write_pct(loaded, now),
        "codex": codex(sessions, now),
    })
    out["codex"]["history"] = codex_history(cache_dir, out["codex"], now)
    # The subscription keys above are the same in both modes; API mode adds its own block beside them.
    mode, limit = billing(cache_dir)
    out["billing"] = mode
    out["api"] = None
    if mode == "api":
        monday = epoch(api_week(None, None, now)["windowStart"])
        missed = []
        codex_rows = codex_requests(sessions, os.path.join(cache_dir, "codex-requests.json"), monday, now, missed)
        api_rows = requests(projects, os.path.join(cache_dir, "limit-requests.json"), min(monday, now - 86400), now)
        out["api"] = api_week(limit, api_rows, now, codex_rows, bool(missed))
        # With no subscription reading nothing above loaded the requests, and cache writes still cost dollars here.
        if out["cacheWritePct24h"] is None:
            out["cacheWritePct24h"] = cache_write_pct(api_rows, now)
    # The day's cost for the top strip, per project: both providers since host-local midnight, in either billing
    # mode. Unlike every figure above, which is the account's, a project's day counts only the sessions run in its
    # own folders. Read from midnight itself, which is over 24 h back on the day the clocks go back.
    midnight = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    lost = []
    day = requests(projects, os.path.join(cache_dir, "limit-requests.json"), midnight, now, True)
    # The week needs the usage reading for its start; the day does not. With that reading refused the
    # panel keeps the day's cost and leaves every week figure unmeasured.
    if out["cost"] is None and day is not None:
        out["cost"] = {**cost([r for r, _ in day], 0, midnight, now), "week": None, "unpricedRequests": None}
    codex_day = codex_requests(sessions, os.path.join(cache_dir, "codex-requests.json"), midnight, now, lost, True)
    # A session is one project's: where one checkout sits inside another, the innermost root that holds it wins.
    roots = sorted(((r, name) for name, rs in (day_projects or {}).items() for r in rs if isinstance(r, str)), key=lambda t: -len(t[0].rstrip("/")))
    owner = lambda folder: next((name for r, name in roots if under(folder, [r])), None)
    own = lambda rows, name: None if rows is None else [r for r, folder in rows if owner(folder) == name]
    out["today"] = {}
    for name in day_projects or {}:
        t = api_week(None, own(day, name), now, own(codex_day, name), bool(lost), midnight)
        out["today"][name] = {k: t[k] for k in ("windowStart", "spentUsd", "claudeUsd", "codexUsd", "estimatedUsd", "requests",
                                                "unpricedRequests", "unpricedModels", "complete")}
    json.dump(out, sys.stdout)
    return 0


def main(argv):
    if argv[1:] == ["fetch"]:
        return fetch()
    if len(argv) in (7, 8, 9) and argv[1] == "build":
        return build(argv[2], argv[3], float(argv[4]), argv[5], argv[6], argv[7] if len(argv) > 7 else None,
                     json.loads(argv[8]) if len(argv) > 8 else None)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
