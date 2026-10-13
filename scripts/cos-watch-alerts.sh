#!/usr/bin/env bash
# cos-watch-alerts.sh -- waits until the dashboard lists an active alert, the
# machine's or this project's, that the Chief of Staff has not seen yet, prints
# it and exits, which wakes the pane (run it in the background).
# Seen ids live in <state>/<project>.alerts-seen; the pane appends an id once
# the owner has been told.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
SEEN=$COS_KEY.alerts-seen
touch "$SEEN"
poll() {
  python3 - "$COS_DATA" "$SEEN" "$PP_PROJECT" <<'EOF'
import json, re, sys
data, seen_path, project = sys.argv[1:4]
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
# the collector keeps while the condition lasts (dashboard.sh alerts()): the
# whole id is one episode, and the condition coming back is a new id.
seen = set(open(seen_path).read().split())
new = [a for a in alerts if a['id'] not in seen]
if not new:
    sys.exit(1)
for a in new:
    print(json.dumps(a))
EOF
}
cos_wait 60 poll
