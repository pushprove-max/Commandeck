#!/usr/bin/env bash
# One headless roles.audit-verifier session per area verifies that area's findings, 4 at a time, from an empty folder.
# It has read tools only, so nothing it reads can make it change the code or a report; this script saves its final
# message as the verdict file.
# Called by run-audit.sh, which sets A (the scratch folder), HERE (this folder) and VERIFIER_ARGV (the role's command).
set -euo pipefail
A=${A:?run-audit.sh sets A} HERE=${HERE:?run-audit.sh sets HERE} VERIFIER_ARGV=${VERIFIER_ARGV:?run-audit.sh sets VERIFIER_ARGV}
COMMIT=$(cat "$A/commit.txt")
# As in run.sh: a failed verifier leaves no output, nor one without the counts line or a row for each finding,
# and an area whose audit failed gets no verifier.
# The verdict check, outside one(): bash 5.2 cannot re-read an exported function whose here-document is followed by
# `||`, so xargs children would get no one().
read -r -d '' CHECK <<'PY' || true
import json, re, sys
audit, log, out = sys.argv[1:]
v = json.load(open(log)).get('result') or ''
want = re.findall(r'^\s*\|\s*(\d+-\d+)\s*\|', open(audit).read(), re.M)
if len(set(want)) < len(want):
    sys.exit('the audit names one finding id twice, so one verdict row would answer for both')
# | ID | Claimed | Verdict | Severity now | Duplicate | Evidence |, every cell filled (evidence may hold a |).
rows = {}
for line in v.splitlines():
    c = [x.strip().strip('*`').strip() for x in line.strip().strip('|').split('|')]
    if c[0] in want:
        rows[c[0]] = c
n = {'CONFIRMED': 0, 'PARTLY': 0, 'REFUTED': 0, 'dup': 0}
bad = []
for i in want:
    c = rows.get(i, [])
    m = len(c) >= 6 and all(c[:5]) and '|'.join(c[5:]).strip('| ') and re.match(r'(CONFIRMED|PARTLY|REFUTED)\b', c[2])
    if not (m and re.match(r'P[0-3]\b', c[3]) and re.match(r'(new|#?\d+)\b', c[4], re.I)):
        bad.append(i)
        continue
    n[m.group(1)] += 1
    n['dup'] += c[4].lower() != 'new'
got = re.search(r'confirmed=(\d+) partly=(\d+) refuted=(\d+) duplicates=(\d+)', v)
if bad or not got or tuple(map(int, got.groups())) != (n['CONFIRMED'], n['PARTLY'], n['REFUTED'], n['dup']):
    sys.exit(f'verdict has no full row for: {" ".join(bad) or "-"}; its counts line must be '
             f'confirmed={n["CONFIRMED"]} partly={n["PARTLY"]} refuted={n["REFUTED"]} duplicates={n["dup"]}')
open(out, 'w').write(v)
PY
one() {
  id=$1
  d="$A/vrun/$id"; mkdir -p "$d"
  rm -f "$A/verify/$id.md"
  [ -s "$A/out/$id.md" ] || { echo "$id skipped: no audit output"; return 1; }
  sed -e "s#{{SLICE}}#$id#g" -e "s#{{COMMIT}}#$COMMIT#g" -e "s#{{A}}#$A#g" "$HERE/VERIFY.template.md" > "$d/PROMPT.md"
  local -a verifier; mapfile -t verifier <<<"$VERIFIER_ARGV"
  (cd "$d" && env "${verifier[@]}" "Read $d/PROMPT.md and do exactly what it says." \
    --setting-sources "" --disable-slash-commands --strict-mcp-config --no-session-persistence \
    --tools Read,Grep,Glob --allowedTools Read,Grep,Glob --add-dir "$A" --output-format json > "$A/vlogs/$id.json" 2>&1)
  rc=$?
  [ "$rc" != 0 ] || python3 -c "$CHECK" "$A/out/$id.md" "$A/vlogs/$id.json" "$A/verify/$id.md" || rc=1
  [ "$rc" = 0 ] || rm -f "$A/verify/$id.md"
  echo "$id exit=$rc $( [ -s "$A/verify/$id.md" ] && wc -c < "$A/verify/$id.md" || echo MISSING) $(date +%H:%M)"
  return "$rc"
}
export -f one; export A HERE COMMIT VERIFIER_ARGV CHECK
cut -f1 "$A/slices.tsv" | grep -v '^\s*$' | tr '\n' '\0' | xargs -0 -n 1 -P 4 bash -c 'one "$1"' _
echo ALL-DONE
