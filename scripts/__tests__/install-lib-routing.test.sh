#!/usr/bin/env bash
# covers: scripts/install-lib.sh
# install-lib.test.sh's routing-file cases (split from it for the shell-test time budget): a routing file of the
# owner's own gains the plan seats it lacks, and an uninstall takes back only the seats no other project still needs.
# INSTALL_LIB_TEST_CASE=<text> runs only the cases whose name holds <text>.
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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] && { [ -z "${INSTALL_LIB_TEST_CASE-}" ] || [ "$PASS" -gt 0 ]; }
