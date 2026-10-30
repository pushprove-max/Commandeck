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
# Main last started under profile A, which has transcripts (agent-startup-context.sh records it); B has none.
SCR=$(. "$T/plugin/scripts/paths.sh" && echo "$PP_SCRATCH"); mkdir -p "$SCR" "$T/prof-a/projects" "$T/prof-b"
echo "$T/prof-a" > "$SCR/claude-config-dir"
(cd "$T/proj" && COMMANDECK_DASHBOARD_CYCLE_S=1 exec bash "$T/plugin/scripts/dashboard.sh" --loop >/dev/null 2>"$T/loop.err") & LOOP=$!
wait_for 20 test -s "$T/out/alive.js"; check "the loop is up" 0 $?
# logs <status>: the newest data.js says Claude Code's transcripts are <status>.
logs() { grep -o '"claude-logs":{[^}]*}' "$T/out/data.js" 2>/dev/null | grep -q "\"status\":\"$1\""; }
wait_for 60 logs fresh; check "the loop reads the profile main started under" 0 $?
# The loop runs for days: main starting under another profile must move the next collect there, or the quota
# would be B's and the transcripts and spend A's.
echo "$T/prof-b" > "$SCR/claude-config-dir"
wait_for 60 logs not-measured; check "the running loop follows main to another profile" 0 $?

# A view file that did not change is not written again: same file, same old time.
touch -t 200001010000 "$T/out/index.html"; touch -t 200001010001 "$T/old"; INO=$(ls -i "$T/out/index.html" | awk '{print $1}')
printf '/* merged fix */\n' >> "$T/plugin/dashboard/app.css"
wait_for 10 same app.css; check "a changed view file reaches the served copy with no --install" 0 $?
check "an unchanged view file is not rewritten" "$INO old" "$(ls -i "$T/out/index.html" | awk '{print $1}') $([ "$T/out/index.html" -nt "$T/old" ] || echo old)"
check "the page sees the new view by its checksum" 1 "$(wait_for 5 grep -q "\"view\":\"$(cat "$T/out/index.html" "$T/out/app.css" "$T/out/app.js" | cksum | cut -d' ' -f1)\"" "$T/out/alive.js" && echo 1)"

chmod a-w "$T/out"; printf '// another\n' >> "$T/plugin/dashboard/app.js"
wait_for 10 grep -q 'could not refresh' "$T/loop.err"; check "a copy it cannot make says so" 0 $?
check "and the old file stays" 1 "$([ -s "$T/out/app.js" ] && ! same app.js && echo 1)"
chmod u+w "$T/out"

# Issue 466: a registered project's stream is followed too, each project's rows in its own file. The loop registers it at
# a cycle, so the event repeats until a lane has run. Its unit stays out of the home project's rows.
B=$T/beta; git init -q -b main "$B" && git -C "$B" remote add origin https://github.com/acme/beta.git
printf '#!/usr/bin/env bash\ncase "$*" in *"worktree ps"*) echo %s ;; *) exit 1 ;; esac\n' "'{\"result\":{\"worktrees\":[]}}'" > "$T/bin/orca-ide"; chmod +x "$T/bin/orca-ide"
inb() { (cd "$B" && env -u COMMANDECK_SCRATCH -u COMMANDECK_WORKSPACES COMMANDECK_MAIN="$B" bash -c ". '$T/plugin/scripts/paths.sh'; $1"); }
BW=$(inb 'echo "$PP_WORKSPACES"'); mkdir -p "$BW/bu1" && touch "$BW/bu1/.git"
printf '%s\n' "$T/proj" "$B" > "$T/out/projects"
beta_live() { inb 'pp_unit_event bu1 seat-launch'; sleep 0.5; jq -e '.rows.bu1.row.unit == "bu1"' "$T/out/live/beta.json" >/dev/null 2>&1; }
wait_for 60 beta_live; check "a registered project goes live (issue 466)" "0 false" "$? $(jq -e '.rows.bu1' "$T/out/live.json" >/dev/null 2>&1 && echo true || echo false)"
printf '%s\n' "$T/proj" > "$T/out/projects"

# Issue 292: the job file left out COMMANDECK_SCRATCH, so a home project with its scratch moved lost its state at
# the first restart. A stub launchctl, so no job is loaded.
printf '#!/usr/bin/env bash\necho "${0##*/} $*" >> "%s/managed"\n[ "$1" != print ]\n' "$T" > "$T/bin/launchctl"; cp "$T/bin/launchctl" "$T/bin/systemctl"; chmod +x "$T/bin/launchctl" "$T/bin/systemctl"
COMMANDECK_HOST_OS=Darwin COMMANDECK_SCRATCH=$T/scr COMMANDECK_DASHBOARD_DIR=$T/inst bash "$T/plugin/scripts/dashboard.sh" --install >/dev/null 2>&1
check "issue 292: the job file keeps COMMANDECK_SCRATCH when it is set" "0 1" \
  "$? $(grep -c "<key>COMMANDECK_SCRATCH</key><string>$T/scr</string>" "$(COMMANDECK_HOST_OS=Darwin bash "$T/plugin/scripts/dashboard.sh" --job-file)")"
# Issue 294: the page's Restart collector runs --restart, which asks the job's own manager by the name install wrote.
: > "$T/managed"
for os in Darwin Linux; do COMMANDECK_HOST_OS=$os bash "$T/plugin/scripts/dashboard.sh" --restart; done
check "issue 294: --restart kicks the job by its label on macOS and restarts its unit on Linux" \
  "launchctl kickstart -k gui/$(id -u)/com.commandeck.dashboard|systemctl --user --no-block restart commandeck-dashboard.service" \
  "$(paste -sd'|' "$T/managed")"
# Issues 263 and 255: a network bind is HTTPS behind a login. Installing it with no password stored would restart the
# dashboard behind a login no one can pass, so --install refuses (exit 5) and installs nothing; with one stored it makes
# the certificate and prints the https address. A loopback install (above) needs neither.
: > "$T/managed"; rm -rf "$HOME/.commandeck/dashboard-tls" "$HOME/.commandeck/dashboard-auth.json"
OUTP=$(COMMANDECK_DASHBOARD_BIND=0.0.0.0 COMMANDECK_HOST_OS=Darwin COMMANDECK_DASHBOARD_DIR=$T/inst2 bash "$T/plugin/scripts/dashboard.sh" --install 2>&1); RC=$?
check "issue 255: a network bind with no password stored exits 5, names set-password, and installs nothing" "5:1:0" \
  "$RC:$(grep -c 'dashboard_serve.py set-password' <<<"$OUTP"):$(wc -c < "$T/managed" | tr -d ' ')"
printf 'eightchr\neightchr\n' | python3 "$T/plugin/scripts/dashboard_serve.py" set-password max >/dev/null 2>&1
OUTP=$(COMMANDECK_DASHBOARD_BIND=0.0.0.0 COMMANDECK_HOST_OS=Darwin COMMANDECK_DASHBOARD_DIR=$T/inst2 bash "$T/plugin/scripts/dashboard.sh" --install 2>&1); RC=$?
check "issue 263: with a password stored, --install makes the certificate and prints the https address" "0:1:1" \
  "$RC:$([ -s "$HOME/.commandeck/dashboard-tls/cert.pem" ] && echo 1):$(grep -c 'open https://<this host>.local:' <<<"$OUTP")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
