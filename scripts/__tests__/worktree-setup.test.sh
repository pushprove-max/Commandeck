#!/usr/bin/env bash
# worktree-setup.test.sh -- the settings profile worktree-setup.sh writes for a worktree, a relay pane's and a
# Builder's, on a hand-written commandeck.json (no setup run). What this pins: the owner wants ponytail at
# full for every role, the relay pane included (2026-10-16), so an earlier run's "off" is taken back out; the
# typescript-lsp plugin is gone, so no profile names it; and the summary line reads as words.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME"
P=$T/proj; git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
mkdir -p "$P/.claude" && echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
run() { (cd "$1" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH bash "$REAL/scripts/worktree-setup.sh" "$@" </dev/null); }
# An earlier run turned ponytail and typescript-lsp off in every profile.
for w in Chief-of-Staff plain bld; do
  git -C "$P" worktree add -q "$T/wt/$w"; mkdir -p "$T/wt/$w/.claude"
  echo '{"enabledPlugins":{"ponytail@ponytail":false,"typescript-lsp@claude-plugins-official":false}}' > "$T/wt/$w/.claude/settings.local.json"
done
run "$T/wt/Chief-of-Staff" >/dev/null 2>&1
run "$T/wt/plain" >"$T/wout" 2>&1
run "$T/wt/bld" --builder >/dev/null 2>&1
check "the relay pane no longer turns ponytail off: it follows the owner's setting" null "$(jq '.enabledPlugins["ponytail@ponytail"]' "$T/wt/Chief-of-Staff/.claude/settings.local.json")"
check "no worktree, relay or Builder profile names typescript-lsp" 0 \
  "$(cat "$T/wt"/{plain,Chief-of-Staff,bld}/.claude/settings.local.json | jq -s '[.[].enabledPlugins | keys[] | select(startswith("typescript-lsp"))] | length')"
check "the worktree summary says memoir off, then the denied tools, a space between" 1 "$(grep -c 'memoir off, [0-9]* unused tools denied' "$T/wout")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
