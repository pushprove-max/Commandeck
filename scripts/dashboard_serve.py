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

One answer (issue 240): a `POST /answer` ({project, id, askedAt, answer}) answers an open decision from the
"Needs me" panel. The page every machine on the network loads is the same page, so a token in it would keep no
one out: only a loopback client, under a loopback Host name, with this page's own Origin, may answer. The answer
goes through `decision.sh answer --asked-at`, so the first answer wins and a second is refused (409); it is logged
as a ruling the way ruling-log.sh logs one, and sent to main (to-main.sh) and, with a relay configured, to the relay
(cos-tell.sh --note). The sends are kept in <directory>/answer-retry.json before the answer is recorded, and an
answer whose sends cannot be kept there is refused (503): main is never left untold. Until the ledger takes the answer
its sends keep the ask they answer, and one the host did not finish (stopped, or the ledger slow) is sent only once the
ledger shows that answer taken: main is never told one it refused. A send that fails stays kept and is sent again after the next
refresh, the page's next read of data.js, by a batch that refresh does not wait on; the collector lists what is still
kept on the card, with each send's tries, first try and last error (issue 295). A send whose main folder is gone or is
no longer a project here, or that has failed for an hour, gives up and is not sent again until the owner says so with
a `POST /unsent` ({key, action}: retry, delivered or drop), taken from the same clients as an answer. An answer delivered while main's own picker was open is kept in <directory>/answer-picker.json,
which the collector shows too: main reads it only after that picker is answered in its pane. The project's
folder is read from the collector's own data.js, never from the request.
A `POST /restart` from the same clients runs `dashboard.sh --restart`, once a minute at most (issue 294).
"""
import fcntl
import functools
import http.server
import ipaddress
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

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
    # Each build the owner folded (true) or unfolded (false): a running one by its unit name, a finished one by its commit.
    'builds': lambda v: id_map(v, lambda b: type(b) is bool),
}


# The host holds more cleared builds for a project than one save may name.
MAX_CLOSED = 2000
HELD = dict(CHECKS, closed=lambda v: ids(v, MAX_CLOSED))


def valid(layout, checks=CHECKS):
    return isinstance(layout, dict) and 'rev' in layout and all(k in checks and checks[k](v) for k, v in layout.items())


def held(path):
    """The file on disk as (home number, home layout, project slots), each value checked again as a save's is.
    Each slot keeps its own number as its `rev`.

    No file, or one no numbered save wrote, is number 0. One that is there but cannot be read raises OSError: a save
    on it would replace every slot it could not see.
    """
    try:
        with open(path) as f:
            disk = json.loads(f.read().partition('=')[2].strip().rstrip(';'))
    except (FileNotFoundError, ValueError):
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
    A log that is there but cannot be read raises OSError: a dropped name would read as new.
    """
    try:
        with open(log) as f:
            return {v for k, _, v in (line.rstrip('\n').partition('\t') for line in f) if k == key}
    except FileNotFoundError:
        return set()


HERE = os.path.dirname(os.path.abspath(__file__))
SENDS = threading.Lock()
STAMP = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')


def snapshot(directory):
    """The collector's data.js as a dict, or None. A project named __proto__ sits under a computed key there
    (dashboard.sh), which is not JSON: the plain key goes back first, as the relay watchers do, or one such project
    would make every other project's answer unreadable (issue 277)."""
    try:
        with open(os.path.join(directory, 'data.js')) as f:
            s = f.read().partition('=')[2].strip().rstrip(';')
        dash = json.loads(re.sub(r'([{,])\["__proto__"\]:', r'\1"__proto__":', s))
    except (OSError, ValueError):
        return None
    return dash if isinstance(dash, dict) else None


def project_path(directory, name):
    """The main checkout of the dashboard's project `name` (None: the home project), from the collector's data.js."""
    try:
        dash = snapshot(directory)
        path = dash['projects'][name if name is not None else dash['home']]['path']
    except (KeyError, TypeError):
        return None
    return path if isinstance(path, str) and os.path.isabs(path) else None


SCRIPT = {'main': 'to-main.sh', 'relay': 'cos-tell.sh'}
# SENDS guards the two files below and FLYING, the keys of the kept sends being tried now; no send runs under it.
FLYING = set()
RETRYING = threading.Lock()  # one retry batch at a time
RESTARTING = threading.Lock()


def kept(directory, strict=False):
    """The sends <directory>/answer-retry.json keeps, each {main, id, to, args, key[, ask]}; `ask` ({askedAt, answer})
    is the answer's, kept until the ledger takes it. A send pass 2 kept has no key:
    its content is one, the same on every read, and the next write keeps it. `strict`: a file that is there but
    cannot be read raises OSError, so a write never replaces sends it could not see."""
    try:
        with open(os.path.join(directory, 'answer-retry.json')) as f:
            ms = [m for m in json.load(f) if isinstance(m, dict) and m.get('to') in SCRIPT and isinstance(m.get('main'), str)
                  and isinstance(m.get('key', ''), str) and isinstance(m.get('args'), list) and all(isinstance(a, str) for a in m['args'])
                  and ('ask' not in m or isinstance(m['ask'], dict) and all(isinstance(m['ask'].get(k), str) for k in ('askedAt', 'answer')))]
    except FileNotFoundError:
        return []
    except OSError:
        if strict:
            raise
        return []
    except (ValueError, TypeError):
        return []
    for m in ms:
        m.setdefault('key', json.dumps(m, sort_keys=True))
    return ms


def marks(directory):
    """The answers <directory>/answer-picker.json keeps, each {main, id}: delivered while main's own picker was open.
    A file that is there but cannot be read raises OSError: its only caller writes it back."""
    try:
        with open(os.path.join(directory, 'answer-picker.json')) as f:
            return [m for m in json.load(f) if isinstance(m, dict) and isinstance(m.get('main'), str) and isinstance(m.get('id'), str)]
    except FileNotFoundError:
        return []
    except (ValueError, TypeError):
        return []


def write(directory, name, value):
    path = os.path.join(directory, name)
    tmp = '%s.%d.tmp' % (path, os.getpid())
    with open(tmp, 'w') as f:
        json.dump(value, f)
    os.replace(tmp, path)


SEND_TIMEOUT = 60
# to-main.sh's line for a pane whose own picker is open: main reads no inbox message until it is answered there.
PICKER = 'but its pane shows an open question or permission prompt'


def utc():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


# Issue 295: a send still failing an hour after its first try gives up, the same hour as the question alert
# (dashboard_alerts.jq), and waits for the owner: retried, marked delivered another way, or dropped (POST /unsent).
GIVE_UP = 3600


def deliver(directory, m):
    """One send with its script: (delivered, timed out, main's own picker open). The script's exit code and its last
    stderr line are left on m as lastExit and lastError, for settle()."""
    # to-main.sh exits 3 when main has no pane: the message is queued and shown first when main starts again.
    try:
        r = subprocess.run(['bash', os.path.join(HERE, SCRIPT[m['to']])] + m['args'], cwd=directory, env=dict(os.environ, COMMANDECK_MAIN=m['main']),
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=SEND_TIMEOUT)
    except subprocess.TimeoutExpired:
        m['lastExit'], m['lastError'] = None, 'no answer in %d s' % SEND_TIMEOUT
        return False, True, False
    except OSError as e:
        m['lastExit'], m['lastError'] = None, str(e)[:200]
        return False, False, False
    m['lastExit'], m['lastError'] = r.returncode, (r.stderr.strip().splitlines() or [''])[-1][:200]
    return r.returncode in ((0, 3) if m['to'] == 'main' else (0,)), False, m['to'] == 'main' and PICKER in r.stdout


def attempt(directory, m):
    """deliver(), unless the send can never go: then m['giveUp'] names why and nothing is sent. Its main folder is
    gone, or no longer a project in data.js (a data.js that cannot be read says nothing), or it has failed for an hour."""
    dash = snapshot(directory)
    paths = {p.get('path') for p in (dash.get('projects') or {}).values() if isinstance(p, dict)} if dash and isinstance(dash.get('projects'), dict) else None
    try:
        late = (datetime.now(timezone.utc) - datetime.strptime(m['firstAt'], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)).total_seconds() >= GIVE_UP
    except (KeyError, TypeError, ValueError):
        late = False
    m['giveUp'] = ('its main folder %s is gone' % m['main'] if not os.path.isdir(m['main'])
                   else '%s is not a project on this dashboard' % m['main'] if paths is not None and m['main'] not in paths
                   else 'not delivered in 1 h, last: %s' % (m.get('lastError') or 'exit %s' % m.get('lastExit')) if late else None)
    return (False, False, False) if m['giveUp'] else deliver(directory, m)


def settle(directory, taken, tried, slow=(), drop=()):
    """`taken` is out of flight again; the keys in `drop` leave the file; of `tried` ([(send, delivered, picker)]) the delivered leave it, those
    that timed out (keys in `slow`) go to its end so the next batch tries the rest first, and each
    delivery to main updates the picker marks: a picker open marks its answer, none open drops that main's marks.
    shortcut: a mark stays until a later delivery to that main finds no picker; read main's pane if that proves stale.
    A file that cannot be read or written keeps what it had: a delivered send may then go twice, which beats never.
    The marks are saved first: a delivered send is the only way to rebuild its mark.
    A send that failed keeps its count (`tries`), its first try (`firstAt`) and its last exit and stderr line; one
    attempt() gave up on is `state: "gave-up"` with its `reason`, and no refresh tries it again."""
    with SENDS:
        FLYING.difference_update(m['key'] for m in taken)
        gone = {m['key'] for m, ok, _ in tried if ok} | set(drop)
        failed = {m['key']: m for m, ok, _ in tried if not ok}
        try:
            held = marks(directory)
            for m, ok, picker in tried:
                if ok and m['to'] == 'main':
                    if not picker:
                        held = [p for p in held if p['main'] != m['main']]
                    elif {'main': m['main'], 'id': m['id']} not in held:
                        held.append({'main': m['main'], 'id': m['id']})
            left = [m for m in kept(directory, True) if m['key'] not in gone]
            for m in left:
                f = failed.get(m['key'])
                if f is None:
                    continue
                m.setdefault('firstAt', utc())
                if f.get('giveUp'):
                    m.update(state='gave-up', reason=f['giveUp'])
                else:
                    m.update(tries=m.get('tries', 0) + 1, lastExit=f.get('lastExit'), lastError=f.get('lastError'))
            write(directory, 'answer-picker.json', held)
            write(directory, 'answer-retry.json', [m for m in left if m['key'] not in slow] + [m for m in left if m['key'] in slow])
        except OSError:
            pass


def keep(directory, msgs, drop=()):
    """msgs written to the file, each in place of the kept send with its key or else at its end, and the keys in
    `drop` taken out. Raises OSError when the file cannot be read or written."""
    with SENDS:
        new = {m['key']: m for m in msgs}
        held = [new.pop(m['key'], m) for m in kept(directory, True) if m['key'] not in drop]
        write(directory, 'answer-retry.json', held + list(new.values()))


def send(directory, msgs):
    """Each message sent with its script, kept in the file until it is delivered. The number that failed, and
    whether main's own picker was open."""
    # Kept before the first try: the ledger row is already closed, so a send that hangs, or a server stopped
    # mid-send, must leave it for the next refresh. A send that timed out may have gone: twice beats never. A file
    # that cannot be written does not stop the sends: an answer's sends were kept before its row closed.
    with SENDS:
        for m in msgs:
            m.setdefault('key', secrets.token_hex(8))
        FLYING.update(m['key'] for m in msgs)
    try:
        keep(directory, msgs)
    except OSError:
        pass
    tried, slow = [], set()
    for m in msgs:
        ok, late, picker = attempt(directory, m)
        tried.append((m, ok, picker))
        if late:
            slow.add(m['key'])
    settle(directory, msgs, tried, slow)
    return sum(not ok for _, ok, _ in tried), any(p for _, _, p in tried)


def accepted(m):
    """For a send kept with its `ask`: True when the ledger holds that answer to that ask, False when it never will
    (the row is closed another way, corrected, or asked again), None while the row is still open at that ask."""
    rows = []
    try:
        with open(os.path.join(m['main'], '.claude', 'metrics', 'decisions.jsonl')) as f:
            fcntl.flock(f, fcntl.LOCK_SH)  # decision.sh appends under LOCK_EX
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if isinstance(r, dict) and r.get('id') == m['id']:
                    rows.append(r)
    except FileNotFoundError:
        return False
    except OSError:
        return None
    # Only the last row stands: a later --correct or reopen revokes the answer an earlier row took.
    ask, last = m['ask'], rows[-1] if rows else {}
    if last.get('askedAt') != ask['askedAt']:
        return False
    if last.get('answeredAt') is None:
        return None
    return last.get('answer') == ask['answer']


def retry(directory):
    """The kept sends not in flight, tried again in order; the batch stops at its first timeout, so one costs at most
    SEND_TIMEOUT and what follows waits for the next refresh. What still fails stays kept, a timed-out send behind the
    rest so it cannot starve them."""
    try:
        with SENDS:
            todo = [m for m in kept(directory) if m['key'] not in FLYING and m.get('state') != 'gave-up']
            FLYING.update(m['key'] for m in todo)
        tried, slow, drop = [], set(), set()
        for m in todo:
            if 'ask' in m:
                took = accepted(m)
                if took is False:
                    drop.add(m['key'])
                if not took:
                    continue
            ok, late, picker = attempt(directory, m)
            tried.append((m, ok, picker))
            if late:
                slow.add(m['key'])
                break
        settle(directory, todo, tried, slow, drop)
    finally:
        RETRYING.release()


def resend(directory):
    """A retry batch started off the request, so a refresh never waits on a send. A refresh while one runs starts none."""
    if os.path.exists(os.path.join(directory, 'answer-retry.json')) and RETRYING.acquire(blocking=False):
        threading.Thread(target=retry, args=(directory,), daemon=True).start()


def log_ruling(main, row, answer):
    """The answer as one ruling-log row (hooks/ruling-log.sh's form, source "dashboard"), its id or None."""
    now = datetime.now(timezone.utc)
    et = now.astimezone(ZoneInfo('America/New_York'))
    rid = 'r-%s-d-%s' % (et.strftime('%Y%m%d-%H%M%S'), secrets.token_hex(3))
    name = re.sub(r'[^A-Za-z0-9_.-]', '-', os.path.basename(main.rstrip('/'))) or 'unknown'
    log = os.environ.get('COMMANDECK_RULING_LOG') or os.path.join(os.path.expanduser('~'), '.claude', 'rulings', name + '.jsonl')
    options = row.get('options') if isinstance(row.get('options'), list) else []
    pick = 'recommended' if answer == row.get('proposedDefault') and answer in options else 'option' if answer in options else 'typed'
    line = json.dumps({'id': rid, 'utc': now.strftime('%Y-%m-%dT%H:%M:%SZ'), 'et': et.strftime('%Y-%m-%d %H:%M:%S %Z'), 'session': None,
                       'cwd': main, 'source': 'dashboard', 'question': row.get('question'), 'answer': answer, 'annotations': None, 'pick': pick})
    try:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, 'a') as f:
            # The lock ruling-log.sh holds for its appends (flock on the log itself).
            fcntl.flock(f, fcntl.LOCK_EX)
            f.write(line + '\n')
    except OSError:
        return None
    return rid


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
            if urlsplit(self.path).path == '/data.js':
                resend(self.directory)
            super().do_GET()

    def own_page(self):
        """A loopback client, under a loopback Host name, from this page's own Origin, with a JSON body."""
        host = self.headers.get('Host', '')
        try:
            name = urlsplit('//' + host).hostname or ''
            ip = ipaddress.ip_address(self.client_address[0].split('%')[0])
            near = ip.is_loopback or bool(getattr(ip, 'ipv4_mapped', None) and ip.ipv4_mapped.is_loopback)
        except ValueError:
            near = False
        return (near and name in LOOPBACK and not self.foreign()
                and self.headers.get('Origin') == 'http://' + host and self.headers.get('Content-Type') == 'application/json')

    def reply(self, code, value):
        out = json.dumps(value).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def restart(self):
        """POST /restart (issue 294): dashboard.sh --restart, which kills this server too, so the once-a-minute stamp
        is a file. No body is read and the command is fixed. The reply goes out first, so a failure is logged here."""
        stamp = os.path.join(self.directory, 'restart-at')
        with RESTARTING:  # the check and the stamp are one step: two requests at once restart once
            try:
                if time.time() - os.stat(stamp).st_mtime < 60:
                    return self.reply(429, 'restarted under a minute ago')
            except OSError:
                pass  # no stamp yet
            try:
                open(stamp, 'w').close()
            except OSError:
                return self.reply(500, 'could not write the restart stamp; not restarting')
        print('dashboard: restart requested from %s at %s' % (self.client_address[0], utc()), file=sys.stderr, flush=True)
        self.reply(202, 'restarting')
        self.wfile.flush()
        try:
            r = subprocess.run(['bash', os.path.join(HERE, 'dashboard.sh'), '--restart'], capture_output=True, text=True, timeout=30)
            if r.returncode:
                print('dashboard: restart FAILED (exit %d): %s' % (r.returncode, (r.stderr.strip().splitlines() or ['no message'])[0]), file=sys.stderr, flush=True)
        except subprocess.TimeoutExpired:
            print('dashboard: restart FAILED: dashboard.sh --restart did not finish in 30 s', file=sys.stderr, flush=True)
        except OSError as e:
            print('dashboard: restart FAILED: could not start dashboard.sh: %s' % e, file=sys.stderr, flush=True)

    def do_POST(self):
        if self.path == '/restart' and self.own_page():
            return self.restart()
        if self.path not in ('/answer', '/unsent') or not self.own_page():
            return self.send_error(403, "an answer is taken from this machine's own page only")
        length = self.headers.get('Content-Length', '')
        if not length.isdigit() or int(length) > MAX_BODY:
            return self.send_error(413)
        try:
            a = json.loads(self.rfile.read(int(length)))
        except ValueError:
            return self.send_error(400)
        if self.path == '/unsent':
            return self.unsent(a)
        text = lambda k, ok: isinstance(a.get(k), str) and ok(a[k])
        if not (isinstance(a, dict) and set(a) <= {'project', 'id', 'askedAt', 'answer'} and text('id', ID.match) and text('askedAt', STAMP.match)
                and text('answer', lambda s: s.strip() and len(s) <= 2000 and not re.search(r'[\x00-\x1f\x7f]', s))
                and (a.get('project') is None or text('project', PROJECT.match))):
            return self.send_error(400)
        main = project_path(self.directory, a.get('project'))
        if not main:
            return self.send_error(404, "no such project on this dashboard")
        msgs = [{'main': main, 'id': a['id'], 'to': 'main', 'args': ['question', a['id']]}]
        try:
            with open(os.path.join(main, '.claude', 'commandeck.json')) as f:
                relay = json.load(f).get('chiefOfStaff', {}).get('name')
        except (OSError, ValueError, AttributeError):
            relay = None
        if relay:
            msgs.append({'main': main, 'id': a['id'], 'to': 'relay', 'args': ['--note', 'answered on the dashboard: %s' % a['id']]})
        # The sends are kept, in flight so no retry batch tries them, before the row closes: once it closes a second
        # answer is refused, so sends that could not be kept and then failed would be lost for good. Their ask lets a
        # later batch tell an answer the ledger took from one it never did.
        for m in msgs:
            m['key'] = secrets.token_hex(8)
            m['ask'] = {'askedAt': a['askedAt'], 'answer': a['answer']}
            m['args'].append('%s (no ruling id: the dashboard host stopped before logging it)' % a['answer'])
        with SENDS:
            FLYING.update(m['key'] for m in msgs)
        try:
            keep(self.directory, msgs)
        except OSError as e:
            with SENDS:
                FLYING.difference_update(m['key'] for m in msgs)
            return self.send_error(503, "not answered: main could not be told for sure, %s cannot be written (%s)"
                                   % (os.path.join(self.directory, 'answer-retry.json'), e.strerror or e))
        try:
            r = subprocess.run(['bash', os.path.join(HERE, 'decision.sh'), 'answer', a['id'], a['answer'], '--asked-at', a['askedAt']], cwd=self.directory,
                               env=dict(os.environ, COMMANDECK_MAIN=main), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            r = None
        if r is None or r.returncode != 0:
            # A refused answer's sends are dropped; a drop that cannot be written, or a timeout (decision.sh killed
            # before or after its append), leaves them to a retry batch, which sends them only if the ledger took it.
            if r is not None:
                try:
                    keep(self.directory, [], {m['key'] for m in msgs})
                except OSError:
                    pass
            with SENDS:
                FLYING.difference_update(m['key'] for m in msgs)
            if r is None:
                return self.send_error(504, "the ledger took no answer in 60 s; refresh: a question gone from the list was answered, and main is told on a later refresh")
            why = r.stderr.strip().splitlines()[-1:] or ['the answer was not recorded']
            code = 409 if re.search(r'already answered|reopened after', why[0]) else 404 if 'unknown decision' in why[0] else 500
            return self.send_error(code, why[0])
        row = json.loads(r.stdout.strip().splitlines()[-1])
        rid = log_ruling(main, row, a['answer'])
        for m in msgs:
            m['args'][-1] = '%s (%s)' % (a['answer'], 'ruling %s' % rid if rid else 'no ruling id: the ruling log could not be written')
        unsent, picker = send(self.directory, msgs)
        self.reply(200, {'ruling': rid, 'unsent': unsent, 'picker': picker})

    def unsent(self, a):
        """Issue 295: the owner's word on one kept send ({key, action}): `retry` puts it back to pending with its count
        and first try cleared and starts a retry batch; `delivered` (main got it another way) and `drop` remove it.
        Each action is one line in <directory>/answer-retry.log: time, key, decision id, action, client."""
        if not (isinstance(a, dict) and set(a) == {'key', 'action'} and isinstance(a['key'], str) and a['action'] in ('retry', 'delivered', 'drop')):
            return self.send_error(400)
        with SENDS:
            if a['key'] in FLYING:
                return self.send_error(409, 'that send is being tried now; refresh and try again')
            try:
                ms = kept(self.directory, True)
                m = next((m for m in ms if m['key'] == a['key']), None)
                if m is None:
                    return self.send_error(404, 'no such unsent answer')
                if a['action'] == 'retry':
                    for k in ('state', 'reason', 'tries', 'firstAt', 'lastExit', 'lastError'):
                        m.pop(k, None)
                else:
                    ms.remove(m)
                write(self.directory, 'answer-retry.json', ms)
            except OSError as e:
                return self.send_error(503, 'not changed: %s' % (e.strerror or e))
            try:
                with open(os.path.join(self.directory, 'answer-retry.log'), 'a') as f:
                    f.write('\t'.join((utc(), a['key'], str(m.get('id')), a['action'], self.client_address[0])) + '\n')
            except OSError:
                pass
        if a['action'] == 'retry':
            resend(self.directory)
        self.reply(200, {'action': a['action']})

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
        # The lock file is shared with dashboard.sh --import, another process writing the same layout.
        with SAVING, open(path + '.lock', 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
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
