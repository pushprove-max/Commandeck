#!/usr/bin/env bash
# PostToolUse hook on Read, Grep, Bash and the serena tools: one local row per search or read, so
# "do the code servers beat rg" is answered by counts, not by guessing (issue 298). Read it with
# scripts/search-log-report.py.
#
# NO QUERY TEXT: a row holds a 12-hex sha1 fingerprint of the query (qfp), whether it looks like a symbol, the
# project-relative paths it named, up to 10 paths from the result that exist under the project (a Bash path must
# exist too), the result's size and emptiness, and follow_of / follow_id -- the tool and the row id of the newest of
# this session's previous 3 logged rows that this one repeats (a read of a path or hit, or a search with the same qfp
# or a shared path). The window is the next 3 LOGGED calls: an Edit, a Write or any unregistered tool is not one.
# Home: ${COMMANDECK_SEARCH_LOG:-${COMMANDECK_SCRATCH:-~/.commandeck/scratch}/search-log.jsonl}, mode 0600; past
# 20 MB it moves to .1 and one generation is kept. The per-session ring of the last 3 rows lives in
# /tmp/claude-search-ring-<sid>, so another session never displaces it.
# Always exits 0 and prints nothing: a logging hook must never change a call.
# shortcut: a Bash query is the first non-flag argument after rg/grep, so `rg -g '*.ts' foo` fingerprints the glob;
# paths and hits resolve against the project root, so a Bash call after `cd sub` logs none; parallel calls race on the
# ring and can miss a follow-up. Upgrade when the report shows any of these matters.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
read -r -d '' PY <<'PYEOF'
import hashlib, json, os, re, shlex, sys, time

d = json.load(sys.stdin)
tool = d.get("tool_name") or ""
ti = d.get("tool_input") or {}
tr = d.get("tool_response")
if d.get("hook_event_name") == "PostToolUseFailure":
    sys.exit(0)
# An errored call is not a search.
if isinstance(tr, dict) and (tr.get("is_error") or tr.get("error")):
    sys.exit(0)
proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

def rel(p):
    p = str(p)
    return os.path.relpath(p, proj) if p.startswith(proj + "/") else p

QUERY_KEYS = ["name_path_pattern", "name_path", "substring_pattern", "query", "name_pattern", "qn_pattern",
              "pattern", "function_name", "semantic_query"]
PATH_KEYS = ["relative_path", "file_path", "path", "path_filter"]
query, paths, kind = "", [], "search"

def operands(words):
    return [w for w in words if not w.startswith("-")]

if tool == "Read":
    kind, paths = "read", [ti.get("file_path")]
elif tool == "Bash":
    for seg in re.split(r"[;&|\n]+", ti.get("command") or ""):
        try:
            w = shlex.split(seg)
        except ValueError:
            continue
        if not w:
            continue
        ops = operands(w[1:])
        if w[0] in ("rg", "grep") and ops:
            query, paths = ops[0], ops[1:]
            break
        if w[0] == "sed" and len(ops) >= 2 and "-n" in w:
            kind, paths = "read", ops[1:]
            break
        if w[0] in ("cat", "head", "tail") and ops:
            kind, paths = "read", ops
            break
    else:
        sys.exit(0)
else:
    for k in QUERY_KEYS:
        if ti.get(k):
            v = ti[k]
            query = " ".join(map(str, v)) if isinstance(v, list) else str(v)
            break
    paths = [ti.get(k) for k in PATH_KEYS if isinstance(ti.get(k), str)]
def exists(p):
    return os.path.exists(os.path.join(proj, p))

# Option values (-g glob, a second -e) shift the query into the Bash operands, so only names on disk are paths.
paths = [rel(p) for p in paths if p and (tool != "Bash" or exists(p))][:5]

def text_of(r):
    if isinstance(r, str):
        return r
    if isinstance(r, list):
        return "".join(b.get("text", "") for b in r if isinstance(b, dict))
    if isinstance(r, dict):
        for k in ("content", "stdout"):
            if k in r:
                return text_of(r[k])
        if isinstance(r.get("filenames"), list):
            return "\n".join(map(str, r["filenames"]))
    return json.dumps(r)

text = text_of(tr)
def all_empty(v):
    return (not v) if not isinstance(v, (list, dict)) else all(all_empty(x) for x in (v.values() if isinstance(v, dict) else v))
def is_empty(t):
    s = t.strip()
    if s in ("", '""', "[]", "{}", "null") or s.startswith(("No files found", "No matches found")):
        return True
    try:
        v = json.loads(s)
        return isinstance(v, list) and all_empty(v)
    except ValueError:
        return False

hits = []
# A read's result is the file itself: its path-like tokens are imports, not what the call found. A search result
# holds matched content (a secret.token, a body), so a token is a hit only when it names something on disk.
for m in (re.finditer(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,5}\b", text[:200000]) if kind == "search" else ()):
    h = rel(m.group(0))
    if h not in hits and exists(h):
        hits.append(h)
    if len(hits) == 10:
        break

sid = re.sub(r"[^A-Za-z0-9_-]", "", d.get("session_id") or "") or "nosid"
ring_path = f"/tmp/claude-search-ring-{sid}"
try:
    ring = [json.loads(l) for l in open(ring_path)][-3:]
except (OSError, ValueError):
    ring = []
qfp = hashlib.sha1(query.encode()).hexdigest()[:12] if query else ""
follow = None
for r in reversed(ring):
    seen = set(r["paths"]) | set(r["hits"])
    if (kind == "read" and seen & set(paths)) or (kind == "search" and ((qfp and qfp == r["qfp"]) or set(r["paths"]) & set(paths))):
        follow = r
        break

if os.path.isdir(os.path.join(proj, ".git")):
    role = "main"
else:
    role = "reviewer" if os.environ.get("COMMANDECK_REVIEWER") == "1" else "builder" if os.environ.get("COMMANDECK_BUILDER") == "1" else "worker"
row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "id": f"{sid}-{time.time_ns()}", "sid": sid,
       "unit": os.path.basename(proj), "role": role,
       "tool": "bash-grep" if tool == "Bash" and kind == "search" else tool, "kind": kind, "qfp": qfp,
       "symbol_shaped": bool(re.match(r"^[A-Za-z_][A-Za-z0-9_]*(/[A-Za-z_][A-Za-z0-9_]*)*$", query)),
       "paths": paths, "hits": hits, "size": len(text), "empty": is_empty(text),
       "follow_of": follow and follow["tool"], "follow_id": follow and follow.get("id")}

log = os.environ.get("COMMANDECK_SEARCH_LOG") or os.path.join(
    os.environ.get("COMMANDECK_SCRATCH") or os.path.expanduser("~/.commandeck/scratch"), "search-log.jsonl")
os.makedirs(os.path.dirname(log), mode=0o700, exist_ok=True)
try:
    if os.path.getsize(log) > 20_000_000:
        os.replace(log, log + ".1")
except OSError:
    pass
fd = os.open(log, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
os.write(fd, (json.dumps(row) + "\n").encode())
os.close(fd)
fd = os.open(ring_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, "".join(json.dumps(r) + "\n" for r in (ring + [row])[-3:]).encode())
os.close(fd)
PYEOF
printf '%s' "$INPUT" | python3 -I -c "$PY" >/dev/null 2>&1
exit 0
