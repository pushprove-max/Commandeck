#!/usr/bin/env bash
# dashboard-loop.test.sh -- the running dashboard serves copies of its view files (index.html, app.css, app.js),
# made at --install. A merged fix to one never reached the page: the --loop job kept serving the old copy until
# someone ran --install again, and no merge does that. What this pins: the loop brings a view file whose copy
# differs from the plugin's own back in line on its own, and a copy it cannot make keeps the old file and says so.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P)
PASS=0 FAIL=0 LOOP=
trap '[ -z "$LOOP" ] || kill "$LOOP" 2>/dev/null; wait 2>/dev/null; rm -rf "$T"' EXIT
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home COMMANDECK_DASHBOARD_DIR=$T/out COMMANDECK_DASHBOARD_BIND=127.0.0.1
export COMMANDECK_DASHBOARD_PORT=$(( 20000 + $$ % 20000 )) COMMANDECK_DASHBOARD_ALIVE_S=1
mkdir -p "$HOME" "$T/plugin" "$T/bin"
for d in scripts hooks config dashboard templates .claude-plugin; do cp -R "$SOURCE/$d" "$T/plugin/"; done
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
git init -q -b main "$T/proj" && git -C "$T/proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
export COMMANDECK_MAIN=$T/proj PATH=$T/bin:$PATH
# wait_for <seconds> <command...> -- 0 once the command succeeds, 1 when the time runs out.
wait_for() { local n=$(( $1 * 10 )); shift; while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 0.1; n=$((n - 1)); done; return 1; }
same() { cmp -s "$T/plugin/dashboard/$1" "$T/out/$1"; }

mkdir -p "$T/out"; for f in index.html app.css app.js; do cp "$T/plugin/dashboard/$f" "$T/out/$f"; done
(cd "$T/proj" && exec bash "$T/plugin/scripts/dashboard.sh" --loop >/dev/null 2>"$T/loop.err") & LOOP=$!
wait_for 20 test -s "$T/out/alive.js"; check "the loop is up" 0 $?

printf '/* merged fix */\n' >> "$T/plugin/dashboard/app.css"
wait_for 10 same app.css; check "a changed view file reaches the served copy with no --install" 0 $?
check "the page sees the new view by its checksum" 1 "$(wait_for 5 grep -q "\"view\":\"$(cat "$T/out/index.html" "$T/out/app.css" "$T/out/app.js" | cksum | cut -d' ' -f1)\"" "$T/out/alive.js" && echo 1)"

chmod a-w "$T/out"; printf '// another\n' >> "$T/plugin/dashboard/app.js"
wait_for 10 grep -q 'could not refresh' "$T/loop.err"; check "a copy it cannot make says so" 0 $?
check "and the old file stays" 1 "$([ -s "$T/out/app.js" ] && ! same app.js && echo 1)"
chmod u+w "$T/out"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
