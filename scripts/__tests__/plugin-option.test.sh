#!/usr/bin/env bash
# plugin-option.test.sh -- the plugin's /config options (issue 245). An answer set in /config is the owner's for every
# project, so it beats the one this project saved; with none, the project's saved answer (the dashboard's: this
# machine's file) runs as it did before 0.22.0, and with neither, the reader's old default. What this pins, for one
# boolean (ponytail), one picker (builderEffort) and one number (dashboardPort): each source present or absent, the
# source named, the readers taking the /config answer, another plugin's options and the project's own settings files
# never read, a /config answer the reader would not take refused, and setup's pre-fill writing only missing keys.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
git init -q -b main "$T/p" && mkdir -p "$T/p/.claude" "$T/home/.claude" "$T/home/.commandeck/install"
P=$T/p/.claude/commandeck.json M=$T/home/.commandeck/install/_machine.json S=$T/home/.claude/settings.json
# L <shell> -- the shell runs in the project with paths.sh and install-lib.sh loaded, as doctor.sh and setup.sh run.
L() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u CLAUDE_CONFIG_DIR -u COMMANDECK_REVIEW_LOOP HOME="$T/home" \
  bash -c '. "$0/paths.sh" && . "$0/install-lib.sh" && eval "$1"' "$REAL/scripts" "$1" 2>&1); }
# O <key> -- "<value>|<source>" as the doctor reports it.
O() { L "echo \"\$(pp_option $1)|\$(pp_option $1 source)\""; }
conf() { jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: $o}, "other@elsewhere": {options: {ponytail: true, builderEffort: "max"}}}}' > "$S"; }
echo '{"version": 1, "profile": "claude"}' > "$P"; echo '{}' > "$S"

check "boolean: with no answer anywhere, the reader's old default" "false|default" "$(O ponytail)"
check "picker: with no answer anywhere, none (the routing file's own)" "|default" "$(O builderEffort)"
check "number: with no answer anywhere, none (setup's first free port)" "|default" "$(O dashboardPort)"
check "another plugin's options are never read" "false|default" "$(conf '{}'; O ponytail)"

# The format 0.21.0 deployed: the answers in the project file, the dashboard's in the machine file.
jq '. + {ponytail: true, builder: {effort: "high"}}' "$P" > "$T/x" && mv "$T/x" "$P"; echo '{"dashboard": {"bind": "127.0.0.1", "port": "8795"}}' > "$M"
check "boolean: the project's saved answer, with no /config one" "true|$P" "$(O ponytail)"
check "picker: the project's saved answer, with no /config one" "high|$P" "$(O builderEffort)"
check "number: the machine's saved port, with no /config one" "8795|$M" "$(O dashboardPort)"
check "and the Builder's launch takes the project's effort, as before 0.22.0" high "$(L 'pp_route_json builder | jq -r .effort')"

conf '{"ponytail": false, "builderEffort": "low", "dashboardPort": 8800}'
check "boolean: a /config false beats the project's true" "false|/config" "$(O ponytail)"
check "picker: the /config answer beats the project's" "low|/config" "$(O builderEffort)"
check "number: the /config port beats the machine's" "8800|/config" "$(O dashboardPort)"
check "the Builder's launch takes the /config effort" low "$(L 'pp_route_json builder | jq -r .effort')"
# Issue 293: the model and effort pickers default to "project", which /config's dialog may save untouched; it is no
# answer, so the project's saved one runs (a fixed "medium" there hid a Sonnet project's "high").
conf '{"builderEffort": "project"}'
check "picker: a /config 'project' is no answer, the project's saved one runs" "high|$P" "$(O builderEffort)"
conf '{"builderEffort": "low", "dashboardPort": 8800}'
check "a CLAUDE_CONFIG_DIR's settings file is the one read" "8795|machine" \
  "$(mkdir -p "$T/cd" && echo '{}' > "$T/cd/settings.json" && L "export CLAUDE_CONFIG_DIR=$T/cd"'; echo "$(pp_option dashboardPort)|$(pp_option dashboardPort source)"' | sed "s#|$M#|machine#")"

jq '. + {reviewLoop: {closingPass: "no", maxRounds: "5"}}' "$P" > "$T/x" && mv "$T/x" "$P"
check "the review loop reads the project's answers with no /config ones" "no 5" "$(L 'echo $(pp_review_loop closingPass yes "^(yes|no)$") $(pp_review_loop maxRounds "" "^[1-9][0-9]*$")')"
conf '{"closingPass": true, "maxReviewRounds": 3}'
check "and takes /config's: a closing pass runs, three rounds" "yes 3" "$(L 'echo $(pp_review_loop closingPass yes "^(yes|no)$") $(pp_review_loop maxRounds "" "^[1-9][0-9]*$")')"
conf '{"maxReviewRounds": 0}'
OUT=$(L 'pp_review_loop maxRounds "" "^[1-9][0-9]*$"; echo "rc=$?"')
check "a /config number the review loop does not take is refused, and says where it is" "rc=1 1" "$(tail -1 <<<"$OUT") $(grep -c 'maxReviewRounds = "0" in /config' <<<"$OUT")"
conf '{"promptCacheTtl": "leave"}'; jq '. + {cacheTtl: "5m"}' "$P" > "$T/x" && mv "$T/x" "$P"
check "a /config 'leave' is an answer, though the project saved 5m" "leave|/config" "$(O promptCacheTtl)"
# Issue 256: the Builder cap has no setup question; an owner sets it in /config, or by hand in the project's file.
check "the Builder cap: none anywhere is no cap" "|default" "$(O maxBuilders)"
jq '.builder.maxBuilders = 4' "$P" > "$T/x" && mv "$T/x" "$P"
check "the Builder cap: the project's hand-written one, with no /config answer" "4|$P" "$(O maxBuilders)"
check "the Builder cap: /config's beats the project's" "2|/config" "$(conf '{"maxBuilders": 2}'; O maxBuilders)"
conf '{"promptCacheTtl": "leave"}'
# A worker pane's settings: worktree-setup.sh writes the 5m only when the answer that runs is 5m.
git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first && git -C "$T/p" worktree add -q --detach "$T/w"
ttl() { (cd "$T/w" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u CLAUDE_CONFIG_DIR HOME="$T/home" bash "$REAL/scripts/worktree-setup.sh" "$T/w" --builder --print-settings 2>/dev/null) | jq -r '.env.CLAUDE_CODE_PROMPT_CACHE_TTL // "none"'; }
check "a worker pane follows /config's leave over the project's 5m" none "$(ttl)"
check "and the project's 5m with no /config answer" 5m "$(conf '{}'; ttl)"

# Setup's pre-fill: the owner's answers go into /config only where it has none; a /config answer that differs is named.
conf '{"builderEffort": "low"}'
OUT=$(L 'il_plugin_options "$HOME/.claude/settings.json" "{\"builderEffort\": \"high\", \"ponytail\": true, \"dashboardPort\": 8791}"')
check "pre-fill writes the missing keys and keeps the owner's /config answer" '{"builderEffort":"low","ponytail":true,"dashboardPort":8791}' \
  "$(jq -c '.pluginConfigs["commandeck@commandeck"].options' "$S")"
check "and names the /config answer that beats this setup's" 1 "$(grep -c 'builderEffort is low in /config, which beats this answer (high)' <<<"$OUT")"
check "another plugin's options stay as they were" '{"ponytail":true,"builderEffort":"max"}' "$(jq -c '.pluginConfigs["other@elsewhere"].options' "$S")"
conf '{"builderEffort": "project", "builderModel": "project"}'
OUT=$(L 'il_plugin_options "$HOME/.claude/settings.json" "{\"builderEffort\": \"high\"}"')
check "pre-fill writes setup's answer over a /config 'project', drops the other, and names no conflict" '{"builderEffort":"high"} 0' \
  "$(jq -c '.pluginConfigs["commandeck@commandeck"].options' "$S") $(grep -c 'in /config, which beats' <<<"$OUT")"
echo '{"enabledPlugins": {"commandeck@mirror": true}}' > "$S"; L 'il_plugin_options "$HOME/.claude/settings.json" "{\"ponytail\": false}"' >/dev/null
check "the plugin's key is the one it is enabled under" '{"ponytail":false}' "$(jq -c '.pluginConfigs["commandeck@mirror"].options' "$S")"
check "and that is the one read" "false|/config" "$(O ponytail)"
# A disabled install's options left in settings are not the running plugin's: reader and pre-fill take the enabled key.
echo '{"enabledPlugins":{"commandeck@a-old":false,"commandeck@commandeck":true},"pluginConfigs":{"commandeck@a-old":{"options":{"fullSuiteBeforeFinal":false}},"commandeck@commandeck":{"options":{"fullSuiteBeforeFinal":true}}}}' > "$S"
check "a disabled install's /config answer is not read over the enabled one's" "true|/config" "$(O fullSuiteBeforeFinal)"
L 'il_plugin_options "$HOME/.claude/settings.json" "{\"ponytail\": false}"' >/dev/null
check "and pre-fill writes under the enabled key, not the disabled one" '{"fullSuiteBeforeFinal":true,"ponytail":false}|{"fullSuiteBeforeFinal":false}' \
  "$(jq -cS '.pluginConfigs["commandeck@commandeck"].options, .pluginConfigs["commandeck@a-old"].options' "$S" | paste -sd'|' -)"

# Uninstall takes out only what pre-fill added, while it still holds setup's value: the owner's /config answers stay.
mkdir -p "${M%/*}" && echo '{"version": 1, "entries": {}}' > "$M"
echo '{"theme":"dark","pluginConfigs":{"commandeck@commandeck":{"options":{"builderEffort":"low"}}}}' > "$S"
L 'il_plugin_options "$HOME/.claude/settings.json" "{\"builderEffort\": \"high\", \"ponytail\": true, \"dashboardPort\": 8791}"' >/dev/null
jq '.pluginConfigs["commandeck@commandeck"].options.dashboardPort = 9000' "$S" > "$T/x" && mv "$T/x" "$S"
L 'il_plugin_options_out "$IL_MACHINE" "$HOME/.claude/settings.json"'
check "uninstall takes out the option pre-fill added, keeps the owner's own and the one they changed since" \
  '{"pluginConfigs":{"commandeck@commandeck":{"options":{"builderEffort":"low","dashboardPort":9000}}},"theme":"dark"}' "$(jq -cS . "$S")"
echo '{"theme":"dark"}' > "$S"; L 'il_plugin_options "$HOME/.claude/settings.json" "{\"ponytail\": true}" && il_plugin_options_out "$IL_MACHINE" "$HOME/.claude/settings.json"' >/dev/null
check "a pluginConfigs pre-fill made goes with it, and the record too" '{"theme":"dark"}:null' "$(jq -c . "$S"):$(jq -c '.entries[] | .options' "$M")"

echo "plugin-option: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
