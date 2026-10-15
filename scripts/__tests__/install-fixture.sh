#!/usr/bin/env bash
# install-fixture.sh -- sourced by setup.test.sh, setup-requirements.test.sh and
# uninstall-snapshot.test.sh. One machine in a temp folder: a HOME that another tool has
# already written to (its own Codex hook and trust entry, its own permission
# list, status line, background job and instruction file), a project, and the
# plugin copied OUTSIDE any checkout, as Claude Code's plugin cache holds it.
# Nothing here touches the real HOME: COMMANDECK_HOST_OS=Linux and a stub
# systemctl stand in for the service manager.
SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
done_tests() { echo "$PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]; }

export HOME=$T/home
BIN=$T/bin PLUGIN=$T/plugin PROJ=$T/proj
mkdir -p "$HOME/.codex" "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/scripts" "$HOME/Library/LaunchAgents" "$BIN" "$PLUGIN"
for d in hooks scripts config templates dashboard skills .claude-plugin CHANGELOG.md; do cp -R "$SOURCE/$d" "$PLUGIN/"; done
rm -rf "$PLUGIN/hooks/__tests__" "$PLUGIN/scripts/__tests__"

# --- stubs ---
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
[ ! -e "$T/orca-down" ] || exit 1
case "\$*" in
  "worktree ps --json") echo '{"result":{"worktrees":[]}}' ;;
  "terminal list --json") echo '{"result":{"terminals":[]}}' ;;
  *) echo '{"ok":true,"result":{}}' ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "$*" >> %q\ncase "$*" in *is-active*) [ -e %q ] && echo active || { echo inactive; exit 3; } ;; esac\n' \
  "$T/systemctl" "$T/jobs-up" > "$BIN/systemctl"
printf '#!/usr/bin/env bash\n[ "$*" = "login status" ] && [ ! -e %q ]\n' "$T/signed-out" > "$BIN/codex"
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/claude"
# gh is never the real one: signed in, and a project's issues are the file named after the folder gh runs in, else gh fails.
printf '#!/usr/bin/env bash\n[ "$*" != "auth token" ] || exit 0\ncat %q/"${PWD##*/}".json 2>/dev/null\n' "$T/gh" > "$BIN/gh"
chmod +x "$BIN"/*
touch "$T/jobs-up"

# --- what was on the machine before the plugin ---
FAMILY=$(jq -r '.roles["codex-reviewer"].model' "$SOURCE/config/routing.json")
printf '{"models":[{"slug":"gpt-9.1-%s"}]}\n' "$FAMILY" > "$HOME/.codex/models_cache.json"
echo '// companion' > "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/scripts/codex-companion.mjs"
# The pass has no prompt but the installed Codex plugin's, and its preflight reads it.
mkdir -p "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/prompts"
printf '{{TARGET_LABEL}} {{USER_FOCUS}}\nPrefer one strong finding over several weak ones.\n<structured_output_contract>\njson\n</structured_output_contract>\n{{REVIEW_COLLECTION_GUIDANCE}}\n{{REVIEW_INPUT}}\n' \
  > "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0/prompts/adversarial-review.md"
cat > "$HOME/.codex/hooks.json" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "/opt/other-tool/hook.sh", "timeout": 5}]}],
           "SessionEnd": [{"hooks": [{"type": "command", "command": "/opt/other-tool/end.sh"}]}]}}
EOF
cat > "$HOME/.codex/config.toml" <<EOF
service_tier = "fast"
model = "other"

[projects."$T/other-project"]
trust_level = "trusted"

[hooks.state."$HOME/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:0000"
enabled = false
EOF
printf '{\n  "statusLine": {"type": "command", "command": "~/.claude/status-lines/other.sh"},\n  "permissions": {"allow": ["Bash(ls:*)"]},\n  "enabledPlugins": {"other@market": true}\n}\n' > "$HOME/.claude/settings.json"
echo '<plist>other tool</plist>' > "$HOME/Library/LaunchAgents/com.other-tool.dashboard.plist"

# project <dir> -- a checkout with its own settings, instruction file and exclude list.
project() {
  git init -q -b main "$1" && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
  mkdir -p "$1/.claude"
  printf '{"permissions": {"allow": ["Bash(make:*)"]}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "./own-stop.sh"}]}]}}\n' > "$1/.claude/settings.json"
  printf '# House rules\n\nKeep it short.\n' > "$1/AGENTS.md"
  printf '# local excludes\n*.swp\n' > "$1/.git/info/exclude"
}
project "$PROJ"

# run <project dir> <script> [args] -- a plugin script, run in the project as a session would run it.
run() {
  local d=$1 s=$2; shift 2
  ( cd "$d" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u CODEX_HOME -u COMMANDECK_DASHBOARD_DIR \
      -u COMMANDECK_HOOK_FIRE_LOG -u COMMANDECK_ROUTING PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux bash "${PLUGIN_DIR:-$PLUGIN}/scripts/$s" "$@" </dev/null )
}

# snap -- every file and folder under the fixture's HOME and projects with its
# content hash. A checkout's .git is left out but for the exclude list: git's
# own bookkeeping moves with any worktree.
snap() {
  ( cd "$T" && { find home proj* -path '*/.git/*' -prune -o -type d -print | sed 's/$/\//'
      find home proj* \( -path '*/.git/*' -prune \) -o \( -type f -o -type l \) -print | while IFS= read -r f; do printf '%s %s\n' "$( { [ -d "$f" ] && readlink "$f" || cat "$f"; } | sha256sum | cut -d' ' -f1)" "$f"; done
      for e in proj*/.git/info/exclude; do printf '%s %s\n' "$(sha256sum < "$e" | cut -d' ' -f1)" "$e"; done; } | sort )
}
# mf <project dir> -- that project's install manifest.
mf() { printf '%s/.commandeck/install/%s.json' "$HOME" "$(printf %s "$1" | tr -c 'A-Za-z0-9' '-')"; }
ANSWERS=(--profile claude-openai --name Ada --persona "dry and brief" --strict --test-command "true")
