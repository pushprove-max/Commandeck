#!/usr/bin/env bash
# hook-fire-log-summary.sh [days] -- which hooks fired, blocked and advised in the
# last N days (default 7), from the day files hooks/lib/hook-fire-log.sh
# writes. One JSON object: the window, the earliest row still retained,
# and per hook {hook, registered, fires, blocks, advises, retried_identical,
# worked_around, ms_body_p50, ms_body_p95, ms_body_total, by_agent}: of its blocks,
# how many the session followed with the same call again and how many with a
# different one; its run time after arming, which excludes process
# startup and the input read, over the window's rows that carry one (null when none);
# fires and blocks per agent. Noisiest and slowest guards:
#   bash scripts/hook-fire-log-summary.sh 7 | jq '.hooks | sort_by(-.blocks)[:10]'
#   bash scripts/hook-fire-log-summary.sh 7 | jq '.hooks | sort_by(-.ms_body_total)[:10]'
#
# Every hook the plugin's hooks/hooks.json registers is listed, at zero
# when it has no row in the window; a hook seen in the window but no longer
# registered is listed with registered:false. Registered hooks that never fired:
#   bash scripts/hook-fire-log-summary.sh 30 | jq '.hooks[] | select(.registered and .fires == 0)'
#
# Zero means no RETAINED row in the window, not proof the hook never ran: the log
# keeps 8 days of day files, so a longer window reads only those -- compare the
# window start with earliest_retained. Counts are per invocation, and the Codex
# dispatcher's own rows stay under its own name. COMMANDECK_HOOK_FIRE_LOG names
# one exact file to read instead.
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
DAYS=${1:-7}
[[ $DAYS =~ ^[1-9][0-9]*$ ]] || { echo "hook-fire-log-summary: days must be a positive integer (got '$DAYS')" >&2; exit 2; }
NOW=$(date -u +%s) || exit 2
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SETTINGS="$HERE/../hooks/hooks.json"
# The day files are named for the project the caller stands in (lib/project.sh).
. "$HERE/../hooks/lib/project.sh"; pp_project

python3 - "${COMMANDECK_HOOK_FIRE_LOG:-}" "$HOME/.claude/hook-fire-log" "$SETTINGS" "$DAYS" "$NOW" "$PP_PROJECT" <<'PY'
import datetime, json, math, os, re, sys
log, logdir, settings, days, now, project = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
cutoff = now - days * 86400
utc = datetime.timezone.utc
def iso(t):
    return datetime.datetime.fromtimestamp(t, utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# The registry is read, never run: the script name is the first word's
# basename, less the quotes hooks.json puts round the path.
try:
    registry = json.load(open(settings)).get("hooks") or {}
except (OSError, ValueError) as error:
    sys.exit(f"hook-fire-log-summary: cannot read {settings}: {error}")
registered = {os.path.basename(words[0].strip('"'))
              for groups in registry.values() for group in groups or []
              for hook in group.get("hooks") or []
              for words in [(hook.get("command") or "").split()] if words}

# The override is one file; otherwise the day files from the cutoff's day on,
# in day order, so a session's calls stay in log order across midnight.
earliest = None
if log:
    paths = [log]
else:
    try:
        names = os.listdir(logdir)
    except OSError:
        names = []
    day = re.compile(re.escape(project) + r"\.(\d{4}-\d{2}-\d{2})\.jsonl")
    retained_days = sorted(m.group(1) for n in names if (m := day.fullmatch(n)))
    paths = [os.path.join(logdir, f"{project}.{d}.jsonl") for d in retained_days if d >= iso(cutoff)[:10]]
    # earliest_retained still says what the log holds before the window: the
    # oldest day file's first row (rows are appended in time order).
    if retained_days and retained_days[0] < iso(cutoff)[:10]:
        try:
            with open(os.path.join(logdir, f"{project}.{retained_days[0]}.jsonl"), encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        earliest = int(datetime.datetime.strptime(json.loads(line)["timestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=utc).timestamp())
                        break
                    except (ValueError, KeyError, TypeError):
                        continue
        except OSError:
            pass

counts, sessions, blocked, ms, agents = {}, {}, [], {}, {}
for path in paths:
    try:
        lines = open(path, encoding="utf-8", errors="replace").readlines()
    except OSError:
        continue
    for line in lines:
        try:
            row = json.loads(line)
            t = int(datetime.datetime.strptime(row["timestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=utc).timestamp())
            hook, decision = row["hook"], row["decision"]
        except (ValueError, KeyError, TypeError):
            continue  # a row cut short by a full disk or a crash
        if not isinstance(hook, str) or not hook:
            continue
        earliest = t if earliest is None else min(earliest, t)
        # Rows of one session in log order, for the next-call lookup below.
        calls = sessions.setdefault(row.get("session_id") or None, [])
        if row.get("use"):
            calls.append((row["use"], row.get("call")))
        if cutoff <= t <= now:
            c = counts.setdefault(hook, [0, 0, 0, 0, 0])
            c[0] += 1
            c[1] += decision == "block"
            c[2] += decision == "advise"
            if type(row.get("ms_body")) is int:
                ms.setdefault(hook, []).append(row["ms_body"])
            if row.get("agent") in ("claude", "codex"):
                a = agents.setdefault(hook, {}).setdefault(row["agent"], [0, 0])
                a[0] += 1
                a[1] += decision == "block"
            if decision == "block" and row.get("use") and row.get("session_id"):
                blocked.append((c, calls, len(calls) - 1))

# After a block, the session's next call is its first row with a different
# tool_use_id (every hook on one call shares the id). The same fingerprint is
# the identical action retried; any other is a workaround. A block with no id,
# or no later call, is neither.
for c, calls, at in blocked:
    use, call = calls[at]
    later = calls[at + 1:]
    nxt_use = next((u for u, _ in later if u != use), None)
    # Only some of the next call's hooks hash it; any one of them answers.
    nxt = next((k for u, k in later if u == nxt_use and k), None)
    if call and nxt is not None:
        c[3 if nxt == call else 4] += 1

def timing(name):
    t = sorted(ms.get(name, []))
    rank = lambda q: t[math.ceil(q * len(t)) - 1] if t else None  # nearest rank
    a = agents.get(name, {})
    return {"ms_body_p50": rank(0.5), "ms_body_p95": rank(0.95), "ms_body_total": sum(t) if t else None,
            "by_agent": {k: dict(zip(("fires", "blocks"), a.get(k, [0, 0]))) for k in ("claude", "codex")}}

print(json.dumps({
    "days": days,
    "window_start": iso(cutoff),
    "now": iso(now),
    "earliest_retained": None if earliest is None else iso(earliest),
    "hooks": [dict(zip(("hook", "registered", "fires", "blocks", "advises", "retried_identical", "worked_around"),
                       [name, name in registered] + counts.get(name, [0, 0, 0, 0, 0])), **timing(name))
              for name in sorted(registered | set(counts))],
}, indent=1))
PY
