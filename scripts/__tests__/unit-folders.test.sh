#!/usr/bin/env bash
# A fresh closing review pass runs in a scratch copy of the unit's worktree (issue 378), so every reader that ties a
# session to a unit by its folder must count that copy as the unit's, or the closing reviewers' calls and cost vanish
# from the dashboard and the merge bill. unit_folders.py is the one home of that rule. Every path below is absent on
# disk, as after a merge: the worktree and the copy are gone, so only the path strings can decide.
set -u
REAL=$(cd "$(dirname "$0")/../.." && pwd)
S=$REAL/scripts
TMP=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected $2, got $3)"; fi; }
export HOME=$TMP/home; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR COMMANDECK_CODEX_REVIEW_HOME COMMANDECK_MAIN COMMANDECK_SCRATCH PP_SCRATCH

# The dashboard's per-unit cost: one Codex call in the worktree, one in its copy, one in another unit's copy, and one
# Claude call under the copy's own projects folder. Run with the scratch the sessions name.
unit_calls() { # <scratch the sessions name> -> the unit's total calls, then its calls by agent
  python3 - "$S" "$TMP" "$1" <<'PY'
import json, os, re, sys, time
sys.path.insert(0, sys.argv[1])
import dashboard_limit as d
tmp, scratch = sys.argv[2], sys.argv[3]
t = int(time.time()) - 3600  # the readers skip a file last written before the window
iso = d.iso
cx, projects, cache = f"{tmp}/sessions/2027/01/15", f"{tmp}/projects", f"{tmp}/cache"
for p in (cx, cache):
    os.makedirs(p, exist_ok=True)
def codex(name, cwd, at):
    with open(f"{cx}/rollout-{name}.jsonl", "w") as f:
        f.write(json.dumps({"type": "session_meta", "timestamp": iso(at), "payload": {"cwd": cwd}}) + "\n")
        f.write(json.dumps({"type": "token_usage_record", "timestamp": iso(at), "payload": {"response_id": name, "usage": {
            "input_tokens": 0, "cached_input_tokens": 0, "cache_write_input_tokens": 0, "output_tokens": 0}}}) + "\n")
codex("a", "/ws/u", t + 10)
codex("b", f"{scratch}/closing-copy/u", t + 20)
codex("c", f"{scratch}/closing-copy/other", t + 30)
slug = lambda p: re.sub(r"[^A-Za-z0-9]", "-", p)
cp = f"{projects}/{slug(scratch + '/closing-copy/u')}"
os.makedirs(cp, exist_ok=True)
with open(f"{cp}/s.jsonl", "w") as f:
    f.write(json.dumps({"type": "assistant", "timestamp": iso(t + 40), "cwd": f"{scratch}/closing-copy/u", "requestId": "cl",
        "message": {"id": "cl", "model": "claude-haiku-5-5", "usage": {"input_tokens": 100000, "output_tokens": 0,
        "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}}}) + "\n")
out = d.unit_costs([{"unit": "u", "worktree": "/ws/u", "stages": [{"stage": "building", "from": iso(t), "to": None}]}],
                   t + 100, cache, projects, f"{tmp}/sessions")["u"]
print(out["total"]["calls"], json.dumps(out["total"]["byAgent"], sort_keys=True).replace(" ", ""))
PY
}
rm -rf "$TMP/cache" "$TMP/sessions" "$TMP/projects"
check "a closing-copy session, Codex's or Claude's, counts as its unit's in the dashboard's unit cost, and another unit's copy does not" "3" \
  "$(PP_SCRATCH=/scratch unit_calls /scratch | cut -d' ' -f1)"
rm -rf "$TMP/cache" "$TMP/sessions" "$TMP/projects"
check "claude_closing_copy_cost_counted: the Claude call under the copy's own projects folder is in the unit's Claude tally" "true" \
  "$(PP_SCRATCH=/scratch unit_calls /scratch | cut -d' ' -f2 | jq -r '.claude > 0' 2>/dev/null)"
# With no scratch in the environment, COMMANDECK_SCRATCH is the second name; with neither, paths.sh names it.
rm -rf "$TMP/cache" "$TMP/sessions" "$TMP/projects"
check "COMMANDECK_SCRATCH names the scratch when PP_SCRATCH is unset" "3" \
  "$(COMMANDECK_SCRATCH=/scratch2 unit_calls /scratch2 | cut -d' ' -f1)"
NAMED=$(env -u PP_SCRATCH -u COMMANDECK_SCRATCH bash -c '. "$1/paths.sh" >/dev/null 2>&1 && printf %s "$PP_SCRATCH"' _ "$S")
rm -rf "$TMP/cache" "$TMP/sessions" "$TMP/projects"
check "with no scratch in the environment, the copy is the one under the scratch paths.sh names" "3" \
  "$(unset PP_SCRATCH COMMANDECK_SCRATCH; unit_calls "$NAMED" | cut -d' ' -f1)"
# With no scratch at all the readers fail loud (the dashboard shows the cost unknown), never count the copy as nobody's.
mkdir -p "$TMP/alone" && cp "$S/unit_folders.py" "$TMP/alone/"
check "with no scratch from the environment or paths.sh, asking whose a folder is raises" 1 \
  "$(cd "$TMP/alone" && env -u PP_SCRATCH -u COMMANDECK_SCRATCH python3 -c 'import unit_folders; unit_folders.belongs("/a", "/ws/u")' 2>/dev/null; [ $? -ne 0 ] && echo 1 || echo 0)"

# Folders under either home count; a near name does not; a symlinked scratch matches the real path it points to.
mkdir -p "$TMP/real" && ln -s "$TMP/real" "$TMP/link"
check "belongs: a folder under the copy or the worktree is the unit's; a same-prefix unit and its copy are not; an alias matches" \
  "True True False False True" \
  "$(PP_SCRATCH="$TMP/link" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from unit_folders import belongs as b; t = sys.argv[2]
print(b(t + "/link/closing-copy/u/web", "/ws/u"), b("/ws/u/web", "/ws/u"), b("/ws/u2", "/ws/u"), b(t + "/link/closing-copy/u2", "/ws/u"), b(t + "/real/closing-copy/u", "/ws/u"))' "$S" "$TMP")"

# The merge bill's Codex line (unit-cost.sh): the worktree's and the copy's sessions, not another unit's copy.
mkdir -p "$TMP/codex"
python3 - "$TMP/codex/state_5.sqlite" "$TMP" <<'PY'
import sqlite3, sys, time
c = sqlite3.connect(sys.argv[1])
c.execute("create table threads (cwd text, tokens_used integer, updated_at integer)")
now = int(time.time())
c.executemany("insert into threads values (?, ?, ?)", [(sys.argv[2] + "/ws/fixture-unit", 1000000, now), ("/scratch/closing-copy/fixture-unit", 2000000, now), ("/scratch/closing-copy/other", 4000000, now)])
c.commit()
PY
check "the merge bill counts the closing copy's Codex sessions as the unit's" "CODEX      2 sessions, 3.0M tokens (index total, all token kinds)" \
  "$(cd "$REAL" && HOME="$TMP/home" CODEX_HOME="$TMP/codex" COMMANDECK_WORKSPACES="$TMP/ws" COMMANDECK_SCRATCH=/scratch bash "$S/unit-cost.sh" fixture-unit '2000-01-01 00:00' 2>/dev/null | grep '^CODEX')"
# The merge bill's Claude lines read the copy's projects folder too.
CPF=$HOME/.claude/projects/$(printf '%s' "/scratch/closing-copy/fixture-unit" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$CPF"
printf '%s\n' '{"type":"assistant","timestamp":"2027-01-15T08:00:00Z","message":{"id":"m1","model":"claude-haiku-5-5","usage":{"input_tokens":1000,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' > "$CPF/s.jsonl"
check "claude_closing_copy_cost_counted: the merge bill's TOTAL counts the Claude session under the copy's projects folder" "1" \
  "$(cd "$REAL" && HOME="$TMP/home" CODEX_HOME="$TMP/codex" COMMANDECK_WORKSPACES="$TMP/ws" COMMANDECK_SCRATCH=/scratch bash "$S/unit-cost.sh" fixture-unit '2000-01-01 00:00' 2>&1 | grep -c '^TOTAL      1 turns')"

# The dashboard hands the day's cost each project's closing-copy root beside its checkout and workspaces.
check "the dashboard's project record carries closingCopies, and the limit card passes it on" "1 1" \
  "$(grep -c 'closingCopies: \$c' "$S/dashboard.sh") $(grep -c '\.workspaces, \.closingCopies\]' "$S/dashboard.sh")"

# One fence: no other code file spells the copy's folder, so no reader keeps a rule of its own.
check "no code file under scripts/, hooks/ or ci/ but unit_folders.py spells the copy's folder name" "" \
  "$(grep -rl --include='*.sh' --include='*.py' --include='*.mjs' --include='*.js' closing-copy "$REAL/scripts" "$REAL/hooks" "$REAL/ci" 2>/dev/null | grep -v '/__tests__/' | grep -v '/unit_folders\.py$')"

echo "unit-folders: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
