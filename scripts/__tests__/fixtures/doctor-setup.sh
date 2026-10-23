# shellcheck shell=bash
# Sourced by doctor.test.sh, doctor-options.test.sh and doctor-run.test.sh: a scratch HOME with the plugin linked in,
# a project whose commandeck.json is hand-written, an Orca stand-in, a config.toml whose notify line calls this
# plugin's hook, and the helpers (in_proj, lib, cache, shadow) and PASS/FAIL/check. Three files, not one: one file of
# every case ran past the runner's 120 s per-file cap under load, and no file raises it.
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
in_proj() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR -u COMMANDECK_SCRATCH -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux "$@"); }
# lib <shell> [args] -- the shell runs with install-lib.sh loaded and the args as "$1"...
lib() { in_proj bash -c '. "$0/paths.sh" && . "$0/install-lib.sh" && c=$1 && shift && eval "$c"' "$REAL/scripts" "$@" 2>&1; }
# cache -- the doctor's prompt-cache lines, with the relay's workspace under $T/ws.
cache() { COMMANDECK_WORKSPACES=$T/ws lib il_cache_ttl_report; }
shadow() { lib il_shadow_report; }
