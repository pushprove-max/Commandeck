#!/usr/bin/env bash
# cos-watch-limit.sh [<percent>] -- waits until the dashboard's 7-day limit
# usage reaches a threshold (default 90), prints the line and exits, which
# wakes the Chief of Staff pane (run it in the background). The pane arms it
# again each time, so the percent it last told is kept in <state>/<project>.limit-told:
# it speaks again only a whole percent higher, or after usage fell back under
# the threshold (a new week).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/cos-lib.sh"
THRESHOLD=${1:-90}
poll() {
  python3 - "$COS_DATA" "$THRESHOLD" "$COS_KEY.limit-told" <<'EOF'
import json, os, re, sys
try:
    s = open(sys.argv[1]).read()
    # A project named __proto__ sits under a computed key (dashboard.sh): JSON again here.
    d = json.loads(re.sub(r'([{,])\["__proto__"\]:', r'\1"__proto__":', s[s.find('{'):s.rfind('}') + 1]))
    used = float(d['limit']['usedPct'])
except (OSError, ValueError, KeyError, TypeError):
    sys.exit(1)  # collector mid-write or field missing: try again next poll
told = sys.argv[3]
if used < float(sys.argv[2]):
    if os.path.exists(told): os.remove(told)
    sys.exit(1)
try: last = int(open(told).read())
except (OSError, ValueError): last = -1
if int(used) <= last:
    sys.exit(1)
open(told, 'w').write(str(int(used)))
print(f"7-day limit at {used:.0f}% (threshold {sys.argv[2]}%)")
EOF
}
cos_wait 60 poll
