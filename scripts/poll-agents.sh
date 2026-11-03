#!/usr/bin/env bash
# Poll every live Orca agent and print ONE table: who is working, who is done,
# and what verdict each reviewer reached.
#
# Why this exists (four things that made hand-polling unreliable):
#
#  1. `orchestration check` REPLAYS an unacked backlog. Every poll returned the
#     same stale messages from long-merged units until each delivery was acked
#     by hand, so a real report sat behind days of noise. This drains and acks
#     in a loop, then shows only messages for tasks that are still open.
#
#  2. A Codex reviewer launched without
#     `-c sandbox_workspace_write.network_access=true` cannot reach the Orca
#     RPC (the sandbox blocks loopback), so its verdict never arrives as a
#     worker_done -- waiting on `check` for one waits forever. The verdict
#     then only exists as text in the terminal, so this reads it from there.
#
#  3. `terminal read --screen` returns only the rendered viewport, so a long
#     review's findings scroll off and look lost (documented in
#     the adversarial-review rules -- it has cost two full review passes).
#     This uses --screen only for the cheap status check, then re-reads the FULL
#     accumulated buffer with --cursor 0 when a reviewer is actually finished.
#
#  4. AN IDLE WORKER LOOKS IDENTICAL TO A FINISHED ONE. A dispatch can wedge --
#     the command is typed into the pane but never executed, and the task is
#     silently marked failed (orchestration.md, step 4). The TUI shows a quiet
#     prompt either way, so "idle" reads as "done" while nothing has run. An
#     implementer's state is only meaningful if the tree actually moved, so this
#     checks git: idle + clean tree + unmoved HEAD = NOT STARTED, reported as a
#     warning rather than as success.
#
# Usage:
#   poll-agents.sh              status table only
#   poll-agents.sh --verdicts   also dump each finished reviewer's findings
#   poll-agents.sh --save DIR   write each finished reviewer's full buffer to DIR
#   poll-agents.sh --no-drain   do not ack the message queue (for the watcher --
#                               acking here would consume a worker report before
#                               the interactive poll could show it)
#   poll-agents.sh --signature  one stable line per pane, spinner churn stripped,
#                               for change detection by watch-agents.sh

set -uo pipefail
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "${0}"; exit 0 ;; esac

VERDICTS=0
SAVE_DIR=""
NO_DRAIN=0
SIGNATURE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --verdicts) VERDICTS=1; shift ;;
    --save) [ $# -ge 2 ] || { echo "--save needs a folder" >&2; exit 2; }; SAVE_DIR=$2; shift 2 ;;
    --no-drain) NO_DRAIN=1; shift ;;
    --signature) SIGNATURE=1; NO_DRAIN=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SAVE_DIR" ] && mkdir -p "$SAVE_DIR"
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1

command -v orca-ide >/dev/null 2>&1 || { echo "orca-ide not found (never use bare 'orca')" >&2; exit 2; }

# ---------------------------------------------------------------- backlog drain
# Ack repeatedly so stale replays stop; keep bodies for still-open tasks only.
OPEN_TASKS=$(orca-ide orchestration task-list --brief --json 2>/dev/null \
  | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); raise SystemExit
r=d.get("result",d); ts=r.get("tasks",r) if isinstance(r,dict) else r
print(" ".join(t["id"] for t in ts if isinstance(t,dict) and t.get("status") in ("dispatched","ready","in_progress")))' 2>/dev/null)

MSG_FILE=$(mktemp); export MSG_FILE; trap 'rm -f "$MSG_FILE"' EXIT
delivery=""
for _ in $([ "$NO_DRAIN" = 1 ] && echo || echo 1 2 3 4 5 6 7 8); do
  if [ -n "$delivery" ]; then
    out=$(orca-ide orchestration check --full --ack "$delivery" --timeout-ms 2000 --json 2>/dev/null)
  else
    out=$(orca-ide orchestration check --full --timeout-ms 2000 --json 2>/dev/null)
  fi
  # A concise batch has no payload, so every report would drain as taskless; its rows print on stderr.
  out=$(pp_orca_full batch <<<"$out") || exit 2
  [ -z "$out" ] && break
  next=$(printf '%s' "$out" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
r=d.get("result",{})
print(r.get("deliveryId") or "")
msgs=r.get("messages") or []
import os
open(os.environ["MSG_FILE"],"a").write("".join(
    json.dumps({"task":(json.loads(m.get("payload") or "{}") or {}).get("taskId",""),
                "subject":m.get("subject",""),"body":m.get("body","")})+"\n"
    for m in msgs))
' 2>/dev/null)
  # stop when the delivery pointer stops advancing (nothing left to drain)
  [ -z "$next" ] && break
  [ "$next" = "$delivery" ] && break
  delivery="$next"
done

# ------------------------------------------------------------------- terminals
orca-ide terminal list --json 2>/dev/null > /tmp/.poll-terms.$$ || exit 2

MSG_FILE="$MSG_FILE" OPEN_TASKS="$OPEN_TASKS" VERDICTS="$VERDICTS" SAVE_DIR="$SAVE_DIR" \
SIGNATURE="$SIGNATURE" \
python3 - /tmp/.poll-terms.$$ <<'PY'
import json, os, re, subprocess, sys

terms = json.load(open(sys.argv[1]))["result"]["terminals"]
os.unlink(sys.argv[1])

def read(handle, full=False):
    """Full=True reads the ACCUMULATED buffer, not the viewport (see header note 3)."""
    cmd = ["orca-ide","terminal","read","--terminal",handle,"--json"]
    cmd += ["--cursor","0","--limit","200000"] if full else ["--screen"]
    try:
        d = json.loads(subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout)
        return "\n".join(d["result"]["terminal"].get("tail", []))
    except Exception:
        return ""

STATUS = re.compile(r"·\s*(Working|Ready)\s*·")
MODEL  = re.compile(r"(gpt-[\d.]+-\w+|Opus [\d.]+|Sonnet \d[\d.]*)", re.I)
EFFORT = re.compile(r"gpt-[\d.]+-\w+\s+(xhigh|high|medium|low)")
TOOLS  = re.compile(r"✓\s*\w+×\d+")

def git(path, *args):
    try:
        return subprocess.run(["git","-C",path,*args], capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        return ""

# Uncommitted changes are the only honest "this round produced work" signal.
# Commits ahead of main are NOT usable here: they survive from earlier rounds,
# so a wedged new dispatch would still look like it had done something.
tree_state = {}
def tree_dirty(path):
    if path not in tree_state:
        tree_state[path] = bool(git(path, "status", "--porcelain"))
    return tree_state[path]

MAIN_CHECKOUT = os.environ["PP_MAIN"].rstrip("/")

rows, finished = [], []
for t in terms:
    h  = t["handle"]
    path = t["worktreePath"].rstrip("/")
    wt = path.split("/")[-1]
    if path == MAIN_CHECKOUT:      # this orchestrating session, not a dispatched agent
        continue
    title = (t.get("title") or "").strip()
    screen = read(h)

    # Match ONLY the status bar, never the pane body. Searching the whole screen
    # reads whatever the agent happens to be displaying -- a brief that mentions
    # a model name, a diff, a log line -- and reported the wrong model for a pane
    # that was running something else. Model identity is a hard rule here (never
    # the wrong model on an implementation dispatch), so a check that can be spoofed by on-screen
    # text is worse than none: it would both invent violations and mask real ones.
    bar = next((l for l in reversed(screen.splitlines())
                if ("ctx " in l or "Context " in l) and MODEL.search(l)), "")
    m = MODEL.search(bar)
    model = m.group(1) if m else ""
    if not model:
        # No model banner yet. A pane that is still booting must NOT vanish from
        # the table -- a silently missing agent is the thing this exists to catch.
        # A long-lived plain shell has a prompt and no agent; skip only those.
        if screen.strip() and "$" in screen.splitlines()[-1]:
            continue
        rows.append((wt, title[:26], "(starting)", "booting", "", h))
        continue
    eff = EFFORT.search(bar)
    if eff: model += f" {eff.group(1)}"

    # Last status marker in the bar wins; absent one on a Claude pane = idle prompt.
    st = STATUS.findall(screen)
    working = (st[-1] == "Working") if st else ("esc to interrupt" in screen)

    if not working and not model.startswith("gpt-"):
        # A Claude pane shows no marker in the GAP between two tool calls, so a
        # single sample catches a healthy agent mid-blink and calls it idle. The
        # watcher debounces across cycles; a one-shot run has no next cycle, so
        # re-sample here. The tool-count line advances while work is happening,
        # which distinguishes a blink from a genuinely quiet pane.
        import time as _t
        before = TOOLS.findall(screen)
        _t.sleep(1.5)
        again = read(h)
        if "esc to interrupt" in again or TOOLS.findall(again) != before:
            working = True
            screen = again

    is_codex = model.startswith("gpt-")
    verdict = ""
    if is_codex and not working:
        # Only now pay for the full buffer -- this is where the verdict lives.
        buf = read(h, full=True)
        # The BRIEF is echoed into the pane and literally contains
        # "End with `VERDICT: GO` or `VERDICT: NO-GO`". Taking the last VERDICT
        # match therefore reported a confident NO-GO for a reviewer that had not
        # answered at all. Skip any match that is part of that instruction.
        verdict = ""
        # No \b anchor: the TUI concatenates counters straight onto the verdict
        # ("NO-GO4650"), and a word boundary never matches between O and 4 -- that
        # silently hid a real NO-GO carrying a P1.
        for m in re.finditer(r"VERDICT:\s*(NO-GO|GO)", buf):
            ctx = buf[max(0, m.start() - 40):m.start()]
            if "End with" in ctx or "` or `" in ctx or "or `VERDICT" in ctx:
                continue
            verdict = m.group(1)
        if os.environ.get("SAVE_DIR"):
            p = os.path.join(os.environ["SAVE_DIR"], f"{wt}.{title or h[:12]}.txt".replace("/","_"))
            open(p,"w").write(buf); finished.append((title or h[:12], p, verdict))
        elif os.environ.get("VERDICTS") == "1":
            finished.append((title or h[:12], None, verdict, buf))

    if working:
        state = "working"
    elif is_codex:
        # A reviewer is only finished if it actually produced a verdict.
        state = "DONE" if verdict else "idle (no verdict)"
    else:
        # An implementer's "idle" means nothing on its own (note 4), and the TUI
        # cannot reliably separate "finished" from "thinking" -- a pause longer
        # than the re-sample window looks identical to a finished run. So do NOT
        # say DONE here: report only the fact the tree gives. The authoritative
        # finish signal for a worker is its worker_done message, which arrives
        # over the queue and is printed under "worker reports" below.
        # NOTE: this is the WORKTREE's state, not this pane's. Several panes share
        # one worktree, so a read-only reviewer sitting beside a working implementer
        # inherits its dirty tree and can look as though IT wrote code. Label it as
        # the worktree's, so the reading cannot be mistaken for an attribution.
        state = "wt has changes" if tree_dirty(path) else "wt clean, idle"

    rows.append((wt, title[:26], model, state, verdict, h))

if os.environ.get("SIGNATURE") == "1":
    # One stable line per pane for change detection. The title carries a braille
    # spinner that advances every frame, so strip non-ASCII or the signature would
    # differ on every cycle and every poll would look like a state change.
    # Lead with the HANDLE: it is the only stable identity. Claude renames its
    # own pane when it picks up a task, so keying identity on the title made a
    # rename look like one pane vanishing and another appearing.
    for wt, title, model, state, verdict, h in sorted(rows):
        clean = re.sub(r"[^\x20-\x7e]", "", title).strip()
        print(f"{h}|{wt}|{clean}|{model}|{state}|{verdict}")
    raise SystemExit(0)

w = max([len(r[0]) for r in rows] + [8])
print(f"{'worktree'.ljust(w)}  {'terminal'.ljust(26)}  {'model'.ljust(20)}  {'state'.ljust(17)}  verdict")
print("-" * (w + 76))
for wt, title, model, state, verdict, _h in sorted(rows):
    print(f"{wt.ljust(w)}  {title.ljust(26)}  {model.ljust(20)}  {state.ljust(17)}  {verdict}")

# Tasks do not carry their worktree, so this cannot tell "wedged" from "already
# committed" on its own. State the fact and let the reader judge -- a banner that
# cries wolf on every committed unit is worse than no banner.
if any(r[3] == "wt clean, idle" for r in rows):
    print('\nnote: "wt clean, idle" = nothing on disk in that WORKTREE (shared by its panes).')
    print("      unit's work is already committed. If you dispatched a task to that pane,")
    print("      it never ran (wedged -- orchestration.md step 4): terminal close, then")
    print("      re-run worker-start. Re-injecting into the wedged pane does NOT help.")

# Reports that DID arrive over the RPC, for tasks still open.
open_ids = set(os.environ.get("OPEN_TASKS","").split())
seen = set()
msgs = []
for line in open(os.environ["MSG_FILE"]):
    try: m = json.loads(line)
    except Exception: continue
    k = (m["task"], m["subject"])
    if k in seen: continue
    seen.add(k)
    if m["task"] in open_ids:
        msgs.append(m)
if msgs:
    print("\nworker reports (open tasks):")
    for m in msgs:
        print(f"  [{m['task']}] {m['subject']}")
        if m["body"]:
            print("    " + m["body"][:1500].replace("\n", "\n    "))

if finished and os.environ.get("SAVE_DIR"):
    print("\nfinished reviewer buffers:")
    for name, path, v in finished:
        print(f"  {name}: {v or '(no verdict line)'} -> {path}")
elif finished:
    for item in finished:
        name, _, v, buf = item
        print(f"\n===== {name}  VERDICT: {v or '(none)'} =====")
        i = buf.rfind("VERDICT")
        seg = buf[max(0, i-7000):i+20] if i > 0 else buf[-7000:]
        seg = re.sub(r"(?:•?W?o?r?k?i?n?g?[•·]){4,}[^\n]*", "", seg)   # strip TUI repaint noise
        print(seg)
PY
