#!/usr/bin/env bash
# SessionStart hook: Orca copies ~/.claude/settings.json over a profile's settings.json at a launch, and what setup put
# in the profile's file (status line, /config options, auto-mode lines, permission rules) goes with it. At a launch
# (source startup, or resume: Orca may start a pane with --resume) this puts those back before the session needs them
# (il_profile_repair), all but the owner's choices made with /commandeck:revoke, in the active profile's file only: it never
# writes ~/.claude/settings.json. A /clear or compact does nothing. It does nothing without CLAUDE_CONFIG_DIR, in the
# home profile, or for a file setup never recorded. Silent: a failure leaves the file as it was.
set -u
input=$(cat 2>/dev/null || true)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$input"
case $(jq -r '.source // empty' <<<"$input" 2>/dev/null) in startup|resume) ;; *) exit 0 ;; esac
[ -n "${CLAUDE_CONFIG_DIR:-}" ] || exit 0
F=$CLAUDE_CONFIG_DIR/settings.json
[ -f "$F" ] && [ ! "$CLAUDE_CONFIG_DIR" -ef "$HOME/.claude" ] || exit 0
. "${BASH_SOURCE[0]%/*}/../scripts/paths.sh" >/dev/null 2>&1 || exit 0
. "$PP_SCRIPTS/install-lib.sh" >/dev/null 2>&1 || exit 0
il_profile_files "$IL_MACHINE" 2>/dev/null | grep -qxF -- "$F" || exit 0
il_profile_repair "$IL_MACHINE" "$F" >/dev/null 2>&1
exit 0
