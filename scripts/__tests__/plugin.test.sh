#!/usr/bin/env bash
# The manifest is what `claude plugin install` reads. A manifest that does not
# parse, lacks its name or version, or points at a hook or command file that
# is not in the repo installs a plugin that fails at first use, on someone
# else's machine. Later batches add hooks and commands; this holds them to
# files that exist.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# manifest_ok <plugin root> -- 0 when the manifest parses, carries a name and a
# semver version, and every file it names exists. A file is any string value
# that is a ./ path or starts at ${CLAUDE_PLUGIN_ROOT}, wherever it sits: hooks,
# commands, agents, skills, an inline hook's command.
manifest_ok() {
  local m=$1/.claude-plugin/plugin.json p
  jq -e '(.name | type == "string" and test("^[a-z0-9][a-z0-9-]*$"))
    and (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$m" >/dev/null 2>&1 || return 1
  while IFS= read -r p; do
    [ -e "$1/$p" ] || { echo "manifest names a missing file: $p"; return 1; }
  done < <(jq -r '.. | strings | select(test("^(\\./|\\$\\{CLAUDE_PLUGIN_ROOT\\}/)"))
    | sub("^\\$\\{CLAUDE_PLUGIN_ROOT\\}/"; "") | sub("^\\./"; "") | split(" ")[0] | select(. != "")' "$m")
}
stage() { rm -rf "$TMP/p"; mkdir -p "$TMP/p/.claude-plugin" "$TMP/p/hooks"; printf '%s\n' "$1" > "$TMP/p/.claude-plugin/plugin.json"; }
ok() { manifest_ok "$TMP/p" >/dev/null 2>&1; echo $?; }

check "the shipped manifest is sound" 0 "$(manifest_ok "$REAL" >/dev/null 2>&1; echo $?)"
M=$REAL/.claude-plugin/plugin.json
check "it is version 0.2.0" 0.2.0 "$(jq -r .version "$M" 2>/dev/null)"
check "the README's badge shows the manifest's version, twice on its line" 2 "$(grep -o "version-0\.2\.0-\|Version 0\.2\.0\"" "$REAL/README.md" | wc -l | tr -d ' ')"
check "and the CHANGELOG has that version's entry" 1 "$(grep -c '^## 0\.2\.0 -- ' "$REAL/CHANGELOG.md")"
check "it carries a description" yes "$(jq -r 'if (.description | type == "string" and length > 20) then "yes" else "no" end' "$M" 2>/dev/null)"
check "it declares no hooks and no commands yet" "null null" "$(jq -c '.hooks, .commands' "$M" 2>/dev/null | paste -sd' ' -)"
# Claude Code loads hooks/hooks.json without being told. A command that names
# a script the repo lacks, or one that is not executable, fails at the first
# event on someone else's machine, and a failed Stop hook is silent.
H=$REAL/hooks/hooks.json
hook_files() { jq -r '.hooks[][].hooks[].command | capture("^\"\\$\\{CLAUDE_PLUGIN_ROOT\\}/(?<f>[^\"]+)\"").f' "$H" 2>/dev/null; }
# The root is wherever the plugin was installed, and that path may hold a
# space: unquoted, the shell splits it and every hook fails, the ones that run
# on every tool call included.
# Each goes through the launcher, which finds a Bash new enough for the hook.
check "every hook command runs from the plugin root, through the launcher, each path quoted" 0 "$(jq '[.hooks[][].hooks[].command | select(test("^\"\\$\\{CLAUDE_PLUGIN_ROOT\\}/hooks/lib/run-hook\\.sh\" \"\\$\\{CLAUDE_PLUGIN_ROOT\\}/hooks/[A-Za-z0-9_.-]+\"( |$)") | not)] | length' "$H" 2>/dev/null)"
mkdir -p "$TMP/a root"; ln -s "$REAL/hooks" "$TMP/a root/hooks"
check "and each one is a runnable word under a root with a space in it" "" \
  "$(jq -r '.hooks[][].hooks[].command' "$H" | while IFS= read -r c; do CLAUDE_PLUGIN_ROOT="$TMP/a root" bash -c "set -- $c; [ -x \"\$1\" ]" 2>/dev/null || echo "$c"; done | head -3)"
check "every registered hook is an executable file in the repo" "" "$(hook_files | while read -r f; do [ -x "$REAL/$f" ] || echo "$f"; done)"
check "hooks.json registers hooks" yes "$([ "$(hook_files | wc -l)" -ge 10 ] && echo yes || echo no)"
# Claude Code offers every skill under skills/ too. /handoff ends by leaving a
# marker for the context-clear Stop hook: offered without that hook registered,
# it would write the marker and restart nothing.
front() { sed -n '2,/^---$/p' "$REAL/skills/handoff/SKILL.md"; }
check "the handoff skill is offered, and its Stop hook is registered" "1 0 1" \
  "$(front | grep -cx 'disable-model-invocation: true') $(front | grep -cx 'user-invocable: false') $(jq '[.hooks.Stop[].hooks[].command | select(endswith("/hooks/context-clear-stop.sh\""))] | length' "$H" 2>/dev/null)"
# The skill runs in the user's project, where the plugin's files are not.
check "the handoff skill names no plugin file by a project path" 0 "$(grep -cE 'CLAUDE_PROJECT_DIR|`(scripts|templates)/' "$REAL/skills/handoff/SKILL.md")"
# `claude plugin install` reads a marketplace; the repo is its own.
check "the marketplace lists this plugin at the repo root" "$(jq -r .name "$M" 2>/dev/null) ./" \
  "$(jq -r '.plugins[0] | "\(.name) \(.source)"' "$REAL/.claude-plugin/marketplace.json" 2>/dev/null)"

stage '{"name": "p", "version": "0.1.0"}'
check "a minimal manifest passes" 0 "$(ok)"
stage '{"name": "p", "version": "0.1.0",}'
check "a manifest that does not parse fails" 1 "$(ok)"
stage '{"version": "0.1.0"}'
check "a manifest without a name fails" 1 "$(ok)"
stage '{"name": "p"}'
check "a manifest without a version fails" 1 "$(ok)"
stage '{"name": "p", "version": "0.1.0", "hooks": "./hooks/hooks.json"}'
check "a hooks file that does not exist fails" 1 "$(ok)"
echo '{}' > "$TMP/p/hooks/hooks.json"
check "the same manifest passes once the file exists" 0 "$(ok)"
stage '{"name": "p", "version": "0.1.0", "commands": ["./commands/setup.md"]}'
check "a command file that does not exist fails" 1 "$(ok)"
stage '{"name": "p", "version": "0.1.0", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/gone.sh --flag"}]}]}}'
check "an inline hook whose script does not exist fails" 1 "$(ok)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
