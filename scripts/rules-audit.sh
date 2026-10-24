#!/usr/bin/env bash
# rules-audit.sh [--repo DIR] [--memory-dir DIR] [--global FILE] -- the rules audit: instruction-lint.py, whose header lists the kinds.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/instruction-lint.py" "$@"
