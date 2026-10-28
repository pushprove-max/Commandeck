#!/usr/bin/env bash
# plan-check.sh [--batch-only] <plan file | - | ''> <batch or ''> [<label>] -- the plan and batch checks of a Builder
# launch, in one home (issue 384): builder-launch.sh runs them before a Builder opens, and seat.sh runs them before
# every launch of a plan judge that certifies the plan, so no judging round is spent on a fault the launcher refuses
# in seconds. `-` reads the plan text on stdin; '' is a plan-less (Skip) batch; '' as the batch is a judge with no
# batch found, whose plan's own checks still run. The label names the plan in every message (default: the plan path).
# With a batch: Prior art and Data design (the batch's own). With a plan or a Skip batch: What can go wrong (the
# batch's or the plan's); with a plan, its size line, a Test: line under each Decisions and Accepted failure modes item,
# and its Mockup: lines (issue 392); with either, no line that describes placeholder UI (issue 400); last, with a plan,
# its Facts citations (issue 427) and its budget (issue 426). --batch-only runs the batch checks alone.
# A relative Mockup: path resolves against the plan file's checkout, or PLAN_CHECK_ROOT (default: this folder's
# checkout) for stdin.
# Pass: prints "size <files> <lines>" when a plan was read, exit 0. Fault: the first REFUSED: line on stderr, exit 2.
# Writes nothing.
set -uo pipefail
USAGE="usage: plan-check.sh [--batch-only] <plan file | - | ''> <batch or ''> [<label>]"
case "${1:-}" in --help|-h) echo "$USAGE"; exit 0 ;; esac
ONLY=0
[ "${1-}" != --batch-only ] || { ONLY=1; shift; }
[ $# -ge 2 ] && [ $# -le 3 ] || { echo "$USAGE" >&2; exit 2; }
SRC=$1 BATCH=$2 PLAN=${3-}
refuse() { echo "REFUSED: $1" >&2; exit 2; }
PT= PROOT=
case $SRC in
  '') ;;
  -) PT=$(cat; echo .) PT=${PT%.}; PLAN=${PLAN:-the plan}; PROOT=${PLAN_CHECK_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)} ;;
  *) [ -f "$SRC" ] && [ -r "$SRC" ] || refuse "cannot read $SRC"
     PT=$(cat -- "$SRC"; echo .) PT=${PT%.}; PLAN=${PLAN:-$SRC}
     PROOT=$(git -C "$(dirname -- "$SRC")" rev-parse --show-toplevel 2>/dev/null) || PROOT=$(dirname -- "$SRC") ;;
esac
BT=
if [ -n "$BATCH" ]; then
  [ -f "$BATCH" ] && [ -r "$BATCH" ] || refuse "cannot read $BATCH"
  BT=$(cat -- "$BATCH"; echo .) BT=${BT%.}
fi
# has_section <heading, lower case> -- reads a text on stdin: the section of that name holds a line of its own beyond the
# template's guidance (the paragraph that starts "Required:") and any <placeholder> line.
has_section() { awk -v h="$1" '/^#+[[:space:]]/ { on = tolower($0) ~ ("^#+[[:space:]]+" h "([[:space:]:]|$)"); req = 0; next } !on { next }
  /^Required:/ { req = 1 } /^[[:space:]]*$/ { req = 0; next } !req && !/<[^>]*>/ { ok = 1 } END { exit !ok }'; }
if [ -n "$BATCH" ]; then
  # Every batch says which standard governs it, what library or service already does it, and why we build if we do.
  grep -qiE '^#+[[:space:]]+Prior art' <<<"$BT" || refuse "$BATCH has no Prior art section (a '## Prior art' heading): name the governing standard and the library or service the project's .claude/paved-road.md approves, and why we build instead if we do"
  # Issue 341: every batch states its data design; "none: <why>" is an answer. A batch with no Data design heading is
  # refused like an empty one (issue 362: the 0.46.0 exception for batches written before the heading existed is gone).
  has_section 'data design' <<<"$BT" \
    || refuse "$BATCH has no Data design section (a '## Data design' heading with a line under it): for each piece of state the batch adds or changes, say where it lives, who writes it, who reads it, when it resets and what a retry runs; or 'none: <why no state is added or changed>'"
fi
[ "$ONLY" = 0 ] || exit 0
# Issue 398: a plan or batch that states existing placeholder UI as context carried it on as a fact into the next brief.
# Issue 400: as on the host, such a line (placeholder copy, or a literal always-disabled control in a tag) is refused
# unless it sits in a fenced block, is a Placeholder: line, or cites the issue that tracks it (#<n>).
. "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/screen-code.sh"
. "$(dirname "${BASH_SOURCE[0]}")/fence.sh"
refuse_placeholders() { # <label> <text>
  local n cands fenced
  cands=$({ grep -inE "$PLACEHOLDER_COPY" <<<"$2" | cut -d: -f1; always_disabled_lines <<<"$2"; } | sort -nu)
  fenced=$(awk "$PP_AWK_FENCE"'fence($0) || flen { print NR }' <<<"$2")
  # The loop runs in this shell, not behind a pipe, so refuse's exit 2 ends the script.
  for n in $cands; do
    ! grep -qx "$n" <<<"$fenced" || continue
    ! sed -n "${n}p" <<<"$2" | grep -qE '^[[:space:]]*(- )?Placeholder: |#[0-9]+' || continue
    refuse "$1 line $n describes placeholder UI: plan its removal, approve it on a Placeholder: line, or cite the issue that tracks it (#<n>)"
  done
}
[ -z "$SRC" ] || refuse_placeholders "$PLAN" "$PT"
[ -z "$BATCH" ] || refuse_placeholders "$BATCH" "$BT"
# Issue 362: what the plan and the batch must hold before a Builder opens. A list of what can go wrong (the batch's or the
# plan's) is what every reviewer and fix round works from; the plan's size line is what a small NO-GO plan is judged by;
# every top-level item under its Decisions or Accepted failure modes names the test that checks it (or says none, why).
# A Skip batch has no plan: its own list is the only one.
{ [ -n "$BATCH" ] && has_section 'what can go wrong' <<<"$BT"; } || { [ -n "$SRC" ] && has_section 'what can go wrong' <<<"$PT"; } \
  || refuse "neither ${BATCH:-the batch (none found)} nor ${PLAN:-its plan (none: a Skip batch)} has a What can go wrong section with cases under it (a '## What can go wrong' heading): limits (empty, tiny, huge, cut off mid-way), timing (two actions or replies in either order, retries, timeouts) and odd data (special characters, missing fields, duplicates, old shapes), one named test per case"
[ -n "$SRC" ] || exit 0
# Lines inside a fenced block (fence.sh's rule: backticks or tildes, indented or not) are never the plan's own.
facts=$(awk "$PP_AWK_FENCE"'function flush() { if (item != "" && !has) print "untested " substr(item, 1, 60); item = ""; has = 0 }
  fence($0) || flen { next } {
    if ($0 ~ /^#+[ \t]/) { flush(); sec = ($0 ~ /^##[ \t]+(Decisions|Accepted failure modes)/) }
    else if (sec && $0 ~ /^([0-9]+\.|[-*])[ \t]/) { flush(); item = $0; has = ($0 ~ /Test:/) }
    else if (sec && item != "" && $0 ~ /Test:/) has = 1
    if ($0 ~ /^[-*] Planned size: ~?[0-9]+ files?, ~?[0-9]+ (changed )?lines?/) { s = $0; gsub(/~/, "", s); split(s, a, /[^0-9]+/); print "size " a[2] " " a[3] }
    if ($0 ~ /^Mockup:[ \t]*[^ \t]/) { m = $0; sub(/^Mockup:[ \t]*/, "", m); sub(/[ \t].*$/, "", m); gsub(/`/, "", m); print "mockup " m }
  } END { flush() }' <<<"$PT")
SIZE=$(awk '$1 == "size" { print $2, $3; exit }' <<<"$facts")
[ -n "$SIZE" ] || refuse "$PLAN has no size line outside a fenced block: a bullet '- Planned size: <n> files, <n> changed lines'"
untested=$(sed -n 's/^untested /  - /p' <<<"$facts")
[ -z "$untested" ] || { printf 'REFUSED: %s has decisions or accepted failure modes with no Test: line (a Test: line naming the test that checks it, or Test: none, <reason>):\n%s\n' "$PLAN" "$untested" >&2; exit 2; }
# Issue 392: a plan names each mockup on a Mockup: line. The Builder's brief is the template plus the whole batch, so a
# mockup the batch does not carry never reaches the Builder; a named file must exist. A URL is not fetched. With no
# batch (a judge with none found) only the file check runs.
while read -r _ M; do
  [ -n "$M" ] || continue
  [ -z "$BATCH" ] || grep -qF -- "$M" <<<"$BT" \
    || refuse "$PLAN names the mockup $M (a Mockup: line) and $BATCH does not carry it: the batch is the Builder's brief, so name the mockup there"
  case $M in http://*|https://*) continue ;; /*) F=$M ;; *) F=$PROOT/$M ;; esac
  [ -f "$F" ] && [ -s "$F" ] || refuse "$PLAN names the mockup $M, which does not exist ($F)"
done < <(grep '^mockup ' <<<"$facts")
# Owner's answer: a plan in the format before 0.55.0 (no Goal: line, no Steps and no Facts section outside a fence)
# still passes, with a warning; a plan with any of the three is checked in full.
if ! awk "$PP_AWK_FENCE"'fence($0) || flen { next } /^Goal:/ || /^##[ \t]+(Steps|Facts)[ \t]*$/ { f = 1 } END { exit !f }' <<<"$PT"; then
  echo "WARNING: $PLAN is in the plan format before 0.55.0, so its Facts and budget were not checked: rewrite it with one Goal: line, a ## Steps section and a ## Facts section" >&2
  echo "size $SIZE"; exit 0
fi
# Issues 426 and 427 run last, so every earlier refusal keeps its priority. A check that cannot run refuses with
# "not run"; it never passes.
command -v python3 >/dev/null || refuse "$PLAN Facts and budget: check not run -- python3 is missing"
# Both read fences by fence.sh's one rule, as every other plan check does: these line numbers are never the plan's own.
export PC_FENCED; PC_FENCED=$(awk "$PP_AWK_FENCE"'fence($0) || flen { print NR }' <<<"$PT" | paste -sd' ' -)
# Issue 427: every fact a plan states sits in `## Facts`, one bullet each, `- <claim> -- <path>:<n>[-<m>][, ...]
# (observed: YYYY-MM-DD)`, and each citation resolves here, before a judge spends a round on a dead one: a file under the
# plan's checkout (never another plan), lines inside it, a real date not after today.
[ -d "$PROOT" ] || refuse "$PLAN Facts: check not run -- no checkout root ($PROOT)"
out=$(PC_PLANTEXT=$PT python3 -I - "$PROOT" "$PLAN" <<'PY'
import datetime, os, re, sys
root, label = os.path.realpath(sys.argv[1]), sys.argv[2]
fenced = set(map(int, os.environ['PC_FENCED'].split()))
facts, seen, comment, inside = [], False, False, False
for n, line in enumerate(os.environ['PC_PLANTEXT'].split('\n'), 1):
    if n in fenced:
        continue
    if comment or line.lstrip().startswith('<!--'):
        comment = '-->' not in line
        continue
    if re.match(r'#+[ \t]', line):
        inside = re.match(r'##[ \t]+Facts[ \t]*$', line) is not None
        seen = seen or inside
    elif inside and re.match(r'[-*][ \t]', line):
        facts.append(line[2:].strip())
    elif inside and facts and re.match(r'[ \t]+\S', line):
        facts[-1] += ' ' + line.strip()
bad = []
if not seen:
    bad.append('no ## Facts section: one bullet per fact, `- <claim> -- <path>:<n>[-<m>] (observed: YYYY-MM-DD)`')
elif not facts:
    bad.append('## Facts has no bullet under it')
today = datetime.date.today()
for fact in facts:
    m = re.search(r'\s--\s+(.+?)\s+\(observed:\s*([^)]*)\)\s*$', fact)
    if not m:
        bad.append('Facts: %s -- no `-- <path>:<n>` citation or no `(observed: YYYY-MM-DD)`' % fact[:80])
        continue
    for cite in (c.strip().strip('`') for c in m.group(1).split(',')):
        c = re.fullmatch(r'(\S+?):(\d+)(?:-(\d+))?', cite)
        if not c:
            bad.append('Facts: %s -- not <path>:<n>[-<m>]' % cite)
            continue
        path, first = c.group(1), int(c.group(2))
        last = int(c.group(3) or first)
        full = os.path.realpath(os.path.join(root, path))
        if not full.startswith(root + os.sep) or not os.path.isfile(full):
            bad.append('Facts: %s -- no such file under %s' % (cite, root))
            continue
        if os.path.relpath(full, root).startswith('.claude/plans/') or '.claude/plans/' in path:
            bad.append('Facts: %s -- cites a plan; cite the code or doc it describes' % cite)
            continue
        with open(full, 'rb') as f:
            data = f.read()
        count = data.count(b'\n') + (1 if data and not data.endswith(b'\n') else 0)
        if first < 1 or last < first or last > count:
            bad.append('Facts: %s -- lines %d-%d are not inside the file (%d lines)' % (cite, first, last, count))
    try:
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', m.group(2).strip()):
            raise ValueError
        seen_on = datetime.date.fromisoformat(m.group(2).strip())
    except ValueError:
        bad.append('Facts: observed: %s -- not a calendar date YYYY-MM-DD' % m.group(2))
        continue
    if seen_on > today:
        bad.append('Facts: observed: %s -- after today (%s)' % (m.group(2).strip(), today))
for b in bad:
    print('REFUSED: %s %s' % (label, b))
sys.exit(2 if bad else 0)
PY
) || { [ -n "$out" ] || out="REFUSED: $PLAN Facts: check not run -- python3 failed"; printf '%s\n' "$out" >&2; exit 2; }
# Issue 426: the plan budget. One `Goal:` line of at most 200 characters; a `## Steps` section of one-line steps
# `- new|modify|delete <path>[ ~<line>] -- <what>`; prose (a line that is not structure, wrapped or not) only under
# `## Why`; each `##` section under its byte cap. The caps are the 75th percentile of a sample of real plans, rounded
# up to 100 bytes; text above the first `##` heading and an unlisted section take the other cap.
out=$(PC_PLANTEXT=$PT python3 -I - "$PLAN" <<'PY'
import os, re, sys
label = sys.argv[1]
CAPS = [('Why', 1200), ('Prior art', 1600), ('Data design', 5500), ('What can go wrong', 9000),
        ('Decisions already made', 8300), ('Question for the owner', 700), ('Assumptions', 2300), ('What exists', 1600),
        ('Cuts', 10700), ('Not in this unit', 700), ('Accepted failure modes', 1100), ('Stated limits', 600),
        ('Acceptance test', 3200), ('Verification', 1600), ('Routing', 700), ('How this will be reviewed', 1100),
        ('Claims to falsify', 1600), ('Plan change log', 5300), ('Author self-check', 800), ('Facts', 4000),
        ('Steps', 2000)]
OTHER = 2000
# Lines the plan-author spec in seat.sh requires word for word: an empty What can go wrong, and the opening of
# `## Stated limits`. plan-check-budget.test.sh proves each entry is in seat.sh; add none that is not.
SENTINELS = ('checked, none',
             '(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)')
# A key may hold an apostrophe: seat.sh's plan-author spec opens every plan with an `Owner's words:` line.
KEY = re.compile(r"[A-Za-z][\w/()`'-]*( [\w/()`'-]+){0,4}:( |$)")
STEP = re.compile(r'- (new|modify|delete) \S+( ~\d+(-\d+)?)? -- \S')
def cap_of(name):
    for key, cap in CAPS:
        if name.lower().startswith(key.lower()):
            return key, cap
    return name or 'the text above the first section', OTHER
lines = os.environ['PC_PLANTEXT'].split('\n')
fenced = set(map(int, os.environ['PC_FENCED'].split()))
bad, sizes, order = [], {}, []
sec, comment, listed, goals, steps = '', False, False, [], None
for n, line in enumerate(lines, 1):
    if n not in fenced and re.match(r'##[ \t]', line):
        sec = line[2:].strip()
        order.append(sec)
    sizes[sec] = sizes.get(sec, 0) + len(line.encode()) + 1
    if n in fenced:
        continue
    if comment or line.lstrip().startswith('<!--'):
        comment = '-->' not in line
        continue
    if line.startswith('Goal:'):
        goals.append(n)
    if re.match(r'#+[ \t]', line):
        listed = False
        if re.match(r'##[ \t]+Steps[ \t]*$', line):
            steps = 0
        continue
    if not line.strip() or sec.lower().startswith('why'):
        continue
    if sec == 'Steps':
        if STEP.match(line):
            steps += 1
        else:
            bad.append('## Steps line %d is not one step `- new|modify|delete <path>[ ~<line>] -- <what>` on one line' % n)
        continue
    item = re.match(r'[ \t]*([-*+]|\d+[.)])[ \t]', line) is not None
    cont = listed and line[0] in ' \t'
    if item or cont:
        listed = True
        continue
    listed = False
    if re.match(r'[ \t]*[|>]', line) or KEY.match(line) or line.strip() in SENTINELS:
        continue
    bad.append('line %d under %s is prose: prose goes under ## Why; elsewhere use a list item, a table row or a one-line Key: value' % (n, sec and '## ' + sec or 'the title'))
if not goals:
    bad.append('has no Goal: line (one line, at most 200 characters)')
elif len(goals) > 1:
    bad.append('has %d Goal: lines (lines %s); one only' % (len(goals), ', '.join(map(str, goals))))
else:
    g = goals[0]
    if len(lines[g - 1]) > 200:
        bad.append('Goal: line %d is %d characters, cap 200' % (g, len(lines[g - 1])))
    nxt = lines[g] if g < len(lines) else ''
    if nxt.strip() and not (re.match(r'#+[ \t]', nxt) or KEY.match(nxt)):
        bad.append('Goal: line %d runs onto line %d; the goal is one line' % (g, g + 1))
if steps is None:
    bad.append('has no ## Steps section (one-line steps `- new|modify|delete <path>[ ~<line>] -- <what>`)')
elif steps == 0:
    bad.append('## Steps has no step under it')
for name in [''] + order:
    key, cap = cap_of(name)
    if sizes.get(name, 0) > cap:
        bad.append('section %s is %d bytes, cap %d' % (name and '## ' + name or key, sizes[name], cap))
for b in bad:
    print('REFUSED: %s %s' % (label, b))
sys.exit(2 if bad else 0)
PY
) || { [ -n "$out" ] || out="REFUSED: $PLAN budget: check not run -- python3 failed"; printf '%s\n' "$out" >&2; exit 2; }
echo "size $SIZE"
