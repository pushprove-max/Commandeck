#!/usr/bin/env bash
# worktree-setup.test.sh -- the settings profile worktree-setup.sh writes for a worktree, a relay pane's and a
# Builder's, on a hand-written commandeck.json (no setup run). What this pins: the owner wants ponytail on
# (a level, lite by default: issue 330) for every role, the relay pane included (2026-10-16), so an earlier run's "off" is taken back out; the
# typescript-lsp plugin is gone, so no profile names it; and the summary line reads as words.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME"; unset CLAUDE_CONFIG_DIR # the owner's settings are $HOME/.claude's, not the caller's
P=$T/proj; git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
mkdir -p "$P/.claude" && echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
run() { (cd "$1" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH bash "$REAL/scripts/worktree-setup.sh" "$@" </dev/null); }
# An earlier run turned ponytail and typescript-lsp off in every profile.
for w in Chief-of-Staff plain bld; do
  git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"
  echo '{"enabledPlugins":{"ponytail@ponytail":false,"typescript-lsp@claude-plugins-official":false}}' > "$T/wt/$w/.claude/settings.local.json"
done
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
run "$T/wt/plain" >"$T/wout" 2>&1
run "$T/wt/bld" --builder >/dev/null 2>&1
check "the relay pane no longer turns ponytail off: it follows the owner's setting" null "$(jq '.enabledPlugins["ponytail@ponytail"]' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
check "no worktree, relay or Builder profile names typescript-lsp" 0 \
  "$(cat "$T/wt"/{plain,Chief-of-Staff,bld}/.claude/settings.local.json | jq -s '[.[].enabledPlugins | keys[] | select(startswith("typescript-lsp"))] | length')"
check "the worktree summary says memoir off, then the denied tools, a space between" 1 "$(grep -c 'memoir off, [0-9]* unused tools denied' "$T/wout")"

# --- the prompt-cache answers: workers 5m, the relay 1h with its other env kept, nothing without an answer ---
tenv() { jq -c ".env.CLAUDE_CODE_PROMPT_CACHE_TTL // null" "$T/wt/$1/.claude/settings.local.json"; }
echo '{"env":{"OTHER":"x"}}' > "$T/wt/Chief-of-Staff/.claude/settings.local.json"
echo '{"version": 1, "profile": "claude", "cacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$P/.claude/commandeck.json"
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1; run "$T/wt/plain" >/dev/null 2>&1; run "$T/wt/bld" --builder >/dev/null 2>&1
check "the relay's 1h is written and its other env entry survives" '{"OTHER":"x","CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}' \
  "$(jq -c '.env' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
check "a worker and a Builder both get 5m (a Builder was 1h)" '"5m":"5m"' "$(tenv plain):$(tenv bld)"
echo '{"version": 1, "profile": "claude", "cacheTtl": "leave", "chiefOfStaff": {"name": "r", "cacheTtl": "leave"}}' > "$P/.claude/commandeck.json"
for w in plain bld Chief-of-Staff; do echo '{}' > "$T/wt/$w/.claude/settings.local.json"; done
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1; run "$T/wt/plain" >/dev/null 2>&1; run "$T/wt/bld" --builder >/dev/null 2>&1
check "Leave as is writes no TTL anywhere" 'null:null:null' "$(tenv plain):$(tenv bld):$(tenv Chief-of-Staff)"

# --- a worker pane's starting context: Stripe and the browser skills off, no auto memory, ponytail as a summary ---
# What this pins: main and the relay keep everything; a worker and a Builder drop what a build never uses, a --keep
# list brings parts back, the keep is remembered across a rerun, and a leaf the owner set by hand is never ours to delete.
echo '{"version": 1, "profile": "claude", "ponytail": false}' > "$P/.claude/commandeck.json"
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
# Ponytail: the hook prints the summary where the plugin is on in the owner's user settings and setup's answer is yes.
SUMHOOK='[.enabledPlugins["ponytail@ponytail"], ([.hooks.SessionStart[]?.hooks[]?.command | select(test("/templates/ponytail/SUMMARY[.]md\"$"))] | length)]'
mkdir -p "$HOME/.claude"; echo '{"enabledPlugins":{"ponytail@ponytail":true}}' > "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude", "ponytail": true}' > "$P/.claude/commandeck.json"
run "$T/wt/w6" >/dev/null 2>&1; run "$T/wt/w7" --builder >/dev/null 2>&1; run "$T/wt/w6" >/dev/null 2>&1
check "ponytail on: a worker and a Builder carry the summary hook once, and the plugin off" '[false,1]:[false,1]' "$(jq -c "$SUMHOOK" "$(f w6)"):$(jq -c "$SUMHOOK" "$(f w7)")"
check "the summary hook prints the level (a saved true is lite), then the summary file" "$(printf 'Ponytail level: lite\n%s' "$(cat "$REAL/templates/ponytail/SUMMARY.md")")" "$(bash -c "$(jq -r '.hooks.SessionStart[]?.hooks[]?.command | select(test("SUMMARY"))' "$(f w6)")")"
# Issue 330: ponytail is a level. off drops the hook as false did; every other level carries it as true did, and says
# its level; none saved is lite; a /config answer beats the project's. Plugin on in the owner's settings throughout.
LV='[.enabledPlugins["ponytail@ponytail"], ([.hooks.SessionStart[]?.hooks[]?.command | select(test("SUMMARY"))] | length), ([.hooks.SessionStart[]?.hooks[]?.command | select(test("SUMMARY"))][0] // "" | capture("Ponytail level: (?<l>[a-z]+)").l? // "")] | join(",")'
lvl() { git -C "$P" worktree add -q "$T/wt/lv$1"; mkdir -p "$T/wt/lv$1/.claude"; run "$T/wt/lv$1" >/dev/null 2>&1; jq -r "$LV" "$(f lv$1)"; }
for l in off lite full ultra; do
  echo "{\"version\": 1, \"profile\": \"claude\", \"ponytail\": \"$l\"}" > "$P/.claude/commandeck.json"
  case $l in off) want=",0," ;; *) want="false,1,$l" ;; esac
  check "ponytail $l: the hook is $([ "$l" = off ] && echo absent || echo "there, saying $l")" "$want" "$(lvl $l)"
done
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
check "ponytail with no answer saved: lite" "false,1,lite" "$(lvl default)"
jq '. + {pluginConfigs: {"commandeck@commandeck": {options: {ponytail: "ultra"}}}}' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude", "ponytail": "off"}' > "$P/.claude/commandeck.json"
check "a /config ultra beats the project's off" "false,1,ultra" "$(lvl config)"
jq 'del(.pluginConfigs)' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude", "ponytail": true}' > "$P/.claude/commandeck.json"
# The owner's own startup command, in the same group as the summary hook, is not ours to delete on a rerun.
git -C "$P" worktree add -q "$T/wt/w10"; mkdir -p "$T/wt/w10/.claude"
echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"cat \"/plugin/templates/ponytail/SUMMARY.md\""},{"type":"command","command":"./owner-startup.sh"}]}]}}' > "$(f w10)"
OWNED='[.hooks.SessionStart[]?.hooks[]?.command | select(test("SUMMARY") | not)]'
run "$T/wt/w10" >/dev/null 2>&1; run "$T/wt/w10" >/dev/null 2>&1
check "a rerun keeps an owner's command grouped with the summary hook, and carries the summary once" '["./owner-startup.sh"]:1' "$(jq -c "$OWNED" "$(f w10)"):$(jq -c "$SUMHOOK | .[1]" "$(f w10)")"
run "$T/wt/w10" --keep all >/dev/null 2>&1
check "--keep all takes the summary out and leaves the owner's command" '["./owner-startup.sh"]:0' "$(jq -c "$OWNED" "$(f w10)"):$(jq -c "$SUMHOOK | .[1]" "$(f w10)")"
run "$T/wt/w6" --keep all >/dev/null 2>&1
check "--keep all takes both ponytail leaves out" '[null,0]' "$(jq -c "$SUMHOOK" "$(f w6)")"
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
check "the relay keeps the plugin: no key, no hook" '[null,0]' "$(jq -c "$SUMHOOK" "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
echo '{"version": 1, "profile": "claude", "ponytail": false}' > "$P/.claude/commandeck.json"
run "$T/wt/w7" --builder >/dev/null 2>&1
check "setup's answer no: the plugin and the hook an earlier run wrote are gone" '[null,0]' "$(jq -c "$SUMHOOK" "$(f w7)")"
echo '{"version": 1, "profile": "claude", "ponytail": true}' > "$P/.claude/commandeck.json"; echo '{}' > "$HOME/.claude/settings.json"
run "$T/wt/w8" >/dev/null 2>&1; run "$T/wt/w9" --builder >/dev/null 2>&1
check "a skill-only install (plugin not on): neither the hook nor the key" '[null,0]:[null,0]' "$(jq -c "$SUMHOOK" "$(f w8)"):$(jq -c "$SUMHOOK" "$(f w9)")"

# --- the owner's own lists in commandeck.json: workerSkillsOff, workerPluginsOff and keeps ---
# What this pins: the plugin ships no name, so a worker's cuts are the move-1 set plus exactly what the owner listed;
# a keep word brings its set back; a list that shrinks takes its dropped leaves out on a rerun, and never a leaf the
# owner set by hand or one another step of this script writes (the business plugins).
SKS='[.skillOverrides | to_entries[] | "\(.key)=\(.value)"] | sort'
EPS='[.enabledPlugins | to_entries[] | select(.key | test("@m$|^stripe@|^design@")) | "\(.key)=\(.value)"] | sort'
M1='"anthropic-skills:built-in-browser=off","anthropic-skills:chrome-browser=off","anthropic-skills:computer-use=off"'
echo '{"version": 1, "profile": "claude", "ponytail": false}' > "$P/.claude/commandeck.json"
for w in w11 w12 w13; do git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"; done
run "$T/wt/w13" >/dev/null 2>&1
check "no owner list (the format 0.16.0 deployed): the skill cuts are the move-1 three and no other name" "[$M1]" "$(jq -c "$SKS" "$(f w13)")"
echo '{"version": 1, "profile": "claude", "ponytail": false, "workerSkillsOff": ["own:a", "own:b"], "workerPluginsOff": ["p1@m", "p2@m", "design@synced"], "keeps": {"tools": {"skills": ["own:b", "anthropic-skills:chrome-browser"], "plugins": ["p2@m"]}}}' > "$P/.claude/commandeck.json"
echo '{"skillOverrides": {"mine:skill": "off"}}' > "$(f w11)"
run "$T/wt/w11" >/dev/null 2>&1; run "$T/wt/w12" --keep tools >/dev/null 2>&1
check "a list produces exactly its leaves beside the move-1 cuts and the owner's own entry" \
  "[$M1,\"mine:skill=off\",\"own:a=off\",\"own:b=off\"]:[\"design@synced=false\",\"p1@m=false\",\"p2@m=false\",\"stripe@claude-plugins-official=false\"]" \
  "$(jq -c "$SKS" "$(f w11)"):$(jq -c "$EPS" "$(f w11)")"
check "a keep word brings back its skills and plugins, a move-1 skill included, and nothing else" \
  '["anthropic-skills:built-in-browser=off","anthropic-skills:computer-use=off","own:a=off"]:["design@synced=false","p1@m=false","stripe@claude-plugins-official=false"]' \
  "$(jq -c "$SKS" "$(f w12)"):$(jq -c "$EPS" "$(f w12)")"
check "the --print-settings view matches what a run leaves" "$(jq -S . "$(f w12)" | cksum)" "$(run "$T/wt/w12" --print-settings 2>/dev/null | jq -S . | cksum)"
echo '{"version": 1, "profile": "claude", "ponytail": false, "workerSkillsOff": ["own:a"]}' > "$P/.claude/commandeck.json"
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
echo '{"version": 1, "profile": "claude", "ponytail": false, "workerSkillsOff": ["own:c", "own:d", "own:e"], "workerPluginsOff": ["p@m", "q@m", "r@m"]}' > "$P/.claude/commandeck.json"
run "$T/wt/w14" >/dev/null 2>&1; run "$T/wt/w15" >/dev/null 2>&1
check "an owner's own leaf for a listed name is left as it is; an unset name is cut" \
  '["own:c=on","own:d=off","own:e=off","p@m=false","q@m=true","r@m=false"]' "$(jq -c "$OWN" "$(f w14)")"
jq '.skillOverrides["own:e"] = "on" | .enabledPlugins["r@m"] = true' "$(f w15)" > "$T/x" && mv "$T/x" "$(f w15)"
run "$T/wt/w15" >/dev/null 2>&1
check "a cut the owner turned back on by hand stays on on a rerun" '["own:c=off","own:d=off","own:e=on","p@m=false","q@m=false","r@m=true"]' "$(jq -c "$OWN" "$(f w15)")"
echo '{"version": 1, "profile": "claude", "ponytail": false}' > "$P/.claude/commandeck.json"
run "$T/wt/w14" >/dev/null 2>&1; run "$T/wt/w15" >/dev/null 2>&1
check "once the lists are gone, only the owner's own leaves remain, each with its value" \
  '["own:c=on","own:d=off","p@m=false","q@m=true"]:["own:e=on","r@m=true"]' "$(jq -c "$OWN" "$(f w14)"):$(jq -c "$OWN" "$(f w15)")"
# A keep word brings back a plugin another step cuts by default (a business plugin, memoir, ponytail), not only the
# owner's listed ones: otherwise the word cannot give the unit the plugin set it promises.
echo '{"enabledPlugins":{"ponytail@ponytail":true}}' > "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude", "ponytail": true, "workerPluginsOff": ["design@synced", "ponytail@ponytail"], "keeps": {"tools": {"plugins": ["design@synced", "ponytail@ponytail", "memoir@memoir"]}}}' > "$P/.claude/commandeck.json"
KP='[.enabledPlugins["design@synced"], .enabledPlugins["memoir@memoir"], .enabledPlugins["ponytail@ponytail"], ([.hooks.SessionStart[]?.hooks[]?.command | select(test("SUMMARY"))] | length), .enabledPlugins["operations@synced"]]'
run "$T/wt/w16" --keep tools >/dev/null 2>&1; run "$T/wt/w17" --builder --keep tools >/dev/null 2>&1; run "$T/wt/w17" --builder >/dev/null 2>&1
check "a keep word turns its business plugin, memoir and ponytail back on for a worker and a Builder; the rest stay off" \
  '[null,null,null,0,false]:[null,null,null,0,false]' "$(jq -c "$KP" "$(f w16)"):$(jq -c "$KP" "$(f w17)")"
check "the --print-settings view of a kept plugin set matches what a run leaves" "$(jq -S . "$(f w16)" | cksum)" "$(run "$T/wt/w16" --print-settings 2>/dev/null | jq -S . | cksum)"
run "$T/wt/w16" --keep other >/dev/null 2>&1
check "without the word the same plugins are cut again" '[false,false,false,1,false]' "$(jq -c "$KP" "$(f w16)")"
echo '{}' > "$HOME/.claude/settings.json"
# Ponytail's off is the run's only beside its summary hook: an owner's own off, listed or not, is never deleted or
# claimed, so a list that drops it cannot turn the plugin back on.
for w in w18 w19; do git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"; echo '{"enabledPlugins":{"ponytail@ponytail":false}}' > "$(f $w)"; done
PT='[.enabledPlugins["ponytail@ponytail"], .env.COMMANDECK_OWNER_CUTS]'
echo '{"version": 1, "profile": "claude", "ponytail": false, "workerPluginsOff": ["ponytail@ponytail"]}' > "$P/.claude/commandeck.json"
run "$T/wt/w18" >/dev/null 2>&1
check "an owner's own ponytail off for a listed name is left as it is and not stored" '[false,null]' "$(jq -c "$PT" "$(f w18)")"
echo '{"version": 1, "profile": "claude", "ponytail": false}' > "$P/.claude/commandeck.json"
run "$T/wt/w18" >/dev/null 2>&1; run "$T/wt/w19" >/dev/null 2>&1
check "once the list is gone, and with no list at all, the owner's ponytail off stays" '[false,null]:[false,null]' "$(jq -c "$PT" "$(f w18)"):$(jq -c "$PT" "$(f w19)")"
# The swap is the same claim: an owner's own ponytail leaf in this file is not swapped, so it is never the run's.
git -C "$P" worktree add -q "$T/wt/w20"; mkdir -p "$T/wt/w20/.claude"; echo '{"enabledPlugins":{"ponytail@ponytail":true}}' > "$(f w20)"
echo '{"enabledPlugins":{"ponytail@ponytail":true}}' > "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude", "ponytail": true}' > "$P/.claude/commandeck.json"
run "$T/wt/w19" >/dev/null 2>&1; run "$T/wt/w20" >/dev/null 2>&1
check "setup's answer yes leaves an owner's own ponytail leaf, off or on, and adds no summary" '[false,0]:[true,0]' "$(jq -c "$SUMHOOK" "$(f w19)"):$(jq -c "$SUMHOOK" "$(f w20)")"
echo '{"version": 1, "profile": "claude", "ponytail": false}' > "$P/.claude/commandeck.json"; echo '{}' > "$HOME/.claude/settings.json"
run "$T/wt/w19" >/dev/null 2>&1
check "and a later answer no still leaves the owner's off" '[false,0]' "$(jq -c "$SUMHOOK" "$(f w19)")"
# Every other name the run deletes before it reads the owner's leaves (a move-1 skill, Stripe, memoir) is never
# claimed for a list either, so a list that drops it leaves that step's own cut in place.
git -C "$P" worktree add -q "$T/wt/w21"
echo '{"version": 1, "profile": "claude", "ponytail": false, "workerSkillsOff": ["anthropic-skills:computer-use"], "workerPluginsOff": ["stripe@claude-plugins-official", "memoir@memoir"]}' > "$P/.claude/commandeck.json"
FX='[.env.COMMANDECK_OWNER_CUTS, .skillOverrides["anthropic-skills:computer-use"], .enabledPlugins["stripe@claude-plugins-official"], .enabledPlugins["memoir@memoir"]]'
run "$T/wt/w21" >/dev/null 2>&1; a=$(jq -c "$FX" "$(f w21)")
echo '{"version": 1, "profile": "claude", "ponytail": false}' > "$P/.claude/commandeck.json"; run "$T/wt/w21" >/dev/null 2>&1
check "a list naming a move-1 skill, Stripe or memoir stores none of them, and a shrink keeps each step's cut" \
  '[null,"off",false,false]:[null,"off",false,false]' "$a:$(jq -c "$FX" "$(f w21)")"
# A hand-edited keep word that is not an object once stopped the run before the lean-pane step.
echo '{"version": 1, "profile": "claude", "ponytail": false, "keeps": {"tools": "x"}}' > "$P/.claude/commandeck.json"
echo '{}' > "$(f w13)"; run "$T/wt/w13" --keep tools >/dev/null 2>&1; rc=$?
check "a keep word that is not an object is ignored and the run still cuts" "0:[$M1]" "$rc:$(jq -c "$SKS" "$(f w13)")"
# A keep word gives back the owner's own leaf for a plugin step 8 cuts, not nothing: a deleted false would turn the
# plugin on from the user settings. Only the leaves the run stored as its own are deleted (ruling 2026-10-18).
for w in w22 w23 w24; do git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"; done
echo '{"enabledPlugins":{"design@synced":false,"memoir@memoir":true}}' > "$(f w22)"
echo '{"env":{"CLAUDE_CODE_AUTO_COMPACT_WINDOW":"450000"},"enabledPlugins":{"design@synced":false,"memoir@memoir":false}}' > "$(f w24)"
echo '{"version": 1, "profile": "claude", "ponytail": false, "keeps": {"tools": {"plugins": ["design@synced", "memoir@memoir"]}}}' > "$P/.claude/commandeck.json"
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
echo '{"version": 1, "profile": "claude", "ponytail": false, "keeps": {"tools": {"skills": ["anthropic-skills:chrome-browser"], "plugins": ["stripe@claude-plugins-official"]}}}' > "$P/.claude/commandeck.json"
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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
