#!/usr/bin/env bash
# covers: scripts/install-lib.sh
# install-lib.test.sh's setup-step cases (split from it for the shell-test time budget): role keys, main's model,
# the notify wrapper, the marked blocks, the update checks and the rules-audit line, on the same hand-written HOME.
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

# Issue 312: setup's --option answers are role keys, checked before anything is written, as every reader checks them.
# setup_keys <--profile or ""> <--option answers as JSON> -- the answers setup writes.
setup_keys() { ASK=$1 GV=$2 lib 'S=$(cat "$0/setup.sh"); HERE=$0; die() { echo "setup: $*" >&2; exit 1; }
  ASKED=$ASK GIVEN=$GV PROFILE=${ASK:-claude-openai} RL={}
  eval "$(sed -n "/^REC_FILE=/p;/^WAKE_KINDS=/p;/^rec_takes()/,/^}/p;/^opt_check()/,/^}/p" <<<"$S")"
  eval "$(sed -n "/^# --- routing:/,/^# --- preflight:/p" <<<"$S")" && echo "$GIVEN"' 2>&1; }
[ ! -e "$PROJ/.claude" ] || { echo "install-lib: the key cases expect no $PROJ/.claude; a case above left one" >&2; exit 1; }
mkdir "$PROJ/.claude" && echo '{"version": 1, "profile": "claude-openai"}' > "$PROJ/.claude/commandeck.json"
check "--profile claude puts the reviewer and the Sol judge on Claude" '{"codexReviewerAgent":"claude","planJudgeSolAgent":"claude"}' \
  "$(setup_keys claude '{}' | jq -cS '{codexReviewerAgent, planJudgeSolAgent}')"
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

# Main's lean lists (il_main_lean): the add-on plugins main never uses are off in the file it is
# given and nowhere else; a key the owner holds stays theirs; uninstall puts the file back as it was.
ML=$T/main-lean.json; USR=$H/.claude/settings.json; PSET=$PROJ/.claude/settings.json
mkdir -p "$H/.claude" "$PROJ/.claude"; echo '{"theme": "dark"}' > "$USR"; echo '{"permissions": {}}' > "$PSET"
sha() { sha256sum "$1" | cut -c1-16; }
# ml [off] -- setup's (or uninstall's) call, the file recorded in the project's manifest first as setup records it.
ml() { lib 'il_record "$IL_PROJECT" merge "$1" && il_main_lean "$IL_PROJECT" "$1" $2' "$ML" "${1:-}"; }
# mlrestore -- what uninstall does after taking setup's keys out: the recorded file back to what it was.
mlrestore() { ml off >/dev/null; lib 'il_restore "$IL_PROJECT"' >/dev/null; }
fresh() { rm -f "$ML" "$(lib 'echo $IL_PROJECT')"; }
fresh; BEFORE=$(sha "$USR")$(sha "$PSET"); ml >/dev/null
check "main lean: the add-on plugins are off in main's local settings, and no ponytail key is written" '{"enabledPlugins":{"mattpocock-skills@claude-plugins-official":false,"ui-themes@ui-themes":false}}' "$(jq -cS . "$ML")"
check "main lean: the user settings file and the project's settings.json are byte for byte as before" "$BEFORE" "$(sha "$USR")$(sha "$PSET")"
AFTER=$(sha "$ML"); ml >/dev/null
check "main lean: a rerun changes nothing" "$AFTER" "$(sha "$ML")"
fresh
jq -n '{enabledPlugins: {"other@x": true, "ui-themes@ui-themes": true}, keep: 1}' > "$ML"; OWNML=$(jq -cS . "$ML")
OUT=$(ml); ml >/dev/null
check "main lean: an owner's own plugin entries are the same after setup and a rerun" 'true true' \
  "$(jq -r '[.enabledPlugins["other@x"], .enabledPlugins["ui-themes@ui-themes"]] | map(tojson) | join(" ")' "$ML")"
check "main lean: the keys it left alone are named, and the ones it set are not" '1 0' "$(grep -c 'enabledPlugins.ui-themes@ui-themes is already set' <<<"$OUT") $(grep -c 'enabledPlugins.other' <<<"$OUT")"
check "main lean: the keys setup did add still come in beside the owner's" false "$(jq '.enabledPlugins["mattpocock-skills@claude-plugins-official"]' "$ML")"
mlrestore
check "main lean: uninstall puts an owner's file back byte for byte" "$OWNML" "$(jq -cS . "$ML")"
fresh; ml >/dev/null; mlrestore
check "main lean: uninstall removes the file setup made, none being there before" absent "$([ -e "$ML" ] && echo present || echo absent)"
fresh; echo '{"x": 1}' > "$ML"; ml >/dev/null; jq '.enabledPlugins["ui-themes@ui-themes"] = true' "$ML" > "$T/x" && mv "$T/x" "$ML"; ml off >/dev/null
check "main lean: uninstall leaves a value the owner changed since" 'true' "$(jq -c '.enabledPlugins["ui-themes@ui-themes"]' "$ML")"
# What each pane runs on, not what a file holds: in a worktree Claude Code applies main's settings.local.json over the
# worktree's own (il_shadow_report), so a cut written there would reach every worker and the relay. Setup's calls, on
# an install whose earlier setup wrote the cuts into main's settings.local.json.
MLOC=$PROJ/.claude/settings.local.json MFILE=$PROJ/$(lib 'echo $IL_MAIN_LEAN_FILE')
setup_lean() { lib 'il_record "$IL_PROJECT" merge "$1" "$2" && il_main_lean "$IL_PROJECT" "$1" off && il_main_lean "$IL_PROJECT" "$2"' "$MLOC" "$MFILE"; }
# runs <file>... -- the plugins the pane runs on: each file over the ones before it.
runs() { cat "$@" | jq -rs 'reduce .[] as $f ({}; . * $f) | [.enabledPlugins["ui-themes@ui-themes", "mattpocock-skills@claude-plugins-official"]] | map(tojson) | join(" ")'; }
fresh; echo '{"enabledPlugins": {"ui-themes@ui-themes": true, "mattpocock-skills@claude-plugins-official": true}}' > "$USR"
echo '{"x": 1}' > "$MLOC"; lib 'il_record "$IL_PROJECT" merge "$1" && il_main_lean "$IL_PROJECT" "$1"' "$MLOC" >/dev/null; setup_lean >/dev/null
echo '{}' > "$T/worktree-local.json"
check "main lean: a worker pane, main's local file applied last, keeps ui-themes and mattpocock-skills" 'true true' \
  "$(runs "$USR" "$T/worktree-local.json" "$MLOC")"
check "main lean: main started with --settings on its own file runs without them" 'false false' "$(runs "$USR" "$MLOC" "$MFILE")"
check "main lean: the cuts are in main's own file, and the owner's key in main's settings.local.json stays" \
  '{"enabledPlugins":{"mattpocock-skills@claude-plugins-official":false,"ui-themes@ui-themes":false}} {"x":1}' \
  "$(jq -cS . "$MFILE") $(jq -cS . "$MLOC")"
check "main lean: git never sees main's own file" 1 "$(lib 'printf "%s\n" "${IL_STATE[@]}"' | grep -cxF "$(lib 'echo $IL_MAIN_LEAN_FILE')")"
fresh; rm -f "$USR" "$PSET" "$MLOC" "$MFILE"; rmdir "$PROJ/.claude" 2>/dev/null

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

# Main's prompt cache (issue 367, il_main_lean's third argument; setup passes its effective answer, /config first):
# the TTL goes into main's own file and nowhere else, and Leave as is keeps the one setup wrote while the file holds it.
# This section sits after the timed cases above.
ML=$T/main-lean.json PM=$(lib 'echo $IL_PROJECT'); MLOC=$PROJ/.claude/settings.local.json PSET=$PROJ/.claude/settings.json
# ttl [file] -- the TTL in the file (main's own by default); rec -- setup's record of it in the manifest.
ttl() { jq -r '.env.CLAUDE_CODE_PROMPT_CACHE_TTL // "none"' "${1:-$ML}" 2>/dev/null || echo none; }
rec() { jq -r --arg p "$ML" '.entries[$p].mainLean.env.CLAUDE_CODE_PROMPT_CACHE_TTL // "none"' "$PM"; }
mkdir -p "$PROJ/.claude"; echo '{"x": 1}' > "$MLOC"; echo '{"permissions": {}}' > "$PSET"; BEFORE=$(sha "$MLOC")$(sha "$PSET")
fresh; ml 1h >/dev/null
check "setup writes main's TTL only into main-session.settings.json: main's settings.local.json and .claude/settings.json get none" "1h:record 1h:$BEFORE" "$(ttl):record $(rec):$(sha "$MLOC")$(sha "$PSET")"
ml leave >/dev/null
check "a leave answer keeps the 1h setup wrote, and its record" "1h:1h" "$(ttl):$(rec)"
ml >/dev/null
check "an unanswered main writes nothing and keeps the 1h setup wrote, as leave does" "1h:1h" "$(ttl):$(rec)"
ml 5m >/dev/null
check "a rerun answered 5m replaces setup's own 1h, in the file and in the record" "5m:5m" "$(ttl):$(rec)"
ml off >/dev/null
check "uninstall takes out the TTL setup wrote, and its record" "none:none" "$(ttl):$(rec)"
fresh; ml 1h >/dev/null; jq '.env.CLAUDE_CODE_PROMPT_CACHE_TTL = "5m"' "$ML" > "$T/x" && mv "$T/x" "$ML"
OUT=$(ml leave)
check "a leave answer leaves an owner-changed TTL and drops setup's record, with no note" "5m:none:0" "$(ttl):$(rec):$(grep -c 'note:' <<<"$OUT")"
fresh; echo '{"env": {"CLAUDE_CODE_PROMPT_CACHE_TTL": "5m", "OTHER": "x"}}' > "$ML"
OUT=$(ml 1h)
check "a TTL the owner holds in main's file stays, is named, and is never recorded" "5m:none:1" "$(ttl):$(rec):$(grep -c 'env.CLAUDE_CODE_PROMPT_CACHE_TTL is already set' <<<"$OUT")"
# Pass 1: only il_main_lean was covered, not setup's order around it. setup_ttl <answer> replays setup.sh's own lines:
# the effective answer, /config's first (MCACHE_ON=), the answer into /config's options (il_plugin_options), then
# main's file. cfg <value> -- the owner's /config answer.
CF=$T/cfg; mkdir -p "$CF"; echo '{"enabledPlugins": {"commandeck@commandeck": true}}' > "$CF/settings.json"
cfg() { jq --arg v "$1" '.pluginConfigs["commandeck@commandeck"].options.mainPromptCacheTtl = $v' "$CF/settings.json" > "$T/x" && mv "$T/x" "$CF/settings.json"; }
setup_ttl() { CLAUDE_CONFIG_DIR=$CF lib 'MCACHE=$2 RL={} GIVEN={} FULL= WCACHE= RCACHE= DASHBOARD= S=$(cat "$0/setup.sh")
  eval "$(grep "^MCACHE_ON=" <<<"$S")" && eval "$(sed -n "/^il_plugin_options \"/,/\"\$GIVEN\"\$/p" <<<"$S")" \
    && il_record "$IL_PROJECT" merge "$1" && il_main_lean "$IL_PROJECT" "$1" "$MCACHE_ON"' "$ML" "$1" 2>&1; }
P="a /config answer of leave keeps the 1h setup wrote, and its record, a flag does not beat /config, and a /config 5m then replaces it"
fresh; BEFORE=$(sha "$MLOC")$(sha "$PSET"); setup_ttl 1h >/dev/null
check "$P (1: a first setup answered 1h writes main's file, its record and /config's empty option)" "1h:1h:1h" \
  "$(ttl):$(rec):$(jq -r '.pluginConfigs["commandeck@commandeck"].options.mainPromptCacheTtl' "$CF/settings.json")"
cfg leave; setup_ttl 1h >/dev/null
check "$P (2: /config leave keeps both)" "1h:1h" "$(ttl):$(rec)"
OUT=$(setup_ttl 5m)
check "$P (3: a 5m flag under /config leave keeps both, and the note names /config)" "1h:1h:1" \
  "$(ttl):$(rec):$(grep -c 'note: mainPromptCacheTtl is leave in /config, which beats this answer (5m); change it with /config' <<<"$OUT")"
cfg 5m; setup_ttl leave >/dev/null
check "$P (4: /config 5m replaces both)" "5m:5m" "$(ttl):$(rec)"
ml off >/dev/null
check "$P (5: uninstall takes both out, and main's settings.local.json and .claude/settings.json never changed)" "none:none:$BEFORE" "$(ttl):$(rec):$(sha "$MLOC")$(sha "$PSET")"
fresh; rm -f "$MLOC" "$PSET"

# The rules audit is setup's closing warning: a project with one dead reference gets one line, a clean one none.
RA=$T/ra; mkdir -p "$RA/docs"; git init -q -b main "$RA"
check "setup's rules-audit line: a clean project prints nothing" "" "$(lib "il_rules_audit_line $RA")"
echo 'see `docs/gone.md`' > "$RA/docs/a.md"
# The line names the plugin by its physical path (IL_ROOT): the merge check's copy sits under a symlinked TMPDIR.
check "setup's rules-audit line: a project with one dead-ref prints the count and the command" "rules audit: 1 findings (a warning; see bash $(cd "$REAL" && pwd -P)/scripts/rules-audit.sh)" "$(lib "il_rules_audit_line $RA")"
# Setup runs under set -e: the audit's exit 1 on a finding is a warning, so the closing report goes on past it; an audit
# that fails to run (exit 2 and up) says so in one line and goes on too.
check "setup's rules-audit line: under setup's set -e a finding warns and setup goes on" "rules audit: 1 findings:next" \
  "$(lib "set -e; il_rules_audit_line $RA | cut -d' ' -f1-4; echo next" | paste -sd: -)"
check "setup's rules-audit line: under setup's set -e an audit that does not run says so and setup goes on" "rules audit: did not run (exit 2:next" \
  "$(lib "set -e; python3() { return 2; }; il_rules_audit_line $RA | cut -d';' -f1; echo next" | paste -sd: -)"

# A compaction keeps the brief, the evidence path, the last round and its open findings.
check "the global CLAUDE.md template carries Compact Instructions" "1:1" \
  "$(grep -c '^## Compact Instructions$' "$REAL/templates/global-claude.md"):$(grep -c 'evidence file path, the current cut and its test' "$REAL/templates/global-claude.md")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] && { [ -z "${INSTALL_LIB_TEST_CASE-}" ] || [ "$PASS" -gt 0 ]; }
