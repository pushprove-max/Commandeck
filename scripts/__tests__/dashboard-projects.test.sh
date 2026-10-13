#!/usr/bin/env bash
# dashboard-projects.test.sh -- the dashboard lists the projects the plugin was
# set up for, and nothing a test wrote by hand: under a test home, setup.sh
# itself is run for three scratch repositories, and the collector and the page
# server then read the registry set-up wrote. What this pins: a project set up
# with a GitHub origin is listed; one set up without is not, and is named; the
# home project is the one the collector runs for; and one project's commits,
# day cost and saved layout never appear under another.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"
PID=''; trap '[ -z "$PID" ] || kill "$PID" 2>/dev/null; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
REG=$HOME/.commandeck/dashboard/projects OUT=$HOME/.commandeck/dashboard
j() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$OUT/data.js" | jq -c "$1" 2>&1; }

project "$T/one"; git -C "$T/one" config remote.origin.url https://github.com/acme/one.git
project "$T/two"; git -C "$T/two" config remote.origin.url git@github.com:acme/two.git
project "$T/three"; git -C "$T/three" config remote.origin.url "$T/elsewhere.git"
for n in one two three; do run "$T/$n" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "set-up of $n succeeds" 0 $?; done
check "set-up wrote the project list, one line each" "$T/one $T/two $T/three " "$(tr '\n' ' ' < "$REG")"
LIST=$(cat "$REG")

# What tells the projects apart: a commit only two has, and one request today from a session run in two.
git -C "$T/two" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "feat: two only"
mkdir -p "$HOME/.claude/projects/p"
printf '{"type":"assistant","requestId":"r1","cwd":"%s","timestamp":"%s","message":{"model":"claude-opus-5-5","usage":%s}}\n' "$T/two" "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
  '{"input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"cache_read_input_tokens":0,"output_tokens":100}' > "$HOME/.claude/projects/p/s.jsonl"
# The fixture's gh answers by the folder it is run in: two open P1 issues for one, no answer for two.
mkdir -p "$T/gh"; echo '[{"labels":[{"name":"P1"}]},{"labels":[{"name":"P1"}]}]' > "$T/gh/one.json"
run "$T/one" dashboard.sh >"$T/out" 2>&1; check "a collect over the list set-up wrote succeeds" 0 $?
check "one project's open P1 issues never appear under the other: its own count, and not measured where gh has no answer" '[2,null,"fresh","not-measured"]' \
  "$(j '[.projects.one.githubP1, .projects.two.githubP1, .projects.one.sources["github-p1"].status, .projects.two.sources["github-p1"].status]')"
check "the collector read set-up's own file, unchanged" "$LIST" "$(cat "$REG")"
check "both projects with a GitHub origin are listed" '["one","two"]' "$(j '.projects | keys')"
check "the project set up without one is not listed, and is named" '[false,true]' \
  "$(j '[(.projects | has("three")), (.sources.projects.error | test("no GitHub origin.*/three$"))]')"
check "the home project is the one the collector runs for" '"one"' "$(j .home)"
check "the page's script lists the same projects" 'one,two' \
  "$(node -e 'global.window = {}; require(process.argv[1]); console.log(Object.keys(window.DASH.projects).sort().join())' "$OUT/data.js" 2>&1)"
check "one project's commits never appear under the other" '[false,true]' "$(j '[.projects.one, .projects.two | [.mainChain.commits[].subject] | index("feat: two only") != null]')"
check "one project's day cost never appears under the other" '[["one","two"],0,1]' "$(j '.limit.today | [keys, .one.requests, .two.requests]')"
check "the 7-day limit is the machine's, once, for every project" '[true,false]' "$(j '[has("limit"), ([.projects[] | has("limit")] | any)]')"
run "$T/two" dashboard.sh >"$T/out" 2>&1
check "run for the other project, each count is still its own project's" '[2,null]' "$(j '[.projects.one.githubP1, .projects.two.githubP1]')"
check "run for the other project, the list is the same and home is that one" '[["one","two"],"two"]' "$(j '[(.projects | keys), .home]')"

# The page server set-up installed, over the folder the collector wrote: each project's layout is its own.
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 "$PLUGIN/scripts/dashboard_serve.py" "$PORT" 127.0.0.1 "$OUT" & PID=$!
U=http://127.0.0.1:$PORT
for _ in $(seq 50); do curl -s -o /dev/null "$U/index.html" && break; sleep 0.1; done
save() { curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' --data-binary "$1" "$U/layout"; }
check "a project's page is the one page" "$(cksum < "$PLUGIN/dashboard/index.html")" "$(curl -s "$U/index.html?project=one" | cksum)"
check "one project's layout saves" 204 "$(save '{"rev":0,"project":"two","hidden":["host"]}')"
check "the other project's layout saves" 204 "$(save '{"rev":1,"project":"one","hidden":["limit"]}')"
check "each layout is its own in the one file" '[["host"],["limit"],["one","two"]]' \
  "$(curl -s "$U/layout.js" | sed -e 's/^window\.DASH_LAYOUT = //' -e 's/;$//' | jq -c '[.projects.two.hidden, .projects.one.hidden, (.projects | keys)]')"
check "the project list is not served as a layout or changed by a save" "$LIST" "$(cat "$REG")"
done_tests
