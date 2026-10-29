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
  bash -c '. scripts/paths.sh && for r in $(jq -r ".roles | keys[]" config/routing.json); do for f in $PP_ROLE_FIELDS; do pp_role_key "$r" "$f"; done; done'
  # The hooks module reads its option as options.<key> (hooks/autodecide.tsx).
  grep -ohE 'options\.[A-Za-z]+' hooks/*.tsx | sed 's/^options\.//'; } | sort -u)
for k in $(jq -r '.userConfig | keys[]' "$M"); do
  check "option $k has a reader" 1 "$(grep -cx "$k" <<<"$READ")"
done
# <key> <default> <setup's recommended answer, as SKILL.md asks it>; none: no default, as the recommended answer saves none.
# -: setup asks nothing for it, so only the default is checked.
while IFS='|' read -r k d a; do
  [ "$a" != - ] || { check "option $k, which setup does not ask, has no default" "$d" "$(jq -c --arg k "$k" '.userConfig[$k].default // "none"' "$M")"; continue; }
  check "option $k defaults to setup's recommended answer ($a)" "$d 1" "$(jq -c --arg k "$k" '.userConfig[$k] | if has("default") then .default else "none" end' "$M") $(grep -cF "$a (recommended)" "$REAL/skills/setup/SKILL.md")"
done <<'EOF'
fullSuiteBeforeFinal|true|Ask "Full suite before the final review": On
dashboardBind|"127.0.0.1"|Ask "Dashboard": On, this machine only
dashboardPort|"none"|Ask "Dashboard": On, this machine only
maxBuilders|"none"|-
EOF
# The recommended profile (config/recommended.json) holds the recommended value of every other option; the skill reads
# it from setup.sh, so its text no longer repeats them. A manifest default that is a concrete value (not "project", which
# is the role's own default) is the profile's value too: the two would show the owner different answers.
check "a profile value equals the key's manifest default wherever the default is a concrete value" "" \
  "$(jq -r --slurpfile m "$M" '.options | to_entries[] | .key as $k | $m[0].userConfig[$k] as $c
    | select($c.default != null and $c.default != "project" and $c.default != .value) | $k' "$REAL/config/recommended.json" | paste -sd' ' -)"
check "the profile recommends an Opus Builder at medium effort (Opus at medium builds as well as Sonnet at high, for less)" "opus medium" \
  "$(jq -r '.options | "\(.builderModel) \(.builderEffort)"' "$REAL/config/recommended.json")"
check "the set is the 26 role keys (issue 312; the Fable judge has four and no agent key) and the 17 options that are no role's: the Builder cap (issue 256), the two wake options (issue 318), the auto-decide seats option (issue 333), the units mod's three views (issue 349), the three prompt-cache options, one for each role (issue 367), and the review workflow's three (blocking severity, pass cap, fresh closing reviewer; issue 373), among them" 43 "$(jq '.userConfig | length' "$M")"
# The recommended profile (config/recommended.json) is the one place setup's recommended values live. Every option is in it
# or asked by name, so none is left for an owner who takes the recommended set to find in /config; every value is one its
# key takes; and it holds nothing that is one machine's (a path, an address, a name).
REC=$REAL/config/recommended.json
ORPHANS=$(jq -r --slurpfile r "$REC" '.userConfig | keys[] | select(. as $k | $r[0].options | has($k) | not)' "$M" | sort | paste -sd' ' -)
check "every option is in the recommended profile or asked by name; the ones asked are these" \
  "codexReviewerAgent dashboardBind dashboardPort fullSuiteBeforeFinal maxBuilders planJudgeSolAgent" "$ORPHANS"
SK=$REAL/skills/setup/SKILL.md
check "and the skill asks each of them: the Reviewer question, the Dashboard question, the Full suite question, and --option maxBuilders" "1 1 1 1" \
  "$(grep -c 'Ask "Reviewer"' "$SK") $(grep -c 'Ask "Dashboard"' "$SK") $(grep -c 'Ask "Full suite' "$SK") $(grep -c -- '--option maxBuilders=' "$SK")"
check "the profile names no option the manifest lacks" "" \
  "$(jq -r --slurpfile m "$M" '.options | keys[] | select(. as $k | $m[0].userConfig | has($k) | not)' "$REC" | paste -sd' ' -)"
check "every profile value is one its key takes (a listed word, a boolean, a number from the key's min, text)" "" \
  "$(jq -r --slurpfile m "$M" '.options | to_entries[] | .key as $k | .value as $v | $m[0].userConfig[$k] as $c
    | select(if $c.options then ($c.options | index($v) | not) elif $c.type == "boolean" then ($v | type) != "boolean"
      elif $c.type == "number" then (($v | type) != "number" or $v < ($c.min // 0) or ($c.max != null and $v > $c.max)) else ($v | type) != "string" end) | $k' "$REC" | paste -sd' ' -)"
check "the profile holds no path, address or name: no value with a slash, an at sign, a dotted address or a space" "" \
  "$(jq -r '.options | to_entries[] | select(.value | tostring | test("[/@ ]|[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+")) | .key' "$REC" | paste -sd' ' -)"
# Issue 373: a review loop with no pass cap never ends, so no option, flag or question offers one.
check "no setup question, flag or option offers No cap for the review loop" 0 \
  "$(cat "$REAL/skills/setup/SKILL.md" "$REAL/scripts/setup.sh" "$M" | grep -c 'No cap\|--max-rounds\|maxReviewRounds')"
# The second plan judge is a Claude seat on Fable that cannot write the plan it judges; the Astra judge role and its
# options are gone, and nothing outside the tests reads them.
check "the Fable judge is a read-only Claude reviewer on fable at high, and no Astra judge role is left" \
  "claude fable high true false Write,Edit,NotebookEdit,Agent:false:" \
  "$(jq -r '.roles["plan-judge-fable"] | "\(.agent) \(.model) \(.effort) \(.reviewer) \(.edits) \(.tools | join(","))"' "$REAL/config/routing.json"):$(jq '.roles | has("plan-judge-astra")' "$REAL/config/routing.json"):$(cd "$REAL" && grep -rnE 'planJudgeAstra|plan-judge-astra' scripts hooks config templates skills docs README.md .claude-plugin --exclude-dir=__tests__)"
# A key setup passes to setup.sh --option that the manifest lacks is refused there, so the question would break.
check "every option key setup's SKILL.md names is a manifest option" "" \
  "$( { grep -o -- '--option [A-Za-z]*=' "$REAL/skills/setup/SKILL.md" | sed 's/^--option //; s/=$//'; grep -o '`[A-Za-z]*Fast`' "$REAL/skills/setup/SKILL.md" | tr -d '`'; } | sort -u \
    | while read -r k; do jq -e --arg k "$k" '.userConfig | has($k)' "$M" >/dev/null || echo "$k"; done)"
# Issue 318: a settings file from before 0.27.0 has neither wake key and takes the defaults; a kinds list naming no
# kind would never wake main, and a window that is not whole seconds cannot be compared, so both take the default.
wopt() { (cd "$TMP" && CLAUDE_CONFIG_DIR=$TMP/cfg COMMANDECK_MAIN=$TMP COMMANDECK_OPTIONS=$1 bash -c '. "$0/scripts/paths.sh" && echo "$(pp_option wakeKinds) $(pp_option wakeWindowSeconds)"' "$REAL"); }
D318="worker_done,escalation,question,decision_gate,merge_ready 60"
check "wake options: no answer (the deployed format) takes the defaults" "$D318" "$(wopt '')"
check "wake options: an empty or unknown kinds list and a window that is not whole seconds take the defaults" "$D318:$D318" \
  "$(wopt '{"wakeKinds":"","wakeWindowSeconds":"soon"}'):$(wopt '{"wakeKinds":"bogus","wakeWindowSeconds":-5}')"
check "wake options: an answer is read, spaces dropped, and a window of 0 kept" "question,status 0" "$(wopt '{"wakeKinds":"question, status","wakeWindowSeconds":0}')"
# Issue 311: AskUserQuestion takes 2 to 4 options. "Worker cuts" and "Keep words" listed only None when nothing was saved,
# the call failed with "Invalid tool parameters" and the agent answered None without asking. A saved name or a detected
# command (<...>) may be absent, so the options that are always there must be two or more, and the line has at most four.
check "every one-line Ask in setup's SKILL.md has 2 to 4 options, two of them always present" "" \
  "$(awk -F'\n' '/^ *Ask "/ { o = $0; sub(/^ *Ask "[^"]*"[^|]*(: |:$)/, "", o); n = split(o, a, / \| /); f = 0
    for (i = 1; i <= n; i++) if (a[i] !~ /^</) f++
    if (n < 2 || n > 4 || f < 2) print $0 }' "$REAL/skills/setup/SKILL.md")"
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
for n in setup update uninstall handoff worktreereview revoke; do
  check "skills/$n sets disable-model-invocation: a side-effect skill Claude could start by itself is the failure" 1 \
    "$(grep -c '^disable-model-invocation: true$' "$REAL/skills/$n/SKILL.md")"
done
# Issue 203: a helper answers by its 20th tool call and names what it did not find, and every helper prompt carries
# those caps and reuses an earlier helper's file:line pointers. A Builder waiting on its own run keeps its cache warm on
# a Signal WARM line, and a worker's ask and its wait for main's answer to an owner question each fit under the prompt
# cache (issue 214).
BT=$REAL/templates/_builder-brief-template.md
check "the Builder template carries the helper caps, the reuse rule, the WARM reply, the 240 s ask and the 240 s owner-answer wait" "1 1 1 1 1 1" \
  "$(for p in '20th tool call' 'NOT FOUND: <what' 'already answered part of it' 'Signal WARM' 'question, 240 s at most per call' 'timeout-ms 240000'; do grep -c -- "$p" "$BT"; done | paste -sd' ' -)"
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
# issue 364: the Chief of Staff unfinished-work Stop hook ships unregistered; the script stays for a project that registers it.
check "the Chief of Staff unfinished-work Stop hook is not registered, and its script stays executable" "0 yes" \
  "$(hook_files | grep -c 'cos-unfinished-stop\.sh') $([ -x "$REAL/hooks/cos-unfinished-stop.sh" ] && echo yes || echo no)"
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
# The two group pickers choose which groups to answer, so no group is the recommended one.
check "every setup question marks exactly one answer (recommended)" "" "$(grep -v ' (recommended)' <<<"$ASKS" | grep -v '^ *Ask "\(More groups\|Groups\)": '; grep '(recommended).*(recommended)' <<<"$ASKS")"
# Issue 367: one prompt-cache question for each role, its default bullet and its Leave as is bullet each ending with the flag.
check "the main prompt cache question recommends 1h, offers 5m, and Leave as is writes nothing" '1:1:1:1' "$(grep -cxF '    Ask "Main prompt cache": 1h (recommended) | 5m | Leave as is' "$SETUP"):$(grep -cF -- '- 1h: Main keeps its cache 1 hour.' "$SETUP"):$(grep -cF -- '`--main-cache-ttl 1h`' "$SETUP"):$(grep -cF -- '- Leave as is: writes nothing; what is set now stays, a value an earlier setup wrote included. `--main-cache-ttl leave`' "$SETUP")"
check "the Builder and worker prompt cache question recommends 5m, offers 1h, and Leave as is writes nothing" '1:1:1:1' "$(grep -cxF '    Ask "Builder and worker prompt cache": 5m (recommended) | 1h | Leave as is' "$SETUP"):$(grep -cF -- '- 5m: Builders, reviewers and every other worker pane keep their cache 5 minutes, subagents too.' "$SETUP"):$(grep -cF -- '`--worker-cache-ttl 5m`' "$SETUP"):$(grep -cF -- '- Leave as is: writes nothing; what is set now stays, a value an earlier setup wrote included. `--worker-cache-ttl leave`' "$SETUP")"
check "the Chief of Staff prompt cache question recommends 1h, offers 5m, and Leave as is writes nothing" '1:1:1:1' "$(grep -cxF '    Ask "Chief of Staff prompt cache": 1h (recommended) | 5m | Leave as is' "$SETUP"):$(grep -cF -- '- 1h: The relay pane keeps its cache 1 hour. It waits on you between turns, and on real sessions a 5-minute cache cost it about 85% more than 1 hour.' "$SETUP"):$(grep -cF -- '`--relay-cache-ttl 1h`' "$SETUP"):$(grep -cF -- '- Leave as is: writes nothing; what is set now stays, a value an earlier setup wrote included. `--relay-cache-ttl leave`' "$SETUP")"
check "no setup text says a 5-minute cache cost main less" 0 "$(grep -c 'about 5% less for main' "$SETUP")"
# Issue 244: the closing pass runs the full suite only when the owner said so.
check "setup asks whether the full suite runs before the final review, On recommended, with its flag" '1:1:1' "$(grep -cxF '   Ask "Full suite before the final review": On (recommended) | Off' "$SETUP"):$(grep -c 'one full run of <testCommand> per build; catches failures a static review misses.*`--full-suite on`' "$SETUP"):$(grep -c '`--full-suite off`' "$SETUP")"
# An update must ask the unanswered cache questions, not replay them.
check "the update skill asks each role's prompt cache question from setup's text, with only that question's flag" '1:1:1:1' "$(grep -c 'Main prompt cache:.*Builder and worker prompt cache:.*Chief of Staff prompt cache:' "$REAL/skills/update/SKILL.md"):$(grep -c -- '--main-cache-ttl' "$REAL/skills/update/SKILL.md"):$(grep -c -- '--worker-cache-ttl' "$REAL/skills/update/SKILL.md"):$(grep -c -- '--relay-cache-ttl' "$REAL/skills/update/SKILL.md")"
check "each Needs-you prompt cache line opens with its setup question's title and names its flag" '1:1:1' \
  "$(grep -c 'NEED+=("Main prompt cache: not answered since 0.48.0.*--main-cache-ttl' "$REAL/scripts/setup.sh"):$(grep -c 'NEED+=("Builder and worker prompt cache: not answered since 0.48.0.*--worker-cache-ttl' "$REAL/scripts/setup.sh"):$(grep -c 'NEED+=("Chief of Staff prompt cache: not answered since 0.48.0.*--relay-cache-ttl' "$REAL/scripts/setup.sh")"
# Leave must read as a change of nothing: the machine's file serves every project, so a Leave that removed would take another project's lines.
check "the auto-mode question: Leave changes nothing, and only Take them out removes" '1:1:1' "$(grep -cxF '    Ask "Auto mode": Add two entries (recommended) | Leave as is | Take them out' "$SETUP"):$(grep -cF -- '- Leave as is: Changes nothing in ~/.claude/settings.json; a refusal of a plugin script stays possible. `--auto-mode leave`' "$SETUP"):$(grep -c -- '--auto-mode remove' "$SETUP")"
check "no setup question is titled by a rule id" "" "$(grep -E 'Ask "(<id>|[0-9a-f]{8})"' <<<"$ASKS")"

# The add-on list as shipped, read without a setup run. The owner wants every add-on kept at its latest, no version pinned.
check "every add-on has a command and a cost: none is a placeholder" 0 \
  "$(grep -v '^#' "$REAL/config/addons.tsv" | awk -F'\t' '$2 == "" || $3 == "" || /no public source/' | wc -l | tr -d ' ')"
check "no add-on command names a version" 0 "$(grep -v '^#' "$REAL/config/addons.tsv" | cut -f2 | grep -cE '@[0-9]|==|--version[ =]?[0-9]')"

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
# And every ledger a script names under .claude/metrics is in IL_STATE: a new one left out shows in git status and
# outlives uninstall --delete-data.
check "every .claude/metrics ledger a script names is in IL_STATE" "" \
  "$(cd "$REAL" && for f in $(grep -ho '\.claude/metrics/[a-z-]*\.jsonl' scripts/*.sh | sort -u); do
     grep -qF "$f" scripts/install-lib.sh || echo "$f"; done)"
check "no tracked file outside the changelog names the retired code-graph server, and no hook matches its tools (issue 446)" "" \
  "$(cd "$REAL" && git grep -il -e 'codebase[-]memory' -- ':!CHANGELOG.md'; jq -r '.. | .matcher? // empty' hooks/hooks.json | grep -iE 'codebase[-_]memory|mcp__codebase')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
