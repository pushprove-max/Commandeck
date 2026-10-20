#!/usr/bin/env bash
# builder-claude-pass.sh [--check] <unit> <N> adversarial|review|final -- the review pass of the
#     Claude-only profile: the same three passes, commit step, round file and
#     checks as builder-codex-pass.sh, run through a headless read-only session
#     on roles.claude-reviewer instead of Codex.
# builder-claude-pass.sh --verify <worktree> <unit> <tip> | --preflight -- as there.
#
# One body for both passes, so the proof cannot drift between them: this file
# only picks the reviewer.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
COMMANDECK_PASS=claude exec bash "$(dirname "${BASH_SOURCE[0]}")/builder-codex-pass.sh" "$@"
