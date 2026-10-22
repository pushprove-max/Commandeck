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
# Issue 245: an option /config shows that nothing reads is a setting that does nothing; a default other than setup's
# recommended answer shows the owner one thing in /config while setup recommends another.
# A role key (issue 312) is read by pp_role_option for every role and field routing.json has; its name is built.
READ=$(cd "$REAL" && { grep -rhoE 'pp_(config_)?option [A-Za-z]+' scripts hooks --include='*.sh' --exclude-dir=__tests__ | awk '{print $2}'
  bash -c '. scripts/paths.sh && for r in $(jq -r ".roles | keys[]" config/routing.json); do for f in $PP_ROLE_FIELDS; do pp_role_key "$r" "$f"; done; done'; } | sort -u)
for k in $(jq -r '.userConfig | keys[]' "$M"); do
  check "option $k has a reader" 1 "$(grep -cx "$k" <<<"$READ")"
done
# <key> <default> <setup's recommended answer, as SKILL.md asks it>; none: no default, as the recommended answer saves none.
# -: setup asks nothing for it, so only the default is checked.
while IFS='|' read -r k d a; do
  [ "$a" != - ] || { check "option $k, which setup does not ask, has no default" "$d" "$(jq -c --arg k "$k" '.userConfig[$k].default // "none"' "$M")"; continue; }
  check "option $k defaults to setup's recommended answer ($a)" "$d 1" "$(jq -c --arg k "$k" '.userConfig[$k] | if has("default") then .default else "none" end' "$M") $(grep -cF "$a (recommended)" "$REAL/skills/setup/SKILL.md")"
done <<'EOF'
builderModel|"project"|Ask "Builder model": Opus
builderEffort|"project"|Ask "Builder effort": Medium
orchestratorEffort|"project"|Ask "Main": Opus, default effort
fixerEnabled|true|Ask "Fixer": Same as Builder, then Opus high
fixerFirstModel|"project"|Ask "Fixer": Same as Builder, then Opus high
codexReviewerModel|"project"|Ask "Reviewer model": Sol medium
planAuthorEnabled|true|Ask "Plan author": Opus high
planJudgeSolEnabled|true|Ask "Sol judge": Codex high
planJudgeAstraEnabled|true|Ask "Astra judge": Codex high
planAuthorFast|false|Ask "Fast tier", one multi-select question (`multiSelect: true`): None
maxReviewRounds|"none"|Ask "Review rounds": No cap
closingPass|true|Ask "Closing pass": Runs
fullSuiteBeforeFinal|true|Ask "Full suite before the final review": On
ponytail|true|Ask "Ponytail": On
promptCacheTtl|"5m"|Ask "Prompt cache": 5m for main and workers
relayPromptCacheTtl|"1h"|Ask "Relay prompt cache": 1h
dashboardBind|"127.0.0.1"|Ask "Dashboard": On, this machine only
dashboardPort|"none"|Ask "Dashboard": On, this machine only
maxBuilders|"none"|-
EOF
check "the set is the ten options of the plan's question 9, the Builder cap (issue 256) and 25 role keys (issue 312)" 36 "$(jq '.userConfig | length' "$M")"
# Issue 293: a Sonnet Builder ran at medium because setup recommended Medium whatever the model, and asked it three
# questions later. The effort is asked right after the model, High recommended on Sonnet; the model and effort
# options default to "project", no answer, which the /config dialog may save without hiding the project's answer.
check "setup asks the Builder effort right after the model, High recommended on Sonnet" '1:1' \
  "$(awk '/Ask "Builder model":/ {m = 1; next} m && /^ +Ask / {print ($0 ~ /Ask "Builder effort": Medium \(recommended\)/); exit}' "$REAL/skills/setup/SKILL.md"):$(grep -A1 -x '   On Sonnet:' "$REAL/skills/setup/SKILL.md" | grep -cxF '   Ask "Builder effort": High (recommended) | Low | Medium | Maximum')"
# claude plugin validate refuses a picker with no default among its options.
check "every picker's labels are 1 to 64 characters and hold its default" true \
  "$(jq '[.userConfig[] | select(.options) | . as $o | (.options | all(length >= 1 and length <= 64)) and any($o.options[]; . == $o.default)] | all' "$M")"
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
# Issue 203: a helper answers by its 20th tool call and names what it did not find, and every helper prompt carries
# those caps and reuses an earlier helper's file:line pointers. A Builder waiting on its own run keeps its cache warm on
# a Signal WARM line, and a worker's ask fits under the prompt cache (issue 214).
BT=$REAL/templates/_builder-brief-template.md
check "the Builder template carries the helper caps, the reuse rule, the WARM reply and the 240 s ask" "1 1 1 1 1" \
  "$(for p in '20th tool call' 'NOT FOUND: <what' 'already answered part of it' 'Signal WARM' 'timeout-ms 240000'; do grep -c -- "$p" "$BT"; done | paste -sd' ' -)"
# A helper is a built-in type (Explore or general-purpose): a plugin agent folder would be one more set of agents to keep.
check "the plugin ships no agents/ folder" no "$([ -e "$REAL/agents" ] && echo yes || echo no)"
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
check "the prompt-cache question says 5m cost less for main and workers, and Leave as is writes nothing" '1:1:1' "$(grep -cxF '    Ask "Prompt cache": 5m for main and workers (recommended) | Leave as is' "$SETUP"):$(grep -cF -- '- 5m for main and workers: Main, Builders, reviewers and every other worker pane keep their cache 5 minutes, subagents too. On real sessions a 5-minute cache cost about 5% less for main and 6 to 17% less for worker panes: they seldom pause long enough for a 1-hour cache to pay. Saved in `.claude/settings.json` and each worktree'"'"'s `.claude/settings.local.json`. `--cache-ttl 5m`' "$SETUP"):$(grep -cF -- '- Leave as is: writes nothing; what is set now stays, a 1-hour value an earlier setup wrote included (on a Claude subscription an unset cache is 1 hour). `--cache-ttl leave`' "$SETUP")"
check "the relay's question says 5m cost it more than 1h, and Leave as is writes nothing" '1:1:1' "$(grep -cxF '    Ask "Relay prompt cache": 1h (recommended) | Leave as is' "$SETUP"):$(grep -cF -- '- 1h: The relay pane keeps its cache 1 hour. It waits on you between turns, and on real sessions a 5-minute cache cost it about 85% more than 1 hour. Saved in its worktree'"'"'s `.claude/settings.local.json`; its other settings stay. The doctor warns if another file overrides it. `--relay-cache-ttl 1h`' "$SETUP"):$(grep -cF -- '- Leave as is: writes nothing in the relay'"'"'s settings. `--relay-cache-ttl leave`' "$SETUP")"
# Issue 244: the closing pass runs the full suite only when the owner said so.
check "setup asks whether the full suite runs before the final review, On recommended, with its flag" '1:1:1' "$(grep -cxF '   Ask "Full suite before the final review": On (recommended) | Off' "$SETUP"):$(grep -c 'one full run of <testCommand> per build; catches failures a static review misses.*`--full-suite on`' "$SETUP"):$(grep -c '`--full-suite off`' "$SETUP")"
# An update must ask the unanswered cache questions, not replay them.
check "the update skill asks the Prompt cache questions from setup's text, with only the answered flag" 1 "$(grep -c 'Prompt cache:.*Relay prompt cache:.*setup.sh.* only that flag' "$REAL/skills/update/SKILL.md")"
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
# A worker pane prints this in place of the plugin's whole ponytail text: a startup print is paid for in every pane.
check "the ponytail summary a worker pane prints is at most 1,200 bytes" ok "$([ "$(wc -c < "$REAL/templates/ponytail/SUMMARY.md")" -le 1200 ] && echo ok || echo long)"

# Issue 291: under an account profile Claude Code keeps these in CLAUDE_CONFIG_DIR, and a read of ~/.claude found
# nothing there. The plugin's own folders (checkpoints, rulings, hook-fire-log) stay under ~/.claude. proof-run.sh
# builds a fake HOME with CLAUDE_CONFIG_DIR unset.
RE291='\$(HOME|\{HOME\})"?/\.claude/(projects|sessions|plugins|skills|commands|settings\.json)|\$(HOME|\{HOME\})"?/\.claude\.json|expanduser\(.~/\.claude/(projects|sessions|\.credentials)'
check "issue 291: no script or hook reads Claude Code's own files from HOME past CLAUDE_CONFIG_DIR" "" \
  "$(cd "$REAL" && grep -rnE "$RE291" \
    scripts hooks skills --include='*.sh' --include='*.py' --include='*.mjs' | grep -v -e '/__tests__/' -e '^scripts/proof-run\.sh:')"
# The proof-run.sh exemption holds only while its every HOME/.claude read is of the fake HOME: HOME is set once,
# to a mktemp folder, after CLAUDE_CONFIG_DIR is unset and before the first such read.
check "issue 291: proof-run.sh sets HOME once, to a temp folder with CLAUDE_CONFIG_DIR unset, before it reads HOME/.claude" ok \
  "$(P=$REAL/scripts/proof-run.sh
     t=$(grep -nm1 '^T=$(cd "$(mktemp -d)"' "$P" | cut -d: -f1) u=$(grep -nm1 '^unset .*CLAUDE_CONFIG_DIR' "$P" | cut -d: -f1)
     h=$(grep -nE '(^|[^A-Za-z_])HOME=' "$P") f=$(grep -nE -m1 "$RE291" "$P" | cut -d: -f1)
     [ "$(wc -l <<<"$h")" -eq 1 ] && [[ $h =~ ^([0-9]+):export\ HOME=\$T/ ]] && [ -n "$t" ] && [ -n "$u" ] && [ -n "$f" ] &&
       [ "$t" -lt "${BASH_REMATCH[1]}" ] && [ "$u" -lt "${BASH_REMATCH[1]}" ] && [ "${BASH_REMATCH[1]}" -lt "$f" ] && echo ok || echo "not isolated: $h")"
# Every ledger setup hides from git under .claude/metrics is one uninstall --delete-data removes.
check "every .claude/metrics ledger in IL_STATE is deleted by uninstall --delete-data" "" \
  "$(cd "$REAL" && for f in $(grep -o '\.claude/metrics/[a-z-]*\.jsonl' scripts/install-lib.sh | sort -u); do n=${f##*/}; n=${n%.jsonl}
     grep -qE "metrics/\"?\{([a-z-]+,)*$n(,[a-z-]+)*\}\.jsonl" scripts/uninstall.sh || echo "$f"; done)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
