#!/usr/bin/env bash
# setup.sh reads --install-missing (the owner's yes to installing tools) in a first loop, before the full parse.
# That loop skips the value of every option in TAKES, so `--name --install-missing` is a value, never a yes. An
# option the full parse takes a value for but TAKES lacks (a typo, two names run together) lets its value grant
# installation. This holds every value-taking option in the full parse to that rule, by running the first loop.
set -uo pipefail
SETUP=$(cd "$(dirname "$0")/.." && pwd)/setup.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

PRE=$(sed -n '/^TAKES=/,/^done/p' "$SETUP")
# The full parse's labels; a branch that ends `shift ;;` on its line takes no value.
OPTS=$(sed -n '/^while \[ \$# -gt 0 \]/,/^done/p' "$SETUP" | grep -vE 'shift ;;' \
  | grep -oE '^[[:space:]]+--[a-z-]+(\|--[a-z-]+)*\)' | tr -d ' )' | tr '|' '\n')
check "the full parse names value-taking options" true "$([ "$(wc -l <<<"$OPTS")" -gt 30 ] && echo true || echo false)"
GRANTED=
for o in $OPTS; do
  # shellcheck disable=SC2034 # the first loop reads INSTALL
  GRANTED+=$(set -- "$o" --install-missing; eval "$PRE"; [ -z "$INSTALL" ] || echo " $o")
done
check "no option's value is read as --install-missing" '' "$GRANTED"
GRANTED=$(set -- --profile claude --install-missing; eval "$PRE"; echo "$INSTALL")
check "a real --install-missing after a value is still the owner's yes" 1 "$GRANTED"

# Issue 333: setup rebuilds commandeck.json from what it carries over. The owner's never-decide list is theirs and
# setup asks nothing about it, so a re-run (and update.sh, which runs setup) must carry it over as saved.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
IL_CONFIG=$T/commandeck.json; echo '{"version":1,"autoDecideNever":["touching the billing config","a new vendor"],"workerSkillsOff":["x"]}' > "$IL_CONFIG"
eval "$(grep '^CUTS=' "$SETUP")"
check "an autoDecideNever list in commandeck.json is carried over by a setup re-run, beside the worker cuts" \
  '["touching the billing config","a new vendor"]:["x"]' "$(jq -c .autoDecideNever <<<"$CUTS"):$(jq -c .workerSkillsOff <<<"$CUTS")"
# Issue 431: the owner's keep list rides the same way. An explicit empty list must survive too: dropped, it would read
# as a missing key, which keeps the standing worktrees the owner chose not to keep.
for k in '["Fast-lane"]' '[]'; do
  echo "{\"version\":1,\"keepWorktrees\":$k}" > "$IL_CONFIG"; eval "$(grep '^CUTS=' "$SETUP")"
  check "a keepWorktrees list $k is carried over by a setup re-run as saved" "$k" "$(jq -c .keepWorktrees <<<"$CUTS")"
done
echo '{"version":1}' > "$IL_CONFIG"; eval "$(grep '^CUTS=' "$SETUP")"
check "with none saved, none is invented" '{}' "$CUTS"

# Issue 374: an On the owner asked for must not vanish. setup.sh's own answer functions run on hand-written values.
# /config is read the way setup reads it: paths.sh's own pp_config_option, over a hand-made settings.json (CFG).
PATHS=$(cd "$(dirname "$SETUP")" && pwd)/paths.sh
CFGFNS=$(sed -n "/^PP_OPTS_KEY=/,/;'\$/p;/^pp_config_option()/,/^}/p" "$PATHS")
FNS=$(sed -n '/^given()/p;/^full_suite_answer()/,/^}/p;/^full_suite_rule()/,/^}/p' "$SETUP")
cfg() { mkdir -p "$T/cfg"; printf '%s' "$1" > "$T/cfg/settings.json"; }
fs() { (die() { echo "setup: $*" >&2; exit 1; }; eval "$CFGFNS"; eval "$FNS"; export CLAUDE_CONFIG_DIR=$T/cfg; CFG=${CFG:-'{}'}; cfg "$CFG"
  GIVEN='{}' FULL_ASKED= FULL_OFF_NOTE=; eval "$1"; echo "FULL=$FULL OFFNOTE=$FULL_OFF_NOTE GIVEN=$GIVEN") 2>&1; }
OUT=$(fs 'TEST= FULL=; full_suite_answer on; full_suite_rule')
check "--full-suite on with no test command refuses, naming the merge check" "1:1" \
  "$(grep -c 'needs a merge check' <<<"$OUT"):$(grep -c 'Nothing was changed' <<<"$OUT")"
# "writes nothing": the refusal stands before setup's first write (the manifest, at il_profile_lock).
check "the refusal comes before the first write" true \
  "$([ "$(grep -n '^full_suite_rule$' "$SETUP" | cut -d: -f1)" -lt "$(grep -n 'il_profile_lock 60' "$SETUP" | head -1 | cut -d: -f1)" ] && echo true || echo false)"
check "--full-suite on with a test command is kept, and handed to /config as this run's answer" "FULL=true OFFNOTE= GIVEN={\"fullSuiteBeforeFinal\":true}" \
  "$(fs 'TEST="npm test" FULL=; full_suite_answer on; full_suite_rule')"
check "a saved On with no test command is set off, noted, and handed to /config as off" "FULL=false OFFNOTE=1 GIVEN={\"fullSuiteBeforeFinal\":false}" \
  "$(fs 'TEST= FULL=true; full_suite_rule')"
# /config beats the project's file, so the rule reads the setting the way the closing pass will.
CFG_ON='{"enabledPlugins":{"commandeck@commandeck":true},"pluginConfigs":{"commandeck@commandeck":{"options":{"fullSuiteBeforeFinal":true}}}}'
CFG_OFF=${CFG_ON/:true\}\}\}\}/:false\}\}\}\}}
check "a project false under a /config On with no test command is set off, noted, and handed to /config as off" "FULL=false OFFNOTE=1 GIVEN={\"fullSuiteBeforeFinal\":false}" \
  "$(CFG=$CFG_ON fs 'TEST= FULL=false; full_suite_rule')"
check "a saved On in both places (the existing case, now with /config holding it too) is set off and noted once" "FULL=false OFFNOTE=1 GIVEN={\"fullSuiteBeforeFinal\":false}" \
  "$(CFG=$CFG_ON fs 'TEST= FULL=true; full_suite_rule')"
check "a project true under a /config Off needs no override and no note" "FULL=false OFFNOTE= GIVEN={}" \
  "$(CFG=$CFG_OFF fs 'TEST= FULL=true; full_suite_rule')"
check "this run's --full-suite off beats a /config On: no second note" "FULL=false OFFNOTE= GIVEN={\"fullSuiteBeforeFinal\":false}" \
  "$(CFG=$CFG_ON fs 'TEST= FULL=; full_suite_answer off; full_suite_rule')"
check "with a test command the /config On is left alone" "FULL=false OFFNOTE= GIVEN={}" \
  "$(CFG=$CFG_ON fs 'TEST="npm test" FULL=false; full_suite_rule')"
check "and the plan and the summary print that note" 1 \
  "$(grep -c '^\[ -z "\$FULL_OFF_NOTE" \] || NOTES+=("Full suite before the final review: off, as no merge check command is set")$' "$SETUP")"
check "and the summary line reads the setting in force (/config's), not the project's file alone" 1 \
  "$(grep -c 'echo "full suite before the final review: $(\[ "$FULL_ON" = true \]' "$SETUP")"
check "where FULL_ON is /config's answer, this run's counted, else the project's" 1 \
  "$(grep -c '^FULL_ON=$(COMMANDECK_OPTIONS=$GIVEN pp_config_option fullSuiteBeforeFinal || echo "$FULL")$' "$SETUP")"
check "--full-suite off with no test command is no refusal" "FULL=false OFFNOTE= GIVEN={\"fullSuiteBeforeFinal\":false}" \
  "$(fs 'TEST= FULL=; full_suite_answer off; full_suite_rule')"

# The recommended profile and --option's checks: setup.sh's own functions, run on the shipped profile and manifest.
REC_FNS=$(sed -n '/^REC_FILE=/p;/^WAKE_KINDS=/p;/^rec_agent()/,/^}/p;/^rec_skip()/,/^}/p;/^rec_expand()/,/^}/p;/^rec_takes()/,/^}/p;/^opt_flag()/,/^}/p;/^opt_check()/,/^}/p' "$SETUP")
ROOT=$(cd "$(dirname "$SETUP")/.." && pwd)
# The answer handlers a profile pair reaches by its own flag are setup.sh's own case lines, so a pair is saved the way a flag saves it.
ANSWER="answer() { case \$1 in
$(grep -E '^    --(main-cache-ttl|worker-cache-ttl|relay-cache-ttl|block-at|pass-cap|fresh-closing|closing-pass|full-suite)\)' "$SETUP")
  *) return 1 ;; esac; }"
RL_FNS=$(sed -n "/^rl()/,/<<<\"\$RL\"); }/p;/^given()/p;/^INT=/p;/^full_suite_answer()/,/^}/p" "$SETUP")
rec() { (die() { echo "setup: $*" >&2; exit 1; }; usage() { echo "usage" >&2; return 1; }; IL_ROOT=$ROOT; FASTOK=${FASTOK:-0}; pp_codex_fast_home() { return "$FASTOK"; }
  eval "$CFGFNS"; export CLAUDE_CONFIG_DIR=$T/cfg; CFG=${CFG:-'{}'}; cfg "$CFG"
  eval "$REC_FNS"; eval "$RL_FNS"; eval "$ANSWER"
  PROFILE=${PROFILE:-claude-openai} ASKED=${ASKED:-} AGENTS=${AGENTS:-} RL='{}' GIVEN='{}' EXP=() REC_SKIPPED=(); eval "$1") 2>&1; }
NKEYS=$(jq '.options | length' "$ROOT/config/recommended.json")
# apply: what the --option branch does with each pair of the expansion (its own flag, or the manifest check), as GIVEN.
APPLY='set -- "${EXP[@]}"; while [ $# -gt 0 ]; do k=${2%%=*}; v=${2#*=}; if f=$(opt_flag "$k" "$v"); then answer $f; else GIVEN=$(jq -c --arg k "$k" --arg v "$v" ".[\$k] = \$v" <<<"$GIVEN"); opt_check "$k"; fi; shift 2; done'
check "setup --recommended on the Codex profile expands to every profile key and skips none" "$NKEYS 0" \
  "$(rec 'rec_expand; echo "$((${#EXP[@]} / 2)) ${#REC_SKIPPED[@]}"')"
# Expected values come from the profile file, not from this test: a pair that is lost, or saved as another type, shows.
REC_WANT=$(jq -c .options "$ROOT/config/recommended.json")
check "and every value passes the --option check, saved as the type its key has (a number, a boolean, a word)" '[]' \
  "$(rec "rec_expand; $APPLY"'; jq -c --argjson w "$REC_WANT" "[\$w | to_entries[] | select(\$g[.key] != .value) | .key]" --argjson g "$GIVEN" -n')"
check "the profile names a pass cap (a missing one would make the next check compare nothing with nothing)" number \
  "$(jq -r '.reviewPassCap | type' <<<"$REC_WANT")"
check "the pass cap the profile names is the one the --pass-cap handler saves" "$(jq -c .reviewPassCap <<<"$REC_WANT")" \
  "$(rec "rec_expand; $APPLY"'; jq -c .reviewPassCap <<<"$GIVEN"')"
check "and the redirected pairs reach the project's review loop too (cap, blocking severity)" \
  "$(jq -c '{passCap: (.reviewPassCap | tostring), blockAt: .reviewBlockSeverity}' <<<"$REC_WANT")" \
  "$(rec "rec_expand; $APPLY"'; jq -c "{passCap, blockAt}" <<<"$RL"')"
check "a Codex model in the profile is skipped and named on the Claude profile, and only those two" "2 1 1" \
  "$(rec 'PROFILE=claude; rec_expand; echo "${#REC_SKIPPED[@]} $(printf "%s\n" "${REC_SKIPPED[@]}" | grep -c "codexReviewerModel=gpt-6.1-sol skipped: the seat runs on Claude") $(printf "%s\n" "${REC_SKIPPED[@]}" | grep -c "planJudgeSolModel=gpt-6.1-sol skipped")"')"
# Pass 1 (effective-agent-mismatch): the seat's agent is the one the run ends with, not the profile's alone.
check "a Claude judge asked for on the Codex profile drops the Codex judge model, and keeps the reviewer's" "1 1 0" \
  "$(rec 'AGENTS=" planJudgeSolAgent=claude" ASKED=claude-openai; rec_expand; echo "${#REC_SKIPPED[@]} $(printf "%s\n" "${REC_SKIPPED[@]}" | grep -c "planJudgeSolModel=gpt-6.1-sol skipped: the seat runs on Claude") $(printf "%s\n" "${REC_SKIPPED[@]}" | grep -c "codexReviewerModel")"')"
check "a Codex judge asked for on the Claude profile keeps the Codex model" "1 0" \
  "$(rec 'AGENTS=" planJudgeSolAgent=codex" ASKED=claude; rec_expand; echo "${#REC_SKIPPED[@]} $(printf "%s\n" "${REC_SKIPPED[@]}" | grep -c "planJudgeSolModel")"')"
check "with no profile asked, the Agent key /config saved decides" "1" \
  "$(CFG='{"enabledPlugins":{"commandeck@commandeck":true},"pluginConfigs":{"commandeck@commandeck":{"options":{"planJudgeSolAgent":"claude"}}}}' rec 'PROFILE=claude-openai; rec_expand; printf "%s\n" "${REC_SKIPPED[@]}" | grep -c "planJudgeSolModel=gpt-6.1-sol skipped"')"
check "a Codex fast tier the Codex home cannot take is skipped and named (the profile's fast tiers are off, so a hand-written On)" "1 0" \
  "$(rec 'FASTOK=1; rec_skip codexReviewerFast true | grep -c "service_tier"; FASTOK=0; rec_skip codexReviewerFast true | wc -l | tr -d " "' | paste -sd' ' -)"
check "a later --option beats --recommended: the profile's pairs come first, so the owner's pair is applied last" "off" \
  "$(rec "rec_expand; EXP+=(--option unitsBand=off); $APPLY"'; jq -r .unitsBand <<<"$GIVEN"')"
check "--option unitsBand=sometimes is refused naming auto, on, off" "1 1" \
  "$(OUT=$(rec 'GIVEN="{\"unitsBand\":\"sometimes\"}"; opt_check unitsBand'); echo "$(grep -c "takes auto, on, off, not 'sometimes'" <<<"$OUT") $(grep -c 'Nothing was changed' <<<"$OUT")")"
check "--option maxBuilders=0, a wake kind that is no kind, and a port under 1024 are each refused naming what the key takes" "1 1 1" \
  "$(for p in 'maxBuilders|0|a whole number from 1' 'wakeKinds|worker_done,nope|a comma list of: worker_done' 'dashboardPort|80|a whole number from 1024 to 65535'; do IFS='|' read -r k v t <<<"$p"
      rec "GIVEN='{\"$k\":\"$v\"}'; opt_check $k" | grep -c "takes $t"; done | paste -sd' ' -)"
check "--option takes only keys /plugin config lists" 1 "$(rec 'GIVEN="{\"noSuchKey\":\"x\"}"; opt_check noSuchKey' | grep -c 'takes a key /plugin config lists')"
check "a key with its own flag is answered by it: closingPass=true is --closing-pass yes, a bad boolean refuses" "--closing-pass yes|--full-suite off|2" \
  "$(rec 'echo "$(opt_flag closingPass true)|$(opt_flag fullSuiteBeforeFinal false)|$(opt_flag closingPass maybe >/dev/null 2>&1; echo $?)"')"
check "--questions begin has a takes list for every profile key" "$NKEYS 0" \
  "$(rec 'n=0; e=0; for k in $(jq -r ".options | keys[]" "$REC_FILE"); do t=$(rec_takes "$k"); n=$((n+1)); [ -n "$t" ] && [ "$t" != "any text" ] || e=$((e+1)); done; echo "$n $e"')"
check "and the begin branch prints those lines from the profile and the manifest" 1 \
  "$(grep -c 'recommended $k: $v (takes: $(rec_takes "$k"))' "$SETUP")"

# The dashboard's address is read once, before its job is installed: setup.sh's own two read lines, run over a saved
# 0.0.0.0:8791. An --option answer read after the install would save one address and serve the old one.
DASH_READ=$(grep -E '^! V=\$\(.*pp_config_option dashboard(Bind|Port)\) \|\| (BIND|PORT)=\$V$' "$SETUP")
CFG_DASH='{"enabledPlugins":{"commandeck@commandeck":true},"pluginConfigs":{"commandeck@commandeck":{"options":{"dashboardBind":"0.0.0.0","dashboardPort":8791}}}}'
dash() { CFG=$CFG_DASH rec "BIND=$1 PORT=$2; $DASH_READ"'; echo "$BIND:$PORT"'; }
check "setup.sh has the two read lines" 2 "$(grep -c . <<<"$DASH_READ")"
check "--option dashboardBind=127.0.0.1 --option dashboardPort=9999 over a saved 0.0.0.0:8791 is the address installed" "127.0.0.1:9999" \
  "$(CFG=$CFG_DASH rec 'GIVEN="{\"dashboardBind\":\"127.0.0.1\",\"dashboardPort\":\"9999\"}"; opt_check dashboardBind; opt_check dashboardPort; BIND= PORT=; '"$DASH_READ"'; echo "$BIND:$PORT"')"
check "with no --option the saved /config address stands" "0.0.0.0:8791" "$(dash '' '')"
check "the reads come before the install, which serves BIND and PORT, and il_plugin_options is handed this run's answers" "true 1" \
  "$([ "$(grep -n 'pp_config_option dashboardPort' "$SETUP" | cut -d: -f1)" -lt "$(grep -n 'dashboard.sh" --install' "$SETUP" | cut -d: -f1)" ] && echo true || echo false) $(grep -c 'COMMANDECK_DASHBOARD_BIND=${BIND:-127.0.0.1} COMMANDECK_DASHBOARD_PORT=$PORT ' "$SETUP")"
check "and /config is saved with the --option answer: the options call ends with GIVEN" 1 \
  "$(grep -c '| with_entries(select(.value != ""))'"')\" \"\$GIVEN\"$" "$SETUP")"

# Main's answer after pass 6: one precedence for every value setup saves, this run's explicit answer, then the profile
# or --recommended, then the saved value. setup.sh's own reads of its saved files, its own full parse and its own
# commandeck.json build run over saved answers (A), with an explicit answer (B) for every field it saves.
PARSE=$(sed -n '/^while \[ \$# -gt 0 \]/,/^done/p' "$SETUP")
READS=$(sed -n '/^old()/p;/^PROFILE=\$(old /,/^RL=/p' "$SETUP")
MREADS=$(sed -n '/^SCOPE=\$(jq/,/^WAS=/p' "$SETUP")
BUILD=$(sed -n '/^jq -n --argjson v "\$IL_VERSION"/,/il_write "\$IL_CONFIG"$/p' "$SETUP")
PFNS=$(grep -E '^(TAKES=|toks\(\))' "$SETUP"; sed -n '/^il_cuts()/,/^}/p' "$ROOT/scripts/install-lib.sh")
check "the harness read setup.sh's parse, reads and build" "true" \
  "$([ "$(wc -l <<<"$PARSE")" -gt 60 ] && [ "$(wc -l <<<"$BUILD")" -gt 15 ] && grep -q '^RL=' <<<"$READS" && grep -q '^HOSTS=' <<<"$MREADS" && echo true || echo false)"
# setup <flag>... -- commandeck.json as this run builds it, then the project, machine and /config answers in force.
setup() { (die() { echo "setup: $*" >&2; exit 1; }; usage() { echo usage >&2; exit 2; }; IL_ROOT=$ROOT IL_VERSION=1
  eval "$CFGFNS"; export CLAUDE_CONFIG_DIR=$T/cfg; cfg "${CFG:-{\}}"
  eval "$REC_FNS"; eval "$RL_FNS"; eval "$PFNS"
  IL_CONFIG=$T/saved.json IL_PROJECT=$T/project.json IL_MACHINE=$T/machine.json
  eval "$READS"; eval "$MREADS"; eval "$PARSE"; il_write() { jq -cS .; }; eval "$BUILD"
  eval "$DASH_READ"; echo "scope=$SCOPE dashboard=${DASHBOARD:-off} hosts=$HOSTS address=$BIND:$PORT") 2>&1; }
SAVED_A='{"version":1,"profile":"claude","strictHooks":false,"serena":true,"standardContext":false,"testCommand":"make a",
 "builder":{"clearLine":"140000","maxBuilders":2},"issueSizing":"80000","reviewLoop":{"blockAt":"P3","passCap":"3",
 "freshClosing":"no","closingPass":"no","smallBuild":"100","maxReviewMinutes":"30","maxTestPercent":"20","maxUsd":"30"},
 "ownFiles":{"AGENT_STARTUP.md":"replace",".claude/main-session.md":"replace"},"rules":"merge",
 "mergeDecisions":{"aaaaaaaa":"keep-mine"},"mainCacheTtl":"1h","workerCacheTtl":"5m","autoMode":"add",
 "fullSuiteBeforeFinal":true,"trustAllHooks":false,"workerSkillsOff":["a"],"workerPluginsOff":["p@m"],
 "keeps":{"w":{"skills":["s"],"plugins":[]}},"autoDecideNever":["x"],"generatedFiles":["g"],
 "chiefOfStaff":{"name":"Relay A","persona":"calm","cacheTtl":"1h"}}'
jq . <<<"$SAVED_A" > "$T/saved.json"; echo '{"scope":"project","dashboard":true}' > "$T/project.json"
echo '{"dashboard":{"bind":"0.0.0.0","port":"8791","hosts":"a.example"}}' > "$T/machine.json"
OUT=$(CFG=$CFG_DASH setup)
check "with no answer every saved value stands: commandeck.json is the saved one, the /config address beats the machine's" \
  "$(jq -cS . <<<"$SAVED_A")|scope=project dashboard=1 hosts=a.example address=0.0.0.0:8791" "$(paste -sd'|' - <<<"$OUT")"
B_WANT='{"version":1,"profile":"claude-openai","strictHooks":true,"serena":false,"standardContext":true,"testCommand":"make b",
 "builder":{"clearLine":"150000","maxBuilders":2},"issueSizing":"90000","reviewLoop":{"blockAt":"P1","passCap":"7",
 "smallBuild":"200","maxReviewMinutes":"40","maxTestPercent":"25","maxUsd":"50"},
 "ownFiles":{"AGENT_STARTUP.md":"merge",".claude/main-session.md":"skip"},"rules":"skip",
 "mergeDecisions":{"aaaaaaaa":"keep-both"},"mainCacheTtl":"5m","workerCacheTtl":"1h","autoMode":"leave",
 "fullSuiteBeforeFinal":false,"trustAllHooks":true,"workerSkillsOff":["b"],"workerPluginsOff":["q@m"],
 "keeps":{"w":{"skills":["t"],"plugins":[]}},"autoDecideNever":["x"],"generatedFiles":["g"],
 "chiefOfStaff":{"name":"Relay B","persona":"plain","cacheTtl":"5m"}}'
OUT=$(CFG=$CFG_DASH setup --profile claude-openai --strict --no-serena --standard-context --test-command "make b" \
  --builder-clear-line 150k --issue-sizing 90k --block-at P1 --pass-cap 7 --fresh-closing yes --closing-pass yes \
  --small-build 200 --max-review-min 40 --max-test-percent 25 --max-usd 50 --own-startup merge --own-main-session skip \
  --rules skip --rules-keep aaaaaaaa --main-cache-ttl 5m --worker-cache-ttl 1h --relay-cache-ttl 5m --auto-mode leave \
  --full-suite off --trust-all-hooks on --worker-skills-off b --worker-plugins-off q@m --keep-word w=t \
  --name "Relay B" --persona plain --scope machine --no-dashboard --hosts b.example --bind 127.0.0.1 --port 9999)
check "an explicit answer beats every saved field (commandeck.json, the project, the machine) and the /config address" \
  "$(jq -cS . <<<"$B_WANT")|scope=machine dashboard=off hosts=b.example address=127.0.0.1:9999" "$(paste -sd'|' - <<<"$OUT")"
check "an empty --bind and --port are no answer: the /config address stands" "address=0.0.0.0:8791" \
  "$(CFG=$CFG_DASH setup --bind '' --port '' | grep -o 'address=.*')"
check "--port is held to the manifest's range, as --option dashboardPort is" 1 \
  "$(CFG=$CFG_DASH rec 'GIVEN="{\"dashboardPort\":\"80\"}"; opt_check dashboardPort' | grep -c 'from 1024 to 65535')"
# Every /config key the profile names, data-driven: a saved value (ALT) loses to --recommended, which loses to an
# explicit --option after it. The value in force is read the way every reader reads it (pp_config_option).
ALT=$(jq -c --slurpfile m "$ROOT/.claude-plugin/plugin.json" '.options | with_entries(.key as $k | $m[0].userConfig[$k] as $c
  | .value |= (if type == "boolean" then not elif type == "number" then . + 1
    elif $c.options then ([$c.options[] | select(. != "project")] - [.])[0] elif $k == "wakeKinds" then "worker_done"
    elif ($k | test("Model$")) then (if . == "opus" then "sonnet" elif IN("sonnet", "fable", "builder") then "opus" else "gpt-alt-1" end)
    else . end))' "$ROOT/config/recommended.json")
check "every profile key has a saved value that differs from the profile's" "[]" \
  "$(jq -c --argjson a "$ALT" '[.options | to_entries[] | select($a[.key] == .value or $a[.key] == null) | .key]' "$ROOT/config/recommended.json")"
CFG_ALT=$(jq -c '{enabledPlugins: {"commandeck@commandeck": true}, pluginConfigs: {"commandeck@commandeck": {options: .}}}' <<<"$ALT")
# in_force <json of {key: value}> -- each key's value in force, read through pp_config_option.
IN_FORCE='in_force() { local k; for k in $(jq -r ".options | keys[]" "$REC_FILE"); do echo "$k=$(COMMANDECK_OPTIONS=$1 pp_config_option "$k")"; done; }'
WANT_REC=$(CFG=$CFG_ALT rec "$IN_FORCE; CLAUDE_CONFIG_DIR=/nonexistent in_force \"\$(jq -c .options \"\$REC_FILE\")\"")
check "--recommended beats a saved value for every profile key" "$WANT_REC" "$(CFG=$CFG_ALT rec "$IN_FORCE; rec_expand; $APPLY"'; in_force "$GIVEN"')"
WANT_ALT=$(CFG=$CFG_ALT rec "$IN_FORCE; in_force '{}'")
check "with no answer the saved value stands for every profile key" "$WANT_ALT" "$(CFG=$CFG_ALT rec "$IN_FORCE; in_force '{}'")"
check "and the saved values are not the profile's (the two checks above compare different things)" true \
  "$([ "$WANT_REC" != "$WANT_ALT" ] && echo true || echo false)"
check "an explicit --option after --recommended beats it for every profile key" "$WANT_ALT" \
  "$(CFG='{}' rec "$IN_FORCE; rec_expand; for p in \$(jq -r 'to_entries[] | \"\(.key)=\(.value)\"' <<<'$ALT'); do EXP+=(--option \"\$p\"); done; $APPLY"'; in_force "$GIVEN"')"

# Pass 6 (stale-model-on-profile-switch): a seat whose agent this run chose drops a saved model that agent cannot run.
STALE=$(sed -n '/^stale_models()/,/^}/p' "$SETUP"; sed -n "/^PP_ROUTE_JQ=/,/^ *'\$/p" "$PATHS")
CFG_GPT='{"enabledPlugins":{"commandeck@commandeck":true},"pluginConfigs":{"commandeck@commandeck":{"options":{"codexReviewerModel":"gpt-6.1-sol","planJudgeSolModel":"gpt-6.1-sol"}}}}'
CFG_OPUS=${CFG_GPT//gpt-6.1-sol/opus}
# models <given> -- each seat's model in force after stale_models, then the notes.
models() { rec "$STALE; GIVEN='$1'; stale_models"'; for k in codexReviewerModel planJudgeSolModel; do printf "%s " "$k=$(COMMANDECK_OPTIONS=$GIVEN pp_config_option $k || echo default)"; done; printf "%s|" "${REC_SKIPPED[@]}"'; }
check "--profile claude over saved Codex models: both go back to the default, each named" \
  "codexReviewerModel=default planJudgeSolModel=default saved codexReviewerModel=gpt-6.1-sol reset to the default: the seat runs on claude this run|saved planJudgeSolModel=gpt-6.1-sol reset to the default: the seat runs on claude this run|" \
  "$(CFG=$CFG_GPT models '{"codexReviewerAgent":"claude","planJudgeSolAgent":"claude"}')"
check "--profile claude --recommended (the finding's run): the profile's Codex models are skipped and the saved ones reset" \
  "codexReviewerModel=default planJudgeSolModel=default 4" \
  "$(CFG=$CFG_GPT rec "$STALE; ASKED=claude PROFILE=claude; rec_expand; $APPLY; GIVEN=\$(jq -c '{codexReviewerAgent: \"claude\", planJudgeSolAgent: \"claude\"} + .' <<<\"\$GIVEN\"); stale_models"'; for k in codexReviewerModel planJudgeSolModel; do printf "%s " "$k=$(COMMANDECK_OPTIONS=$GIVEN pp_config_option $k || echo default)"; done; echo "${#REC_SKIPPED[@]}"')"
check "an explicit model answer is this run's, never reset: only the other seat's saved model goes" \
  "codexReviewerModel=opus planJudgeSolModel=default " \
  "$(CFG=$CFG_GPT models '{"codexReviewerAgent":"claude","planJudgeSolAgent":"claude","codexReviewerModel":"opus"}' | cut -d' ' -f1-2) "
check "a saved Claude model under --profile claude-openai goes back to the default too" \
  "codexReviewerModel=default planJudgeSolModel=default" \
  "$(CFG=$CFG_OPUS models '{"codexReviewerAgent":"codex","planJudgeSolAgent":"codex"}' | cut -d' ' -f1-2)"
check "a saved model the chosen agent can run stays" "codexReviewerModel=opus planJudgeSolModel=opus |" \
  "$(CFG=$CFG_OPUS models '{"codexReviewerAgent":"claude","planJudgeSolAgent":"claude"}')"
check "no agent chosen this run: the saved model is left for the preflight to judge" \
  "codexReviewerModel=gpt-6.1-sol planJudgeSolModel=gpt-6.1-sol |" "$(CFG=$CFG_GPT models '{}')"
check "setup.sh runs it after the profile sets the agent keys and before the role checks" true \
  "$(a=$(grep -n "^  GIVEN=\$(jq -c --arg a \"\$a\" '{codexReviewerAgent" "$SETUP" | cut -d: -f1) b=$(grep -n '^stale_models$' "$SETUP" | cut -d: -f1) c=$(grep -n '^for k in \$(jq -r .keys\[\]. <<<"\$GIVEN"); do$' "$SETUP" | cut -d: -f1)
    [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && echo true || echo false)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
