#!/usr/bin/env bash
# worktree-setup.test.sh -- the settings profile worktree-setup.sh writes for a worktree, a relay pane's and a
# Builder's, on a hand-written commandeck.json (no setup run). What this pins: the ponytail add-on is gone (issue 365),
# so no profile carries a ponytail key or hook and a rerun takes an earlier run's out; the typescript-lsp plugin is gone,
# so no profile names it; and the summary line reads as words.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME"; unset CLAUDE_CONFIG_DIR # the owner's settings are $HOME/.claude's, not the caller's
P=$T/proj; git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
mkdir -p "$P/.claude" && echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
run() { (cd "$1" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH bash "$REAL/scripts/worktree-setup.sh" "$@" </dev/null); }
# An earlier run turned the third-party ponytail plugin and typescript-lsp off in every profile.
for w in Chief-of-Staff plain bld; do
  git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"
  echo '{"enabledPlugins":{"ponytail@ponytail":false,"typescript-lsp@claude-plugins-official":false}}' > "$T/wt/$w/.claude/settings.local.json"
done
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
run "$T/wt/plain" >"$T/wout" 2>&1
run "$T/wt/bld" --builder >/dev/null 2>&1
check "the relay pane takes an earlier run's ponytail off out" null "$(jq '.enabledPlugins["ponytail@ponytail"]' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
check "no worktree, relay or Builder profile names typescript-lsp" 0 \
  "$(cat "$T/wt"/{plain,Chief-of-Staff,bld}/.claude/settings.local.json | jq -s '[.[].enabledPlugins | keys[] | select(startswith("typescript-lsp"))] | length')"
check "the worktree summary says memoir off, then the denied tools, a space between" 1 "$(grep -c 'memoir off, [0-9]* unused tools denied' "$T/wout")"

# --- the prompt-cache answers: workers 5m, the relay 1h with its other env kept, nothing without an answer ---
tenv() { jq -c ".env.CLAUDE_CODE_PROMPT_CACHE_TTL // null" "$T/wt/$1/.claude/settings.local.json"; }
echo '{"env":{"OTHER":"x"}}' > "$T/wt/Chief-of-Staff/.claude/settings.local.json"
echo '{"version": 1, "profile": "claude", "workerCacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$P/.claude/commandeck.json"
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1; run "$T/wt/plain" >/dev/null 2>&1; run "$T/wt/bld" --builder >/dev/null 2>&1
check "the relay's 1h is written and its other env entry survives" '{"OTHER":"x","CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}' \
  "$(jq -c '.env' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
check "a worker and a Builder both get 5m (a Builder was 1h)" '"5m":"5m"' "$(tenv plain):$(tenv bld)"
echo '{"version": 1, "profile": "claude", "workerCacheTtl": "1h", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$P/.claude/commandeck.json"
run "$T/wt/plain" >/dev/null 2>&1; run "$T/wt/bld" --builder >/dev/null 2>&1
check "each role's worktree gets its own TTL: a Builder answered 1h gets 1h, the relay keeps 1h" '"1h":"1h":"1h"' "$(tenv plain):$(tenv bld):$(tenv Chief-of-Staff)"
echo '{"version": 1, "profile": "claude", "workerCacheTtl": "leave", "chiefOfStaff": {"name": "r", "cacheTtl": "leave"}}' > "$P/.claude/commandeck.json"
for w in plain bld Chief-of-Staff; do echo '{}' > "$T/wt/$w/.claude/settings.local.json"; done
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1; run "$T/wt/plain" >/dev/null 2>&1; run "$T/wt/bld" --builder >/dev/null 2>&1
check "Leave as is writes no TTL anywhere" 'null:null:null' "$(tenv plain):$(tenv bld):$(tenv Chief-of-Staff)"
# The relay answered 5m: written from a fresh settings file and beside another env entry.
echo '{"version": 1, "profile": "claude", "chiefOfStaff": {"name": "r", "cacheTtl": "5m"}}' > "$P/.claude/commandeck.json"
echo '{}' > "$T/wt/Chief-of-Staff/.claude/settings.local.json"; run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
R1=$(tenv Chief-of-Staff)
echo '{"env":{"OTHER":"x"}}' > "$T/wt/Chief-of-Staff/.claude/settings.local.json"; run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
check "a relay answered 5m gets 5m, from a fresh settings file and beside another env entry" '"5m":{"OTHER":"x","CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}' "$R1:$(jq -c '.env' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"

# --- a worker pane's starting context: Stripe and the browser skills off, no auto memory ---
# What this pins: main and the relay keep everything; a worker and a Builder drop what a build never uses, a --keep
# list brings parts back, the keep is remembered across a rerun, and a leaf the owner set by hand is never ours to delete.
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
for w in w1 w2 w3 w4 w5 w6 w7 w8 w9; do git -C "$P" worktree add -q "$T/wt/$w"; done
f() { echo "$T/wt/$1/.claude/settings.local.json"; }
CUTS='[.enabledPlugins["stripe@claude-plugins-official"], .skillOverrides["anthropic-skills:computer-use"], .skillOverrides["anthropic-skills:built-in-browser"], .skillOverrides["anthropic-skills:chrome-browser"], .autoMemoryEnabled]'
run "$T/wt/w1" >/dev/null 2>&1; run "$T/wt/w2" --builder >/dev/null 2>&1
check "a worker file has Stripe off, the three browser skills off and auto memory off" '[false,"off","off","off",false]' "$(jq -c "$CUTS" "$(f w1)")"
check "so does a Builder file" '[false,"off","off","off",false]' "$(jq -c "$CUTS" "$(f w2)")"
run "$T/wt/w3" --keep billing --builder >/dev/null 2>&1; run "$T/wt/w4" --keep billing >/dev/null 2>&1
check "--keep billing, either side of --builder, leaves the Stripe key unset and the rest cut" '[null,"off","off","off",false]:[null,"off","off","off",false]' "$(jq -c "$CUTS" "$(f w3)"):$(jq -c "$CUTS" "$(f w4)")"
run "$T/wt/w3" --builder >/dev/null 2>&1; run "$T/wt/w4" >/dev/null 2>&1
check "a rerun without the flag keeps the stored keep" 'billing:billing:null' "$(jq -r '.env.COMMANDECK_SKILL_KEEP' "$(f w3)"):$(jq -r '.env.COMMANDECK_SKILL_KEEP' "$(f w4)"):$(jq -c '.enabledPlugins["stripe@claude-plugins-official"]' "$(f w4)")"
run "$T/wt/w4" --keep other >/dev/null 2>&1
check "a rerun that passes --keep replaces it: Stripe is off again" false "$(jq -c '.enabledPlugins["stripe@claude-plugins-official"]' "$(f w4)")"
run "$T/wt/w1" --keep all >/dev/null 2>&1
check "--keep all on a seeded file removes every leaf" '[null,null,null,null,null]' "$(jq -c "$CUTS" "$(f w1)")"
run "$T/wt/w1" >/dev/null 2>&1
check "and stays removed on a rerun without the flag" '[null,null,null,null,null]:all' "$(jq -c "$CUTS" "$(f w1)"):$(jq -r '.env.COMMANDECK_SKILL_KEEP' "$(f w1)")"
mkdir -p "$T/wt/w5/.claude"; echo '{"skillOverrides":{"mine:skill":"off"},"autoMemoryEnabled":true}' > "$(f w5)"
run "$T/wt/w5" >/dev/null 2>&1; run "$T/wt/w5" >/dev/null 2>&1
check "an owner's hand-set skillOverrides entry survives a rerun, and the cuts sit beside it" '"off":"off"' "$(jq -c '.skillOverrides["mine:skill"]' "$(f w5)"):$(jq -c '.skillOverrides["anthropic-skills:chrome-browser"]' "$(f w5)")"
run "$T/wt/w5" --keep all >/dev/null 2>&1
check "and survives --keep all" '"off"' "$(jq -c '.skillOverrides["mine:skill"]' "$(f w5)")"
echo '{"autoMemoryEnabled":false,"skillOverrides":{"anthropic-skills:chrome-browser":"off"},"env":{"COMMANDECK_SKILL_KEEP":"all","COMMANDECK_DEFAULT_CUTS":"anthropic-skills:chrome-browser"}}' > "$T/wt/Chief-of-Staff/.claude/settings.local.json"
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
check "the relay file has none, and a leaf an earlier run wrote is taken out" '[null,null,null,null]:null' \
  "$(jq -c '[.skillOverrides["anthropic-skills:chrome-browser"], .autoMemoryEnabled, .env.COMMANDECK_SKILL_KEEP, .hooks.SessionStart]' "$T/wt/Chief-of-Staff/.claude/settings.local.json"):$(jq -c '.enabledPlugins["ponytail@ponytail"]' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
run "$T/wt/w3" --builder --keep billing >/dev/null 2>&1
check "--print-settings prints the file a rerun leaves, the stored keep read" "$(jq -S . "$(f w3)" | cksum)" "$(run "$T/wt/w3" --builder --print-settings 2>/dev/null | jq -S . | cksum)"
# Issue 365: setup writes no ponytail key and no summary hook, even where the owner has the third-party plugin on.
SUMHOOK='[.enabledPlugins["ponytail@ponytail"], ([.hooks.SessionStart[]?.hooks[]?.command | select(test("/templates/ponytail/SUMMARY[.]md\"$"))] | length)]'
mkdir -p "$HOME/.claude"; echo '{"enabledPlugins":{"ponytail@ponytail":true}}' > "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
run "$T/wt/w6" >/dev/null 2>&1; run "$T/wt/w7" --builder >/dev/null 2>&1; run "$T/wt/w6" >/dev/null 2>&1
check "a fresh Builder setup writes no ponytail@ponytail key" '[null,0]' "$(jq -c "$SUMHOOK" "$(f w7)")"
check "a worker setup writes none either, on a rerun too" '[null,0]' "$(jq -c "$SUMHOOK" "$(f w6)")"
# A worktree set up before 0.48.0 has the summary SessionStart hook, its off leaf and maybe an owner's hook in the same
# registration: a rerun drops the setup's hook and the off leaf, and keeps the owner's.
git -C "$P" worktree add -q "$T/wt/w10"; mkdir -p "$T/wt/w10/.claude"
SUMCMD='echo "Ponytail level: lite"; cat "/plugin/templates/ponytail/SUMMARY.md"'
jq -n --arg s "$SUMCMD" '{enabledPlugins: {"ponytail@ponytail": false}, hooks: {SessionStart: [{hooks: [{type: "command", command: $s}, {type: "command", command: "./owner-startup.sh"}]}, {hooks: [{type: "command", command: $s}]}]}}' > "$(f w10)"
OLD='[.enabledPlugins["ponytail@ponytail"], [.hooks.SessionStart[]?.hooks[]?.command], (.hooks.SessionStart | length)]'
run "$T/wt/w10" >/dev/null 2>&1; run "$T/wt/w10" --builder >/dev/null 2>&1
check "a rerun on a worktree set up with the summary hook drops that hook and its off leaf and keeps an owner hook beside it" '[null,["./owner-startup.sh"],1]' "$(jq -c "$OLD" "$(f w10)")"
git -C "$P" worktree add -q "$T/wt/w19"; mkdir -p "$T/wt/w19/.claude"; echo '{"enabledPlugins":{"ponytail@ponytail":false}}' > "$(f w19)"
run "$T/wt/w19" >/dev/null 2>&1
check "an owner's own ponytail off with no summary hook beside it is left as it is" '[false,0]' "$(jq -c "$SUMHOOK" "$(f w19)")"
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
check "the relay carries no ponytail key and no hook" '[null,0]' "$(jq -c "$SUMHOOK" "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
echo '{}' > "$HOME/.claude/settings.json"

# --- the owner's own lists in commandeck.json: workerSkillsOff, workerPluginsOff and keeps ---
# What this pins: the plugin ships no name, so a worker's cuts are the move-1 set plus exactly what the owner listed;
# a keep word brings its set back; a list that shrinks takes its dropped leaves out on a rerun, and never a leaf the
# owner set by hand or one another step of this script writes (the business plugins).
SKS='[.skillOverrides | to_entries[] | "\(.key)=\(.value)"] | sort'
EPS='[.enabledPlugins | to_entries[] | select(.key | test("@m$|^stripe@|^design@")) | "\(.key)=\(.value)"] | sort'
M1='"anthropic-skills:built-in-browser=off","anthropic-skills:chrome-browser=off","anthropic-skills:computer-use=off"'
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
for w in w11 w12 w13; do git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"; done
run "$T/wt/w13" >/dev/null 2>&1
check "no owner list (the format 0.16.0 deployed): the skill cuts are the move-1 three and no other name" "[$M1]" "$(jq -c "$SKS" "$(f w13)")"
echo '{"version": 1, "profile": "claude", "workerSkillsOff": ["own:a", "own:b"], "workerPluginsOff": ["p1@m", "p2@m", "design@synced"], "keeps": {"tools": {"skills": ["own:b", "anthropic-skills:chrome-browser"], "plugins": ["p2@m"]}}}' > "$P/.claude/commandeck.json"
echo '{"skillOverrides": {"mine:skill": "off"}}' > "$(f w11)"
run "$T/wt/w11" >/dev/null 2>&1; run "$T/wt/w12" --keep tools >/dev/null 2>&1
check "a list produces exactly its leaves beside the move-1 cuts and the owner's own entry" \
  "[$M1,\"mine:skill=off\",\"own:a=off\",\"own:b=off\"]:[\"design@synced=false\",\"p1@m=false\",\"p2@m=false\",\"stripe@claude-plugins-official=false\"]" \
  "$(jq -c "$SKS" "$(f w11)"):$(jq -c "$EPS" "$(f w11)")"
check "a keep word brings back its skills and plugins, a move-1 skill included, and nothing else" \
  '["anthropic-skills:built-in-browser=off","anthropic-skills:computer-use=off","own:a=off"]:["design@synced=false","p1@m=false","stripe@claude-plugins-official=false"]' \
  "$(jq -c "$SKS" "$(f w12)"):$(jq -c "$EPS" "$(f w12)")"
check "the --print-settings view matches what a run leaves" "$(jq -S . "$(f w12)" | cksum)" "$(run "$T/wt/w12" --print-settings 2>/dev/null | jq -S . | cksum)"
echo '{"version": 1, "profile": "claude", "workerSkillsOff": ["own:a"]}' > "$P/.claude/commandeck.json"
run "$T/wt/w11" >/dev/null 2>&1
check "a rerun after the lists shrink removes the dropped leaves; the owner's entry and the business plugin stay" \
  "[$M1,\"mine:skill=off\",\"own:a=off\"]:[\"design@synced=false\",\"stripe@claude-plugins-official=false\"]" \
  "$(jq -c "$SKS" "$(f w11)"):$(jq -c "$EPS" "$(f w11)")"
run "$T/wt/w11" --keep all >/dev/null 2>&1
check "--keep all removes the owner's cuts too" '["mine:skill=off"]' "$(jq -c "$SKS" "$(f w11)")"
cp "$(f w12)" "$T/wt/Chief-of-Staff/.claude/settings.local.json"; run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
check "the relay carries none of the owner's cuts, and a leaf an earlier run wrote is taken out" '[]:null' \
  "$(jq -c "[.skillOverrides // {} | keys[] | select(startswith(\"own:\"))] + [.enabledPlugins | keys[] | select(endswith(\"@m\"))]" "$T/wt/Chief-of-Staff/.claude/settings.local.json"):$(jq -c '.env.COMMANDECK_OWNER_CUTS' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
# A leaf the owner set in the worktree file, before a run or after one, is theirs: a listed name never claims it, so a
# list that shrinks never deletes it (a deleted false would turn the plugin back on).
OWN='[(.skillOverrides // {} | to_entries[] | select(.key | startswith("own:"))), (.enabledPlugins // {} | to_entries[] | select(.key | endswith("@m"))) | "\(.key)=\(.value)"] | sort'
for w in w14 w15 w16 w17; do git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"; done
echo '{"enabledPlugins":{"p@m":false,"q@m":true},"skillOverrides":{"own:c":"on","own:d":"off"}}' > "$(f w14)"
echo '{"version": 1, "profile": "claude", "workerSkillsOff": ["own:c", "own:d", "own:e"], "workerPluginsOff": ["p@m", "q@m", "r@m"]}' > "$P/.claude/commandeck.json"
run "$T/wt/w14" >/dev/null 2>&1; run "$T/wt/w15" >/dev/null 2>&1
check "an owner's own leaf for a listed name is left as it is; an unset name is cut" \
  '["own:c=on","own:d=off","own:e=off","p@m=false","q@m=true","r@m=false"]' "$(jq -c "$OWN" "$(f w14)")"
jq '.skillOverrides["own:e"] = "on" | .enabledPlugins["r@m"] = true' "$(f w15)" > "$T/x" && mv "$T/x" "$(f w15)"
run "$T/wt/w15" >/dev/null 2>&1
check "a cut the owner turned back on by hand stays on on a rerun" '["own:c=off","own:d=off","own:e=on","p@m=false","q@m=false","r@m=true"]' "$(jq -c "$OWN" "$(f w15)")"
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
run "$T/wt/w14" >/dev/null 2>&1; run "$T/wt/w15" >/dev/null 2>&1
check "once the lists are gone, only the owner's own leaves remain, each with its value" \
  '["own:c=on","own:d=off","p@m=false","q@m=true"]:["own:e=on","r@m=true"]' "$(jq -c "$OWN" "$(f w14)"):$(jq -c "$OWN" "$(f w15)")"
# A keep word brings back a plugin another step cuts by default (a business plugin, memoir), not only the
# owner's listed ones: otherwise the word cannot give the unit the plugin set it promises.
echo '{"version": 1, "profile": "claude", "workerPluginsOff": ["design@synced", "own@m"], "keeps": {"tools": {"plugins": ["design@synced", "own@m", "memoir@memoir"]}}}' > "$P/.claude/commandeck.json"
KP='[.enabledPlugins["design@synced"], .enabledPlugins["memoir@memoir"], .enabledPlugins["own@m"], .enabledPlugins["operations@synced"]]'
run "$T/wt/w16" --keep tools >/dev/null 2>&1; run "$T/wt/w17" --builder --keep tools >/dev/null 2>&1; run "$T/wt/w17" --builder >/dev/null 2>&1
check "a keep word turns its business plugin, memoir and a listed plugin back on for a worker and a Builder; the rest stay off" \
  '[null,null,null,false]:[null,null,null,false]' "$(jq -c "$KP" "$(f w16)"):$(jq -c "$KP" "$(f w17)")"
check "the --print-settings view of a kept plugin set matches what a run leaves" "$(jq -S . "$(f w16)" | cksum)" "$(run "$T/wt/w16" --print-settings 2>/dev/null | jq -S . | cksum)"
run "$T/wt/w16" --keep other >/dev/null 2>&1
check "without the word the same plugins are cut again" '[false,false,false,false]' "$(jq -c "$KP" "$(f w16)")"
echo '{}' > "$HOME/.claude/settings.json"
# Every other name the run deletes before it reads the owner's leaves (a move-1 skill, Stripe, memoir) is never
# claimed for a list either, so a list that drops it leaves that step's own cut in place.
git -C "$P" worktree add -q "$T/wt/w21"
echo '{"version": 1, "profile": "claude", "workerSkillsOff": ["anthropic-skills:computer-use"], "workerPluginsOff": ["stripe@claude-plugins-official", "memoir@memoir"]}' > "$P/.claude/commandeck.json"
FX='[.env.COMMANDECK_OWNER_CUTS, .skillOverrides["anthropic-skills:computer-use"], .enabledPlugins["stripe@claude-plugins-official"], .enabledPlugins["memoir@memoir"]]'
run "$T/wt/w21" >/dev/null 2>&1; a=$(jq -c "$FX" "$(f w21)")
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"; run "$T/wt/w21" >/dev/null 2>&1
check "a list naming a move-1 skill, Stripe or memoir stores none of them, and a shrink keeps each step's cut" \
  '[null,"off",false,false]:[null,"off",false,false]' "$a:$(jq -c "$FX" "$(f w21)")"
# A hand-edited keep word that is not an object once stopped the run before the lean-pane step.
echo '{"version": 1, "profile": "claude", "keeps": {"tools": "x"}}' > "$P/.claude/commandeck.json"
echo '{}' > "$(f w13)"; run "$T/wt/w13" --keep tools >/dev/null 2>&1; rc=$?
check "a keep word that is not an object is ignored and the run still cuts" "0:[$M1]" "$rc:$(jq -c "$SKS" "$(f w13)")"
# A keep word gives back the owner's own leaf for a plugin step 8 cuts, not nothing: a deleted false would turn the
# plugin on from the user settings. Only the leaves the run stored as its own are deleted (ruling 2026-10-18).
for w in w22 w23 w24; do git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"; done
echo '{"enabledPlugins":{"design@synced":false,"memoir@memoir":true}}' > "$(f w22)"
echo '{"env":{"CLAUDE_CODE_AUTO_COMPACT_WINDOW":"450000"},"enabledPlugins":{"design@synced":false,"memoir@memoir":false}}' > "$(f w24)"
echo '{"version": 1, "profile": "claude", "keeps": {"tools": {"plugins": ["design@synced", "memoir@memoir"]}}}' > "$P/.claude/commandeck.json"
DM='[.enabledPlugins["design@synced"], .enabledPlugins["memoir@memoir"], .enabledPlugins["operations@synced"]]'
run "$T/wt/w22" --keep tools >/dev/null 2>&1; a=$(jq -c "$DM" "$(f w22)"); run "$T/wt/w22" --keep tools >/dev/null 2>&1
check "a keep word leaves the owner's own off and on for a kept plugin, on every rerun; the rest stay off" \
  '[false,true,false]:[false,true,false]' "$a:$(jq -c "$DM" "$(f w22)")"
run "$T/wt/w22" --keep other >/dev/null 2>&1; run "$T/wt/w22" --keep tools >/dev/null 2>&1
check "and a run without the word between keeps the owner's off and gives back their on" '[false,true,false]' "$(jq -c "$DM" "$(f w22)")"
run "$T/wt/w23" >/dev/null 2>&1; run "$T/wt/w23" --keep tools >/dev/null 2>&1; a=$(jq -c "$DM" "$(f w23)")
jq '.enabledPlugins["design@synced"] = false' "$(f w23)" > "$T/x" && mv "$T/x" "$(f w23)"; run "$T/wt/w23" >/dev/null 2>&1
check "the run's own cut goes on a keep; an off the owner sets after it stays" '[null,null,false]:[false,null,false]' "$a:$(jq -c "$DM" "$(f w23)")"
run "$T/wt/w24" --keep tools >/dev/null 2>&1
check "a file with no stored cuts (an earlier version's): every off is the owner's, so a keep word leaves it" '[false,false,false]' "$(jq -c "$DM" "$(f w24)")"
# The move-1 cuts (the browser skills, Stripe) follow the same rule: a keep word, --keep billing or --keep all takes
# out only the leaves the run stored as its own, and the owner's own leaf for one of them is left as it is.
for w in w25 w26 w27; do git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"; done
echo '{"version": 1, "profile": "claude", "keeps": {"tools": {"skills": ["anthropic-skills:chrome-browser"], "plugins": ["stripe@claude-plugins-official"]}}}' > "$P/.claude/commandeck.json"
MV='[.skillOverrides["anthropic-skills:chrome-browser"], .enabledPlugins["stripe@claude-plugins-official"], .skillOverrides["anthropic-skills:computer-use"]]'
echo '{"skillOverrides":{"anthropic-skills:chrome-browser":"off"},"enabledPlugins":{"stripe@claude-plugins-official":false}}' > "$(f w25)"
run "$T/wt/w25" --keep tools >/dev/null 2>&1; a=$(jq -c "$MV" "$(f w25)"); run "$T/wt/w25" --keep tools >/dev/null 2>&1
check "a keep word leaves the owner's own browser-skill and Stripe off, on every rerun; the run's other cuts stay" \
  '["off",false,"off"]:["off",false,"off"]' "$a:$(jq -c "$MV" "$(f w25)")"
run "$T/wt/w25" --keep all >/dev/null 2>&1
check "and --keep all leaves them too, taking out only the run's own" '["off",false,null]' "$(jq -c "$MV" "$(f w25)")"
echo '{"enabledPlugins":{"stripe@claude-plugins-official":false}}' > "$(f w26)"; run "$T/wt/w26" --keep billing >/dev/null 2>&1
a=$(jq -c '.enabledPlugins["stripe@claude-plugins-official"]' "$(f w26)"); run "$T/wt/w26" --keep other >/dev/null 2>&1; run "$T/wt/w26" --keep billing >/dev/null 2>&1
check "--keep billing leaves the owner's own Stripe off, a run without the word between too" false:false "$a:$(jq -c '.enabledPlugins["stripe@claude-plugins-official"]' "$(f w26)")"
check "and the summary line says Stripe off, not kept" 1 "$(run "$T/wt/w26" --keep billing 2>&1 | grep -c 'Stripe off')"
echo '{"skillOverrides":{"anthropic-skills:chrome-browser":"on"},"enabledPlugins":{"stripe@claude-plugins-official":true}}' > "$(f w27)"
run "$T/wt/w27" --keep other >/dev/null 2>&1; a=$(jq -c "$MV" "$(f w27)"); run "$T/wt/w27" --keep tools >/dev/null 2>&1
check "the owner's own on for a move-1 name is left as it is, with or without the word" '["on",true,"off"]:["on",true,"off"]' "$a:$(jq -c "$MV" "$(f w27)")"

# --- Issue 397: every worker pane runs the model guard; a planning worktree may start helpers ---
# guard <wt> <payload> [env...] -- the Agent|Task command the worktree's settings register, run with the settings' env.
guard() { local w=$1 i=$2; shift 2; local cmd; cmd=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Agent|Task") | .hooks[0].command' "$(f "$w")" | head -n1)
  jq -cn --argjson i "$i" '{tool_name:"Agent", tool_input:$i}' | env -u COMMANDECK_SEAT -u COMMANDECK_BUILDER "$@" $(jq -r '.env | to_entries[] | select(.key == "COMMANDECK_BUILDER") | "\(.key)=\(.value)"' "$(f "$w")") sh -c "$cmd" 2>/dev/null | jq -sr '.[0].hookSpecificOutput.updatedInput.model // "none"'; }
EXP='{"subagent_type":"Explore","description":"x","prompt":"y"}'; GPO='{"subagent_type":"general-purpose","model":"opus","description":"x","prompt":"y"}'
git -C "$P" worktree add -q "$T/wt/g1"; git -C "$P" worktree add -q "$T/wt/g2"; git -C "$P" worktree add -q "$T/wt/g3"; git -C "$P" worktree add -q "$T/wt/g4"
run "$T/wt/g1" --builder >/dev/null 2>&1
check "a Builder worktree created the normal way runs Explore on Haiku and general-purpose on Sonnet" haiku:sonnet "$(guard g1 "$EXP"):$(guard g1 "$GPO")"
run "$T/wt/g2" >/dev/null 2>&1
check "a worker worktree registers the model guard too" 1 "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Agent|Task")] | length' "$(f g2)")"
# Issue 399: the auto-mode classifier must not stop a Codex helper call; the script refuses judge and reviewer panes itself.
check "a worker worktree allows the Codex helper" "1:1" \
  "$(jq --arg e "Bash(bash $(printf '%q' "$REAL/scripts")/codex-ask.sh:*)" '[.permissions.allow[] | select(. == $e)] | length' "$(f g2)"):$(jq --arg e "Bash(bash $(printf '%q' "$REAL/scripts")/codex-ask.sh:*)" '[.permissions.allow[] | select(. == $e)] | length' "$(f g1)")"
run "$T/wt/g2" >/dev/null 2>&1; run "$T/wt/g1" --builder >/dev/null 2>&1
check "a rerun registers it once" 1:1 "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Agent|Task")] | length' "$(f g2)"):$(jq '[.hooks.PreToolUse[] | select(.matcher == "Agent|Task")] | length' "$(f g1)")"
echo plan-unit > "$(git -C "$T/wt/g3" rev-parse --absolute-git-dir)/commandeck-plan-of"
run "$T/wt/g3" >/dev/null 2>&1
check "a planning worktree's settings allow helpers" "false:true:sonnet" \
  "$(jq '.permissions.deny | index("Agent") != null' "$(f g3)"):$(jq '.permissions.deny | index("WebSearch") != null' "$(f g3)"):$(guard g3 "$GPO" COMMANDECK_SEAT=plan-author)"
check "an unmarked worker worktree still denies helpers" true "$(jq '.permissions.deny | index("Agent") != null' "$(f g2)")"
echo plan-unit > "$(git -C "$T/wt/g4" rev-parse --absolute-git-dir)/commandeck-plan-of"
run "$T/wt/g4" >/dev/null 2>&1
check "a planning worktree's printed settings match the written ones" true "$(run "$T/wt/g4" --print-settings 2>/dev/null | jq -s --slurpfile w "$(f g4)" '.[0] == $w[0]')"
# The routing validator: a helpers entry that is not a model name fails the whole file.
jq '.roles.builder.helpers.Explore = "Haiku 4"' "$REAL/config/routing.json" > "$T/bad-routing.json"
check "a helpers entry that is not a model name fails the routing file" "1:1" \
  "$(COMMANDECK_ROUTING=$T/bad-routing.json bash -c '. "$0/scripts/paths.sh"; pp_routing_valid' "$REAL" 2>&1 | grep -c 'builder has a bad helpers entry Explore'):$(COMMANDECK_ROUTING=$REAL/config/routing.json bash -c '. "$0/scripts/paths.sh"; pp_routing_valid >/dev/null 2>&1 && echo 1' "$REAL" 2>/dev/null)"

# --- the standing lanes (issue 416): a Fast-lane and a Research-lane worktree are workers with three differences ---
# The 1-hour cache in the lane's own file only, no Stop hook that wakes main every lane turn, and high effort for Research.
for w in Fast-lane Research-lane lanep; do git -C "$P" worktree add -q "$T/wt/$w"; done
echo '{"version": 1, "profile": "claude", "workerCacheTtl": "5m"}' > "$P/.claude/commandeck.json"
for w in Fast-lane Research-lane lanep; do run "$T/wt/$w" >/dev/null 2>&1; done
check "a lane's settings carry the 1-hour cache; an ordinary worker's keep 5m" '"1h":"1h":"5m"' "$(tenv Fast-lane):$(tenv Research-lane):$(tenv lanep)"
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
for w in Fast-lane lanep; do echo '{}' > "$T/wt/$w/.claude/settings.local.json"; run "$T/wt/$w" >/dev/null 2>&1; done
check "a lane has the 1-hour cache even when the owner gave no worker answer" '"1h":null' "$(tenv Fast-lane):$(tenv lanep)"
notify() { jq '[.hooks.Stop[]?.hooks[]?.command | select(test("claude-worker-notify"))] | length' "$T/wt/$1/.claude/settings.local.json"; }
check "a lane registers no main-waking Stop hook; an ordinary worker does" '0:0:1' "$(notify Fast-lane):$(notify Research-lane):$(notify lanep)"
check "the Research lane runs at high effort; the Fast lane and a worker set none" '"high":null:null' \
  "$(jq -c '.effortLevel // null' "$T/wt/Research-lane/.claude/settings.local.json"):$(jq -c '.effortLevel // null' "$T/wt/Fast-lane/.claude/settings.local.json"):$(jq -c '.effortLevel // null' "$T/wt/lanep/.claude/settings.local.json")"
# Issue 424: the two lanes may start Sonnet and Haiku helpers, so their settings drop the Agent deny; by exact name,
# so a look-alike folder or a new standing seat keeps it.
agents() { jq '[.permissions.deny[]? | select(. == "Agent")] | length' "$T/wt/$1/.claude/settings.local.json"; }
check "a lane may spawn helpers: its settings do not deny Agent; an ordinary worker's do" '0:0:1' "$(agents Fast-lane):$(agents Research-lane):$(agents lanep)"
for w in Fast-lane2 Research; do git -C "$P" worktree add -q "$T/wt/$w"; run "$T/wt/$w" >/dev/null 2>&1; done
check "the helper allowance is the two lanes only" '1:1:1' "$(agents Fast-lane2):$(agents Research):$(agents lanep)"
echo '{"permissions":{"deny":["Agent"]}}' > "$T/wt/Fast-lane/.claude/settings.local.json"; run "$T/wt/Fast-lane" >/dev/null 2>&1
check "a rerun takes an old Agent deny off a lane" 0 "$(agents Fast-lane)"
# The drift check: every site that names the standing folders names the same three as pp_standing_wt. A shell site
# must call the function; a jq site spells the set in an alternation, which must equal the function's.
SET=$(bash -c '. "$0/hooks/lib/project.sh"; for n in Chief-of-Staff Fast-lane Research-lane Builder-probe main Fast-lane2 Research Chief; do pp_standing_wt "$n" && echo "$n"; done | sort | paste -sd, -' "$REAL")
check "pp_standing_wt is true for the three folders and no look-alike" 'Chief-of-Staff,Fast-lane,Research-lane' "$SET"
DRIFT=
for s in hooks/pane-budget-gate.sh hooks/worker-ask-guard.sh hooks/ruling-log.sh scripts/install-lib.sh scripts/dashboard.sh scripts/worktree-setup.sh; do
  grep -q 'pp_standing_wt' "$REAL/$s" || DRIFT="$DRIFT $s(no call)"
done
grep -q 'PP_STANDING_SEATS' "$REAL/scripts/ruling-log-archive.sh" || DRIFT="$DRIFT scripts/ruling-log-archive.sh(no list)"
for s in scripts/cos-check.sh; do
  got=$(grep -oE '\(Chief-of-Staff(\|[A-Za-z-]+)+\)' "$REAL/$s" | tr -d '()' | tr '|' '\n' | sort | paste -sd, -)
  [ "$got" = "$SET" ] || DRIFT="$DRIFT $s($got)"
done
# Issue 420: the units view filters the folders by the stage dashboard.sh writes, the folder name lowercased.
got=$(sed -n "s/^export const NOT_UNITS = new Set(\[\(.*\)\])$/\1/p" "$REAL/hooks/units-sources.ts" | tr -d "' " | tr ',' '\n' | sort | paste -sd, -)
[ "$got" = "$(tr '[:upper:]' '[:lower:]' <<<"$SET")" ] || DRIFT="$DRIFT hooks/units-sources.ts($got)"
check "every standing-worktree list names the same three folders" "" "$DRIFT"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
