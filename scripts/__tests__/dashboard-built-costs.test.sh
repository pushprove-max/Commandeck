#!/usr/bin/env bash
# dashboard-built-costs.test.sh -- the costs kept for finished builds, and the project registry, are never lost to a
# file that cannot be read or a directory in its place. The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
dash

# The costs kept for finished builds are written back whole on every run. A kept file that could not be read
# was taken as empty and overwritten, losing every earlier unit's cost; one that reads but is not an object is reset.
K=$T/out/cache/demo/unit-cost.json
printf '{"old-unit":{"usd":1}}\n' > "$K"; chmod 000 "$K"; dash; chmod 644 "$K"
check "an unreadable kept cost file is left as it was" '{"old-unit":{"usd":1}}' "$(jq -c . "$K" 2>&1)"
echo 'not json{' > "$K"; dash
check "a corrupt kept cost file is reset to an object" '{}' "$(jq -c . "$K" 2>&1)"
rm "$K"; mkdir "$K"; dash
check "a directory where the kept cost file belongs gets nothing put inside it" 0 "$(ls -A "$K" | wc -l | tr -d ' ')"
# The same fault in --unregister: an unreadable registry was rewritten as empty, dropping every registered project.
unreg() { COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" bash "$SOURCE/scripts/dashboard.sh" --unregister "$1" >/dev/null 2>&1; }
R=$T/out/projects; printf '/a\n/b\n' > "$R"; chmod 000 "$R"; unreg /a
check "--unregister with an unreadable registry fails and leaves it as it was" "1 /a /b" "$? $(chmod 644 "$R"; paste -sd' ' "$R")"
unreg /a; check "--unregister drops only that project" "0 /b" "$? $(paste -sd' ' "$R")"
rm "$R"; mkdir "$R"; unreg /b
check "--unregister with a directory where the registry belongs fails, putting nothing inside it" "1 0" "$? $(ls -A "$R" | wc -l | tr -d ' ')"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
