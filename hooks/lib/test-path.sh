#!/usr/bin/env bash
# ONE definition of "a test file": test-skip-only-blocker.sh screens these paths and
# scripts/new-test-count.sh counts new cases in them, so the two cannot drift apart.
# new-test-file-guard.sh keeps its own narrower `.test.ts` rule for its own purpose.
#
# Usage: is_test_path <path>   -- exit 0 for a test file, 1 otherwise.
is_test_path() {
  case "$1" in
    *.test.*|*.spec.*|*__tests__*|*/e2e/*) return 0 ;;
  esac
  return 1
}
