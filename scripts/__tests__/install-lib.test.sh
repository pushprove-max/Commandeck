#!/usr/bin/env bash
# install-lib.test.sh -- the install's data-safety rules, on a hand-written HOME, by the functions setup.sh and
# uninstall.sh call (no whole run of either). What this pins: another tool's Codex hooks keep their places and
# its trust entries stay as they were, since Codex keys trust by position; the manifest records what was at a path
# with its hash and keeps the bytes; the restore puts those bytes back, and leaves a file edited since and names it;
# a plan writes nothing, manifest included. INSTALL_LIB_TEST_CASE=<text> runs only the cases whose name holds <text>.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
# INSTALL_LIB_TEST_CASE=<text> re-checks only the cases whose name holds <text>; the fixtures still build, the others are not counted.
check() { case $1 in *"${INSTALL_LIB_TEST_CASE-}"*) ;; *) return 0 ;; esac; if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
H=$T/home C=$T/home/.codex PROJ=$T/proj
# The caller's profile is never read: a case names its own CLAUDE_CONFIG_DIR, else it is the hand-written HOME's.
unset CLAUDE_CONFIG_DIR
mkdir -p "$C" && git init -q -b main "$PROJ"
# Another tool's Codex hooks and its trust entry, one of them disabled.
cat > "$C/hooks.json" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "/opt/other-tool/hook.sh", "timeout": 5}]}],
           "SessionEnd": [{"hooks": [{"type": "command", "command": "/opt/other-tool/end.sh"}]}]}}
EOF
cat > "$C/config.toml" <<EOF
model = "other"

[hooks.state."$C/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:0000"
enabled = false
EOF
cp "$C/hooks.json" "$T/hooks.before"; cp "$C/config.toml" "$T/config.before"
# lib <shell> [args] -- run it with paths.sh and install-lib.sh loaded and the args as "$1"..., in the project (or $CWD), on the hand-written HOME, under pipefail as setup.sh and uninstall.sh run.
lib() { (cd "${CWD:-$PROJ}" && env -u CLAUDE_PROJECT_DIR -u ORCA_WORKTREE_ID -u ORCA_TERMINAL_HANDLE -u COMMANDECK_SCRATCH -u CODEX_HOME COMMANDECK_MAIN="$PROJ" HOME="$H" \
  bash -c 'set -o pipefail; . "$0/paths.sh" && . "$0/install-lib.sh" && c=$1 && shift && eval "$c"' "$REAL/scripts" "$@"); }
snap() { (cd "$T" && find home proj -path '*/.git' -prune -o -print | sort | while IFS= read -r f; do [ -f "$f" ] && sha256sum < "$f" | cut -c1-16; echo "$f"; done); }
SETUP='il_record "$IL_MACHINE" merge "$IL_CODEX/hooks.json" "$IL_CODEX/config.toml" && il_record "$IL_PROJECT" own "$IL_CONFIG" \
  && il_codex_hooks "$IL_ROOT" && python3 "$PP_SCRIPTS/codex-hook-trust.py" "$IL_CODEX" >/dev/null'

# --- a plan writes nothing, the manifest included ---
B=$(snap)
OUT=$(IL_PLAN=1 IL_WROTE=$T/wrote lib 'il_record "$IL_MACHINE" merge "$IL_CODEX/hooks.json" && il_codex_hooks "$IL_ROOT" && il_set "$IL_MACHINE" ".x = 1"
  printf "x\n" | il_write "$IL_CONFIG"' 2>&1)
check "a plan writes nothing, in HOME or the project, and no manifest" "$B" "$(snap)"
check "and says what it would change and create" '1:1' "$(grep -c "^plan: would change $C/hooks.json:" <<<"$OUT"):$(grep -c "^plan: would create $PROJ/.claude/commandeck.json" <<<"$OUT")"
# A plan reads what it would already have written: with no Codex hooks file yet, it would create one.
mv "$C/hooks.json" "$T/hooks.kept"
OUT=$(IL_PLAN=1 IL_WROTE=$T/wrote2 lib 'il_codex_hooks "$IL_ROOT"' 2>&1)
check "a plan with no Codex hooks file yet says it would create it, and does not" '0:1:no' "$?:$(grep -c "^plan: would create $C/hooks.json" <<<"$OUT"):$([ -e "$C/hooks.json" ] && echo yes || echo no)"
mv "$T/hooks.kept" "$C/hooks.json"

# --- setup's steps: record, then add the plugin's entries ---
lib "$SETUP"; check "the steps succeed" 0 $?
MF=$H/.commandeck/install/_machine.json PMF=$(ls "$H/.commandeck/install/"*.json | grep -v _machine)
check "a file that was there is recorded by its content hash" "sha256:$(sha256sum < "$T/hooks.before" | cut -d' ' -f1)" "$(jq -r --arg p "$C/hooks.json" '.entries[$p].prior' "$MF")"
check "and its bytes are kept under that hash" 0 "$(cmp -s "$H/.commandeck/install/blobs/$(sha256sum < "$T/hooks.before" | cut -d' ' -f1)" "$T/hooks.before"; echo $?)"
check "a file that was not there is recorded as such, and the folder setup must make as a folder" 'did not exist:dir' \
  "$(jq -r --arg p "$PROJ/.claude/commandeck.json" '.entries[$p].prior' "$PMF"):$(jq -r --arg p "$PROJ/.claude" '.entries[$p].kind' "$PMF")"
check "Codex has the plugin's five entries" 5 "$(lib il_codex_count)"
check "the other tool's Codex hooks are still first in their groups" '["/opt/other-tool/hook.sh","/opt/other-tool/end.sh"]' \
  "$(jq -c '[.hooks.PreToolUse[0].hooks[0].command, .hooks.SessionEnd[0].hooks[0].command]' "$C/hooks.json")"
check "the plugin's five entries are trusted" 5 "$(grep -c "^\[hooks.state.\"$C/hooks.json:" "$C/config.toml" | awk '{print $1 - 1}')"
check "the other tool's trust entry and its disabled flag are untouched" 2 "$(grep -A2 'pre_tool_use:0:0' "$C/config.toml" | grep -c 'sha256:0000\|enabled = false')"
# A second setup records nothing over the first record and adds no entry twice.
lib "$SETUP"
check "a second run adds no entry twice" 5 "$(lib il_codex_count)"
check "and keeps the first record of what was there" "sha256:$(sha256sum < "$T/hooks.before" | cut -d' ' -f1)" "$(jq -r --arg p "$C/hooks.json" '.entries[$p].prior' "$MF")"

# --- uninstall's steps: the plugin's entries out, then the recorded bytes back ---
UNDO='python3 "$PP_SCRIPTS/codex-hook-trust.py" --forget "$IL_CODEX" >/dev/null && il_codex_hooks "" && il_restore "$IL_MACHINE"'
cp -R "$H" "$T/home.kept"
OUT=$(lib "$UNDO" 2>&1); check "the restore succeeds and leaves nothing named" '0:' "$?:$OUT"
check "Codex's hooks file is back byte for byte" 0 "$(cmp -s "$C/hooks.json" "$T/hooks.before"; echo $?)"
check "and its config, the other tool's trust entry included" 0 "$(cmp -s "$C/config.toml" "$T/config.before"; echo $?)"
check "the machine's manifest is gone with it" no "$([ -e "$MF" ] && echo yes || echo no)"
# A file the owner edited after setup is theirs: the restore leaves it and says so.
rm -rf "$H"; mv "$T/home.kept" "$H"
jq '.hooks.Stop = [{"hooks": [{"type": "command", "command": "/opt/mine.sh"}]}]' "$C/hooks.json" > "$T/h" && cp "$T/h" "$C/hooks.json"
OUT=$(lib "$UNDO" 2>&1)
check "a file edited since setup is left with the owner's edit, and named" "1:1" \
  "$(jq '[.hooks.Stop[0].hooks[0].command] | index("/opt/mine.sh") + 1' "$C/hooks.json"):$(grep -c "^changed since setup, left as it is: $C/hooks.json$" <<<"$OUT")"

# --- auto mode: two plain-English lines in the classifier's environment list of ~/.claude/settings.json ---
# The list is the owner's: setup keeps "$defaults" (Claude Code's built-in rules) in it, adds its lines once, and
# touches nothing when the owner's list has no "$defaults" (it replaced the built-in rules on purpose). Leave
# changes nothing at all, in the settings file or the machine manifest: the manifest serves every project, so a
# second project answering Leave must not take the first project's lines back.
AS=$H/.claude/settings.json; MM=$H/.commandeck/install/_machine.json; mkdir -p "$H/.claude"
auto() { lib 'il_auto_mode "$IL_MACHINE" "$HOME/.claude/settings.json" '"$1" 2>&1; }
envs() { jq -c '.autoMode.environment | [.[0], length]' "$AS" 2>&1; }
rm -rf "$H/.commandeck"; rm -f "$AS"
auto add >/dev/null
check "no autoMode yet: the list is written with \"\$defaults\" first and setup's two lines" '["$defaults",3]' "$(envs)"
auto add >/dev/null
check "a second run adds nothing" '["$defaults",3]' "$(envs)"
check "the first line names the plugin's repo, the second the relay pane" '1:1' \
  "$(jq -r '.autoMode.environment[1]' "$AS" | grep -c '^Trusted repo: https://'):$(jq -r '.autoMode.environment[2]' "$AS" | grep -c 'Chief-of-Staff')"
B=$(sha256sum < "$AS"; sha256sum < "$MM")
auto leave >/dev/null
check "Leave after an earlier add changes neither the settings file nor the machine manifest" "$B" "$(sha256sum < "$AS"; sha256sum < "$MM")"
auto remove >/dev/null
check "taking them out, when setup made the list, leaves no autoMode and no record" 'null:null' "$(jq -c '.autoMode' "$AS"):$(jq -c '.entries[$f].autoMode' --arg f "$AS" "$MM")"
echo '{"theme":"dark","autoMode":{"environment":["$defaults","mine"]}}' > "$AS"
auto add >/dev/null; auto add >/dev/null
check "an owner's list with \"\$defaults\" gets the lines once, their own entry kept in place" '["$defaults",4]:mine' "$(envs):$(jq -r '.autoMode.environment[1]' "$AS")"
auto remove >/dev/null
check "taking them out removes only setup's lines, the owner's entry and the rest of the file stay" '{"theme":"dark","autoMode":{"environment":["$defaults","mine"]}}' "$(jq -c . "$AS")"
echo '{"autoMode":{"environment":["mine"]}}' > "$AS"; cp "$AS" "$T/as.before"; B=$(sha256sum < "$MM")
OUT=$(auto add)
check "an owner's list without \"\$defaults\" is left byte for byte, and setup says how to keep the built-in rules" '0:1' \
  "$(cmp -s "$AS" "$T/as.before"; echo $?):$(grep -c '"$defaults"' <<<"$OUT")"
check "and nothing is recorded for it, so taking the lines out later removes nothing of the owner's" "$B" "$(sha256sum < "$MM")"
rm -rf "$H/.commandeck" "$AS"

# --- profiles: each CLAUDE_CONFIG_DIR's settings file is its own (class profile-cleanup) ---
# Setup's steps at machine scope under profile A, then B; uninstall's under B, or under no profile. Each file comes
# back as it was: the plugin's rules and options out of every profile setup wrote to, and each profile's own status
# line back, not the first profile's.
PA=$T/profiles/A/settings.json PB=$T/profiles/B/settings.json; mkdir -p "${PA%/*}" "${PB%/*}"
fresh() {
  rm -rf "$H/.commandeck"
  echo '{"statusLine": {"type": "command", "command": "owner-A"}, "permissions": {"allow": ["Bash(ls:*)"]}}' > "$PA"
  echo '{"statusLine": {"type": "command", "command": "owner-B"}, "permissions": {"allow": ["Bash(pwd)"]}}' > "$PB"
  cp "$PA" "$T/pa.before"; cp "$PB" "$T/pb.before"
}
prof_setup() { CLAUDE_CONFIG_DIR=${1%/settings.json} lib 'S=$CLAUDE_CONFIG_DIR/settings.json; il_record "$IL_MACHINE" merge "$S" && il_status_was "$IL_MACHINE" "$S" \
  && il_allow_set "$IL_MACHINE" "$S" "$(il_allow "$IL_ROOT")" && il_auto_mode "$IL_MACHINE" "$S" add >/dev/null && il_plugin_options "$S" "{\"ponytail\": true}" \
  && il_status_set "$IL_MACHINE" "$S" plugin-line'; }
UNDO_PROF='il_profiles_out "$IL_MACHINE" && il_restore "$IL_MACHINE"'
fresh; prof_setup "$PA"
check "profiles: setup under A puts its rules, options, auto-mode lines and status line in A's file" 'true:true:true:plugin-line' \
  "$(jq -c '(.permissions.allow | length > 1), (.pluginConfigs != null), (.autoMode != null), .statusLine.command' "$PA" | paste -sd: - | tr -d '"')"
OUT=$(lib "unset CLAUDE_CONFIG_DIR; $UNDO_PROF" 2>&1)
check "profiles: uninstall under no profile puts A's file back byte for byte, and names nothing" same: "$(cmp -s "$PA" "$T/pa.before" && echo same):$OUT"
# B's setup runs twice: the second must not take setup's own status line for the one B had before.
fresh; prof_setup "$PA"; prof_setup "$PB"; prof_setup "$PB"
check "profiles: the scope move and uninstall read both profiles' files from the manifest" "$PA $PB" "$(lib 'il_profile_files "$IL_MACHINE"' | paste -sd' ' -)"
CLAUDE_CONFIG_DIR=${PB%/settings.json} lib "$UNDO_PROF" >/dev/null 2>&1
check "profiles: uninstall under B gives B its own status line back after a second setup there, and A its own" owner-B:owner-A \
  "$(jq -r .statusLine.command "$PB"):$(jq -r .statusLine.command "$PA")"
check "profiles: and both files are back byte for byte" same:same "$(cmp -s "$PA" "$T/pa.before" && echo same):$(cmp -s "$PB" "$T/pb.before" && echo same)"
# The deployed format: a manifest from before has one top-level status-line record, the one its setup's profile read.
fresh; mkdir -p "${MM%/*}"
jq -n --arg b "$PB" '{version: 1, entries: {($b): {kind: "merge"}}, statusLine: {was: {type: "command", command: "owner-B"}, set: {type: "command", command: "plugin-line"}}}' > "$MM"
jq '.statusLine.command = "plugin-line"' "$T/pb.before" > "$PB"
CLAUDE_CONFIG_DIR=${PA%/settings.json} lib 'il_status_out "$IL_MACHINE" "$1"' "$PB"
check "profiles: an old manifest's top-level record is not put into another profile's file" plugin-line "$(jq -r .statusLine.command "$PB")"
CLAUDE_CONFIG_DIR=${PB%/settings.json} lib 'il_status_out "$IL_MACHINE" "$1"' "$PB"
check "profiles: and still restores the profile uninstall runs under" owner-B "$(jq -r .statusLine.command "$PB")"
rm -rf "$H/.commandeck"
# Pre-filled options record the file's bytes first: update's rollback deletes a recorded file with no prior as setup's new one.
fresh; mkdir -p "${MM%/*}"; echo '{"version": 1, "entries": {}}' > "$MM"
CLAUDE_CONFIG_DIR=${PB%/settings.json} lib 'il_plugin_options "$1" "{\"ponytail\": true}"' "$PB" >/dev/null
check "profiles: pre-filled options keep the file's bytes before them, for update's rollback" "sha256:$(sha256sum < "$T/pb.before" | cut -d' ' -f1):same" \
  "$(jq -r --arg p "$PB" '.entries[$p].prior' "$MM"):$(cmp -s "$H/.commandeck/install/blobs/$(sha256sum < "$T/pb.before" | cut -d' ' -f1)" "$T/pb.before" && echo same)"
rm -rf "$H/.commandeck"
# A file that is there but cannot be read is not an empty one (class unreadable-state-loss): taking it for {} wrote
# setup's few keys over the owner's whole file. Every read-then-write step refuses it and writes nothing.
fresh; prof_setup "$PB"; cp "$PB" "$T/pb.set"; chmod 000 "$PB"
CLAUDE_CONFIG_DIR=${PB%/settings.json} lib "$UNDO_PROF" >/dev/null 2>&1; RC=$?
chmod 600 "$PB"
check "unreadable: uninstall refuses a profile file it cannot read, leaves it and keeps the manifest" '1:same:yes' \
  "$RC:$(cmp -s "$PB" "$T/pb.set" && echo same):$([ -s "$MM" ] && echo yes)"
fresh; chmod 000 "$PB"
OUT=$(CLAUDE_CONFIG_DIR=${PB%/settings.json} lib 'il_status_was "$IL_MACHINE" "$1" || echo refused; il_allow_set "$IL_MACHINE" "$1" "[\"x\"]" || echo refused
  il_status_set "$IL_MACHINE" "$1" plugin-line || echo refused; il_lines "$IL_MACHINE" "$1" x || echo refused; il_block "$1" "$2" || echo refused' "$PB" "$T/pb.before" 2>/dev/null)
chmod 600 "$PB"
check "unreadable: setup's steps refuse it too, record no status line and leave the file" '5:null:same' \
  "$(grep -c refused <<<"$OUT"):$(jq -c --arg p "$PB" '.entries[$p].statusLine' "$MM" 2>/dev/null || echo null):$(cmp -s "$PB" "$T/pb.before" && echo same)"
rm -rf "$H/.commandeck"

# --- the prompt-cache lifetime: 5m, and setup's own earlier 1h moves while an owner's own value stays ---
CM=$T/cm.json CS=$T/cs.json
ttl() { lib 'il_cache_ttl "$1" "$2" '"${1:-}" "$CM" "$CS" 2>&1; }
echo '{"entries":{}}' > "$CM"
echo '{"promptCacheTtl":"1h","subagentPromptCacheTtl":"5m"}' > "$CS"
jq --arg p "$CS" '.entries[$p].cacheTtl = {promptCacheTtl: "1h", subagentPromptCacheTtl: "5m"}' "$CM" > "$CM.n" && mv "$CM.n" "$CM"
ttl >/dev/null
check "an update moves the 1h an earlier setup wrote to 5m, in the file and in the record" '5m:5m:5m'   "$(jq -r .promptCacheTtl "$CS"):$(jq -r .subagentPromptCacheTtl "$CS"):$(jq -r --arg p "$CS" '.entries[$p].cacheTtl.promptCacheTtl' "$CM")"
echo '{"promptCacheTtl":"1h"}' > "$CS"; echo '{"entries":{}}' > "$CM"
ttl >/dev/null
check "a 1h the owner set (no record) stays 1h, and the other key is added" '1h:5m' "$(jq -r .promptCacheTtl "$CS"):$(jq -r .subagentPromptCacheTtl "$CS")"
ttl off >/dev/null
check "taking setup's keys out leaves the owner's own 1h" '{"promptCacheTtl":"1h"}' "$(jq -c . "$CS")"

# --- a config from before 0.15.0 holds the cache answer as "recommended" or "default": /commandeck:update replays it ---
# A replay that read the old word as 5m would move an owner's 1h unasked, and one that said nothing would leave the
# question unasked for good. setup.sh's own lines (the read, the gate on il_cache_ttl, the Needs-you line) run on a
# hand-written config, as requirements.test.sh runs one of its lines; il_cache_ttl is a counter, no setup run.
replay() {
  echo "$1" > "$T/replay.json"
  ( IL_CONFIG=$T/replay.json IL_PROJECT=p PSET=s NEED=() calls=0 CLAUDE_CONFIG_DIR=$T/replay-cc
    il_cache_ttl() { calls=$((calls + 1)); }
    eval "$(sed -n '/^PP_OPTS_KEY=/,/^}/p' "$REAL/scripts/paths.sh")"
    for l in '^old()' 'CACHE=$(old .cacheTtl)' '^CACHE_ON=' '\[ "$CACHE_ON" != 5m \] || il_cache_ttl' 'Prompt cache: not answered since 0.15.0'; do eval "$(grep -- "$l" "$REAL/scripts/setup.sh")"; done
    echo "$calls:${#NEED[@]}" )
}
mkdir -p "$T/replay-cc" && echo '{}' > "$T/replay-cc/settings.json"
check "a stored \"recommended\" is not an answer: nothing is written, and the question is asked" 0:1 "$(replay '{"cacheTtl":"recommended"}')"
check "a stored \"default\" is the same" 0:1 "$(replay '{"cacheTtl":"default"}')"
check "a config with no answer is asked" 0:1 "$(replay '{"version":1}')"
check "a stored 5m is written again on every replay, and not asked" 1:0 "$(replay '{"cacheTtl":"5m"}')"
check "a stored leave writes nothing and is not asked" 0:0 "$(replay '{"cacheTtl":"leave"}')"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"promptCacheTtl": "5m"}}}}' > "$T/replay-cc/settings.json"
check "a /config 5m beats a stored leave: the 5m is written, and nothing is asked (issue 245)" 1:0 "$(replay '{"cacheTtl":"leave"}')"
check "and answers a config with none" 1:0 "$(replay '{"version":1}')"
echo '{}' > "$T/replay-cc/settings.json"

# --- the owner's worker cuts: setup ships no name, and update (setup with no answers) keeps the owner's lists ---
# setup.sh's own read lines and its config write run on a hand-written config, il_write printing what it would write;
# each later arg is a flag and its answer, through il_cuts as setup's case arms pass them. No setup run.
cuts() {
  if [ "$1" = none ]; then rm -f "$T/cuts.json"; else echo "$1" > "$T/cuts.json"; fi; shift
  lib 'S=$(cat "$0/setup.sh"); IL_CONFIG=$1; shift; il_write() { cat; }; CMODELS={} RL={} GEN=null DROPS={} BUILDER={}
    eval "$(grep "^old()" <<<"$S")"; eval "$(grep "^CUTS=" <<<"$S")"
    while [ $# -gt 0 ]; do CUTS=$(il_cuts "$CUTS" "$1" "$2") || exit 1; shift 2; done
    eval "$(sed -n "/^jq -n --argjson v \"\$IL_VERSION\"/,/| il_write \"\$IL_CONFIG\"$/p" <<<"$S")"' "$T/cuts.json" "$@"
}
OWNER='{"version":1,"profile":"claude","workerSkillsOff":["own:a"],"workerPluginsOff":["p@m"],"keeps":{"tools":{"skills":["own:a"],"plugins":[]}}}'
for c in none '{"version":1,"profile":"claude"}'; do
  out=$(cuts "$c")
  check "no owner input ($c): the config has no worker list and no keep, and names no skill" '[null,null,null]:[]' \
    "$(jq -c '[.workerSkillsOff, .workerPluginsOff, .keeps]' <<<"$out"):$(jq -c '[.. | strings | select(test("^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+$"))]' <<<"$out")"
done
check "an owner's lists and keep survive update (setup with no answers)" "$(jq -c '[.workerSkillsOff, .workerPluginsOff, .keeps]' <<<"$OWNER")" \
  "$(cuts "$OWNER" | jq -c '[.workerSkillsOff, .workerPluginsOff, .keeps]')"
check "the flags set a list, add a keep word (an @ name is a plugin) and clear another" '[["x:y","z"],null,{"web":{"skills":["s:t"],"plugins":["q@m"]}}]' \
  "$(cuts "$OWNER" --worker-skills-off z,x:y --worker-plugins-off '' --keep-word tools= --keep-word web=q@m,s:t | jq -c '[.workerSkillsOff, .workerPluginsOff, .keeps]')"
for bad in '--worker-plugins-off nomarket' '--worker-skills-off a@b' '--keep-word all=x' '--keep-word x' '--worker-skills-off a,,b'; do
  check "setup refuses $bad and writes nothing" refused "$(cuts "$OWNER" $bad 2>/dev/null || echo refused)"
done

# --- issue 244: the full suite before the final review, saved as fullSuiteBeforeFinal for builder-codex-pass.sh ---
# setup.sh's own read line, its no-test-command rule and its config write, as cuts runs them; the second arg is the
# --full-suite answer as its case arm saves it (true, false, or '' for none given). No setup run.
full() {
  echo "$1" > "$T/full.json"
  lib 'S=$(cat "$0/setup.sh"); IL_CONFIG=$1; il_write() { cat; }; CMODELS={} RL={} GEN=null DROPS={} CUTS={} BUILDER={}
    eval "$(grep "^old()" <<<"$S")"; eval "$(grep "^PROFILE=\$(old .profile)" <<<"$S")"; eval "$(grep "^FULL=\$(old " <<<"$S")"
    [ -z "$2" ] || FULL=$2
    eval "$(grep "^\[ -n \"\$TEST\" \] || FULL=false" <<<"$S")"
    { eval "$(sed -n "/^jq -n --argjson v \"\$IL_VERSION\"/,/| il_write \"\$IL_CONFIG\"$/p" <<<"$S")"; } | jq -c .fullSuiteBeforeFinal' "$T/full.json" "$2"
}
check "--full-suite on is saved as true" true "$(full '{"version":1,"testCommand":"t"}' true)"
check "a re-run with no answer keeps on as saved" true "$(full '{"version":1,"testCommand":"t","fullSuiteBeforeFinal":true}' '')"
check "a re-run with no answer keeps off as saved, not dropped" false "$(full '{"version":1,"testCommand":"t","fullSuiteBeforeFinal":false}' '')"
check "with no test command it records off, whatever the answer: the closing pass would have no suite to run" false "$(full '{"version":1}' true)"

# Issue 256: setup rebuilds .builder from its answers; a key it asks nothing about (the hand-written maxBuilders cap)
# must survive, or an update lifts the cap. The second arg is the --builder-clear-line answer ('' clears it). No setup
# run. Issue 312: the Builder's model and effort are /plugin config keys, so the file saves neither again.
builder() {
  echo "$1" > "$T/builder.json"
  lib 'S=$(cat "$0/setup.sh"); IL_CONFIG=$1; il_write() { cat; }; RL={} GEN=null DROPS={} CUTS={}
    eval "$(grep "^old()" <<<"$S")"; eval "$(grep "^BCLEAR=\$(old " <<<"$S")"; eval "$(grep "^BUILDER=" <<<"$S")"; [ "$2" = keep ] || BCLEAR=$2
    { eval "$(sed -n "/^jq -n --argjson v \"\$IL_VERSION\"/,/| il_write \"\$IL_CONFIG\"$/p" <<<"$S")"; } | jq -c .builder' "$T/builder.json" "$2"
}
check "a re-run keeps the project's Builder cap and clear line, and saves no model or effort there" '{"maxBuilders":1,"clearLine":"300000"}' \
  "$(builder '{"version":1,"builder":{"model":"opus","effort":"high","maxBuilders":1,"clearLine":"300000"}}' keep)"
check "an answer cleared to the default is dropped, the cap kept" '{"maxBuilders":1}' \
  "$(builder '{"version":1,"builder":{"clearLine":"300000","maxBuilders":1}}' '')"

# Issue 311: the Builder clear line and the issue sizing take 140k, 140K or 140000 (a typed answer is passed as typed). No setup run.
toks() { lib 'eval "$(grep "^toks()" "$0/setup.sh")"; die() { echo "$*" >&2; exit 1; }; (toks --builder-clear-line "$1") || echo REFUSED' "$1" 2>&1; }
check "a clear line typed 140k is saved as 140000" 140000 "$(toks 140k)"
check "a clear line typed 140K is saved as 140000" 140000 "$(toks 140K)"
check "a clear line typed 140000 is saved as typed" 140000 "$(toks 140000)"
check "off and the empty default pass as given" "off|" "$(toks off)|$(toks '')"
check "a unit other than k is refused, the flag named" "REFUSED" "$(toks 140m | tail -1)"
check "a bare k and a zero count are refused" "REFUSED REFUSED" "$(toks k | tail -1) $(toks 0k | tail -1)"

# --- a routing file of the owner's own gains the plan seats it lacks, and uninstall takes back only those ---
# A COMMANDECK_ROUTING file kept from before the plan seats had none, so no plan run could start. Setup adds each
# role the plugin's defaults have and the file lacks; a role the file has, or the owner changes later, is theirs.
D=$REAL/config/routing.json R=$T/routing.json RM=$T/routing-manifest.json
jq -c '.roles = {builder: (.roles.builder + {effort: "high"})}' "$D" > "$R"; cp "$R" "$T/routing.orig"
# seats -- setup's calls (il_routing_merged, then il_routing_seats); unseat -- uninstall's (off, then il_restore).
seats() { lib 'il_routing_merged "$1" "$2" > "$3" && il_routing_seats "$4" "$1" "$3"' "$R" "$D" "$T/rt" "$RM"; }
unseat() { lib 'il_routing_seats "$2" "$1" - off && il_restore "$2"' "$R" "$RM"; }
ADDED=$(jq -c '.roles | keys - ["builder"]' "$D")
OUT=$(seats)
check "a routing file with only an edited builder gains every other role from the defaults, its builder unchanged" "$(jq -c '.roles | keys' "$D"):high" \
  "$(jq -c '.roles | keys' "$R"):$(jq -r '.roles.builder.effort' "$R")"
check "setup names the added seats, and the manifest records them under .roles" "1:$ADDED" \
  "$(grep -c '^Routing: added seats .*plan-judge-sol.* to .*routing.json from the plugin.s defaults; uninstall takes them out again\.$' <<<"$OUT"):$(jq -c --arg p "$R" '.entries[$p].roles | keys' "$RM")"
B1=$(sha256sum < "$R") M1=$(sha256sum < "$RM")
check "a second run prints nothing and changes nothing" ":$B1:$M1" "$(seats):$(sha256sum < "$R"):$(sha256sum < "$RM")"
check "the defaults file itself is left as it is" "" "$(lib 'il_routing_merged "$1" "$1"' "$D")"
check "the merged routing passes routing validation and has the plan seat the file lacked" ok \
  "$(lib 'il_routing_merged "$1" "$2" > "$3" && COMMANDECK_ROUTING=$3 pp_routing_valid && jq -e ".roles[\"plan-judge-sol\"]" "$3" >/dev/null && echo ok' "$T/routing.orig" "$D" "$T/rt2")"
unseat >/dev/null
check "uninstall puts the owner's file back byte for byte" same "$(cmp -s "$R" "$T/routing.orig" && echo same)"
# The owner edits one added role and adds one of their own: both edits stay, the other added roles go, and the file
# is not overwritten from the bytes setup kept.
seats >/dev/null
jq '.roles["plan-judge-sol"].effort = "max" | .roles.mine = {agent: "claude", model: "sonnet", effort: "low"}' "$R" > "$T/r" && cp "$T/r" "$R"
OUT=$(unseat)
check "uninstall after owner edits keeps the edited role and the owner's own, takes out the rest, and says the file changed" \
  "[\"builder\",\"mine\",\"plan-judge-sol\"]:max:1" \
  "$(jq -c '.roles | keys' "$R"):$(jq -r '.roles["plan-judge-sol"].effort' "$R"):$(grep -c "changed since setup, left as it is: $R" <<<"$OUT")"
# A later setup merges what it adds into what an earlier one recorded: the owner removed one added seat, setup
# added it again, and uninstall still takes out both it and the rest, so the file restores.
cp "$T/routing.orig" "$R"; seats >/dev/null
jq 'del(.roles.orchestrator)' "$R" > "$T/r" && cp "$T/r" "$R"; seats >/dev/null; unseat >/dev/null
check "setup, an owner removal, setup again, then uninstall: the owner's file is back byte for byte" same "$(cmp -s "$R" "$T/routing.orig" && echo same)"
# Two projects on one routing file of the owner's own: the first setup adds the seats and the second finds them
# there, so it recorded none, and the first's uninstall took them out from under the second. A seat another
# project's manifest records with the same value stays until the last of them uninstalls, in either order.
MA=$H/.commandeck/install/share-a.json MB=$H/.commandeck/install/share-b.json
for order in "$MA $MB" "$MB $MA"; do
  cp "$T/routing.orig" "$R"; rm -f "$MA"; mkdir -p "${MB%/*}"; echo '{"version": 1, "entries": {}}' > "$MB"
  RM=$MA seats >/dev/null; RM=$MB seats >/dev/null
  set -- $order; RM=$1 unseat >/dev/null; KEPT=$(jq -c '.roles | keys' "$R"); RM=$2 unseat >/dev/null
  check "a shared routing file keeps the added seats until the last project uninstalls, then is the owner's again (${1##*/} first)" \
    "$(jq -c '.roles | keys' "$D"):same" "$KEPT:$([ "$(jq -cS . "$R")" = "$(jq -cS . "$T/routing.orig")" ] && echo same)"
done
# Pass 2: the second project spelled the same file another way (a ./ or a symlink), so its manifest key matched no
# other and recorded no shared seat, and the first's uninstall took them out from under it. Keys compare as files.
ln -s "$R" "$T/routing-link.json"
for alias in "$T/./routing.json" "$T/routing-link.json"; do
  cp "$T/routing.orig" "$R"; rm -f "$MA"; echo '{"version": 1, "entries": {}}' > "$MB"
  RM=$MA seats >/dev/null; R=$alias RM=$MB seats >/dev/null
  RM=$MA unseat >/dev/null; KEPT=$(jq -c '.roles | keys' "$R"); R=$alias RM=$MB unseat >/dev/null
  check "a shared routing file another project names as ${alias#"$T/"} keeps the seats until the last uninstall, then is the owner's again" \
    "$(jq -c '.roles | keys' "$D"):same" "$KEPT:$([ "$(jq -cS . "$R")" = "$(jq -cS . "$T/routing.orig")" ] && echo same)"
done
# Pass 5: two projects named one routing file by relative paths (../routing.json, ../../routing.json), so each
# manifest key resolved against the cwd of whoever read it, another project's key named no file, and the first
# uninstall took the seats the second needed. Setup records the absolute path, so uninstall run from anywhere finds
# its own.
A=$T/A B=$T/nested/B; mkdir -p "$A" "$B"
proj() { echo "{\"version\": 1, \"entries\": {}, \"project\": \"$2\"}" > "$1"; }
# rseat <cwd> <relative path> <manifest> [old] -- setup's own routing line, from setup.sh; old: the call before pass 5.
rseat() { CWD=$1 COMMANDECK_ROUTING=$2 lib 'IL_PROJECT=$1 RT=$2; die() { echo "setup: $*" >&2; exit 1; }
  il_routing_merged "$(pp_routing)" "$IL_ROOT/config/routing.json" > "$RT"
  if [ "$3" = old ]; then il_routing_seats "$IL_PROJECT" "$(pp_routing)" "$RT"; else eval "$(grep "^il_routing_seats " "$0/setup.sh")"; fi' "$3" "$T/rt" "${4:-}"; }
# runseat <cwd> <manifest> <project> -- uninstall's routing lines, from uninstall.sh, run from <cwd>.
runseat() { CWD=$1 lib 'IL_PROJECT=$1 PP_MAIN=$2; eval "$(sed -n "/^  # The seats setup added to a routing file/,/^  il_restore /p" "$0/uninstall.sh")"' "$2" "$3"; }
# A relative key an older setup left is never resolved (pass 7: the cwd it was written in went unrecorded, and every
# guess at it named a wrong file for some layout), and proves no ownership (pass 8): uninstall takes a seat out only
# by an absolute record of its own that no other record could share, so with an older key in play the seats stay.
for case in new:new old:new new:old; do for first in A B; do
  cp "$T/routing.orig" "$R"; proj "$MA" "$A"; proj "$MB" "$B"
  rseat "$A" ../routing.json "$MA" "${case%%:*}" >/dev/null; rseat "$B" ../../routing.json "$MB" "${case#*:}" >/dev/null
  if [ $first = A ]; then set -- "$MA" "$A" "$MB" "$B"; else set -- "$MB" "$B" "$MA" "$A"; fi
  OUT=$(runseat "$2" "$1" "$2"); KEPT=$(jq -c '.roles | keys' "$R"); runseat "$T" "$3" "$4" >/dev/null
  # The owner's again only where the last out set the seats up itself by an absolute record.
  case $case:$first in new:new:*|new:old:B) WANT=$(jq -c '.roles | keys' "$T/routing.orig") ;; *) WANT=$(jq -c '.roles | keys' "$D") ;; esac
  check "two projects naming one routing file by relative paths ($case setup, $first out first) keep the seats until the last uninstall, the first out says why, then it is the owner's again only by an absolute record" \
    "$(jq -c '.roles | keys' "$D"):$WANT:1" "$KEPT:$(jq -c '.roles | keys' "$R"):$([ $case = new:new ] && grep -c "^kept seats .* in $R: another project's install record names this file$" <<<"$OUT" || echo 1)"
done; done
cp "$T/routing.orig" "$R"; proj "$MA" "$A"; rseat "$A" ../routing.json "$MA" >/dev/null
check "setup records a relative routing path as the absolute file" "[\"$R\"]" "$(jq -c '[.entries | to_entries[] | select(.value.roles) | .key]' "$MA")"
cp "$T/routing.orig" "$R"; proj "$MA" "$A"; rseat "$A" ../routing.json "$MA" old >/dev/null; OUT=$(runseat "$T" "$MA" "$A")
check "uninstall leaves the seats an older setup recorded under a relative key, and says so" "$(jq -c '.roles | keys' "$D"):1" \
  "$(jq -c '.roles | keys' "$R"):$(grep -c "^an older setup recorded a routing file as ../routing.json, " <<<"$OUT")"
check "a relative CODEX_HOME is the absolute folder, so uninstall from elsewhere finds the same one" "$C" "$(CWD=$H lib 'CODEX_HOME=.codex; . "$PP_SCRIPTS/install-lib.sh" && echo "$IL_CODEX"')"
# Pass 6: a machine manifest an older setup wrote under a relative CODEX_HOME holds relative keys (.codex/hooks.json);
# the next setup recorded the same files again under absolute keys, the plugin's entries as their prior, so uninstall
# removed hooks.json by one record and put the plugin's hooks back by the other. Pass 11: no relative key is resolved
# (the next case), so the plugin's entries come out by the absolute record, whose prior held them: the file is left
# without them and named, and the older keys are named.
H6=$T/h6 P6=$T/p6; mkdir -p "$P6/.codex"; printf 'model = "other"\n' > "$P6/.codex/config.toml"; cp "$P6/.codex/config.toml" "$T/config6"
SETUP6='il_record "$IL_MACHINE" merge "$IL_CODEX/hooks.json" "$IL_CODEX/config.toml" && il_codex_hooks "$IL_ROOT" && python3 "$PP_SCRIPTS/codex-hook-trust.py" "$IL_CODEX" >/dev/null'
H=$H6 CWD=$P6 lib "IL_CODEX=.codex; $SETUP6"   # the older setup: IL_CODEX as CODEX_HOME gave it
H=$H6 CWD=$P6 lib "CODEX_HOME=.codex; . \"\$PP_SCRIPTS/install-lib.sh\" && $SETUP6"
OUT=$(H=$H6 CWD=$P6 lib 'CODEX_HOME=.codex; . "$PP_SCRIPTS/install-lib.sh"; HERE=$PP_SCRIPTS
  eval "$(sed -n "/^  # The relative keys an older setup/,/^  done < <(jq/p" "$0/uninstall.sh")"; il_restore "$IL_MACHINE"')
check "an older setup under a relative CODEX_HOME, setup again, then uninstall: none of the plugin's hooks, config.toml byte for byte, the older keys named" "0:same:2:1" \
  "$(jq '[.hooks[]?[]?.hooks[]?] | length' "$P6/.codex/hooks.json" 2>/dev/null || echo 0):$(cmp -s "$P6/.codex/config.toml" "$T/config6" && echo same):$(grep -c "^an older setup recorded a Codex path as " <<<"$OUT"):$(grep -c "^changed since setup, left as it is: $P6/.codex/hooks.json$" <<<"$OUT")"
# Pass 11: the cwd an older setup's relative Codex key was written in is in no manifest. Setup in B took A's records
# (.codex/config.toml read from B) as B's own, so A's were lost: A's plugin hooks stayed and no uninstall named them.
H11=$T/h11 A11=$T/a11 B11=$T/b11; mkdir -p "$A11/.codex" "$B11/.codex"
printf 'model = "a"\n' > "$A11/.codex/config.toml"; printf 'model = "b"\n' > "$B11/.codex/config.toml"; cp "$B11/.codex/config.toml" "$T/config11"
H=$H11 CWD=$A11 lib "IL_CODEX=.codex; $SETUP6"   # the older setup, in A
A11SUM=$(cat "$A11/.codex/"* | sha256sum)
H=$H11 CWD=$B11 lib "CODEX_HOME=.codex; . \"\$PP_SCRIPTS/install-lib.sh\" && $SETUP6"
check "a later setup in another project records its own Codex files, and leaves an older setup's relative keys where they are" \
  "sha256:$(sha256sum < "$T/config11" | cut -d' ' -f1):[\".codex/config.toml\",\".codex/hooks.json\"]" \
  "$(jq -r --arg p "$B11/.codex/config.toml" '.entries[$p].prior' "$H11/.commandeck/install/_machine.json"):$(jq -c '[.entries | keys[] | select(startswith("/") | not)]' "$H11/.commandeck/install/_machine.json")"
OUT=$(H=$H11 CWD=$B11 lib 'CODEX_HOME=.codex; . "$PP_SCRIPTS/install-lib.sh"; HERE=$PP_SCRIPTS
  eval "$(sed -n "/^  # The relative keys an older setup/,/^  done < <(jq/p" "$0/uninstall.sh")"; il_restore "$IL_MACHINE"')
check "then the last uninstall, from B: B's Codex files back byte for byte, A's not written, and A's relative keys named" "absent:same:$A11SUM:2" \
  "$([ -e "$B11/.codex/hooks.json" ] && echo present || echo absent):$(cmp -s "$B11/.codex/config.toml" "$T/config11" && echo same):$(cat "$A11/.codex/"* | sha256sum):$(grep -c "^an older setup recorded a Codex path as .codex/[a-z]*[.][a-z]*, relative to a folder it did not record" <<<"$OUT")"
# Pass 6: an older setup run from a project's subfolder recorded ../../../seats.json, which read from the project names
# another file: another project's uninstall took the seats it needed, and its own put the owner's bytes back at that
# other path. Another project's relative key keeps the seats in, whatever it names; its own uninstall leaves it.
S6=$T/deep/seats.json B6=$T/deep/n/B; mkdir -p "$B6/sub"
for first in A B; do
  cp "$T/routing.orig" "$S6"; proj "$MA" "$A"; proj "$MB" "$B6"
  if [ $first = A ]; then rseat "$A" "$S6" "$MA" >/dev/null; fi
  rseat "$B6/sub" ../../../seats.json "$MB" old >/dev/null
  if [ $first = B ]; then rseat "$A" "$S6" "$MA" >/dev/null; fi
  runseat "$A" "$MA" "$A" >/dev/null; KEPT=$(jq -c '.roles | keys' "$S6"); runseat "$B6" "$MB" "$B6" >/dev/null
  check "an older setup's relative key written from a subfolder ($first set up first) keeps the shared seats, and its own uninstall leaves them and writes no other file" \
    "$(jq -c '.roles | keys' "$D"):$(jq -c '.roles | keys' "$D"):absent" "$KEPT:$(jq -c '.roles | keys' "$S6"):$([ -e "$T/seats.json" ] && echo present || echo absent)"
done
cp "$T/routing.orig" "$S6"; cp "$T/routing.orig" "$T/seats.json"; proj "$MB" "$B6"
rseat "$B6/sub" ../../../seats.json "$MB" old >/dev/null; OUT=$(runseat "$B6" "$MB" "$B6")
check "a relative key an older setup left that could name two files touches neither, and says so" "1:same" \
  "$(grep -c "^an older setup recorded a routing file as ../../../seats.json, " <<<"$OUT"):$(cmp -s "$T/seats.json" "$T/routing.orig" && echo same)"
rm -f "$T/seats.json"
# Pass 7: a key with no ../ written from a subfolder (routing.json from B/sub) named a file inside the project; the
# search from the project found only B/routing.json and took from it the roles the key recorded, which it owned.
P7=$T/b7; mkdir -p "$P7/sub"; cp "$T/routing.orig" "$P7/sub/routing.json"; proj "$MB" "$P7"
rseat "$P7/sub" routing.json "$MB" old >/dev/null; cp "$P7/sub/routing.json" "$P7/routing.json"; cp "$P7/routing.json" "$T/root7"
cp "$P7/sub/routing.json" "$T/sub7"; runseat "$P7" "$MB" "$P7" >/dev/null
check "an older setup's routing.json written from a subfolder, uninstall from the project: neither same-named file loses a role" same:same \
  "$(cmp -s "$P7/routing.json" "$T/root7" && echo same):$(cmp -s "$P7/sub/routing.json" "$T/sub7" && echo same)"
# The same key at setup: the next setup, run from the project, took the older record for the project's own file, so
# uninstall took out a role the owner had there (orchestrator) and put back the subfolder file's bytes.
cp "$T/routing.orig" "$P7/sub/routing.json"; proj "$MB" "$P7"
jq --slurpfile d "$D" '.roles.orchestrator = $d[0].roles.orchestrator' "$T/routing.orig" > "$P7/routing.json"; cp "$P7/routing.json" "$T/root7"
rseat "$P7/sub" routing.json "$MB" old >/dev/null; rseat "$P7" routing.json "$MB" >/dev/null; runseat "$P7" "$MB" "$P7" >/dev/null
check "an older setup's relative key, setup again from the project, then uninstall: the project's own routing file is back byte for byte" same \
  "$(cmp -s "$P7/routing.json" "$T/root7" && echo same)"
# Pass 8: another project's relative key was matched by file name. At setup that made A record as its own the roles
# its file already had, because an unrelated B's routing.json recorded the same values, and A's uninstall took them out.
A8=$T/a8 B8=$T/b8; mkdir -p "$A8" "$B8"; proj "$MA" "$A8"; proj "$MB" "$B8"
cp "$T/routing.orig" "$B8/routing.json"; jq . "$D" > "$A8/routing.json"; cp "$A8/routing.json" "$T/a8.orig"
rseat "$B8" routing.json "$MB" old >/dev/null; rseat "$A8" "$A8/routing.json" "$MA" >/dev/null
runseat "$B8" "$MB" "$B8" >/dev/null; runseat "$A8" "$MA" "$A8" >/dev/null
check "an unrelated older setup's routing.json of the same name: setup takes none of the owner's roles, and uninstall leaves the file byte for byte" same \
  "$(cmp -s "$A8/routing.json" "$T/a8.orig" && echo same)"
# And at uninstall a name match missed an older key through a link of another name (B/routing-link.json to the file),
# so A's uninstall took out the seats B still needed.
R8=$T/r8.json; cp "$T/routing.orig" "$R8"; ln -s "$R8" "$B8/routing-link.json"; proj "$MA" "$A8"; proj "$MB" "$B8"
rseat "$A8" "$R8" "$MA" >/dev/null; rseat "$B8" routing-link.json "$MB" old >/dev/null; OUT=$(runseat "$A8" "$MA" "$A8")
check "an older setup's relative link of another name to the shared file: the other project's uninstall keeps the seats and says which and why" \
  "$(jq -c '.roles | keys' "$D"):1" \
  "$(jq -c '.roles | keys' "$R8"):$(grep -c "^kept seats .*plan-judge-sol.* in $R8: an older setup's install record in another project names a routing file by a relative path, which may be this one$" <<<"$OUT")"
# Pass 9: other projects' records were merged into one map, so a later-sorted C's other value for a role hid B's
# matching one, and A's uninstall took out the seat B still needed. A seat stays if any record holds its value.
MC=$H/.commandeck/install/share-c.json
for ckey in other.json "$R8"; do
  cp "$T/routing.orig" "$R8"; proj "$MA" "$A8"; proj "$MB" "$B8"; proj "$MC" "$T"
  rseat "$A8" "$R8" "$MA" >/dev/null; rseat "$B8" routing-link.json "$MB" old >/dev/null
  jq --arg k "$ckey" '.entries[$k].roles = {"plan-judge-sol": {effort: "other"}}' "$MC" > "$T/mc" && cp "$T/mc" "$MC"
  runseat "$A8" "$MA" "$A8" >/dev/null
  check "a later project's other value for a role ($ckey) does not hide the earlier record that keeps the seat" \
    "$(jq -c '.roles | keys' "$D")" "$(jq -c '.roles | keys' "$R8")"
done
rm -f "$MB" "$MC"

# Setup's routing checks and its review preflight read the merged routing (judge amendment A): with only an edited
# builder in the owner's file, the Claude profile's preflight found no Claude reviewer and refused before any write.
# The preflight also reads GitHub as the reviewer would (issue 316): the project has a GitHub remote and a gh that answers.
git -C "$PROJ" remote get-url origin >/dev/null 2>&1 || git -C "$PROJ" remote add origin https://github.com/o/proj.git
mkdir -p "$T/ghbin" && printf '#!/usr/bin/env bash\necho "{}"\n' > "$T/ghbin/gh" && chmod +x "$T/ghbin/gh"
setup_routing() { PATH=$T/ghbin:$PATH COMMANDECK_ROUTING=$1 lib 'S=$(cat "$0/setup.sh"); HERE=$0; die() { echo "setup: $*" >&2; exit 1; }
  ASKED=claude GIVEN={} PROFILE=claude PASS=claude RL={}
  eval "$(sed -n "/^# --- routing:/,/^# --- preflight:/p" <<<"$S")"
  eval "$(grep -F "COMMANDECK_PASS=\$PASS bash \"\$HERE/builder-codex-pass.sh\" --preflight" <<<"$S")" && echo "preflight ok"' 2>&1; }
check "setup's routing block and review preflight pass on an owner's file with only an edited builder" 1 "$(setup_routing "$T/routing.orig" | grep -c '^preflight ok$')"

# Issue 312: setup's --option answers are role keys, checked before anything is written, as every reader checks them.
# setup_keys <--profile or ""> <--option answers as JSON> -- the answers setup writes.
setup_keys() { ASK=$1 GV=$2 lib 'S=$(cat "$0/setup.sh"); HERE=$0; die() { echo "setup: $*" >&2; exit 1; }
  ASKED=$ASK GIVEN=$GV PROFILE=${ASK:-claude-openai} RL={}
  eval "$(sed -n "/^# --- routing:/,/^# --- preflight:/p" <<<"$S")" && echo "$GIVEN"' 2>&1; }
[ ! -e "$PROJ/.claude" ] || { echo "install-lib: the key cases expect no $PROJ/.claude; a case above left one" >&2; exit 1; }
mkdir "$PROJ/.claude" && echo '{"version": 1, "profile": "claude-openai"}' > "$PROJ/.claude/commandeck.json"
check "--profile claude puts the reviewer and both judges on Claude" '{"codexReviewerAgent":"claude","planJudgeAstraAgent":"claude","planJudgeSolAgent":"claude"}' \
  "$(setup_keys claude '{}' | jq -cS '{codexReviewerAgent, planJudgeSolAgent, planJudgeAstraAgent}')"
check "and an --option naming one of them beats the profile" codex "$(setup_keys claude '{"codexReviewerAgent": "codex"}' | jq -r .codexReviewerAgent)"
check "a boolean answer is saved as a boolean, so /plugin shows it as its toggle" false "$(setup_keys '' '{"fixerEnabled": "false"}' | jq -r '.fixerEnabled | if type == "boolean" then tostring else "not a boolean" end')"
for k in orchestrator builder codexReviewer; do
  check "${k}Enabled=false is refused, saying why that role cannot be off" 1 "$(setup_keys '' "{\"${k}Enabled\": \"false\"}" | grep -c 'cannot be off.*Nothing was changed')"
done
check "a model the fixer does not take is refused naming its key" 1 "$(setup_keys '' '{"fixerFirstModel": "gpt-9"}' | grep -c '^setup: .*fixerFirstModel.*Nothing was changed')"
check "a key /plugin config does not list is refused" 1 "$(setup_keys '' '{"leanWorkerModel": "sonnet"}' | grep -c "not 'leanWorkerModel'")"
rm -f "$H/.claude/settings.json"; rm -r "$PROJ/.claude"

# Issue 312: main's model and effort keys go into main's settings file over the owner's own values, which come back
# when the keys are unset again or the plugin is uninstalled; a value the owner changed since stays theirs. With no
# effort key main runs routing's orchestrator effort, medium.
MS=$T/main-settings.json; echo '{"model": "sonnet", "effortLevel": "low", "x": 1}' > "$MS"; OWN='{"effortLevel":"low","model":"sonnet","x":1}'
# mm <keys> [off] -- setup's (or uninstall's) call, the file recorded in the project's manifest first as setup records it.
mm() { COMMANDECK_OPTIONS=$1 lib 'il_record "$IL_PROJECT" merge "$1" && il_main_model "$IL_PROJECT" "$1" $2' "$MS" "${2:-}"; jq -c '{model, effortLevel}' "$MS"; }
KEYS='{"orchestratorModel": "opus", "orchestratorEffort": "high"}'
check "main model: the keys replace the owner's model and effort, a rerun too" '{"model":"opus","effortLevel":"high"}' "$(mm "$KEYS" >/dev/null; mm "$KEYS")"
check "main model: the keys unset again put the owner's model back, and the effort goes to routing's medium" '{"effortLevel":"medium","model":"sonnet","x":1}' "$(mm '{}' >/dev/null; jq -cS . "$MS")"
check "main model: uninstall puts the owner's values back" "$OWN" "$(mm "$KEYS" >/dev/null; mm '{}' off >/dev/null; jq -cS . "$MS")"
mm "$KEYS" >/dev/null; jq '.effortLevel = "max"' "$MS" > "$T/x" && mv "$T/x" "$MS"
check "main model: uninstall leaves an effort the owner changed since, and puts back the model" '{"model":"sonnet","effortLevel":"max"}' "$(mm '{}' off)"

# --- issue 207: a wrapper that already calls the stable link is no question, even before setup re-points the link ---
H2=$T/h2; mkdir -p "$H2/.codex" "$H2/.commandeck" "$T/v1/hooks"; echo old > "$T/v1/hooks/codex-notify.sh"; ln -s "$T/v1" "$H2/.commandeck/plugin"
printf 'notify = ["bash", "%s"]\n' "$T/wrap.sh" > "$H2/.codex/config.toml"
printf '#!/bin/sh\n~/.commandeck/plugin/hooks/codex-notify.sh "$@"\n' > "$T/wrap.sh"
OUT=$(H=$H2 IL_PLAN=1 lib 'il_notify_repoint "$IL_MACHINE"' 2>&1)
check "notify: a wrapper calling the stable link by ~, the link still on an older folder, gets no ASK" 0 "$(grep -c 'ASK' <<<"$OUT")"
printf '#!/bin/sh\n"%s/hooks/codex-notify.sh" "$@"\n' "$T/v1" > "$T/wrap.sh"
OUT=$(H=$H2 IL_PLAN=1 lib 'il_notify_repoint "$IL_MACHINE"' 2>&1)
check "notify: a wrapper calling an older versioned folder's hook gets the ASK, old and new lines different" 1 \
  "$(grep -c "ASK: .*Old line: \"$T/v1/hooks/codex-notify.sh\" \"\$@\" New line: \"$H2/.commandeck/plugin/hooks/codex-notify.sh\" \"\$@\"" <<<"$OUT")"

# --- issue 208: setup's two marked blocks are replaced where they stand; a run with nothing new writes nothing ---
# globals [plan] [rules template] -- setup's two il_global merge calls, as setup.sh makes them, on H2's global file.
globals() {
  H=$H2 IL_PLAN=${1:-} IL_WROTE=${1:+$T/gw} R=${2:-} lib 'il_record "$IL_MACHINE" merge "$IL_GLOBAL" && il_global merge claude-md "$IL_ROOT/templates/global-claude.md" --global-claude \
    && il_global merge rules "${R:-$IL_ROOT/templates/global-rules.md}" --global-rules' 2>&1; rm -f "$T/gw"
}
G=$H2/.claude/CLAUDE.md; mkdir -p "$H2/.claude"; printf 'my rules\n' > "$G"
globals >/dev/null; printf '\nmy tail\n' >> "$G"; cp "$G" "$T/g.once"; rm -f "$G".commandeck-bak-*
globals >/dev/null; globals >/dev/null
check "blocks: two more runs with the same templates leave the global file byte-identical" "" "$(cmp "$T/g.once" "$G" 2>&1)"
OUT=$(globals plan)
check "blocks: a plan with nothing new would change nothing and copy nothing" 0 "$(grep -c 'would' <<<"$OUT")"
{ cat "$REAL/templates/global-rules.md"; printf -- '- A rule only this test adds.\n'; } > "$T/rules2.md"
OUT=$(globals plan "$T/rules2.md")
check "blocks: a plan with one block's template changed would copy the file once and change it once" "1:1" \
  "$(grep -c 'would copy' <<<"$OUT"):$(grep -c "would change $G" <<<"$OUT")"
globals "" "$T/rules2.md" >/dev/null
blk() { awk -v b="<!-- commandeck:$1:begin -->" '$0 == b { on = 1 } on { print } $0 == "<!-- commandeck:'"$1"':end -->" { on = 0 }' "$2"; }
check "blocks: the changed block is replaced where it stands, the other untouched, the owner's text around them in place" "1:1:my rules:my tail" \
  "$(blk rules "$G" | grep -c 'A rule only this test adds'):$([ "$(blk claude-md "$G")" = "$(blk claude-md "$T/g.once")" ] && echo 1):$(head -1 "$G"):$(tail -1 "$G")"
check "blocks: the apply's backup holds the bytes from before it" "" "$(cmp "$T/g.once" "$G".commandeck-bak-* 2>&1)"
{ cat "$REAL/templates/global-claude.md"; printf -- '- A line only this test adds.\n'; } > "$T/claude2.md"
rm -f "$G".commandeck-bak-*; printf -- '- Another.\n' > "$T/rules3.md"
OUT=$(H=$H2 IL_PLAN=1 IL_WROTE=$T/gw lib 'il_record "$IL_MACHINE" merge "$IL_GLOBAL" && il_global block claude-md "$1" x && il_global block rules "$2" y' "$T/claude2.md" "$T/rules3.md" 2>&1); rm -f "$T/gw"
check "blocks: a plan that changes both blocks says it would copy the file once" 1 "$(grep -c 'would copy' <<<"$OUT")"

# Issue 315: a Codex launch rewrites config.toml holding locked the folder of the file it resolves to
# (codex-hook-trust.py). Setup's notify line waits for that lock: written at once, one of the two writes drops the
# other's lines. The home's config.toml is a link, as when two homes share one file: the home's own folder is not the lock.
H3=$T/h3; mkdir -p "$H3/.codex" "$T/shared3"; printf 'model = "m"\n' > "$T/shared3/config.toml"; ln -s "$T/shared3/config.toml" "$H3/.codex/config.toml"
exec 8<"$T/shared3"; flock 8
(H=$H3 lib 'il_notify "$IL_ROOT"') 8<&- & P=$!
sleep 2
check "notify: setup waits while a launch holds the linked config's folder" 0 "$(grep -c '^notify = ' "$T/shared3/config.toml")"
exec 8<&-; wait "$P"
check "notify: and writes its line once the launch lets go, keeping the rest" "1:1" "$(grep -c '^notify = ' "$T/shared3/config.toml"):$(grep -c '^model = "m"$' "$T/shared3/config.toml")"
# Sol r3: the link repointed between setup's read and its write. The new file keeps its own settings and gets the line.
mkdir -p "$T/old4" "$T/new4"; printf 'model = "old"\n' > "$T/old4/config.toml"; printf 'model = "new"\n' > "$T/new4/config.toml"
ln -sfn "$T/old4/config.toml" "$H3/.codex/config.toml"
NEW4=$T/new4/config.toml H=$H3 lib 'eval "real_$(declare -f il_read)"; il_read() { real_il_read "$1"; [ -e "$NEW4.moved" ] || { touch "$NEW4.moved"; ln -sfn "$NEW4" "$IL_CODEX/config.toml"; }; }; il_notify "$IL_ROOT"' >/dev/null 2>&1
check "notify: repointed after the read, the new file keeps its own settings and gets the line" "1:0:1" \
  "$(grep -c '^model = "new"$' "$T/new4/config.toml"):$(grep -c '^model = "old"$' "$T/new4/config.toml"):$(grep -c '^notify = ' "$T/new4/config.toml")"
# Sol r4, and the rest of its class: config.toml is not the file it was at the
# read (a link now, another file, or edited in place). Setup writes nothing over it; a link is retried at its target.
# Under set -e, as setup.sh and uninstall.sh run it: the refused write must not end the shell before the retry.
for how in link file edit; do
  H5=$T/h5$how; mkdir -p "$H5/.codex"; printf 'model = "old"\n' > "$H5/.codex/config.toml"; printf 'model = "new"\n' > "$T/new5$how.toml"
  OUT=$(HOW=$how NEW5=$T/new5$how.toml H=$H5 lib 'set -e; eval "real_$(declare -f il_read)"; il_read() { real_il_read "$1"; [ -e "$NEW5.moved" ] || { touch "$NEW5.moved"; c=$IL_CODEX/config.toml
    case $HOW in link) rm "$c"; ln -s "$NEW5" "$c" ;; file) printf "model = \"theirs\"\n" > "$c.x"; mv "$c.x" "$c" ;; *) printf "theirs = 1\n" >> "$c" ;; esac; }; }; il_notify "$IL_ROOT"' 2>&1)
  case $how in
    link) check "notify: file made a link after the read: the link is kept, its target keeps its settings and gets the line" "yes:1:1" \
      "$([ -L "$H5/.codex/config.toml" ] && echo yes):$(grep -c '^model = "new"$' "$T/new5link.toml"):$(grep -c '^notify = ' "$T/new5link.toml")" ;;
    file) check "notify: file replaced after the read: the new file is left as it is, and setup says so" "1:0:1" \
      "$(grep -c '^model = "theirs"$' "$H5/.codex/config.toml"):$(grep -c '^notify = ' "$H5/.codex/config.toml"):$(grep -c 'changed since it was read; nothing was written' <<<"$OUT")" ;;
    edit) check "notify: file edited after the read: the edit is kept, and setup says so" "1:0:1" \
      "$(grep -c '^theirs = 1$' "$H5/.codex/config.toml"):$(grep -c '^notify = ' "$H5/.codex/config.toml"):$(grep -c 'changed since it was read; nothing was written' <<<"$OUT")" ;;
  esac
done
# Sol r5: config.toml made a link before the first stat, its target edited after the read. Both stats see the one
# link, so its target's edit is not seen: only a regular file is trusted as the snapshot, and the link is retried at its target.
H6=$T/h6; mkdir -p "$H6/.codex"; printf 'model = "original"\n' > "$H6/.codex/config.toml"; printf 'model = "old"\n' > "$T/shared6.toml"
S6=$T/shared6.toml H=$H6 lib 'set -e; stat() { [ -e "$S6.linked" ] || { touch "$S6.linked"; rm "$IL_CODEX/config.toml"; ln -s "$S6" "$IL_CODEX/config.toml"; }; command stat "$@"; }
  eval "real_$(declare -f il_read)"; il_read() { real_il_read "$1"; [ -e "$S6.edited" ] || { touch "$S6.edited"; printf "model = \"theirs\"\n" > "$S6"; }; }; il_notify "$IL_ROOT"' >/dev/null 2>&1
check "notify: made a link before the first stat, its target edited after the read: the edit is kept and the target gets the line" "1:1" \
  "$(grep -c '^model = "theirs"$' "$T/shared6.toml"):$(grep -c '^notify = ' "$T/shared6.toml")"
# Sol r6: GNU stat translates %F ("fichier ordinaire" in French), so an unchanged regular file failed the regular check
# in a translated locale and setup stopped under set -e. The stand-in stat translates as coreutils does without LC_ALL=C.
H7=$T/h7; mkdir -p "$H7/.codex"; printf 'model = "owner"\n' > "$H7/.codex/config.toml"
H=$H7 lib 'set -e; export LC_ALL=fr_FR.UTF-8; stat() { if [ "${LC_ALL:-}" = C ]; then command stat "$@"; else command stat "$@" | sed "s/^regular file/fichier ordinaire/; s/^regular empty file/fichier vide ordinaire/"; fi; }
  il_notify "$IL_ROOT"' >/dev/null 2>&1
check "notify: stat translated in the owner's locale: the unchanged file still gets the line, its settings kept" "1:1" \
  "$(grep -c '^notify = ' "$H7/.codex/config.toml"):$(grep -c '^model = "owner"$' "$H7/.codex/config.toml")"
# Two setup runs (ticks) with one piece of the first run's state taken away between them: the second run writes the
# line into the file the home resolves to now, whichever piece is gone, and keeps its settings.
for gone in "the notify line" "the link's target, swapped for a fresh file" "the old target, the link replaced by a file"; do
  case $gone in
    "the notify line") sed -i.bak '/^notify = /d' "$T/new4/config.toml" ;;
    "the link's target"*) mkdir -p "$T/tick4"; printf 'model = "b"\n' > "$T/tick4/config.toml"; ln -sfn "$T/tick4/config.toml" "$H3/.codex/config.toml" ;;
    *) rm "$T/tick4/config.toml" "$H3/.codex/config.toml"; printf 'model = "c"\n' > "$H3/.codex/config.toml" ;;
  esac
  H=$H3 lib 'il_notify "$IL_ROOT"' >/dev/null 2>&1
  f=$(readlink -f "$H3/.codex/config.toml")
  check "notify ticks: $gone gone, the next run writes the line in the file the home names, its settings kept" "1:1" \
    "$(grep -c '^notify = ' "$f"):$(grep -c '^model = ' "$f")"
done

# --- Issue 314: a launched Codex pane must never stop on the CLI's update prompt, and Codex is updated outside panes ---
# Setup writes check_for_update_on_startup = false above the first table (a root key), next to the notify line and
# issue 315's trust tables, all kept; an owner's own key stays, quoted or not (tomllib decides, not a grep).
KEYTXT='check_for_update_on_startup = false # commandeck: no update prompt in launched panes'
H314=$T/h314; mkdir -p "$H314/.codex"
printf 'model = "m"\n\n[hooks.state."%s/hooks.json:pre_tool_use:0:0"]\ntrusted_hash = "sha256:0000"\nenabled = false\n' "$H314/.codex" > "$H314/.codex/config.toml"
cp "$H314/.codex/config.toml" "$T/c314.orig"
H=$H314 lib 'il_notify "$IL_ROOT"' >/dev/null 2>&1
rd() { python3 -c 'import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb")); print(d.get("check_for_update_on_startup"), d.get("model"), sorted(d.get("hooks", {})))' "$1" 2>&1; }
check "update check: setup writes the key once above the first table, model and 315's trust table kept" "1:False m ['state']:same" \
  "$(grep -cxF "$KEYTXT" "$H314/.codex/config.toml"):$(rd "$H314/.codex/config.toml"):$(diff <(grep -vE '^(notify|check_for_update_on_startup) ' "$H314/.codex/config.toml") "$T/c314.orig" >/dev/null && echo same)"
H=$H314 lib 'il_notify "$IL_ROOT"' >/dev/null 2>&1
check "update check: a second setup run does not double the key" 1 "$(grep -c '^check_for_update_on_startup' "$H314/.codex/config.toml")"
H=$H314 lib "il_notify ''" >/dev/null 2>&1
check "update check: uninstall takes out the plugin's lines and nothing else" same "$(cmp -s "$H314/.codex/config.toml" "$T/c314.orig" && echo same)"
for form in plain quoted; do
  H314b=$T/h314-$form; mkdir -p "$H314b/.codex"
  case $form in
    plain) printf 'check_for_update_on_startup = true\nnotify = ["x"]\nmodel = "m"\n' ;;
    quoted) printf '"check_for_update_on_startup" = true\n"notify" = ["x"]\n\n[hooks.state."%s/hooks.json:pre_tool_use:0:0"]\ntrusted_hash = "sha256:0000"\n' "$H314b/.codex" ;;
  esac > "$H314b/.codex/config.toml"
  cp "$H314b/.codex/config.toml" "$T/c314-$form.orig"
  H=$H314b lib 'il_notify "$IL_ROOT"' >/dev/null 2>&1
  check "update check: an owner's own $form key is kept, none is added, the file still parses with True" "same:True" \
    "$(cmp -s "$H314b/.codex/config.toml" "$T/c314-$form.orig" && echo same):$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["check_for_update_on_startup"])' "$H314b/.codex/config.toml" 2>&1)"
done
# Pass 1: the plugin's lines were filtered out of the whole text, so the same text inside an owner's multiline string
# was cut from the owner's value. Only the root keys are the plugin's: the string survives setup and uninstall.
H314m=$T/h314-ml; mkdir -p "$H314m/.codex"
printf 'developer_instructions = """\n%s\nnotify = ["/x/hooks/codex-notify.sh"]\n"""\n' "$KEYTXT" > "$H314m/.codex/config.toml"
cp "$H314m/.codex/config.toml" "$T/c314-ml.orig"
H=$H314m lib 'il_notify "$IL_ROOT"' >/dev/null 2>&1
ML=$(python3 -c 'import sys, tomllib
a, b = (tomllib.load(open(f, "rb")) for f in sys.argv[1:])
print(a["developer_instructions"] == b["developer_instructions"], a.get("check_for_update_on_startup"), "notify" in a)' "$H314m/.codex/config.toml" "$T/c314-ml.orig" 2>&1)
H=$H314m lib "il_notify ''" >/dev/null 2>&1
check "update check: the plugin's line text inside an owner's multiline string is kept by setup and uninstall" "True False True:same" \
  "$ML:$(cmp -s "$H314m/.codex/config.toml" "$T/c314-ml.orig" && echo same)"

# codex update: a fake codex (--version reads a file; update logs its argv, then runs update.sh) and a fake curl are
# first on PATH; no network, no real Codex. $FK/short holds a timeout that shrinks the first duration to 1 s.
export FK=$T/fk; mkdir -p "$FK/bin" "$FK/short"
cat > "$FK/bin/codex" <<'EOF'
#!/usr/bin/env bash
case $1 in
  --version) [ ! -e "$FK/version-hangs" ] || sleep 30; echo "codex-cli $(cat "$FK/version")" ;;
  update) echo "$*" >> "$FK/log"; . "$FK/update.sh" ;;
esac
EOF
cat > "$FK/bin/curl" <<'EOF'
#!/usr/bin/env bash
[ ! -e "$FK/curl-fails" ] || { echo "curl: (22) The requested URL returned error: 403" >&2; exit 22; }
echo '{"tag_name":"rust-v0.41.0"}'
EOF
printf '#!/usr/bin/env bash\na=(); d=; for x in "$@"; do case $x in --kill-after=*) a+=(--kill-after=1) ;; [0-9]*) [ -n "$d" ] && a+=("$x") || { a+=(1); d=1; } ;; *) a+=("$x") ;; esac; done\nexec %s "${a[@]}"\n' "$(command -v timeout)" > "$FK/short/timeout"
chmod +x "$FK"/bin/* "$FK/short/timeout"
# upd314 <installed> <update.sh body> -- il_codex_update's line in $L, its status in $RC, the fake's argv log in $FK/log
upd314() { echo "$1" > "$FK/version"; printf '%s\n' "$2" > "$FK/update.sh"; : > "$FK/log"; L=$(PATH=$FK/bin:$PATH lib 'il_codex_update'); RC=$?; }
upd314 0.40.0 'echo 0.41.0 > "$FK/version"'
check "codex update: a newer release runs codex update once and says updated 0.40.0 -> 0.41.0, status 0" "0:codex: updated 0.40.0 -> 0.41.0 (codex update):update" "$RC:$L:$(cat "$FK/log")"
upd314 0.41.0 'echo no >> "$FK/log"'
check "codex update: the latest runs nothing and says so, status 0" "0:codex: 0.41.0, the latest:" "$RC:$L:$(cat "$FK/log")"
upd314 0.40.0 'echo "installer broke" >&2; exit 1'
check "codex update: a failed update says FAILED with the installer's last line, status 1, Codex stays" "1:codex: update 0.40.0 -> 0.41.0 FAILED (installer broke); Codex stays on 0.40.0. Run: codex update" "$RC:$L"
# An updater that ignores TERM: the run ends at --kill-after, under the test's own timeout (a missing --kill-after fails the case, it does not hang the suite).
cat > "$T/c6.sh" <<'EOF'
. "$1/paths.sh" && . "$1/install-lib.sh" || exit 9
set -e; PLAN=
eval "$(grep 'il_codex_update plan' "$2")"
echo "next:${CUPD:-}"
EOF
echo 0.40.0 > "$FK/version"; echo "trap '' TERM; while :; do sleep 1; done" > "$FK/update.sh"
OUT=$(PATH=$FK/short:$FK/bin:$PATH lib "$(command -v timeout) 20 bash $T/c6.sh \"\$PP_SCRIPTS\" $REAL/scripts/setup.sh" 2>&1); RC=$?
check "codex update: an updater that ignores TERM is stopped within the bound, reported FAILED, and setup goes on" "0:1:2" \
  "$RC:$(grep -c '^next:codex: update 0.40.0 -> 0.41.0 FAILED (no end in' <<<"$OUT"):$(grep -c 'Codex stays on 0.40.0' <<<"$OUT")"   # 2: setup's own echo, then CUPD
echo 0.40.0 > "$FK/version"; : > "$FK/log"; L=$(PATH=$FK/bin:$PATH lib 'il_codex_update plan'); RC=$?
check "codex update: plan mode names the update and runs nothing" "0:plan: would update Codex 0.40.0 -> 0.41.0 (codex update):" "$RC:$L:$(cat "$FK/log")"
# Pass 1: an updater that exits 0 and leaves `codex --version` with no version (a broken install) said "updated 0.40.0 ->".
# Success needs a version read after the update, newer than before; a failure never claims the old Codex still runs.
upd314 0.40.0 ': > "$FK/version"'
check "codex update: exit 0 with no readable version after it is FAILED, status 1, never 'updated' or 'stays on'" "1:1:0:0" \
  "$RC:$(grep -c 'FAILED (it exited 0); codex --version now: ' <<<"$L"):$(grep -c 'updated' <<<"$L"):$(grep -c 'stays on' <<<"$L")"
# Both version probes are bounded (10 s, 1 s under $FK/short): a hung `codex --version`, before or after the update,
# ends the call reported, under this test's own 10 s.
printf '. "$1/paths.sh" && . "$1/install-lib.sh" || exit 9\nil_codex_update\n' > "$T/c7.sh"
echo 0.40.0 > "$FK/version"; touch "$FK/version-hangs"
L=$(PATH=$FK/short:$FK/bin:$PATH lib "$(command -v timeout) 10 bash $T/c7.sh \"\$PP_SCRIPTS\"" 2>&1); RC=$?; rm -f "$FK/version-hangs"
echo 'touch "$FK/version-hangs"' > "$FK/update.sh"
L2=$(PATH=$FK/short:$FK/bin:$PATH lib "$(command -v timeout) 10 bash $T/c7.sh \"\$PP_SCRIPTS\"" 2>&1); RC2=$?; rm -f "$FK/version-hangs"
check "codex update: a hung codex --version, before or after the update, is stopped and reported" "2:1:1:1" \
  "$RC:$(grep -c 'no answer in 10 s' <<<"$L"):$RC2:$(grep -c 'FAILED (it exited 0); codex --version now: no answer in 10 s' <<<"$L2")"
touch "$FK/curl-fails"; : > "$FK/log"
OUT=$(PATH=$FK/bin:$PATH lib "set -e; PLAN=1; eval \"\$(grep 'il_codex_update plan' $REAL/scripts/setup.sh)\"; echo next" 2>&1); RC=$?
check "setup --plan offline: the preview says latest unknown and goes on, running nothing" "0:1:1:" "$RC:$(grep -c 'latest unknown' <<<"$OUT"):$(grep -c '^next$' <<<"$OUT"):$(cat "$FK/log")"
rm -f "$FK/curl-fails"
echo 0.40.0 > "$FK/version"; echo 'echo "installer broke" >&2; exit 1' > "$FK/update.sh"
OUT=$(PATH=$FK/bin:$PATH lib "PLAN=; eval \"\$(grep -E 'NEED\\[@\\]|il_codex_update plan|^NOTES=\\(\\) NEED=\\(\\)|CUPD' $REAL/scripts/setup.sh)\"" 2>&1)
check "setup: a failed update is under Needs you in setup's report (the line sits after the NEED reset)" "Needs you:
  codex: update 0.40.0 -> 0.41.0 FAILED (installer broke); Codex stays on 0.40.0. Run: codex update" "$(grep -A1 '^Needs you:' <<<"$OUT")"
UL=$(grep -n 'il_codex_update' "$REAL/scripts/setup.sh" | head -1 | cut -d: -f1); PL=$(grep -nE 'orca-ide (worktree|terminal) create|open_pane "' "$REAL/scripts/setup.sh" | head -1 | cut -d: -f1)
check "setup: the Codex update call sits above the first pane-making line" yes "$([ -n "$UL" ] && [ -n "$PL" ] && [ "$UL" -lt "$PL" ] && echo yes)"


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] && { [ -z "${INSTALL_LIB_TEST_CASE-}" ] || [ "$PASS" -gt 0 ]; }
