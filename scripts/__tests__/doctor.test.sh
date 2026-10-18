#!/usr/bin/env bash
# doctor.sh is what an owner runs when something seems off: each way Codex's one notify command can miss the plugin
# is named with its own line and the fix, and its startup measure takes nothing of the owner's or main's. Codex
# takes a single notify command, so an owner with another notify tool runs a wrapper that calls both; a wrapper
# that kept an old version's path went on calling a stale hook through several updates. The wrapper is the owner's
# file: it changes only on a yes. Each case calls the check the doctor prints, or the repoint setup runs, on a
# hand-written config.toml (no setup or uninstall run), so this runs in seconds.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd -P)   # -P: as install-lib.sh's IL_ROOT, or a checkout under a link fails the first check
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PROJ=$T/proj BIN=$T/bin CFG=$T/home/.codex/config.toml LINK=$T/home/.commandeck/plugin/hooks/codex-notify.sh
mkdir -p "$HOME/.codex" "$HOME/.commandeck" "$BIN" && ln -s "$REAL" "$HOME/.commandeck/plugin"
git init -q -b main "$PROJ" && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
mkdir -p "$PROJ/.claude" && echo '{"version": 1, "profile": "claude-openai"}' > "$PROJ/.claude/commandeck.json"
printf '#!/usr/bin/env bash\necho "{\\"ok\\":true,\\"result\\":{}}"\n' > "$BIN/orca-ide"; chmod +x "$BIN/orca-ide"
printf 'notify = ["%s/hooks/codex-notify.sh"]\nmodel = "other"\n' "$REAL" > "$CFG"
in_proj() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux "$@"); }
# lib <shell> [args] -- the shell runs with install-lib.sh loaded and the args as "$1"...
lib() { in_proj bash -c '. "$0/paths.sh" && . "$0/install-lib.sh" && c=$1 && shift && eval "$c"' "$REAL/scripts" "$@" 2>&1; }
# report -- the notify check doctor.sh prints, called by itself ("ok ..." or "warn ...").
report() { lib il_notify_report; }
check "the direct notify line passes, and says which case" 1 "$(report | grep -c "^ok codex notify: the line calls this plugin's hook$")"

# --- the doctor's startup measure takes nothing of the owner's or main's ---
# A message queued for main while it is down is main's to read; an open decision is the owner's to answer.
QD=$(in_proj bash -c '. "$0" && echo "$PP_SCRATCH/queue"' "$REAL/scripts/paths.sh")
mkdir -p "$QD" && echo '{"at":"x","type":"status","subject":"answer","body":"stop this build"}' > "$QD/main.jsonl"
in_proj bash "$REAL/scripts/decision.sh" add doctor-test 'May this build ship?' no chat >/dev/null 2>&1
in_proj bash "$REAL/scripts/startup-size.sh" >/dev/null 2>&1; in_proj bash "$REAL/scripts/startup-size.sh" --per-prompt >/dev/null 2>&1
check "the doctor's startup measure leaves the owner's open decision open" null \
  "$(in_proj bash "$REAL/scripts/decision.sh" list 2>/dev/null | jq '.[] | select(.id == "doctor-test") | .answeredAt')"
check "and main's queued messages where they are" 1 "$(grep -c 'stop this build' "$QD/main.jsonl" 2>/dev/null)"

# notify <script body> -- Codex's notify is the owner's wrapper with this body; the doctor's notify line.
notify() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$T/wrap.sh"; chmod +x "$T/wrap.sh"
  { printf 'notify = ["bash", "%s"]\n' "$T/wrap.sh"; grep -v '^notify = ' "$CFG"; } > "$T/cfg" && mv "$T/cfg" "$CFG"
  report
}
check "a wrapper calling the current hook passes" 1 "$(notify "/opt/tracker \"\$@\"; \"$REAL/hooks/codex-notify.sh\" \"\$@\"" | grep -c "^ok codex notify: through the wrapper $T/wrap.sh")"
check "a wrapper calling it by the stable link passes" 1 "$(notify "\"$LINK\" \"\$@\"" | grep -c '^ok codex notify: through the wrapper')"
OUT=$(notify '/opt/tracker "$@"')
check "a wrapper with no hook in it warns so, with the line to add" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh does not call the plugin's hook.*add this line to it: \"$LINK\" \"\$@\"" <<<"$OUT")"
OLD=$HOME/.claude/plugins/cache/commandeck/commandeck/0.1.0/hooks/codex-notify.sh
mkdir -p "${OLD%/*}" && touch "$OLD"
OUT=$(notify "\"$OLD\" \"\$@\"")
check "a wrapper calling an older version warns so, naming it and the fix" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh calls an older plugin's hook ($OLD).*update.sh, which points it at $LINK" <<<"$OUT")"
OUT=$(notify "# \"$LINK\" \"\$@\"
exit 0")
check "a hook named only in a comment is no call: it warns" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh does not call the plugin's hook" <<<"$OUT")"
OUT=$(notify "exit 0 # \"$LINK\" \"\$@\"")
check "a hook named only in an inline comment is no call: it warns" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh does not call the plugin's hook" <<<"$OUT")"
check "a wrapper that names the hook is reported as read, not run" 1 "$(notify "\"$LINK\" \"\$@\"" | grep -c 'read as text, not run')"
SP="$HOME/My Plugins/0.1.0/hooks/codex-notify.sh"; mkdir -p "${SP%/*}" && touch "$SP"
OUT=$(notify "\"$SP\" \"\$@\"")
check "an older hook at a quoted path with a space is named whole" 1 "$(grep -cF "calls an older plugin's hook ($SP)" <<<"$OUT")"
lib 'il_notify_repoint "$1" yes' "$T/repoint-mf.json" >/dev/null
check "and a yes replaces it whole" "\"$LINK\" \"\$@\"" "$(sed -n 2p "$T/wrap.sh")"

# --- the wrapper is the owner's file: setup asks before it changes it, and changes it only on yes ---
notify "\"$OLD\" \"\$@\"" >/dev/null; WAS=$(cat "$T/wrap.sh")
OUT=$(lib 'il_notify_repoint "$1"' "$T/mf.json")
check "with no answer about the wrapper it is left as it was" "$WAS" "$(cat "$T/wrap.sh")"
check "and the question shows the old line and the new one" 1 "$(grep -cF "codex notify: ASK: the wrapper $T/wrap.sh calls an older plugin's hook. Old line: \"$OLD\" \"\$@\" New line: \"$LINK\" \"\$@\" Change it: --notify-wrapper yes; leave it: --notify-wrapper no" <<<"$OUT")"
OUT=$(lib 'il_notify_repoint "$1" no' "$T/mf.json")
check "a no leaves the wrapper as it was" "$WAS" "$(cat "$T/wrap.sh")"
check "and says what the doctor will warn" 1 "$(grep -c "^codex notify: the wrapper $T/wrap.sh was left as it is; the doctor will warn: codex notify: the wrapper .* calls an older plugin's hook" <<<"$OUT")"
OUT=$(lib 'il_notify_repoint "$1" yes' "$T/mf.json")
check "a yes points the wrapper at the stable link, and says so" "1:0:1" "$(grep -c "\"$LINK\" \"\$@\"" "$T/wrap.sh"):$(grep -c '0\.1\.0' "$T/wrap.sh"):$(grep -c "^codex notify: $T/wrap.sh now calls $LINK" <<<"$OUT")"
check "and leaves the owner's notify line as it was" 1 "$(grep -c "^notify = \[\"bash\", \"$T/wrap.sh\"\]$" "$CFG")"
check "the doctor then passes it" 1 "$(report | grep -c '^ok codex notify: through the wrapper')"
# Uninstall leaves the wrapper to its owner (uninstall.sh says which line to take out); the manifest keeps what it was.
check "the yes recorded the wrapper as it was, in the manifest it was given, its bytes kept" "$WAS" \
  "$(cat "$HOME/.commandeck/install/blobs/$(jq -r --arg w "$T/wrap.sh" '.entries[$w].prior | ltrimstr("sha256:")' "$T/mf.json" 2>/dev/null)" 2>/dev/null)"

grep -v '^notify = ' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"
check "no notify line at all warns so, with the line to add" 1 "$(report | grep -c "^warn codex notify: .* has no notify line.*notify = \[\"$LINK\"\]")"

# --- the auto-mode lines: a list that replaced the built-in rules, and a project file the classifier ignores ---
AM=$HOME/.claude/settings.json; mkdir -p "$HOME/.claude"
am() { lib il_auto_mode_report; }
rm -f "$AM" "$PROJ/.claude/settings.json" "$PROJ/.claude/settings.local.json"
check "no autoMode anywhere: one ok line" '1:0' "$(am | grep -c '^ok auto mode:'):$(am | grep -c '^warn')"
echo '{"autoMode":{"environment":["$defaults","mine"],"allow":["mine"]}}' > "$AM"
OUT=$(am)
check "a list without \"\$defaults\" warns for that list only, and says where to look" '1:1:0' \
  "$(grep -c '^warn auto mode: the allow list in .* has no "\$defaults"' <<<"$OUT"):$(grep -c 'claude auto-mode critique' <<<"$OUT"):$(grep -c 'the environment list' <<<"$OUT")"
echo '{"autoMode":{"environment":["$defaults"]}}' > "$AM"; echo '{"autoMode":{"allow":["x"]}}' > "$PROJ/.claude/settings.local.json"
OUT=$(am)
check "autoMode in a project file warns that the classifier ignores it, and where to move it" 1 "$(grep -c "^warn auto mode: .*settings.local.json has autoMode, which the classifier ignores there; move it to $AM" <<<"$OUT")"
rm -f "$AM" "$PROJ/.claude/settings.local.json"

# --- instruction size: past 200 lines a file loads in every session and is followed less well; MEMORY.md past 200 lines or 25 KB is cut off ---
LR=$T/lint; mkdir -p "$LR/.claude/rules" "$T/mem"; git init -q -b main "$LR"
lint() { python3 "$REAL/scripts/instruction-lint.py" --repo "$LR" --memory-dir "$T/mem" --global "$T/no-global.md" 2>&1; }
n_lines() { for i in $(seq "$1"); do echo "line $i"; done; }
n_lines 200 > "$LR/CLAUDE.md"
check "a CLAUDE.md of 200 lines is not flagged" 0 "$(lint | grep -c over-200-lines)"
n_lines 201 > "$LR/CLAUDE.md"
check "a CLAUDE.md of 201 lines is flagged, with its length" "CLAUDE.md:201 over-200-lines 201 lines" "$(lint | grep over-200-lines)"
n_lines 300 > "$LR/.claude/rules/a.md"; { printf -- '---\npaths:\n  - "src/**"\n---\n'; n_lines 300; } > "$LR/.claude/rules/b.md"
check "a 300-line rules file is flagged unless it has paths:, which loads it only when a matching file is read" ".claude/rules/a.md:201 over-200-lines 300 lines" "$(lint | grep over-200-lines | grep rules)"
n_lines 300 > "$LR/AGENT_STARTUP.md"
check "AGENT_STARTUP.md is left to startup-size.sh" 0 "$(lint | grep -c AGENT_STARTUP)"
n_lines 201 > "$T/global.md"
check "the global CLAUDE.md counts too" 1 "$(python3 "$REAL/scripts/instruction-lint.py" --repo "$LR" --memory-dir "$T/mem" --global "$T/global.md" 2>&1 | grep -c "global.md:201 over-200-lines")"
n_lines 200 > "$T/mem/MEMORY.md"
check "a MEMORY.md of 200 lines is not flagged" 0 "$(lint | grep -c memory-over-limit)"
n_lines 201 > "$T/mem/MEMORY.md"
check "a MEMORY.md of 201 lines is flagged" 1 "$(lint | grep -c memory-over-limit)"
head -c 26000 /dev/zero | tr '\0' 'x' | fold -w 2600 > "$T/mem/MEMORY.md"
check "a 10-line MEMORY.md of 26 KB is flagged: what is past 25 KB is not loaded" 1 "$(lint | grep -c 'memory-over-limit 10 lines')"
rm -rf "$LR" "$T/mem" "$T/global.md"

# --- tool search: off loads every tool of every MCP server on every turn; the rule is the docs', row by row ---
echo '{"mcpServers":{"a":{},"b":{}}}' > "$PROJ/.mcp.json"; rm -f "$HOME/.claude/settings.json" "$HOME/.claude.json"
ts() { (unset ENABLE_TOOL_SEARCH CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS ANTHROPIC_BASE_URL; export "$@"; lib il_tool_search_report); }
check "nothing set: on, with the server count" 1 "$(ts X=1 | grep -c '^ok tool search: on, so 2 MCP servers')"
check "ENABLE_TOOL_SEARCH=false warns, naming it and the count" 1 "$(ts ENABLE_TOOL_SEARCH=false | grep -c '^warn tool search: tool search is off (ENABLE_TOOL_SEARCH=false), so every tool of 2 MCP servers loads')"
check "a proxy with the variable unset warns" 1 "$(ts ANTHROPIC_BASE_URL=https://proxy.example:8443/v1 | grep -c '^warn tool search: tool search is off (ANTHROPIC_BASE_URL is proxy.example,')"
check "the same proxy with ENABLE_TOOL_SEARCH=true is ok" 1 "$(ts ANTHROPIC_BASE_URL=https://proxy.example ENABLE_TOOL_SEARCH=true | grep -c '^ok tool search')"
check "ANTHROPIC_BASE_URL on api.anthropic.com is ok" 1 "$(ts ANTHROPIC_BASE_URL=https://api.anthropic.com | grep -c '^ok tool search')"
check "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS beats ENABLE_TOOL_SEARCH=true" 1 "$(ts CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 ENABLE_TOOL_SEARCH=true | grep -c '^warn tool search: tool search is off (CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS is set)')"
echo '{"env":{"ENABLE_TOOL_SEARCH":"false"}}' > "$HOME/.claude/settings.json"
check "a value in user settings counts when the environment has none, and the environment wins over it" '1:1' \
  "$(ts X=1 | grep -c '^warn tool search: tool search is off (ENABLE_TOOL_SEARCH=false)'):$(ts ENABLE_TOOL_SEARCH=true | grep -c '^ok tool search')"
rm -f "$PROJ/.mcp.json" "$HOME/.claude/settings.json"

# --- the relay's prompt cache: the value its pane really runs on, not only the bytes in its own file ---
mkdir -p "$HOME/.claude" "$T/ws/Chief-of-Staff/.claude"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude-openai", "cacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$PROJ/.claude/commandeck.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$T/ws/Chief-of-Staff/.claude/settings.local.json"
echo '{"permissions":{"allow":[]}}' > "$PROJ/.claude/settings.local.json"
cache() { COMMANDECK_WORKSPACES=$T/ws lib il_cache_ttl_report; }
OUT=$(cache)
check "the relay's own 1h beats the user's 5m: one ok line and no warn" '1:0' "$(grep -c '^ok prompt cache' <<<"$OUT"):$(grep -c '^warn' <<<"$OUT")"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$PROJ/.claude/settings.local.json"
OUT=$(cache)
check "a TTL in the main checkout's local file warns, naming the file, and the relay then runs 5m" '1:1' \
  "$(grep -c "^warn prompt cache: $PROJ/.claude/settings.local.json sets CLAUDE_CODE_PROMPT_CACHE_TTL=5m" <<<"$OUT"):$(grep -c '^warn prompt cache: the relay pane runs 5m, not the 1h you chose' <<<"$OUT")"
echo '{}' > "$PROJ/.claude/settings.local.json"; echo '{}' > "$T/ws/Chief-of-Staff/.claude/settings.local.json"
check "a relay file without the key runs on the user's 5m, and the doctor says so" 1 "$(cache | grep -c '^warn prompt cache: the relay pane runs 5m, not the 1h you chose')"
echo '{"version": 1, "profile": "claude-openai", "cacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "leave"}}' > "$PROJ/.claude/commandeck.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$HOME/.claude/settings.json"
check "a user-level 1h beats the 5m setup wrote for main, and the doctor says so" '1:0' "$(cache | grep -c '^warn prompt cache: main runs 1h, not the 5m you chose'):$(cache | grep -c '^ok')"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$PROJ/.claude/settings.json"; echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$HOME/.claude/settings.json"
check "a project-level 1h beats the user's 5m for main" 1 "$(cache | grep -c '^warn prompt cache: main runs 1h, not the 5m you chose')"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$PROJ/.claude/settings.json"
check "a 5m in the user and project files is ok" '1:0' "$(cache | grep -c '^ok prompt cache'):$(cache | grep -c '^warn')"
# No env key anywhere: main runs on the promptCacheTtl settings, and the main checkout's local file is read after the
# project's, where setup wrote its 5m, so a key there wins.
echo '{}' > "$HOME/.claude/settings.json"; echo '{"promptCacheTtl":"5m","subagentPromptCacheTtl":"5m"}' > "$PROJ/.claude/settings.json"
echo '{"promptCacheTtl":"1h"}' > "$PROJ/.claude/settings.local.json"
OUT=$(cache)
check "a promptCacheTtl in main's local file beats the project's 5m: the doctor names the file and the key" '1:0' \
  "$(grep -c "^warn prompt cache: main runs 1h, not the 5m you chose: promptCacheTtl is 1h in $PROJ/.claude/settings.local.json" <<<"$OUT"):$(grep -c '^ok' <<<"$OUT")"
echo '{"subagentPromptCacheTtl":"1h"}' > "$PROJ/.claude/settings.local.json"
check "and so does a subagentPromptCacheTtl there" 1 "$(cache | grep -c '^warn prompt cache: main runs 1h, not the 5m you chose: subagentPromptCacheTtl is 1h in ')"
echo '{"promptCacheTtl":"5m","subagentPromptCacheTtl":"5m"}' > "$PROJ/.claude/settings.local.json"
check "a local 5m is ok" '1:0' "$(cache | grep -c '^ok prompt cache'):$(cache | grep -c '^warn')"
echo '{}' > "$PROJ/.claude/settings.local.json"
rm -f "$PROJ/.claude/settings.json"
echo '{"version": 1, "profile": "claude-openai", "cacheTtl": "leave", "chiefOfStaff": {"name": "r", "cacheTtl": "leave"}}' > "$PROJ/.claude/commandeck.json"
check "with both answers Leave as is the doctor has nothing to check" '1:0' "$(cache | grep -c '^ok prompt cache: setup sets none'):$(cache | grep -c '^warn')"
rm -f "$HOME/.claude/settings.json" "$PROJ/.claude/settings.local.json"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
