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
# The version comes from the manifest, so a release edits one file, not this test.
V=$(jq -r .version "$M" 2>/dev/null); VE=${V//./\\.}
check "the README's badge shows the manifest's version in its image and its alt text, on one line" 1 "$(grep -c "badge/version-$VE-.*alt=\"Version $VE\"" "$REAL/README.md")"
check "the README shows no other version badge" 1 "$(grep -c 'badge/version-' "$REAL/README.md")"
check "and the CHANGELOG's newest entry is that version" "## $V -- " "$(grep -m1 -o '^## [^ ]* -- ' "$REAL/CHANGELOG.md")"
check "it carries a description" yes "$(jq -r 'if (.description | type == "string" and length > 20) then "yes" else "no" end' "$M" 2>/dev/null)"
check "it declares no hooks and no commands yet" "null null" "$(jq -c '.hooks, .commands' "$M" 2>/dev/null | paste -sd' ' -)"
# An instruction file over 200 lines loads in every session and is followed less well (Claude Code's memory guide).
# startup-size.sh holds the bytes the hooks print; global-claude.md and global-rules.md never pass through a hook.
for t in AGENT_STARTUP main-session global-claude global-rules; do
  check "templates/$t.md is at most 200 lines: a longer file loads in every session and is followed less well" ok \
    "$([ "$(wc -l < "$REAL/templates/$t.md")" -le 200 ] && echo ok || echo long)"
done
# A skill's SKILL.md over 500 lines, or description plus when_to_use over 1,536 characters, is cut or ignored; a skill
# that spends money or changes the owner's setup must not be one Claude can start by itself.
for d in "$REAL"/skills/*/; do
  n=$(basename "$d")
  check "skills/$n/SKILL.md is at most 500 lines" ok "$([ "$(wc -l < "$d/SKILL.md")" -le 500 ] && echo ok || echo long)"
  check "skills/$n description plus when_to_use is at most 1,536 characters" ok \
    "$([ "$(awk '/^---$/ {k++; next} k == 1 && /^(description|when_to_use): / {sub(/^[a-z_]+: /, ""); c += length($0)} END {print c + 0}' "$d/SKILL.md")" -le 1536 ] && echo ok || echo long)"
done
for n in setup update uninstall handoff worktreereview; do
  check "skills/$n sets disable-model-invocation: a side-effect skill Claude could start by itself is the failure" 1 \
    "$(grep -c '^disable-model-invocation: true$' "$REAL/skills/$n/SKILL.md")"
done
# The lean helper agent: omitClaudeMd and maxTurns do the work; hooks, mcpServers and permissionMode are ignored for a
# plugin's agents, so each would be a setting that silently does nothing.
H=$REAL/agents/helper.md
check "agents/helper.md sets omitClaudeMd and maxTurns, and none of the keys a plugin agent ignores" "1 1 0" \
  "$(grep -c '^omitClaudeMd: true$' "$H") $(grep -c '^maxTurns: [0-9]' "$H") $(grep -cE '^(hooks|mcpServers|permissionMode):' "$H")"
# The fast-tier question's "None" answer is `--plan-fast ''` (skills/setup): the flag takes the empty value, and an empty value saves no planFast.
check "setup.sh takes --plan-fast as a value flag and saves nothing for an empty one" "1 1" \
  "$(grep -c '^TAKES=.* --plan-fast ' "$REAL/scripts/setup.sh") $(grep -c 'if $pf == "" then {} else {planFast' "$REAL/scripts/setup.sh")"
# Every key merge-unit-local.sh reads from .claude/commandeck.json must survive setup's rebuild of that file
# (update reruns setup): a key the writer's object does not build is dropped at the next update.
for k in $(sed -n "s/.*jq -r '\.\([A-Za-z]*\).*commandeck\.json.*/\1/p" "$REAL/scripts/merge-unit-local.sh"); do
  check "setup.sh's config writer names $k, which merge-unit-local.sh reads" 1 "$(grep -cE "[{,] *$k:" "$REAL/scripts/setup.sh" | sed 's/^[1-9][0-9]*$/1/')"
done
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
# Main may read any file in a worker's worktree (owner ruling 2026-10-15, restoring 2026-09-25): every
# hook that runs before main's Read, Grep or Glob lets a worktree path through.
git init -q "$TMP/main"; mkdir -p "$TMP/main/.claude"; echo '{"version": 1}' > "$TMP/main/.claude/commandeck.json"; W=$TMP/main/orca/workspaces/u/src/a.sh
refused=$(for t in Read Grep Glob; do
  jq -r --arg t "$t" '.hooks.PreToolUse[] | select(.matcher as $m | $t | test("^(" + $m + ")$")) | .hooks[].command' "$H" | while IFS= read -r c; do
    jq -n --arg t "$t" --arg w "$W" --arg d "$TMP/main" '{tool_name: $t, cwd: $d, session_id: "s", tool_input: {file_path: $w, path: $w, pattern: $w}}' \
      | (cd "$TMP/main" && CLAUDE_PLUGIN_ROOT=$REAL CLAUDE_PROJECT_DIR=$TMP/main HOME=$TMP bash -c "set -- $c; \"\$@\"" >/dev/null 2>&1) || echo "$t: $c"
  done
done)
check "no hook refuses main a read in a worker's worktree" "" "$refused"
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

# #86: setup asks every value in a picker. A "name one" option sent the owner a typed follow-up list in
# chat, past the picker's record. The decoy is off while setup asks (owner ruling Q5), so a question
# has the picker's four options of its own.
SETUP=$REAL/skills/setup/SKILL.md
ASKS=$(grep -E '^ +Ask "[^"]+": ' "$SETUP")
check "setup asks its questions in pickers" 1 "$([ "$(wc -l <<<"$ASKS")" -ge 15 ] && echo 1)"
check "no setup question has more than four options of its own" "" "$(awk -F' [|] ' 'NF > 4' <<<"$ASKS")"
check "no setup option defers a typed value to a follow-up" "" "$(grep -E '(: |[|] )(name one|set one|set a number|set numbers|another name)( [|]|$)' <<<"$ASKS")"
check "setup sends no typed follow-up after its pickers" 0 "$(grep -ci 'ask in plain text for' "$SETUP")"
# A first-time owner sees which answer to take: one option of every question is marked, and a
# question is titled in words, never by a rule's hash.
check "every setup question marks exactly one answer (recommended)" "" "$(grep -v ' (recommended)' <<<"$ASKS"; grep '(recommended).*(recommended)' <<<"$ASKS")"
# The recommended cache answer must not read as the one that costs more.
check "the prompt-cache question says the recommended mix cost least" '1:1' "$(grep -cxF '    Ask "Prompt cache": 1h for main, 5m for subagents (recommended) | Leave default' "$SETUP"):$(grep -cF -- '- 1h for main, 5m for subagents: Main and Claude panes keep their cache 1 hour, subagents 5 minutes. On real sessions this mix cost least: a 5-minute cache cost main about 19% more, and a 1-hour cache cost subagents about 8% more. Saved in `.claude/settings.json`. `--cache-ttl recommended`' "$SETUP")"
# Leave must read as a change of nothing: the machine's file serves every project, so a Leave that removed would take another project's lines.
check "the auto-mode question: Leave changes nothing, and only Take them out removes" '1:1:1' "$(grep -cxF '    Ask "Auto mode": Add two entries (recommended) | Leave as is | Take them out' "$SETUP"):$(grep -cF -- '- Leave as is: Changes nothing in ~/.claude/settings.json; a refusal of a plugin script stays possible. `--auto-mode leave`' "$SETUP"):$(grep -c -- '--auto-mode remove' "$SETUP")"
check "no setup question is titled by a rule id" "" "$(grep -E 'Ask "(<id>|[0-9a-f]{8})"' <<<"$ASKS")"

# The add-on list and the ponytail skill setup installs, as shipped, read without a setup run. The owner wants
# every add-on kept at its latest, no version pinned; the skill's own rule keeps its name out of code comments.
check "every add-on has a command and a cost: none is a placeholder" 0 \
  "$(grep -v '^#' "$REAL/config/addons.tsv" | awk -F'\t' '$2 == "" || $3 == "" || /no public source/' | wc -l | tr -d ' ')"
check "no add-on command names a version" 0 "$(grep -v '^#' "$REAL/config/addons.tsv" | cut -f2 | grep -cE '@[0-9]|==|--version[ =]?[0-9]')"
check "the ponytail skill says never to write its name in a comment" '1:0' \
  "$(grep -c 'Never write "ponytail" in a comment' "$REAL/templates/ponytail/SKILL.md"):$(grep -c '`ponytail:` comment' "$REAL/templates/ponytail/SKILL.md")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
