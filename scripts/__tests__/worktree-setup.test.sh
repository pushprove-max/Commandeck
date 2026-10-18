#!/usr/bin/env bash
# worktree-setup.test.sh -- the settings profile worktree-setup.sh writes for a worktree, a relay pane's and a
# Builder's, on a hand-written commandeck.json (no setup run). What this pins: the owner wants ponytail at
# full for every role, the relay pane included (2026-10-16), so an earlier run's "off" is taken back out; the
# typescript-lsp plugin is gone, so no profile names it; and the summary line reads as words.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME"
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
echo '{"autoMemoryEnabled":false,"skillOverrides":{"anthropic-skills:chrome-browser":"off"},"env":{"COMMANDECK_SKILL_KEEP":"all"}}' > "$T/wt/Chief-of-Staff/.claude/settings.local.json"
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
check "the summary hook prints the summary file" "$(cat "$REAL/templates/ponytail/SUMMARY.md")" "$(bash -c "$(jq -r '.hooks.SessionStart[]?.hooks[]?.command | select(test("SUMMARY"))' "$(f w6)")")"
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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
