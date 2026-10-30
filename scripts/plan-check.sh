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
# plan-check.sh --issue-cases <n> -- the cases issue n's own text names, one per line `<Fix|Done|Body> <k> <first 80
# chars>` (issue 444): a top-level list item outside a fence under a `## Fix...` or `## Done means` heading, a section
# with no such item being one case, and the whole body the one Body section when the issue has neither (md_items.py,
# the Markdown reader). A failed or slow gh read, or a list shape the reader does not know, is
# `REFUSED: issue #<n> cases: check not run`, exit 2: it never reads as an issue with fewer cases.
set -uo pipefail
USAGE="usage: plan-check.sh [--batch-only] <plan file | - | ''> <batch or ''> [<label>]"
case "${1:-}" in --help|-h) echo "$USAGE"; exit 0 ;; esac
issue_cases() { # <n>
  local body out err
  [[ $1 =~ ^[0-9]+$ ]] || { echo "REFUSED: issue cases: '$1' is not an issue number" >&2; return 2; }
  command -v python3 >/dev/null || { echo "REFUSED: issue #$1 cases: check not run -- python3 is missing" >&2; return 2; }
  body=$(timeout 20 gh issue view "$1" --json body -q .body 2>/dev/null) \
    || { echo "REFUSED: issue #$1 cases: check not run -- gh issue view failed or timed out" >&2; return 2; }
  err=$(mktemp) || { echo "REFUSED: issue #$1 cases: check not run -- no temp file" >&2; return 2; }
  out=$(PC_BODY=$body python3 -I "$(dirname "${BASH_SOURCE[0]}")/md_items.py" cases 2>"$err") \
    || { echo "REFUSED: issue #$1 cases: check not run -- $(head -1 "$err" | grep . || echo 'the reader failed')" >&2; rm -f "$err"; return 2; }
  rm -f "$err"
  printf '%s\n' "$out"
}
if [ "${1:-}" = --issue-cases ]; then
  [ $# -eq 2 ] || { echo "usage: plan-check.sh --issue-cases <issue number>" >&2; exit 2; }
  issue_cases "$2"; exit
fi
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
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh"
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
# Issue 444: every case an issue the unit closes states in its own text has one `## Issue cases` row
# `- #<n> <Fix|Done|Body> <k> -- <path> -- <test name>`, whose path is a `## Steps` path (a `{a,b}` group counts as each
# path it expands to) and whose test name is in `## Acceptance test`. The issues are the batch's (brief-issues.sh: its
# numbered list, text items with no number skipped) and any `Closes:` line of the plan or batch. A planless (Skip)
# batch, or a plan in the format before 0.55.0 (`issue_check legacy`: no Steps to check against), carries its own rows,
# checked for a path and a test name only.
issue_check() {
  local label text planless nums n c cases='' out
  if [ -n "$SRC" ]; then label=$PLAN text=$PT planless=0; else label=$BATCH text=$BT planless=1; fi
  [ "${1-}" != legacy ] || planless=1
  nums=$({ [ -z "$BATCH" ] || bash "$(dirname "${BASH_SOURCE[0]}")/brief-issues.sh" "$BATCH" | jq -r '.[] | numbers'
    grep -h '^Closes:' <<<"$PT"$'\n'"$BT" | grep -oE '#[0-9]+' | tr -d '#'; } | sort -un || true)
  [ -n "$nums" ] || return 0
  for n in $nums; do
    c=$(issue_cases "$n") || exit 2
    cases+=$(sed "s/^/$n /" <<<"$c")$'\n'
  done
  out=$(PC_CASES=$cases PC_TEXT=$text python3 -I - "$label" "$planless" <<'PY'
import os, re, sys
label, planless = sys.argv[1], sys.argv[2] == '1'
rows, steps, accept, sec, fence = {}, set(), [], '', False

def expand(path):
    """scripts/{a,b}.sh is scripts/a.sh and scripts/b.sh; a group with no comma is literal."""
    m = re.search(r'\{([^{}]*,[^{}]*)\}', path)
    if not m:
        return [path]
    return [p for alt in m.group(1).split(',') for p in expand(path[:m.start()] + alt + path[m.end():])]

for line in os.environ['PC_TEXT'].split('\n'):
    if line.startswith('```'):
        fence = not fence
        continue
    if fence:
        continue
    h = re.match(r'(#+)[ \t]+(.*)', line)
    if h:
        if len(h.group(1)) <= 2:
            sec = h.group(2).strip().lower()
        continue
    if sec == 'issue cases':
        m = re.match(r'[-*] #(\d+) (Fix|Done|Body) (\d+) -- (.*?) -- (.*?)\s*$', line)
        if m:
            rows.setdefault((m.group(1), m.group(2), m.group(3)), []).append((m.group(4).strip('` '), m.group(5)))
    elif sec == 'steps':
        m = re.match(r'- (?:new|modify|delete) (\S+)', line)
        if m:
            steps.update(expand(m.group(1).strip('`')))
    elif sec.startswith('acceptance test'):
        accept.append(line)
accept = '\n'.join(accept)
missing, bad = [], []
for case in os.environ['PC_CASES'].split('\n'):
    if not case:
        continue
    n, kind, k, text = (case.split(' ', 3) + [''])[:4]
    key = '#%s %s %s' % (n, kind, k)
    if (n, kind, k) not in rows:
        missing.append('  - %s: %s' % (key, text))
        continue
    for path, test in rows[(n, kind, k)]:
        if not path or not test:
            bad.append('  - %s: the row needs `-- <path> -- <test name>`' % key)
        elif not planless and path not in steps:
            bad.append('  - %s: path %s is not a ## Steps path' % (key, path))
        elif not planless and test not in accept:
            bad.append('  - %s: test "%s" is not in ## Acceptance test' % (key, test))
if missing:
    print('REFUSED: %s drops issue cases (each needs a `- #<n> <Fix|Done|Body> <k> -- <path> -- <test name>` row under ## Issue cases):' % label)
    print('\n'.join(missing))
if bad:
    print('REFUSED: %s has issue case rows that do not hold:' % label)
    print('\n'.join(bad))
sys.exit(2 if missing or bad else 0)
PY
) || { [ -n "$out" ] || out="REFUSED: $label issue cases: check not run -- python3 failed"; printf '%s\n' "$out" >&2; exit 2; }
}
[ -n "$SRC" ] || { issue_check; exit 0; }
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
  issue_check legacy
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
        ('Steps', 2000), ('Issue cases', 4000)]
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
# Issue 476: every question for the owner sits in the one `## Question for the owner` section, which main sends as one ask.
# A second such heading, or a `> Owner:` line outside the section, is refused; fenced lines are skipped.
PC_ASK=$(awk -v fenced="$PC_FENCED" 'BEGIN { n = split(fenced, a, " "); for (i = 1; i <= n; i++) f[a[i]] = 1 }
  NR in f { next }
  /^#+[ \t]/ { q = (tolower($0) ~ /^#+[ \t]+questions? for the owner/); if (q && seen++) { print NR; exit } next }
  !q && /^[ \t]*>[ \t]*Owner:/ { print NR; exit }' <<<"$PT")
[ -z "$PC_ASK" ] || refuse "$PLAN asks the owner outside its one ## Question for the owner section (line $PC_ASK)"
# Issue 486: a Closes issue left off a per-issue line would reach the merge with no review of its own.
if [ -n "$BATCH" ]; then
  PC_WF=$(pp_review_workflow "$BATCH") || exit 2
  if [ "$PC_WF" != default ]; then
    for n in $(grep -h '^Closes:' <<<"$PT"$'\n'"$BT" | grep -oE '#[0-9]+' | sort -u || true); do
      [[ " ${PC_WF#per-issue } " == *" $n "* ]] \
        || refuse "the Closes: line names $n and $BATCH's Review workflow line does not ($PC_WF): list every closed issue there"
    done
  fi
fi
# Issue 480: a plan over the review-limits caps (changed lines, distinct Closes issues, as issue_check lists them) is split
# unless a `Split override: <reason>` line stands outside a fence; a bare key is none. An unreadable key refuses.
PC_LCAP=$(pp_review_limit diffLines) || refuse "cannot read review-limits.diffLines from $(pp_routing)"
PC_ICAP=$(pp_review_limit maxIssues) || refuse "cannot read review-limits.maxIssues from $(pp_routing)"
PC_LINES=${SIZE#* }
PC_ISSUES=$({ [ -z "$BATCH" ] || bash "$(dirname "${BASH_SOURCE[0]}")/brief-issues.sh" "$BATCH" | jq -r '.[] | numbers'
  grep -h '^Closes:' <<<"$PT"$'\n'"$BT" | grep -oE '#[0-9]+' | tr -d '#'; } | sort -un | wc -l | tr -d ' ' || true)
if [ "$PC_LINES" -gt "$PC_LCAP" ] || [ "$PC_ISSUES" -gt "$PC_ICAP" ]; then
  awk -v fenced="$PC_FENCED" 'BEGIN { n = split(fenced, a, " "); for (i = 1; i <= n; i++) f[a[i]] = 1 }
    !(NR in f) && /^Split override:[ \t]*[^ \t]/ { ok = 1 } END { exit !ok }' <<<"$PT" \
    || refuse "$PLAN is over a cap ($PC_LINES changed lines, cap $PC_LCAP; $PC_ISSUES Closes issues, cap $PC_ICAP): split the unit, or carry a line 'Split override: <reason>' (a bare 'Split override:' is no override)"
fi
# Issue 462: a plan that names test cases carries the `New tests:` line the pass's cap reads, so its Builder never stops to
# ask for the cap. The line is read by pp_new_tests_line, the cap's own reader, for the unit (PLAN_CHECK_UNIT, default the
# plan's file name; a bare line counts only in the unit's own plan). The count is the `; `-separated cases in the
# parenthesis of every `- test file path:` row under `## Acceptance test`, or, in a plan with no such case, the
# `; `-separated cases of its `Red-first:` lines; fenced lines are skipped and `Break:` lines are never counted. N may
# differ from the count only with a ` -- <reason>` after it.
PC_NT=$(PC_PLANTEXT=$PT python3 -I - <<'PY'
import os, re
def split(s): # the `; `-separated parts of s, never split inside backticks
    parts, cur, tick = [], '', False
    for i, ch in enumerate(s):
        tick = tick != (ch == '`')
        if not tick and s.startswith('; ', i):
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    return [p for p in parts + [cur] if p.strip()]
def scan(text): # (closed, cases) of the parenthesis after the row's backticked paths, parens counted outside backticks
    body = re.sub(r'^(\s*`[^`]*`\s*,?(\s*and\b)?)+', '', text)
    depth, start, tick = 0, -1, False
    for i, ch in enumerate(body):
        if ch == '`':
            tick = not tick
        elif not tick and ch == '(':
            start, depth = start if start >= 0 else i, depth + 1
        elif not tick and ch == ')' and depth:
            depth -= 1
            if depth == 0:
                return True, len(split(body[start + 1:i]))
    return False, len(split(body[start + 1:])) if start >= 0 else 0
fenced = set(map(int, os.environ['PC_FENCED'].split()))
sec, rows, red, row = '', 0, 0, None
for n, line in enumerate(os.environ['PC_PLANTEXT'].split('\n'), 1):
    if n in fenced:
        continue
    if row is not None:
        if re.match(r'\s*([-*] |#+(?:[ \t]|$)|New tests:|Red-first:)', line):
            rows, row = rows + scan(row)[1], None
        else:
            row += ' ' + line.strip()
            closed, k = scan(row)
            if closed:
                rows, row = rows + k, None
            continue
    m = re.match(r'\s*(?:[-*]\s+)?Red-first:\s*(.*)$', line)
    if m and m.group(1).strip().lower() not in ('', 'none'):
        red += len(split(m.group(1)))
    h = re.match(r'(#+)[ \t]+(.*)', line)
    if h:
        if len(h.group(1)) <= 2:
            sec = h.group(2).strip().lower()
        continue
    if sec.startswith('acceptance test'):
        m = re.match(r'\s*[-*] test file path:(.*)$', line)
        if m:
            closed, k = scan(m.group(1))
            if closed:
                rows += k
            else:
                row = m.group(1)
if row is not None:
    rows += scan(row)[1]
print(rows or red)
PY
) || { echo "REFUSED: $PLAN New tests: check not run -- python3 failed" >&2; exit 2; }
if [ "$PC_NT" -gt 0 ]; then
  PC_OWN=${PLAN##*/}; PC_OWN=${PC_OWN%.md}; PC_UNIT=${PLAN_CHECK_UNIT:-$PC_OWN}
  PC_TMP=$(mktemp) || refuse "$PLAN New tests: check not run -- no temp file"
  printf '%s\n' "$PT" > "$PC_TMP"
  PC_LINE=$(pp_new_tests_line "$PC_TMP" "$PC_UNIT" "$([ "$PC_UNIT" = "$PC_OWN" ] && echo 1)")
  rm -f "$PC_TMP"
  [ -n "$PC_LINE" ] || refuse "$PLAN names $PC_NT new test cases but has no \`New tests: $PC_UNIT $PC_NT\` line (counted by \`; \`; when one case holds several tests, write the real count after \` -- <reason>\`)"
  if [ "$((10#${PC_LINE% *}))" -ne "$PC_NT" ] && [ "${PC_LINE#* }" != 1 ]; then
    refuse "$PLAN says New tests: ${PC_LINE% *} but names $PC_NT cases; make them agree, or give the difference after \` -- <reason>\`"
  fi
fi
# Issue 456: a line under `## Done` is `- #<n> Done: <user action> -- <what the user sees>`; one with no ` -- `, a side under
# three words or a side (action or outcome) that is a one- or two-word parenthesized label (`(API)`) names a component. Issue 458: outside
# a fence, a line under `## Stated limits` that says follow-up, or any line starting `Follow-up:`, holds a filed issue
# (`#N` or `owner/repo#N`); the section's opening line (SENTINELS[1] of the budget block) is exempt word for word.
out=$(PC_PLANTEXT=$PT python3 -I - "$PLAN" <<'PY'
import os, re, sys
label = sys.argv[1]
OPENING = '(every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker)'
lines = os.environ['PC_PLANTEXT'].split('\n')
fenced = set(map(int, os.environ['PC_FENCED'].split()))
done_bad, later, sec = [], [], ''
for n, line in enumerate(lines, 1):
    if n in fenced:
        continue
    if re.match(r'##[ \t]', line):
        sec = line[2:].strip().lower()
        continue
    if sec == 'done' and re.match(r'[ \t]*[-*+][ \t]', line):
        act, _, side = line.partition(' -- ')
        act = re.sub(r'^[ \t]*[-*+][ \t]+(#\d+[ \t]+)?(Done:)?', '', act)
        if any(len(s.split()) < 3 or re.fullmatch(r'\(\s*\S+(\s+\S+)?\s*\)', s.strip()) for s in (act, side)):
            done_bad.append('REFUSED: %s line %d Done line names a component, not what a user sees: %s' % (label, n, line))
    if line.strip() == OPENING or re.search(r'#\d+', line):
        continue
    if line.startswith('Follow-up:') or (sec.startswith('stated limits') and re.search(r'follow[- ]?up', line, re.I)):
        later.append('  - line %d: %s' % (n, line))
if done_bad:
    print('\n'.join(done_bad))
if later:
    print('REFUSED: %s names later work with no filed issue (#N or owner/repo#N):' % label)
    print('\n'.join(later))
sys.exit(2 if done_bad or later else 0)
PY
) || { [ -n "$out" ] || out="REFUSED: $PLAN Done and follow-up lines: check not run -- python3 failed"; printf '%s\n' "$out" >&2; exit 2; }
issue_check
echo "size $SIZE"
