#!/usr/bin/env bash
# covers: scripts/dashboard_serve.py
# dashboard-serve-project-path.test.sh -- issue 292: /p/<name>/ is a project's own address and sends the browser to the
# page with that project open. Only a name the collector lists is sent on; a name that climbs a folder, or hides a
# slash, is no project and is refused with no Location (the static file handler would serve the root page for /p/../).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
echo '<html></html>' > "$T/index.html"
echo 'window.DASH = {"home":"demo","projects":{"demo":{"path":"/x"},"demo.api":{"path":"/y"}}};' > "$T/data.js"
OUT=$(python3 - "$ROOT/scripts" "$T" <<'PY'
import functools, http.client, http.server, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
def get(path):
    c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
    c.request("GET", path, headers={"Host": "127.0.0.1:%d" % srv.server_address[1]})
    r = c.getresponse()
    return r.status, r.getheader("Location")
class Lan(d.Handler):  # bound to the network, typed into a browser: plain HTTP, so no Sec-Fetch-Site and no Referer
    loopback_only = False
lan = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Lan, directory=sys.argv[2]))
threading.Thread(target=lan.serve_forever, daemon=True).start()
def get_lan(path):
    c = http.client.HTTPConnection("127.0.0.1", lan.server_address[1])
    c.request("GET", path, headers={"Host": "192.0.2.7:%d" % lan.server_address[1]})
    r = c.getresponse()
    return r.status, r.getheader("Location")
class Login(Lan):  # bound to the network with the login on, nobody logged in
    login_on = True
login = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Login, directory=sys.argv[2]))
threading.Thread(target=login.serve_forever, daemon=True).start()
def get_login(path):
    c = http.client.HTTPConnection("127.0.0.1", login.server_address[1])
    c.request("GET", path, headers={"Host": "192.0.2.7:%d" % login.server_address[1]})
    r = c.getresponse()
    return r.status, r.getheader("Location")
for p in ("/p/demo/", "/p/demo.api/", "/p/../", "/p/%2E%2E/", "/p/a%2Fb/", "/p/nope/"):
    s, loc = get(p)
    print(p, s, loc)
print("lan", *get_lan("/p/demo/"))
print("login", *get_login("/p/demo/"))
PY
)
check "GET /p/demo/ redirects to index.html with that project open" "/p/demo/ 302 ../../index.html?project=demo" "$(sed -n 1p <<<"$OUT")"
check "GET /p/demo.api/ does the same for a name with a dot" "/p/demo.api/ 302 ../../index.html?project=demo.api" "$(sed -n 2p <<<"$OUT")"
check "/p/../, /p/%2E%2E/, /p/a%2Fb/ and an unknown name are 404 with no Location" "/p/../ 404 None
/p/%2E%2E/ 404 None
/p/a%2Fb/ 404 None
/p/nope/ 404 None" "$(sed -n 3,6p <<<"$OUT")"
check "typed into a browser on the network (plain HTTP, no Sec-Fetch-Site, no Referer), /p/demo/ is not refused as another site's" \
  "lan 302 ../../index.html?project=demo" "$(sed -n 7p <<<"$OUT")"
# A regression pin: gate() runs before the route, so a visitor who is not logged in is sent to the login, not on.
check "on a network bind with the login on and nobody logged in, /p/demo/ is sent to /login, never on to the page" "login 302 /login" "$(sed -n 8p <<<"$OUT")"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
