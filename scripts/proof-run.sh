#!/usr/bin/env bash
# proof-run.sh [--keep] [--profile claude|claude-openai] -- the numbers a
# release is compared by, for both profiles (or the one named). It builds a clean machine in a temp folder: an empty HOME that
# another tool has already written to, a small Node project whose one test
# fails (the toy unit), another project already on the dashboard, and this
# plugin copied outside any checkout. Per profile it runs setup, the scripted
# steps of one unit, and uninstall, and prints one row per measure.
#
# No model runs here and no real job starts: a clean HOME has no sign-in, so
# Orca, the service manager, `claude` and `codex` are stubs. The rows that need
# a live unit (tokens, cache, review passes, the restart resuming) are printed
# as "not measured" with the command that measures them after a real toy unit.
# Exit 1 when a measured row breaks its limit. --keep leaves the temp folder.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEEP= PROFILES=(claude claude-openai)
while [ $# -gt 0 ]; do
  case $1:${2:-} in
    --keep:*) KEEP=1; shift ;;
    --profile:claude|--profile:claude-openai) PROFILES=("$2"); shift 2 ;;
    *) echo "usage: proof-run.sh [--keep] [--profile claude|claude-openai]" >&2; exit 2 ;;
  esac
done
T=$(cd "$(mktemp -d)" && pwd -P)
[ -n "$KEEP" ] || trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT COMMANDECK_MAIN COMMANDECK_WORKSPACES COMMANDECK_SCRATCH CODEX_HOME COMMANDECK_DASHBOARD_DIR \
  COMMANDECK_HOOK_FIRE_LOG COMMANDECK_ROUTING COMMANDECK_CLEAR_LINE COMMANDECK_HOOK_TIER COMMANDECK_BUILDER COMMANDECK_REVIEWER AGENT_KIND
export HOME=$T/home COMMANDECK_HOST_OS=Linux PATH=$T/bin:$PATH
BIN=$T/bin PLUGIN=$T/plugin SAMPLE=$T/sample LIMIT=10240 RC=0
LIVE="not measured: no model runs here. After a real toy unit:"

# --- the machine ---
mkdir -p "$BIN" "$PLUGIN" "$HOME/.codex" "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/scripts" "$HOME/Library/LaunchAgents" "$HOME/.commandeck/dashboard"
for d in hooks scripts config templates dashboard skills .claude-plugin CHANGELOG.md; do cp -R "$ROOT/$d" "$PLUGIN/"; done
rm -rf "$PLUGIN/hooks/__tests__" "$PLUGIN/scripts/__tests__"
printf '#!/usr/bin/env bash\ncase "$*" in "worktree ps --json") echo %s ;; "terminal list --json") echo %s ;; *) echo %s ;; esac\n' \
  "'{\"result\":{\"worktrees\":[]}}'" "'{\"result\":{\"terminals\":[]}}'" "'{\"ok\":true,\"result\":{}}'" > "$BIN/orca-ide"
printf '#!/usr/bin/env bash\ncase "$*" in *is-active*) echo active ;; esac\n' > "$BIN/systemctl"
printf '#!/usr/bin/env bash\n[ "$*" = "login status" ]\n' > "$BIN/codex"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/claude"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/gh"   # the sample is no GitHub project: the real gh is never asked
chmod +x "$BIN"/*
# What another tool left here before the plugin: the stand-in for coexistence.
printf '{"models":[{"slug":"gpt-9.1-%s"}]}\n' "$(jq -r '.roles["codex-reviewer"].model' "$ROOT/config/routing.json")" > "$HOME/.codex/models_cache.json"
echo '// companion' > "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/scripts/codex-companion.mjs"
# The pass has no prompt but the installed Codex plugin's, and its preflight reads it.
mkdir -p "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/prompts"
printf '{{TARGET_LABEL}} {{USER_FOCUS}}\nPrefer one strong finding over several weak ones.\n<structured_output_contract>\njson\n</structured_output_contract>\n{{REVIEW_COLLECTION_GUIDANCE}}\n{{REVIEW_INPUT}}\n' \
  > "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/prompts/adversarial-review.md"
echo '{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "/opt/other-tool/hook.sh"}]}], "SessionEnd": [{"hooks": [{"type": "command", "command": "/opt/other-tool/end.sh"}]}]}}' > "$HOME/.codex/hooks.json"
printf 'service_tier = "fast"\n\n[hooks.state."%s/.codex/hooks.json:pre_tool_use:0:0"]\ntrusted_hash = "sha256:0000"\nenabled = false\n' "$HOME" > "$HOME/.codex/config.toml"
echo '{"statusLine": {"type": "command", "command": "other.sh"}, "permissions": {"allow": ["Bash(ls:*)"]}, "enabledPlugins": {"other@market": true}}' > "$HOME/.claude/settings.json"
echo '<plist>other tool</plist>' > "$HOME/Library/LaunchAgents/com.other-tool.dashboard.plist"
git init -q -b main "$T/other" && git -C "$T/other" -c user.name=p -c user.email=p@p commit -q --allow-empty -m first
echo "$T/other" > "$HOME/.commandeck/dashboard/projects"
# The sample project. Its one test fails: making it pass is the toy unit.
git init -q -b main "$SAMPLE"
echo '{"name": "sample", "private": true, "scripts": {"test": "node --test"}}' > "$SAMPLE/package.json"
echo 'module.exports = (a, b) => a - b;' > "$SAMPLE/sum.js"
echo "require('node:test')('sum adds', () => require('node:assert').strictEqual(require('./sum')(2, 3), 5));" > "$SAMPLE/sum.test.js"
git -C "$SAMPLE" add -A && git -C "$SAMPLE" -c user.name=p -c user.email=p@p commit -q -m "a sum that subtracts"

p() { local d=$1 s=$2; shift 2; ( cd "$d" && bash "$PLUGIN/scripts/$s" "$@" </dev/null ); }
row() { printf '%-14s %-36s %s\n' "$P" "$1" "$2"; }
# snap -- every file and folder of the home and the sample project with its
# content hash; a checkout's .git but for its exclude list is git's own. The
# other project is not in it: the shared collector writes that project's own
# ledger folder, which is not this project's uninstall to remove.
snap() {
  ( cd "$T" && { find home sample -path '*/.git/*' -prune -o -type d -print | sed 's/$/\//'
      find home sample \( -path '*/.git/*' -prune \) -o \( -type f -o -type l \) -print | while IFS= read -r f; do printf '%s %s\n' "$(sha256sum < "$f" | cut -d' ' -f1)" "$f"; done
      printf '%s %s\n' "$(sha256sum < sample/.git/info/exclude | cut -d' ' -f1)" sample/.git/info/exclude; } | sort )
}
changed() { diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | sed -n 's/^[<>] //p' | sed -E 's/^[0-9a-f]{64} //' | sort -u; }
DATA='^(home/\.commandeck/|home/\.claude/hook-fire-log/|home/\.claude/rulings/|home/orca/|sample/\.claude/$|sample/\.claude/metrics/)'
# foreign -- the other tool's own parts, in the files the plugin merges into and beside them.
foreign() {
  jq -cS '[.hooks.PreToolUse[0], .hooks.SessionEnd]' "$HOME/.codex/hooks.json"
  grep -A2 -F 'pre_tool_use:0:0' "$HOME/.codex/config.toml"; grep '^service_tier' "$HOME/.codex/config.toml"
  jq -cS '[.statusLine, .enabledPlugins, .permissions.allow[0]]' "$HOME/.claude/settings.json"
  cat "$HOME/Library/LaunchAgents/com.other-tool.dashboard.plist"; grep -xF "$T/other" "$HOME/.commandeck/dashboard/projects"
}
# fire <tool> <tool_input json> -- one tool call through every PreToolUse hook registered for that tool.
# The call's id goes last, as Claude Code sends it: the fire log tells one call from the next by it.
fire() {
  local payload cmd
  CALL=$((${CALL:-0} + 1))
  payload=$(jq -cn --arg t "$1" --argjson i "$2" --arg d "$SAMPLE" --arg u "toolu_proof$CALL" \
    '{hook_event_name: "PreToolUse", session_id: "00000000-0000-4000-8000-000000000001", cwd: $d, tool_name: $t, tool_input: $i, tool_use_id: $u}')
  while IFS= read -r cmd; do
    ( cd "$SAMPLE" && printf '%s' "$payload" | CLAUDE_PLUGIN_ROOT=$PLUGIN CLAUDE_PROJECT_DIR=$SAMPLE bash -c "$cmd" >/dev/null 2>&1 )
  done < <(jq -r --arg t "$1" '.hooks.PreToolUse[] | select((.matcher // "") as $m | $m == "" or ($t | test("^(" + $m + ")$"))) | .hooks[].command' "$PLUGIN/hooks/hooks.json")
}

echo "commandeck $(jq -r .version "$PLUGIN/.claude-plugin/plugin.json") proof run, $(date -u +%Y-%m-%dT%H:%MZ), clean HOME, stubbed Orca and service manager"
for P in "${PROFILES[@]}"; do
  BEFORE=$(snap) OTHER=$(foreign)
  p "$SAMPLE" setup.sh --profile "$P" --test-command "npm test" >"$T/setup.out" 2>&1 || { row setup "FAILED: $(tail -1 "$T/setup.out")"; RC=1; continue; }
  SIZES=$(p "$SAMPLE" startup-size.sh 2>&1) || RC=1
  PROMPT=$(p "$SAMPLE" startup-size.sh --per-prompt 2>&1) || RC=1
  for seat in main builder worker chief-of-staff; do
    n=$(awk -F'\t' -v s="$seat" '$1 == s && $2 == "total" { print $3 }' <<<"$SIZES")
    [ "${n:-$LIMIT}" -lt "$LIMIT" ] || RC=1
    row "startup bytes, $seat" "${n:-unreadable} (limit $LIMIT)"
  done
  n=$(awk -F'\t' '$2 == "total" && $3 > m { m = $3 } END { print m + 0 }' <<<"$PROMPT")
  [ "$n" -lt "$LIMIT" ] || RC=1
  row "per-prompt bytes, largest seat" "$n (limit $LIMIT)"

  # The scripted steps of one unit: its worktree, four tool calls through the hooks (one of them refused, twice), one dashboard collect.
  WT=$HOME/orca/workspaces/sample/toy
  git -C "$SAMPLE" worktree add -q "$WT" -b toy && p "$WT" worktree-setup.sh "$WT" >/dev/null 2>&1 || { row "toy unit worktree" "FAILED"; RC=1; }
  fire Bash '{"command": "git status"}'; fire Read "$(jq -cn --arg f "$SAMPLE/sum.js" '{file_path: $f}')"
  fire Bash '{"command": "git push --force origin main"}'; fire Bash '{"command": "git push --force origin main"}'
  p "$SAMPLE" dashboard.sh >/dev/null 2>&1
  COST=$(p "$SAMPLE" hook-fire-log-summary.sh 1 2>/dev/null | jq -c '[.hooks[] | select(.fires > 0)]') || COST='[]'
  row "hook cost, all hooks" "$(jq -r '"\(length) hooks, \(map(.fires) | add // 0) fires, \(map(.blocks) | add // 0) blocks, \(map(.retried_identical) | add // 0) retried identical, slowest p95 \(map(.ms_body_p95 // 0) | max // 0) ms"' <<<"$COST")"
  while IFS= read -r line; do row "  hook" "$line"; done < <(jq -r '.[] | "\(.hook): \(.fires) fires, \(.blocks) blocks, \(.retried_identical) retried identical, p95 \(.ms_body_p95 // "-") ms"' <<<"$COST")
  [ "$(jq 'map(.fires) | add // 0' <<<"$COST")" -gt 0 ] || RC=1
  row "tokens and turns per role" "$LIVE bash scripts/unit-cost.sh <unit>; bash scripts/seat-tokens.sh"
  row "cache hit rate and write share" "$LIVE bash scripts/builder-cache-check.sh <worktree>; the dashboard's cache tiles"
  row "review passes to GO, findings" "$LIVE the unit's round files; bash scripts/builder-${P/claude-openai/codex}-pass.sh --verify <unit>"

  # Standard context: the project's answer alone moves the line to 150K.
  p "$SAMPLE" setup.sh --standard-context >/dev/null 2>&1 || RC=1
  printf '{"message":{"usage":{"cache_read_input_tokens":160000,"input_tokens":0}}}\n' > "$T/transcript.jsonl"
  OUT=$(cd "$SAMPLE" && printf '{"session_id":"proof-run","transcript_path":"%s"}' "$T/transcript.jsonl" | bash "$PLUGIN/hooks/context-line.sh" 2>&1)
  case $OUT in *"over the 150K line"*) row "standard context, 150K line" "fires at 160K" ;; *) row "standard context, 150K line" "DID NOT FIRE at 160K"; RC=1 ;; esac
  row "standard context, restart resumes" "$LIVE let the orchestrator cross 150K and watch the unit go on in the new pane"

  if [ "$(foreign)" = "$OTHER" ]; then row "coexistence while installed" "the other tool's hooks, trust, settings, job file and dashboard line are identical (a stand-in: not this machine's real home)"
  else row "coexistence while installed" "DIFFERS"; RC=1; fi
  git -C "$SAMPLE" worktree remove --force "$WT" && git -C "$SAMPLE" branch -q -D toy
  p "$SAMPLE" uninstall.sh >"$T/uninstall.out" 2>&1 || RC=1
  LEFT=$(changed "$BEFORE" "$(snap)")
  if [ -z "$(grep -vE "$DATA" <<<"$LEFT")" ]; then row "uninstall, data kept" "identical but for the kept data ($(grep -c . <<<"$LEFT") paths)"
  else row "uninstall, data kept" "DIFFERS: $(grep -vE "$DATA" <<<"$LEFT" | paste -sd' ' -)"; RC=1; fi
  p "$SAMPLE" uninstall.sh --delete-data >>"$T/uninstall.out" 2>&1 || RC=1
  LEFT=$(changed "$BEFORE" "$(snap)")
  if [ -z "$LEFT" ]; then row "uninstall, data deleted" "identical"; else row "uninstall, data deleted" "DIFFERS: $(paste -sd' ' - <<<"$LEFT")"; RC=1; fi
done
[ -z "$KEEP" ] || echo "kept: $T"
if [ "$RC" = 0 ]; then echo "proof run: every measured row holds"; else echo "proof run: a measured row FAILED, above"; fi
exit "$RC"
