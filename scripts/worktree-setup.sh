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
set -euo pipefail
WT=${1:?usage: worktree-setup.sh <worktree-path> [--builder]}
BUILDER=0; [ "${2:-}" = --builder ] && BUILDER=1
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
MAIN=$PP_MAIN
# The plugin's hooks, by full path: an installed plugin is not in the project,
# so neither $MAIN/hooks nor $CLAUDE_PROJECT_DIR/hooks is where they are.
HOOKS=$(cd "$PP_SCRIPTS/../hooks" && pwd)
[ -d "$WT" ] || { echo "no such worktree: $WT" >&2; exit 1; }
[ "$(cd "$WT" && git rev-parse --git-dir)" != "$(cd "$WT" && git rev-parse --git-common-dir)" ] \
  || { echo "refusing: $WT is the main checkout" >&2; exit 1; }

mkdir -p "$WT/.claude"
F="$WT/.claude/settings.local.json"
[ -f "$F" ] || echo '{}' > "$F"
# The session's own files never ride a unit commit and never read as untracked
# code at the merge, whatever the project's gitignore says: the repo's shared
# exclude file names them.
EXCLUDE=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir)/info/exclude
mkdir -p "${EXCLUDE%/*}"
for p in .claude/settings.local.json .claude/builder-events.jsonl; do
  grep -qxF "$p" "$EXCLUDE" 2>/dev/null || echo "$p" >> "$EXCLUDE"
done
# A Builder stays a Builder: seat.sh launch reruns this script without the flag.
[ "$(jq -r '.env.COMMANDECK_BUILDER // empty' "$F")" = 1 ] && BUILDER=1
tmp=$(mktemp)
PLUGINS_OFF='{"customer-support@synced":false,"design@synced":false,"operations@synced":false,"product-management@synced":false,"productivity@synced":false,"cowork-plugin-management@synced":false}'

# The Chief-of-Staff relay pane never reads code, so it gets only the
# slimming keys: code servers, code plugins and connectors off. None of the
# worker mechanics below -- its Stop notify hook would wake main every relay turn.
# Same seat test as agent-startup-context.sh: the worktree's directory name.
if [ "$(basename "$(cd "$WT" && git rev-parse --show-toplevel)")" = Chief-of-Staff ]; then
  COS_MCP_DENY='[{"serverName":"serena"},{"serverName":"codebase-memory"},{"serverName":"context7"},{"serverName":"aws-knowledge"},{"serverName":"aws-cloudwatch-dev"},{"serverName":"aws-cloudwatch-prod"},{"serverName":"claude-in-chrome"},{"serverName":"alphaxiv"}]'
  COS_PLUGINS_OFF='{"ponytail@ponytail":false,"typescript-lsp@claude-plugins-official":false,"skill-creator@claude-plugins-official":false,"canvas@claude-canvas":false,"mattpocock-skills@claude-plugins-official":false,"stripe@claude-plugins-official":false,"memoir@memoir":false}'
  # The orca commands the relay pane needs to reach main (owner ruling 2026-10-09); nothing broader.
  COS_ALLOW='["Bash(orca-ide terminal list:*)","Bash(orca-ide terminal send:*)","Bash(orca-ide terminal read:*)","Bash(orca-ide terminal wait:*)","Bash(orca-ide orchestration send:*)","Bash(orca-ide orchestration check:*)","Bash(orca-ide orchestration reply:*)","Bash(orca-ide orchestration inbox:*)"]'
  # Its own watcher scripts and the decision script, each by the full path the
  # startup text names (owner ruling 2026-10-12); no other script.
  COS_ALLOW=$(jq -c --arg s "$PP_SCRIPTS_Q" '. + (["cos-watch-alerts", "cos-watch-decisions", "cos-watch-inbox", "cos-watch-limit", "decision"] | map("Bash(bash \($s)/\(.).sh:*)"))' <<<"$COS_ALLOW")
  jq --argjson poff "$PLUGINS_OFF" --argjson cpoff "$COS_PLUGINS_OFF" --argjson mdeny "$COS_MCP_DENY" --argjson callow "$COS_ALLOW" '
    .enabledPlugins = ((.enabledPlugins // {}) + $cpoff + $poff)
    | .disableClaudeAiConnectors = true
    | .deniedMcpServers = ((.deniedMcpServers // []) + $mdeny | unique)
    | .permissions.allow = ((.permissions.allow // []) + $callow | unique)' "$F" > "$tmp"
  mv "$tmp" "$F"
  echo "$WT: Chief-of-Staff relay pane: $(echo "$COS_MCP_DENY" | jq length) MCP servers denied, code + business plugins and claude.ai connectors off, 8 orca command patterns and 5 of the plugin's scripts allowed; no worker settings"
  exit 0
fi

pp_link_node_modules "$MAIN" "$WT"

WINDOW=${COMMANDECK_WORKER_COMPACT_WINDOW:-450000}
[ "$BUILDER" = 1 ] && WINDOW=300000
# Standard-context models hold 200K: a larger window would never compact.
# The setting is the worktree's own project's, read from its primary checkout.
PROJECT=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); PROJECT=${PROJECT%/.git}
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
# 5. The typescript-lsp plugin is off in worktrees: every Claude pane already
#    runs Serena's TypeScript server, and the plugin starts a second one for
#    the same tree. Measured 2026-09-04: 21 tsserver processes, 13.9 GB of a
#    31.5 GB cage, two per pane at 1 to 3 GB each. Workers navigate through
#    Serena (`AGENT_STARTUP.md` 1b) and never call the plugin's LSP tool.
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
MCP_DENY='[{"serverName":"claude-in-chrome"},{"serverName":"aws-cloudwatch-dev"},{"serverName":"aws-cloudwatch-prod"}]'
ALLOW='["Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git show:*)","Bash(git ls-files:*)","Bash(git rev-parse:*)","Bash(git add:*)","Bash(npm run:*)","Bash(npx tsc:*)","Bash(npx vitest:*)","Bash(node --test:*)","Bash(node --max-old-space-size=4096:*)","Bash(orca-ide:*)","Bash(awk:*)","Bash(sed -n:*)","Bash(grep:*)","Bash(rg:*)","Bash(cat:*)","Bash(head:*)","Bash(tail:*)","Bash(ls:*)","Bash(wc:*)","Bash(find:*)","Bash(diff:*)","Bash(jq:*)","Bash(sort:*)","Bash(uniq:*)","Bash(cut:*)","Bash(tr:*)","Bash(xargs:*)","Bash(mkdir:*)","Bash(cp:*)","Bash(mv:*)","Bash(printf:*)","Bash(echo:*)","Bash(test:*)","Bash(aws dynamodb get-item:*)","Bash(aws dynamodb query:*)","Bash(aws dynamodb scan:*)","Bash(aws dynamodb describe-table:*)","Bash(aws sts get-caller-identity:*)"]'
jq --arg w "$WINDOW" --arg notify "\"$HOOKS/claude-worker-notify.sh\"" --arg ex "$EXCLUDE" --arg h "$HOOKS" --argjson deny "$DENY" --argjson allow "$ALLOW" --argjson poff "$PLUGINS_OFF" --argjson mdeny "$MCP_DENY" '
  # A hook this script registered from another plugin path (before an update).
  def stale: (.command // "") | test("/hooks/(claude-worker-notify|builder-event-log|builder-search-guard)[.]sh\"$") and (startswith("\"" + $h + "/") | not);
  .env = ((.env // {}) + {CLAUDE_CODE_AUTO_COMPACT_WINDOW: $w})
  | .hooks = ((.hooks // {}) | map_values(map(select(((.hooks // []) | length) > 0 and all(.hooks[]; stale) | not))))
  | .enabledPlugins = ((.enabledPlugins // {}) + {"memoir@memoir": false, "typescript-lsp@claude-plugins-official": false} + $poff)
  | .disableClaudeAiConnectors = true
  | .deniedMcpServers = ((.deniedMcpServers // []) + $mdeny | unique)
  | .permissions = ((.permissions // {}) + {deny: ((.permissions.deny // []) - ["Workflow"] + $deny | unique), allow: ((.permissions.allow // []) + $allow | unique), defaultMode: "auto"})
  | .claudeMdExcludes = ((.claudeMdExcludes // []) + [$ex] | unique)
  | .hooks = ((.hooks // {}) | .Stop = (((.Stop // []) + [{hooks: [{type: "command", command: $notify}]}]) | unique))' "$F" > "$tmp"
mv "$tmp" "$F"
# The Stop hook (ruling 2026-09-07) sends an Orca worker_done when any Claude
# pane in the worktree finishes a turn, the twin of the Codex `notify` hook, so
# main's blocking wait wakes at once instead of at its timeout.
echo "$WT: node_modules linked where main has them, compact window $WINDOW, memoir off, typescript-lsp plugin off, $(echo "$DENY" | jq length) unused tools denied, auto mode with $(echo "$ALLOW" | jq length) allowed command patterns, Stop notify hook, orchestration.md excluded, business plugins + claude.ai connectors + chrome/CloudWatch off"

# 9. --builder: a Builder runs its own Explore subagents (Agent allowed)
#    and the Codex companion (node), carries no orchestration rules, and logs
#    its events through hooks registered here only, so no other session pays
#    for them. agent-startup-context.sh and agent-model-guard.sh read the env.
#    Its main thread runs on the 1h prompt cache (owner, 2026-10-11) set here, not
#    inherited from ~/.claude/settings.json; subagents keep the global 5m.
#    Proof on a launched Builder: builder-cache-check.sh.
if [ "$BUILDER" = 1 ]; then
  RULES="$(cd "$WT" && pwd)/.claude/rules"
  BX=$(jq -cn --arg r "$RULES" '["orchestration", "agents", "planning", "adversarial-reviews", "worktree-sessions"] | map("\($r)/\(.).md")')
  jq --argjson bx "$BX" --arg cmd "\"$HOOKS/builder-event-log.sh\"" \
    --arg gcmd "\"$HOOKS/builder-search-guard.sh\"" --arg s "$PP_SCRIPTS_Q" '
    def reg($m): [{hooks: [{type: "command", command: $cmd}]} + (if $m then {matcher: $m} else {} end)];
    .env.COMMANDECK_BUILDER = "1"
    | .env.CLAUDE_CODE_PROMPT_CACHE_TTL = "1h"
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
  echo "$WT: Builder profile: COMMANDECK_BUILDER=1, 1h prompt cache, Agent allowed, node allowed, $(echo "$BX" | jq length) orchestration rules excluded, event-log hooks on"
fi
