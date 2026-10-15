#!/usr/bin/env python3
"""dashboard_serve.py <port> <bind> <directory> -- serve the dashboard's files.

The snapshot is a script file, data.js, and a plain file server hands a script
to any web page that names it in a <script> tag: the owner's decisions and
task text would be readable by whatever page the browser has open. So a
request a browser marks as coming from another site is refused, and so is one
whose page is not this server's own. Served to the network over plain HTTP a
browser sends no such mark, so there a request that names no page at all is
given the page itself and nothing else. On a loopback bind a request under any
other host name is refused too (a name rebound to 127.0.0.1); on a LAN bind,
the owner's choice, the machine's names are not known here and are not checked.

One write: a `PUT /layout` from the dashboard's own page saves the owner's
panel layout as <directory>/layout.js (`window.DASH_LAYOUT = {...};`), which
index.html loads before app.js, so every browser shows the same layout. The
path is fixed, the body is checked value by value and written whole, and any
other method or path is refused. The host numbers each save (`rev`): a save
names the number of the layout it was made over and is refused with 409 and
the number held when that is not the one on disk, so a save that arrives late
cannot undo a newer one. A save that names a `project` lands in that
project's slot of the same file (`projects[<name>]`); one that names none is
the home project's, kept at the top. The name is a key and never a path.
Each slot has its own number, so a save on one project refuses none on another.
The same save appends each newly cleared build to <directory>/closed.log, the
uncut history that tells a stale tab's replay from a new clear.
Every file is served `no-cache`, so a browser revalidates the page's code
instead of guessing it is fresh.
"""
import functools
import http.server
import ipaddress
import json
import os
import re
import socket
import sys
import threading
from urllib.parse import urlsplit

SAVING = threading.Lock()
MAX_BODY = 16384
ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')
HEIGHTS = ('auto', 'half', 'tall')
# A project's name as the collector cleans it (hooks/lib/project.sh). `__proto__` as a plain key in a script
# would set the object's prototype, so that one project keeps no layout on the host.
PROJECT = re.compile(r'^(?!\.+$|__proto__$)[A-Za-z0-9_.-]{1,80}$')
MAX_PROJECTS = 200


def ids(v, most=200):
    return isinstance(v, list) and len(v) <= most and all(isinstance(x, str) and ID.match(x) for x in v)


def id_map(v, ok):
    return isinstance(v, dict) and len(v) <= 200 and all(isinstance(k, str) and ID.match(k) and ok(x) for k, x in v.items())


# One check per key the page saves (app.js LAYOUT), and the number of the layout the save was made over.
# An unknown key refuses the whole write.
CHECKS = {
    'rev': lambda v: type(v) is int and 0 <= v < 2 ** 53,
    'project': lambda v: isinstance(v, str) and bool(PROJECT.match(v)),
    'order': ids, 'hidden': ids, 'closed': ids, 'collapsed': ids,
    'sizes': lambda v: id_map(v, lambda n: type(n) is int and 1 <= n <= 4),
    # A preset, or the whole number of pixels a panel was dragged to (app.js PX_MIN, PX_MAX).
    'heights': lambda v: id_map(v, lambda h: (type(h) is str and h in HEIGHTS) or (type(h) is int and 60 <= h <= 4000)),
}


# The host holds more cleared builds for a project than one save may name.
MAX_CLOSED = 2000
HELD = dict(CHECKS, closed=lambda v: ids(v, MAX_CLOSED))


def valid(layout, checks=CHECKS):
    return isinstance(layout, dict) and 'rev' in layout and all(k in checks and checks[k](v) for k, v in layout.items())


def held(path):
    """The file on disk as (home number, home layout, project slots), each value checked again as a save's is.
    Each slot keeps its own number as its `rev`.

    No file, or one no numbered save wrote, is number 0.
    """
    try:
        with open(path) as f:
            disk = json.loads(f.read().partition('=')[2].strip().rstrip(';'))
    except (OSError, ValueError):
        disk = None
    disk = disk if isinstance(disk, dict) else {}
    part = lambda d: {k: v for k, v in d.items() if k not in ('rev', 'project') and k in HELD and HELD[k](v)}
    num = lambda d: d.get('rev') if CHECKS['rev'](d.get('rev')) else 0
    slots = disk.get('projects') if isinstance(disk.get('projects'), dict) else {}
    slots = {k: dict(part(v), rev=num(v)) for k, v in slots.items() if CHECKS['project'](k) and isinstance(v, dict) and valid(dict(v, rev=0), HELD)}
    return num(disk), part(disk), slots


def cleared(log, key):
    """Every build the host dropped from one slot's cleared list ('' is the home project's): closed.log, a
    `<slot>\\t<name>` line each. Unlike the layout it is never cut, so it grows by one short line per drop.
    """
    try:
        with open(log) as f:
            return {v for k, _, v in (line.rstrip('\n').partition('\t') for line in f) if k == key}
    except OSError:
        return set()


LOOPBACK = ("127.0.0.1", "localhost", "::1")
# The names this machine goes by on its network.
# A name from other DNS (a tailnet's) is refused unless the owner listed it:
# COMMANDECK_DASHBOARD_HOSTS, comma separated, set by setup.sh --hosts.
_HOST = socket.gethostname().lower()
OWN = {_HOST, _HOST.split(".")[0], _HOST.split(".")[0] + ".local"}
OWN |= {n.strip().lower() for n in os.environ.get("COMMANDECK_DASHBOARD_HOSTS", "").split(",") if n.strip()}


class Handler(http.server.SimpleHTTPRequestHandler):
    loopback_only = True

    def foreign(self):
        site = self.headers.get("Sec-Fetch-Site")
        if site not in (None, "same-origin", "none"):
            return True
        host = self.headers.get("Host", "")
        page = self.headers.get("Origin") or self.headers.get("Referer")
        if page and urlsplit(page).netloc != host:
            return True
        try:
            name = urlsplit("//" + host).hostname or ""
        except ValueError:
            return True
        if name in LOOPBACK:
            return False
        if self.loopback_only:
            return True
        # Plain HTTP to a network address carries no Sec-Fetch-Site, and a page
        # that asks for no referrer names none: another site's <script> tag
        # then looks like this. The dashboard's own page always names itself.
        if site is None and not page and urlsplit(self.path).path not in ("/", "/index.html"):
            return True
        # Served to the network: any other name is one another site pointed at
        # this address (DNS rebinding). An address cannot be rebound.
        try:
            ipaddress.ip_address(name)
            return False
        except ValueError:
            return name not in OWN

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def do_GET(self):
        if self.foreign():
            self.send_error(403, "the dashboard answers its own page only")
        else:
            super().do_GET()

    def do_HEAD(self):
        if self.foreign():
            self.send_error(403, "the dashboard answers its own page only")
        else:
            super().do_HEAD()

    def do_PUT(self):
        length = self.headers.get('Content-Length', '')
        # A JSON content type makes a browser ask first (a preflight this server never answers), so another
        # site's page cannot send this from the owner's browser.
        if self.foreign() or self.path != '/layout' or self.headers.get('Content-Type') != 'application/json':
            return self.send_error(403)
        if not length.isdigit() or int(length) > MAX_BODY:
            return self.send_error(413)
        try:
            layout = json.loads(self.rfile.read(int(length)))
        except ValueError:
            return self.send_error(400)
        if not valid(layout):
            return self.send_error(400)
        path = os.path.join(self.directory, 'layout.js')
        log = os.path.join(self.directory, 'closed.log')
        tmp = '%s.%d.tmp' % (path, os.getpid())
        # One save at a time: every request thread shares the temporary file, and the number read is the number
        # written over. The number saved is the host's own next one, never a caller's.
        name = layout.pop('project', None)
        with SAVING:
            rev, home, slots = held(path)
            if name is not None and name not in slots and len(slots) >= MAX_PROJECTS:
                return self.send_error(400)
            # The number checked is the named slot's own, so a save on one project refuses none on another.
            slot = home if name is None else slots.get(name, {})
            now = rev if name is None else slot.get('rev', 0)
            saved = layout.pop('rev') == now
            if saved:
                # A cleared build stays cleared, in the order this host first saw each: a save adds the names never
                # seen and never moves or drops a held one, so a tab replaying old names, a save that names none
                # and a Reset layout change nothing. Past MAX_CLOSED the host drops its own oldest from the layout;
                # closed.log keeps every name it dropped, so a dropped one replayed by a stale tab is not new.
                was = slot.get('closed', [])
                key = name or ''
                seen = cleared(log, key)
                added = [u for u in dict.fromkeys(layout.get('closed', [])) if u not in was and u not in seen]
                closed = (was + added)[-MAX_CLOSED:]
                if closed:
                    layout['closed'] = closed
                # The names this save drops are written down before the layout is replaced: a save whose append
                # fails does not land, so a dropped name never reads as new; one whose layout write fails has
                # logged only names it was dropping, never one it was adding.
                with open(log, 'ab+') as f:
                    # An append cut off mid-record left no final newline: end that record first, or this one joins it.
                    end = f.seek(0, os.SEEK_END)
                    f.seek(max(end - 1, 0))
                    torn = end > 0 and f.read(1) != b'\n'
                    dropped = ''.join('%s\t%s\n' % (key, u) for u in (was + added)[:-MAX_CLOSED] if u not in seen)
                    f.write((('\n' if torn else '') + dropped).encode())
                if name is None:
                    home, rev = layout, rev + 1
                else:
                    slots[name] = dict(layout, rev=now + 1)
                out = dict(home, rev=rev, **({'projects': slots} if slots else {}))
                with open(tmp, 'w') as f:
                    # ensure_ascii keeps the file plain ASCII; "<" cannot appear in a checked value.
                    f.write('window.DASH_LAYOUT = %s;\n' % json.dumps(out, sort_keys=True))
                os.replace(tmp, path)
        if not saved:
            body = json.dumps({'rev': now}).encode()
            self.send_response(409)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):  # request lines would flood dashboard.log
        pass


if __name__ == "__main__":
    port, bind, directory = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    Handler.loopback_only = bind in ("127.0.0.1", "localhost", "::1")
    # An IPv6 address (::1, ::) needs an IPv6 socket; the default is IPv4 only.
    family = socket.AF_INET6 if ":" in bind else socket.AF_INET
    server = type("Server", (http.server.ThreadingHTTPServer,), {"address_family": family})
    server((bind, port), functools.partial(Handler, directory=directory)).serve_forever()
