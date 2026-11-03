#!/usr/bin/env bash
# Whole-workflow token ledger. Rows are deliberately machine-readable, so a
# script can read the same evidence humans inspect here. Missing provider
# fields stay missing; absence is never zero.
set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "${0}"; exit 0 ;; esac

SINCE=""; INCLUDE_MAIN=0; WAITS_PLAN=""; UNITS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE=${2:?date required}; shift 2 ;;
    --main) INCLUDE_MAIN=1; shift ;;
    --waits) WAITS_PLAN=${2:?plan required}; shift 2 ;;
    --*) echo "unknown option: $1" >&2; exit 2 ;;
    *) UNITS+=("$1"); shift ;;
  esac
done
[ ${#UNITS[@]} -gt 0 ] || { echo "usage: $0 [--since YYYY-MM-DD] [--main] [--waits PLAN] <unit>..." >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1

PYTHONPATH="$PP_SCRIPTS${PYTHONPATH:+:$PYTHONPATH}" python3 - "$SINCE" "$INCLUDE_MAIN" "$WAITS_PLAN" "${UNITS[@]}" <<'PY'
import collections, datetime, glob, json, os, pathlib, re, statistics, subprocess, sys
from unit_folders import belongs

since, include_main, waits_plan, *units = sys.argv[1:]
cut = datetime.datetime.strptime(since, "%Y-%m-%d").replace(tzinfo=datetime.timezone.utc).timestamp() if since else 0
home = pathlib.Path.home()
top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
claude_root = pathlib.Path(os.environ.get("TOKEN_LEDGER_CLAUDE_ROOT", pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR") or home / ".claude") / "projects"))
main_project = pathlib.Path(os.environ.get("TOKEN_LEDGER_MAIN_PROJECT", claude_root / os.environ["PP_MAIN_SLUG"]))
codex_roots = [pathlib.Path(p) for p in os.environ.get("TOKEN_LEDGER_CODEX_ROOTS", f"{home}/.codex-review/sessions:{home}/.codex/sessions").split(":") if p]
briefs = pathlib.Path(os.environ.get("TOKEN_LEDGER_BRIEFS", os.environ["PP_MAIN"] + "/.claude/briefs"))
rates_path = pathlib.Path(os.environ.get("TOKEN_LEDGER_RATES", top + "/.claude/config/token-rates.json"))
status_root = pathlib.Path(os.environ.get("TOKEN_LEDGER_STATUS_ROOT", top + "/.claude/plans"))
fields = ("uncached", "cache_create", "cache_read", "output", "reasoning")
tool_counts = collections.Counter(); big_results = []; seen_reads = set(); all_claude_panes = []

def recorded_at(obj):
    raw = obj.get("timestamp") or (obj.get("message") or {}).get("timestamp")
    if not raw: return None
    try: return datetime.datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError): return None

def in_window(path):
    # mtime only selects candidate files; before_cut drops their older records.
    return path.stat().st_mtime >= cut

def before_cut(obj):
    # An unstamped record cannot be placed, so it stays with its file.
    stamp = recorded_at(obj)
    return stamp is not None and stamp < cut

def total_usage(obj):
    payload = obj.get("payload") or {}
    if obj.get("type") == "event_msg" and payload.get("type") == "token_count":
        usage = (payload.get("info") or {}).get("total_token_usage")
    elif obj.get("type") == "token_usage_record":
        usage = payload.get("total_token_usage") or payload.get("thread_token_usage")
    else: return None
    return usage if isinstance(usage, dict) else None

def class_of(unit):
    path = briefs / f"{unit}.md"
    try: text = path.read_text(errors="replace")[:3000].lower()
    except OSError: return "unknown"
    match = re.search(r"class:\s*([a-z/-]+)", text)
    marker = match.group(1) if match else ""
    if "gate-ci" in marker or "gate/ci" in marker: return "gate-ci"
    if "cross-file" in marker: return "cross-file"
    if "risky" in marker: return "risky"
    if "runtime" in marker: return "runtime"
    if "tooling" in marker: return "tooling"
    return "unknown"

def claude_pane(path, diagnose=True):
    totals = collections.Counter(); present = set(); compactions = 0; contexts = []; ids = {}; pane_reads = set(); replies = {}
    try: lines = path.open(errors="replace")
    except OSError: return None
    for line in lines:
        try: obj = json.loads(line)
        except (ValueError, TypeError): continue
        if not isinstance(obj, dict) or before_cut(obj): continue
        typ = obj.get("type"); message = obj.get("message") or {}
        if typ == "assistant" and isinstance(message.get("usage"), dict):
            usage = message["usage"]
            vals = [usage.get("input_tokens"), usage.get("cache_creation_input_tokens"), usage.get("cache_read_input_tokens"), usage.get("output_tokens")]
            # One reply is a line per content block, each repeating its usage
            #: keep the reply's last line, as unit-cost.sh does.
            if any(v is not None for v in vals): replies[message.get("id") or obj.get("uuid") or len(replies)] = vals
            if diagnose:
                for item in message.get("content") or []:
                    if not isinstance(item, dict) or item.get("type") != "tool_use": continue
                    name = item.get("name", "unknown"); inp = item.get("input") or {}
                    what = inp.get("file_path") or (inp.get("command", "")[:80] if name == "Bash" else "")
                    ids[item.get("id")] = (name, what); tool_counts[name] += 1
                    if name == "Bash" and str(inp.get("command", "")).lstrip().split(" ", 1)[0] in ("cat", "head", "tail", "awk"):
                        tool_counts["Bash:shell-read"] += 1
        elif diagnose and typ == "user" and isinstance(message.get("content"), list):
            for item in message["content"]:
                if not isinstance(item, dict) or item.get("type") != "tool_result" or item.get("tool_use_id") not in ids: continue
                name, what = ids[item["tool_use_id"]]; content = item.get("content")
                text = content if isinstance(content, str) else "".join(part.get("text", "") for part in (content or []) if isinstance(part, dict))
                totals[f"result:{name}"] += len(text); totals["result_all"] += len(text); big_results.append((len(text), name, what))
                if name == "Read":
                    pane_reads.add(what)
                    if what in seen_reads: totals["reread_cross_chars"] += len(text)
        if obj.get("isCompactSummary") is True or typ == "summary" or (typ == "user" and isinstance(message.get("content"), str) and message["content"].startswith("This session is being continued")):
            compactions += 1
    for vals in replies.values():
        for key, value in zip(fields[:4], vals):
            if value is not None: totals[key] += value; present.add(key)
        contexts.append(sum((v or 0) for v in vals[:3]))
    turns = len(replies)
    if not turns or not in_window(path): return None
    if diagnose: seen_reads.update(pane_reads)
    usage = {field: totals[field] if field in present else None for field in fields[:4]}
    return {**totals, **usage, "reasoning": None, "turns": turns, "compactions": compactions, "context": max(contexts, default=0), "fresh": contexts[0] if contexts else 0}

def add_rows(panes):
    row = {}; partial = []
    for field in fields:
        values = [p.get(field) for p in panes]
        recorded = [value for value in values if value is not None]
        row[field] = sum(recorded) if recorded else None
        if recorded and len(recorded) != len(values): partial.append(field)
    row["turns"] = sum(p["turns"] for p in panes) if panes and all(p.get("turns") is not None for p in panes) else None
    row["partial"] = partial
    return row

def load_jsonl(path):
    out = []
    try:
        for line in path.open(errors="replace"):
            try: out.append(json.loads(line))
            except (ValueError, TypeError): pass
    except OSError: pass
    return out

def codex_session(path):
    objects = load_jsonl(path)
    if not objects: return None
    cwd = None
    for obj in objects:
        payload = obj.get("payload") or {}
        if obj.get("type") in ("session_meta", "turn_context"): cwd = payload.get("cwd") or cwd
    workspaces = os.environ["PP_WORKSPACES"]
    # A closing pass reviews in the unit's closing copy; unit_folders.belongs counts it as the unit's session.
    wanted = next((u for u in units if belongs(cwd, os.path.join(workspaces, u))), None)
    if not wanted or not in_window(path): return None
    # Cumulative totals carry pre-boundary usage; the last one before the cut
    # is subtracted so only the window's share is reported.
    baseline = {}
    for obj in objects:
        if before_cut(obj): baseline = total_usage(obj) or baseline
    objects = [obj for obj in objects if not before_cut(obj)]
    cumulative = []; turn_local = {}; anonymous_turns = []; legacy_turns = []; turn_ids = set()
    for obj in objects:
        payload = obj.get("payload") or {}
        total = total_usage(obj)
        if isinstance(total, dict):
            cumulative.append({key: value - baseline[key] if isinstance(value, (int, float)) and isinstance(baseline.get(key), (int, float)) else value for key, value in total.items()})
        if obj.get("type") == "event_msg" and payload.get("type") == "token_count": pass
        elif obj.get("type") == "token_usage_record":
            local = payload.get("turn_token_usage")
            if isinstance(local, dict):
                if payload.get("turn_id"): turn_local[payload["turn_id"]] = local
                else: anonymous_turns.append(local)
            if not isinstance(total, dict) and not isinstance(local, dict):
                usage = payload.get("usage") or obj.get("usage")
                if isinstance(usage, dict): legacy_turns.append(usage)
            if payload.get("turn_id"): turn_ids.add(payload["turn_id"])
        elif isinstance(obj.get("usage"), dict): legacy_turns.append(obj["usage"])
        elif isinstance(payload.get("usage"), dict): legacy_turns.append(payload["usage"])
    def summed(records):
        keys = set().union(*(record.keys() for record in records)) if records else set()
        result = {}
        for key in keys:
            recorded = [record[key] for record in records if record.get(key) is not None]
            result[key] = sum(recorded) if recorded else None
        return result
    candidates = []
    if cumulative: candidates.append(cumulative[-1])
    local_records = list(turn_local.values()) + anonymous_turns
    if local_records: candidates.append(summed(local_records))
    if legacy_turns: candidates.append(summed(legacy_turns))
    if not candidates:
        return wanted, ({field: None for field in fields} | {"turns": None})
    turns = len(turn_ids) or len(local_records) or len(legacy_turns) or sum(1 for o in objects if o.get("type") == "event_msg" and (o.get("payload") or {}).get("type") == "token_count") or 1
    def normalized(raw):
        cached = raw.get("cached_input_tokens"); inp = raw.get("input_tokens")
        return {"uncached": inp - cached if inp is not None and cached is not None else inp,
                "cache_create": raw.get("cache_write_input_tokens"), "cache_read": cached,
                "output": raw.get("output_tokens"), "reasoning": raw.get("reasoning_output_tokens")}
    normalized_candidates = [normalized(candidate) for candidate in candidates]
    usage = {field: max((candidate[field] for candidate in normalized_candidates if candidate.get(field) is not None), default=None) for field in fields}
    return wanted, {**usage, "turns": turns}

def fmt(value): return '"not recorded"' if value is None else str(value)
def print_row(unit, source, row):
    suffix = f" partial={','.join(row['partial'])}" if row.get("partial") else ""
    print("row unit=%s source=%s %s turns=%s%s" % (unit, source, " ".join(f"{key}={fmt(row.get(key))}" for key in fields), fmt(row.get("turns")), suffix))

codex_by_unit = collections.defaultdict(list); seen_codex = set()
for root in codex_roots:
    if not root.exists(): continue
    for path in root.rglob("*.jsonl"):
        real = path.resolve()
        if real in seen_codex: continue
        seen_codex.add(real); session = codex_session(path)
        if session:
            unit, usage = session; codex_by_unit[unit].append(usage)

# A project folder is a unit's when it is <slug>-<unit> or a subfolder <slug>-<unit>-...; a bare <unit>* prefix
# also took u10's folders for u1. Each folder goes to the longest requested unit it fits, so none counts twice.
pp_slug = lambda s: re.sub(r"[^A-Za-z0-9]", "-", s)  # paths.sh pp_slug: Claude Code's project-folder naming
ws_prefix = f"{os.environ['PP_WORKSPACES_SLUG']}-"
claude_dirs = collections.defaultdict(list)
for folder in sorted(glob.glob(str(claude_root / f"{glob.escape(ws_prefix)}*"))):
    rest = os.path.basename(folder)[len(ws_prefix):]
    fits = [u for u in units if rest == pp_slug(u) or rest.startswith(pp_slug(u) + "-")]
    if fits: claude_dirs[max(fits, key=len)].append(folder)

all_rows = []
for unit in units:
    names = sorted(name for folder in claude_dirs[unit] for name in glob.glob(os.path.join(folder, "*.jsonl")))
    panes = [p for p in (claude_pane(pathlib.Path(name)) for name in names) if p]
    all_claude_panes.extend(panes)
    row = add_rows(panes); print_row(unit, "claude", row); all_rows.append(row)
    klass = class_of(unit)
    for pane in panes:
        print(f"pane unit={unit} classes={klass} turns={pane['turns']} context={pane['context']} compactions={pane['compactions']} output={fmt(pane['output'])}")
    if panes:
        med = lambda key: statistics.median(p[key] for p in panes if p.get(key) is not None)
        maximum = lambda key: max(p[key] for p in panes if p.get(key) is not None)
        output = [p['output'] for p in panes if p.get('output') is not None]
        output_median = f"{statistics.median(output):g}" if output else '"not recorded"'
        output_max = str(max(output)) if output else '"not recorded"'
        print(f"distribution unit={unit} classes={klass} panes={len(panes)} turns_median={med('turns'):g} turns_max={maximum('turns')} compactions_median={med('compactions'):g} compactions_max={maximum('compactions')} output_median={output_median} output_max={output_max} context_median={med('context'):g} context_max={maximum('context')}")
    else:
        print(f"distribution unit={unit} classes={klass} panes=0 turns_median=\"not recorded\" turns_max=\"not recorded\" compactions_median=\"not recorded\" compactions_max=\"not recorded\" output_median=\"not recorded\" output_max=\"not recorded\" context_median=\"not recorded\" context_max=\"not recorded\"")
    codex = add_rows(codex_by_unit[unit]); print_row(unit, "codex", codex); all_rows.append(codex)

if include_main == "1":
    panes = [p for p in (claude_pane(pathlib.Path(name), False) for name in sorted(glob.glob(str(main_project / "*.jsonl")))) if p]
    row = add_rows(panes); print_row("main", "main", row); all_rows.append(row)

# Keep the original retrospective summary while the row/pane records above
# provide the new stable input for automation.
if all_claude_panes:
    total = collections.Counter()
    for pane in all_claude_panes: total.update({key: value for key, value in pane.items() if isinstance(value, int)})
    turns = sorted(pane["turns"] for pane in all_claude_panes); pane_count = len(all_claude_panes)
    short = lambda value: f"{value / 1e3:,.0f}K"
    million = lambda value: f"{value / 1e6:,.1f}M"
    missing = {field for field in fields[:4] if any(pane.get(field) is None for pane in all_claude_panes)}
    def legacy_tokens(field):
        recorded = [pane[field] for pane in all_claude_panes if pane.get(field) is not None]
        if not recorded: return "not recorded"
        return short(sum(recorded)) + (" partial" if field in missing else "")
    print(f"panes={pane_count}  turns={sum(turns)} (median {turns[len(turns)//2]}/pane)  compactions={total['compactions']}")
    print(f"{'source':44s} {'tokens':>10s}  lever")
    legacy = [
        ("input re-sent per turn, cache READ (0.1x price)", total["cache_read"], "turns per pane; warm-pane reuse; fewer rounds"),
        ("input written to cache (1.25x price)", total["cache_create"], "startup size; tool-result size; compactions"),
        ("input uncached (1x)", total["uncached"], "should be ~0; nonzero means cache misses"),
        ("output incl. reasoning", total["output"], "effort level; brief precision; fewer rounds"),
        (f"  of which fresh-pane startup ({pane_count} panes x ~{short(total['fresh']/pane_count)})", total["fresh"], "fewer fresh panes; trim worker startup"),
        ("  of which tool results, all (~)", total["result_all"] // 4, "read symbols not files; never cat logs"),
        ("    Read results (~)", total["result:Read"] // 4, "bounded symbol reads"),
        ("    Bash results (~)", total["result:Bash"] // 4, "one Bash call for independent commands"),
        ("    cross-pane re-reads of unchanged files (~)", total["reread_cross_chars"] // 4, "warm-pane reuse; reviewers read the diff first"),
    ]
    legacy_fields = ("cache_read", "cache_create", "uncached", "output")
    for index, (name, value, lever) in enumerate(legacy):
        shown = legacy_tokens(legacy_fields[index]) if index < len(legacy_fields) else short(value)
        print(f"{name:44s} {shown:>10s}  {lever}")
    total_input = total["uncached"] + total["cache_create"] + total["cache_read"]
    input_note = " partial" if missing.intersection(("uncached", "cache_create", "cache_read")) else ""
    input_text = million(total_input) + input_note if any(pane.get(field) is not None for pane in all_claude_panes for field in ("uncached", "cache_create", "cache_read")) else "not recorded"
    output_text = "not recorded" if all(pane.get("output") is None for pane in all_claude_panes) else million(total["output"]) + (" partial" if "output" in missing else "")
    print(f"total input {input_text}  output {output_text}")
    print("tool calls: " + ", ".join(f"{name} {count}" for name, count in tool_counts.most_common(8)))
    print("largest single tool results:")
    for size, name, what in sorted(big_results, reverse=True)[:8]: print(f"  ~{short(size//4):>6s} {name:6s} {what}")

if rates_path.exists():
    try: rates = json.loads(rates_path.read_text())
    except (OSError, ValueError): rates = None
    needed = [row.get(field) for row in all_rows for field in fields if rates and field in rates]
    if rates and needed and all(value is not None for value in needed) and not any(row.get("partial") for row in all_rows):
        cost = sum(row[field] * rates[field] for row in all_rows for field in fields if field in rates)
        print(f"cost={cost:g}")
    else: print('cost="not recorded"')
else: print("cost=missing")

def seconds(started, finished):
    try:
        start = datetime.datetime.fromisoformat(started.replace("Z", "+00:00")); end = datetime.datetime.fromisoformat(finished.replace("Z", "+00:00"))
        return max(0, int((end - start).total_seconds()))
    except (AttributeError, TypeError, ValueError): return None

if waits_plan:
    status = status_root / f"{waits_plan}.status.json"
    gh = subprocess.run(["sh", "-c", "command -v gh"], capture_output=True, text=True).returncode == 0
    for unit in units:
        opened = merged = None
        if gh and status.exists():
            pr = subprocess.run(["gh", "pr", "view", unit, "--json", "createdAt,mergedAt"], capture_output=True, text=True)
            try: data = json.loads(pr.stdout); opened, merged = data.get("createdAt"), data.get("mergedAt")
            except ValueError: pass
        print(f"waits unit={unit} pr_open_to_merge={fmt(seconds(opened, merged))}")
PY
