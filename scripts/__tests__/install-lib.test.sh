#!/usr/bin/env bash
# install-lib.test.sh -- the install's data-safety rules, on a hand-written HOME, by the functions setup.sh and
# uninstall.sh call (no whole run of either). What this pins: another tool's Codex hooks keep their places and
# its trust entries stay as they were, since Codex keys trust by position; the manifest records what was at a path
# with its hash and keeps the bytes; the restore puts those bytes back, and leaves a file edited since and names it;
# a plan writes nothing, manifest included. INSTALL_LIB_TEST_CASE=<text> runs only the cases whose name holds <text>.
# The routing-file cases are in install-lib-routing.test.sh and the setup-step cases in install-lib-setup.test.sh
# (split for the shell-test time budget; each starts from the same hand-written HOME).
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
# Issue 333: the relay line names auto-decided answers. A machine set up by the old wording gets the new line in its
# place on the next add, and uninstall still takes out everything setup added.
rm -rf "$H/.commandeck"; rm -f "$AS"; auto add >/dev/null
check "the relay line says the relay's own decisions are titled auto-decided and main checks them against the ledger" 1 \
  "$(jq -r '.autoMode.environment[2]' "$AS" | grep -c 'while auto-decide is on it also sends its own decisions, titled auto-decided, which main checks against the decisions ledger instead')"
OLDL='Key internal services: Orca panes on this machine. The relay pane (the worktree ending in /Chief-of-Staff) passes the owner'"'"'s answers to main word for word; main checks each against the owner'"'"'s ruling log before acting.'
jq -c --arg o "$OLDL" '.autoMode.environment[2] = $o' "$AS" > "$T/as" && mv "$T/as" "$AS"
jq -c --arg f "$AS" --arg o "$OLDL" '.entries[$f].autoMode.added[1] = $o' "$MM" > "$T/mm" && mv "$T/mm" "$MM"
auto add >/dev/null
check "after an update from the old line, the list holds the new line once and the old line not at all" '3:1:0' \
  "$(jq '.autoMode.environment | length' "$AS"):$(jq -r '.autoMode.environment[] | select(contains("titled auto-decided"))' "$AS" | grep -c .):$(jq -r --arg o "$OLDL" '.autoMode.environment[] | select(. == $o)' "$AS" | grep -c .)"
check "and the record holds the same two lines" '2:0' "$(jq --arg f "$AS" '.entries[$f].autoMode.added | length' "$MM"):$(jq --arg f "$AS" --arg o "$OLDL" '.entries[$f].autoMode.added | map(select(. == $o)) | length' "$MM")"
auto remove >/dev/null
check "uninstall removes it" 'null' "$(jq -c '.autoMode' "$AS")"
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
# Issue 334: two records, two jobs. `options` is uninstall's (only the keys setup added where /config had none); `optionsWant`
# is the repair's (every value setup wrote, an explicit --option answer over the owner's value included).
fresh; mkdir -p "${MM%/*}"; echo '{"version": 1, "entries": {}}' > "$MM"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"k": "old"}}}}' > "$PB"
CLAUDE_CONFIG_DIR=${PB%/settings.json} lib 'il_plugin_options "$1" "{\"ponytail\": \"lite\"}" "{\"k\": \"new\"}"' "$PB" >/dev/null
check "il_plugin_options records an explicit replacement in optionsWant and not in options" '{"ponytail":"lite"}:{"k":"new","ponytail":"lite"}' \
  "$(jq -c --arg p "$PB" '.entries[$p].options["commandeck@commandeck"]' "$MM"):$(jq -cS --arg p "$PB" '.entries[$p].optionsWant["commandeck@commandeck"]' "$MM")"
CLAUDE_CONFIG_DIR=${PB%/settings.json} lib 'il_plugin_options_out "$IL_MACHINE" "$1"' "$PB"
check "uninstall then leaves k=new and removes only the keys setup added" '{"k":"new"}' "$(jq -c '.pluginConfigs["commandeck@commandeck"].options' "$PB")"
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

# --- the subagents' prompt-cache lifetime (issue 367): the worker answer, and setup's own earlier value moves while an owner's own stays ---
CM=$T/cm.json CS=$T/cs.json
ttl() { lib 'il_cache_ttl "$1" "$2" '"${1:-}" "$CM" "$CS" 2>&1; }
echo '{"entries":{}}' > "$CM"
echo '{"promptCacheTtl":"5m","subagentPromptCacheTtl":"1h"}' > "$CS"
jq --arg p "$CS" '.entries[$p].cacheTtl = {subagentPromptCacheTtl: "1h"}' "$CM" > "$CM.n" && mv "$CM.n" "$CM"
ttl 5m >/dev/null
check "an update moves the 1h an earlier setup wrote to the worker answer 5m, in the file and in the record" '5m:5m' "$(jq -r .subagentPromptCacheTtl "$CS"):$(jq -r --arg p "$CS" '.entries[$p].cacheTtl.subagentPromptCacheTtl' "$CM")"
echo '{}' > "$CS"; echo '{"entries":{}}' > "$CM"
ttl 1h >/dev/null
check "il_cache_ttl writes subagentPromptCacheTtl with the worker answer and never promptCacheTtl" '1h:null' "$(jq -r .subagentPromptCacheTtl "$CS"):$(jq -r .promptCacheTtl "$CS")"
echo '{"subagentPromptCacheTtl":"1h"}' > "$CS"; echo '{"entries":{}}' > "$CM"
ttl 5m >/dev/null
check "a 1h the owner set (no record) stays 1h" '1h' "$(jq -r .subagentPromptCacheTtl "$CS")"
ttl off >/dev/null
check "taking setup's keys out leaves the owner's own 1h" '{"subagentPromptCacheTtl":"1h"}' "$(jq -c . "$CS")"
echo '{"promptCacheTtl":"1h"}' > "$CS"; echo '{"entries":{}}' > "$CM"
ttl 5m >/dev/null
check "il_cache_ttl never writes promptCacheTtl, and leaves an owner's own promptCacheTtl as it is" '{"promptCacheTtl":"1h","subagentPromptCacheTtl":"5m"}' "$(jq -cS . "$CS")"

# --- a config from before 0.15.0 holds the cache answer as "recommended" or "default": /commandeck:update replays it ---
# A replay that read the old word as 5m would move an owner's 1h unasked, and one that said nothing would leave the
# question unasked for good. setup.sh's own lines for the worker answer (the read, its /config merge, the gate on
# il_cache_ttl, the Needs-you line) run on a hand-written config, as requirements.test.sh runs one of its lines;
# il_cache_ttl is a counter, no setup run. A line that is gone fails the harness loud: a rename cannot make the cases no-ops.
replay() {
  echo "$1" > "$T/replay.json"
  ( IL_CONFIG=$T/replay.json IL_PROJECT=p PSET=s NEED=() calls=0 CLAUDE_CONFIG_DIR=$T/replay-cc GIVEN={}
    il_cache_ttl() { calls=$((calls + 1)); }
    eval "$(sed -n '/^PP_OPTS_KEY=/,/^}/p' "$REAL/scripts/paths.sh")"
    for l in '^old()' 'WCACHE=$(old .workerCacheTtl)' '^MCACHE_ON=' 'case $WCACHE_ON in 5m|1h) il_cache_ttl' 'Builder and worker prompt cache: not answered since 0.48.0'; do
      s=$(grep -F -- "$l" "$REAL/scripts/setup.sh" || grep -- "$l" "$REAL/scripts/setup.sh") || true
      [ -n "$s" ] || { echo "setup.sh has no line matching $l"; exit 0; }
      eval "$s"
    done
    echo "$calls:${#NEED[@]}" )
}
mkdir -p "$T/replay-cc" && echo '{}' > "$T/replay-cc/settings.json"
check "a stored \"recommended\" is not an answer: nothing is written, and the question is asked" 0:1 "$(replay '{"workerCacheTtl":"recommended"}')"
check "a stored \"default\" is the same" 0:1 "$(replay '{"workerCacheTtl":"default"}')"
check "a config with no answer is asked" 0:1 "$(replay '{"version":1}')"
check "an old stored cacheTtl is no answer: nothing is written and the worker question is asked" 0:1 "$(replay '{"cacheTtl":"5m"}')"
check "a stored 5m is written again on every replay, and not asked" 1:0 "$(replay '{"workerCacheTtl":"5m"}')"
check "a stored 1h is written again on every replay, and not asked" 1:0 "$(replay '{"workerCacheTtl":"1h"}')"
check "a stored leave writes nothing and is not asked" 0:0 "$(replay '{"workerCacheTtl":"leave"}')"
echo '{"pluginConfigs": {"commandeck@commandeck": {"options": {"workerPromptCacheTtl": "5m"}}}}' > "$T/replay-cc/settings.json"
check "a /config 5m beats a stored leave: the 5m is written, and nothing is asked (issue 245)" 1:0 "$(replay '{"workerCacheTtl":"leave"}')"
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
# --full-suite answer as its case arm passes it (on, off, or '' for none given). No setup run.
full() {
  echo "$1" > "$T/full.json"
  lib 'S=$(cat "$0/setup.sh"); IL_CONFIG=$1; il_write() { cat; }; CMODELS={} RL={} GEN=null DROPS={} CUTS={} BUILDER={}
    eval "$(grep "^old()" <<<"$S")"; eval "$(grep "^PROFILE=\$(old .profile)" <<<"$S")"; eval "$(grep "^FULL=\$(old " <<<"$S")"
    F=$(sed -n "/^given()/p;/^full_suite_answer()/,/^}/p;/^full_suite_rule()/,/^}/p" <<<"$S")
    [ "$(grep -c "()" <<<"$F")" = 3 ] || { echo "setup.sh lost given, full_suite_answer or full_suite_rule"; exit 0; }
    eval "$F"; GIVEN={} FULL_ASKED= FULL_OFF_NOTE=
    [ -z "$2" ] || full_suite_answer "$2"
    full_suite_rule
    { eval "$(sed -n "/^jq -n --argjson v \"\$IL_VERSION\"/,/| il_write \"\$IL_CONFIG\"$/p" <<<"$S")"; } | jq -c .fullSuiteBeforeFinal' "$T/full.json" "$2"
}
check "--full-suite on is saved as true" true "$(full '{"version":1,"testCommand":"t"}' on)"
check "a re-run with no answer keeps on as saved" true "$(full '{"version":1,"testCommand":"t","fullSuiteBeforeFinal":true}' '')"
check "a re-run with no answer keeps off as saved, not dropped" false "$(full '{"version":1,"testCommand":"t","fullSuiteBeforeFinal":false}' '')"
check "with no test command a saved on is recorded off: the closing pass would have no suite to run" false "$(full '{"version":1,"fullSuiteBeforeFinal":true}' '')"

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


echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] && { [ -z "${INSTALL_LIB_TEST_CASE-}" ] || [ "$PASS" -gt 0 ]; }
