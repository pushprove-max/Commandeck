#!/usr/bin/env bash
# SessionStart hook, main only: a card of script signatures taken from each script's `--help`, so main reads usage
# instead of the script's header. Never blocks: a script whose `--help` fails or takes over 2 s adds no line, and a
# missing script prints nothing. Scripts are read from this plugin's own folder.
#
# Self-test: bash hooks/__tests__/main-script-card.test.sh
# Retire when: startup context lists the script usage lines
[ -t 0 ] || IFS= read -r -d '' INPUT
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "${INPUT-}" SessionStart
PLUGIN=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)

# Main is a plain checkout that is not a reviewer pane, and Orca (when present) names this pane as main's.
[ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] && [ "${COMMANDECK_REVIEWER:-}" != 1 ] || exit 0
. "${BASH_SOURCE[0]%/*}/lib/project.sh" 2>/dev/null || exit 0
pp_is_main_pane || exit 0

# A usage line is `usage: <name>.sh ...`; the indented lines that start with the same name continue it (seat.sh's
# collect form). At most 40 lines in all.
SIGNATURES="peek long-job seat merge-unit-local"
echo
echo "# Script signatures (each script's --help; run it for the flags)"
for name in $SIGNATURES; do
  help=$(timeout 2 bash "$PLUGIN/scripts/$name.sh" --help </dev/null 2>/dev/null) || continue
  printf '%s\n' "$help" \
    | awk -v n="$name.sh" '{ t = $0; sub(/^[ \t]+/, "", t) } index($0, "usage: " n) == 1 || (/^[ \t]/ && index(t, n " ") == 1) { print }'
done | head -40
