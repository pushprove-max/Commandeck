#!/usr/bin/env bash
# auto-setup.test.sh -- Auto Setup (issue 536): the profile's args, the detected values, and the rules rewrite and its
# restore, on a hand-written HOME and project, by the functions setup.sh and uninstall.sh call in their order and by
# setup.sh's own lines read as fragments (no whole run of either script). What this pins: Auto sends the reference
# profile with model families only; a rewritten rule file is backed up first and uninstall puts every original back
# byte for byte; an edit the owner made in between is kept beside the file; a file Auto did not write keeps the
# owner's edits; Custom never edits rule text. AUTO_SETUP_TEST_CASE=<text> runs only the cases whose name holds <text>.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
SETUP=$REAL/scripts/setup.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { case $1 in *"${AUTO_SETUP_TEST_CASE-}"*) ;; *) return 0 ;; esac; if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
# The owner's Claude and Codex settings are never read or written: every config-path override goes (proof-run.sh's
# list), ANTHROPIC_MODEL too, and each case runs on its own HOME.
unset CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_ROOT COMMANDECK_MAIN COMMANDECK_WORKSPACES COMMANDECK_SCRATCH CODEX_HOME COMMANDECK_DASHBOARD_DIR \
  COMMANDECK_HOOK_FIRE_LOG COMMANDECK_ROUTING COMMANDECK_CLEAR_LINE COMMANDECK_HOOK_TIER COMMANDECK_BUILDER COMMANDECK_REVIEWER AGENT_KIND ANTHROPIC_MODEL
# A day of the case's choosing: FAKEDAY=<yyyymmdd> is what the backups and edited copies are named by.
BIN=$T/bin; mkdir -p "$BIN"
printf '#!/bin/sh\nif [ -n "${FAKEDAY:-}" ] && [ "$1" = +%%Y%%m%%d ]; then echo "$FAKEDAY"; else exec %s "$@"; fi\n' "$(command -v date)" > "$BIN/date"; chmod +x "$BIN/date"
TODAY=$(date +%Y%m%d)
PIN='claude-(opus|sonnet|haiku|fable)-[0-9]|gpt-[0-9]'

# fresh -- a new HOME and project for the case (H, PROJ).
N=0
fresh() { N=$((N + 1)); H=$T/h$N PROJ=$T/p$N; mkdir -p "$H/.claude" "$PROJ/.claude/rules" && git init -q -b main "$PROJ"; }
# lib <shell> [args] -- run it with paths.sh and install-lib.sh loaded, in the project, on the case's HOME, as setup.sh does.
lib() { (cd "$PROJ" && env -u ORCA_WORKTREE_ID -u ORCA_TERMINAL_HANDLE COMMANDECK_MAIN="$PROJ" HOME="$H" PATH="$BIN:$PATH" \
  bash -c 'set -o pipefail; . "$0/paths.sh" && . "$0/install-lib.sh" && c=$1 && shift && eval "$c"' "$REAL/scripts" "$@"); }
# as_run <auto-setup.sh args> -- auto-setup.sh in the project, on the case's HOME.
as_run() { (cd "$PROJ" && env -u ORCA_WORKTREE_ID -u ORCA_TERMINAL_HANDLE COMMANDECK_MAIN="$PROJ" HOME="$H" PATH="$BIN:$PATH" bash "$REAL/scripts/auto-setup.sh" "$@"); }
# owner -- the owner's rule files: the project's CLAUDE.md, a path-scoped rules file, AGENT_STARTUP.md with front
# matter, main-session.md with its Details, and the global CLAUDE.md.
owner() {
  printf '# Project\n- Use tabs.\n- Run make check.\n' > "$PROJ/CLAUDE.md"
  printf -- '---\npaths: src/**\n---\n- Keep functions short.\n' > "$PROJ/.claude/rules/style.md"
  printf -- '---\nname: startup\n---\n# Startup\n- Read the plan first.\n' > "$PROJ/AGENT_STARTUP.md"
  printf 'You are main.\n- Ask before merging.\n\n## Details (not injected)\nNotes.\n' > "$PROJ/.claude/main-session.md"
  printf '# Mine\n- Be brief.\n' > "$H/.claude/CLAUDE.md"
}
RULEFILES='CLAUDE.md .claude/rules/style.md AGENT_STARTUP.md .claude/main-session.md'
# sums -- each rule file's hash (global and AGENTS.md last), "none" for one that is not there.
sums() { local f; for f in $RULEFILES; do echo "$PROJ/$f"; done | { cat; echo "$H/.claude/CLAUDE.md"; echo "$PROJ/AGENTS.md"; } \
  | while IFS= read -r f; do if [ -e "$f" ]; then sha256sum < "$f" | cut -c1-16; else echo none; fi; done | paste -sd' ' -; }
# snap -- every file under the case's HOME and project with its hash: a refusal must leave this as it was.
snap() { (cd "$T" && find "h$N" "p$N" -path '*/.git' -prune -o -print | sort | while IFS= read -r f; do [ -f "$f" ] && sha256sum < "$f" | cut -c1-16; echo "$f"; done); }
# sources -- auto-setup.sh --sources (it empties the staging folder); sets S to the folder.
sources() { S=$(as_run --sources | awk -F'\t' '$1 == "staging" { print $2 }'); }
# stage <key> <text> -- the merged text the skill writes for one rule file.
stage() { mkdir -p "$(dirname "$S/$1")" && printf '%s' "$2" > "$S/$1"; }
# stage_listed -- as the skill does: every file --sources lists as `file` staged (its text plus a line), none `linked`.
stage_listed() { local s k p; while IFS=$'\t' read -r s k p; do [ "$s" != file ] || stage "$k" "$(cat "$p")"$'\n- tightened.\n'; done < <(as_run --sources); }
FM=$'---\nname: startup\n---\n'

# The functions setup.sh calls for Auto, in its order ($1 staging folder, $2 --global-rewrite, $3 the global answer,
# $4 the profile): the staged rules checked, the manifest step, the Codex block, the rewrite, the global blocks and the
# own-file merges (setup.sh: il_rules_check, the manifest, il_block, il_rules_rewrite, il_global, il_own).
AUTO='S=$1 G=$2 GA=$3 P=$4
il_rules_check "$S" "$G" || exit 1
[ "$P" != claude-openai ] || il_record "$IL_PROJECT" merge "$IL_AGENTS" || exit 1
il_rules_record "$S" "$G" || exit 1
case $GA in install|block|merge) il_record "$IL_MACHINE" merge "$IL_GLOBAL" ;; esac
[ "$P" != claude-openai ] || il_block "$IL_AGENTS" "$IL_ROOT/templates/codex-instructions.md" || exit 1
il_rules_rewrite "$S" "$G" || exit 1
il_global "$GA" claude-md "$IL_ROOT/templates/global-claude.md" --global-claude || exit 1
il_global "$GA" rules "$IL_ROOT/templates/global-rules.md" --global-rules || exit 1
for f in AGENT_STARTUP.md .claude/main-session.md; do il_own "$IL_PROJECT" "$PP_MAIN/$f" "$IL_ROOT/templates/${f#.claude/}" merge || exit 1; done'
# Custom's rule steps: the own files merged (il_own records each), the owner's --drop answers passed on.
CUSTOM='for f in AGENT_STARTUP.md .claude/main-session.md; do il_own "$IL_PROJECT" "$PP_MAIN/$f" "$IL_ROOT/templates/${f#.claude/}" merge "$@" || exit 1; done'
# uninstall.sh:39-79's steps for the rule files, in its order.
UNINSTALL='if [ -s "$IL_PROJECT" ]; then
  ! il_has "$IL_PROJECT" "$IL_AGENTS" || il_block "$IL_AGENTS"
  for S in "$PP_MAIN/AGENT_STARTUP.md" "$PP_MAIN/.claude/main-session.md"; do
    ! il_has "$IL_PROJECT" "$S" || [ ! -e "$S" ] || IL_BEGIN="<!-- commandeck:merge:begin -->" IL_END="<!-- commandeck:merge:end -->" il_block "$S"
  done
  il_restore "$IL_PROJECT"
fi
if [ -s "$IL_MACHINE" ]; then
  ! il_has "$IL_MACHINE" "$IL_GLOBAL" || [ ! -e "$IL_GLOBAL" ] || il_global_out
  il_profiles_out "$IL_MACHINE"
  il_restore "$IL_MACHINE"
fi'
# cut_setup <end ERE> <max lines> -- setup.sh from `TAKES=` to the first line matching <end>, printed only when the cut
# ends on that line within <max> lines; otherwise nothing, so the case fails without running it. An end line that is
# reworded or gone would make sed print to the end of setup.sh, and the eval would run all of setup.
cut_setup() { local f; f=$(sed -n "/^TAKES=/,/$1/p" "$SETUP"); [ "$(grep -c '' <<<"$f")" -le "$2" ] && tail -n 1 <<<"$f" | grep -qE -- "$1" && printf '%s\n' "$f"; }
# frag_run <fragment> [setup.sh args] -- eval a setup.sh fragment with those args as "$@", on the test's own HOME; an
# empty fragment (a failed cut) runs nothing.
frag_run() { local _frag=$1; shift; [ -n "$_frag" ] || return 0; HOME=$T/frag-home; export HOME; eval "$_frag"; }
bak() { find "$PROJ" "$H/.claude" -name '*.commandeck-bak-*' | wc -l | tr -d ' '; }
edited() { find "$PROJ" "$H/.claude" -name '*.commandeck-edited-*' | wc -l | tr -d ' '; }

# --- the setup skill's first question and Auto's one question ---
SK=$REAL/skills/setup/SKILL.md
Q1=$(grep -n '^   Ask "Setup": Auto Setup (recommended) | Custom$' "$SK" | cut -d: -f1) QS=$(grep -n '^## 1. The questions' "$SK" | cut -d: -f1)
COND=$(grep -A1 'Only when `--questions begin` printed both "Codex reviewer: ready" and "Codex model: found":' "$SK" | tail -1)
ELSE=$(grep -A3 'Only when `--questions begin` printed both' "$SK" | tail -1)
check "the setup skill asks Auto Setup or Custom first and offers Claude + Codex only when the Codex reviewer and model are ready" \
  'first|codex-gated|claude-only-else' \
  "$([ -n "$Q1" ] && [ "$Q1" -lt "$QS" ] && echo first)|$([ "$COND" = '   Ask "Auto profile": Claude + Codex (recommended) | Claude Only' ] && echo codex-gated)|$([ "$ELSE" = '   Ask "Auto profile": Claude Only (recommended) | Stop' ] && echo claude-only-else)"

# --- the profile's args ---
fresh
A=$(as_run --args claude-openai) C=$(as_run --args claude)
# opts <args> -- the --option pairs as one JSON object; dupes counts a key sent twice.
opts() { awk 'p { print; p = 0 } $0 == "--option" { p = 1 }' <<<"$1" | jq -Rn '[inputs | {(split("=")[0]): (sub("^[^=]*="; ""))}] | add'; }
dupes() { awk 'p { sub(/=.*/, ""); print; p = 0 } $0 == "--option" { p = 1 }' <<<"$1" | sort | uniq -d | wc -l | tr -d ' '; }
after() { awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }' <<<"$1"; }
REC=$(jq -c '.options | map_values(tostring)' "$REAL/config/recommended.json")
# The reference values: maxBuilders 3 and builder-fix effort medium over recommended.json's; every other key as it is.
WANT=$(jq -c '. + {maxBuilders: "3", fixerEffort: "medium", codexReviewerModel: "sol", planJudgeSolModel: "sol"}' <<<"$REC")
check "the Claude + Codex args carry every recommended key at the reference values, sol on both Codex seats, --strict and no --addons" \
  '0|[]|1|0|add|Chief of Staff|127.0.0.1' \
  "$(dupes "$A")|$(jq -c --argjson w "$WANT" --argjson g "$(opts "$A")" -n '[$w | to_entries[] | select($g[.key] != .value) | .key]')|$(grep -cx -- --strict <<<"$A")|$(grep -cx -- --addons <<<"$A")|$(after "$A" --auto-mode)|$(after "$A" --name)|$(after "$A" --bind)"
O=$(opts "$C")
check "the Claude Only args run the reviewer and the Sol judge on Claude with opus at the same efforts" \
  'claude opus claude opus|0|same' \
  "$(jq -r '"\(.codexReviewerAgent) \(.codexReviewerModel) \(.planJudgeSolAgent) \(.planJudgeSolModel)"' <<<"$O")|$(grep -c '^[A-Za-z]*Agent=codex$' <<<"$C")|$(jq -r --argjson a "$(opts "$A")" 'if .codexReviewerEffort == $a.codexReviewerEffort and .planJudgeSolEffort == $a.planJudgeSolEffort and .codexReviewerEffort == "medium" and .planJudgeSolEffort == "high" then "same" else "differ" end' <<<"$O")"
check "no Auto profile, recommended set, setup text or Auto run's args names a pinned model version" 0 \
  "$( { cat "$REAL/config/auto-profile.json" "$REAL/config/recommended.json" "$REAL/config/routing.json" "$SK" "$REAL/docs/setup-questions.md"; echo "$A"; echo "$C"; } | grep -cE "$PIN")"
# What il_plugin_options (/config's options) and il_main_model (main's settings) write from each profile's --option pairs.
W=
for P in A C; do
  fresh; printf '{"enabledPlugins":{"commandeck@commandeck":true}}\n' > "$H/.claude/settings.json"
  G=$(opts "${!P}")
  # setup.sh records main's settings file at its manifest step, before il_main_model writes it.
  lib 'il_plugin_options "$HOME/.claude/settings.json" "{}" "$1" >/dev/null && il_record "$IL_PROJECT" merge "$PP_MAIN/.claude/settings.local.json" \
    && COMMANDECK_OPTIONS=$1 il_main_model "$IL_PROJECT" "$PP_MAIN/.claude/settings.local.json"' "$G" || W+=" fail"
  W+=" $(cat "$H/.claude/settings.json" "$PROJ/.claude/settings.local.json" 2>/dev/null | grep -cE "$PIN")$(jq -r '.pluginConfigs["commandeck@commandeck"].options.codexReviewerModel' "$H/.claude/settings.json")"
done
check "the settings setup writes from either Auto profile's args name no pinned model id" ' 0sol 0opus' "$W"

# --- setup.sh's first loop and its rewrite wiring, read as fragments ---
PRE=$(cut_setup '^done$' 40)
check "--auto names the profile in setup.sh's first loop" 'cut|claude claude|claude-openai' \
  "${PRE:+cut}|$(frag_run "$PRE" --auto claude; echo "$ASKED $AUTOP")|$(frag_run "$PRE" --name --auto --auto claude-openai; echo "$ASKED")"
L=$(grep -nE '^\[ -z "\$RW" \] \|\| il_rules_check "\$RREW" "\$GREW"' "$SETUP" | cut -d: -f1)
M=$(grep -n '^# --- the manifest' "$SETUP" | cut -d: -f1)
RC=$(grep -nE '^\[ -z "\$RREW" \] \|\| il_rules_record' "$SETUP" | cut -d: -f1)
G=$(grep -nE '^if \[ -n "\$RREW" \]; then$' "$SETUP" | cut -d: -f1)
R=$(grep -n 'il_rules_rewrite "\$RREW"' "$SETUP" | cut -d: -f1 | paste -sd' ' -)
FG=$(grep -n '^il_global ' "$SETUP" | head -1 | cut -d: -f1) FO=$(grep -n '^  il_own ' "$SETUP" | head -1 | cut -d: -f1)
check "setup.sh checks staged rules before any write and rewrites before the blocks, only on --rules-rewrite" \
  "check<manifest|record guarded|$((G + 1)) $((G + 2))|rewrite<global<own|4" \
  "$([ -n "$L" ] && [ -n "$M" ] && [ "$L" -lt "$M" ] && echo 'check<manifest')|$([ -n "$RC" ] && [ "$RC" -gt "$M" ] && echo 'record guarded')|$R|$([ -n "$G" ] && [ "$((G + 2))" -lt "$FG" ] && [ "$FG" -lt "$FO" ] && echo 'rewrite<global<own')|$(grep -cE 'il_rules_(check|record|rewrite) ' "$SETUP")"

# --- detected values ---
fresh
printf '{"scripts":{"test":"jest","typecheck":"tsc -p ."}}\n' > "$PROJ/package.json"; mkdir -p "$PROJ/web/src"
printf '{"model":"opus[1m]"}\n' > "$PROJ/.claude/settings.local.json"
D1=$(as_run --args claude)
fresh; printf 'test:\n\techo ok\n' > "$PROJ/Makefile"; printf '{}\n' > "$PROJ/tsconfig.json"
D2=$(as_run --args claude)
check "detected values become the merge check, typecheck, screen folders, lockfile rule and context window" \
  'npm test|on|npm run typecheck|web/src/|on|1|make test|npx tsc --noEmit||1' \
  "$(after "$D1" --test-command)|$(after "$D1" --full-suite)|$(after "$D1" --typecheck-command)|$(after "$D1" --screen-paths)|$(after "$D1" --lockfile-deny)|$(grep -cx -- --no-standard-context <<<"$D1")|$(after "$D2" --test-command)|$(after "$D2" --typecheck-command)|$(after "$D2" --screen-paths)|$(grep -cx -- --standard-context <<<"$D2")"
ODD=
for pj in '' '{not json' '{"scripts":{"test":"  "}}' '{"scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}' '{"scripts":{"test":"jest \"a b\" '"'"'c'"'"'"}}'; do
  fresh; [ -z "$pj" ] || printf '%s\n' "$pj" > "$PROJ/package.json"
  D=$(as_run --args claude); ODD+="$(after "$D" --test-command)/$(after "$D" --full-suite) "
done
check "odd project files give no merge check and full suite off" '/off /off /off /off npm test/on |1' \
  "$ODD|$(as_run --report detected | grep -cx 'auto: context window: 200K, no model setting found')"

# --- the Auto report ---
fresh; printf '{"scripts":{"test":"jest"}}\n' > "$PROJ/package.json"
lib 'mkdir -p "$IL_DIR" && echo "{\"version\":1,\"entries\":{},\"dashboard\":true}" > "$IL_PROJECT" && echo "{\"version\":1,\"entries\":{},\"dashboard\":{\"bind\":\"127.0.0.1\",\"port\":8765}}" > "$IL_MACHINE"'
RP=$(as_run --report)
check "the Auto report prints each detected value with its source, the dashboard's local address and the one command that opens it to the network once a password is set" \
  '1|1|1|1' \
  "$(grep -cx 'auto: merge check: npm test (package.json test script)' <<<"$RP")|$(grep -cx 'auto: context window: 200K, no model setting found' <<<"$RP")|$(grep -cx 'auto: dashboard: http://127.0.0.1:8765/ (this machine only)' <<<"$RP")|$(grep -c 'set-password <user>), then run: bash .*/setup.sh --dashboard --bind 0.0.0.0 --hosts <name>$' <<<"$RP")"

# --- the rules rewrite ---
fresh; owner; B=$(sums)
sources
stage CLAUDE.md $'# Project\n- Use tabs.\n'
stage .claude/rules/style.md $'---\npaths: src/**\n---\n- Short functions.\n'
stage AGENT_STARTUP.md "$FM"$'# Startup\n- Read the plan.\n'
stage .claude/main-session.md $'You are main.\n- Ask first.\n\n## Details (not injected)\nNotes.\n'
stage global/CLAUDE.md $'# Mine\n- Brief.\n'
printf 'CLAUDE.md\t- Run make check.\tRun the merge check the config names\n' > "$S/conflicts.tsv"
OUT=$(lib "$AUTO" "$S" yes merge claude 2>&1); RCODE=$?
OK=
for k in $RULEFILES global/CLAUDE.md; do
  p=$PROJ/$k; [ "$k" != global/CLAUDE.md ] || p=$H/.claude/CLAUDE.md
  # the file holds the staged text (the plugin's blocks aside) and its backup is the original, named in the report
  [ -e "$p.commandeck-bak-$TODAY" ] && lib 'il_rules_same "$1" "$2"' "$p" "$S/$k" && grep -qxF "rules: rewrote $k (the original: $p.commandeck-bak-$TODAY)" <<<"$OUT" && OK+=y || OK+=n
done
MFS=$(lib 'echo "$IL_PROJECT"; echo "$IL_MACHINE"')
J=$(while IFS= read -r m; do jq -e '[.entries[] | select(.kind == "rewrite")] | length > 0 and all(has("written"))' "$m" >/dev/null && echo y || echo n; done <<<"$MFS" | paste -sd' ' -)
check "a rules rewrite backs up each original, writes the staged text and reports each file, conflict and backup path" \
  "0|yyyyy|1|y y|$B" \
  "$RCODE|$OK|$(grep -cxF 'rules: conflict settled in CLAUDE.md: yours "- Run make check."; the plugin'"'"'s rule wins: "Run the merge check the config names" (yours stays in the backup)' <<<"$OUT")|$J|$(for k in $RULEFILES; do echo "$PROJ/$k.commandeck-bak-$TODAY"; done | { cat; echo "$H/.claude/CLAUDE.md.commandeck-bak-$TODAY"; echo "$PROJ/AGENTS.md"; } | while IFS= read -r f; do if [ -e "$f" ]; then sha256sum < "$f" | cut -c1-16; else echo none; fi; done | paste -sd' ' -)"
UOUT=$(lib "$UNINSTALL" 2>&1)
check "uninstall after an Auto rewrite puts every original back byte for byte, the global CLAUDE.md included, and removes the backups" \
  "$B|0|0" "$(sums)|$(bak)|$(grep -c 'changed since setup' <<<"$UOUT")"

fresh; owner; B=$(sums)
sources; stage CLAUDE.md $'# Project\n- Tabs.\n'; : > "$S/.claude/rules/style.md" 2>/dev/null || { mkdir -p "$S/.claude/rules"; : > "$S/.claude/rules/style.md"; }
OUT=$(lib "$AUTO" "$S" no skip claude 2>&1)
check "a listed file left unstaged or staged empty is left as it is and reported" \
  "1|1|$(cut -d' ' -f2 <<<"$B")|no backup|no entry" \
  "$(grep -cx 'rules: .claude/rules/style.md left as it is (staged empty)' <<<"$OUT")|$(grep -cx 'rules: AGENT_STARTUP.md left as it is (nothing staged for it)' <<<"$OUT")|$(cut -d' ' -f2 <<<"$(sums)")|$([ -e "$PROJ/.claude/rules/style.md.commandeck-bak-$TODAY" ] && echo backup || echo no backup)|$(lib 'il_has "$IL_PROJECT" "$PP_MAIN/.claude/rules/style.md" && echo entry || echo no entry')"
printf -- '- my own line\n' >> "$PROJ/.claude/rules/style.md"; E=$(sha256sum < "$PROJ/.claude/rules/style.md" | cut -c1-16)
lib "$UNINSTALL" >/dev/null 2>&1
check "an unstaged project file edited after Auto keeps the edit through uninstall" "$E|$(cut -d' ' -f1 <<<"$B")" \
  "$(sha256sum < "$PROJ/.claude/rules/style.md" | cut -c1-16)|$(cut -d' ' -f1 <<<"$(sums)")"

# Each way a staged folder is refused, on one owner's files: exit 1, and no file or manifest changed.
fresh; owner; ln -s CLAUDE.md "$PROJ/AGENTS.md"; sources
REF=
for bad in absent unlisted linked marker front conflicts; do
  sources
  case $bad in
    absent) D=$T/none ;;
    unlisted) stage junk.md 'x'; D=$S ;;
    linked) stage CLAUDE.md 'x'; D=$S ;;
    marker) stage AGENT_STARTUP.md "$FM"$'<!-- commandeck:begin -->\nx\n'; D=$S ;;
    front) stage AGENT_STARTUP.md $'# Startup\n'; D=$S ;;
    conflicts) stage AGENT_STARTUP.md "$FM"$'x\n'; printf 'AGENT_STARTUP.md\tonly two\n' > "$S/conflicts.tsv"; D=$S ;;
  esac
  B=$(snap); lib "$AUTO" "$D" no skip claude >/dev/null 2>&1; REF+="$bad:$?:$([ "$B" = "$(snap)" ] && echo same || echo changed) "
done
check "a staged rules folder that is absent, names an unlisted or linked file, holds a plugin marker or drops a file's front matter is refused and nothing changes" \
  'absent:1:same unlisted:1:same linked:1:same marker:1:same front:1:same conflicts:1:same ' "$REF"

fresh; owner; Q='.claude/rules/my "team" rules.md'; printf -- "- the team's rule\n" > "$PROJ/$Q"; B=$(snap)
sources; stage "$Q" $'- the team rule\n'
lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
check "a staged file whose name holds spaces and quotes is written to that one file" \
  "$(printf -- '- the team rule\n' | sha256sum | cut -c1-16)|$(printf -- "- the team's rule\n" | sha256sum | cut -c1-16)|3" \
  "$(sha256sum < "$PROJ/$Q" | cut -c1-16)|$(sha256sum < "$PROJ/$Q.commandeck-bak-$TODAY" | cut -c1-16)|$(ls "$PROJ/.claude/rules" | wc -l | tr -d ' ')"

# The flag refusals run in setup.sh's first-loop fragment, before the requirements check: exit 2, nothing read.
FRAG=$(cut_setup '--global-rewrite takes yes or no' 40)
FR=
for a in '--rules-rewrite x' '--auto claude --global-rewrite maybe' '--auto claude --global-rewrite yes_' '--auto claude --global-rewrite -'; do
  # shellcheck disable=SC2086 # the words of each case; _ is a trailing space, - an empty value
  set -- $a; set -- "${@//yes_/yes }"; [ "${!#}" != - ] || set -- "${@:1:$(($# - 1))}" ''
  FR+="$( (frag_run "$FRAG" "$@"; echo reached) 2>/dev/null; echo "rc=$?") "
done
fresh; owner; sources; stage global/CLAUDE.md $'# Mine\n'; B=$(snap)
check "--rules-rewrite without --auto, or a staged global file with no yes or no answer, is refused and nothing changes" \
  'cut|rc=2 rc=2 rc=2 rc=2 |1|same' \
  "${FRAG:+cut}|$FR|$(lib 'il_rules_check "$1" ""' "$S" >/dev/null 2>&1; echo $?)|$([ "$B" = "$(snap)" ] && echo same || echo changed)"

fresh; owner; G0=$(sha256sum < "$H/.claude/CLAUDE.md" | cut -c1-16)
# A global file that needs no change is not staged (SKILL.md step 2): its preview still runs and says so.
sources; PU=$(as_run --global-preview "$S" 2>&1; echo "rc=$?")
sources; stage global/CLAUDE.md $'# Mine\n- Brief, always.\n'; printf 'global/CLAUDE.md\t- Be brief.\tSay only what is needed\n' > "$S/conflicts.tsv"
PV=$(as_run --global-preview "$S")
lib "$AUTO" "$S" no skip claude >/dev/null 2>&1; GN=$(sha256sum < "$H/.claude/CLAUDE.md" | cut -c1-16)
lib "$AUTO" "$S" yes merge claude >/dev/null 2>&1
check "the global CLAUDE.md is previewed with each conflict flagged and written only on a yes" \
  "1|rc=0|1|1|1|$G0|staged" \
  "$(grep -cxF "$H/.claude/CLAUDE.md needs no change: Optimize it adds only the plugin's rules it lacks, in marked blocks" <<<"$PU")|${PU##*$'\n'}|$(grep -cx -- '+- Brief, always.' <<<"$PV")|$(grep -cx -- '-- Be brief.' <<<"$PV")|$(grep -cxF "CONFLICT: yours: - Be brief. | the plugin's rule, which wins: Say only what is needed" <<<"$PV")|$GN|$(lib 'il_rules_same "$1" "$2"' "$H/.claude/CLAUDE.md" "$S/global/CLAUDE.md" && echo staged)"

fresh; owner
sources; stage global/CLAUDE.md $'# Mine\n- Brief.\n'
lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
# Declined, so Auto recorded nothing for it: no prior uninstall could write back over a later edit.
GE=$(lib 'il_has "$IL_MACHINE" "$IL_GLOBAL" && echo entry || echo no entry')
printf -- '- my later line\n' >> "$H/.claude/CLAUDE.md"; E=$(sha256sum < "$H/.claude/CLAUDE.md" | cut -c1-16)
lib "$UNINSTALL" >/dev/null 2>&1
check "decline the global file, edit it, uninstall: the edit survives byte for byte" "no entry|$E" \
  "$GE|$(sha256sum < "$H/.claude/CLAUDE.md" | cut -c1-16)"

# --- same-day reruns ---
fresh; owner
sources; stage CLAUDE.md $'# Project\n- Tabs.\n'; lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
sources; stage CLAUDE.md $'# Project\n- Tabs.\n'; lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
check "a same-day Auto rerun with no edit makes no edited copy" 0 "$(edited)"
printf -- '- my edit\n' >> "$PROJ/CLAUDE.md"; cp "$PROJ/CLAUDE.md" "$T/edit"
sources; stage CLAUDE.md $'# Project\n- Tabs, always.\n'; OUT=$(lib "$AUTO" "$S" no skip claude 2>&1)
check "a second Auto run the same day after a hand edit keeps the edit byte for byte in an edited copy first" 'same|1|staged' \
  "$(cmp -s "$T/edit" "$PROJ/CLAUDE.md.commandeck-edited-$TODAY" && echo same)|$(grep -cxF "rules: kept your edit of CLAUDE.md since today's backup, byte for byte: $PROJ/CLAUDE.md.commandeck-edited-$TODAY" <<<"$OUT")|$(lib 'il_rules_same "$1" "$2"' "$PROJ/CLAUDE.md" "$S/CLAUDE.md" && echo staged)"

# --- linked rule files ---
fresh; owner; printf '# Agents\n- Codex rule.\n' > "$PROJ/AGENTS.md"; rm "$PROJ/CLAUDE.md"; ln -s AGENTS.md "$PROJ/CLAUDE.md"; B=$(sums)
sources; L1=$(grep -c '^linked	CLAUDE.md	' <<<"$(as_run --sources)")
sources; stage_listed; OUT=$(lib "$AUTO" "$S" no skip claude-openai 2>&1); lib "$UNINSTALL" >/dev/null 2>&1
check "a CLAUDE.md that links to AGENTS.md is left as it is and uninstall restores both byte for byte" "1|1|$B|link" \
  "$L1|$(grep -c '^rules: CLAUDE.md links to .*, left as it is$' <<<"$OUT")|$(sums)|$([ -L "$PROJ/CLAUDE.md" ] && echo link)"
fresh; owner; ln -s CLAUDE.md "$PROJ/AGENTS.md"; B=$(sums)
sources; stage_listed; lib "$AUTO" "$S" no skip claude-openai >/dev/null 2>&1; CB=$(grep -c '^<!-- commandeck:begin -->$' "$PROJ/CLAUDE.md")
lib "$UNINSTALL" >/dev/null 2>&1
CL="$CB|$(sums)|$([ -L "$PROJ/AGENTS.md" ] && echo link)"
# The same with AGENTS.md linked to the global CLAUDE.md (pass 5): Claude + Codex, Optimize it. The global file is
# listed as linked, so nothing stages it and the Codex block setup writes through the link stays.
fresh; owner; ln -s "$H/.claude/CLAUDE.md" "$PROJ/AGENTS.md"; BG=$(sums)
sources; stage_listed; lib "$AUTO" "$S" yes merge claude-openai >/dev/null 2>&1; GB=$(grep -c '^<!-- commandeck:begin -->$' "$H/.claude/CLAUDE.md")
lib "$UNINSTALL" >/dev/null 2>&1
check "an AGENTS.md linked to CLAUDE.md keeps the Codex block and uninstall restores both byte for byte" "1|$B|link 1|$BG|link" \
  "$CL $GB|$(sums)|$([ -L "$PROJ/AGENTS.md" ] && echo link)"

# --- uninstall after an edit, and over Custom ---
fresh; owner; B=$(sums)
sources; stage CLAUDE.md $'# Project\n- Tabs.\n'; lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
printf -- '- edited after setup\n' >> "$PROJ/CLAUDE.md"; cp "$PROJ/CLAUDE.md" "$T/edit"
UOUT=$(lib "$UNINSTALL" 2>&1)
check "uninstall after the owner edited a rewritten file puts the original back and keeps the edit beside it" "$B|same|1" \
  "$(sums)|$(cmp -s "$T/edit" "$PROJ/CLAUDE.md.commandeck-edited-$TODAY" && echo same)|$(grep -cxF "kept your edit of $PROJ/CLAUDE.md, made after setup rewrote it, beside it: $PROJ/CLAUDE.md.commandeck-edited-$TODAY" <<<"$UOUT")"

fresh; owner; B=$(sums)
FAKEDAY=20261030 lib "$CUSTOM" >/dev/null 2>&1
sources; stage AGENT_STARTUP.md "$FM"$'# Startup\n- The plan first.\n'; FAKEDAY=20261101 lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
UOUT=$(lib "$UNINSTALL" 2>&1)
check "Custom on one day and Auto on a later day, then uninstall, puts the original back and the kept backup's line names its day" \
  "$(cut -d' ' -f3 <<<"$B")|1|gone" \
  "$(cut -d' ' -f3 <<<"$(sums)")|$(grep -cxF "kept setup's copy of $PROJ/AGENT_STARTUP.md as it was on 2026-11-01, before setup changed it that day: $PROJ/AGENT_STARTUP.md.commandeck-bak-20261101" <<<"$UOUT")|$([ -e "$PROJ/AGENT_STARTUP.md.commandeck-bak-20261030" ] || echo gone)"

# Keep-mine answers: both profiles send --rules-drop '', and setup.sh's handler makes that {} (none kept).
HD=$(sed -n '/^    --rules-drop|--rules-keep)/,/shift 2 ;;$/p' "$SETUP")
KM=$(set -- --rules-drop ''; DROPS='{"0123abcd":"keep-mine"}'; die() { exit 9; }; eval "case \$1 in $HD esac"; echo "$DROPS")
fresh; owner; B=$(sums); ID=$(python3 "$REAL/scripts/merge-rules.py" "$REAL/templates/AGENT_STARTUP.md" --units 2>/dev/null | grep -oE '^[0-9a-f]{8}' | head -1)
lib "$CUSTOM" ${ID:+--drop "$ID"} >/dev/null 2>&1
sources; stage AGENT_STARTUP.md "$FM"$'# Startup\n- The plan first.\n'; lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
lib "$UNINSTALL" >/dev/null 2>&1
check "Auto over an earlier Custom setup clears its Keep-mine answers and uninstall still restores the bytes from before Custom" \
  "{}|1|1|$B" "$KM|$(after "$A" --rules-drop | grep -c '^$')|$(after "$C" --rules-drop | grep -c '^$')|$(sums)"

fresh; owner; B=$(sums)
sources; stage CLAUDE.md $'# Project\n- Tabs.\n'; stage AGENT_STARTUP.md "$FM"$'# Startup\n- The plan first.\n'
lib "$AUTO" "$S" no skip claude >/dev/null 2>&1; lib "$CUSTOM" >/dev/null 2>&1
CU=$(lib 'il_rules_same "$1" "$2" && il_rules_same "$3" "$4" && echo kept' "$PROJ/CLAUDE.md" "$S/CLAUDE.md" "$PROJ/AGENT_STARTUP.md" "$S/AGENT_STARTUP.md")
lib "$UNINSTALL" >/dev/null 2>&1
check "Custom after Auto leaves the rewritten text as it is and uninstall still restores the originals" "kept|$B" "$CU|$(sums)"

# --- edits the comparison and the restore must not lose (pass 1) ---
# A paragraph break is the owner's edit: only the blank lines beside a plugin block are no edit.
fresh; owner; B=$(sums)
sources; stage CLAUDE.md $'# Project\n- Tabs.\n- Run make check.\n'; lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
printf '# Project\n- Tabs.\n\n- Run make check.\n' > "$PROJ/CLAUDE.md"; cp "$PROJ/CLAUDE.md" "$T/edit"
SAME=$(lib 'il_rules_same "$1" "$2" && echo same || echo edit' "$PROJ/CLAUDE.md" "$S/CLAUDE.md")
lib "$UNINSTALL" >/dev/null 2>&1
check "an owner's blank line inside a rewritten file is an edit, kept through uninstall" "edit|$B|same" \
  "$SAME|$(sums)|$(cmp -s "$T/edit" "$PROJ/CLAUDE.md.commandeck-edited-$TODAY" && echo same)"

# The copy aside fails: uninstall (set -e, as uninstall.sh runs) stops with the record and its bytes kept, then runs again.
fresh; owner; B=$(sums)
sources; stage CLAUDE.md $'# Project\n- Tabs.\n'; lib "$AUTO" "$S" no skip claude >/dev/null 2>&1
printf -- '- edited after setup\n' >> "$PROJ/CLAUDE.md"; cp "$PROJ/CLAUDE.md" "$T/edit"; E=$(sha256sum < "$T/edit" | cut -c1-16)
R1=$(lib 'set -e; il_keep_edit() { return 1; }; '"$UNINSTALL" >/dev/null 2>&1; echo $?)
KEPT=$(lib '[ -s "$IL_PROJECT" ] && [ -s "$IL_DIR/blobs/$(jq -r --arg p "$1" ".entries[\$p].prior" "$IL_PROJECT" | cut -d: -f2)" ] && echo kept' "$PROJ/CLAUDE.md")
E1=$(sha256sum < "$PROJ/CLAUDE.md" | cut -c1-16)
lib "$UNINSTALL" >/dev/null 2>&1
check "an edit copy that fails stops uninstall, record and bytes kept, a rerun restores both" \
  "1|kept|$E|$B|same" "$R1|$KEPT|$E1|$(sums)|$(cmp -s "$T/edit" "$PROJ/CLAUDE.md.commandeck-edited-$TODAY" && echo same)"

# --- class rewrite-restore (pass 2): whatever the global file's prior, its pre-Auto text and a later edit survive ---
# Every ordering found so far, in order: a blob prior; Custom made the file (prior "did not exist") and the owner added a
# line (r1: the restore skipped the rewrite); the same with 20000 owner lines (r2: `| grep -q` stopped early and the
# backup was skipped); Custom made it, blocks only; a dangling-link prior. Each: Auto rewrites it, the owner edits it,
# uninstall fails at the edit copy (tick 1), one piece of the rewrite's state goes (each piece once), uninstall runs
# again (tick 2). A blob prior comes back byte for byte; a file setup created comes back to its text right before Auto,
# the plugin's blocks out, and is never removed (the owner's ruling, 2026-11-01); a backup holding nothing outside the
# plugin's blocks goes. Per ordering: <pre-Auto backup taken>|<first rc>|<record gone>|<edit beside it>|<prior
# back>|<backups left>.
G=$T/G
for o in blob:file absent:blob large:none blocks:none dangling:backup; do
  x=${o#*:} o=${o%:*}; fresh; owner; B=$(sums | cut -d' ' -f5)
  case $o in
    blob) ;;
    dangling) rm "$H/.claude/CLAUDE.md"; ln -s "$H/.claude/real.md" "$H/.claude/CLAUDE.md" ;;
    *) rm "$H/.claude/CLAUDE.md" ;;
  esac
  [ "$o" = blob ] || lib 'il_record "$IL_MACHINE" merge "$IL_GLOBAL" && il_global install claude-md "$IL_ROOT/templates/global-claude.md" --global-claude' >/dev/null 2>&1
  case $o in
    absent|dangling) printf -- '- Owner rule.\n' >> "$H/.claude/CLAUDE.md" ;;
    large) python3 -c 'print("- Preserve this owner rule.\n" * 20000, end="")' >> "$H/.claude/CLAUDE.md" ;;
  esac
  cp "$H/.claude/CLAUDE.md" "$T/pre"
  sources; stage global/CLAUDE.md $'# Mine\n- Owner rule, tightened.\n'; lib "$AUTO" "$S" yes skip claude >/dev/null 2>&1
  K=$(cmp -s "$T/pre" "$H/.claude/CLAUDE.md.commandeck-bak-$TODAY" && echo bak)
  printf -- '- later\n' >> "$H/.claude/CLAUDE.md"; cp "$H/.claude/CLAUDE.md" "$T/edit"
  R1=$(lib 'set -e; il_keep_edit() { return 1; }; '"$UNINSTALL" >/dev/null 2>&1; echo $?)
  case $x in
    backup) rm -f "$H/.claude/CLAUDE.md.commandeck-bak-$TODAY" ;;
    blob) lib 'rm -f "$IL_DIR/blobs/$(jq -r --arg p "$IL_GLOBAL" ".entries[\$p].written" "$IL_MACHINE" | cut -d: -f2)"' ;;
    file) rm -f "$(readlink -f "$H/.claude/CLAUDE.md")" ;;
  esac
  lib 'set -e; '"$UNINSTALL" >/dev/null 2>&1
  if [ "$o" = blob ]; then P=$([ "$(sums | cut -d' ' -f5)" = "$B" ] && echo back)
  else P=$({ [ -L "$H/.claude/CLAUDE.md" ] || [ "$o" != dangling ]; } && cmp -s <(printf '%s\n' "$(lib 'il_rules_strip "$1"' "$T/pre")") "$H/.claude/CLAUDE.md" && echo back); fi
  printf '%s:%s|%s|%s|%s|%s|%s\n' "$o" "$K" "$R1" "$(lib '[ -e "$IL_MACHINE" ] || echo gone')" \
    "$(cmp -s "$T/edit" "$H/.claude/CLAUDE.md.commandeck-edited-$TODAY" && echo edit)" "$P" "$(bak)"
done > "$G"
check "every rewrite ordering keeps the pre-Auto text and a later edit, and uninstall retried restores with any piece gone" \
  'blob:bak|1|gone||back|0 absent:bak|1|gone|edit|back|1 large:bak|1|gone|edit|back|1 blocks:bak|1|gone|edit|back|0 dangling:bak|1|gone|edit|back|0' \
  "$(paste -sd' ' "$G")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
