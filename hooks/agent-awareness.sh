#!/usr/bin/env bash
# UserPromptSubmit hook -- surface dispatched-work state EVERY turn so it survives
# context summarization (the root cause of losing track of dispatched agents).
# Read-only and concise; only prints when there is something to flag.
# Workers run as CLIs in Orca worktrees, so the live state lives in Orca, not
# in a markdown ledger.
#
# THE COORDINATOR IS THE ONLY READER. Every line here is about work main
# dispatched: unpushed commits to reconcile, worktrees to verify, cage headroom
# to spend. A worker in a linked worktree dispatches nothing and cannot act on
# any of it, so it paid two git scans, a pgrep and three RPCs a turn for text it
# had to ignore. Topology is the test.
#
# AND ONLY WHEN IT CHANGED. The state is identical across most consecutive
# prompts, so re-printing it is the same paragraph every turn -- which is how a
# banner stops being read. The assembled text is hashed and reprinted only when
# it differs from the last turn's, EXCEPT the over-budget cage warning, which
# prints every turn it is true because it is the one line that must not be
# skimmed past. COMMANDECK_AWARENESS_DIR relocates the record for the self-test.
set +e
[ -t 0 ] || IFS= read -r -d '' INPUT
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "${INPUT-}" UserPromptSubmit
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/paths.sh" || exit 1
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/host-services.sh"
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
GIT="git --no-optional-locks"

if [ "$($GIT rev-parse --git-dir 2>/dev/null)" \
   != "$($GIT rev-parse --git-common-dir 2>/dev/null)" ]; then
  exit 0
fi

out=""
ALWAYS=0

# 1) Unpushed local commits -- a worker that committed shows up here.
up=$($GIT rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
range=""
if [ -n "$up" ]; then range='@{u}..HEAD'; elif $GIT rev-parse origin/main >/dev/null 2>&1; then range='origin/main..HEAD'; fi
if [ -n "$range" ]; then
  # Count plus the newest three, subjects cut short. The full 20-line list
  # cost ~2.4K characters on EVERY turn of a plan session and the signal is
  # only a commit main did not make, which surfaces at the top.
  unpushed=$($GIT log --format='%h %<(70,trunc)%s' -n 3 "$range" 2>/dev/null)
  if [ -n "$unpushed" ]; then
    n=$($GIT rev-list --count "$range" 2>/dev/null)
    branch=$($GIT rev-parse --abbrev-ref HEAD 2>/dev/null)
    out+="$n UNPUSHED commit(s) on $branch (newest 3; a hash you did not make means a worker committed):\n$unpushed\n\n"
  fi
fi

# 2) Live Orca worktrees (anything but the main checkout) with their agents.
# Bounded: Orca calls are RPCs; a stalled runtime must not stall every prompt.
if command -v orca-ide >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  # The three RPCs are independent, so they run together. A call that hits its
  # cap leaves a .late marker: an empty list from a stalled runtime must read
  # as "not checked", never as "nothing is running".
  OT=$(mktemp -d)
  { timeout 20 orca-ide worktree ps --json >"$OT/wts" 2>/dev/null; [ $? -ne 124 ] || : >"$OT/wts.late"; } &
  { timeout 20 orca-ide terminal list --json >"$OT/live" 2>/dev/null; [ $? -ne 124 ] || : >"$OT/live.late"; } &
  { timeout 20 orca-ide orchestration task-list --brief --json >"$OT/tasks" 2>/dev/null; [ $? -ne 124 ] || : >"$OT/tasks.late"; } &
  wait
  late=""
  for n in wts:worktrees live:panes tasks:tasks; do [ ! -e "$OT/${n%%:*}.late" ] || late+=" ${n#*:}"; done
  if [ -n "$late" ]; then
    out+="Orca state NOT CHECKED (no answer in 20s):$late -- the lists below may be missing live work\n\n"; ALWAYS=1
  fi
  wts=$(jq -r '
    .result.worktrees[]? | select(.isMainWorktree != true)
    | select(.isArchived != true)
    | "  \(.displayName) [\(.branch | sub("^refs/heads/";""))] status=\(.workspaceStatus) terminals=\(.liveTerminalCount // 0)"
      + ((.agents // []) | map(" orca-says=\(.agentType):\(.state)") | join(""))' <"$OT/wts" 2>/dev/null)
  if [ -n "$wts" ]; then
    out+="Orca worktrees (verify each is yours; Orca task-list is the ledger):\n$wts\n\n"
  fi
  # Live panes, fetched once and reused by the task filter and the cage line.
  LIVE=$(jq -c '[.result | flatten | .[] | objects | select(.agentIdentity != null) | .handle]' <"$OT/live" 2>/dev/null)
  [ -n "$LIVE" ] || LIVE='[]'
  # A live pane a round's .kept file names is not debris: close-round.sh keeps a
  # round's finished reviewers while a lens is missing, and review-round.sh's
  # same-round relaunch carries their verdicts over. The worktree line above
  # still reports them as agent=...:done, which reads as leaked.
  # Old .kept files name long-dead handles, so only the live intersection prints.
  warm=$(grep -ho 'term_[0-9a-f-]\{36\}' \
      "$PP_SCRATCH"/review-handles-*.kept 2>/dev/null \
    | sort -u | while read -r h; do case "$LIVE" in (*"$h"*) printf ' %s' "$h" ;; esac; done)
  if [ -n "$warm" ]; then
    out+="Panes kept for the same-round relaunch -- closing one discards the verdict it holds:\n $warm\n\n"
  fi
  # ONLY a task a LIVE pane is working on is actionable. The ledger keeps every
  # dispatched task whose pane is gone and every task created and never
  # dispatched, so after the 2026-09-11 crash 29 rows printed on EVERY prompt,
  # 3.2 KB of this hook's 5 KB, and all but four were dead. Live rows in full;
  # the rest as one count, because the only action they support is closing them.
  # An Orca task row names its CREATOR, never its assignee: there is no
  # `assignee_handle` field, so matching on one scored every open task as dead
  # and this hook cried "no live pane" on every prompt of 2026-09-15 while all
  # four panes were working. The seat record is the pairing that exists -- it
  # names the task and the pane together -- so a record whose pane is live
  # makes its task active.
  LIVE_TASKS=$(awk -F= '/^handle=/{h=$2} /^task=/ && h {print $2, h; h=""}' \
      "$PP_SCRATCH"/seat-*.txt 2>/dev/null \
    | while read -r t h; do case "$LIVE" in (*"$h"*) printf '%s\n' "$t" ;; esac; done \
    | jq -R . | jq -sc . 2>/dev/null)
  [ -n "$LIVE_TASKS" ] || LIVE_TASKS='[]'
  tasks=$(jq -r --argjson live "$LIVE_TASKS" '
    [.result.tasks[]? | select(.status != "completed" and .status != "failed")] as $open
    | [$open[] | select(.id as $i | $live | index($i))] as $active
    | (($open | length) - ($active | length)) as $stale
    | (($active | map("  \(.id) \(.status): \(.spec // .task_title // "" | .[0:100])")
        + (if $stale > 0 then ["  + \($stale) open task(s) with no live pane -- close with task-update --status completed|failed"] else [] end))
       | join("\n"))' <"$OT/tasks" 2>/dev/null)
  rm -rf "$OT"
  if [ -n "$tasks" ]; then
    out+="Open Orca tasks:\n$tasks\n\n"
  fi
  # The drivers, with the stage each one reached. A pane's agent state says a
  # seat is thinking; only the driver says which stage of the unit that seat
  # belongs to, and a driver that died leaves its panes working on a round
  # nobody will collect. Main spent six calls on 2026-09-15 rediscovering this
  # because nothing printed it. `run-*` needs the .service suffix or systemd's
  # own transient scopes bury the drivers.
  hs_list --no-legend >/dev/null 2>&1 \
    || out+="SERVICE STATE UNKNOWN: the service manager gave no answer; live drivers may be missing below\n\n"
  drivers=$(hs_list --no-legend --plain --all \
      'loop-*' 'drive-*' 'chain-*' 'run-*.service' \
    | awk '{print $1, $3"/"$4}' \
    | while read -r u st; do
        n=${u%.service}; unit=${n%-*}; unit=${unit#*-}
        # The driver's own log, by exact name: loop-run.sh writes
        # <unit>-<kind>-<epoch>.log and chain-run.sh <name>.log. A prefix glob
        # picked a sibling unit's newer log.
        log=$PP_SCRATCH/scratchpad/$unit-${n%%-*}-${n##*-}.log
        [ "${n%%-*}" != chain ] || log=${log%/*}/$n.log
        [ -f "$log" ] || log=""
        printf '  %s %s%s\n' "$n" "$st" "${log:+ | $(tail -1 "$log" | cut -c1-110)}"
      done)
  if [ -n "$drivers" ]; then
    out+="Live drivers (the stage each unit reached; no line here means NO driver is watching):\n$drivers\n\n"
  fi
fi
# main-watch.sh is the one thing that wakes main: down means nothing
# will, so this prints on every prompt until it runs again.
if ! mw=$(bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/main-watch.sh" --status); then
  out+="$mw\n\n"; ALWAYS=1
fi
# The owner's open asks print every turn: an answer given in chat closes nothing on
# the dashboard's Needs Owner card until main records it.
open=$(bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/decision.sh" list 2>/dev/null \
  | jq -r 'map(select(.answeredAt == null) | .id) | join(", ")' 2>/dev/null)
if [ -n "$open" ]; then
  out+="Open decisions for the owner: $open\n  when they answer: bash ${BASH_SOURCE[0]%/*}/../scripts/decision.sh answer <id> '<answer>'\n\n"; ALWAYS=1
fi

# 2b) Dependency-aware ready/blocked view (beads-lite). Orca's task-list is a
# flat dump; this renders which OPEN units are actionable now vs waiting on
# another unit. Source of truth: .claude/orchestration-deps.tsv (main-only).
deps=".claude/orchestration-deps.tsv"
if [ -f "$deps" ]; then
  rb=$(awk -F'\t' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { unit[$1]=1; dep[$1]=$2; note[$1]=$3; order[++n]=$1 }
    END {
      for (i=1;i<=n;i++) {
        u=order[i]; blockers="";
        if (dep[u] != "" && dep[u] != "-") {
          m=split(dep[u], d, ",");
          for (j=1;j<=m;j++) { gsub(/^ +| +$/,"",d[j]); if (d[j] in unit) blockers=blockers (blockers?", ":"") d[j] }
        }
        if (blockers=="") { ready[++r]=u } else { blk[++b]=u; blkof[u]=blockers }
      }
      if (r) { print "READY (deps satisfied):"; for (i=1;i<=r;i++) printf "  %s -- %s\n", ready[i], note[ready[i]] }
      if (b) { print "BLOCKED:";                for (i=1;i<=b;i++) printf "  %s -- waits on: %s\n", blk[i], blkof[blk[i]] }
    }' "$deps" 2>/dev/null)
  if [ -n "$rb" ]; then
    out+="Unit dependency ledger (.claude/orchestration-deps.tsv):\n$rb\n\n"
  fi
fi

# 3) Stray headless workers outside Orca (codex exec / claude -p) -- these are
# not part of the sanctioned flow any more; anything here needs reconciling.
# Whitelist: the memoir + session-tracker Stop-hooks spawn a short-lived
# `claude -p --model haiku` to summarize the ending turn -- that is a sanctioned
# memory helper, not a rogue worker, and it is still finishing when the next
# prompt fires. Filter it out so this stops crying wolf every turn.
# ps, not pgrep: the Mac's BSD pgrep prints pids only and -a adds its own
# ancestors, a fresh pid every prompt that defeated the once-per-state hash.
# The [c] keeps awk's own command line from matching.
# Ours only: a worker counts when its parent chain reaches Orca or an interactive
# claude/codex. Another app's headless claude (2026-10-01) is
# not ours, and a headless ancestor proves nothing either way.
# ponytail: a worker of ours orphaned to launchd/init is not listed; match by cwd
# (lsof) if one ever leaks that way.
workers=$(ps -eo pid=,ppid=,args= 2>/dev/null | awk '
  { pid = $1; up[pid] = $2; c = $0; sub(/^ *[0-9]+ +[0-9]+ +/, "", c); cmd[pid] = c; order[++n] = pid }
  # The program, not a word in the command text: argv0, or the script node/bun
  # runs. AI is its argv index. A shell that merely mentions claude is neither.
  function agent(s,   a, b) {
    split(s, a, " "); b = a[1]; sub(/.*\//, "", b); AI = 1
    if (b == "node" || b == "bun") { b = a[2]; sub(/.*\//, "", b); AI = 2 }
    return b == "claude" || b == "codex" ? b : ""
  }
  # Headless claude is -p/--print anywhere after the program (`claude --model
  # x -p`); a positional match read a reordered foreign parent as interactive.
  # Headless codex is the exec subcommand, the first positional past the global
  # flags that take a value: `exec` in an interactive prompt is only a word.
  # ponytail: a claude prompt holding a bare -p token reads as headless; parse
  # the claude value flags too if that misfires. No apostrophes: awk is quoted.
  function headless(s,   a, k, j, b) {
    if ((b = agent(s)) == "") return 0
    k = split(s, a, " ")
    for (j = AI + 1; j <= k; j++) {
      if (b == "claude") { if (a[j] == "-p" || a[j] == "--print") return 1; continue }
      if (a[j] ~ /^-(c|i|m|p|s|C|a|-(config|enable|disable|remote|remote-auth-token-env|image|model|local-provider|profile|sandbox|cd|add-dir|ask-for-approval))$/) { j++; continue }
      if (a[j] !~ /^-/) return a[j] == "exec" || a[j] == "e"
    }
    return 0
  }
  function ours(p,   hops) {
    for (p = up[p]; p in cmd && hops++ < 64; p = up[p]) {
      if (cmd[p] ~ /\/Orca\.app\/|(^|\/)orca(-ide)?( |$)/) return 1
      if (agent(cmd[p]) != "" && !headless(cmd[p])) return 1
    }
    return 0
  }
  END { for (i = 1; i <= n; i++) { p = order[i]
    if (headless(cmd[p]) && cmd[p] !~ /[c]laude -p --model haiku/ && ours(p)) print p, cmd[p] } }')
if [ -n "$workers" ]; then
  wn=$(printf '%s\n' "$workers" | wc -l | tr -d ' ')
  out+="$wn headless worker process(es) alive outside Orca (codex exec / claude -p) -- reconcile:\n$(printf '%s\n' "$workers" | sed 's/^/  /' | cut -c1-100)\n"
fi
# A Codex plugin helper (app-server-broker.mjs + its codex app-server child) is
# not a worker: one runs per worktree. Only a pair whose worktree is gone needs
# action, and the action is a kill by pid.
orphans=$(bash "${BASH_SOURCE[0]%/*}/../scripts/codex-helpers.sh" orphans 2>/dev/null)
if [ -n "$orphans" ]; then
  out+="$(echo $orphans | wc -w) orphaned Codex helper process(es) whose worktree is gone -- kill $orphans\n"
fi

# 4) Orca's memory cage. Two crashes on 2026-09-03 were the scope's own
# MemoryMax (36 GB) oom-killing Orca under seven agent panes plus a suite;
# the budget is the line this prints. Shown every turn so
# main sees the headroom BEFORE it dispatches.
scope=$(ls -d ${COMMANDECK_ORCA_SCOPE_GLOB:-/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-orca-*.scope} 2>/dev/null | head -1)
if [ "$(hs_os)" != Darwin ] && [ -n "$scope" ] && [ -r "$scope/memory.stat" ]; then
  # Process memory (anon) is the number that can OOM the cage; memory.current
  # also counts page cache, which the kernel drops before it kills anything.
  # On 2026-09-04 current read 31 GB while anon was 6.7 GB, and main held
  # back dispatches for hours on a number that was 22 GB of file cache.
  cur=$(awk '$1=="anon" {printf "%d", $2/1073741824}' "$scope/memory.stat")
  cache=$(awk '$1=="file" {printf "%d", $2/1073741824}' "$scope/memory.stat")
  max=$(cat "$scope/memory.max"); [ "$max" = max ] && max=uncapped || max="$(( max / 1073741824 )) GB cap"
  panes=$(printf '%s' "${LIVE:-[]}" | jq -r 'length' 2>/dev/null)
  # Since 2026-09-11 every dispatched pane runs inside its own systemd scope
  # (`pane-box.sh`, 8 GB each), and a scope lands under app.slice OUTSIDE Orca's
  # cgroup. So the cage number above no longer counts the workers at all, and
  # reading it alone would say 3 GB while four panes held 30. Sum the boxes.
  boxed=0; nboxes=0
  for d in ${COMMANDECK_PANE_SCOPE_GLOB:-/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/run-*.scope}; do
    [ -r "$d/memory.current" ] || continue
    [ "$(cat "$d/memory.max" 2>/dev/null)" = max ] && continue
    boxed=$(( boxed + $(cat "$d/memory.current" 2>/dev/null || echo 0) ))
    nboxes=$(( nboxes + 1 ))
  done
  boxed=$(( boxed / 1073741824 ))
  total=$(( cur + boxed ))
  warn=""; [ "$total" -ge 28 ] && { warn=" -- OVER 28 GB in use: dispatch nothing until a pane closes"; ALWAYS=1; }
  out+="Orca cage: ${cur} GB process memory (+${cache} GB reclaimable cache) of ${max}, ${panes:-?} agent pane(s); ${nboxes} boxed pane(s) hold ${boxed} GB outside the cage, ${total} GB together; ceiling 12 GB on an editing seat, 8 GB read-only, stop at 28 GB${warn}\n"
fi

[ -n "$out" ] || exit 0

if [ "$ALWAYS" = 0 ]; then
  STATE_DIR="${COMMANDECK_AWARENESS_DIR:-$HOME/.cache/commandeck/agent-awareness}"
  if mkdir -p "$STATE_DIR" 2>/dev/null; then
    STATE="$STATE_DIR/$(pwd | sha1sum | cut -c1-40)"
    # HASH THE CAGE LINE WITHOUT ITS NUMBERS. Its GB figures move a little on
    # every prompt, so hashing the raw text made this whole block reprint on
    # EVERY turn and the once-per-state rule never fired once in practice --
    # 1.3K tokens a turn for a paragraph that had not changed. The printed text
    # still carries the real numbers, and the over-28 GB warning sets ALWAYS=1,
    # so the one line that must not be missed is still exempt.
    # A driver's log tail changes on every prompt while a loop runs, so the
    # driver rows are hashed without it; the stage word stays in the hash.
    NOW=$(printf '%b' "$out" | sed -E '/^Orca cage:/ s/[0-9]+/N/g; /^  (loop|drive|chain|run)-/ s/ \| .*$//' | sha1sum | cut -c1-40)
    [ -f "$STATE" ] && read -r PREV < "$STATE"
    [ "${PREV:-}" = "$NOW" ] && exit 0
    printf '%s\n' "$NOW" > "$STATE" 2>/dev/null
  fi
fi

printf '## Dispatched-work state (agent-awareness hook)\n%b' "$out"
exit 0
