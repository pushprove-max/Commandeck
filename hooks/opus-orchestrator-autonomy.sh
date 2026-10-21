#!/usr/bin/env bash
# Opus-as-orchestrator autonomy: the context overlay and the premature-stop
# guard, two modes behind ONE gate so "is this seat in scope" has a single home.
#
#   (no argument)  SessionStart -- print the autonomy overlay into the context.
#   --stop         Stop hook    -- refuse a stop that asks permission to carry
#                                  on with work the user already authorized.
#
# The gate is model AND seat: any Opus model, orchestrator seat only. Seat
# detection reuses the rule context-clear-stop.sh already uses, so there is one
# definition of a seat in the hooks: COMMANDECK_REVIEWER=1 is a reviewer, a
# linked git worktree is a worker, and the main checkout is the orchestrator.
# Sol, Luna, Astra and Codex seats never reach this hook because they are not
# Claude panes; a Fable or Sonnet main falls out at the model check.
#
# Why a hook and not prose in a rules file: prose is advice the model weighs
# against its own caution, and the failure this exists to stop IS excess
# caution. The Stop hook hands the turn back with the reason instead, the same
# shape context-clear-stop.sh uses for the checkpoint line.
set -u
MODE=${1:-}
input=$(cat 2>/dev/null || true)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$input"

# --- gate, part 1: the seat ------------------------------------------------
# A reviewer must stop the moment it has a verdict; that is its whole job.
[ "${COMMANDECK_REVIEWER:-}" = "1" ] && exit 0
# A worker owns one unit in a linked worktree and reports to main; the unit
# loop decides when it continues, not this hook.
gd=$(git rev-parse --git-dir 2>/dev/null || true)
gc=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -n "$gd" ] && [ "$gd" != "$gc" ]; then exit 0; fi

# --- gate, part 2: the model ----------------------------------------------
# The transcript is the only source that reports what actually answered this
# turn; the pin and the pane command line are fallbacks for a first turn that
# has written no assistant row yet. COMMANDECK_SEAT_MODEL overrides all three,
# which is how the self-test drives every row of the matrix.
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
model=${COMMANDECK_SEAT_MODEL:-}
if [ -z "$model" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  model=$(tail -c 1000000 "$transcript" | grep -o '"model":"[^"]*"' | tail -1 | cut -d'"' -f4)
fi
[ -n "$model" ] || model=$(jq -r '.model // empty' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null)
[ -n "$model" ] || model=$(ps -o args= -p "$PPID" 2>/dev/null | grep -o -- '--model [^ ]*' | awk '{print $2}')
printf '%s' "$model" | grep -qi opus || exit 0

# --- mode 1: the overlay ---------------------------------------------------
if [ "$MODE" != "--stop" ]; then
  cat <<'OVERLAY'
# Opus orchestrator: continuation is the default

You are the top-level orchestrator. The user's request authorizes you to
complete the whole scope they asked for. Keep going until it is done.

Decide for yourself: architecture, implementation, sequencing, delegation,
testing, debugging and remediation. When several reasonable approaches exist,
pick the best one and continue. Say which one you picked and why, in a line.

None of these is a checkpoint. They are transitions in your own workflow:

- planning finished
- a phase finished
- a subagent or worker finished
- a reviewer returned findings
- two models disagree
- tests failed
- something needs remediation
- a reasonable decision has to be made

A reviewer finding is an input, not an approval gate. Evaluate it; if it is
valid and in scope, fix it and carry on. A test failure is work to do, not a
reason to stop: diagnose it, fix it, run it again.

Do not ask "should I continue", "shall I proceed", "would you like me to
implement this" or "should I fix these" while authorized work remains.

Ask the user only when one of these is true:

1. You need information you cannot get from the repo, your tools, the
   documentation, existing context, or reasonable inference.
2. Assuming would materially change the result they asked for, or would cause
   substantial rework or something irreversible.

Otherwise make the reasonable assumption, state it, and continue. When you do
have to ask, use AskUserQuestion.

Before you end a turn, check whether authorized work is left. If work remains
and nothing genuinely blocks you, keep working. Do not widen the scope just
because further improvements are possible: finishing what was asked is the
goal, and inventing more work is its own failure.

This overlay changes when you stop, never how carefully you work. Reading
before editing, verifying claims, running the tests and surfacing conflicts all
stand exactly as they are.
OVERLAY
  exit 0
fi

# --- mode 2: the stop guard ------------------------------------------------
# One nudge, never a loop: a second stop in the same chain always passes, so a
# genuine blocker phrased like a question still gets out on the next stop.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

rows=$(tail -c 1000000 "$transcript" | grep '"type":"assistant"' | tail -10)
[ -n "$rows" ] || exit 0
# AskUserQuestion is the sanctioned way to raise a real blocker, so a turn that
# used it is asking properly and may stop.
printf '%s' "$rows" | grep -q '"name":"AskUserQuestion"' && exit 0

last=$(printf '%s\n' "$rows" \
  | jq -r '([.message.content[]? | select(.type=="text") | .text] | join(" ")) // ""' 2>/dev/null \
  | grep -v '^[[:space:]]*$' | tail -1)
[ -n "$last" ] || exit 0

# Permission-seeking phrasing only. A plain completion report, a closing
# "next" line and a statement of what was decided all pass untouched, which is
# what keeps a finished task from being blocked into inventing more work.
ASK='should i (continue|proceed|go ahead|start|implement|apply|fix|address|remediate|keep going|move on)'
ASK="$ASK"'|shall i (continue|proceed|go ahead|start|implement|apply|fix|address|remediate)'
ASK="$ASK"'|would you like me to|do you want me to'
ASK="$ASK"'|want me to (continue|proceed|fix|implement|apply|address|go ahead)'
ASK="$ASK"'|let me know (if|whether|how) you'
ASK="$ASK"'|ready (to proceed|for me to)'
ASK="$ASK"'|(awaiting|waiting for|waiting on|need) your (approval|go|go-ahead|confirmation|input|decision|sign-off|ruling)'
# Word-bounded: "before I fixed the brief" is a report, not an ask. And only in
# a sentence that ends with a question mark: "I am waiting for the
# marker before I start the merge." is a report too.
ASK="$ASK"'|before i (proceed|continue|implement|start|fix)([^[:alnum:]_.!?][^.!?]*)?\?'
ASK="$ASK"'|(approve|confirm) (this|the) (plan|approach|fix|change|findings)'
ASK="$ASK"'|(proceed|continue)\?'

hit=$(printf '%s' "$last" | tr '\n' ' ' | grep -oiE "$ASK" | head -1)
[ -n "$hit" ] || exit 0

HOOK_FIRE_BLOCK=1
jq -n --arg h "$hit" '{
  decision: "block",
  reason: ("Continue now: take the option you would recommend, say which, and finish the work. " +
    "You are the orchestrator and you ended the turn with \"" + $h +
    "\". That is asking permission to carry on with work the user already " +
    "authorized. Planning, a phase ending, a worker finishing, reviewer " +
    "findings, a test failure and a decision between reasonable options are " +
    "all workflow transitions, not user checkpoints. Make the call, say which " +
    "option you took, and finish the authorized work. If something genuinely " +
    "blocks you -- information you cannot get from the repo, the tools or " +
    "context, or an assumption that would cause substantial rework or " +
    "something irreversible -- ask with AskUserQuestion and this hook will let " +
    "the turn end.")
}'
exit 0
