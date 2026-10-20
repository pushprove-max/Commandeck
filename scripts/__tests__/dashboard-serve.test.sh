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

# Issue 240: the owner answers a decision from the "Needs me" panel, from this machine only (a token in the page
# would be readable by anyone on the network who loads it). A POST from another address, or with another site's
# Origin, is refused. A loopback answer closes the ledger row, logs a ruling and tells main and the relay (stubs
# here, writing what they were sent); a second answer to the same id is refused; a send that failed is kept and
# sent again on the next refresh, the page's next read of data.js. The project's folder comes from the host's
# own data.js, never from the request.
P=$T/plugin; mkdir -p "$P"; cp -R "$ROOT/scripts" "$ROOT/hooks" "$P/"
printf '#!/usr/bin/env bash\n[ ! -e "%s/no-send" ] || exit 1\nprintf "%%s|" "${0##*/}" "$@" >> "%s/sent"; echo >> "%s/sent"\n' "$T" "$T" "$T" > "$P/scripts/to-main.sh"
cp "$P/scripts/to-main.sh" "$P/scripts/cos-tell.sh"
M=$T/proj W=$T/www; git init -q -b main "$M"; mkdir -p "$M/.claude" "$W"
echo '{"chiefOfStaff": {"name": "Relay"}}' > "$M/.claude/commandeck.json"
printf 'window.DASH = %s;\n' "$(jq -cn --arg p "$M" '{home: "proj", projects: {proj: {path: $p}}}')" > "$W/data.js"
D() { (cd "$M" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" COMMANDECK_MAIN="$M" bash "$ROOT/scripts/decision.sh" "$@"); }
D add ship-1999-01-01 'Ship it?' yes main --options 'yes|no' >/dev/null; D add keys-1999-01-01 'Rotate the keys?' yes main >/dev/null
at() { D list | jq -r --arg id "$1" '.[] | select(.id == $id) | .askedAt'; }
OUT=$(env HOME="$T/home" COMMANDECK_RULING_LOG="$T/rulings.jsonl" python3 - "$P/scripts" "$W" "$(at ship-1999-01-01)" "$(at keys-1999-01-01)" "$T" <<'PY'
import functools, http.client, http.server, json, os, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
class Far(d.Handler):  # the same server as another machine on the network reaches it
    def setup(self):
        super().setup()
        self.client_address = ("192.0.2.7", 40000)
def serve(h):
    s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(h, directory=sys.argv[2]))
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s.server_address[1]
near, far = serve(d.Handler), serve(Far)
def req(port, method, path, body=None, origin=None):
    c = http.client.HTTPConnection("127.0.0.1", port)
    own = "127.0.0.1:%d" % port
    c.request(method, path, body and json.dumps(body), {"Content-Type": "application/json", "Host": own, "Origin": origin or "http://" + own})
    return c.getresponse().status
a = {"project": "proj", "id": "ship-1999-01-01", "askedAt": sys.argv[3], "answer": "no"}
print(req(far, "POST", "/answer", a), req(near, "POST", "/answer", a, "http://attacker.example"), req(near, "POST", "/answer", a), req(near, "POST", "/answer", a))
open(sys.argv[5] + "/no-send", "w").close()
print(req(near, "POST", "/answer", {"project": "proj", "id": "keys-1999-01-01", "askedAt": sys.argv[4], "answer": "not yet"}))
held = json.load(open(sys.argv[2] + "/answer-retry.json"))
os.remove(sys.argv[5] + "/no-send")
st = req(near, "GET", "/data.js")
while getattr(d, "RETRYING", threading.Lock()).locked():  # the refresh's retry runs off the request
    threading.Event().wait(0.05)
print(len(held), st, len(json.load(open(sys.argv[2] + "/answer-retry.json"))))
PY
)
check "another machine's POST and another site's are refused; the first loopback answer is taken, a second is refused" \
  "403 403 200 409" "$(sed -n 1p <<<"$OUT")"
check "the ledger row is answered" '"no"' "$(D list | jq -c '.[] | select(.id == "ship-1999-01-01") | .answer')"
RID=$(jq -r 'select(.question == "Ship it?") | .id' "$T/rulings.jsonl" 2>/dev/null)
check "the answer is logged as a ruling, by the ruling log's id form" 'yes dashboard no option' \
  "$([[ $RID =~ ^r-[0-9]{8}-[0-9]{6}-d-[0-9a-f]{6}$ ]] && echo yes) $(jq -r 'select(.question == "Ship it?") | "\(.source) \(.answer) \(.pick)"' "$T/rulings.jsonl" 2>/dev/null)"
check "main is told the answer and its ruling, and so is the relay" \
  "to-main.sh|question|ship-1999-01-01|no (ruling $RID)|
cos-tell.sh|--note|answered on the dashboard: ship-1999-01-01|no (ruling $RID)|" "$(head -2 "$T/sent")"
check "a failed send is kept for main and the relay, and sent again on the next refresh" "200
2 200 0" "$(sed -n '2,3p' <<<"$OUT")"
check "the resent messages are the failed answer's" 2 "$(grep -c 'keys-1999-01-01|not yet (ruling r-' "$T/sent")"

# The ledger row is closed before the sends, so a send that hangs past its timeout must still be kept for the next
# refresh: lost, a second answer gets 409 and nothing resends it. A refresh never waits on the resend: four kept sends
# that each hang to their timeout would hold the page's data.js for four timeouts, and an answer given meanwhile
# would wait behind them too. A retry batch stops at its first timeout, so one batch costs at most one.
# Main reads no inbox message while its own picker is open (to-main.sh says so): the reply names it, so the page
# can tell the owner to pick or press Esc there, and names no picker when to-main.sh saw none. The host keeps that
# word for the collector, a resent answer's too: the reply alone is lost to a send that only a refresh delivers.
# A later delivery to main that finds no picker open drops it.
cat > "$P/scripts/to-main.sh" <<EOF
#!/usr/bin/env bash
printf "%s|" "\${0##*/}" "\$@" >> "$T/tried"; echo >> "$T/tried"
[ ! -e "$T/no-send" ] || exit 1
case "\$*" in *hang-*) [ ! -e "$T/hang" ] || sleep 5 ;; esac
[ ! -e "$T/picker" ] || echo "to-main: sent to main (h), but its pane shows an open question or permission prompt: it reads this only after that prompt is answered in its own pane"
printf "%s|" "\${0##*/}" "\$@" >> "$T/sent"; echo >> "$T/sent"
EOF
cp "$P/scripts/to-main.sh" "$P/scripts/cos-tell.sh"
check "the stub's picker line is to-main.sh's own" 1 "$(grep -c 'but its pane shows an open question or permission prompt' "$ROOT/scripts/to-main.sh")"
for k in hang fast pick calm again; do D add $k-1999-01-01 "$k?" yes main --options 'yes|no' >/dev/null; done
OUT=$(env HOME="$T/home" COMMANDECK_RULING_LOG="$T/rulings.jsonl" python3 - "$P/scripts" "$W" "$(at hang-1999-01-01)" "$(at pick-1999-01-01)" "$(at calm-1999-01-01)" "$T" "$(at fast-1999-01-01)" "$(at again-1999-01-01)" <<'PY'
import functools, http.client, http.server, json, os, sys, threading, time
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
d.SEND_TIMEOUT = 1
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=s.serve_forever, daemon=True).start()
own = "127.0.0.1:%d" % s.server_address[1]
def req(method, path, body=None):
    c = http.client.HTTPConnection("127.0.0.1", s.server_address[1], timeout=30)
    c.request(method, path, body and json.dumps(body), {"Content-Type": "application/json", "Host": own, "Origin": "http://" + own})
    r = c.getresponse()
    return r.status, r.read()
held = lambda: [m["id"] for m in json.load(open(sys.argv[2] + "/answer-retry.json"))]
flag = lambda k: open(os.path.join(sys.argv[6], k), "w").close()
flag("hang")
st, body = req("POST", "/answer", {"project": "proj", "id": "hang-1999-01-01", "askedAt": sys.argv[3], "answer": "yes"})
print(st, json.loads(body).get("unsent"), held())
tries = lambda: sum("hang-1999-01-01" in l for l in open(os.path.join(sys.argv[6], "tried")))
def settled():  # the refresh's retry batch, run off the request, has finished
    for _ in range(600):
        if not d.RETRYING.locked():
            return
        time.sleep(0.05)
before, t0 = tries(), time.monotonic()
st = req("GET", "/data.js")[0]
print(st, time.monotonic() - t0 < 0.5, held())
t0 = time.monotonic()
st, body = req("POST", "/answer", {"project": "proj", "id": "fast-1999-01-01", "askedAt": sys.argv[7], "answer": "yes"})
print(st, json.loads(body).get("unsent"), time.monotonic() - t0 < 3)
settled()
print(tries() - before)
os.remove(os.path.join(sys.argv[6], "hang"))
req("GET", "/data.js")
settled()
print(held())
marks = lambda: [m["id"] for m in json.load(open(sys.argv[2] + "/answer-picker.json"))]
flag("picker")
print(json.loads(req("POST", "/answer", {"project": "proj", "id": "pick-1999-01-01", "askedAt": sys.argv[4], "answer": "yes"})[1]).get("picker"), marks())
os.remove(os.path.join(sys.argv[6], "picker"))
print(json.loads(req("POST", "/answer", {"project": "proj", "id": "calm-1999-01-01", "askedAt": sys.argv[5], "answer": "yes"})[1]).get("picker"), marks())
flag("no-send")
req("POST", "/answer", {"project": "proj", "id": "again-1999-01-01", "askedAt": sys.argv[8], "answer": "yes"})
os.remove(os.path.join(sys.argv[6], "no-send"))
flag("picker")
req("GET", "/data.js")
settled()
print(held(), marks())
PY
)
check "a send that hangs is kept for the next refresh, main's and the relay's" "200 2 ['hang-1999-01-01', 'hang-1999-01-01']" "$(sed -n 1p <<<"$OUT")"
check "a refresh whose resend hangs serves data.js at once, and keeps them" "200 True ['hang-1999-01-01', 'hang-1999-01-01']" "$(sed -n 2p <<<"$OUT")"
check "an answer given while a resend hangs is sent at once" "200 0 True" "$(sed -n 3p <<<"$OUT")"
check "a retry batch stops at its first send that times out" 1 "$(sed -n 4p <<<"$OUT")"
check "and the next refresh sends them" "[]" "$(sed -n 5p <<<"$OUT")"
check "main's open picker is named in the reply and kept for the collector; a delivery that finds none drops it" "True ['pick-1999-01-01']
False []" "$(sed -n 6,7p <<<"$OUT")"
check "a resent answer that finds main's picker open is kept for the collector" "[] ['again-1999-01-01']" "$(sed -n 8p <<<"$OUT")"

# The sends are kept before the ledger row closes: an answer whose sends cannot be kept (a full disk) and then fail
# would be lost, and the closed row refuses the next answer with 409. So that answer is refused and the row stays
# open; once the disk takes writes again the same answer is taken and its failed sends kept. An answer the ledger
# refuses leaves nothing kept: main is never told an answer that was not taken.
D add full-1999-01-01 'Full disk?' yes main --options 'yes|no' >/dev/null
OUT=$(env HOME="$T/home" COMMANDECK_RULING_LOG="$T/rulings.jsonl" python3 - "$P/scripts" "$W" "$(at full-1999-01-01)" "$T" "$M" <<'PY'
import errno, functools, http.client, http.server, json, os, subprocess, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
threading.Thread(target=s.serve_forever, daemon=True).start()
own = "127.0.0.1:%d" % s.server_address[1]
def req(body):
    c = http.client.HTTPConnection("127.0.0.1", s.server_address[1], timeout=30)
    c.request("POST", "/answer", json.dumps(body), {"Content-Type": "application/json", "Host": own, "Origin": "http://" + own})
    r = c.getresponse()
    return r.status, r.read()
held = lambda: [m["id"] for m in json.load(open(sys.argv[2] + "/answer-retry.json"))]
write = d.write
def full(directory, name, value):
    raise OSError(errno.ENOSPC, "No space left on device")
open(os.path.join(sys.argv[4], "no-send"), "w").close()
a = {"project": "proj", "id": "full-1999-01-01", "askedAt": sys.argv[3], "answer": "no"}
d.write = full
print(req(a)[0], held())
d.write = write
rows = subprocess.run(["bash", os.path.join(sys.argv[1], "decision.sh"), "list"], cwd=sys.argv[5], capture_output=True, text=True,
                      env=dict(os.environ, COMMANDECK_MAIN=sys.argv[5])).stdout
print(json.dumps([r.get("answer") for r in json.loads(rows) if r["id"] == "full-1999-01-01"]))
st, body = req(a)
print(st, json.loads(body).get("unsent"), held().count("full-1999-01-01"))
print(req(dict(a, answer="yes"))[0], held().count("full-1999-01-01"))
PY
)
rm -f "$T/no-send"
check "an answer whose sends cannot be kept is refused, and nothing is kept" "503 []" "$(sed -n 1p <<<"$OUT")"
check "its ledger row stays open" "[null]" "$(sed -n 2p <<<"$OUT")"
check "with the disk back, the same answer is taken and its failed sends kept" "200 2 2" "$(sed -n 3p <<<"$OUT")"
check "a second answer the ledger refuses keeps nothing more" "409 2" "$(sed -n 4p <<<"$OUT")"

# The sends are kept before the ledger takes the answer, so a host stopped in between, or one that cannot drop
# the sends of an answer the ledger refused, leaves sends for an answer that may never have been taken. A
# restarted host checks the ledger before it sends one: taken, it goes; refused, it is dropped; the row still
# open at that ask, it waits (a decision.sh the stopped host started may still take it).
D add stop-1999-01-01 'Stop here?' yes main --options 'yes|no' >/dev/null
D add took-1999-01-01 'Took it?' yes main --options 'yes|no' >/dev/null
D add late-1999-01-01 'Too late?' yes main --options 'yes|no' >/dev/null; D answer late-1999-01-01 yes >/dev/null
: > "$T/sent"
OUT=$(env HOME="$T/home" COMMANDECK_RULING_LOG="$T/rulings.jsonl" python3 - "$P/scripts" "$W" "$(at stop-1999-01-01)" "$(at took-1999-01-01)" "$(at late-1999-01-01)" "$T" "$M" <<'PY'
import errno, functools, http.client, http.server, json, os, subprocess, sys, threading, time
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(d.Handler, directory=sys.argv[2]))
s.handle_error = lambda *a: None  # the stopped host's traceback
threading.Thread(target=s.serve_forever, daemon=True).start()
own = "127.0.0.1:%d" % s.server_address[1]
def req(method, path, body=None):
    c = http.client.HTTPConnection("127.0.0.1", s.server_address[1], timeout=30)
    c.request(method, path, body and json.dumps(body), {"Content-Type": "application/json", "Host": own, "Origin": "http://" + own})
    try:
        return c.getresponse().status
    except http.client.RemoteDisconnected:
        return "stopped"
class Stop(Exception):
    pass
def stop(*a, **k):
    raise Stop()
def restart():  # a new host: nothing in flight; its first refresh runs a retry batch
    d.FLYING.clear()
    req("GET", "/data.js")
    for _ in range(600):
        if not d.RETRYING.locked():
            break
        time.sleep(0.05)
held = lambda: sorted({m["id"] for m in json.load(open(sys.argv[2] + "/answer-retry.json"))})
sent = lambda i: sum(i in l for l in open(sys.argv[6] + "/sent"))
ledger = lambda *a: subprocess.run(["bash", os.path.join(sys.argv[1], "decision.sh")] + list(a), cwd=sys.argv[7], capture_output=True,
                                   env=dict(os.environ, COMMANDECK_MAIN=sys.argv[7]))
run = d.subprocess.run
d.subprocess.run = stop  # stopped after the sends are kept, before decision.sh
print(req("POST", "/answer", {"project": "proj", "id": "stop-1999-01-01", "askedAt": sys.argv[3], "answer": "no"}))
d.subprocess.run = run
restart()
print(sent("stop-1999-01-01"), held())
ledger("answer", "stop-1999-01-01", "yes")  # answered in main's own pane
restart()
print(sent("stop-1999-01-01"), held())
log = d.log_ruling
d.log_ruling = stop  # stopped after the ledger took the answer, before the sends
print(req("POST", "/answer", {"project": "proj", "id": "took-1999-01-01", "askedAt": sys.argv[4], "answer": "no"}))
d.log_ruling = log
restart()
print(sent("took-1999-01-01|no (no ruling id: the dashboard host stopped before logging it)"), held())
write, writes = d.write, []
def full(*a):  # the disk fills between the keep and the drop
    writes.append(1)
    if len(writes) > 1:
        raise OSError(errno.ENOSPC, "No space left on device")
    write(*a)
d.write = full
print(req("POST", "/answer", {"project": "proj", "id": "late-1999-01-01", "askedAt": sys.argv[5], "answer": "no"}), held())
d.write = write
restart()
print(sent("late-1999-01-01"), held())
PY
)
check "a host stopped before the ledger took the answer" "stopped" "$(sed -n 1p <<<"$OUT")"
check "restarted, it sends nothing while the row is still open at that ask" "0 ['stop-1999-01-01']" "$(sed -n 2p <<<"$OUT")"
check "and drops the sends once the row is answered another way" "0 []" "$(sed -n 3p <<<"$OUT")"
check "a host stopped after the ledger took the answer" "stopped" "$(sed -n 4p <<<"$OUT")"
check "restarted, it sends that answer to main and the relay" "2 []" "$(sed -n 5p <<<"$OUT")"
check "an answer the ledger refused whose sends cannot be dropped" "409 ['late-1999-01-01']" "$(sed -n 6p <<<"$OUT")"
check "is never sent by a restarted host, and its sends are dropped" "0 []" "$(sed -n 7p <<<"$OUT")"

# Pass 2 kept sends without a key, and their ledger rows are already closed: an upgrade that drops them on its next
# write loses those answers for good. And a send that always times out must not starve the ones behind it: each
# batch stops at its first timeout, so the timed-out send goes to the back of the file.
mkdir -p "$T/retry"
OUT=$(python3 - "$ROOT/scripts" "$T/retry" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import dashboard_serve as d
D = sys.argv[2]
held = lambda: [m["id"] for m in json.load(open(D + "/answer-retry.json"))]
json.dump([{"main": "/project", "id": "old-1999-01-01", "to": "main", "args": ["question", "old-1999-01-01", "yes"]}], open(D + "/answer-retry.json", "w"))
print([m["id"] for m in d.kept(D)])
d.deliver = lambda directory, m: (False, False, False)
d.send(D, [{"main": "/project", "id": "new-1999-01-01", "to": "main", "args": ["question", "new-1999-01-01", "yes"]}])
print(held())
d.deliver = lambda directory, m: (True, False, False)
d.RETRYING.acquire(); d.retry(D)
print(held())
json.dump([{"main": "/project", "id": i, "to": "main", "args": [i], "key": i} for i in ("A", "B")], open(D + "/answer-retry.json", "w"))
tried = []
def deliver(directory, m):
    tried.append(m["id"])
    return (False, True, False) if m["id"] == "A" else (True, False, False)
d.deliver = deliver
for _ in range(3):
    d.RETRYING.acquire(); d.retry(D)
print(tried, held())
PY
)
check "a pass-2 send without a key is still kept" "['old-1999-01-01']" "$(sed -n 1p <<<"$OUT")"
check "and survives the next write" "['old-1999-01-01', 'new-1999-01-01']" "$(sed -n 2p <<<"$OUT")"
check "and leaves the file once delivered" "[]" "$(sed -n 3p <<<"$OUT")"
check "a send that always times out goes behind the rest, which are delivered" "['A', 'B', 'A', 'A'] ['A']" "$(sed -n 4p <<<"$OUT")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
