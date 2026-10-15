#!/usr/bin/env bash
# dashboard-serve.test.sh -- the host keeps the owner's cleared builds, the last
# 2,000 of them, in the order it first saw each. A tab left open still lists a
# build whose clear has since left that history, and sends it again with its
# next save. What this pins: such a replay at the 2,000-entry boundary is not
# taken as a new clear, so it cannot push out clears newer than it (they would
# come back on the owner's next reload); a build never cleared before still is.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

# One server in this process; each save is a real PUT. Prints the held list's first and last name and its length.
OUT=$(python3 - "$ROOT/scripts" "$T" <<'PY'
import functools, http.client, http.server, json, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
rev = 0
def save(names):
    global rev
    c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
    c.request("PUT", "/layout", json.dumps({"rev": rev, "project": "demo", "closed": names}), {"Content-Type": "application/json"})
    status = c.getresponse().status
    assert status == 204, status
    rev += 1
def held():
    rev_, _, slots = d.held(sys.argv[2] + "/layout.js")
    return slots["demo"]["closed"]
name = lambda i: "b%04d" % i
# 2,100 clears, 200 a save (the most one save may name): the first 100 have left the history.
for start in range(1, 2101, 200):
    save([name(i) for i in range(start, min(start + 200, 2101))])
h = held()
print(h[0], h[-1], len(h))
# A stale tab replays the 100 expired clears.
save([name(i) for i in range(1, 101)])
h = held()
print(h[0], h[-1], len(h))
# A build never cleared before is still a new clear, and the oldest held one makes room.
save(["fresh"])
h = held()
print(h[0], h[-1], len(h))
PY
)
check "2,100 clears keep the newest 2,000" "b0101 b2100 2000" "$(sed -n 1p <<<"$OUT")"
check "a stale tab's replay of expired clears pushes out no newer clear" "b0101 b2100 2000" "$(sed -n 2p <<<"$OUT")"
check "a build cleared for the first time is still added" "b0102 fresh 2000" "$(sed -n 3p <<<"$OUT")"

# An upgrade: a full layout from a host that kept no closed.log. Its first save drops the oldest held clear,
# which must still count as seen, so the stale tab's replay of it pushes out nothing.
mkdir "$T/up"
OUT=$(python3 - "$ROOT/scripts" "$T/up" <<'PY'
import functools, http.client, http.server, json, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
name = lambda i: "b%04d" % i
with open(sys.argv[2] + "/layout.js", "w") as f:
    f.write("window.DASH_LAYOUT = %s;\n" % json.dumps({"rev": 0, "projects": {"demo": {"rev": 5, "closed": [name(i) for i in range(1, 2001)]}}}))
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
for rev, names in ((5, ["fresh"]), (6, [name(1)])):
    c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
    c.request("PUT", "/layout", json.dumps({"rev": rev, "project": "demo", "closed": names}), {"Content-Type": "application/json"})
    assert c.getresponse().status == 204
h = d.held(sys.argv[2] + "/layout.js")[2]["demo"]["closed"]
print(h[0], h[-1], len(h))
PY
)
check "after an upgrade, a replay of the clear the first save dropped pushes out no newer clear" "b0002 fresh 2000" "$OUT"

# The same upgrade with the first append to closed.log failing: that save must not land, or its dropped clear is lost.
mkdir "$T/fail"
OUT=$(python3 - "$ROOT/scripts" "$T/fail" <<'PY'
import builtins, functools, http.client, http.server, json, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
name = lambda i: "b%04d" % i
with open(sys.argv[2] + "/layout.js", "w") as f:
    f.write("window.DASH_LAYOUT = %s;\n" % json.dumps({"rev": 0, "projects": {"demo": {"rev": 5, "closed": [name(i) for i in range(1, 2001)]}}}))
fails = [1]
def flaky(path, mode="r", *a, **k):
    if str(path).endswith("closed.log") and "a" in mode and fails:
        fails.pop(); raise OSError("disk full")
    return builtins.open(path, mode, *a, **k)
d.open = flaky
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
def put(rev, names):
    c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
    c.request("PUT", "/layout", json.dumps({"rev": rev, "project": "demo", "closed": names}), {"Content-Type": "application/json"})
    try:
        return c.getresponse().status
    except Exception:
        return "dropped"
codes = [put(5, ["fresh"])]
rev = d.held(sys.argv[2] + "/layout.js")[2]["demo"]["rev"]
codes += [put(rev, ["fresh"]), put(rev + 1, [name(1)])]
h = d.held(sys.argv[2] + "/layout.js")[2]["demo"]["closed"]
print(codes[0] != 204, rev, h[0], h[-1], len(h))
PY
)
check "a save whose closed.log append fails does not land, and the replay after it pushes out nothing" "True 5 b0002 fresh 2000" "$OUT"

# The other order: the append lands and the layout write fails. The page sends its clear again, and it is held.
mkdir "$T/rep"
OUT=$(python3 - "$ROOT/scripts" "$T/rep" <<'PY'
import functools, http.client, http.server, json, os, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
name = lambda i: "b%04d" % i
with open(sys.argv[2] + "/layout.js", "w") as f:
    f.write("window.DASH_LAYOUT = %s;\n" % json.dumps({"rev": 0, "projects": {"demo": {"rev": 5, "closed": [name(i) for i in range(1, 2001)]}}}))
fails, real = [1], os.replace
def flaky(a, b):
    if fails:
        fails.pop(); raise OSError("disk full")
    return real(a, b)
d.os.replace = flaky
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
def put(rev, names):
    c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
    c.request("PUT", "/layout", json.dumps({"rev": rev, "project": "demo", "closed": names}), {"Content-Type": "application/json"})
    try:
        return c.getresponse().status
    except Exception:
        return "dropped"
codes = [put(5, ["fresh"]), put(5, ["fresh"])]
h = d.held(sys.argv[2] + "/layout.js")[2]["demo"]["closed"]
print(codes[0] != 204, codes[1], h[0], h[-1], len(h))
PY
)
check "a save whose layout write fails, sent again, holds its clear" "True 204 b0002 fresh 2000" "$OUT"

# An append cut off mid-record (a full disk, a crash) leaves closed.log with no final newline. The next
# record must not join the torn one, or the name it writes down is lost.
mkdir "$T/torn"
printf 'demo\tb000' > "$T/torn/closed.log"
OUT=$(python3 - "$ROOT/scripts" "$T/torn" <<'PY'
import functools, http.client, http.server, json, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
name = lambda i: "b%04d" % i
with open(sys.argv[2] + "/layout.js", "w") as f:
    f.write("window.DASH_LAYOUT = %s;\n" % json.dumps({"rev": 0, "projects": {"demo": {"rev": 5, "closed": [name(i) for i in range(1, 2001)]}}}))
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
for rev, names in ((5, ["fresh"]), (6, [name(1)])):
    c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
    c.request("PUT", "/layout", json.dumps({"rev": rev, "project": "demo", "closed": names}), {"Content-Type": "application/json"})
    assert c.getresponse().status == 204
h = d.held(sys.argv[2] + "/layout.js")[2]["demo"]["closed"]
print(h[0], h[-1], len(h))
PY
)
check "after a torn append, the next drop is still written down whole" "b0002 fresh 2000" "$OUT"

# Each project's slot has its own save number. A save on project a must not refuse the next save on project b
# (that page would reload and lose its change), while a save made over an older a is still refused.
mkdir "$T/rev"
OUT=$(python3 - "$ROOT/scripts" "$T/rev" <<'PY'
import functools, http.client, http.server, json, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
def put(project, rev):
    c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
    c.request("PUT", "/layout", json.dumps({"rev": rev, "project": project, "hidden": [project]}), {"Content-Type": "application/json"})
    return c.getresponse().status
print(put("a", 0), put("b", 0), put("a", 0), put("a", 1))
PY
)
check "a save on one project refuses no save on another; a stale one on the same project still is" "204 204 409 204" "$OUT"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
