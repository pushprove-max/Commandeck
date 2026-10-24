#!/usr/bin/env bash
# Orca copies ~/.claude/settings.json over a profile's settings.json at a launch, and setup's status line, /config
# options, auto-mode lines and permission rules go with it. The SessionStart hook puts them back in the active
# profile's file, and never writes the shared home file. Pinned: an overwritten profile file gets setup's settings
# back and keeps the owner's own keys; the home file and another profile's file are untouched byte for byte; no
# profile means no write; an explicit --option answer that replaced the owner's value comes back; a rule revoked with
# /commandeck:revoke stays out, a copy that holds it included. Setup's steps run as the install-lib functions setup.sh calls, not setup.sh whole.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
H=$T/home PROJ=$T/proj PA=$T/profiles/A PB=$T/profiles/B HOMEF=$T/home/.claude/settings.json
mkdir -p "$H/.claude" "$PA" "$PB" && git init -q -b main "$PROJ"
unset CLAUDE_CONFIG_DIR
env_() { env -u CLAUDE_PROJECT_DIR -u ORCA_WORKTREE_ID -u ORCA_TERMINAL_HANDLE -u COMMANDECK_SCRATCH -u CODEX_HOME COMMANDECK_MAIN="$PROJ" HOME="$H" "$@"; }
# lib <profile dir> <shell> -- the install-lib functions, run in the project under that profile.
lib() { local p=$1; shift; (cd "$PROJ" && env_ CLAUDE_CONFIG_DIR="$p" bash -c 'set -o pipefail; . "$0/paths.sh" && . "$0/install-lib.sh" && eval "$1"' "$REAL/scripts" "$@"); }
# hook <profile dir|-> <startup|resume|clear> -- the hook, as a launch, a /resume or a /clear runs it.
hook() { local p=$1; [ "$p" != - ] || p=
  (cd "$PROJ" && env_ ${p:+CLAUDE_CONFIG_DIR="$p"} bash "$REAL/hooks/profile-settings.sh" <<<"{\"hook_event_name\":\"SessionStart\",\"source\":\"$2\"}" >/dev/null 2>&1); }
home_file='{"theme": "dark", "statusLine": {"type": "command", "command": "owner-home"}, "permissions": {"allow": ["Bash(ls:*)"]},
  "pluginConfigs": {"commandeck@commandeck": {"options": {"k": "old"}}}}'
fresh() { rm -rf "$H/.commandeck"; echo "$home_file" > "$HOMEF"; cp "$HOMEF" "$PA/settings.json"; cp "$HOMEF" "$PB/settings.json"; }
# Setup under profile A: its rules, auto-mode lines, options (k=new replaces the owner's k=old) and status line.
setup_a() { lib "$PA" 'S=$CLAUDE_CONFIG_DIR/settings.json; il_record "$IL_MACHINE" merge "$S" && il_status_was "$IL_MACHINE" "$S" \
  && il_allow_set "$IL_MACHINE" "$S" "$(il_allow "$IL_ROOT")" && il_auto_mode "$IL_MACHINE" "$S" add >/dev/null \
  && il_plugin_options "$S" "{\"ponytail\": \"lite\"}" "{\"k\": \"new\"}" >/dev/null && il_status_set "$IL_MACHINE" "$S" plugin-line'; }
sha() { sha256sum < "$1" | cut -c1-16; }

fresh; setup_a
check "setup under a fake profile wrote its status line and the replaced option" "plugin-line:new" "$(jq -r '.statusLine.command' "$PA/settings.json"):$(jq -r '.pluginConfigs["commandeck@commandeck"].options.k' "$PA/settings.json")"
HB=$(sha "$HOMEF") BB=$(sha "$PB/settings.json")
check "setup never wrote the home file or a second profile's file" "$HB:$BB" "$(sha "$HOMEF"):$(sha "$PB/settings.json")"
cp "$HOMEF" "$PA/settings.json"   # the launch: Orca copies the home file over the profile's
hook "$PA" startup
D=$(jq -c '[.statusLine.command, .pluginConfigs["commandeck@commandeck"].options.ponytail, (.autoMode.environment | length), (.permissions.allow | map(select(startswith("Bash(orca-ide orchestration"))) | length), .theme, .permissions.allow[0]]' "$PA/settings.json")
check "setup under a fake profile, then the home file copied over the profile's file, then session start: setup's status line, options, auto-mode lines and permission rules are back, the owner's keys stay" \
  '["plugin-line","lite",3,1,"dark","Bash(ls:*)"]' "$D"
check "an explicit --option k=new that replaced the profile's k=old comes back after the copy" "new" "$(jq -r '.pluginConfigs["commandeck@commandeck"].options.k' "$PA/settings.json")"
check "the home file and a second profile's file are byte for byte the same after session start" "$HB:$BB" "$(sha "$HOMEF"):$(sha "$PB/settings.json")"
check "the repair is stamped for the doctor" "statusLine" "$(jq -r --arg p "$PA/settings.json" '.entries[$p].repaired.keys | join(",") | split(",")[] | select(. == "statusLine")' "$H/.commandeck/install/_machine.json")"
A1=$(sha "$PA/settings.json") M1=$(sha "$H/.commandeck/install/_machine.json"); hook "$PA" startup; hook "$PA" clear
check "a second launch and a /clear with nothing changed write nothing, the file or the manifest" "$A1:$M1" "$(sha "$PA/settings.json"):$(sha "$H/.commandeck/install/_machine.json")"
# Claude Code's own write to a key setup does not own (/effort) is harmless: the next copy is still repaired.
cp "$HOMEF" "$PA/settings.json"; jq '.effortLevel = "high"' "$PA/settings.json" > "$T/a.new" && mv "$T/a.new" "$PA/settings.json"; hook "$PA" startup
check "an effortLevel write after the copy does not stop the repair" "plugin-line:high" "$(jq -r '.statusLine.command + ":" + .effortLevel' "$PA/settings.json")"

# No profile: nothing is written, whatever the files hold.
fresh; setup_a; cp "$HOMEF" "$PA/settings.json"
HB=$(sha "$HOMEF") AB=$(sha "$PA/settings.json") MB=$(sha "$H/.commandeck/install/_machine.json")
hook - startup
check "with CLAUDE_CONFIG_DIR unset, session start writes nothing" "$HB:$AB:$MB" "$(sha "$HOMEF"):$(sha "$PA/settings.json"):$(sha "$H/.commandeck/install/_machine.json")"
# A profile file setup never wrote to is not touched.
hook "$PB" startup
check "a profile setup never recorded is left byte for byte" "$BB" "$(sha "$PB/settings.json")"

# Uninstall after a repair takes out what setup added and leaves the owner's keys; the home file is never written.
fresh; setup_a; cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
jq '.mine = 1' "$PA/settings.json" > "$T/a.new" && mv "$T/a.new" "$PA/settings.json"
HB=$(sha "$HOMEF")
lib "$PA" 'il_profiles_out "$IL_MACHINE"' >/dev/null 2>&1
check "uninstall after a repair removes setup's rules, auto-mode lines and status line, keeps the owner's key and option k=new" '[null,null,1,"new"]' \
  "$(jq -c '[.autoMode, (.permissions.allow | map(select(startswith("Bash(orca-ide"))) | if length == 0 then null else . end), .mine, .pluginConfigs["commandeck@commandeck"].options.k]' "$PA/settings.json")"
check "and the home file is still byte for byte the same" "$HB" "$(sha "$HOMEF")"

# Class permission-resurrection: what setup put in a profile's file (a permission rule, an auto-mode line, the status
# line, an option) is taken out, or for the status line and an option kept at the owner's own value, only with
# /commandeck:revoke (scripts/revoke.sh). That writes the owner's choices (`revoked`), which the panes on a profile
# share. The repair never reads a removal from the file: a hand edit of setup's settings is undone at the next launch,
# an in-session /resume included (Claude Code sends it as source "resume", like Orca's `claude --resume`).
M=$H/.commandeck/install/_machine.json
revoke() { local p=$1; shift; (cd "$PROJ" && env_ CLAUDE_CONFIG_DIR="$p" bash "$REAL/scripts/revoke.sh" "$@"); }
own='del(.statusLine) | .permissions.allow -= ["Bash(orca-ide terminal:*)"] | .autoMode.environment |= .[:-1]
  | .pluginConfigs["commandeck@commandeck"].options.k = "project"'
pick='[.statusLine.command, (.permissions.allow | index("Bash(orca-ide terminal:*)") != null), (.autoMode.environment | length), .pluginConfigs["commandeck@commandeck"].options.k]'
fresh; setup_a; cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
jq "$own" "$PA/settings.json" > "$T/a.new" && mv "$T/a.new" "$PA/settings.json"; hook "$PA" clear
check "a hand edit of setup's settings stays until the next launch: a /clear writes nothing" '[null,false,2,"project"]' "$(jq -c "$pick" "$PA/settings.json")"
hook "$PA" resume
check "and the next launch, an in-session /resume included, undoes it: a hand edit is not a revoke" '["plugin-line",true,3,"new"]' "$(jq -c "$pick" "$PA/settings.json")"
# Two panes on one profile file. Pane 1 and pane 2 launch (Orca copies the home file over the profile's each time);
# the owner revokes a rule in pane 1. Then pane 1 runs /resume in its session (pass 3's case), and pane 2 is closed
# and launched again: Orca's copy, with a /clear in pane 1 between the copy and pane 2's own session start.
fresh; setup_a; cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
# Orca's copy can hold setup's own values (class revoked-option-restoration): this file as setup's repair left it.
cp "$PA/settings.json" "$T/setup-copy"
revoke "$PA" rule 'Bash(orca-ide terminal:*)' >/dev/null
check "revoke takes the rule out of the profile file at once and leaves the rest" '["plugin-line",false,3,"new"]' "$(jq -c "$pick" "$PA/settings.json")"
check "and puts it on the profile file's list of the owner's choices" '["Bash(orca-ide terminal:*)"]' "$(jq -c --arg p "$PA/settings.json" '.entries[$p].revoked.added' "$M")"
hook "$PA" resume
check "pane 1's in-session /resume after the revoke leaves the rule out" '["plugin-line",false,3,"new"]' "$(jq -c "$pick" "$PA/settings.json")"
cp "$HOMEF" "$PA/settings.json"; hook "$PA" clear; hook "$PA" startup
check "pane 2's relaunch on the same profile file (Orca's copy, pane 1's /clear before its start) puts the rest back and the revoked rule stays out" \
  '["plugin-line",false,3,"new"]' "$(jq -c "$pick" "$PA/settings.json")"
cp "$T/setup-copy" "$PA/settings.json"; hook "$PA" startup
check "a relaunch whose copy holds the revoked rule takes it out" '["plugin-line",false,3,"new"]' "$(jq -c "$pick" "$PA/settings.json")"
cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
check "the doctor still names the copy's repair (the rules setup kept)" "permissions" "$(jq -r --arg p "$PA/settings.json" '.entries[$p].repaired.keys[] | select(. == "permissions")' "$M")"
lib "$PA" 'il_allow_set "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json" "$(il_allow "$IL_ROOT")"' >/dev/null 2>&1
check "a setup rerun leaves the revoked rule out of the file too" false "$(jq -c '.permissions.allow | index("Bash(orca-ide terminal:*)") != null' "$PA/settings.json")"
# The retry needs nothing but a launch: the repair stamp taken out between two launches, the next copy is repaired
# with the rule still out; the owner's choices taken out, the rule comes back (the list is the only record).
jq --arg p "$PA/settings.json" 'del(.entries[$p].repaired)' "$M" > "$T/m.new" && mv "$T/m.new" "$M"
cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
check "with the repair stamp gone from the manifest, the next copy is repaired, the revoked rule left out" '["plugin-line",false,3,"new"]' "$(jq -c "$pick" "$PA/settings.json")"
jq --arg p "$PA/settings.json" 'del(.entries[$p].revoked)' "$M" > "$T/m.new" && mv "$T/m.new" "$M"
cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
check "with the owner's choices gone too, the next copy is repaired whole" '["plugin-line",true,3,"new"]' "$(jq -c "$pick" "$PA/settings.json")"
# The other three kinds, each kept across a relaunch: the owner's own k=third kept, the status line and one auto-mode
# line taken out, the ponytail option taken out. A /config change by hand would be undone; one kept with the command is not.
jq '.pluginConfigs["commandeck@commandeck"].options.k = "third"' "$PA/settings.json" > "$T/a.new" && mv "$T/a.new" "$PA/settings.json"
L1=$(jq -r --arg p "$PA/settings.json" '.entries[$p].autoMode.added[0]' "$M")
revoke "$PA" option commandeck@commandeck k --keep >/dev/null && revoke "$PA" status-line >/dev/null && revoke "$PA" auto-mode "$L1" >/dev/null \
  && revoke "$PA" option commandeck@commandeck ponytail >/dev/null
check "keep k, take out the status line (the one before setup's comes back), one auto-mode line and ponytail: the file now" \
  '["owner-home",true,2,"third",null,false]' "$(jq -c --arg l "$L1" "$pick + [.pluginConfigs[\"commandeck@commandeck\"].options.ponytail, (.autoMode.environment | index(\$l) != null)]" "$PA/settings.json")"
cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
check "and a relaunch (Orca's copy) keeps every one of those choices" \
  '["owner-home",true,2,"third",null,false]' "$(jq -c --arg l "$L1" "$pick + [.pluginConfigs[\"commandeck@commandeck\"].options.ponytail, (.autoMode.environment | index(\$l) != null)]" "$PA/settings.json")"
cp "$T/setup-copy" "$PA/settings.json"; hook "$PA" startup
check "and a relaunch whose copy holds setup's status line, auto-mode line, k=new and ponytail keeps them too" \
  '["owner-home",true,2,"third",null,false]' "$(jq -c --arg l "$L1" "$pick + [.pluginConfigs[\"commandeck@commandeck\"].options.ponytail, (.autoMode.environment | index(\$l) != null)]" "$PA/settings.json")"
lib "$PA" 'il_auto_mode "$IL_MACHINE" "$CLAUDE_CONFIG_DIR/settings.json" add' >/dev/null 2>&1
check "a setup rerun leaves the revoked auto-mode line out too" 2 "$(jq '.autoMode.environment | length' "$PA/settings.json")"
# Revoke takes only a value setup put in a file setup recorded, keeps only a value of the owner's, and names them with
# no argument.
AB=$(sha "$PA/settings.json"); revoke "$PA" rule 'Bash(ls:*)' >/dev/null 2>&1; RC=$?
check "a rule setup did not add (the owner's own) is refused and the file not written" "1:$AB" "$RC:$(sha "$PA/settings.json")"
revoke "$PB" rule 'Bash(orca-ide terminal:*)' >/dev/null 2>&1
check "a profile setup never recorded is refused" 1 "$?"
fresh; setup_a; revoke "$PA" option commandeck@commandeck k --keep >/dev/null 2>&1
check "keep with setup's own value in the file is refused: there is nothing of the owner's to keep" 1 "$?"
check "with no argument it lists setup's values for this profile's file, as the command names them" 1:1:1 \
  "$(revoke "$PA" | grep -cxF 'rule Bash(orca-ide terminal:*)'):$(revoke "$PA" | grep -cxF 'status-line'):$(revoke "$PA" | grep -cxF 'option commandeck@commandeck k')"

# The manifest format already deployed: options only in `options` (no optionsWant), the status line in the
# top-level record kept before status lines were kept per file.
fresh; setup_a; M=$H/.commandeck/install/_machine.json
jq --arg p "$PA/settings.json" '.statusLine = .entries[$p].statusLine | del(.entries[$p].statusLine, .entries[$p].optionsWant)' "$M" > "$T/m.new" && mv "$T/m.new" "$M"
cp "$HOMEF" "$PA/settings.json"; hook "$PA" startup
check "a deployed-format manifest (options, top-level statusLine) still repairs the option and the status line" '["lite","plugin-line"]' \
  "$(jq -c '[.pluginConfigs["commandeck@commandeck"].options.ponytail, .statusLine.command]' "$PA/settings.json")"
# The manifest as main's released install-lib.sh writes it (the steps of setup_a, run from `git archive main`), its
# paths made placeholders: `options` holds only the added answer, no optionsWant.
fresh; mkdir -p "$H/.commandeck/install"
sed -e "s|@PROFILE@|$PA|g" -e "s|@HOME@|$H|g" -e "s|@ROOT@|$REAL|g" "$REAL/scripts/__tests__/fixtures/deployed-machine-manifest.json" > "$H/.commandeck/install/_machine.json"
hook "$PA" startup
check "a manifest written by the released setup repairs the option, status line, auto-mode lines and rules after a copy" '["lite","plugin-line",3,true]' \
  "$(jq -c '[.pluginConfigs["commandeck@commandeck"].options.ponytail, .statusLine.command, (.autoMode.environment | length), (.permissions.allow | index("Bash(orca-ide terminal:*)") != null)]' "$PA/settings.json")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
