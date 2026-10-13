# shellcheck shell=bash
# The rule commit-msg enforces, shared with scripts/unit-loop.sh so the
# loop stops on a missing note by name before this hook refuses its commit.

# Guard-class test files (the naming rule the push-gate selector enforces:
# *conformance* / *guard* / *parity* / *coverage*): paths on stdin, the
# guard-class ones on stdout.
guard_class_tests() { grep -E '(conformance|guard|parity|coverage)[^/]*\.test\.(ts|tsx)$' || true; }

# 0 when the commit message (a file argument, or stdin) carries the note.
has_mutation_note() { grep -qi 'Mutation-verified' "$@"; }
