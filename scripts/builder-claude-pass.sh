#!/usr/bin/env bash
# builder-claude-pass.sh <unit> <N> adversarial|review|final -- the review pass of the
#     Claude-only profile: the same three passes, commit step, round file and
#     checks as builder-codex-pass.sh, run through a headless read-only session
#     on roles.claude-reviewer instead of Codex.
# builder-claude-pass.sh --verify <worktree> <unit> <tip> | --preflight -- as there.
#
# One body for both passes, so the proof cannot drift between them: this file
# only picks the reviewer.
# Self-test: bash scripts/__tests__/builder-claude-pass.test.sh
COMMANDECK_PASS=claude exec bash "$(dirname "${BASH_SOURCE[0]}")/builder-codex-pass.sh" "$@"
