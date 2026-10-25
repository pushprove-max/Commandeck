#!/usr/bin/env python3
"""The dashboard's 7-day limit panel, called by dashboard.sh.

  dashboard_limit.py fetch
      Claude's own usage reading (the statusline's source) as JSON on stdout;
      exit 1 with no output when there is no login token or the read fails, and
      the cause as one stderr line (dashboard.sh shows it and honours its
      `retry after <n> s`). The login is CLAUDE_CONFIG_DIR's when set: main's
      config folder, which Orca may set per pane.
  dashboard_limit.py account <cache-dir>
      The signed-in account ({account, label}). When it is not the one the
      cached reading was taken for, or no record says whose it is, that reading and its retry note are
      removed, and limit-history.jsonl moves aside to limit-history.<old>.jsonl.
  dashboard_limit.py build <status> <usage-file> <now-epoch> <cache-dir> <projects-dir> [<codex-sessions-dir> [<day-projects-json>]]
      The panel's JSON. <status> is dashboard.sh's record for the usage file.
      With the Codex sessions folder it adds `codex`: Codex's own 7-day
      reading, never summed with Claude's. Codex spend also reads the review
      home's sessions (COMMANDECK_CODEX_REVIEW_HOME, default ~/.codex-review). <day-projects-json> is an object,
      project name to its folders: `today` then holds, per project, the day's
      cost of the sessions run in those folders. Every other figure is the
      account's.
  dashboard_limit.py tests <projects-dir> <cache-file> <now-epoch> <folder>...
      The Tests card's finished runs (issue 269) and each command's usual time, from the transcripts' Bash calls that
      ran a test runner in the folders; `null` when they cannot be read whole. Its cache is <cache-file>, apart from
      the limit card's.
  dashboard_limit.py units <now-epoch> <cache-dir> <projects-dir> <codex-sessions-dir>
      Each Builder's cost by stage, from its worktree's own sessions; the units
      ([{unit, worktree, stages}]) on stdin, {unit: {stages, total} or null} out.
  dashboard_limit.py seats <now-epoch> <cache-dir> <projects-dir> <clear-hook-log> <main-checkout> [<relay-worktree>]
      Main's and the relay's day, 7-day daily average and restarts today, from their own sessions.
  dashboard_limit.py main-events <now-epoch> <main-projects-folder> <clear-hook-log>
      Main's compactions and unhealed carry failures over 24 h, and its last restart, for the alerts.
  dashboard_limit.py restarts <clear-hook-log> [--since <iso>] [--until <iso>] [--transcripts <dir>]
      Restarts per day, the median checkpoint bytes, the median post-restart context and the checkpoint's share of it
      (an estimate), from the <session id>.resumed-from records beside the log.

Every figure comes from that reading or from Claude Code's own transcripts; a
figure with no source is null, never 0 or an estimate. Dollars are list-price
equivalents of the transcripts' token counts (the owner, 2026-10-10): what the same
usage would cost on the pay-as-you-go API. The reading carries no
history, so each new sample is appended to <cache-dir>/limit-history.jsonl and
the chart draws from that file.
"""
import contextlib
import fcntl
import glob
import hashlib
import json
import os
import platform
import re
import shlex
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

WEEK = 7 * 86400
FIVE_HOURS = 5 * 3600
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
HISTORY_KEEP = 14 * 86400


@contextlib.contextmanager
def locked(path):
    """Held across one read-then-replace of path: the collector's, the server's layout save and --import each take it."""
    with open(path + ".lock", "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return None


def config_dir():
    """The Claude config folder main last started under (CLAUDE_CONFIG_DIR, dashboard.sh passes it on), or None for the default."""
    d = os.environ.get("CLAUDE_CONFIG_DIR") or ""
    return None if not d or os.path.realpath(d) == os.path.realpath(os.path.expanduser("~/.claude")) else d


def account():
    """{account, label} of the signed-in login: a hash of its uuid and a masked email; each None when unreadable."""
    d = config_dir()
    try:
        with open(os.path.join(d, ".claude.json") if d else os.path.expanduser("~/.claude.json")) as f:
            a = json.load(f).get("oauthAccount") or {}
    except (OSError, ValueError, AttributeError):
        a = {}
    uuid, email = a.get("accountUuid"), a.get("emailAddress")
    # The dashboard is reachable from the home network: the first letter and the domain only.
    label = f"{email[0]}…@{email.split('@', 1)[1]}" if isinstance(email, str) and "@" in email[1:] else None
    return {"account": hashlib.sha256(uuid.encode()).hexdigest()[:12] if isinstance(uuid, str) and uuid else None, "label": label}


def switch_account(cache_dir):
    """A reading cached for another account is that account's: drop it and its retry note, and move its history aside."""
    now = account()
    path = os.path.join(cache_dir, "claude-account.json")
    try:
        with open(path) as f:
            old = json.load(f)["account"]
    except (OSError, ValueError, LookupError, TypeError):
        old = "unknown"
    # No record (the release before this one, or a broken file): whose the reading is cannot be known, so it goes too.
    if now["account"] != old:
        for f in ("claude-usage", "claude-usage.retry"):
            try:
                os.remove(os.path.join(cache_dir, f))
            except OSError:
                pass
        hist = os.path.join(cache_dir, "limit-history.jsonl")
        with locked(hist):
            if os.path.exists(hist):
                os.replace(hist, os.path.join(cache_dir, f"limit-history.{old or 'unknown'}.jsonl"))
    tmp = f"{path}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(now, f)
    os.replace(tmp, path)
    return now


def token():
    # The same stores the statusline reads: the Mac keychain, else the credentials file.
    d = config_dir()
    if d:
        # shortcut: a non-default folder's keychain item name is not documented, so a Mac reads it as not measured;
        # upgrade when Claude Code documents it.
        if (os.environ.get("COMMANDECK_HOST_OS") or platform.system()) == "Darwin":
            return None
        try:
            with open(os.path.join(d, ".credentials.json")) as f:
                return json.load(f)["claudeAiOauth"]["accessToken"]
        except (OSError, ValueError, KeyError, TypeError):
            return None
    if (os.environ.get("COMMANDECK_HOST_OS") or platform.system()) == "Darwin":
        r = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                           capture_output=True, text=True)
        raw = r.stdout if r.returncode == 0 else ""
    else:
        try:
            with open(os.path.join(config_dir() or os.path.expanduser("~/.claude"), ".credentials.json")) as f:
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
        mac = (os.environ.get("COMMANDECK_HOST_OS") or platform.system()) == "Darwin"
        print("no login token" if not (config_dir() and mac) else
              f"not measured: the keychain item of the Claude config folder {config_dir()} is not known", file=sys.stderr)
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
    with locked(history_path):
        rows = read_history(history_path)
        if rows is None:
            return []  # unreadable: left as it is, not rewritten with this one sample
        if rows and rows[-1][0] >= at:
            return rows
        rows = [r for r in rows if r[0] >= now - HISTORY_KEEP] + [(at, pct)]
        tmp = f"{history_path}.{os.getpid()}"
        with open(tmp, "w") as f:
            f.writelines(json.dumps({"at": iso(a), "pct": p}) + "\n" for a, p in rows)
        os.replace(tmp, history_path)
    return rows


def read_history(path):
    """The history's rows, oldest first; [] with no file, None for one that is there and cannot be read, which
    no writer may replace as if it were empty."""
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
    except FileNotFoundError:
        pass
    except OSError:
        return None
    return sorted(rows)


def request_ids(r):
    """The ids one request is known by: message.id and requestId, else the line's uuid, else none.

    Behind an API proxy a line has no requestId (#47), but every assistant line
    carries message.id, shared by the lines a streamed request writes (each has
    its own uuid). A line may name either id or both, so lines that share
    either are one request (#51). The uuid is the last resort.
    """
    m = r.get("message")
    ids = [k for k in (m.get("id") if isinstance(m, dict) else None, r.get("requestId")) if isinstance(k, str) and k]
    u = r.get("uuid")
    return ids or ([u] if isinstance(u, str) and u else [])


def model_id(model):
    """A Claude model id as PRICES keys it: a proxy's 'claude-haiku-5.5', 'anthropic/claude-haiku-5-5' and
    'claude-haiku-5-5-20261001' are all 'claude-haiku-5-5' (#96). Any other id comes back as it was."""
    m = re.fullmatch(r"(?:[\w.-]*[/.])?(claude-[a-z]+)-(\d+)[.-](\d+)(?:-\d{8})?", model)
    return f"{m[1]}-{m[2]}-{m[3]}" if m else model


def request_row(r):
    """[time, model, input, 5-min cache write, 1-hour cache write, cache read, output] or None.

    A fast-mode request keeps the model name with a ":fast" suffix, so the price
    table never prices it at the standard rate. A count the usage lacks stays
    None, so a price that depends on the prompt size can tell unknown from zero.

    An advisor call is logged only as an "advisor_message" entry in
    usage.iterations: the top-level counts leave it out. Each one follows
    the seven fields as its own row of the same shape, under its own model.
    """
    at, msg = epoch(r.get("timestamp")), r.get("message")
    if r.get("type") != "assistant" or at is None or not isinstance(msg, dict):
        return None
    u = msg.get("usage") if isinstance(msg.get("usage"), dict) else {}
    n = lambda d, k: d.get(k) if isinstance(d.get(k), int) else None

    def counts(u, model):
        cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else None
        w5, w1 = (n(cc, "ephemeral_5m_input_tokens"), n(cc, "ephemeral_1h_input_tokens")) if cc else (n(u, "cache_creation_input_tokens"), 0)
        return [at, model, n(u, "input_tokens"), w5, w1, n(u, "cache_read_input_tokens"), n(u, "output_tokens")]

    its = u.get("iterations") if isinstance(u.get("iterations"), list) else []
    return counts(u, model_id(str(msg.get("model"))) + (":fast" if u.get("speed") == "fast" else "")) + [
        counts(i, model_id(str(i.get("model")))) for i in its if isinstance(i, dict) and i.get("type") == "advisor_message"]


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
# (luna: read 2026-10-14; a cache write is 1.25x input there too); prompts over 272K tokens take the long rate. A known tier
# prices every version of it (the owner's ruling, #36): a version other than the one the rate was read
# for is priced by tier, and says so. A name with no known tier, or any other part (-mini, a date,
# another mode), matches nothing and stays unpriced.
CODEX_NAME = re.compile(r"gpt-(\d+(?:\.\d+)?)-([a-z]+)(:fast)?")
CODEX_RULES = {  # tier: (version the rate was published for, {mode: (short-prompt rate, long-prompt rate)})
    "sol": ("6.1", {"": ((2.0, 10.0, 0.10), (4.0, 15.0, 0.20)), ":fast": ((4.0, 20.0, 0.20), (8.0, 30.0, 0.40))}),
    "luna": ("6", {"": ((0.10, 0.50, 0.01), (0.20, 0.75, 0.02)), ":fast": ((0.20, 1.00, 0.02), (0.40, 1.50, 0.04))}),
    "astra": ("6", {"": ((10.0, 50.0, 1.00), (20.0, 75.0, 2.00)), ":fast": ((20.0, 100.0, 2.00), (40.0, 150.0, 4.00))}),
}
CODEX_LONG_PROMPT = 272_000


def codex_rates(model):
    """(short-prompt rate, long-prompt rate) of a Codex model the rule prices by its name, or None."""
    m = CODEX_NAME.fullmatch(model)
    return CODEX_RULES.get(m.group(2), (None, {}))[1].get(m.group(3) or "") if m else None


def by_tier(row):
    """Whether this request, or an advisor call inside it, is priced by its Codex tier, not its exact version."""
    names = [CODEX_NAME.fullmatch(x[1]) for x in [row] + row[7:]]
    return any(m and m[2] in CODEX_RULES and m[1] != CODEX_RULES[m[2]][0] for m in names)


def listed(model):
    """Whether the model has a published price: a row of PRICES or a Codex rule."""
    return model in PRICES or codex_rates(model) is not None


UNREAD_TIER = ":tier-unread"  # a Codex response whose file never logged a speed tier (codex_row): priced as standard, estimated


def estimate(model):
    """The price of a mode the vendor does not publish: a fast mode is twice its model's standard rate, the multiple
    both vendors publish for the fast modes they do list; a response whose tier was never read is its model's
    standard rate. None when there is nothing near to estimate from."""
    if model.endswith(UNREAD_TIER):
        standard = model[:-len(UNREAD_TIER)]
        return PRICES.get(standard) or (codex_rates(standard) or (None,))[0]
    base = PRICES.get(model[:-5]) if model.endswith(":fast") else None
    return tuple(2 * x for x in base) if base else None


# An estimated fast mode steps up for long prompts where its model does: the same doubling, on the long rate.
LONG_PRICES.update({f"{m}:fast": tuple(2 * x for x in p) for m, p in list(LONG_PRICES.items())
                    if not m.endswith(":fast") and f"{m}:fast" not in PRICES})


def estimated(row):
    """Whether this request, or an advisor call inside it, is priced by estimate()."""
    return any(not listed(x[1]) and estimate(x[1]) is not None for x in [row] + row[7:])


def price(row):
    # A response of unread tier steps up for a long prompt where its model's standard rate does.
    codex = codex_rates(row[1][:-len(UNREAD_TIER)] if row[1].endswith(UNREAD_TIER) else row[1])
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


def gone(path):
    """Whether a folder is not there. One whose parent cannot be searched is there: what it holds is unknown."""
    try:
        os.stat(path)
    except (FileNotFoundError, NotADirectoryError):
        return True
    except OSError:
        return False
    return not os.path.isdir(path)


# One collect's stamp (dashboard.sh sets it per collect), so the readers of one collect share one read of the files.
CYCLE = os.environ.get("DASH_CYCLE") or None


def reuses(cache, since):
    """Whether a request cache an earlier call of this same collect wrote already holds every request from `since`
    on: whole, and read back that far. The units, the seats and the limit card each call from their own process,
    so only the first call of a collect reads the files (issue 299)."""
    held = cache.get("covered")
    return CYCLE is not None and cache.get("cycle") == CYCLE and cache.get("complete") is True \
        and isinstance(held, (int, float)) and held <= since


def remember_started(cache_dir, times):
    """Merge {transcript path: first line time, or None to forget it} into limit-started.json beside the request cache.

    Every entry whose transcript still exists stays, so projects sharing one transcript root and one cache never
    evict each other. A write that fails or is lost costs one started() open in a later cycle, never a wrong number.
    """
    path = os.path.join(cache_dir, "limit-started.json")
    try:
        with open(path) as f:
            memo = json.load(f)
        if not isinstance(memo, dict):
            raise ValueError("not a memo")
    except (OSError, ValueError):
        memo = {}
    memo.update(times)
    memo = {p: t for p, t in memo.items() if t is not None and os.path.exists(p)}
    tmp = f"{path}.{os.getpid()}"
    try:
        with open(tmp, "w") as f:
            json.dump(memo, f)
        os.replace(tmp, path)
    except OSError:
        pass


def requests(projects, cache_path, since, now, folders=False):
    """Each distinct API request's row from Claude Code's transcripts (subagents included) since `since`.

    A week of transcripts runs to gigabytes, so each file is read once from the
    byte offset the last call stopped at; the cache keeps every request's row,
    the working folder its session ran in and the transcript it came from. With
    `folders`, each row comes as (row, folder, transcript).
    None when a transcript is there and cannot be read: the rows would be short.
    """
    if not os.path.isdir(projects):
        return None
    try:
        with open(cache_path) as f:
            cache = json.load(f)
        offsets, seen, where, alias, file = cache["offsets"], cache["requests"], cache["cwd"], cache["alias"], cache["file"]
        # Version 6 keeps every id a request is known by (#52), version 7 its transcript: an older cache is read again.
        if cache.get("version") != 7 or not all(isinstance(v, list) for v in seen.values()) or not isinstance(where, dict) \
                or not isinstance(alias, dict) or not isinstance(file, dict):
            raise ValueError("cache from before a request kept its transcript")
        if cache.get("root") != projects:
            raise ValueError("another profile's transcripts: none of its rows are this root's")
        if reuses(cache, since):
            return [(v, where.get(k), file.get(k)) if folders else v for k, v in seen.items() if since <= v[0] <= now]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        offsets, seen, where, alias, file = {}, {}, {}, {}, {}
    live, unread, unlisted, firsts = {}, False, [], {}
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
            if st.st_size == off:
                live[path] = off  # nothing appended since the last read: not opened
                continue
            if st.st_size < off:
                # Rewritten in place: request ids are keys, so a re-read never double counts. Limit: the rows of the lines
                # the rewrite dropped stay cached (they are spend), so one can still count as the session's first call
                # and a warm rebuildUsd may differ from a cold read after a rewrite.
                off = 0
            # Line by line: the Linux service caps the collector at 256 MB.
            try:
                f = open(path, "rb")
            except FileNotFoundError:
                continue  # gone since the listing: the rows it gave are in the cache
            except OSError:
                unread = True  # the other transcripts are still read, for the next call
                continue
            # A read from 0 (new, or rewritten smaller) notes the transcript's first line time for seats(), so
            # started() need not open it again. shortcut: a file rewritten to the same or a larger size is missed
            # here as it is above; key the memo by inode if that ever happens.
            first = off == 0
            if first:
                firsts[path] = None
            with f:
                f.seek(off)
                for line in f:
                    if not line.endswith(b"\n"):
                        break  # a half-written last line waits for the next call
                    off += len(line)
                    if first and b'"timestamp"' in line:
                        try:
                            t = epoch(json.loads(line).get("timestamp"))
                        except (ValueError, AttributeError):
                            t = None
                        if t is not None:
                            firsts[path], first = t, False
                    if b'"usage"' not in line:
                        continue
                    try:
                        r = json.loads(line)
                    except ValueError:
                        continue
                    row = request_row(r) if isinstance(r, dict) else None
                    ids = request_ids(r) if row else []
                    if not ids:
                        continue
                    # A request is kept under the key its ids already have; a line naming two keys joins them.
                    keys = list(dict.fromkeys(alias[i] for i in ids if i in alias)) or ids[:1]
                    for old in keys[1:]:
                        seen.pop(old, None)
                        where.pop(old, None)
                        file.pop(old, None)
                        alias.update({i: keys[0] for i, k in alias.items() if k == old})
                    alias.update(dict.fromkeys(ids, keys[0]))
                    seen[keys[0]] = row  # a streamed request's last line carries its final usage
                    where[keys[0]] = r.get("cwd")
                    file[keys[0]] = path
            live[path] = off
    seen = {k: v for k, v in seen.items() if v[0] >= now - 2 * WEEK}
    whole = not unread and all(isinstance(e, FileNotFoundError) for e in unlisted)
    tmp = f"{cache_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump({"version": 7, "offsets": live, "requests": seen, "cwd": {k: where.get(k) for k in seen},
                   "alias": {i: k for i, k in alias.items() if k in seen}, "file": {k: file.get(k) for k in seen},
                   "cycle": CYCLE, "complete": whole, "covered": since, "root": projects}, f)
    os.replace(tmp, cache_path)
    if firsts:
        remember_started(os.path.dirname(cache_path), firsts)
    if not whole:
        return None
    return [(v, where.get(k), file.get(k)) if folders else v for k, v in seen.items() if since <= v[0] <= now]


# Issue 269, the Tests card's finished runs: each Bash call that ran a test runner, paired with its result, read from
# the same transcripts requests() walks, and kept in a cache of its own (the limit card's is untouched).
# A call is a run only when it starts, after an optional `cd <dir> && ` and VAR=value words, with one of: `npm test`,
# `npm run test*`, `bash <file>.test.sh`, a test wrapper (run-shell-tests.sh), or `node --test`. Any other call is not
# measured, however it is spelled. The run (group "run") ends at the first unquoted separator or redirect.
TEST_COMMAND = re.compile(
    r"""\s*(?:cd \S+ && )?(?:\w+=\S* )*(?P<run>(?:npm test|npm run test[\w:.-]*|(?:bash|sh) \S*\.test\.sh"""
    r"""|(?:(?:bash|sh) )?\S*run-shell-tests\.sh|node --test)(?=[\s;&|<>]|$)"""
    r"""(?:'[^']*'|"[^"]*"|(?!\s+(?:\d*|&)>)[^;&|\n'"<>])*)""")
# The rest of the call's words up to the first unquoted separator. A help, version, dry-run, check, print or eval
# word anywhere in them means the call prints information and runs no test. shortcut: npm's abbreviations (`--usag`)
# and glommed shorthands (`-sv`) are not read; upgrade if one is ever seen.
TEST_ARGS = re.compile(r"""(?:'[^']*'|"[^"]*"|[<>]+[|&]?|&>>?|[^;&|\n'"<>])*""")
TEST_NOT_A_RUN = re.compile(r"--?(?:help|version|versions|usage|dry-run|if-present|check|print|eval|[hvVcpe?])(?:=.*)?")
# What after the run hides its exit: a pipe, `||`, `;`, a newline or a lone `&` (`&&` stops at the first failure).
TEST_EXIT_MASK = re.compile(r"[|;\n]|(?<!&)&(?!&)")
TEST_REDIRECT = re.compile(r"\s*(?:\d*>>?\s*&?|&>>?\s*)[^\s;&|]+")
# A background run's completion: the task notification Claude Code logs in place of a tool result.
TEST_NOTE = re.compile(r"<task-notification>.*?</task-notification>", re.S)


def test_segment(cmd):
    """The test run a Bash command starts (TEST_COMMAND), else None. Ceiling: only the first run of a chain is named."""
    m = TEST_COMMAND.match(cmd)
    if not m:
        return None
    try:
        words = shlex.split(m.group(0) + TEST_ARGS.match(cmd, m.end()).group(0))
    except ValueError:  # quoting shlex cannot close: not measured rather than guessed
        return None
    if any(TEST_NOT_A_RUN.fullmatch(w) for w in words):
        return None
    return m.group("run").strip()[:300]


def exit_masked(cmd):
    """Whether the Bash call's exit status may not be its run's: a pipe, `||`, `;`, a newline or a lone `&` after it."""
    m = TEST_COMMAND.match(cmd)
    return bool(m and TEST_EXIT_MASK.search(TEST_REDIRECT.sub("", cmd[m.end():])))


def test_counts(out):
    """(passed, failed) from the runner's own summary lines, summed over every suite a call ran: node's `pass N` and
    `fail N`, a shell test file's `N passed, M failed` and run-shell-tests.sh's `N passed, M failed, K parked`; else
    nulls."""
    sh = re.findall(r"^(\d+) passed, (\d+) failed(?:, \d+ parked)?", out, re.M)
    node = [re.findall(r"^(?:# |ℹ )%s (\d+)" % k, out, re.M) for k in ("pass", "fail")]
    if not (sh or node[0] or node[1]):
        return None, None
    return sum(int(p) for p, _ in sh) + sum(map(int, node[0])), sum(int(f) for _, f in sh) + sum(map(int, node[1]))


def test_result(is_error, passed, failed, masked):
    """failed on a failing exit or any failure the runner printed; passed on printed counts or an exit nothing could
    mask; else unknown, never a guessed pass."""
    if is_error or (failed or 0) > 0:
        return "failed"
    return "passed" if passed is not None or not masked else "unknown"


def output_tail(path):
    """The last 64 KB of a background run's output file, or "" once the file is gone."""
    try:
        with open(path, "rb") as f:
            f.seek(max(0, os.fstat(f.fileno()).st_size - 65536))
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def finish_run(pending, runs, path, tool_id, t, body, is_error):
    start, where, cmd, _, masked = pending.pop(tool_id)
    passed, failed = test_counts(body)
    runs.append([t, round(max(0, t - start)), where, cmd, test_result(is_error, passed, failed, masked), passed, failed, start, path])


def test_line(r, pending, runs, path):
    """One transcript line into the file's pending runs: a runner call waits there; its result completes a run, or for
    a background call its task notification (the first of the records that repeat it)."""
    t, content = epoch(r.get("timestamp")), (r.get("message") or {}).get("content")
    if t is None:
        return
    text = r.get("content") if isinstance(r.get("content"), str) else content
    if isinstance(text, str):
        for note in TEST_NOTE.findall(text):
            tid, code = re.search(r"<tool-use-id>([^<]+)</tool-use-id>", note), re.search(r"\(exit code (\d+)\)", note)
            status = re.search(r"<status>(\w+)</status>", note)
            p = pending.get(tid.group(1)) if tid else None
            if not p or not p[3]:
                continue
            if code is None and not (status and status.group(1) in ("completed", "failed")):
                pending.pop(tid.group(1))  # killed or stopped: the run never finished
                continue
            out = re.search(r"<output-file>([^<]+)</output-file>", note)
            finish_run(pending, runs, path, tid.group(1), t, output_tail(out.group(1)) if out else "",
                       code.group(1) != "0" if code else status.group(1) == "failed")
        return
    for c in content if isinstance(content, list) else []:
        if not isinstance(c, dict):
            continue
        if c.get("type") == "tool_use" and c.get("name") == "Bash":
            inp = c.get("input") or {}
            full = inp.get("command") if isinstance(inp.get("command"), str) else ""
            cmd = test_segment(full)
            if cmd:
                # A background call's tool result only says it started; its task notification completes it.
                pending[c.get("id")] = [t, r.get("cwd"), cmd, bool(inp.get("run_in_background")), exit_masked(full)]
        elif c.get("type") == "tool_result" and c.get("tool_use_id") in pending and not pending[c["tool_use_id"]][3]:
            body = c.get("content")
            if isinstance(body, list):
                body = "".join(b.get("text", "") for b in body if isinstance(b, dict))
            finish_run(pending, runs, path, c["tool_use_id"], t, body if isinstance(body, str) else "", bool(c.get("is_error")))


def test_runs(projects, cache_path, now, roots, builders=()):
    """The last day's finished test runs run in `roots`, and each command's usual time; None when the transcripts
    cannot be read whole. Usual time = median seconds of the same command over the week, from 3 runs.
    `testSecToday` is today's test seconds; `builderShare` the part of the Builder sessions' span today (their
    transcripts' first to last line, from midnight, summed) spent in test runs under a `builders` folder, else None."""
    if not os.path.isdir(projects):
        return None
    since = now - WEEK
    midnight = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    # The cache is keyed to this file's bytes: a run is classified once, when read, so any change to the parser
    # must read the week's transcripts again rather than keep what an older one cached.
    with open(__file__, "rb") as f:
        version = hashlib.sha256(f.read()).hexdigest()
    unread = []
    with locked(cache_path):
        try:
            with open(cache_path) as f:
                cache = json.load(f)
            if cache["version"] != version:
                raise ValueError("cache from another version of this script")
            offsets, files, runs, spans = cache["offsets"], cache["files"], cache["runs"], cache["spans"]
        except (OSError, ValueError, KeyError, TypeError):
            offsets, files, runs, spans = {}, {}, [], {}
        live = {}
        for root, _, names in os.walk(projects, onerror=unread.append):
            for name in names:
                path = os.path.join(root, name)
                try:
                    if not name.endswith(".jsonl") or os.stat(path).st_mtime < since:
                        continue
                    size, off = os.stat(path).st_size, offsets.get(path, 0)
                    pending = files.get(path)
                    if pending is None or size < off:  # a file rewritten in place is read again from its start
                        off, pending = 0, {}
                        runs = [r for r in runs if r[8] != path]
                        spans[path] = [None, None, None]
                    span = spans.setdefault(path, [None, None, None])  # first and last line time, and the session's folder
                    with open(path, "rb") as f:
                        f.seek(off)
                        for line in f:
                            if not line.endswith(b"\n"):
                                break  # a half-written last line waits for the next call
                            off += len(line)
                            i = line.find(b'"timestamp":"')
                            # To the closing quote: a stamp with no milliseconds is shorter than the usual 24 bytes.
                            at = epoch(line[i + 13:line.find(b'"', i + 13)].decode("ascii", "replace")) if i >= 0 else None
                            if at is not None:
                                span[0] = span[0] if span[0] is not None else at
                                span[1] = at
                            if span[2] is None and (m := re.search(rb'"cwd":"((?:[^"\\]|\\.)*)"', line)):
                                try:
                                    span[2] = json.loads(b'"' + m[1] + b'"')
                                except ValueError:
                                    pass
                            keys = [k.encode() for k in pending if isinstance(k, str)]
                            if (b'"tool_use"' in line and b'"name":"Bash"' in line) \
                                    or (keys and (b'"tool_result"' in line or b"<task-notification>" in line) and any(k in line for k in keys)):
                                try:
                                    r = json.loads(line)
                                except ValueError:
                                    continue
                                if isinstance(r, dict):
                                    test_line(r, pending, runs, path)
                    live[path], files[path] = off, pending
                except OSError as e:
                    unread.append(e)
        runs = [r for r in runs if r[0] >= since]
        tmp = f"{cache_path}.{os.getpid()}"
        with open(tmp, "w") as f:
            json.dump({"version": version, "offsets": live, "files": {p: files[p] for p in live}, "runs": runs, "spans": {p: spans[p] for p in live}}, f)
        os.replace(tmp, cache_path)
    if unread:
        print(f"dashboard_limit: {len(unread)} transcript path(s) could not be read, so test runs are unknown: {unread[0]}", file=sys.stderr)
        return None
    took = {}
    for r in runs:
        if under(r[2], roots):  # another project's `npm test` is another suite
            took.setdefault(r[3], []).append(r[1])
    usual = {c: round(statistics.median(v)) for c, v in took.items() if len(v) >= 3}
    # A run that began before midnight counts its seconds from midnight, as the Builders' clock does.
    today = [(r, round(max(0, r[0] - max(r[7], midnight)))) for r in runs if r[0] >= midnight and under(r[2], roots)]
    span = sum(max(0, sp[1] - max(sp[0], midnight)) for sp in spans.values() if sp[1] is not None and sp[1] >= midnight and under(sp[2], builders))
    return {"testSecToday": sum(sec for _, sec in today),
            "builderShare": sum(sec for r, sec in today if under(r[2], builders)) / span if builders and span > 0 else None,
            "finished": [{"when": iso(r[0]), "start": iso(r[7]), "cwd": r[2], "what": r[3], "took": r[1], "result": r[4],
                          "passed": r[5], "failed": r[6], "usual": usual.get(r[3])}
                         for r in sorted(runs, key=lambda r: -r[0]) if r[0] >= now - 86400 and under(r[2], roots)][:100],
            "usual": [{"cmd": c, "sec": s, "n": len(took[c])} for c, s in usual.items()]}


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
    rows = record(path, int(at), cx["usedPct"], now) if at is not None else read_history(path) or []
    return [{"at": iso(a), "pct": p} for a, p in rows if start <= a <= now]


def api_base_url():
    """Whether Claude is reached through an API base URL (a proxy): ANTHROPIC_BASE_URL in the environment or in
    the env block of ~/.claude/settings.json. Such a machine has no subscription usage windows (#97)."""
    if os.environ.get("ANTHROPIC_BASE_URL"):
        return True
    try:
        with open(os.path.join(os.path.expanduser("~"), ".claude", "settings.json")) as f:
            env = json.load(f).get("env")
    except (OSError, ValueError, AttributeError):
        return False
    return isinstance(env, dict) and bool(env.get("ANTHROPIC_BASE_URL"))


def codex_billing(sessions_dir):
    """How Codex is signed in, from auth.json in its home (the sessions folder's parent): "subscription" for a
    ChatGPT login, "api" for an API key, "none" with no file, None when it cannot be read or no sessions folder
    is given. Only the kind is read, never a token. Only "api" and "none" hide the Codex 7-day tile: an unknown
    never does. Codex keeps a sign-in out of auth.json when config.toml names any cli_auth_credentials_store but
    "file" (keyring, auto, ephemeral; in any profile): no auth.json is then unknown, not "none". With keyring or
    ephemeral Codex reads no auth.json at all, so one left from before is unknown too. build() also reads "none"
    with a live 7-day reading as unknown."""
    if not sessions_dir:
        return None
    home = os.path.dirname(os.path.abspath(sessions_dir))
    try:
        import tomllib  # Python 3.11+, a stated requirement; without it the sign-in is unknown, not "none"
        with open(os.path.join(home, "config.toml"), "rb") as f:
            cfg = tomllib.load(f)
    except FileNotFoundError:
        cfg = {}
    except (ImportError, OSError, ValueError):
        return None
    profiles = cfg.get("profiles")
    tables = [cfg] + [p for p in (profiles.values() if isinstance(profiles, dict) else ()) if isinstance(p, dict)]
    key = "cli_auth_credentials_store"
    # A value that is not a string (a number, a list) is unknown, like any store but "file" or "auto".
    stores = {t[key] if isinstance(t[key], str) else None for t in tables if key in t}
    if stores - {"file", "auto"}:
        return None
    try:
        with open(os.path.join(home, "auth.json")) as f:
            a = json.load(f)
    except FileNotFoundError:
        return "none" if stores <= {"file"} else None
    except (OSError, ValueError):
        return None
    if not isinstance(a, dict):
        return None
    mode = a.get("auth_mode")
    if mode in ("chatgpt", "apikey"):
        return "subscription" if mode == "chatgpt" else "api"
    if isinstance(a.get("tokens"), dict):
        return "subscription"
    return "api" if a.get("OPENAI_API_KEY") else "none"


def billing(cache_dir):
    """("subscription" | "api", weekly limit in dollars or None), from billing.json beside the cache folder.

    The file is {"billing": "api", "weeklyLimitUsd": 1000}. With no "billing" key there, or no file, a machine
    that reaches Claude through an API base URL is the API panel and any other is the subscription panel; the
    file's own "billing" word wins over that.
    """
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(cache_dir)), "billing.json")) as f:
            b = json.load(f)
    except (OSError, ValueError):
        b = None
    b = b if isinstance(b, dict) else {}
    if b.get("billing", "api" if api_base_url() else "subscription") != "api":
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
    # A tier the file never logged (None) is unread: priced as standard and counted as estimated. A tier the log
    # read as null reaches here as "default": standard, read. Any other name stays in the model name, priced only if listed.
    mode = UNREAD_TIER if tier is None else "" if tier == "default" else ":fast" if tier == "priority" else f":{tier}"
    return [epoch(r["timestamp"]), f"{model or 'unknown Codex model'}{mode}",
            None if inp is None else max(0, inp - (read or 0) - (write or 0)), write, 0, read, n(u, "output_tokens")]


# The review Codex home every session reader searches: its spend counts beside the main home's.
REVIEW_HOME = os.environ.get("COMMANDECK_CODEX_REVIEW_HOME") or os.path.expanduser("~/.codex-review")


def codex_all(sessions, cache_dir, stem, since, now, missed, folders=False):
    """codex_requests() on `sessions` and on the review home's sessions folder, joined; None when neither is there."""
    review = os.path.join(REVIEW_HOME, "sessions")
    got = [codex_requests(sessions, os.path.join(cache_dir, f"{stem}.json"), since, now, missed, folders)]
    if not sessions or os.path.realpath(sessions) != os.path.realpath(review):
        got.append(codex_requests(review, os.path.join(cache_dir, f"{stem}-review.json"), since, now, missed, folders))
    got = [g for g in got if g is not None]
    return sum(got, []) if got else None


def codex_requests(sessions_dir, cache_path, since, now, missed=None, folders=False):
    """Each Codex response's row, in request_row's shape, from the session files since `since`.

    A `token_usage_record` holds one response's counts. Its input count includes the cached and
    cache-written tokens, so the row's input is what is left. The model is the file's last `turn_context`
    or `thread_settings_applied`; the speed tier is logged only by the latter ("priority" is the vendor's
    fast mode). Both are kept per file beside the byte offset, so a later call that starts past them still
    knows them, as is the working folder the file's `session_meta` names, which `folders` pairs each row with,
    and the file itself, as in requests(). The walk and the cache are requests()'s, with that state added.

    A file or folder that cannot be opened is appended to `missed`: what it spent is unknown, so the caller
    must not call the week complete. One that has gone since it was listed spent nothing unseen.
    """
    missed = [] if missed is None else missed
    lost = lambda e: None if isinstance(e, FileNotFoundError) else missed.append(e.filename)
    if not sessions_dir or gone(sessions_dir):
        return None
    try:
        with open(cache_path) as f:
            cache = json.load(f)
        files, seen, where, file = cache["files"], cache["requests"], cache["cwd"], cache["file"]
        # Version 3 keeps each response's working folder, version 4 its file, version 5 prices a response whose file never logged its tier as unread (standard, estimated); an older cache is read again.
        if cache.get("version") != 5 or not isinstance(files, dict) or not isinstance(seen, dict) or not isinstance(where, dict) \
                or not isinstance(file, dict):
            raise ValueError("not this reader's cache")
        if cache.get("root") != sessions_dir:
            raise ValueError("another Codex home's sessions: none of its rows are this home's")
        if reuses(cache, since):
            return [(v, where.get(k), file.get(k)) if folders else v for k, v in seen.items() if since <= v[0] <= now]
    except (OSError, ValueError, KeyError, TypeError):
        files, seen, where, file = {}, {}, {}, {}
    live, n = {}, len(missed)
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
                if isinstance(files.get(path), list) and files[path][:1] == [st.st_size]:
                    live[path] = files[path]  # nothing appended since the last read: not opened
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
                        model, tier = s.get("model") if isinstance(s.get("model"), str) else model, "default" if s.get("service_tier") is None else s["service_tier"]
                    elif r.get("type") == "turn_context" and isinstance(p.get("model"), str):
                        model = p["model"]
                    elif r.get("type") == "token_usage_record" and codex_row(r, model, tier):
                        seen[p["response_id"]] = codex_row(r, model, tier)
                        where[p["response_id"]] = cwd
                        file[p["response_id"]] = path
                    elif r.get("type") == "token_usage_record":
                        # Never dropped: a usage line this reader cannot use is spend of unknown size, kept as a
                        # request with no counts so the week reads it as unpriced. Keyed by where it sits in the file.
                        at = epoch(r.get("timestamp"))
                        seen[f"unreadable:{path}:{off}"] = [min(int(st.st_mtime), now) if at is None else at,
                                                            "unreadable Codex record", None, None, 0, None, None]
                        where[f"unreadable:{path}:{off}"] = cwd
                        file[f"unreadable:{path}:{off}"] = path
            live[path] = [off, model, tier, cwd]
    seen = {k: v for k, v in seen.items() if v[0] >= now - 2 * WEEK}
    tmp = f"{cache_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump({"version": 5, "files": live, "requests": seen, "cwd": {k: where.get(k) for k in seen}, "file": {k: file.get(k) for k in seen},
                   "cycle": CYCLE, "complete": len(missed) == n, "covered": since, "root": sessions_dir}, f)
    os.replace(tmp, cache_path)
    return [(v, where.get(k), file.get(k)) if folders else v for k, v in seen.items() if since <= v[0] <= now]


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
           "claudeUsd": None, "codexUsd": None, "estimatedUsd": None, "tierUsd": None, "unpricedModels": None, "complete": False}
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
               estimatedUsd=sum(c for r, _, c in costs if c is not None and estimated(r)),
               tierUsd=sum(c for r, _, c in costs if c is not None and by_tier(r)))
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
        rows = read_history(hist_path) or []
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
        "accountLabel": account()["label"],
    })
    out["codex"]["history"] = codex_history(cache_dir, out["codex"], now)
    # The subscription keys above are the same in both modes; API mode adds its own block beside them.
    mode, limit = billing(cache_dir)
    out["billing"] = mode
    cb = codex_billing(sessions)
    out["codexBilling"] = None if cb == "none" and out["codex"]["usedPct"] is not None else cb
    out["api"] = None
    if mode == "api":
        monday = epoch(api_week(None, None, now)["windowStart"])
        missed = []
        codex_rows = codex_all(sessions, cache_dir, "codex-requests", monday, now, missed)
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
        out["cost"] = {**cost([r for r, _, _ in day], 0, midnight, now), "week": None, "unpricedRequests": None}
    codex_day = codex_all(sessions, cache_dir, "codex-requests", midnight, now, lost, True)
    # A session is one project's: where one checkout sits inside another, the innermost root that holds it wins.
    roots = sorted(((r, name) for name, rs in (day_projects or {}).items() for r in rs if isinstance(r, str)), key=lambda t: -len(t[0].rstrip("/")))
    owner = lambda folder: next((name for r, name in roots if under(folder, [r])), None)
    own = lambda rows, name: None if rows is None else [r for r, folder, _ in rows if owner(folder) == name]
    out["today"] = {}
    for name in day_projects or {}:
        t = api_week(None, own(day, name), now, own(codex_day, name), bool(lost), midnight)
        out["today"][name] = {k: t[k] for k in ("windowStart", "spentUsd", "claudeUsd", "codexUsd", "estimatedUsd", "tierUsd", "requests",
                                                "unpricedRequests", "unpricedModels", "complete")}
    json.dump(out, sys.stdout)
    return 0


def tally(rows, sec):
    """One stage's figures (#94): seconds, model calls, tokens in (and the cached part), out, list-price $.

    A request with no price leaves the dollars a floor: partial, with the models that have no price named."""
    parts = [x for r in rows for x in [r] + r[7:]]
    n = lambda i: sum(x[i] for x in parts if isinstance(x[i], int))
    priced = [price(r) for r in rows]
    return {"sec": sec, "calls": len(rows), "input": n(2) + n(3) + n(4) + n(5), "cached": n(5), "output": n(6),
            "usd": round(sum(p for p in priced if p is not None), 4), "partial": None in priced, "unpriced": unpriced_models(rows)}


def by_agent(claude, codex):
    """A total's Claude and Codex parts: None for an agent with an unpriced call, never $0 or a guess; 0 with no call."""
    out = {}
    for agent, rows in (("claude", claude), ("codex", codex)):
        t = tally(rows, 0)
        out[agent] = None if t["partial"] else t["usd"]
    return out


def seat_costs(seats, rows, folder, now):
    """A planning stage's requests by the seat that made them; `rows` are (row, folder, file, agent).

    A seat holds a request when its file is the seat's session: a Claude id is `<folder>/<id>.jsonl`, whose helpers
    and sub-agents write under `<folder>/<id>/`; a path (the seat ledger's, a Codex log) is that file. A seat's time
    runs from its launch to its collect, else to its last request so far. A request two seats claim (their lookups
    found one log) is neither's. What no seat holds is one entry with no role, so the seats always sum to the stage.
    """
    claims = []
    # Compared real, as unit_costs reads homes: a seat's path spelled through a symlink or a "." names the same log.
    real = {p: os.path.realpath(p) for p in {t[2] for t in rows if isinstance(t[2], str)}}
    for s in seats or []:
        f = s.get("session") if isinstance(s.get("session"), str) and s.get("session") else None
        if f and not os.path.isabs(f):
            f = os.path.join(folder, f + ".jsonl")
        f = f and os.path.realpath(f)
        claims.append([i for i, t in enumerate(rows) if f and t[2] in real and (real[t[2]] == f or (f.endswith(".jsonl") and real[t[2]].startswith(f[:-6] + "/")))])
    count = Counter(i for k in claims for i in k)
    out, held = [], {i for i, n in count.items() if n == 1}
    for s, k in zip(seats or [], claims):
        k = [i for i in k if i in held]
        a, b = epoch(s.get("from")), epoch(s.get("completedAt")) or max((rows[i][0][0] for i in k), default=now)
        out.append({"role": s.get("role"), "model": s.get("model"), "effort": s.get("effort"), "from": s.get("from"), "to": s.get("completedAt"),
                    **tally([rows[i][0] for i in k], round(max(0, b - a)) if a else 0)})
    rest = [t[0] for i, t in enumerate(rows) if i not in held]
    if rest:
        out.append({"role": None, "model": None, "effort": None, "from": None, "to": None, **tally(rest, 0)})
    return out


def unit_costs(units, now, cache_dir, projects, sessions):
    """Each Builder's cost by stage, from the requests its own worktree's sessions made (#94).

    `units` is [{unit, worktree, stages: [{stage, from, to}], plan}] (dashboard_builders.jq's stageHistory). A
    request belongs to the unit when its session ran in the worktree: the Builder, its helpers and Workflow
    sub-agents (their transcripts sit under the worktree's own projects folder) and its review passes,
    Claude's or Codex's. Main works in the main checkout, so its own requests are never counted. A request
    goes to the stage it was made in; one before the first stage (the session's opening) to the first.
    A `plan` ({worktree, from, seats}: dashboard.sh plan_seats) adds its planning worktree's requests as a first
    stage, "planning", into the total, and split by seat (seat_costs) as `seats`. A planning worktree's own
    card is a unit whose worktree is its plan's, with no other stage.
    None for a unit whose requests cannot all be read: a short total would read as the whole. The transcripts are
    one read of the whole tree, shared with the seats and the limit card (issue 299), so any transcript that cannot
    be read makes every unit None.
    """
    start = lambda u: epoch(u["plan"]["from"]) if u.get("plan") else epoch(u["stages"][0]["from"]) if u.get("stages") else None
    starts = {u["unit"]: start(u) for u in units}
    since = min((t for t in starts.values() if t is not None), default=None)
    if since is None:
        return {}
    missed = []
    # No sessions folder is an install without Codex: no Codex review ran, so it adds nothing rather than unknown.
    cx = codex_all(sessions, cache_dir, "codex-requests", since - 600, now, missed, True) or []
    # A collected Codex seat may have run in another Codex home (routing's per-role codexHome): that home's whole
    # sessions tree is read too, as its earlier launches log in other date folders (<home>/sessions/YYYY/MM/DD).
    # Each home's cache is keyed by a hash of its path: a punctuation-folded key gave two homes one cache.
    # Paths are compared real: a log spelled through a symlink or a "." is still in the home already read.
    home = lambda f: (re.match(r"(.*/sessions)/\d{4}/\d{2}/\d{2}/[^/]+$", f) or re.match(r"(.*)/[^/]+$", f)).group(1)
    read = [os.path.realpath(r) for r in (sessions, projects, os.path.join(REVIEW_HOME, "sessions")) if r]
    other = {home(os.path.realpath(s["session"])) for u in units for s in ((u.get("plan") or {}).get("seats") or [])
             if isinstance(s.get("session"), str) and os.path.isabs(s["session"]) and not under(os.path.realpath(s["session"]), read)}
    for d in sorted(other):
        if cx is not None and not gone(d):
            key = hashlib.sha256(d.encode()).hexdigest()[:16]
            more = codex_requests(d, os.path.join(cache_dir, f"unit-codex-{key}.json"), since - 600, now, missed, True)
            cx = None if more is None else cx + more
    # Claude Code's folder for a session run in a worktree: every byte that is not a letter or digit becomes "-".
    folder = lambda wt: os.path.join(projects, re.sub(r"[^A-Za-z0-9]", "-", wt))
    every = [] if gone(projects) else requests(projects, os.path.join(cache_dir, "limit-requests.json"), since - 600, now, True)
    out = {}
    for u in units:
        t0, wt, plan = starts.get(u["unit"]), u["worktree"], u.get("plan")
        if t0 is None:
            continue
        pwt = plan["worktree"] if plan else None
        got = {w: None if every is None else [t for t in every if t[0][0] >= t0 - 600 and (t[2] or "").startswith(folder(w) + os.sep)]
               for w in {wt, pwt} - {None}}
        if None in got.values() or cx is None or missed:
            out[u["unit"]] = None
            continue
        mine = lambda w: sorted([(r, f, p, a) for a, src in (("claude", got[w]), ("codex", cx)) for r, f, p in src
                                 if under(f, [w]) and r[0] <= now], key=lambda t: t[0][0])
        build, planned = mine(wt) if wt != pwt else [], mine(pwt) if plan else []
        if wt == pwt and u["stages"]:
            # The Builder took over its plan's worktree (issue 242): the build's requests are the ones from its first stage on.
            t1 = epoch(u["stages"][0]["from"])
            build, planned = [t for t in planned if t[0][0] >= t1], [t for t in planned if t[0][0] < t1]
        rows = [t[0] for t in build]
        bounds = [(epoch(s["from"]), epoch(s["to"]) if s.get("to") else now) for s in u["stages"]]
        stages = []
        for i, (s, (a, b)) in enumerate(zip(u["stages"], bounds)):
            mine_ = [r for r in rows if (i == 0 or r[0] >= a) and (r[0] < b or (i == len(bounds) - 1 and r[0] <= now))]
            stages.append({"stage": s["stage"], "from": s["from"], "to": s.get("to"), **tally(mine_, round(max(0, b - a)))})
        seats = {}
        if plan:
            to = u["stages"][0]["from"] if u["stages"] else None
            stages.insert(0, {"stage": "planning", "from": plan["from"], "to": to, **tally([t[0] for t in planned], round(max(0, (epoch(to) or now) - t0)))})
            seats = {"seats": seat_costs(plan.get("seats"), planned, folder(pwt), now)}
        # The last stage is always the open one (stageHistory), so the build has run from its start to now.
        both = build + planned
        part = lambda a: [t[0] for t in both if t[3] == a]
        out[u["unit"]] = {"stages": stages, "total": {**tally([t[0] for t in both], round(max(0, now - t0))), "byAgent": by_agent(part("claude"), part("codex"))}, **seats}
    return out


def seats(now, cache_dir, projects, log, main, relay=None):
    """Main's and the relay's own figures (issue 224), {main, relay}: no relay key with no relay configured.

    A seat's sessions are its checkout's projects folder: main's is the main checkout's (the one unit_costs leaves
    out), the relay's the Chief-of-Staff worktree's. Today runs from host-local midnight; the 7-day average is the
    seven days before today over 7 (today is not in it: Today is compared with it). Also, per seat: `live` (a request in
    the last 10 minutes), `hourly` (the last 12 hours' tokens), `week` (sessions and their tokens over the last 7 x 24 h),
    main's `rebuildUsd` (the mean cost of the first call of each session begun today: what a restart costs to rebuild)
    and the relay's `sideRuns` (the sub-agent runs it made today, {count, usd}). A restart is a clear-hook.log line of a completed one (context-clear-restart.sh) whose
    checkpoint, <session id>.md, is one of the seat's sessions; its `.restarted` stamp keeps only a checkpoint's
    last restart, so the log is the one source. None for a seat whose sessions cannot all be read: with the whole
    tree read once, any transcript that cannot be read.
    """
    midnight = datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    week = now - 7 * 86400
    before = midnight - 7 * 86400
    done = []
    try:
        with open(log, errors="replace") as f:
            for line in f:
                m = re.match(r"(\S+) restart: new pane \S+ resumed from (\S+)\.md; closing ", line)
                try:
                    if m:
                        done.append((datetime.fromisoformat(m[1]).timestamp(), os.path.basename(m[2])))
                except ValueError:
                    pass
    except OSError:
        pass
    figures = lambda rs: (lambda t: {"tokens": t["input"] + t["output"], "usd": t["usd"], "partial": t["partial"]})(tally(rs, 0))
    out = {}
    # One read of the whole transcript tree, shared with the units and the limit card (issue 299).
    every = [] if gone(projects) else requests(projects, os.path.join(cache_dir, "limit-requests.json"), min(week, before), now, True)
    for name, wt in (("main", main), ("relay", relay)):
        if not wt:
            continue
        folder = os.path.join(projects, re.sub(r"[^A-Za-z0-9]", "-", wt))
        mine = [] if gone(folder) else None if every is None else [(r, f[len(folder) + 1:]) for r, _, f in every if (f or "").startswith(folder + os.sep)]
        if mine is None:
            out[name] = None
            continue
        # A transcript is <session id>.jsonl, or under <session id>/ for a sub-agent's (a sidechain with a context of its own).
        rows = [r for r, _ in mine]
        sess = lambda rel: re.sub(r"\.jsonl$", "", rel.split(os.sep)[0])
        wk = figures([r for r in rows if before <= r[0] < midnight])
        sessions = {}
        for r, rel in mine:
            if week <= r[0] <= now:
                sessions.setdefault(sess(rel), []).append(r)
        whole = [rs for rs in sessions.values() if all(isinstance(n, int) for r in rs for x in [r] + r[7:] for n in x[2:7])]
        t = tally([r for rs in whole for r in rs], 0)
        times = sorted(at for at, sid in done if midnight <= at <= now and os.path.exists(os.path.join(folder, sid + ".jsonl")))
        out[name] = {"today": figures([r for r in rows if midnight <= r[0] <= now]),
                     "avg7": {"tokens": round(wk["tokens"] / 7), "usd": round(wk["usd"] / 7, 4), "partial": wk["partial"]},
                     "live": any(now - 600 <= r[0] <= now for r in rows),
                     "hourly": [figures([r for r in rows if now - (12 - i) * 3600 <= r[0] < now - (11 - i) * 3600])["tokens"] for i in range(12)],
                     "week": {"sessions": len(sessions), "unmeasuredSessions": len(sessions) - len(whole),
                              "input": t["input"] if whole else None, "cachedInput": t["cached"] if whole else None, "output": t["output"] if whole else None},
                     "restarts": len(times), "restartGapSec": round((times[-1] - times[0]) / (len(times) - 1)) if len(times) > 1 else None,
                     "restartTimes": [iso(t) for t in times]}
        if name == "main":
            first = {}
            for r, rel in sorted(((r, rel) for r, rel in mine if os.sep not in rel), key=lambda e: e[0][0]):
                first.setdefault(sess(rel), r)
            # A session's first call in the requests read is its first call only if its transcript began today too: one
            # resumed from before the read is no restart. One unpriced first call, or a transcript that cannot be read,
            # leaves the mean unknown: the other sessions' alone would read as every session's.
            begun, learned = [], {}
            try:
                with open(os.path.join(cache_dir, "limit-started.json")) as f:
                    memo = json.load(f)
                if not isinstance(memo, dict):
                    raise ValueError("not a memo")
            except (OSError, ValueError):
                memo = {}
            for s, r in first.items():
                p = os.path.join(folder, s + ".jsonl")
                t = None
                if r[0] >= midnight:
                    t = memo.get(p) if os.path.exists(p) else None  # a deleted transcript's start is unknown
                    if t is None:
                        t = learned[p] = started(p)
                if r[0] >= midnight and (t is None or t >= midnight):
                    begun.append(None if t is None else price(r))
            if any(t is not None for t in learned.values()):
                remember_started(cache_dir, learned)
            out[name]["rebuildUsd"] = round(sum(begun) / len(begun), 4) if begun and None not in begun else None
        else:
            runs = {}
            for r, rel in mine:
                if os.sep in rel and r[0] >= midnight:
                    runs.setdefault(rel, []).append(r)
            costs = [price(r) for rs in runs.values() for r in rs]
            out[name]["sideRuns"] = {"count": len(runs), "usd": None if None in costs else round(sum(costs), 4)}
    return out


def first_context(path):
    """The first assistant usage of a transcript summed as hooks/lib/context-size.sh sums it (output left out), or None."""
    try:
        with open(path, errors="replace") as f:
            for line in f:
                try:
                    u = json.loads(line).get("message", {}).get("usage")
                except (ValueError, AttributeError):
                    continue
                if isinstance(u, dict):
                    return sum(u.get(k) or 0 for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    except OSError:
        pass
    return None


def started(path):
    """A transcript's first line time (its first line with a timestamp), or None when it cannot be read."""
    try:
        with open(path, errors="replace") as f:
            for line in f:
                try:
                    t = epoch(json.loads(line).get("timestamp"))
                except (ValueError, AttributeError):
                    continue
                if t is not None:
                    return t
    except OSError:
        pass
    return None


def restarts(log, since=None, until=None, transcripts=None):
    """Issue 283: how often main restarts and how much of its first context the checkpoint is, {restarts, perDay, ...}.

    A restart is a <session id>.resumed-from record beside the log (hooks/resume-context.sh): its mtime the restart
    time, its first line the checkpoint resumed from. A record whose <session id>.jsonl is not under `transcripts`
    (default: any project folder) is another project's and counts in `skipped`. Checkpoint bytes are the last
    cp_bytes= the hook logged for that checkpoint before the restart (the line after an automatic carry is the size
    the restart takes); post-restart context is the session's first usage. The share is bytes / 4 over that context,
    an estimate: four bytes to a token. A stop line never marks a restart: equal since_restart_min values do not.
    """
    lines = []
    try:
        with open(log, errors="replace") as f:
            for line in f:
                m = re.match(r"(\S+) stop-hook: (?:.* )?cp=(\S+) cp_bytes=(\d+)", line)
                try:
                    if m:
                        lines.append((datetime.fromisoformat(m[1]).timestamp(), m[2], int(m[3])))
                except ValueError:
                    pass
    except OSError:
        pass
    lo, hi = (datetime.fromisoformat(x).timestamp() if x else None for x in (since, until))
    per_day, sizes, contexts, shares, skipped = {}, [], [], [], 0
    for rec in sorted(glob.glob(os.path.join(os.path.dirname(log), "*.resumed-from"))):
        sid = os.path.basename(rec)[: -len(".resumed-from")]
        paths = glob.glob(os.path.join(transcripts, sid + ".jsonl")) if transcripts else glob.glob(os.path.join(config_dir() or os.path.expanduser("~/.claude"), "projects", "*", sid + ".jsonl"))
        try:
            at = os.path.getmtime(rec)
            with open(rec, errors="replace") as f:
                cp = f.readline().strip()
        except OSError:
            continue
        if (lo is not None and at < lo) or (hi is not None and at > hi):
            continue
        if not paths:
            skipped += 1
            continue
        day = datetime.fromtimestamp(at).strftime("%Y-%m-%d")
        per_day[day] = per_day.get(day, 0) + 1
        before = [b for t, c, b in lines if c == cp and t <= at]
        ctx = first_context(paths[0])
        if before:
            sizes.append(before[-1])
        if ctx:
            contexts.append(ctx)
        if before and ctx:
            shares.append(before[-1] / 4 / ctx * 100)
    med = lambda v: round(statistics.median(v), 2) if v else None
    return {"restarts": sum(per_day.values()), "perDay": dict(sorted(per_day.items())), "skipped": skipped,
            "medianCheckpointBytes": med(sizes), "medianContext": med(contexts), "medianSharePct": med(shares), "estimate": True}


def main_events(now, proj, log):
    """Issues 292, 300: main's last 24 h as {compactions, carryFailed, carried, resumedAt}, for the alerts in dashboard_alerts.jq.

    A compaction is a compact_boundary row in a transcript under `proj` (the main checkout's projects folder). A carry
    failure is a `carry-over check failed for <cp>` line of the hook log with no later `carried automatically into the
    checkpoint <cp>` line, or a `could not copy` line: the hook did not heal it. The log is machine-wide and in local
    time, so a checkpoint counts only when its session has a transcript under `proj`. carried lists each checkpoint the
    hook carried automatically ({cp, at, items, restartedAt}: the first restart after it, else null): a rejected
    checkpoint whose main was never restarted. resumedAt is the newest <session id>.resumed-from record of such a
    session, main's last restart. An unreadable file raises OSError.
    """
    since = now - 86400
    comp = []
    for name in (os.listdir(proj) if os.path.isdir(proj) else []):
        path = os.path.join(proj, name)
        if not name.endswith(".jsonl") or os.path.getmtime(path) < since:
            continue
        with open(path, errors="replace") as f:
            for line in f:
                if '"compact_boundary"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                at = epoch(r.get("timestamp")) if isinstance(r, dict) and r.get("subtype") == "compact_boundary" else None
                if at is not None and at >= since:
                    meta = r.get("compactMetadata") or {}
                    comp.append({"sid": r.get("sessionId") or name[:-6], "at": iso(at), "trigger": meta.get("trigger"), "preTokens": meta.get("preTokens")})
    ours = lambda cp: os.path.exists(os.path.join(proj, os.path.basename(cp)[:-3] + ".jsonl"))
    failed, healed, carried = {}, set(), {}
    try:
        with open(log, errors="replace") as f:
            for line in f:
                m = re.match(r"(\S+) stop-hook: (?:carry-over check failed for (\S+) against |could not copy \d+ missing items into (\S+?);|(\d+) items carried automatically into the checkpoint (\S+))", line)
                try:
                    at = datetime.fromisoformat(m[1]).timestamp() if m else None
                except ValueError:
                    at = None
                if at is None or at < since:
                    continue
                if m[5]:
                    healed.add(m[5])
                    carried[m[5]] = (at, int(m[4]))
                elif m[2]:
                    failed[m[2]] = at
                    healed.discard(m[2])
                else:
                    failed[m[3]] = at
                    healed.discard(m[3])
    except FileNotFoundError:
        pass
    resumed = [os.path.getmtime(p) for p in glob.glob(os.path.join(os.path.dirname(log), "*.resumed-from"))
               if os.path.exists(os.path.join(proj, os.path.basename(p)[:-len(".resumed-from")] + ".jsonl"))]
    restarts_at = sorted(resumed)
    return {"compactions": sorted(comp, key=lambda c: c["at"]),
            "carried": [{"cp": cp, "at": iso(at), "items": n, "restartedAt": next((iso(r) for r in restarts_at if r > at), None)}
                        for cp, (at, n) in sorted(carried.items(), key=lambda x: x[1][0]) if ours(cp)],
            "carryFailed": [{"at": iso(at), "cp": cp} for cp, at in sorted(failed.items(), key=lambda x: x[1]) if cp not in healed and ours(cp)],
            "resumedAt": iso(max(resumed)) if resumed else None}


def main(argv):
    if argv[1:] == ["fetch"]:
        return fetch()
    if len(argv) == 3 and argv[1] == "account":
        json.dump(switch_account(argv[2]), sys.stdout)
        return 0
    if len(argv) == 6 and argv[1] == "units":
        # units <now> <cache dir> <Claude projects folder> <Codex sessions folder>; the units on stdin.
        json.dump(unit_costs(json.load(sys.stdin), float(argv[2]), argv[3], argv[4], argv[5] or None), sys.stdout)
        return 0
    if len(argv) == 5 and argv[1] == "main-events":
        # main-events <now> <main project folder> <hook log>
        json.dump(main_events(float(argv[2]), argv[3], argv[4]), sys.stdout)
        return 0
    if len(argv) >= 3 and argv[1] == "restarts":
        # restarts <hook log> [--since <iso>] [--until <iso>] [--transcripts <dir>]
        opts = dict(zip(argv[3::2], argv[4::2]))
        json.dump(restarts(argv[2], opts.get("--since"), opts.get("--until"), opts.get("--transcripts")), sys.stdout)
        return 0
    if len(argv) >= 6 and argv[1] == "tests":
        rest = argv[5:]
        cut = rest.index("--builders") if "--builders" in rest else len(rest)
        json.dump(test_runs(argv[2], argv[3], float(argv[4]), rest[:cut], rest[cut + 1:]), sys.stdout)
        return 0
    if len(argv) in (7, 8) and argv[1] == "seats":
        json.dump(seats(float(argv[2]), argv[3], argv[4], argv[5], argv[6], argv[7] if len(argv) > 7 else None), sys.stdout)
        return 0
    if len(argv) in (7, 8, 9) and argv[1] == "build":
        return build(argv[2], argv[3], float(argv[4]), argv[5], argv[6], argv[7] if len(argv) > 7 else None,
                     json.loads(argv[8]) if len(argv) > 8 else None)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
