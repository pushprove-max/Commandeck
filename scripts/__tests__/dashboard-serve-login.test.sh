#!/usr/bin/env bash
# dashboard-serve-login.test.sh -- the network-bind login half of dashboard-serve.test.sh (issue 263).
# covers: scripts/dashboard_serve.py
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# Issue 263: on a network bind the dashboard is HTTPS only and behind a login (loopback binds serve as above, with none).
# Each case is a real request to a real server process; the steps that need a restart or the command line run between.
LG=$T/login; mkdir -p "$LG/home" "$LG/srv"; echo 'window.DASH = {};' > "$LG/srv/data.js"; echo '<html>page</html>' > "$LG/srv/index.html"
SRVPY=$ROOT/scripts/dashboard_serve.py
lg() { env HOME="$LG/home" COMMANDECK_DASHBOARD_AUTH="$LG/auth/auth.json" python3 "$SRVPY" "$@"; }
CERT=$LG/auth/dashboard-tls/cert.pem
check "no certificate: a network bind refuses to start and says how to make one" "1" \
  "$(timeout 10 env HOME="$LG/home" COMMANDECK_DASHBOARD_AUTH="$LG/auth/auth.json" python3 "$SRVPY" 0 0.0.0.0 "$LG/srv" 2>&1 | grep -c 'no certificate: run dashboard_serve.py make-cert')"
lg make-cert >/dev/null 2>&1
check "make-cert makes the certificate once and keeps it the second time" "1:1" "$([ -s "$CERT" ] && echo 1):$(lg make-cert 2>&1 | grep -c 'certificate kept')"
check "a 7-character password is refused" "1" "$(printf 'seven77\nseven77\n' | lg set-password max 2>&1 | grep -c 'at least 8 characters')"
check "a 7-character password is refused and stores nothing (has-password exits 1)" "1" "$(lg has-password >/dev/null 2>&1; echo $?)"
check "an 8-character password is taken" "0:0" "$(printf 'eightchr\neightchr\n' | lg set-password max >/dev/null 2>&1; echo $?):$(lg has-password >/dev/null 2>&1; echo $?)"
check "the store holds a hash and no password; it is mode 600" "0:600" \
  "$(grep -c eightchr "$LG/auth/auth.json"):$(stat -c %a "$LG/auth/auth.json" 2>/dev/null || stat -f %Lp "$LG/auth/auth.json")"
lgport() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
lgstart() { LGPORT=$(lgport); env HOME="$LG/home" COMMANDECK_DASHBOARD_AUTH="$LG/auth/auth.json" python3 "$SRVPY" "$LGPORT" 0.0.0.0 "$LG/srv" >/dev/null 2>"$LG/stderr" & LGPID=$!
  for _ in $(seq 100); do python3 - "$LGPORT" <<'PY' 2>/dev/null && return 0
import socket, sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1).close()
PY
    sleep 0.1; done; return 1; }
lgstop() { kill "$LGPID" 2>/dev/null; wait "$LGPID" 2>/dev/null; }
# lgreq <port> <name=cookie;...> <METHOD> <path> [json body]: prints "<status> <Location> <Set-Cookie flags of the first cookie> | <body>"
lgreq() { python3 - "$CERT" "$@" <<'PY'
import http.client, json, ssl, sys
cert, port, jar, method, path = sys.argv[1:6]
body = sys.argv[6] if len(sys.argv) > 6 else None
ctx = ssl.create_default_context(cafile=cert)
c = http.client.HTTPSConnection("localhost", int(port), context=ctx)
h = {"Origin": "https://localhost:%s" % port}
if jar: h["Cookie"] = jar
if body is not None: h["Content-Type"] = "application/json"
c.request(method, path, body, h)
r = c.getresponse(); data = r.read().decode(errors="replace")
print(r.status, r.getheader("Location") or "-", "|".join(sorted(v.split(";", 1)[0].split("=")[0] + ":" + ("Secure" in v and "HttpOnly" in v and "SameSite=Strict" in v and "ok" or "bad") for k, v in r.getheaders() if k == "Set-Cookie")) or "-", "|", data[:60].replace("\n", " "))
for k, v in r.getheaders():
    if k == "Set-Cookie": print("COOKIE", v.split(";", 1)[0], file=sys.stderr)
PY
}
# lglogin <port> <trust true|false> <label>: the cookies it set, as "a=b; c=d", on stdout
lglogin() { local out; out=$(lgreq "$1" "" POST /login "{\"user\":\"max\",\"password\":\"eightchr\",\"trust\":$2,\"label\":\"$3\"}" 2>&1 >/dev/null | sed -n 's/^COOKIE //p' | paste -sd';' - | sed 's/;/; /g'); printf '%s' "$out"; }
only() { tr ';' '\n' <<<"$1" | sed 's/^ *//' | grep "^$2="; }
status() { lgreq "$@" 2>/dev/null | cut -d' ' -f1; }
lgstart || echo "FAIL the login server did not start"
P=$LGPORT
check "a page without a login is sent to /login with 302, a data file too" "302 /login:302 /login" "$(lgreq $P "" GET / | cut -d' ' -f1-2):$(lgreq $P "" GET /data.js | cut -d' ' -f1-2)"
check "a write without a login is 401: layout, answer, unsent, restart" "401 401 401 401" \
  "$(for r in 'PUT /layout' 'POST /answer' 'POST /unsent' 'POST /restart'; do status $P "" $r '{}'; done | paste -sd' ' -)"
check "and the layout file is untouched" "none" "$([ -e "$LG/srv/layout.js" ] && echo made || echo none)"
check "the login page is public (GET and HEAD)" "200 1:200" "$(status $P "" GET /login) $(lgreq $P "" GET /login | grep -c '<!doctype html>'):$(status $P "" HEAD /login)"
check "a wrong password is 401 and sets no cookie" "401 - -" "$(lgreq $P "" POST /login '{"user":"max","password":"wrongpass","trust":false,"label":""}' 2>/dev/null | cut -d' ' -f1-3)"
check "a login sets pp_session as HttpOnly, Secure and SameSite=Strict" "200 - pp_session:ok" "$(lgreq $P "" POST /login '{"user":"max","password":"eightchr","trust":false,"label":""}' 2>/dev/null | cut -d' ' -f1-3)"
J=$(lglogin $P false none)
check "logged in, the page and the data file are served" "200 200" "$(status $P "$J" GET /index.html) $(status $P "$J" GET /data.js)"
check "logged in, an answer and a layout save get past the login (a bad body is 400, not 401 or 403)" "400 400" "$(status $P "$J" POST /answer '{}') $(status $P "$J" PUT /layout '{}')"
check "a made-up session cookie gets nothing" "302" "$(status $P "pp_session=forged" GET /index.html)"
D=$(lglogin $P true phone)
check "a trusted device login sets both cookies, each Secure" "pp_device:ok|pp_session:ok" "$(lgreq $P "" POST /login '{"user":"max","password":"eightchr","trust":true,"label":"x"}' 2>/dev/null | cut -d' ' -f3)"
DEV=$(only "$D" pp_device); SES=$(only "$D" pp_session)
check "the device is listed by label" 1 "$(lg devices | grep -c phone)"
check "plain HTTP to the TLS port gets no page" "none" "$(python3 - "$P" <<'PY'
import http.client, sys
try:
    c = http.client.HTTPConnection("localhost", int(sys.argv[1]), timeout=5); c.request("GET", "/"); r = c.getresponse(); print(r.status if r.read() else "none")
except Exception:
    print("none")
PY
)"
lgstop; lgstart; P=$LGPORT
check "after a restart a session is gone and the trusted device logs straight back in" "302 200" "$(status $P "$SES" GET /index.html) $(status $P "$DEV" GET /index.html)"
ID=$(lg devices | awk '/phone/ {print $1; exit}')
D2=$(lglogin $P true tablet); DEV2=$(only "$D2" pp_device); SES2=$(only "$D2" pp_session)
check "before a revoke the tablet's session works" 200 "$(status $P "$SES2" GET /index.html)"
lg revoke "$(lg devices | awk '/tablet/ {print $1; exit}')" >/dev/null
check "a revoked device ends its device cookie and its session on the next request" "302 302" "$(status $P "$DEV2" GET /index.html) $(status $P "$SES2" GET /index.html)"
check "the other device is untouched" 200 "$(status $P "$DEV" GET /index.html)"
J3=$(lglogin $P false none); SES3=$(only "$J3" pp_session)
lg revoke all >/dev/null
check "revoke all ends every device and a session made without one" "302 302 0" "$(status $P "$DEV" GET /index.html) $(status $P "$SES3" GET /index.html) $(lg devices | wc -l | tr -d ' ')"
D4=$(lglogin $P true phone4); DEV4=$(only "$D4" pp_device); SES4=$(only "$D4" pp_session)
printf 'eightchr\neightchr\n' | lg set-password max >/dev/null 2>&1
check "a new password ends every session but keeps the trusted devices" "302 200 1" "$(status $P "$SES4" GET /index.html) $(status $P "$DEV4" GET /index.html) $(lg devices | wc -l | tr -d ' ')"
lgstop; lgstart; P=$LGPORT
check "twenty parallel wrong logins give exactly five 401 and fifteen 429" "5 15" "$(python3 - "$CERT" "$P" <<'PY'
import http.client, json, ssl, sys, threading
cert, port = sys.argv[1:3]
codes = []
def go():
    c = http.client.HTTPSConnection("localhost", int(port), context=ssl.create_default_context(cafile=cert))
    c.request("POST", "/login", json.dumps({"user": "max", "password": "wrong-one", "trust": False, "label": ""}), {"Content-Type": "application/json", "Origin": "https://localhost:" + port})
    codes.append(c.getresponse().status)
ts = [threading.Thread(target=go) for _ in range(20)]
[t.start() for t in ts]; [t.join() for t in ts]
print(codes.count(401), codes.count(429))
PY
)"
check "the right password is locked out too while the lockout lasts" 429 "$(status $P "" POST /login '{"user":"max","password":"eightchr","trust":false,"label":""}')"
lgstop
check "no password reached the server's log or any file under the auth folder" 0 "$(grep -rl -e eightchr -e wrong-one "$LG/auth" "$LG/stderr" 2>/dev/null | wc -l | tr -d ' ')"
# A loopback bind serves as before: no login page, no login, the page is open.
LP=$(lgport); env HOME="$LG/home" COMMANDECK_DASHBOARD_AUTH="$LG/auth/auth.json" python3 "$SRVPY" "$LP" 127.0.0.1 "$LG/srv" >/dev/null 2>&1 & LPID=$!
for _ in $(seq 100); do python3 -c "import socket,sys; socket.create_connection(('127.0.0.1', $LP), 1).close()" 2>/dev/null && break; sleep 0.1; done
check "a loopback bind serves the page with no login and has no login page" "200 404" \
  "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$LP/") $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$LP/login")"
kill "$LPID" 2>/dev/null; wait "$LPID" 2>/dev/null

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
