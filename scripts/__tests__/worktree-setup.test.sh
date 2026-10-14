#!/usr/bin/env bash
# worktree-setup.sh keeps main's rulebook out of worker sessions:
# orchestration.md is path-gated on .claude/briefs/**, every worker reads its
# brief there, and the file costs every worker turn without ever being used.
# The exclusion must land in the worktree's settings.local.json, exactly once
# however often setup runs, and never in the main checkout.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo"
git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
git -C "$TMP/repo" worktree add -q "$TMP/wt" -b wtb >/dev/null 2>&1
mkdir -p "$TMP/wt/web" "$TMP/wt/infra"
F="$TMP/wt/.claude/settings.local.json"
WANT="$TMP/wt/.claude/rules/orchestration.md"

bash "$REAL/scripts/worktree-setup.sh" "$TMP/wt" >/dev/null
check "the worktree excludes its own orchestration.md" 1 \
  "$(jq --arg w "$WANT" '[.claudeMdExcludes[]? | select(. == $w)] | length' "$F")"
bash "$REAL/scripts/worktree-setup.sh" "$TMP/wt" >/dev/null
check "a second run adds nothing" 1 "$(jq '.claudeMdExcludes | length' "$F")"
# Workers never use the business plugins or these servers, and their tool lists
# rode every worker turn. The code servers must stay.
check "the business plugins are off" 6 \
  "$(jq '[.enabledPlugins | to_entries[] | select((.key | test("^(customer-support|design|operations|product-management|productivity|cowork-plugin-management)@synced$")) and .value == false)] | length' "$F")"
check "claude.ai connectors (Claude Docs) are off" true "$(jq '.disableClaudeAiConnectors' "$F")"
check "chrome and both CloudWatch servers are denied" 3 \
  "$(jq '[.deniedMcpServers[]?.serverName | select(. == "claude-in-chrome" or . == "aws-cloudwatch-dev" or . == "aws-cloudwatch-prod")] | length' "$F")"
check "serena, codebase-memory, context7 and AWS Knowledge are not denied" 0 \
  "$(jq '[.deniedMcpServers[]?.serverName | select(test("serena|codebase-memory|context7|aws-knowledge"))] | length' "$F")"
check "a second run denies nothing twice" 3 "$(jq '.deniedMcpServers | length' "$F")"
check "an ordinary worktree keeps the Stop notify hook" 1 "$(jq '.hooks.Stop | length' "$F")"

# The Chief-of-Staff relay pane never reads code: the code servers and
# plugins are off, and it gets none of the worker mechanics -- the Stop notify
# hook would wake main on every relay turn.
git -C "$TMP/repo" worktree add -q "$TMP/Chief-of-Staff" -b cos >/dev/null 2>&1
CF="$TMP/Chief-of-Staff/.claude/settings.local.json"
bash "$REAL/scripts/worktree-setup.sh" "$TMP/Chief-of-Staff" >/dev/null
check "Chief-of-Staff denies serena and codebase-memory" 2 \
  "$(jq '[.deniedMcpServers[]?.serverName | select(. == "serena" or . == "codebase-memory")] | length' "$CF")"
check "Chief-of-Staff turns ponytail off" false "$(jq '.enabledPlugins["ponytail@ponytail"]' "$CF")"
check "Chief-of-Staff keeps the business plugins off" 6 \
  "$(jq '[.enabledPlugins | to_entries[] | select((.key | endswith("@synced")) and .value == false)] | length' "$CF")"
check "Chief-of-Staff turns claude.ai connectors off" true "$(jq '.disableClaudeAiConnectors' "$CF")"
check "Chief-of-Staff has no Stop hook" null "$(jq '.hooks.Stop' "$CF")"
check "Chief-of-Staff gets no worker tool denies" null "$(jq '.permissions.deny' "$CF")"
check "Chief-of-Staff gets no node_modules symlink" no "$([ -e "$TMP/Chief-of-Staff/node_modules" ] && echo yes || echo no)"
# The relay pane reaches main through exactly these eight orca commands
# (owner ruling 2026-10-09), and runs its own watcher scripts and the
# decision script, each by the plugin's full path (owner ruling 2026-10-12);
# a recreated worktree must keep them, and nothing broader.
COS_ALLOW='["Bash(orca-ide orchestration check:*)","Bash(orca-ide orchestration inbox:*)","Bash(orca-ide orchestration reply:*)","Bash(orca-ide orchestration send:*)","Bash(orca-ide terminal list:*)","Bash(orca-ide terminal read:*)","Bash(orca-ide terminal send:*)","Bash(orca-ide terminal wait:*)"]'
COS_ALLOW=$(jq -c --arg s "$REAL/scripts" '. + (["cos-watch-alerts", "cos-watch-decisions", "cos-watch-inbox", "cos-watch-limit", "decision"] | map("Bash(bash \($s)/\(.).sh:*)")) | sort' <<<"$COS_ALLOW")
check "Chief-of-Staff allows exactly the eight orca patterns, its watcher scripts and the decision script" true "$(jq --argjson w "$COS_ALLOW" '(.permissions.allow | sort) == $w' "$CF")"
check "Chief-of-Staff gets no blanket allow of bash or of the plugin's scripts" 0 "$(jq '[.permissions.allow[]? | select(test("^Bash\\(bash:|/scripts/\\*|/scripts:|/scripts/:"))] | length' "$CF")"
check "Chief-of-Staff gets no blanket orca allow" 0 "$(jq '[.permissions.allow[]? | select(. == "Bash(orca-ide:*)")] | length' "$CF")"
check "Chief-of-Staff gets no permission mode" null "$(jq '.permissions.defaultMode' "$CF")"
bash "$REAL/scripts/worktree-setup.sh" "$TMP/Chief-of-Staff" >/dev/null
check "a second Chief-of-Staff run denies nothing twice" 8 "$(jq '.deniedMcpServers | length' "$CF")"
check "a second Chief-of-Staff run allows nothing twice" 13 "$(jq '.permissions.allow | length' "$CF")"
check "an ordinary worktree gets none of the Chief-of-Staff patterns" 0 \
  "$(jq --argjson w "$COS_ALLOW" '[.permissions.allow[] | select(IN($w[]))] | length' "$F")"

# A Builder runs Explore subagents, so Agent must not be denied; it
# runs the Codex companion with node; main's rulebook and the worker rules
# stay out of its context; and its event-log hooks live only in its own
# settings, so no other session pays for them.
git -C "$TMP/repo" worktree add -q "$TMP/bwt" -b bwt >/dev/null 2>&1
mkdir -p "$TMP/bwt/web" "$TMP/bwt/infra"
BF="$TMP/bwt/.claude/settings.local.json"
bash "$REAL/scripts/worktree-setup.sh" "$TMP/bwt" --builder >/dev/null
bash "$REAL/scripts/worktree-setup.sh" "$TMP/bwt" --builder >/dev/null
check "Builder: COMMANDECK_BUILDER is set" '"1"' "$(jq '.env.COMMANDECK_BUILDER' "$BF")"
check "Builder: the compact window is 300000" '"300000"' "$(jq '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW' "$BF")"
# A project set to standard-context models has a 200K window: a 300000 or
# 450000 compaction window would never fire there, so it becomes 180000.
mkdir -p "$TMP/repo/.claude"; echo '{"standardContext": true}' > "$TMP/repo/.claude/commandeck.json"
bash "$REAL/scripts/worktree-setup.sh" "$TMP/bwt" --builder >/dev/null
bash "$REAL/scripts/worktree-setup.sh" "$TMP/wt" >/dev/null
check "standard context: Builder and worker compact at 180000" '"180000" "180000"' \
  "$(jq '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW' "$BF" "$F" | paste -sd' ' -)"
rm "$TMP/repo/.claude/commandeck.json"
bash "$REAL/scripts/worktree-setup.sh" "$TMP/bwt" --builder >/dev/null
bash "$REAL/scripts/worktree-setup.sh" "$TMP/wt" >/dev/null
check "Builder: Agent is not denied" 0 "$(jq '[.permissions.deny[] | select(. == "Agent")] | length' "$BF")"
# The owner 2026-10-13: a Builder or a worker may run dynamic workflows, so no profile denies the tool.
check "no profile denies Workflow" "0 0" "$(jq '[.permissions.deny[] | select(. == "Workflow")] | length' "$BF" "$F" | paste -sd' ' -)"
# A worktree set up before that still has the denial in its settings, and a second run merges into them.
for f in "$BF" "$F"; do jq '.permissions.deny += ["Workflow"]' "$f" > "$f.t" && mv "$f.t" "$f"; done
bash "$REAL/scripts/worktree-setup.sh" "$TMP/bwt" --builder >/dev/null
bash "$REAL/scripts/worktree-setup.sh" "$TMP/wt" >/dev/null
check "a denial of Workflow left by an earlier set-up is taken out" "0 0" "$(jq '[.permissions.deny[] | select(. == "Workflow")] | length' "$BF" "$F" | paste -sd' ' -)"
check "the other worker denies stay" "1 1 1 1" "$(jq '.permissions.deny | (map(select(. == "Artifact")) | length), (map(select(. == "NotebookEdit")) | length)' "$BF" "$F" | paste -sd' ' -)"
check "Builder: node is allowed" 1 "$(jq '[.permissions.allow[] | select(. == "Bash(node:*)")] | length' "$BF")"
# Every Codex pass goes through this script; a classifier prompt would stall an unattended Builder.
# An installed plugin is not in the project: the rule, like the brief's command,
# names the pass script where the plugin is, for either reviewer.
check "Builder: the pass script is allowed, by the plugin's path" 2 "$(jq --arg s "$REAL/scripts" '[.permissions.allow[] | select(. == "Bash(bash \($s)/builder-codex-pass.sh:*)" or . == "Bash(bash \($s)/builder-claude-pass.sh:*)")] | length' "$BF")"
check "Builder: its hooks are the plugin's files, which exist" "2 yes" \
  "$(jq -r '[.hooks.PreToolUse[].hooks[].command] | unique | length' "$BF") $(jq -r '.hooks.PreToolUse[].hooks[].command' "$BF" | while IFS= read -r c; do eval "set -- $c"; for f; do [ -x "$f" ] || echo no; done; done | grep -q no && echo no || echo yes)"
check "Builder: no hook is looked for in the project" 0 "$(grep -c 'CLAUDE_PROJECT_DIR' "$BF")"
check "Builder: the five orchestration rules are excluded, once each" \
  "adversarial-reviews.md agents.md orchestration.md planning.md worktree-sessions.md" \
  "$(jq -r --arg r "$TMP/bwt/.claude/rules/" '[.claudeMdExcludes[] | select(startswith($r)) | ltrimstr($r)] | sort | join(" ")' "$BF")"
for ev in PreToolUse PostToolUse PostToolUseFailure SubagentStart SubagentStop; do
  check "Builder: the event log is registered once on $ev" 1 \
    "$(jq --arg e "$ev" '[.hooks[$e][]?.hooks[]?.command | select(test("builder-event-log.sh"))] | length' "$BF")"
done
# The log times every tool call: a start needs its end, so no registration carries a matcher.
check "Builder: the event log has no matcher on any of its five events" "null null null null null" \
  "$(jq -r '[.hooks["PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStart", "SubagentStop"][] | select(.hooks[0].command | test("builder-event-log.sh")) | .matcher | tojson] | join(" ")' "$BF")"
# seat.sh launch reruns setup without the flag; that must not deny Agent again.
bash "$REAL/scripts/worktree-setup.sh" "$TMP/bwt" >/dev/null
check "Builder: a plain rerun keeps Agent allowed" 0 "$(jq '[.permissions.deny[] | select(. == "Agent")] | length' "$BF")"
check "Builder: a plain rerun keeps the event log registered once" 1 \
  "$(jq '[.hooks.SubagentStop[]?.hooks[]?.command | select(test("builder-event-log.sh"))] | length' "$BF")"
# The search guard counts a Builder's searches; the matcher keeps it off Read and serena symbol reads.
check "Builder: the search guard is registered once on PreToolUse" 1 \
  "$(jq '[.hooks.PreToolUse[]?.hooks[]?.command | select(test("builder-search-guard.sh"))] | length' "$BF")"
check "Builder: the search guard matcher names the searches and the resets, no Read" \
  "Grep|Glob|Bash|Edit|Write|MultiEdit|Agent|Task|mcp__serena__search_for_pattern|mcp__codebase-memory__search_code|mcp__codebase-memory__search_graph" \
  "$(jq -r '.hooks.PreToolUse[] | select(.hooks[0].command | test("builder-search-guard")) | .matcher' "$BF")"
check "an ordinary worktree gets no search guard" 0 "$(jq '[.. | strings | select(test("builder-search-guard"))] | length' "$F")"
check "an ordinary worktree is no Builder" null "$(jq '.env.COMMANDECK_BUILDER' "$F")"
check "an ordinary worktree still denies Agent" 1 "$(jq '[.permissions.deny[] | select(. == "Agent")] | length' "$F")"
check "an ordinary worktree gets no event-log hook" 0 "$(jq '[.. | strings | select(test("builder-event-log"))] | length' "$F")"

# A repo with no node_modules and no web/ or infra/ directory (this plugin's
# own repo): setup used to die on the first link, so no Builder could start
# there, and where it did not die it left a link to nothing.
git -C "$TMP/repo" worktree add -q "$TMP/bare" -b bare >/dev/null 2>&1
NF="$TMP/bare/.claude/settings.local.json"
COMMANDECK_MAIN="$TMP/repo" bash "$REAL/scripts/worktree-setup.sh" "$TMP/bare" --builder >/dev/null 2>&1
check "no node_modules in main: Builder setup exits 0" 0 "$?"
check "no node_modules in main: no link is left, dangling or not" 0 \
  "$(find "$TMP/bare" -name node_modules | wc -l | tr -d ' ')"
check "no node_modules in main: the Builder env and the 1h cache are written" '"1" "1h"' \
  "$(jq -c '.env.COMMANDECK_BUILDER, .env.CLAUDE_CODE_PROMPT_CACHE_TTL' "$NF" 2>/dev/null | paste -sd' ' -)"
check "no node_modules in main: both Builder hooks are registered" "1 1" \
  "$(jq -r '[([.hooks.PreToolUse[]?.hooks[]?.command | select(test("builder-event-log.sh"))] | length), ([.hooks.PreToolUse[]?.hooks[]?.command | select(test("builder-search-guard.sh"))] | length)] | join(" ")' "$NF" 2>/dev/null)"
# Where main has one, the worktree still shares it.
mkdir -p "$TMP/repo/node_modules"
git -C "$TMP/repo" worktree add -q "$TMP/linked" -b linked >/dev/null 2>&1
COMMANDECK_MAIN="$TMP/repo" bash "$REAL/scripts/worktree-setup.sh" "$TMP/linked" >/dev/null 2>&1
check "node_modules in main: the worktree links to it" yes "$([ "$TMP/linked/node_modules" -ef "$TMP/repo/node_modules" ] && echo yes || echo no)"
check "node_modules in main: an absent web/ gets no link" no "$([ -e "$TMP/linked/web" ] && echo yes || echo no)"

# Claude Code runs a hook command through a shell: a path with a space in it
# must stay one word, or the worker's finish never reaches main. And the hook
# is the PLUGIN's: the project carries none, so a command that looked in the
# project would find nothing and the worker's finish would never be sent.
git init -q "$TMP/my repo"; git -C "$TMP/my repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
git -C "$TMP/my repo" worktree add -q "$TMP/spaced" -b spaced >/dev/null 2>&1
mkdir "$TMP/my plugin"; cp -R "$REAL/scripts" "$REAL/hooks" "$REAL/config" "$TMP/my plugin/"
printf '#!/bin/sh\ntouch "%s/notified"\n' "$TMP" > "$TMP/my plugin/hooks/claude-worker-notify.sh"
COMMANDECK_MAIN="$TMP/my repo" bash "$TMP/my plugin/scripts/worktree-setup.sh" "$TMP/spaced" >/dev/null 2>&1
sh -c "$(jq -r '.hooks.Stop[0].hooks[0].command' "$TMP/spaced/.claude/settings.local.json")" >/dev/null 2>&1
check "the Stop hook is the plugin's, and runs from a path with a space" yes "$([ -e "$TMP/notified" ] && echo yes || echo no)"

check "main's checkout is refused" 1 \
  "$(bash "$REAL/scripts/worktree-setup.sh" "$TMP/repo" >/dev/null 2>&1; echo $?)"

# A worktree whose settings could not be written is not set up: a launch that
# goes on anyway runs a session without its denies and hooks.
git -C "$TMP/repo" worktree add -q "$TMP/bad" -b badb >/dev/null 2>&1
mkdir -p "$TMP/bad/.claude"; echo '{not json' > "$TMP/bad/.claude/settings.local.json"
check "a settings file that cannot be updated fails the setup" no \
  "$(bash "$REAL/scripts/worktree-setup.sh" "$TMP/bad" >/dev/null 2>&1 && echo yes || echo no)"

# The pass script commits with `git add -A`, and the merge refuses untracked
# code. The session files setup and the event log leave in a worktree must be
# ignored in ANY project, not only where the owner's own gitignore covers them.
touch "$TMP/wt/.claude/builder-events.jsonl"
check "the worktree's settings and event log are ignored without any user gitignore" "" \
  "$(GIT_CONFIG_GLOBAL=/dev/null git -C "$TMP/wt" status --porcelain --untracked-files=all -- .claude/settings.local.json .claude/builder-events.jsonl)"
check "a second run adds no second exclude line" 1 "$(grep -cx '.claude/settings.local.json' "$TMP/repo/.git/info/exclude")"

# The plugin was updated to a new path and the worktree set up again: the
# hooks registered from the old path go, or every Builder event is logged
# twice and the old guard keeps deciding. A hook of the owner's stays.
BF=$TMP/bwt/.claude/settings.local.json
jq '.hooks.Stop += [{hooks: [{type: "command", command: "\"/old/plugin/hooks/claude-worker-notify.sh\""}]}, {hooks: [{type: "command", command: "/mine/hook.sh"}]}]
  | .hooks.PreToolUse += [{hooks: [{type: "command", command: "\"/old/plugin/hooks/builder-event-log.sh\""}]}, {matcher: "Grep", hooks: [{type: "command", command: "\"/old/plugin/hooks/builder-search-guard.sh\""}]}]
  | .permissions.allow += ["Bash(bash /old/plugin/scripts/builder-codex-pass.sh:*)"]' "$BF" > "$TMP/bf.json" && cp "$TMP/bf.json" "$BF"
bash "$REAL/scripts/worktree-setup.sh" "$TMP/bwt" --builder >/dev/null
check "a rerun from another plugin path leaves nothing of the old one" 0 "$(grep -c '/old/plugin/' "$BF")"
# The search guard is on three events: before a search, after one, after a failed one.
check "each of the plugin's hooks is there once per event, and the owner's is kept" "1 3 1 1" \
  "$(for n in claude-worker-notify builder-search-guard; do grep -c "/hooks/$n.sh" "$BF"; done | paste -sd' ' -) $(jq '[.hooks.PreToolUse[].hooks[] | select(.command | test("builder-event-log"))] | length' "$BF") $(grep -c '/mine/hook.sh' "$BF")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
