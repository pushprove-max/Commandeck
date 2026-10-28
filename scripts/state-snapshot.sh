#!/usr/bin/env bash
# state-snapshot.sh [--out <path>] [--force] [--goal <text>] [--stage <unit>=<text>]... [--next <unit>=<text>]...
#   [--open-item <text>]... -- write a checkpoint with every MECHANICAL field already filled, so main only types the
# judgment ones.
#
# The template's live-units table wants the unit, its panes with handles, its
# task ids and its loop unit. All four come off board.sh, and all four are what
# main mistypes at the clear line: a handle or a run id remembered from earlier
# in the session is a dead pane by the time the checkpoint is read back.
# Stage and next are judgment, so they land as TODO for main to fill.
#
# Default output is ~/.claude/checkpoints/<session>.md, where <session> is
# $CLAUDE_SESSION_ID or the newest transcript under the project's projects dir.
# Refuses to clobber an existing checkpoint without --force.
#
# Any of --goal/--stage/--next/--open-item fills the judgment fields of the checkpoint at --out in place (generating
# it first when absent), appends each open item as Q-<n> under ## Queue, numbered past every Q number in this file
# and in the checkpoint this session resumed from, then runs the carry check the Stop hook runs and prints its result.
# A result that would still hold the Goal placeholder or a unit's TODO cell, or an unknown unit, exits 2 naming what
# is missing before anything is written, so the retry is the same call with the named flags. Every save is a temp
# file then a rename.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
OUT=""; FORCE=0; GOAL=""; FLAGGED=0; FILLS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=${2-}; shift $(( $# > 1 ? 2 : 1 )) ;;
    --force) FORCE=1; shift ;;
    --goal) GOAL=${2-}; FLAGGED=1; shift $(( $# > 1 ? 2 : 1 )) ;;
    --stage|--next|--open-item) FILLS+=("$1=${2-}"); FLAGGED=1; shift $(( $# > 1 ? 2 : 1 )) ;;
    *) echo "unknown flag $1" >&2; exit 2 ;;
  esac
done
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
PROJECTS=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$PP_MAIN_SLUG
if [ -z "$OUT" ]; then
  SID=${CLAUDE_SESSION_ID:-$(ls -t "$PROJECTS"/*.jsonl 2>/dev/null | head -1 | xargs -r basename | sed 's/\.jsonl$//')}
  [ -n "$SID" ] || { echo "no session id: pass --out <path>" >&2; exit 2; }
  OUT=$HOME/.claude/checkpoints/$SID.md
fi
[ "$FORCE" = 1 ] || [ "$FLAGGED" = 1 ] || [ ! -e "$OUT" ] || { echo "$OUT exists; pass --force to overwrite" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")" || exit 1
# The result is built beside --out and moved over it once it is complete, so a refusal or a failed save leaves --out
# as it was. A flagged call fills an existing checkpoint as it stands, or generates one first.
NEW="$OUT.new.$$"
trap 'rm -f "$NEW"' EXIT
if [ "$FLAGGED" = 0 ] || [ ! -e "$OUT" ]; then
BOARD=$(bash "$(dirname "${BASH_SOURCE[0]}")/board.sh" 2>&1)

# One awk over the board rather than a second round of git and systemctl calls:
# board.sh is the one home for those queries, and a snapshot that asked its own
# questions would drift from what main reads at resume.
# The heredoc is unquoted so line 40 can interpolate the board; that means bash
# also runs any backtick in the template text below. Every command shown to main
# keeps its backticks escaped, or generating a checkpoint executes it.
KEEP_WT=$(pp_keep_worktrees) python3 - "$OUT" "$NEW" <<PY
import os, re, sys, datetime
board = """$(printf '%s' "$BOARD" | sed 's/\\/\\\\/g; s/"/\\"/g')"""
out = sys.argv[1]

def section(name):
    # board.sh titles its sections with a trailing note ("== seats (live
    # worktrees only)"), so an equality match silently returns nothing and
    # every handle column reads "--".
    body, hit = [], False
    for line in board.splitlines():
        if line.startswith("== "):
            hit = line[3:].strip().startswith(name)
            continue
        if hit and line.strip():
            body.append(line)
    return body

units = [l.split()[0] for l in section("worktrees") if l.startswith("  ") and not l.strip().startswith("brief")]
keep = os.environ.get("KEEP_WT", "").splitlines()
units = [u for u in units if u not in keep]
seats, tasks, loops = {}, {}, {}
for l in section("seats"):
    p = l.split()
    if len(p) >= 4:
        seats.setdefault(p[0], []).append(f"{p[1]}={p[2]}")
        tasks.setdefault(p[0], set()).add(p[3])
for l in section("loops and main-watch"):
    m = re.match(r"\s*((?:loop|drive|chain)-(.+)-\d+)\.service\s+(\S+)", l)
    if m:
        loops.setdefault(m.group(2), []).append(f"{m.group(1)} ({m.group(3)})")
watch = "\n".join(l for l in section("loops and main-watch") if "main-watch" in l or "MAIN-WATCH" in l)
head = next((l for l in board.splitlines() if l.startswith("RUN=")), "")
mainline = next((l for l in board.splitlines() if l.startswith("main: ")), "")

rows = "\n".join(
    "| {u} | TODO | {p} | {t} | {l} | TODO |".format(
        u=u, p="; ".join(seats.get(u, [])) or "--",
        t=", ".join(sorted(tasks.get(u, []))) or "--",
        l="; ".join(loops.get(u, [])) or "none")
    for u in units) or "| (no live units) | | | | | |"

open(sys.argv[2], "w").write(f"""# Checkpoint {out.rsplit('/',1)[-1][:-3]} -- {datetime.datetime.now():%Y-%m-%d %H:%M} ET

Mechanical fields generated by state-snapshot.sh; every TODO is main's to fill.

{head}
{mainline}

## Goal

TODO one line: the batch, and the standing rulings that bind it.

## Live units (one line each)

| unit | stage | panes (role=handle) | task ids | loop log / systemd unit | next |
|---|---|---|---|---|---|
{rows}

## Waiting on

{watch}

TODO for each live unit: the marker or verdict expected, and the exact command
main runs when it lands.

## Rulings this session not yet in memory or a rule file

TODO: first run \`bash scripts/repeat-report.sh\` and turn its top items
into fixes; then save every correction or ruling from the owner this session, and every
friction main hit twice, to memory or a rule, or fix it; then list only what
could not be saved yet, and why, or "none".

## Queue (in order)

TODO or "none".

## Gotchas learned this session

Only what CHANGED this session, and only a fact a person had to decide. Stable
tool behaviour belongs in that tool's own header, not here.

TODO or "none".

## Ruled out

TODO: each approach tried or rejected, why, and what would reopen it; or "none".

## How to verify

TODO: each command that proves the current state, as literal text,
for example \`git log --oneline main..<unit-branch>\`; or "none".

## Closed since last checkpoint

TODO: every open item of the checkpoint this session resumed from that is no
longer open above, verbatim, with what closed it; or "none". The restart is
refused while one is neither.

## Resume

- FIRST CALL after the clear: \`bash scripts/board.sh\`. Do not retype a
  path, a run id or a handle from this file; read them from the board. It binds
  this terminal to the run when nothing is bound, so no separate run-use call.
- Nothing to arm: main-watch.sh posts every finished, unhandled item and Orca's
  nudge wakes main. On a nudge, drain in the foreground with
  \`bash scripts/orca-wait.sh\`; close an item's task once it is handled.
""")
PY
[ $? = 0 ] || exit 1
fi
if [ "$FLAGGED" = 0 ]; then
  mv -f "$NEW" "$OUT" || { echo "could not save the checkpoint to $OUT" >&2; exit 1; }
  echo "$OUT"
  exit 0
fi
[ -e "$NEW" ] || cp "$OUT" "$NEW" || exit 1
# Q numbers are never reused, so the numbering continues past the checkpoint this session resumed from.
BASE=""; ANC=$HOME/.claude/checkpoints/$(basename "$OUT" .md).resumed-from
[ ! -e "$ANC" ] || BASE=$(head -1 "$ANC")
python3 -I - "$NEW" "$GOAL" "$BASE" "${FILLS[@]+"${FILLS[@]}"}" <<'PY' || exit $?
import re, sys
path, goal, base, *fills = sys.argv[1:]
lines = open(path).read().splitlines()
try:
    inherited = open(base).read() if base else ""
except OSError:
    inherited = ""
stage, nxt, items = {}, {}, []
for f in fills:
    flag, _, val = f[2:].partition("=")
    if flag == "open-item":
        items.append(val)
    else:
        unit, _, text = val.partition("=")
        (stage if flag == "stage" else nxt)[unit] = text

def cells(l):
    return [c.strip() for c in l.strip()[1:-1].split("|")]
rows = {cells(l)[0]: i for i, l in enumerate(lines) if l.startswith("| ") and not l.startswith("| unit ") and "|---|" not in l}
unknown = [u for u in sorted(set(stage) | set(nxt)) if u not in rows]
if unknown:
    print("unknown unit: " + ", ".join(unknown) + " (live units: " + (", ".join(rows) or "none") + ")", file=sys.stderr)
    sys.exit(2)
if goal:
    lines = [goal if l.startswith(("TODO one line:", "<one line:")) else l for l in lines]
# The stage and next columns are found from the unit table's header row, so the generator's six-column table and the hand template's three-column one both fill.
head = next((cells(l) for l in lines if l.startswith("| unit ")), [])
cols = {w: head.index(w) for w in ("stage", "next") if w in head}
for u, i in rows.items():
    c = cells(lines[i])
    if len(c) != len(head): continue
    if u in stage and "stage" in cols and c[cols["stage"]] == "TODO": c[cols["stage"]] = stage[u]
    if u in nxt and "next" in cols and c[cols["next"]] == "TODO": c[cols["next"]] = nxt[u]
    lines[i] = "| " + " | ".join(c) + " |"
if items:
    n = max([int(m) for m in re.findall(r"Q-(\d+)", "\n".join(lines) + inherited)] or [0])
    q = next(i for i, l in enumerate(lines) if l.startswith("## Queue"))
    end = next((i for i in range(q + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    # A text already queued as "- Q-<n>: <text>" is not added again, so the replay of this call after a stop is safe.
    held = {m.group(1) for m in (re.match(r"- Q-\d+: (.*)$", l) for l in lines[q + 1:end]) if m}
    items = [t for k, t in enumerate(items) if t not in held and t not in items[:k]]
    while lines[end - 1].strip() == "": end -= 1
    lines[end:end] = [f"- Q-{n + k + 1}: {t}" for k, t in enumerate(items)]
missing = [f"{u} {w} (--{w} {u}=<text>)" for u, i in rows.items() for w in ("stage", "next") if w in cols and cells(lines[i])[cols[w]:cols[w] + 1] == ["TODO"]]
if any(l.startswith(("TODO one line:", "<one line:")) for l in lines): missing.insert(0, "Goal (--goal <text>)")
if missing:
    print("the checkpoint would still hold unfilled fields, so main is not restarted from it; still missing: " + "; ".join(missing), file=sys.stderr)
    sys.exit(2)
open(path, "w").write("\n".join(lines) + "\n")
PY
mv -f "$NEW" "$OUT" || { echo "could not save the checkpoint to $OUT" >&2; exit 1; }
echo "$OUT"
# The Stop hook's own carry check, run here so a missing inherited item shows while main can still act on it.
[ -z "$BASE" ] || python3 "$(dirname "${BASH_SOURCE[0]}")/checkpoint-context.py" carry "$BASE" "$OUT" 2>&1
exit 0
