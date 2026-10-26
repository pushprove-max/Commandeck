#!/usr/bin/env bash
# profile-revoke.test.sh -- the launch repair of a Claude profile's settings file, the lock every writer of that file and
# the manifest shares, and the owner's choices made with revoke.sh (taken out of install-lib.test.sh, whose fixtures
# made it run past the runner's limit). Each case runs install-lib.sh's functions or revoke.sh on its own scratch HOME
# and profile. PROFILE_REVOKE_TEST_CASE=<text> runs only the cases whose name holds <text>.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { case $1 in *"${PROFILE_REVOKE_TEST_CASE-}"*) ;; *) return 0 ;; esac; if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
PROJ=$T/proj
unset CLAUDE_CONFIG_DIR
git init -q -b main "$PROJ"

# --- pass 4: a revoke in another pane while a launch's repair runs is not undone ---
# Two panes share one profile file. The repair is held at one point of its read-modify-write (after it reads the record,
# or after it reads the manifest for its stamp); a revoke starts then. A revoke that ran inside the repair's window had
# its choice written over: the rule back in the file, or `revoked` gone from the manifest (the next launch puts it back).
RH=$T/race RP=$T/race/profile RULE='Bash(orca-ide terminal:*)'
mkdir -p "$RP" "$RH/.commandeck/install"
rlib() { (cd "$PROJ" && env -u CLAUDE_PROJECT_DIR -u ORCA_WORKTREE_ID -u ORCA_TERMINAL_HANDLE -u COMMANDECK_SCRATCH -u CODEX_HOME \
  COMMANDECK_MAIN="$PROJ" HOME="$RH" CLAUDE_CONFIG_DIR="$RP" bash -c 'set -o pipefail; . "$0/paths.sh" && . "$0/install-lib.sh" && c=$1 && shift && eval "$c"' "$REAL/scripts" "$@"); }
HOLD='hold() { touch "$HOME/ready"; while [ ! -e "$HOME/release" ]; do sleep 0.05; done; }'
# race <label> <shell that redefines a function to call hold, then runs the repair>
race() {
  local rp vp rc1 rc2 i
  rm -f "$RH/ready" "$RH/release"; echo '{}' > "$RP/settings.json"
  jq -n --arg f "$RP/settings.json" --arg r "$RULE" '{version: 1, entries: {($f): {kind: "merge", added: [$r, "Bash(git worktree:*)"]}}}' > "$RH/.commandeck/install/_machine.json"
  rlib "$HOLD; $2; il_profile_repair \"\$IL_MACHINE\" \"\$CLAUDE_CONFIG_DIR/settings.json\"" & rp=$!
  for i in $(seq 200); do [ ! -e "$RH/ready" ] || break; sleep 0.05; done
  rlib 'bash "$PP_SCRIPTS/revoke.sh" rule "$1"' "$RULE" >/dev/null & vp=$!
  sleep 1; touch "$RH/release"   # a revoke that waits for the repair's lock is still waiting here
  wait "$rp"; rc1=$?; wait "$vp"; rc2=$?
  check "$1" "0:0:true:false" "$rc1:$rc2:$(jq --arg f "$RP/settings.json" --arg r "$RULE" '.entries[$f].revoked.added // [] | index($r) != null' "$RH/.commandeck/install/_machine.json"):$(jq --arg r "$RULE" '.permissions.allow // [] | index($r) != null' "$RP/settings.json")"
}
race "pass 4: a revoke while the repair holds the record it read stays revoked: on the list, and out of the file" \
  'eval "$(declare -f il_profile_record | sed "1s/il_profile_record/read_record/")"; il_profile_record() { local s; s=$(read_record "$@") || return; hold; printf "%s\n" "$s"; }'
race "pass 4: a revoke while the repair's stamp holds the manifest it read stays revoked: on the list, and out of the file" \
  'eval "$(declare -f il_write | sed "1s/il_write/write_now/")"; il_write() { [ "$1" != "$IL_MACHINE" ] || hold; write_now "$@"; }'
# Setup takes the lock with its own line, before its first write: a second pane's launch repair waits for it.
rm -f "$RH/ready" "$RH/release"; echo '{}' > "$RP/settings.json"
rlib "$HOLD; PLAN=; die() { exit 1; }; $(grep -F 'il_profile_lock 60' "$REAL/scripts/setup.sh"); hold" & SP=$!
for i in $(seq 200); do [ ! -e "$RH/ready" ] || break; sleep 0.05; done
rlib 'il_profile_repair "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json"' & RPID=$!
sleep 1; W=$(kill -0 "$RPID" 2>/dev/null && echo waiting):$(jq -c . "$RP/settings.json")
touch "$RH/release"; wait "$SP"; wait "$RPID"; RC=$?
check "pass 4: a launch repair in a second pane while setup holds the lock waits, then repairs (the rule revoked above left out)" \
  "waiting:{}:0:1" "$W:$RC:$(jq '.permissions.allow // [] | length' "$RP/settings.json")"
# The retry needs no state but the file and the manifest: a repair that misses the lock writes nothing; with the
# stamp taken out of the manifest the next launch repairs (the owner's list still honoured), and with the list taken
# out too it repairs whole.
echo '{}' > "$RP/settings.json"
jq --arg f "$RP/settings.json" '.entries[$f].revoked = {added: ["Bash(git worktree:*)"]}' "$RH/.commandeck/install/_machine.json" > "$T/m" && mv "$T/m" "$RH/.commandeck/install/_machine.json"
OUT=$(rlib '( exec 9<"$IL_DIR"; flock 9; touch "$HOME/held"; sleep 3 ) & while [ ! -e "$HOME/held" ]; do sleep 0.05; done
  il_profile_lock 1; echo "miss=$?:fd=${IL_PROFILE_LOCK_FD:-none}"' 2>/dev/null); rm -f "$RH/held"
check "pass 4: a lock not taken in time is let go and not held" "miss=1:fd=none" "$OUT"
for s in repaired:1 revoked:2; do n=${s#*:} s=${s%:*}
  jq --arg f "$RP/settings.json" --arg s "$s" 'del(.entries[$f][$s])' "$RH/.commandeck/install/_machine.json" > "$T/m" && mv "$T/m" "$RH/.commandeck/install/_machine.json"
  check "pass 4: with $s taken out between two launches, the next launch still repairs" "0:$n:$s" \
    "$(rlib 'il_profile_repair "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json"'; echo $?):$(jq '.permissions.allow // [] | length' "$RP/settings.json"):$s"
  echo '{}' > "$RP/settings.json"
done
# Setup lets the lock go before it opens the relay's pane, whose launch repair takes it: a profile-file or manifest
# write after that line runs unlocked. Every such write goes through il_write, so the writers are il_write and each
# function of install-lib.sh or setup.sh whose body calls a writer (a fixed point); no code line after the release calls one.
late_writes() {
  awk '
    FNR == 1 { file++ }
    /^[A-Za-z_][A-Za-z0-9_]*\(\) / { n = $0; sub(/\(\).*/, "", n); one = ($0 ~ /\}$/) }
    n { b[n] = b[n] "\n" $0; if (one || /^}/) n = "" }
    file == 2 && !rel && /^\[ -z "\$\{IL_PROFILE_LOCK_FD:-\}" \] \|\| \{ exec/ { rel = FNR; next }
    file == 2 && rel && !/^[[:space:]]*#/ { late[++nl] = FNR ": " $0 }
    function calls(s, x) { return s ~ ("(^|[^A-Za-z0-9_])" x "([^A-Za-z0-9_]|$)") }
    END {
      w["il_write"] = 1
      do { more = 0; for (f in b) if (!(f in w)) for (x in w) if (calls(b[f], x)) { w[f] = 1; more = 1; break } } while (more)
      if (!rel) print "no release line"
      for (i = 1; i <= nl; i++) for (x in w) if (calls(late[i], x)) { print late[i]; break }
    }' "$REAL/scripts/install-lib.sh" "$1"
}
awk '/^\[ -z "\$\{IL_PROFILE_LOCK_FD:-\}" \] \|\| \{ exec/ { print "late_set() { il_set \"$IL_PROJECT\" .; }"; print; print "late_set"; next } 1' \
  "$REAL/scripts/setup.sh" > "$T/setup-late.sh"
check "pass 5: setup makes no profile-file or manifest write after it lets go of the lock (and the guard sees one made through a function)" \
  ":1" "$(late_writes "$REAL/scripts/setup.sh"):$(late_writes "$T/setup-late.sh" | grep -c ': late_set$')"

# --- pass 7 (class revoked-option-restoration): a launch's copy holding a value the owner took out does not keep it ---
# Orca's copy of the home file can hold setup's own values (the home file is setup's too, or a copy of this file). A
# value revoked without --keep is out of the file after the launch as revoke.sh left it: a rule and an auto-mode line
# out, the status line back to the one before setup's, an option gone. A value of the owner's own there stays, as revoke leaves it.
SL='{"type":"command","command":"plugin-line"}' WAS='{"type":"command","command":"owner-home"}'
jq -n --arg f "$RP/settings.json" --arg r "$RULE" --argjson sl "$SL" --argjson was "$WAS" '{version: 1, entries: {($f): {kind: "merge",
  added: [$r, "Bash(git worktree:*)"], autoMode: {added: ["line one", "line two"]}, statusLine: {was: $was, set: $sl},
  optionsWant: {"commandeck@commandeck": {builderModel: "sonnet", ponytail: "lite"}},
  revoked: {added: [$r], autoMode: ["line one"], statusLine: {keep: null}, options: {"commandeck@commandeck": {builderModel: {keep: null}}}}}}}' \
  > "$RH/.commandeck/install/_machine.json"
jq -n --arg r "$RULE" --argjson sl "$SL" '{permissions: {allow: ["Bash(ls:*)", $r, "Bash(git worktree:*)"]}, autoMode: {environment: ["$defaults", "line one", "line two"]},
  statusLine: $sl, pluginConfigs: {"commandeck@commandeck": {options: {builderModel: "sonnet", ponytail: "lite"}}}}' > "$RP/settings.json"
RC=$(rlib 'il_profile_repair "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json"'; echo $?)
check "pass 7: revoked-option-restoration: a copy holding setup's revoked rule, auto-mode line, status line and option is put back as revoke left it" \
  '0:["Bash(ls:*)","Bash(git worktree:*)"]:["$defaults","line two"]:"owner-home":{"ponytail":"lite"}' \
  "$RC:$(jq -c '.permissions.allow' "$RP/settings.json"):$(jq -c '.autoMode.environment' "$RP/settings.json"):$(jq -c '.statusLine.command' "$RP/settings.json"):$(jq -c '.pluginConfigs["commandeck@commandeck"].options' "$RP/settings.json")"
check "pass 7: revoked-option-restoration: the doctor's stamp names the four kinds taken out" '["autoMode","options","permissions","statusLine"]' \
  "$(jq -c --arg f "$RP/settings.json" '.entries[$f].repaired.keys | sort' "$RH/.commandeck/install/_machine.json")"
S1=$(jq -cS . "$RP/settings.json") M1=$(jq -cS . "$RH/.commandeck/install/_machine.json")
rlib 'il_profile_repair "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json"'
check "pass 7: revoked-option-restoration: the next launch with nothing changed writes nothing" "$S1:$M1" "$(jq -cS . "$RP/settings.json"):$(jq -cS . "$RH/.commandeck/install/_machine.json")"
jq '.statusLine.command = "mine" | .pluginConfigs["commandeck@commandeck"].options.builderModel = "opus"' "$RP/settings.json" > "$T/s" && mv "$T/s" "$RP/settings.json"
S1=$(jq -cS . "$RP/settings.json"); rlib 'il_profile_repair "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json"'
check "pass 7: revoked-option-restoration: the owner's own status line and option value, set after the revoke, stay" "$S1" "$(jq -cS . "$RP/settings.json")"

# --- pass 8 (class revoked-option-restoration, again): no writer of a kind the owner can revoke puts it back ---
# A setup rerun (an update runs one) writes the status line and /config's options again from its own answers. A value
# the owner took out with revoke.sh stays out, as the rule and auto-mode setters leave theirs out. The launch is the
# retry: it takes a revoked value out of a copy from the owner's list alone, whatever else of the record is gone.
RM8=$RH/.commandeck/install/_machine.json
copy8() { jq -n --argjson sl "$SL" '{statusLine: $sl, pluginConfigs: {"commandeck@commandeck": {options: {ponytail: "lite", k: "new"}}}}' > "$RP/settings.json"; }
got8() { jq -c '[.statusLine.command, (.pluginConfigs["commandeck@commandeck"].options // {} | has("ponytail")), .pluginConfigs["commandeck@commandeck"].options.k]' "$RP/settings.json"; }
jq -n --arg f "$RP/settings.json" --argjson sl "$SL" --argjson was "$WAS" '{version: 1, entries: {($f): {kind: "merge", statusLine: {was: $was, set: $sl},
  options: {"commandeck@commandeck": {ponytail: "lite", k: "new"}}, optionsWant: {"commandeck@commandeck": {ponytail: "lite", k: "new"}}}}}' > "$RM8"
copy8
rlib 'bash "$PP_SCRIPTS/revoke.sh" option commandeck@commandeck ponytail && bash "$PP_SCRIPTS/revoke.sh" status-line' >/dev/null
RC=$(rlib 'il_plugin_options "$CLAUDE_CONFIG_DIR/settings.json" "{\"ponytail\":\"lite\",\"k\":\"new\"}" "{}" && il_status_set "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json" plugin-line' >/dev/null; echo $?)
check "pass 8: revoked-option-restoration: a setup rerun leaves the revoked option and status line out, and sets the rest" \
  '0:["owner-home",false,"new"]' "$RC:$(got8)"
# Main's ruling: the list wins over this run's own --option answer too, and setup names each value it left out and the
# command that takes it off the list.
OUT=$(rlib 'il_plugin_options "$CLAUDE_CONFIG_DIR/settings.json" "{}" "{\"ponytail\":\"full\"}" && il_status_set "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json" plugin-line' 2>&1)
check "pass 8: revoked-option-restoration: an explicit --option answer for a revoked option is left out too, and setup says so with the undo command" \
  '["owner-home",false,"new"]:1:1' "$(got8):$(grep -c '^option commandeck@commandeck ponytail: chosen with /commandeck:revoke.*/commandeck:revoke undo option commandeck@commandeck ponytail' <<<"$OUT"):$(grep -c '^status-line: chosen with /commandeck:revoke.*/commandeck:revoke undo status-line' <<<"$OUT")"
for s in repaired options optionsWant statusLine; do
  jq --arg f "$RP/settings.json" --arg s "$s" 'del(.entries[$f][$s])' "$RM8" > "$T/m" && mv "$T/m" "$RM8"
  copy8
  check "pass 8: revoked-option-restoration: with $s taken out between two launches, a copy holding setup's values still has the revoked ones taken out" \
    '0:["owner-home",false,"new"]' "$(rlib 'il_profile_repair "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json"' >/dev/null; echo $?):$(got8)"
done
# Only revoke.sh clears the list: undo takes a value off it, and the next launch puts setup's value back.
jq -n --arg f "$RP/settings.json" --arg r "$RULE" --argjson sl "$SL" --argjson was "$WAS" '{version: 1, entries: {($f): {kind: "merge", added: [$r],
  statusLine: {was: $was, set: $sl}, optionsWant: {"commandeck@commandeck": {ponytail: "lite", k: "new"}}}}}' > "$RM8"
copy8
rlib 'for w in "option commandeck@commandeck ponytail" status-line; do bash "$PP_SCRIPTS/revoke.sh" $w; done; bash "$PP_SCRIPTS/revoke.sh" rule "$1"' "$RULE" >/dev/null
RC=$(rlib 'bash "$PP_SCRIPTS/revoke.sh" undo option commandeck@commandeck ponytail && bash "$PP_SCRIPTS/revoke.sh" undo status-line && bash "$PP_SCRIPTS/revoke.sh" undo rule "$1"' "$RULE" >/dev/null; echo $?)
echo '{}' > "$RP/settings.json"; rlib 'il_profile_repair "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json"'
check "pass 8: revoked-option-restoration: revoke.sh undo takes the option, status line and rule off the list, and the next launch puts setup's back" \
  '0:{}:["plugin-line",true,"new"]:1' "$RC:$(jq -c --arg f "$RP/settings.json" '.entries[$f].revoked | with_entries(select(.value | . != [] and . != {}))' "$RM8"):$(got8):$(jq '.permissions.allow | length' "$RP/settings.json")"
RC=$(for a in "undo status-line" "undo" "undo status-line --keep"; do rlib 'bash "$PP_SCRIPTS/revoke.sh" $1 2>/dev/null' "$a"; printf '%s ' $?; done)
check "pass 8: revoked-option-restoration: undo of a value not on the list is refused, and undo with nothing or with --keep is usage" "1 2 2 " "$RC"


# A machine with no manifest yet (setup --plan writes none): no record, an empty answer, where jq's error on the missing
# file ended setup --plan under set -e with exit 2 and no message.
eval "$(sed -n '/^il_profile_record()/,/^}/p' "$REAL/scripts/install-lib.sh")"
check "a manifest that does not exist yet is no record (empty, exit 0)" "0:" "$(r=$(il_profile_record "$T/none.json" "$T/s.json"); echo "$?:$r")"
echo '{' > "$T/bad.json"
check "a manifest that is not JSON still fails" 1 "$(il_profile_record "$T/bad.json" "$T/s.json" >/dev/null; [ $? -ne 0 ] && echo 1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] && { [ -z "${PROFILE_REVOKE_TEST_CASE-}" ] || [ "$PASS" -gt 0 ]; }
