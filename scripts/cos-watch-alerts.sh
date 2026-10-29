#!/usr/bin/env bash
# cos-watch-alerts.sh -- waits until the dashboard lists an active alert, the
# machine's or this project's, that the Chief of Staff has not seen yet, prints
# it and exits, which wakes the pane (run it in the background).
# Seen ids live in <state>/<project>.alerts-seen; this watcher appends each id it prints (and the pane may add one).
# A stage alert, and a Builder's quiet alert (id builder-...-quiet-<time>), are never printed. <state>/<project>.alerts-told holds "<fingerprint>
# <epoch>" for each time this watcher printed one.
# --seed: every alert id open now goes into the seen file, told now, and the script exits: run once at a switch from
# another watcher, so the alerts the owner already knows of raise nothing (issue 292).
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
SEEN=$COS_KEY.alerts-seen
touch "$SEEN"
poll() {
  python3 - "$COS_DATA" "$SEEN" "$PP_PROJECT" "$COS_KEY.alerts-told" "${1:-}" <<'EOF'
import json, re, sys, time
data, seen_path, project, told_path, mode = sys.argv[1:6]
try:
    s = open(data).read()
    # A project named __proto__ sits under a computed key (dashboard.sh): JSON again here.
    d = json.loads(re.sub(r'([{,])\["__proto__"\]:', r'\1"__proto__":', s[s.find('{'):s.rfind('}') + 1]))
except (OSError, ValueError):
    sys.exit(1)  # collector mid-write or missing: try again next poll
# The dashboard is every project's: another project's alert is its own Chief of
# Staff's. One with no project (a limit, the host) is the machine's and is told.
alerts = [a for a in d.get('alerts') or [] if a.get('id') and a.get('project') in (None, project)]
# An id ends with the time its condition began (limit-claude-1791717824), which
# the collector keeps only while the condition shows on every collect
# (dashboard.sh alerts()): one that flaps, or an input missing for one collect,
# comes back under a new stamp. So the id without its stamp is the alert's
# fingerprint, and a fingerprint already told is told again once 24 h have
# passed since this watcher last told it (Alertmanager's repeat_interval, at
# 24 h), whether its stamp moved or not: one that stays on keeps its id.
def split(i):
    m = re.search(r'-(\d{9,})$', i)
    return (i[:m.start()], int(m.group(1))) if m else (i, None)
seen = set(open(seen_path).read().split())
newest = {}
for k, t in map(split, seen):
    if t is not None:
        newest[k] = max(t, newest.get(k, t))
told = {}
try:
    for line in open(told_path):
        k, _, t = line.rpartition(' ')
        if t.strip().isdigit():
            told[k] = max(int(t), told.get(k, 0))
except OSError:
    pass
now = int(time.time())
if mode == '--seed':
    # Told now too: seen alone, an alert whose stamp is a day old would be told again at the next poll.
    with open(seen_path, 'a') as f:
        f.write(''.join(a['id'] + '\n' for a in alerts if a['id'] not in seen))
    with open(told_path, 'a') as f:
        f.write(''.join(f"{split(a['id'])[0]} {now}\n" for a in alerts))
    print('cos-watch-alerts: seeded %d open alert ids into %s' % (len(alerts), seen_path))
    sys.exit(0)
def is_new(i):
    k, t = split(i)
    if i not in seen and k not in newest:
        return True
    # A state from before the told record: the newest stamp seen stands for the last tell.
    last = told.get(k, newest.get(k))
    return last is None or now - last >= 86400
# A stage alert (its id names no stage) and a Builder's quiet alert are the dashboard's to show, never a wake (issue 461).
def wakes(i):
    k = split(i)[0]
    return not (k.startswith('stage-') or (k.startswith('builder-') and k.endswith('-quiet')))
new = [a for a in alerts if wakes(a['id']) and is_new(a['id'])]
if not new:
    sys.exit(1)
try:
    with open(told_path, 'a') as f:
        f.write(''.join(f"{split(a['id'])[0]} {now}\n" for a in new))
except OSError:
    pass  # the owner is told all the same; the newest seen stamp stands in for this tell
# Printed is seen: the next poll, under this stamp or a later one, is quiet until 24 h pass since the told record (issue 461).
try:
    with open(seen_path, 'a') as f:
        f.write(''.join(a['id'] + '\n' for a in new))
except OSError:
    pass  # the owner is told all the same; the told record keeps the next poll quiet for 24 h
for a in new:
    row = json.dumps(a)  # issue 290: cut at 1,500 characters, with a pointer
    print(row if len(row) <= 1500 else row[:1500] + ' ...[cut; full row: the dashboard data.js alerts]')
EOF
}
if [ "${1-}" = --seed ]; then poll --seed || { echo "cos-watch-alerts: cannot read $COS_DATA; nothing seeded" >&2; exit 1; }; exit 0; fi
cos_wait 60 poll
