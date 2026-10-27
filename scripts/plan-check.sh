#!/usr/bin/env bash
# plan-check.sh [--batch-only] <plan file | - | ''> <batch or ''> [<label>] -- the plan and batch checks of a Builder
# launch, in one home (issue 384): builder-launch.sh runs them before a Builder opens, and seat.sh runs them before
# every launch of a plan judge that certifies the plan, so no judging round is spent on a fault the launcher refuses
# in seconds. `-` reads the plan text on stdin; '' is a plan-less (Skip) batch; '' as the batch is a judge with no
# batch found, whose plan's own checks still run. The label names the plan in every message (default: the plan path).
# With a batch: Prior art and Data design (the batch's own). With a plan or a Skip batch: What can go wrong (the
# batch's or the plan's); with a plan, its size line, a Test: line under each Decisions and Accepted failure modes item,
# and its Mockup: lines (issue 392); with either, no line that describes placeholder UI (issue 400). --batch-only runs
# the batch checks alone.
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
echo "size $SIZE"
