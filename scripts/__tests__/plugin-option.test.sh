#!/usr/bin/env bash
# plugin-option.test.sh -- the plugin's /config options (issue 245). An answer set in /config is the owner's for every
# project, so it beats the one this project saved; with none, the project's saved answer (the dashboard's: this
# machine's file) runs as it did before 0.22.0, and with neither, the reader's old default; a role key (issue 312) reads
# /config alone. What this pins, for one
# picker with a validated value (ponytail, a level), one picker (builderEffort) and one number (dashboardPort): each source present or absent, the
# source named, the readers taking the /config answer, another plugin's options and the project's own settings files
# never read, a /config answer the reader would not take refused, and setup's pre-fill writing only missing keys
# and the answers given this run.
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

check "level: with no answer anywhere, lite" "lite|default" "$(O ponytail)"
check "picker: with no answer anywhere, the routing file's own, as the doctor shows it" "high|default" "$(O builderEffort)"
check "number: with no answer anywhere, none (setup's first free port)" "|default" "$(O dashboardPort)"
check "another plugin's options are never read" "lite|default" "$(conf '{}'; O ponytail)"

# The format 0.21.0 deployed: the answers in the project file, the dashboard's in the machine file.
jq '. + {ponytail: "ultra", builder: {effort: "medium"}}' "$P" > "$T/x" && mv "$T/x" "$P"; echo '{"dashboard": {"bind": "127.0.0.1", "port": "8795"}}' > "$M"
check "level: the project's saved answer, with no /config one" "ultra|$P" "$(O ponytail)"
# A role key (issue 312) reads no answer from the project's file: builder.effort there is an older setup's, not read.
check "picker: a role key's project answer is not read, routing's own runs" "high|default" "$(O builderEffort)"
check "number: the machine's saved port, with no /config one" "8795|$M" "$(O dashboardPort)"
check "and the Builder's launch takes routing's effort, not the project's" high "$(L 'pp_route_json builder | jq -r .effort')"

conf '{"ponytail": "off", "builderEffort": "low", "dashboardPort": 8800}'
check "level: a /config off beats the project's ultra" "off|/config" "$(O ponytail)"
# Issue 330: each of the four levels is read as it is; the booleans an earlier setup saved in the project file read as
# off / lite; a project value that is no level takes the default rather than passing for a level.
for l in off lite full ultra; do check "level: a /config $l is read as $l" "$l|/config" "$(conf "{\"ponytail\": \"$l\"}"; O ponytail)"; done
cp "$P" "$T/P.keep"; conf '{}'
for v in false:off true:lite '"bogus":lite'; do
  jq --argjson v "${v%:*}" '.ponytail = $v' "$T/P.keep" > "$P"
  check "level: the project's saved ${v%:*} reads as ${v#*:}" "${v#*:}" "$(O ponytail | cut -d'|' -f1)"
done
cp "$T/P.keep" "$P"; conf '{"ponytail": "off", "builderEffort": "low", "dashboardPort": 8800}'
check "picker: the /config answer runs" "low|/config" "$(O builderEffort)"
check "number: the /config port beats the machine's" "8800|/config" "$(O dashboardPort)"
check "the Builder's launch takes the /config effort" low "$(L 'pp_route_json builder | jq -r .effort')"
# Issue 293: the model and effort pickers default to "project", which /config's dialog may save untouched; it is no
# answer, so routing's own runs.
conf '{"builderEffort": "project"}'
check "picker: a /config 'project' is no answer, routing's own runs" "high|default" "$(O builderEffort)"
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

# Issue 312: each role's settings are /plugin keys, read by one checked reader for every launch.
R() { L "pp_route_json $1 | jq -r '$2'"; }
conf '{"planAuthorModel": "sonnet", "builderModel": "sonnet", "codexReviewerAgent": "codex", "codexReviewerModel": "gpt-6.1-astra"}'
check "a Claude role set in /plugin resolves to it, and its launch line runs it" "sonnet claude --model sonnet --effort high|sonnet" \
  "$(R plan-author '"\(.model) \(.cmd | sub("^[A-Z_]+=1 "; ""))"')|$(R builder .model)"
check "a Codex role set in /plugin resolves to it" gpt-6.1-astra "$(R codex-reviewer .model)"
check "an unset key keeps routing's default" "high medium" "$(R plan-author .effort) $(R codex-reviewer .effort)"
conf '{"fixerEffort": "huge"}'
check "an effort a role does not take is refused naming the key and the role" 1 "$(L 'pp_route_json fixer' | grep -c '^REFUSED: /plugin config fixerEffort = huge is not a claude effort for fixer')"
conf '{"planAuthorModel": "gpt-6.1-sol"}'
check "a Codex model on a Claude role is refused, not run on a fallback" 1 "$(L 'pp_route_json plan-author; echo "rc=$?"' | grep -c 'rc=2')"
# A plugin update replaces config/routing.json; the key lives in the user's settings file, so it outlives the copy.
conf '{"planAuthorModel": "sonnet"}'; cp "$REAL/config/routing.json" "$T/routing.json"
check "a replaced routing file keeps the /plugin value" sonnet "$(L "export COMMANDECK_ROUTING=$T/routing.json; pp_route_json plan-author | jq -r .model")"
# A seat's settings follow the agent chosen: the row when it is on that agent, else the owner's claude overlay for
# Claude, else the plugin's own row for that agent. A Codex row with no claude overlay has no Claude choice (a routing
# file before 0.26.0 is not read as one with the plugin's overlay).
# Owner rows: Codex as shipped, or Claude on opus max; an owner overlay on fable low.
own() { # <row agent> <overlay yes|no> -- an owner routing file in $T/own-routing.json
  jq --arg a "$1" --arg ov "$2" '.roles |= with_entries(if (.key | IN("codex-reviewer", "plan-judge-sol", "plan-judge-astra")) then
      .value |= (.claude as $c
        | if $a == "claude" then {agent: "claude", model: "opus", effort: "max", tools: $c.tools, edits, note}
            + (if $c.headless then {headless: true} else {reviewer: true, unboxed: true} end) else . end
        | if $ov == "yes" then .claude = ($c + {model: "fable", effort: "low"}) else del(.claude) end)
    else . end)' "$REAL/config/routing.json" > "$T/own-routing.json"; }
seats() { L "export COMMANDECK_ROUTING=$T/own-routing.json; for r in codex-reviewer plan-judge-sol plan-judge-astra; do
  j=\$(pp_route_json \$r 2>/dev/null) && jq -r '\"\(.agent) \(if .agent == \"claude\" then .model else \"-\" end) \(.effort)\"' <<<\"\$j\" || echo refused; done" | paste -sd '|' -; }
keys() { [ "$1" = none ] && conf '{}' || conf "{\"codexReviewerAgent\": \"$1\", \"planJudgeSolAgent\": \"$1\", \"planJudgeAstraAgent\": \"$1\"}"; }
SHIPPED='codex - medium|codex - high|codex - high' OPUS='claude opus max|claude opus max|claude opus max'
cp "$P" "$T/P.keep"; jq '.profile = "claude-openai"' "$T/P.keep" > "$P"
mkdir -p "$T/home/.codex"; echo '{"models": [{"slug": "gpt-6.1-sol"}, {"slug": "gpt-6.1-astra"}]}' > "$T/home/.codex/models_cache.json"
while read -r row ov key want; do
  own "$row" "$ov"; keys "$key"
  case $want in shipped) want=$SHIPPED ;; opus) want=$OPUS ;; fable) want='claude fable low|claude fable low|claude fable low' ;;
    refused) want='refused|refused|refused' ;; esac
  check "a $row row, overlay $ov, Agent key $key: the seat for that agent" "$want" "$(seats)"
done <<'TABLE'
codex yes none shipped
codex yes codex shipped
codex yes claude fable
codex no none shipped
codex no codex shipped
codex no claude refused
claude yes none opus
claude yes codex shipped
claude yes claude opus
claude no none opus
claude no codex shipped
claude no claude opus
TABLE
# A Codex model id with more hyphenated parts is still a model id.
check "a Codex model id with more hyphenated parts in its key runs" gpt-5.3-codex-spark "$(conf '{"codexReviewerModel": "gpt-5.3-codex-spark"}'; R codex-reviewer .model)"
mv "$T/P.keep" "$P"; conf '{}'; rm -r "$T/home/.codex"
# A Claude model is one of the fixed list, whatever the owner's routing names: haiku there is not a model key's value.
jq '.roles.builder.model = "haiku"' "$REAL/config/routing.json" > "$T/h-routing.json"
HR() { L "export COMMANDECK_ROUTING=$T/h-routing.json; $1"; }
check "haiku in the Builder's key is refused, though the owner's routing names it" 1 "$(conf '{"builderModel": "haiku"}'; HR 'pp_route_json builder; echo "rc=$?"' | grep -c '^rc=2$')"
check "and the Builder launch check refuses it" 1 "$(conf '{}'; HR 'pp_builder_model_ok haiku' | grep -c '^REFUSED: --model haiku is not one of opus, sonnet, fable$')"
# Class caller-mismatch (r5): a row that holds candidates has its agent on each candidate; every reader resolves the
# candidate first (the agent, the model key's check, a Codex family).
jq '.roles.builder = {edits: true, candidates: [{agent: "claude", model: "sonnet", effort: "medium", unboxed: true}]}
  | .roles["plan-judge-sol"] |= {edits, candidates: [del(.claude, .first, .edits, .note) + {model: "astra"}]}' "$REAL/config/routing.json" > "$T/c-routing.json"
CR() { L "export COMMANDECK_ROUTING=$T/c-routing.json; $1"; }
conf '{}'
check "a Claude candidate route resolves on its candidate's agent" "claude sonnet" "$(CR "pp_route_json builder.0 | jq -r '\"\(.agent) \(.model)\"'")"
check "and takes its model key" opus "$(conf '{"builderModel": "opus"}'; CR 'pp_route_json builder.0 | jq -r .model')"
check "the doctor shows a candidate row's model, not none" sonnet "$(conf '{}'; cp "$P" "$T/P.keep"; jq 'del(.builder)' "$T/P.keep" > "$P"; CR 'pp_option builderModel'; mv "$T/P.keep" "$P")"
cp "$P" "$T/P.keep"; jq '.profile = "claude-openai"' "$T/P.keep" > "$P"; conf '{}'
mkdir -p "$T/home/.codex"; echo '{"models": [{"slug": "gpt-6.1-sol"}, {"slug": "gpt-6.1-astra"}]}' > "$T/home/.codex/models_cache.json"
check "a Codex candidate route resolves its candidate's model family" gpt-6.1-astra "$(CR 'pp_route_json plan-judge-sol.0 | jq -r .model')"
# Class caller-mismatch (r7): a role key on a row whose candidates run on two agents is checked on the candidate named.
# Each key is set, then taken out, between two runs of one candidate: the seat stays on that candidate's agent.
jq '.roles["plan-judge-sol"] = {edits: false, candidates: [{agent: "claude", model: "sonnet", effort: "high", unboxed: true},
  {agent: "codex", model: "gpt-6.1-sol", effort: "high", unboxed: true, sandbox: "read-only"}]}' "$REAL/config/routing.json" > "$T/m-routing.json"
MR() { L "export COMMANDECK_ROUTING=$T/m-routing.json; pp_route_json $1 | jq -r '\"\(.agent) \(.model) \(.effort)\"'"; }
while read -r spec key want; do
  check "mixed candidates: $spec with $key" "$want" "$(conf "$key"; MR "$spec")"
  check "and with the key taken out, still on its agent" "${want%% *}" "$(conf '{}'; MR "$spec" | cut -d' ' -f1)"
done <<'TABLE'
plan-judge-sol.0 {"planJudgeSolEffort":"medium"} claude sonnet medium
plan-judge-sol.1 {"planJudgeSolEffort":"medium"} codex gpt-6.1-sol medium
plan-judge-sol.0 {"planJudgeSolModel":"opus"} claude opus high
plan-judge-sol.1 {"planJudgeSolModel":"gpt-6.1-astra"} codex gpt-6.1-astra high
TABLE
check "a Claude model key on the Codex candidate is refused" 1 "$(conf '{"planJudgeSolModel":"opus"}'; MR plan-judge-sol.1 2>&1 | grep -c 'REFUSED: /plugin config planJudgeSolModel = opus is not a codex model')"
check "a model key on the bare mixed role is refused, naming the index" 1 "$(conf '{"planJudgeSolModel":"opus"}'; MR plan-judge-sol 2>&1 | grep -c 'name one as plan-judge-sol.<index>')"
conf '{}'
mv "$T/P.keep" "$P"; rm -r "$T/home/.codex"
# A Claude seat denied only Write still edits: the overlay must deny Write, Edit and NotebookEdit, and only that is read-only.
jq '.roles["plan-judge-sol"].claude.tools = ["Write"]' "$REAL/config/routing.json" > "$T/w-routing.json"
check "a claude overlay denying only Write is refused" 1 "$(L "COMMANDECK_ROUTING=$T/w-routing.json pp_routing_valid" | grep -c 'plan-judge-sol.claude must deny Write, Edit and NotebookEdit')"
jq '.roles["plan-author"].tools = ["Write"]' "$REAL/config/routing.json" > "$T/w-routing.json"; conf '{}'
check "a seat denied only Write is not read-only" false "$(L "export COMMANDECK_ROUTING=$T/w-routing.json; pp_route_json plan-author | jq -r .readonly")"
# Classes incomplete-write-denial and caller-mismatch (r3): a Claude seat the owner wrote for a reviewer or judge, as its
# row or its overlay, keeps the contract of the overlay the plugin ships: Write, Edit and NotebookEdit denied, and its
# shape (the reviewer headless for builder-codex-pass.sh, the judges panes for plan-tier.sh). Its model and effort stay.
direct() { # <jq on each of the three rows> -- "<model> <effort> <readonly> <shape>" per seat
  jq "$1" "$REAL/config/routing.json" > "$T/d-routing.json"
  L "export COMMANDECK_ROUTING=$T/d-routing.json; for r in codex-reviewer plan-judge-sol plan-judge-astra; do
    pp_route_json \$r | jq -r '\"\(.model) \(.effort) \(.readonly) \(if .argv then \"headless\" else \"pane\" end)\"' || echo refused; done" | paste -sd '|' -; }
seven() { printf '.roles |= with_entries(if (.key | IN("codex-reviewer", "plan-judge-sol", "plan-judge-astra")) then .value |= (%s) else . end)' "$1"; }
CONTRACT='opus high true headless|opus high true pane|opus high true pane'
conf '{}'
check "a pane-shaped Claude row denying only Write: each seat denies all three and has its shape" "$CONTRACT" \
  "$(direct "$(seven '{agent: "claude", model: "opus", effort: "high", unboxed: true, edits: false, tools: ["Write"]}')")"
check "a headless Claude row denying nothing: each seat denies all three and has its shape" "$CONTRACT" \
  "$(direct "$(seven '{agent: "claude", headless: true, model: "opus", effort: "high", edits: false}')")"
conf '{"codexReviewerAgent": "claude", "planJudgeSolAgent": "claude", "planJudgeAstraAgent": "claude"}'
check "a pane-shaped owner overlay: each seat has its shape" "$CONTRACT" \
  "$(direct "$(seven '.claude = {model: "opus", effort: "high", unboxed: true, tools: ["Write", "Edit", "NotebookEdit"]}')")"
check "a headless owner overlay: each seat has its shape" "$CONTRACT" \
  "$(direct "$(seven '.claude = {headless: true, model: "opus", effort: "high", tools: ["Write", "Edit", "NotebookEdit"]}')")"
conf '{}'

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
# Issue 312: an answer given this run (--option, or a profile's agent keys) is a change the owner asked for, so it
# replaces the /config value; a key setup was not given keeps its value, and only what had none is setup's to take out.
mkdir -p "${M%/*}" && echo '{"version": 1, "entries": {}}' > "$M"
conf '{"fixerEnabled": false, "codexReviewerModel": "gpt-6.1-astra"}'
OUT=$(L 'il_plugin_options "$HOME/.claude/settings.json" "{\"codexReviewerModel\": \"gpt-6.1-sol\"}" "{\"fixerEnabled\": true, \"fixerFirstModel\": \"opus\"}"')
check "a rerun's given answers replace the /config ones, and a key not given keeps its value" '{"codexReviewerModel":"gpt-6.1-astra","fixerEnabled":true,"fixerFirstModel":"opus"}' \
  "$(jq -cS '.pluginConfigs["commandeck@commandeck"].options' "$S")"
check "only the fill answer /config beats is named" "1 0" "$(grep -c 'codexReviewerModel is gpt-6.1-astra in /config, which beats' <<<"$OUT") $(grep -c 'fixerEnabled is' <<<"$OUT")"
check "uninstall would take out only the key that had no value" '{"fixerFirstModel":"opus"}' "$(jq -c --arg s "$S" '.entries[$s].options["commandeck@commandeck"]' "$M")"
# A role key given this run lives only in the user settings file, so with none the pre-fill makes one; it was setup's,
# so the record says so and uninstall takes out the options it added.
rm "$S"; echo '{"version": 1, "entries": {}}' > "$M"; L 'il_plugin_options "$HOME/.claude/settings.json" "{}" "{\"builderModel\": \"sonnet\"}"' >/dev/null
check "pre-fill with no user settings file creates it for a given answer, recorded as setup's" '{"builderModel":"sonnet"}|{"builderModel":"sonnet"}' \
  "$(jq -c '.pluginConfigs["commandeck@commandeck"].options' "$S" 2>&1)|$(jq -c --arg s "$S" '.entries[$s].options["commandeck@commandeck"]' "$M")"
echo '{"enabledPlugins": {"commandeck@mirror": true}}' > "$S"; L 'il_plugin_options "$HOME/.claude/settings.json" "{\"ponytail\": \"off\"}"' >/dev/null
check "the plugin's key is the one it is enabled under" '{"ponytail":"off"}' "$(jq -c '.pluginConfigs["commandeck@mirror"].options' "$S")"
check "and that is the one read" "off|/config" "$(O ponytail)"
# A disabled install's options left in settings are not the running plugin's: reader and pre-fill take the enabled key.
echo '{"enabledPlugins":{"commandeck@a-old":false,"commandeck@commandeck":true},"pluginConfigs":{"commandeck@a-old":{"options":{"fullSuiteBeforeFinal":false}},"commandeck@commandeck":{"options":{"fullSuiteBeforeFinal":true}}}}' > "$S"
check "a disabled install's /config answer is not read over the enabled one's" "true|/config" "$(O fullSuiteBeforeFinal)"
L 'il_plugin_options "$HOME/.claude/settings.json" "{\"ponytail\": \"off\"}"' >/dev/null
check "and pre-fill writes under the enabled key, not the disabled one" '{"fullSuiteBeforeFinal":true,"ponytail":"off"}|{"fullSuiteBeforeFinal":false}' \
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
