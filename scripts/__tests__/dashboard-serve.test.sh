#!/usr/bin/env bash
# dashboard-serve.test.sh -- the dashboard's snapshot is a script file
# (data.js) holding the owner's decisions and task text. A plain file server
# hands it to any web page that names it in a <script> tag. What this pins:
# the server answers its own page and a direct visit, and refuses a request a
# browser marks as coming from another site or sends under another host name.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'kill "${SRV:-}" "${SRV2:-}" "${SRV3:-}" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

echo 'window.DASH = {"secret": 1};' > "$T/data.js"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 "$ROOT/scripts/dashboard_serve.py" "$PORT" 127.0.0.1 "$T" >/dev/null 2>&1 & SRV=$!
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/data.js" && break; sleep 0.1; done
code() { curl -s -o /dev/null -w '%{http_code}' "$@" "http://127.0.0.1:$PORT/data.js"; }

check "a direct visit reads the snapshot" 200 "$(code)"
check "the dashboard's own page reads it" 200 "$(code -H 'Sec-Fetch-Site: same-origin' -H "Referer: http://127.0.0.1:$PORT/")"
check "another site's page is refused" 403 "$(code -H 'Sec-Fetch-Site: cross-site' -H 'Referer: https://evil.example/')"
check "a browser that sends no fetch mark is judged by where the page is" 403 "$(code -H 'Referer: https://evil.example/x')"
check "a request under another host name is refused (a rebound name)" 403 "$(code -H 'Host: evil.example')"
check "localhost is this machine too" 200 "$(code -H "Host: localhost:$PORT")"

# Served to the network (COMMANDECK_DASHBOARD_BIND=0.0.0.0) the page is reached
# by this machine's address or name. Any other name is one another site has
# pointed at this address, and its page would read the snapshot as its own.
# The server is started on loopback here, in that mode, so the test opens no port to the network.
PORT2=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
COMMANDECK_DASHBOARD_HOSTS='box.tailnet.example, Desk.Lan' python3 - "$ROOT/scripts" "$PORT2" "$T" >/dev/null 2>&1 <<'PY' & SRV2=$!
import functools, http.server, sys
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
d.Handler.loopback_only = False
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), functools.partial(d.Handler, directory=sys.argv[3])).serve_forever()
PY
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT2/data.js" && break; sleep 0.1; done
code2() { curl -s -o /dev/null -w '%{http_code}' "$@" "http://127.0.0.1:$PORT2/data.js"; }
check "served to the network, a name that is not this machine's is refused" 403 "$(code2 -H "Host: evil.example:$PORT2")"
check "an address is answered: no name can be rebound to it" "200 200" "$(code2 -H "Host: 192.0.2.20:$PORT2" -H "Referer: http://192.0.2.20:$PORT2/") $(code2 -H "Host: [fe80::1]:$PORT2" -H "Referer: http://[fe80::1]:$PORT2/")"
# Over plain HTTP to a network address a browser sends no Sec-Fetch-Site, and
# a page that asks for no referrer sends no Referer either: such a request
# says nothing of where it came from, and another site's <script> tag makes
# exactly that. The dashboard's own page always names itself.
check "served to the network, a request that names no page is refused the snapshot" 403 "$(code2 -H "Host: 192.0.2.20:$PORT2")"
check "but is given the page itself, which is how the dashboard is opened" 200 "$(: > "$T/index.html"; curl -s -o /dev/null -w '%{http_code}' -H "Host: 192.0.2.20:$PORT2" "http://127.0.0.1:$PORT2/")"
check "a browser that does say same-origin is answered" 200 "$(code2 -H "Host: 192.0.2.20:$PORT2" -H 'Sec-Fetch-Site: same-origin')"
OWNNAME=$(python3 -c 'import socket; print(socket.gethostname().split(".")[0])').local
check "this machine's own name is answered" 200 "$(code2 -H "Host: $OWNNAME:$PORT2" -H "Referer: http://$OWNNAME:$PORT2/")"
check "and so is loopback" 200 "$(code2)"
# The machine may be reached by a name from other DNS (a tailnet's). The list
# is closed until setup is given the name (setup.sh --hosts), and the server
# above was started with two.
check "a name setup was given is answered, in any case" "200 200" \
  "$(code2 -H "Host: box.tailnet.example:$PORT2" -H "Referer: http://box.tailnet.example:$PORT2/") $(code2 -H "Host: desk.lan:$PORT2" -H "Referer: http://desk.lan:$PORT2/")"
check "a name that only starts like one is still refused" 403 "$(code2 -H "Host: box.tailnet.example.evil.example:$PORT2" -H "Referer: http://box.tailnet.example.evil.example:$PORT2/")"

# COMMANDECK_DASHBOARD_BIND=::1 is an IPv6 address, and the server must open
# an IPv6 socket for it. Skipped on a host with no IPv6 loopback.
if PORT3=$(python3 -c 'import socket; s = socket.socket(socket.AF_INET6); s.bind(("::1", 0)); print(s.getsockname()[1])' 2>/dev/null); then
  python3 "$ROOT/scripts/dashboard_serve.py" "$PORT3" ::1 "$T" >/dev/null 2>&1 & SRV3=$!
  for _ in $(seq 30); do curl -s -o /dev/null "http://[::1]:$PORT3/data.js" && break; sleep 0.1; done
  check "bound to ::1 it answers there" 200 "$(curl -s -o /dev/null -w '%{http_code}' "http://[::1]:$PORT3/data.js")"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
