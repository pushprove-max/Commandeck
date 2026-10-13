#!/usr/bin/env bash
set -eu
cd "$(git rev-parse --show-toplevel)"
predicate='all(.tool_input.questions[]?; .options[0].label == $d)'
owners=$(rg -l -F "$predicate" \
  hooks/worker-ask-guard.sh \
  hooks/ask-records-decision.sh \
  hooks/lib/ask-decoy.sh)
[ "$owners" = 'hooks/lib/ask-decoy.sh' ] || {
  echo "FAIL: decoy validation must have one shared library owner"
  exit 1
}
