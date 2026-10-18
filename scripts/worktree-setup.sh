#!/usr/bin/env bash
# worktree-setup.sh <worktree-path> -- one home for what every Orca worktree
# needs before its first pane boots. Idempotent; main runs it right after
# `orca-ide worktree create`.
#
# 1. node_modules symlinks to the main checkout, where it has them (gitignored;
#    never `git add`).
# 2. .claude/settings.local.json with the worker compact window. A worker's
#    whole context is re-sent on every turn, and compaction fires at roughly
#    two thirds of the configured window, so the window is set well above the
#    trigger it is meant to buy. 450K (ruling 2026-09-17, superseding the
#    2026-09-07 350K) targets a ~300K trigger: measured over 7 days of worker
#    transcripts, 138 of 164 auto-compactions fired below 300K, so the 350K
#    window almost never bound. Each compaction costs re-reads -- in the 25
#    turns after one, a worker re-opened an already-read file 40% of the time
#    against an 18% baseline. The file is globally gitignored,
#    so it never rides a unit commit, and main's own settings.local.json is
#    untouched because main is not a worktree.
#
# A worker or Builder pane also starts lean (the owner, 2026-10-18): Stripe and the three browser skills off,
# auto memory off (the brief carries what the unit needs), and a ~1 KB ponytail summary in place of the plugin's
# full print. --keep <list> (billing: keep Stripe; all: change none of this) is stored in env, so a rerun without
# the flag keeps it. A rerun deletes every leaf this script owns before it writes the current set; no other leaf is
# touched, so an owner's own skillOverrides entry stays. On top, the owner's own lists in commandeck.json (setup's
# answers; the plugin ships no name): workerSkillsOff and workerPluginsOff are cut too, and a --keep word named in
# keeps brings its skills and plugins back, the ones cut by default included. The leaves a run cuts for the lists are
# stored in env, so a list that shrinks loses them; a name the owner already set in the file is theirs, never cut or stored.
set -euo pipefail
USAGE="usage: worktree-setup.sh <worktree-path> [--builder] [--keep <billing|all|a keep word>[,...]] [--print-settings]"
WT=${1:?$USAGE}; shift
BUILDER=0 PRINT=0 KEEP= KEEPSET=0
# --print-settings: writes nothing in <wt>, prints the settings file a fresh run would leave (plan-worktree-close.sh compares it).
while [ $# -gt 0 ]; do
  case $1 in
    --builder) BUILDER=1; shift ;;
    --print-settings) PRINT=1; shift ;;
    --keep) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; KEEP=$2 KEEPSET=1; shift 2 ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
MAIN=$PP_MAIN
# The plugin's hooks, by full path: an installed plugin is not in the project,
# so neither $MAIN/hooks nor $CLAUDE_PROJECT_DIR/hooks is where they are.
HOOKS=$(cd "$PP_SCRIPTS/../hooks" && pwd)
[ -d "$WT" ] || { echo "no such worktree: $WT" >&2; exit 1; }
[ "$(cd "$WT" && git rev-parse --git-dir)" != "$(cd "$WT" && git rev-parse --git-common-dir)" ] \
  || { echo "refusing: $WT is the main checkout" >&2; exit 1; }

if [ "$PRINT" = 1 ]; then F=$(mktemp); echo '{}' > "$F"; exec 3>&1 >&2
else
  mkdir -p "$WT/.claude"
  F="$WT/.claude/settings.local.json"
  [ -f "$F" ] || echo '{}' > "$F"
fi
# The session's own files never ride a unit commit and never read as untracked
# code at the merge, whatever the project's gitignore says: the repo's shared
# exclude file names them.
EXCLUDE=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir)/info/exclude
[ "$PRINT" = 1 ] || mkdir -p "${EXCLUDE%/*}"
for p in .claude/settings.local.json .claude/builder-events.jsonl; do
  [ "$PRINT" = 1 ] || grep -qxF "$p" "$EXCLUDE" 2>/dev/null || echo "$p" >> "$EXCLUDE"
done
# A Builder stays a Builder: seat.sh launch reruns this script without the flag.
[ "$(jq -r '.env.COMMANDECK_BUILDER // empty' "$F")" = 1 ] && BUILDER=1
# The keep a run stored; a print reads it from the worktree's real file, as its own temp file is empty.
[ "$KEEPSET" = 1 ] || KEEP=$(jq -r '.env.COMMANDECK_SKILL_KEEP // empty' "$([ "$PRINT" = 1 ] && echo "$WT/.claude/settings.local.json" || echo "$F")" 2>/dev/null || true)
tmp=$(mktemp)
# Every leaf the lean-pane settings own: a rerun removes them all before it writes the current set. A move-1 leaf (a
# browser skill, Stripe) is the run's only while COMMANDECK_DEFAULT_CUTS names it and it holds the run's value. The
# ponytail off (the run's only beside the summary hook) is owned on a worker only: the relay branch takes ponytail out.
SUMMARY=$(cd "$PP_SCRIPTS/../templates/ponytail" && pwd)/SUMMARY.md
DISOWN='def disown: (.env.COMMANDECK_OWNER_CUTS // "" | split(",")) as $o | (.env.COMMANDECK_DEFAULT_CUTS // "" | split(",")) as $r
    | del((.skillOverrides[$o[] | select(contains("@") | not)] | select(. == "off")), (.enabledPlugins[$o[] | select(contains("@"))] | select(. == false)))
    | del((.skillOverrides[$r[] | select(contains("@") | not)] | select(. == "off")), (.enabledPlugins[$r[] | select(. == "stripe@claude-plugins-official")] | select(. == false)))
    | del(.autoMemoryEnabled, .env.COMMANDECK_SKILL_KEEP, .env.COMMANDECK_OWNER_CUTS, .env.COMMANDECK_DEFAULT_CUTS, .env.COMMANDECK_OWNER_ON)
    | def sum: (.command // "") | test("/templates/ponytail/SUMMARY[.]md\"$");
      if .hooks.SessionStart then .hooks.SessionStart |= map(if any(.hooks[]?; sum) then (.hooks |= map(select(sum | not))) | select(.hooks != []) else . end) else . end
    | if (.hooks.SessionStart // [1]) == [] then del(.hooks.SessionStart) else . end;'
PLUGINS_OFF='{"customer-support@synced":false,"design@synced":false,"operations@synced":false,"product-management@synced":false,"productivity@synced":false,"cowork-plugin-management@synced":false}'

# The setting is the worktree's own project's, read from its primary checkout.
PROJECT=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); PROJECT=${PROJECT%/.git}
# The Chief-of-Staff relay pane never reads code, so it gets only the
# slimming keys: code servers, code plugins and connectors off. None of the
# worker mechanics below -- its Stop notify hook would wake main every relay turn.
# Same seat test as agent-startup-context.sh: the worktree's directory name.
if [ "$(basename "$(cd "$WT" && git rev-parse --show-toplevel)")" = Chief-of-Staff ]; then
  COS_MCP_DENY='[{"serverName":"serena"},{"serverName":"codebase-memory"},{"serverName":"context7"},{"serverName":"aws-knowledge"},{"serverName":"aws-cloudwatch-dev"},{"serverName":"aws-cloudwatch-prod"},{"serverName":"claude-in-chrome"},{"serverName":"alphaxiv"}]'
  COS_PLUGINS_OFF='{"skill-creator@claude-plugins-official":false,"canvas@claude-canvas":false,"mattpocock-skills@claude-plugins-official":false,"stripe@claude-plugins-official":false,"memoir@memoir":false}'
  # The orca commands the relay pane needs to reach main (owner ruling 2026-10-09); nothing broader.
  COS_ALLOW='["Bash(orca-ide terminal list:*)","Bash(orca-ide terminal send:*)","Bash(orca-ide terminal read:*)","Bash(orca-ide terminal wait:*)","Bash(orca-ide orchestration send:*)","Bash(orca-ide orchestration check:*)","Bash(orca-ide orchestration reply:*)","Bash(orca-ide orchestration inbox:*)"]'
  # Its own watcher scripts and the decision script, each by the full path the
  # startup text names (owner ruling 2026-10-12); no other script.
  COS_ALLOW=$(jq -c --arg s "$PP_SCRIPTS_Q" '. + (["cos-watch-alerts", "cos-watch-decisions", "cos-watch-inbox", "cos-watch-limit", "decision"] | map("Bash(bash \($s)/\(.).sh:*)"))' <<<"$COS_ALLOW")
  # Ponytail runs in every seat, the relay pane too (owner, 2026-10-16): the off an earlier run wrote goes, and the
  # pane follows the owner's own setting; worker panes run it through a summary instead of the plugin. The typescript-lsp plugin is gone, and so is the key for it.
  # The setup answer for the relay's prompt cache: 1h is written into env by path, so its other env entries stay.
  jq --arg rttl "$(jq -r '.chiefOfStaff.cacheTtl // empty' "$PROJECT/.claude/commandeck.json" 2>/dev/null)" --argjson poff "$PLUGINS_OFF" --argjson cpoff "$COS_PLUGINS_OFF" --argjson mdeny "$COS_MCP_DENY" --argjson callow "$COS_ALLOW" "$DISOWN"'
    disown
    | (if $rttl == "1h" then .env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h" else . end)
    | .enabledPlugins = ((.enabledPlugins // {}) + $cpoff + $poff | del(.["ponytail@ponytail"], .["typescript-lsp@claude-plugins-official"]))
    | .disableClaudeAiConnectors = true
    | .deniedMcpServers = ((.deniedMcpServers // []) + $mdeny | unique)
    | .permissions.allow = ((.permissions.allow // []) + $callow | unique)' "$F" > "$tmp"
  mv "$tmp" "$F"
  echo "$WT: Chief-of-Staff relay pane: $(echo "$COS_MCP_DENY" | jq length) MCP servers denied, code + business plugins and claude.ai connectors off, 8 orca command patterns and 5 of the plugin's scripts allowed; no worker settings"
  [ "$PRINT" = 0 ] || { cat "$F" >&3; rm -f "$F"; }
  exit 0
fi

[ "$PRINT" = 1 ] || pp_link_node_modules "$MAIN" "$WT"

WINDOW=${COMMANDECK_WORKER_COMPACT_WINDOW:-450000}
[ "$BUILDER" = 1 ] && WINDOW=300000
# Standard-context models hold 200K: a larger window would never compact.
[ "$(jq -r '.standardContext // false' "$PROJECT/.claude/commandeck.json" 2>/dev/null)" = true ] && WINDOW=180000
# 3. memoir off in worktrees (ruling 2026-09-03). Its SessionStart hook
#    prints the store's 200-key listing (~8 KB) into every pane, its prompt
#    hook adds a ~700-byte "recall before acting" note on every turn, and its
#    Stop hook spawns a capture run. Workers use none of it; main keeps it.
# 4. Tools a worker never uses are denied, which drops their schemas from every
#    turn (ruling 2026-09-03): the dashboard implementer made 116 tool
#    calls, 97% of them Bash, Read and Edit, and never touched Agent,
#    Artifact or the worktree tools -- which the worker rules forbid anyway.
#    Workflow is not on the list (the owner 2026-10-13): any pane may run one,
#    and a denial an earlier run of this script wrote is taken out.
#    Fewer tool definitions in the window is also less to attend to (19 tools
#    beat 46 in the same window in the context-engineering literature).
DENY='["Agent","Artifact","NotebookEdit","EnterPlanMode","ExitPlanMode","EnterWorktree","ExitWorktree","WebSearch","WebFetch","SendUserFile","PushNotification","CronCreate","CronDelete","CronList"]'
# 6. Workers stay in `auto` mode and the commands a worker actually needs are
#    allowlisted, so the classifier never prompts for a read, a test run or
#    a git query (it stalled the prod-config-to-dev implementer on a plain
#    `awk | sed` read, 2026-09-04) but still stands in front of everything
#    else. NOT bypassPermissions: a pane runs on this host with the AWS
#    profiles, including prod admin, and the prompt is the one thing between
#    a worker and `aws --profile <prod> ... delete`. DynamoDB reads
#    are allowed; every write to AWS still prompts and main answers it.
# 7. Main's rulebook is excluded. orchestration.md is path-gated on
#    .claude/briefs/**, so every worker reading its brief loaded it; workers
#    follow worktree-sessions.md and agents.md instead. Do not drop the paths:
#    frontmatter to fix this -- main relies on it when it writes briefs.
EXCLUDE="$(cd "$WT" && pwd)/.claude/rules/orchestration.md"
# 8. Servers and plugins a worker never uses are off: the claude.ai
#    business plugins (synced ones are keyed `<name>@synced`; they bring ~25
#    MCP servers, Pendo among them), the claude.ai connectors (Claude Docs),
#    Chrome and both CloudWatch servers. Measured 2026-09-23 with `claude -p`:
#    startup 35,280 -> 29,392 input tokens, 185 -> 72 tools. serena,
#    codebase-memory, context7 and AWS Knowledge stay. OPT BACK for a seat
#    that needs one (a browser walkthrough): edit this worktree's
#    settings.local.json, e.g.
#    jq 'del(.disableClaudeAiConnectors) | .deniedMcpServers |= map(select(.serverName != "claude-in-chrome"))'
#    and relaunch the pane; a rerun of this script turns them off again.
#    PLUGINS_OFF is set above, shared with the Chief-of-Staff branch.
#    The business plugin and memoir leaves the owner set in this file, read before this step writes over them, so a
#    keep word (step 10) gives each back. A false is the run's only while COMMANDECK_DEFAULT_CUTS names it (ruling
#    2026-10-18: a file with no such key has no false of the run's); an owner's on this step wrote over is named in
#    COMMANDECK_OWNER_ON, so it is still the owner's on the next run.
FIXED=$(jq -c 'keys + ["memoir@memoir"]' <<<"$PLUGINS_OFF")
OWNFIX=$(jq -c --argjson fixed "$FIXED" '(.env.COMMANDECK_DEFAULT_CUTS // "" | split(",")) as $r | (.env.COMMANDECK_OWNER_ON // "" | split(",")) as $on
  | .enabledPlugins // {} | with_entries(select(.key | IN($fixed[])) | if .value == false and (.key | IN($on[])) then .value = true else . end
    | select(.value != false or (.key | IN($r[]) | not)))' "$F")
MCP_DENY='[{"serverName":"claude-in-chrome"},{"serverName":"aws-cloudwatch-dev"},{"serverName":"aws-cloudwatch-prod"}]'
ALLOW='["Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git show:*)","Bash(git ls-files:*)","Bash(git rev-parse:*)","Bash(git add:*)","Bash(npm run:*)","Bash(npx tsc:*)","Bash(npx vitest:*)","Bash(node --test:*)","Bash(node --max-old-space-size=4096:*)","Bash(orca-ide:*)","Bash(awk:*)","Bash(sed -n:*)","Bash(grep:*)","Bash(rg:*)","Bash(cat:*)","Bash(head:*)","Bash(tail:*)","Bash(ls:*)","Bash(wc:*)","Bash(find:*)","Bash(diff:*)","Bash(jq:*)","Bash(sort:*)","Bash(uniq:*)","Bash(cut:*)","Bash(tr:*)","Bash(xargs:*)","Bash(mkdir:*)","Bash(cp:*)","Bash(mv:*)","Bash(printf:*)","Bash(echo:*)","Bash(test:*)","Bash(aws dynamodb get-item:*)","Bash(aws dynamodb query:*)","Bash(aws dynamodb scan:*)","Bash(aws dynamodb describe-table:*)","Bash(aws sts get-caller-identity:*)"]'
jq --arg ttl "$(jq -r '.cacheTtl // empty' "$PROJECT/.claude/commandeck.json" 2>/dev/null)" --arg w "$WINDOW" --arg notify "\"$HOOKS/lib/run-hook.sh\" \"$HOOKS/claude-worker-notify.sh\"" --arg ex "$EXCLUDE" --arg h "$HOOKS" --argjson deny "$DENY" --argjson allow "$ALLOW" --argjson poff "$PLUGINS_OFF" --argjson mdeny "$MCP_DENY" '
  # A hook this script registered from another plugin path, or by its own path with no launcher (before an update).
  def stale: (.command // "") | test("/hooks/(claude-worker-notify|builder-event-log|builder-search-guard)[.]sh\"$") and (startswith("\"" + $h + "/lib/run-hook.sh\" ") | not);
  .env = ((.env // {}) + {CLAUDE_CODE_AUTO_COMPACT_WINDOW: $w})
  | (if $ttl == "5m" then .env.CLAUDE_CODE_PROMPT_CACHE_TTL = "5m" else . end)
  | .hooks = ((.hooks // {}) | map_values(map(select(((.hooks // []) | length) > 0 and all(.hooks[]; stale) | not))))
  | .enabledPlugins = ((.enabledPlugins // {}) + {"memoir@memoir": false} + $poff | del(.["typescript-lsp@claude-plugins-official"]))
  | .disableClaudeAiConnectors = true
  | .deniedMcpServers = ((.deniedMcpServers // []) + $mdeny | unique)
  | .permissions = ((.permissions // {}) + {deny: ((.permissions.deny // []) - ["Workflow"] + $deny | unique), allow: ((.permissions.allow // []) + $allow | unique), defaultMode: "auto"})
  | .claudeMdExcludes = ((.claudeMdExcludes // []) + [$ex] | unique)
  | .hooks = ((.hooks // {}) | .Stop = (((.Stop // []) + [{hooks: [{type: "command", command: $notify}]}]) | unique))' "$F" > "$tmp"
mv "$tmp" "$F"
# The Stop hook (ruling 2026-09-07) sends an Orca worker_done when any Claude
# pane in the worktree finishes a turn, the twin of the Codex `notify` hook, so
# main's blocking wait wakes at once instead of at its timeout.
echo "$WT: node_modules linked where main has them, compact window $WINDOW, memoir off, $(echo "$DENY" | jq length) unused tools denied, auto mode with $(echo "$ALLOW" | jq length) allowed command patterns, Stop notify hook, orchestration.md excluded, business plugins + claude.ai connectors + chrome/CloudWatch off"

# 10. Lean pane (owner, 2026-10-18; probed with `claude -p` that each override hides its name): Stripe and the three
#     browser skills off unless --keep says otherwise, auto memory off (a file key, so it holds on every relaunch
#     path), and the ponytail plugin swapped for its summary where the owner has the plugin on and setup said yes.
#     A browser skill or Stripe leaf the owner set in this file is left as it is, kept or not; the ones the run writes
#     are named in COMMANDECK_DEFAULT_CUTS, so a keep word takes out only those.
#     The owner's lists add to the cuts; a plugin another step writes (the business plugins, memoir) is never stored
#     as the owner's, so a list that drops it does not take that step's leaf out, and a keep word that names it (or
#     ponytail) deletes the run's own leaf and gives back the one the owner set in this file (OWNFIX, step 8), so the
#     owner's own setting holds. A listed name the owner set in this file is left
#     as it is; a stored leaf the owner changed by hand is no longer this run's to delete. Ponytail too: its off is
#     this run's only beside the summary hook, so an owner's own leaf is neither deleted, claimed nor swapped.
CUTS=$(jq -c '{s: [.workerSkillsOff[]? | strings], p: [.workerPluginsOff[]? | strings], k: (.keeps | if type == "object" then . else {} end)}' "$PROJECT/.claude/commandeck.json" 2>/dev/null) || CUTS='{"s":[],"p":[],"k":{}}'
PONY=0
[ "$(jq -r '.ponytail // false' "$PROJECT/.claude/commandeck.json" 2>/dev/null)" = true ] \
  && jq -e '.enabledPlugins["ponytail@ponytail"] == true' "$HOME/.claude/settings.json" >/dev/null 2>&1 && PONY=1
jq --arg keep "$KEEP" --argjson pony "$PONY" --arg sum "cat \"$SUMMARY\"" --argjson cuts "$CUTS" --argjson fixed "$FIXED" --argjson ownfix "$OWNFIX" "$DISOWN"'
  def keeps($w): ($keep | split(",") | index($w)) != null;
  ["anthropic-skills:computer-use", "anthropic-skills:built-in-browser", "anthropic-skills:chrome-browser"] as $m1
  | "stripe@claude-plugins-official" as $stripe
  | [$keep | split(",")[] as $w | $cuts.k[$w] | objects] as $kw
  | [$kw[] | .skills[]? | strings] as $ks
  | ([$kw[] | .plugins[]? | strings] + (if keeps("billing") then [$stripe] else [] end)) as $kp
  | any(.hooks.SessionStart[]?.hooks[]?; (.command // "") | test("/templates/ponytail/SUMMARY[.]md\"$")) as $sumhook
  | disown
  | if $sumhook and .enabledPlugins["ponytail@ponytail"] == false then del(.enabledPlugins["ponytail@ponytail"]) else . end
  | reduce ($kp[] | select(IN($fixed[]))) as $n (.; if $ownfix | has($n) then .enabledPlugins[$n] = $ownfix[$n] else del(.enabledPlugins[$n]) end)
  | (.skillOverrides // {}) as $so | (.enabledPlugins // {}) as $ep
  | if keeps("all") then [] else $m1 - $ks + [$stripe] - $kp | map(select(. as $n | $so + $ep | has($n) | not)) end as $w1
  | .env.COMMANDECK_DEFAULT_CUTS = ($fixed - $kp - ($ownfix | keys) + $w1 | join(","))
  | ([$ownfix | to_entries[] | select(.value == true).key] - $kp) as $on | (if $on != [] then .env.COMMANDECK_OWNER_ON = ($on | join(",")) else . end)
  | ($cuts.s - $m1 - $ks | unique | map(select(. as $n | $so | has($n) | not))) as $os
  | ($cuts.p - $fixed - [$stripe] - $kp | unique | map(select(. as $n | $ep | has($n) | not))) as $op
  | if keeps("all") then .env.COMMANDECK_SKILL_KEEP = $keep
    else
      .autoMemoryEnabled = false
      | (if $keep != "" then .env.COMMANDECK_SKILL_KEEP = $keep else . end)
      | .enabledPlugins = ((.enabledPlugins // {}) + ($w1 - $m1 + $op | map({(.): false}) | add // {}))
      | .skillOverrides = ((.skillOverrides // {}) + ($w1 - [$stripe] + $os | map({(.): "off"}) | add // {}))
      | (if $os + $op != [] then .env.COMMANDECK_OWNER_CUTS = ($os + $op | join(",")) else . end)
      | (if $pony == 1 and ($kp | index("ponytail@ponytail") | not) and ($ep | has("ponytail@ponytail") | not) then .enabledPlugins["ponytail@ponytail"] = false | .hooks.SessionStart = ((.hooks.SessionStart // []) + [{hooks: [{type: "command", command: $sum}]}]) else . end)
    end' "$F" > "$tmp"
mv "$tmp" "$F"
echo "$WT: lean pane: $(if [ "$KEEP" = all ]; then echo "kept whole (--keep all)"; else echo "browser skills off, auto memory off, Stripe $(jq -e '.enabledPlugins["stripe@claude-plugins-official"] == false' "$F" >/dev/null && echo off || echo kept), ponytail $(jq -e '[.hooks.SessionStart[]?.hooks[]?.command | select(test("/templates/ponytail/SUMMARY[.]md\"$"))] != []' "$F" >/dev/null && echo summary || echo untouched), $(jq -r '.env.COMMANDECK_OWNER_CUTS // "" | split(",") | length' "$F") of your listed skills and plugins off"; fi)"

# 9. --builder: a Builder runs its own Explore subagents (Agent allowed)
#    and the Codex companion (node), carries no orchestration rules, and logs
#    its events through hooks registered here only, so no other session pays
#    for them. agent-startup-context.sh and agent-model-guard.sh read the env.
#    Its prompt cache follows the setup answer like every worker's (owner, 2026-10-18,
#    replacing the 1h pin of 2026-10-11): 5m above, nothing on Leave as is.
#    Proof on a launched Builder: builder-cache-check.sh.
if [ "$BUILDER" = 1 ]; then
  RULES="$(cd "$WT" && pwd)/.claude/rules"
  BX=$(jq -cn --arg r "$RULES" --arg n "$PP_BUILDER_RULES_OFF" '$n | split(" ") | map("\($r)/\(.).md")')
  jq --argjson bx "$BX" --arg cmd "\"$HOOKS/lib/run-hook.sh\" \"$HOOKS/builder-event-log.sh\"" \
    --arg gcmd "\"$HOOKS/lib/run-hook.sh\" \"$HOOKS/builder-search-guard.sh\"" --arg s "$PP_SCRIPTS_Q" '
    def reg($m): [{hooks: [{type: "command", command: $cmd}]} + (if $m then {matcher: $m} else {} end)];
    .env.COMMANDECK_BUILDER = "1"
    | .permissions.deny -= ["Agent"]
    | .permissions.allow = ((.permissions.allow | map(select(test("^Bash\\(bash .*/builder-(codex|claude)-pass[.]sh:") | not))) + ["Bash(node:*)", "Bash(bash \($s)/builder-codex-pass.sh:*)", "Bash(bash \($s)/builder-claude-pass.sh:*)"] | unique)
    | .claudeMdExcludes = (.claudeMdExcludes + $bx | unique)
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + reg(null) | unique)
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + reg(null) | unique)
    | .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) + reg(null) | unique)
    | .hooks.PostToolBatch = ((.hooks.PostToolBatch // []) + reg(null) | unique)
    | .hooks.PermissionDenied = ((.hooks.PermissionDenied // []) + reg(null) | unique)
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{matcher: "Grep|Glob|Bash|Edit|Write|MultiEdit|Agent|Task|mcp__serena__search_for_pattern|mcp__codebase-memory__search_code|mcp__codebase-memory__search_graph", hooks: [{type: "command", command: $gcmd}]}] | unique)
    | ([{matcher: "Grep|Glob|Bash|mcp__serena__search_for_pattern|mcp__codebase-memory__search_code|mcp__codebase-memory__search_graph", hooks: [{type: "command", command: $gcmd}]}]) as $counted
    | .hooks.PostToolUse = (.hooks.PostToolUse + $counted | unique)
    | .hooks.PostToolUseFailure = (.hooks.PostToolUseFailure + $counted | unique)
    | .hooks.SubagentStart = ((.hooks.SubagentStart // []) + reg(null) | unique)
    | .hooks.SubagentStop = ((.hooks.SubagentStop // []) + reg(null) | unique)' "$F" > "$tmp"
  mv "$tmp" "$F"
  echo "$WT: Builder profile: COMMANDECK_BUILDER=1, Agent allowed, node allowed, $(echo "$BX" | jq length) orchestration rules excluded, event-log hooks on"
fi
[ "$PRINT" = 0 ] || { cat "$F" >&3; rm -f "$F"; }
