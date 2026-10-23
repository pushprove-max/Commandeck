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

The login (issue 263), on only when the bind is not loopback (a loopback bind serves as above, with no login): the
server speaks HTTPS only, every route but GET/HEAD/POST /login needs a session or a trusted device (a page without
one is sent to /login with 302, a write is refused with 401), and `/answer`, `/unsent` and `/restart` then take any
logged-in client, not loopback alone. One user, an scrypt hash in dashboard-auth.json (env COMMANDECK_DASHBOARD_AUTH,
default ~/.commandeck/dashboard-auth.json, outside the served folder) and the self-signed certificate in
dashboard-tls/ beside it. Command line, run by the owner:
  dashboard_serve.py make-cert [--force]    the certificate, once (825 days)
  dashboard_serve.py set-password <user>    the password (asked twice, 8 characters or more); ends every session, keeps devices
  dashboard_serve.py has-password           exits 0 when a password is stored, 1 when not
  dashboard_serve.py devices                trusted devices: id, label, created
  dashboard_serve.py revoke <id>|all        end a device (`all`: every device and every session)
Sessions live in memory (a restart logs them out); a trusted device lasts a year and survives a restart.
"""
import fcntl
import functools
import getpass
import hashlib
import hmac
import http.cookies
import http.server
import io
import ipaddress
import json
import os
import re
import secrets
import socket
import ssl
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


# Issue 263: the login. The store and the certificate sit beside each other, outside the served folder.
AUTH = os.environ.get('COMMANDECK_DASHBOARD_AUTH') or os.path.expanduser('~/.commandeck/dashboard-auth.json')
TLS = os.path.join(os.path.dirname(AUTH), 'dashboard-tls')
CERT, KEY = os.path.join(TLS, 'cert.pem'), os.path.join(TLS, 'key.pem')
# The only routes a caller without a login may use. Every other method and path is behind authed().
PUBLIC = frozenset({('GET', '/login'), ('HEAD', '/login'), ('POST', '/login')})
NO_PASSWORD = 'no dashboard password: run dashboard_serve.py set-password <user>'
# scrypt N=2^14, r=8, p=5: an OWASP password-storage configuration (16 MiB, inside hashlib.scrypt's default cap).
SCRYPT = {'n': 2 ** 14, 'r': 8, 'p': 5}
USER = re.compile(r'^[A-Za-z0-9._-]{1,40}$')
MIN_PASSWORD = 8
SESSION_TTL, DEVICE_TTL = 43200, 31536000  # the cookies' max-age, enforced here as well
LOCK_AFTER, LOCK_WINDOW = 5, 900  # failed logins, and the seconds they count over and the lockout lasts
MAX_LOGIN_BODY = 4096
# One lock holds the lockout check, the scrypt compare and the failure record together, so parallel attempts cannot
# pass the count. Sessions: sha256(cookie) -> {exp, epoch, device}; memory only, so a restart logs them out.
LOGIN = threading.Lock()
SESSIONS = {}
FAILS = []
LOCKED = [0.0]
LOGIN_PAGE = b'''<!doctype html><meta charset=utf-8><title>Commandeck dashboard login</title>
<form id=f><p><input name=user placeholder=user autocomplete=username required>
<p><input name=password type=password placeholder=password autocomplete=current-password required>
<p><label><input name=trust type=checkbox> Trust this device</label> <input name=label placeholder="device label" maxlength=40>
<p><button>Log in</button> <span id=m></span></form>
<script>f.onsubmit = async e => {
  e.preventDefault(); const d = new FormData(f);
  const r = await fetch('/login', {method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({user: d.get('user'), password: d.get('password'), trust: !!d.get('trust'), label: d.get('label')})});
  if (r.ok) location = '/'; else m.textContent = await r.text();
};</script>
'''


def sha(token):
    return hashlib.sha256(token.encode()).hexdigest()


def read_store():
    try:
        with open(AUTH) as f:
            store = json.load(f)
        return store if isinstance(store, dict) else {}
    except (OSError, ValueError):
        return {}


def change_store(fn):
    """Every read-modify-write of the store, here and in the CLI, runs under one flock and is written temp-then-rename,
    mode 0600; returns what fn(store) returns."""
    os.makedirs(os.path.dirname(AUTH), mode=0o700, exist_ok=True)
    with os.fdopen(os.open(AUTH + '.lock', os.O_CREAT | os.O_RDWR, 0o600)) as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        store = read_store()
        store.setdefault('epoch', 0)
        store.setdefault('devices', {})
        out = fn(store)
        tmp = '%s.%d.tmp' % (AUTH, os.getpid())
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as f:
            json.dump(store, f)
        os.replace(tmp, AUTH)
    return out


def device_ok(device, now):
    """A trusted device is good for DEVICE_TTL from its creation, however long its cookie is kept."""
    try:
        made = datetime.strptime(device['created'], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
        return now < made.timestamp() + DEVICE_TTL
    except (KeyError, ValueError, TypeError):
        return False


def password_ok(store, user, password):
    """Always one scrypt, so a wrong user costs what a wrong password does; both compares are constant-time."""
    try:
        salt, want = bytes.fromhex(store['salt']), bytes.fromhex(store['hash'])
        got = hashlib.scrypt(password.encode(), salt=salt, dklen=len(want), **{k: store[k] for k in SCRYPT})
        return hmac.compare_digest(got, want) & hmac.compare_digest(user.encode(), str(store.get('user')).encode())
    except (KeyError, ValueError, TypeError):
        return False


def cookie(name, value, ttl):
    return '%s=%s; HttpOnly; Secure; SameSite=Strict; Path=/; max-age=%d' % (name, value, ttl)


def ask(prompt):
    return getpass.getpass(prompt) if sys.stdin.isatty() else sys.stdin.readline().rstrip('\n')


def cli_make_cert(force):
    if os.path.exists(CERT) and not force:  # not an error: dashboard.sh --install runs this every time
        print('certificate kept: %s (--force makes a new one)' % CERT)
        return
    host = re.sub(r'[^A-Za-z0-9-]', '', socket.gethostname().split('.')[0]) or 'localhost'
    os.makedirs(TLS, mode=0o700, exist_ok=True)
    old = os.umask(0o077)
    try:
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes', '-days', '825',
                        '-keyout', KEY, '-out', CERT, '-subj', '/CN=%s.local' % host,
                        '-addext', 'subjectAltName=DNS:%s.local,DNS:localhost,IP:127.0.0.1' % host],
                       check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as e:
        sys.exit('openssl could not make the certificate: %s' % (getattr(e, 'stderr', None) or e))
    finally:
        os.umask(old)
    print('certificate for %s.local, localhost and 127.0.0.1 in %s (825 days)' % (host, TLS))


def cli_set_password(user):
    if not USER.match(user):
        sys.exit('usage: dashboard_serve.py set-password <user>   (letters, digits, . _ -; up to 40)')
    pw = ask('password: ')
    if len(pw) < MIN_PASSWORD:
        sys.exit('the password must be at least %d characters' % MIN_PASSWORD)
    if ask('again: ') != pw:
        sys.exit('the two passwords differ')
    salt = os.urandom(16)
    # The epoch moves, so every session ends, including ones made from a device; the devices stay (`revoke all` ends them).
    change_store(lambda s: s.update(user=user, salt=salt.hex(), epoch=s['epoch'] + 1, **SCRYPT,
                                    hash=hashlib.scrypt(pw.encode(), salt=salt, dklen=32, **SCRYPT).hex()))
    print('password set for %s' % user)


def cli_devices():
    for i, d in sorted(read_store().get('devices', {}).items(), key=lambda x: str(x[1].get('created'))):
        print('%s\t%s\t%s' % (i, d.get('label'), d.get('created')))


def cli_revoke(which):
    def revoke(store):
        if which == 'all':
            store.update(devices={}, epoch=store['epoch'] + 1)  # the epoch ends sessions made without a device too
        elif which in store['devices']:
            del store['devices'][which]
        else:
            return False
        return True
    if not change_store(revoke):
        sys.exit('no such device: %s' % which)


class Handler(http.server.SimpleHTTPRequestHandler):
    loopback_only = True
    login_on = False  # set from the bind: on a network bind every route but /login needs a login

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

    def public(self):
        return self.login_on and (self.command, urlsplit(self.path).path) in PUBLIC

    def authed(self):
        """A live session (unexpired, made under the store's current epoch, and its device, if any, still trusted) or a
        trusted device cookie that has not outlived DEVICE_TTL. The store is read per request, so a revoke or a new
        password takes effect on the next one."""
        store, now = read_store(), time.time()
        devices = store.get('devices') if isinstance(store.get('devices'), dict) else {}
        if not store.get('hash'):
            return False
        try:
            jar = http.cookies.SimpleCookie(self.headers.get('Cookie', ''))
        except http.cookies.CookieError:
            return False
        if 'pp_session' in jar:
            s = SESSIONS.get(sha(jar['pp_session'].value))
            if s and now < s['exp'] and s['epoch'] == store.get('epoch') and (
                    s['device'] is None or (isinstance(devices.get(s['device']), dict) and device_ok(devices[s['device']], now))):
                return True
        if 'pp_device' in jar:
            h = sha(jar['pp_device'].value)
            return any(isinstance(d, dict) and d.get('sha') == h and device_ok(d, now) for d in devices.values())
        return False

    def gate(self, head=False):
        """With the login on: the login page for a public route, 302 to it for a page, 401 for a write; True when the
        request is answered here."""
        if not self.login_on:
            return False
        if self.public():
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(LOGIN_PAGE)))
            self.end_headers()
            if not head:
                self.wfile.write(LOGIN_PAGE)
            return True
        if self.authed():
            return False
        if self.command in ('GET', 'HEAD'):
            self.send_response(302)
            self.send_header('Location', '/login')
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            self.reply(401, 'log in first')
        return True

    def do_GET(self):
        if self.gate():
            return
        if self.foreign():
            self.send_error(403, "the dashboard answers its own page only")
        else:
            if urlsplit(self.path).path == '/data.js':
                resend(self.directory)
            super().do_GET()

    def own_page(self):
        """A loopback client, under a loopback Host name, from this page's own Origin, with a JSON body. With the login
        on, any client that is logged in (the caller has checked) from this page's own https Origin."""
        host = self.headers.get('Host', '')
        try:
            name = urlsplit('//' + host).hostname or ''
            ip = ipaddress.ip_address(self.client_address[0].split('%')[0])
            near = ip.is_loopback or bool(getattr(ip, 'ipv4_mapped', None) and ip.ipv4_mapped.is_loopback)
        except ValueError:
            near = False
        return ((self.login_on or (near and name in LOOPBACK)) and not self.foreign()
                and self.headers.get('Origin') == ('https://' if self.login_on else 'http://') + host
                and self.headers.get('Content-Type') == 'application/json')

    def login(self):
        """POST /login {user, password, trust, label}. The lockout check, the scrypt compare and the failure record
        happen under one lock; no password or token reaches a log or a reply body."""
        if not self.own_page():
            return self.send_error(403)
        length = self.headers.get('Content-Length', '')
        if not length.isdigit() or int(length) > MAX_LOGIN_BODY:
            return self.send_error(413)
        try:
            body = json.loads(self.rfile.read(int(length)))
        except ValueError:
            return self.send_error(400)
        label = body.get('label', '') if isinstance(body, dict) else None
        if not (isinstance(body, dict) and isinstance(body.get('user'), str) and isinstance(body.get('password'), str)
                and isinstance(body.get('trust'), bool) and isinstance(label, str) and len(label) <= 40 and label.isprintable()):
            return self.send_error(400)
        with LOGIN:
            now = time.time()
            store = read_store()
            if not store.get('hash'):
                return self.reply(503, NO_PASSWORD)
            if now < LOCKED[0]:
                return self.reply(429, 'too many failed logins: try again in 15 minutes')
            if not password_ok(store, body['user'], body['password']):
                FAILS[:] = [t for t in FAILS if now - t < LOCK_WINDOW] + [now]
                if len(FAILS) >= LOCK_AFTER:
                    LOCKED[0], FAILS[:] = now + LOCK_WINDOW, []
                return self.reply(401, 'wrong user or password')
            FAILS.clear()
            cookies, device, epoch = [], None, store.get('epoch')
            if body['trust']:
                token, device = secrets.token_urlsafe(32), secrets.token_hex(6)
                created = datetime.fromtimestamp(now, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

                def add(s):
                    # A set-password or revoke-all since the check above means the password checked may be the old one.
                    if s['epoch'] != epoch:
                        return None
                    s['devices'][device] = {'sha': sha(token), 'label': label or 'device', 'created': created}
                    return epoch
                if change_store(add) is None:
                    return self.reply(401, 'the password changed: log in again')
                cookies.append(cookie('pp_device', token, DEVICE_TTL))
            session = secrets.token_urlsafe(32)
            for k in [k for k, v in SESSIONS.items() if v['exp'] <= now]:
                del SESSIONS[k]
            SESSIONS[sha(session)] = {'exp': now + SESSION_TTL, 'epoch': epoch, 'device': device}
            cookies.append(cookie('pp_session', session, SESSION_TTL))
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', '2')
        for c in cookies:
            self.send_header('Set-Cookie', c)
        self.end_headers()
        self.wfile.write(b'ok')

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
        if self.public():
            return self.login()
        if self.gate():
            return
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
        if self.gate(head=True):
            return
        if self.foreign():
            self.send_error(403, "the dashboard answers its own page only")
        else:
            super().do_HEAD()

    def do_PUT(self):
        if self.gate():
            return
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


def serve(port, bind, directory):
    Handler.loopback_only = bind in ("127.0.0.1", "localhost", "::1")
    Handler.login_on = not Handler.loopback_only
    # An IPv6 address (::1, ::) needs an IPv6 socket; the default is IPv4 only.
    family = socket.AF_INET6 if ":" in bind else socket.AF_INET
    attrs = {"address_family": family}
    if Handler.login_on:
        if not (os.path.exists(CERT) and os.path.exists(KEY)):
            sys.exit("no certificate: run dashboard_serve.py make-cert")
        Handler.timeout = 30  # a client that stalls (or never finishes the TLS handshake) frees its thread

        def quiet(self, request, client_address):
            # A client that cannot finish the TLS handshake (plain HTTP, a scanner) or goes quiet is noise, not a fault.
            if not isinstance(sys.exc_info()[1], (ssl.SSLError, ConnectionError, TimeoutError)):
                http.server.ThreadingHTTPServer.handle_error(self, request, client_address)
        attrs.update(request_queue_size=128, handle_error=quiet)  # the default queue of 5 drops a burst of TLS connections
    server = type("Server", (http.server.ThreadingHTTPServer,), attrs)((bind, port), functools.partial(Handler, directory=directory))
    if Handler.login_on:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(CERT, KEY)
        # The handshake runs in each request's own thread: done at accept(), one silent client would stop the whole server.
        server.socket = ctx.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
    server.serve_forever()


if __name__ == "__main__":
    cmd, args = (sys.argv[1:2] or [""])[0], sys.argv[2:]
    if cmd == "make-cert":
        cli_make_cert("--force" in args)
    elif cmd == "set-password" and len(args) == 1:
        cli_set_password(args[0])
    elif cmd == "has-password":
        sys.exit(0 if read_store().get("hash") else 1)
    elif cmd == "devices":
        cli_devices()
    elif cmd == "revoke" and len(args) == 1:
        cli_revoke(args[0])
    elif cmd.isdigit() and len(args) == 2:
        serve(int(cmd), args[0], args[1])
    else:
        sys.exit("usage: dashboard_serve.py <port> <bind> <directory> | make-cert [--force] | set-password <user> | has-password | devices | revoke <id>|all")
