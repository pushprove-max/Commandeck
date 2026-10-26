#!/usr/bin/env bash
# timeout: 240
# doctor.sh is what an owner runs when something seems off: each way Codex's one notify command can miss the plugin
# is named with its own line and the fix. Codex
# takes a single notify command, so an owner with another notify tool runs a wrapper that calls both; a wrapper
# that kept an old version's path went on calling a stale hook through several updates. The wrapper is the owner's
# file: it changes only on a yes. Each case calls the check the doctor prints, or the repoint setup runs, on a
# hand-written config.toml (no setup or uninstall run), so this runs in seconds. The option lines are in
# doctor-options.test.sh, the startup measure and the whole run in doctor-run.test.sh; the setup all three share is
# fixtures/doctor-setup.sh.
set -uo pipefail
. "$(dirname "$0")/fixtures/doctor-setup.sh"
# report -- the notify check doctor.sh prints, called by itself ("ok ..." or "warn ...").
report() { lib il_notify_report; }
check "the direct notify line passes, and says which case" 1 "$(report | grep -c "^ok codex notify: the line calls this plugin's hook$")"

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
check "a CLAUDE.md of 201 lines is flagged, with its length" "CLAUDE.md:201 over-200-lines 201 lines rule: docs/commands.md#rules-audit" "$(lint | grep over-200-lines)"
n_lines 300 > "$LR/.claude/rules/a.md"; { printf -- '---\npaths:\n  - "src/**"\n---\n'; n_lines 300; } > "$LR/.claude/rules/b.md"
check "a 300-line rules file is flagged unless it has paths:, which loads it only when a matching file is read" ".claude/rules/a.md:201 over-200-lines 300 lines rule: docs/commands.md#rules-audit" "$(lint | grep over-200-lines | grep -F .claude/rules/)"
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

# --- the prompt cache per role (issue 367): main's own file, the Builder's worktree, and the value the relay's pane really runs on ---
mkdir -p "$HOME/.claude" "$T/ws/Chief-of-Staff/.claude" "$T/ws/Builder-fix/.claude"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$HOME/.claude/settings.json"
echo '{"version": 1, "profile": "claude-openai", "mainCacheTtl": "1h", "workerCacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$PROJ/.claude/commandeck.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$PROJ/.claude/main-session.settings.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$T/ws/Builder-fix/.claude/settings.local.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$T/ws/Chief-of-Staff/.claude/settings.local.json"
echo '{"permissions":{"allow":[]}}' > "$PROJ/.claude/settings.local.json"
OUT=$(cache)
check "the relay's own 1h beats the user's 5m: one ok line for each role and no warn" '3:0' "$(grep -c '^ok prompt cache' <<<"$OUT"):$(grep -c '^warn' <<<"$OUT")"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$PROJ/.claude/settings.local.json"
OUT=$({ cache; shadow; })
check "a TTL in the main checkout's local file warns, naming the file, and the relay then runs 5m" '1:1' \
  "$(grep -c "^warn prompt cache: $PROJ/.claude/settings.local.json sets CLAUDE_CODE_PROMPT_CACHE_TTL=5m" <<<"$OUT"):$(grep -c '^warn prompt cache: the relay pane runs 5m, not the 1h you chose' <<<"$OUT")"
echo '{}' > "$PROJ/.claude/settings.local.json"; echo '{}' > "$T/ws/Chief-of-Staff/.claude/settings.local.json"
check "a relay file without the key runs on the user's 5m, and the doctor says so" 1 "$(cache | grep -c '^warn prompt cache: the relay pane runs 5m, not the 1h you chose')"
echo '{"version": 1, "profile": "claude-openai", "mainCacheTtl": "1h", "workerCacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "leave"}}' > "$PROJ/.claude/commandeck.json"
OUT=$(cache)
check "main's line names main-session.settings.json, and the claude --settings launch that reads it" '1:0' \
  "$(grep -c "^ok prompt cache: main 1h (.claude/main-session.settings.json; read only by a main started with claude --settings $PROJ/.claude/main-session.settings.json)$" <<<"$OUT"):$(grep -c '^warn' <<<"$OUT")"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$PROJ/.claude/main-session.settings.json"
check "main's line warns, naming the file, when that file's TTL is not main's answer" 1 "$(cache | grep -c "^warn prompt cache: main's $PROJ/.claude/main-session.settings.json holds 5m CLAUDE_CODE_PROMPT_CACHE_TTL, not the 1h you chose")"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$PROJ/.claude/main-session.settings.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$HOME/.claude/settings.json"; echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$PROJ/.claude/settings.json"
check "a user-level or project-level TTL does not change main's line" '1:0' "$(cache | grep -c '^ok prompt cache: main 1h'):$(cache | grep -c '^warn')"
rm -f "$PROJ/.claude/settings.json"
# A subagentPromptCacheTtl is read from the project's files, the local one last.
echo '{"subagentPromptCacheTtl":"1h"}' > "$PROJ/.claude/settings.local.json"
check "a subagentPromptCacheTtl in main's local file that is not the worker answer warns, naming the file and the key" 1 \
  "$(cache | grep -c "^warn prompt cache: subagents run 1h, not the 5m you chose: subagentPromptCacheTtl is 1h in $PROJ/.claude/settings.local.json")"
echo '{"subagentPromptCacheTtl":"5m"}' > "$PROJ/.claude/settings.local.json"
check "a local subagentPromptCacheTtl equal to the worker answer is ok" '3:0' "$(cache | grep -c '^ok prompt cache'):$(cache | grep -c '^warn')"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$T/ws/Builder-fix/.claude/settings.local.json"
check "a Builder worktree whose TTL is not the worker answer warns, naming its file" 1 "$(cache | grep -c "^warn prompt cache: workers run 1h, not the 5m you chose: CLAUDE_CODE_PROMPT_CACHE_TTL is 1h in $T/ws/Builder-fix/.claude/settings.local.json")"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$T/ws/Builder-fix/.claude/settings.local.json"
echo '{}' > "$PROJ/.claude/settings.local.json"
echo '{"version": 1, "profile": "claude-openai", "mainCacheTtl": "leave", "workerCacheTtl": "leave", "chiefOfStaff": {"name": "r", "cacheTtl": "leave"}}' > "$PROJ/.claude/commandeck.json"
check "with every answer Leave as is the doctor prints one leave line per role and no warn" '3:0' "$(cache | grep -cE '^ok prompt cache: (main|workers|relay) leave \(setup sets none\)$'):$(cache | grep -c '^warn')"
rm -f "$HOME/.claude/settings.json" "$PROJ/.claude/settings.local.json" "$PROJ/.claude/main-session.settings.json"; rm -rf "$T/ws/Builder-fix"

# --- a key in the main checkout's local file shadows the per-worktree one (Claude Code applies it over the worktree's own) ---
echo '{"version": 1, "profile": "claude-openai", "cacheTtl": "leave", "chiefOfStaff": {"name": "r", "cacheTtl": "leave"}}' > "$PROJ/.claude/commandeck.json"
echo '{"autoMemoryEnabled":true}' > "$PROJ/.claude/settings.local.json"
OUT=$(shadow)
check "autoMemoryEnabled true in main's local file warns, naming the key and the file" "1:0" \
  "$(grep -c "^warn settings: $PROJ/.claude/settings.local.json sets autoMemoryEnabled=true" <<<"$OUT"):$(grep -c '^ok' <<<"$OUT")"
echo '{"autoMemoryEnabled":false,"someOwnerKey":"x"}' > "$PROJ/.claude/settings.local.json"
OUT=$(shadow)
check "the same value, and a key setup never writes, do not warn" "1:0" "$(grep -c '^ok settings' <<<"$OUT"):$(grep -c '^warn' <<<"$OUT")"
echo '{"skillOverrides":{"anthropic-skills:chrome-browser":"on"},"enabledPlugins":{"stripe@claude-plugins-official":true}}' > "$PROJ/.claude/settings.local.json"
check "a nested leaf is named by its path, one warning for each" "1:1" \
  "$(shadow | grep -c 'sets skillOverrides.anthropic-skills:chrome-browser=on'):$(shadow | grep -c 'sets enabledPlugins.stripe@claude-plugins-official=true')"
check "no worktree is left behind by the check" 1 "$(git -C "$PROJ" worktree list | wc -l | tr -d ' ')"
# A probe that cannot run is no clean bill: the owner's key may still shadow what it would have shown.
echo '{"autoMemoryEnabled":true}' > "$PROJ/.claude/settings.local.json"
RG=$(command -v git); mkdir -p "$T/nogit" "$T/emptygit"
printf '#!/usr/bin/env bash\n[[ "$*" == *"worktree add"* ]] && exit 1\nexec %s "$@"\n' "$RG" > "$T/nogit/git"
printf '#!/usr/bin/env bash\n[[ "$*" == *"worktree add"* ]] && exit 0\nexec %s "$@"\n' "$RG" > "$T/emptygit/git"
chmod +x "$T/nogit/git" "$T/emptygit/git"
OUT=$(PATH="$T/nogit:$PATH" shadow)
check "a probe worktree that cannot be made is a warning, never an ok" '0:1' "$(grep -c '^ok settings' <<<"$OUT"):$(grep -c '^warn settings' <<<"$OUT")"
OUT=$(PATH="$T/emptygit:$PATH" shadow)
check "a probe whose profile cannot be generated is a warning, never an ok" '0:1' "$(grep -c '^ok settings' <<<"$OUT"):$(grep -c '^warn settings' <<<"$OUT")"
# The doctor removes its own probes and prunes nothing else: another worktree whose directory is away keeps its metadata.
git -C "$PROJ" worktree add -q "$T/away" && mv "$T/away" "$T/away.gone"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gc.worktreePruneExpire GIT_CONFIG_VALUE_0=now shadow >/dev/null
check "an offline worktree's metadata survives the check" 1 "$(git -C "$PROJ" worktree list | grep -c "$T/away")"
mv "$T/away.gone" "$T/away" && git -C "$PROJ" worktree remove --force "$T/away"
rm -f "$PROJ/.claude/settings.local.json"
check "no local file: nothing shadowed" 1 "$(shadow | grep -c '^ok settings')"

# Issue 315: a hook another tool rewrote drops out of trust and opens every Codex pane on the review menu, so the
# trust line covers every entry in the Codex home, not the plugin's alone, and names the modified one.
: > "$CFG"; HJ=$HOME/.codex/hooks.json
echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/opt/other/start.sh"}]}]}}' > "$HJ"
python3 "$REAL/scripts/codex-hook-trust.py" --all "$HOME/.codex" >/dev/null
check "trust line: a trusted third-party hook is ok" "ok codex trust: every hook in $HOME/.codex is trusted" "$(lib il_codex_trust_report)"
echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/opt/other/start-v2.sh"}]}]}}' > "$HJ"
TL=$(lib il_codex_trust_report)
check "trust line: a modified non-plugin hook is flagged, named, and the fix says how to turn trust-all on" "1:1:1" \
  "$(grep -c '^bad codex trust: 1 hook(s)' <<<"$TL"):$(grep -c 'start-v2.sh) is modified' <<<"$TL"):$(grep -c -- '--trust-all-hooks on' <<<"$TL")"
echo '{"version": 1, "profile": "claude-openai", "trustAllHooks": true}' > "$PROJ/.claude/commandeck.json"
check "with trust-all on the fix says the next launch re-trusts" 1 "$(lib il_codex_trust_report | grep -c 'each Codex launch trusts them again')"

# Issue 316: a seat type that cannot read GitHub is a FAIL line of its own, naming its agent, sandbox mode and roles.
# The stubs: gh fails only under the codex stub's sandbox, as a read-only Codex seat without network does.
git -C "$PROJ" remote add origin https://github.com/o/proj.git
cat > "$BIN/gh" <<STUB
#!/usr/bin/env bash
case "\$*" in "auth status"*|"auth token"*) exit 0 ;; esac
[ -z "\${GH_SANDBOXED:-}" ] || [ ! -e "$T/gh-fail-sandbox" ] || { cat "$T/gh-fail-sandbox" >&2; exit 1; }
echo '{"nameWithOwner":"o/proj"}'
STUB
cat > "$BIN/codex" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = sandbox ]; then shift; while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done; shift; GH_SANDBOXED=1 exec "$@"; fi
exit 0
STUB
chmod +x "$BIN/gh" "$BIN/codex"
printf '{"models": [{"slug": "gpt-9.1-sol"}, {"slug": "gpt-9.1-astra"}]}\n' > "$HOME/.codex/models_cache.json"
echo "error connecting to api.github.com" > "$T/gh-fail-sandbox"
OUT=$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1); RC=$?
check "the doctor reports a seat type that cannot reach GitHub, with its sandbox and the reason, and exits 1" "1:1:1" \
  "$(grep -c '^FAIL github read: codex read-only + network (plan-judge-sol): no network in the sandbox: error connecting to api.github.com' <<<"$OUT"):$(grep -c '^ok   github read: claude, no sandbox (orchestrator, plan-author, plan-judge-fable, builder, fixer)$' <<<"$OUT"):$RC"
rm -f "$T/gh-fail-sandbox"
OUT=$(in_proj timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1)
check "with GitHub reachable from every seat the doctor says so for each agent and mode" "1:1" \
  "$(grep -c '^ok   github read: codex read-only + network (plan-judge-sol)$' <<<"$OUT"):$(grep -c '^ok   github read: claude, no sandbox' <<<"$OUT")"
# Same agent and sandbox, other credentials: a second Codex seat's routed token is its own, so a read as Sol proves nothing for it.
sed -i.bak '2a\
[ "${GH_TOKEN:-}" != invalid ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }' "$BIN/gh"; rm -f "$BIN/gh.bak"
jq '.roles["plan-judge-fable"] = .roles["plan-judge-sol"] + {shellEnv: {GH_TOKEN: "invalid"}}' "$REAL/config/routing.json" > "$T/routing.json"
OUT=$(in_proj env COMMANDECK_ROUTING="$T/routing.json" timeout 60 bash "$REAL/scripts/doctor.sh" 2>&1); RC=$?
check "a seat whose own environment cannot read GitHub fails alone, though another seat of its agent and mode reads" "1:1:1" \
  "$(grep -c '^ok   github read: codex read-only + network (plan-judge-sol)$' <<<"$OUT"):$(grep -c '^FAIL github read: codex read-only + network (plan-judge-fable): no credentials visible in the sandbox: HTTP 401: Bad credentials' <<<"$OUT"):$RC"

# Issue 334: an Orca launch overwrote a profile's settings file and the session-start repair put setup's parts back:
# the doctor says so, naming the file, when, and what.
mkdir -p "$HOME/.commandeck/install"
jq -n --arg f "$T/profile/settings.json" '{version: 1, entries: {($f): {kind: "merge", repaired: {at: "2026-10-24T09:00:00Z", keys: ["statusLine", "options"]}}}}' > "$HOME/.commandeck/install/_machine.json"
check "after a session-start repair the doctor names the profile file, the repair time and statusLine, and says a hand edit is undone and the command that revokes" \
  "ok profile settings: $T/profile/settings.json was overwritten at a launch and repaired at 2026-10-24T09:00:00Z (statusLine, options); a hand edit of setup's status line, options, auto-mode lines or permission rules is undone at the next launch: remove one, or keep your own value, with /commandeck:revoke" "$(lib il_profile_repair_report)"
# The owner's choices made with /commandeck:revoke are named, repaired or not: each of the four kinds.
jq -n --arg f "$T/profile/settings.json" '{version: 1, entries: {($f): {kind: "merge", revoked: {added: ["Bash(a:*)", "Bash(b:*)"],
  autoMode: ["line one"], statusLine: {keep: null}, options: {"p@m": {k: {keep: "third"}, j: {keep: null}}}}}}}' > "$HOME/.commandeck/install/_machine.json"
check "a profile file with the owner's choices has a line naming each" \
  "ok profile settings: $T/profile/settings.json: chosen with /commandeck:revoke, a launch does not put setup's value back: Bash(a:*), Bash(b:*), 1 auto-mode line, the status line (removed), option p@m k (kept: \"third\"), option p@m j (removed)" "$(lib il_profile_repair_report)"
rm -f "$HOME/.commandeck/install/_machine.json"
check "a profile file never repaired has no line" "" "$(lib il_profile_repair_report)"

# Issue 367, after the timed cases: one line per role, each naming where its TTL is written.
mkdir -p "$T/ws/Chief-of-Staff/.claude" "$T/ws/Builder-fix/.claude"
echo '{"version": 1, "profile": "claude-openai", "mainCacheTtl": "1h", "workerCacheTtl": "5m", "chiefOfStaff": {"name": "r", "cacheTtl": "1h"}}' > "$PROJ/.claude/commandeck.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$PROJ/.claude/main-session.settings.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"5m"}}' > "$T/ws/Builder-fix/.claude/settings.local.json"
echo '{"env":{"CLAUDE_CODE_PROMPT_CACHE_TTL":"1h"}}' > "$T/ws/Chief-of-Staff/.claude/settings.local.json"
OUT=$(cache)
check "the doctor names each role's prompt cache and where it is written" "1:1:1:0" \
  "$(grep -c '^ok prompt cache: main 1h (.claude/main-session.settings.json;' <<<"$OUT"):$(grep -c "^ok prompt cache: workers 5m (each worktree's .claude/settings.local.json; subagents: subagentPromptCacheTtl in .claude/settings.json)" <<<"$OUT"):$(grep -c '^ok prompt cache: relay 1h ' <<<"$OUT"):$(grep -c '^warn' <<<"$OUT")"
rm -rf "$T/ws/Builder-fix" "$PROJ/.claude/main-session.settings.json"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
