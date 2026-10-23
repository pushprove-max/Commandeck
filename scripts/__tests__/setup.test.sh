#!/usr/bin/env bash
# setup.sh reads --install-missing (the owner's yes to installing tools) in a first loop, before the full parse.
# That loop skips the value of every option in TAKES, so `--name --install-missing` is a value, never a yes. An
# option the full parse takes a value for but TAKES lacks (a typo, two names run together) lets its value grant
# installation. This holds every value-taking option in the full parse to that rule, by running the first loop.
set -uo pipefail
SETUP=$(cd "$(dirname "$0")/.." && pwd)/setup.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

PRE=$(sed -n '/^TAKES=/,/^done/p' "$SETUP")
# The full parse's labels; a branch that ends `shift ;;` on its line takes no value.
OPTS=$(sed -n '/^while \[ \$# -gt 0 \]/,/^done/p' "$SETUP" | grep -vE 'shift ;;' \
  | grep -oE '^[[:space:]]+--[a-z-]+(\|--[a-z-]+)*\)' | tr -d ' )' | tr '|' '\n')
check "the full parse names value-taking options" true "$([ "$(wc -l <<<"$OPTS")" -gt 30 ] && echo true || echo false)"
GRANTED=
for o in $OPTS; do
  # shellcheck disable=SC2034 # the first loop reads INSTALL
  GRANTED+=$(set -- "$o" --install-missing; eval "$PRE"; [ -z "$INSTALL" ] || echo " $o")
done
check "no option's value is read as --install-missing" '' "$GRANTED"
GRANTED=$(set -- --profile claude --install-missing; eval "$PRE"; echo "$INSTALL")
check "a real --install-missing after a value is still the owner's yes" 1 "$GRANTED"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
