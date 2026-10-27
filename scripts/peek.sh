#!/usr/bin/env bash
# usage: peek.sh [--unit <unit> [--plan <file>] [--closing]] [-g <pattern> <path>] <item>...   item: <path> | <path>:A-B | <path>#Heading
# -- several reads in one call: one `== <item> ==` header per item, numbered lines, 400 lines per item (the cut names
# the resume range) and 60 KB in all. --unit prints a reviewer's inputs in read-cold order (diff stat, brief, plan
# without its change log, paved road): never implementer evidence or round reports, which would anchor the review.
# --plan reads the plan from <file> in place of .claude/plans/<unit>.md (a plan judge's frozen copy); a missing <file>
# is a missing item, never a fall back to the live plan. --closing prints the diff stat and the plan's claim sections
# only. Exit 2: a path refused (the checkout root or a parent of it: bash-guardrails.sh calls those unbounded); 1: an
# item missing; else 0.
# Self-test: bash scripts/run-shell-tests.sh scripts/__tests__/peek.test.sh
set -uo pipefail
LC_ALL=C
USAGE="usage: peek.sh [--unit <unit> [--plan <file>] [--closing]] [-g <pattern> <path>] <path | path:A-B | path#Heading>..."
case ${1:-} in
  --help|-h) printf '%s\nexample: peek.sh a.ts:10-40 plan.md#Decisions --unit my-unit --closing\n' "$USAGE"; exit 0 ;;
  "") echo "$USAGE" >&2; exit 2 ;;
esac
CAP=400 TOTAL_MAX=61440 TOTAL=0 RC=0 STOP=0 CLOSING=0 UNIT="" PLANFILE=""
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && ROOT=$(cd "$ROOT" && pwd -P) || { echo "peek: run it inside the checkout" >&2; exit 2; }

# <header> <body>: the chunk goes out whole while it fits the total cap, else cut there and the run stops.
out() {
  local chunk="== $1 =="$'\n'"$2"$'\n'
  [ "$STOP" = 1 ] && return
  if [ $((TOTAL + ${#chunk})) -gt "$TOTAL_MAX" ]; then
    printf '%s' "${chunk:0:$((TOTAL_MAX - TOTAL))}"; echo
    echo "cut at 60 KB total; ask for the remaining items in another call"; STOP=1; return
  fi
  TOTAL=$((TOTAL + ${#chunk})); printf '%s' "$chunk"
}
# <path> <numbered lines>: the first CAP lines, then where to resume. Grep's context lines (`N-`) and `--` separators
# carry no `N:`, so the range runs from the first numbered line past the cut to the last numbered line.
capped() {
  local n; n=$(printf '%s\n' "$2" | wc -l | tr -d ' ')
  if [ "$n" -le "$CAP" ]; then printf '%s\n' "$2"; return; fi
  printf '%s\n' "$2" | head -n "$CAP"
  echo "cut at $CAP; resume: peek.sh $1:$(printf '%s\n' "$2" | sed -n "$((CAP + 1)),\$p" | grep -m1 -oE '^[0-9]+')-$(printf '%s\n' "$2" | grep -oE '^[0-9]+' | tail -n 1)"
}
# <path> -> ABS; 2 refused, 1 missing
bounded() {
  local p=$1 d
  [ -n "$p" ] || return 2
  if [ -d "$p" ]; then ABS=$(cd "$p" && pwd -P)
  else d=$(dirname "$p"); [ -d "$d" ] || return 1; ABS=$(cd "$d" && pwd -P)/$(basename "$p"); fi
  ABS=${ABS%/}
  [[ $ROOT/ == "$ABS"/* ]] && return 2
  [ -f "$ABS" ]
}
# <heading> <file>: the section under a heading (prefix match, any case) with the file's own line numbers, through its subsections.
section() {
  awk -v h="$1" '/^#+[[:space:]]/ { match($0, /^#+/); if (on && RLENGTH <= L) on = 0; t = $0; sub(/^#+[[:space:]]+/, "", t); if (!on && tolower(substr(t, 1, length(h))) == tolower(h)) { on = 1; L = RLENGTH; found = 1 } } on { print NR ": " $0 } END { exit !found }' "$2"
}
numbered() { awk '{ print NR ": " $0 }' "$1"; }
plan_no_log() { awk '/^#+[[:space:]]/ { match($0, /^#+/); if (skip && RLENGTH <= L) skip = 0; t = $0; sub(/^#+[[:space:]]+/, "", t); if (!skip && tolower(substr(t, 1, 15)) == "plan change log") { skip = 1; L = RLENGTH } } !skip { print NR ": " $0 }' "$1"; }

item() {
  local it=$1 path=$1 a="" b="" h="" body
  if [[ $it =~ ^(.*):([0-9]+)-([0-9]+)$ ]]; then path=${BASH_REMATCH[1]} a=${BASH_REMATCH[2]} b=${BASH_REMATCH[3]}
  elif [[ $it == *#* ]]; then path=${it%%#*} h=${it#*#}; fi
  bounded "$path"
  case $? in
    2) echo "peek: refused '$path': the checkout root or a parent of it is unbounded; name a file under it" >&2; out "$it" "(refused)"; RC=2; return ;;
    1) out "$it" "(missing: no such file)"; [ "$RC" = 2 ] || RC=1; return ;;
  esac
  if [ -n "$h" ]; then
    body=$(section "$h" "$ABS") || { out "$it" "no section '$h' in $path"; [ "$RC" = 2 ] || RC=1; return; }
  elif [ -n "$a" ]; then body=$(awk -v a="$a" -v b="$b" 'NR >= a && NR <= b { print NR ": " $0 }' "$ABS")
  else body=$(numbered "$ABS"); fi
  out "$it" "$(capped "$path" "$body")"
}
grep_item() { # <pattern> <path>
  local body
  bounded "$2"
  case $? in
    2) echo "peek: refused '$2': the checkout root or a parent of it is unbounded; name a file under it" >&2; out "-g $1 $2" "(refused)"; RC=2; return ;;
    1) out "-g $1 $2" "(missing: no such file)"; [ "$RC" = 2 ] || RC=1; return ;;
  esac
  body=$(grep -n -C2 -e "$1" "$ABS" 2>&1)
  out "-g $1 $2" "$(capped "$2" "${body:-(no match)}")"
}

# <path> [heading]: a path the bundle names itself, so no boundary check; absent prints (none). A path is under the root unless absolute.
named() {
  local body f=$1
  case $f in /*) ;; *) f=$ROOT/$f ;; esac
  if [ ! -f "$f" ]; then out "$1${2:+#$2}" "(none)"; return; fi
  if [ -n "${2:-}" ]; then body=$(section "$2" "$f") || body="(none)"; else body=$(numbered "$f"); fi
  out "$1${2:+#$2}" "$(capped "$1" "$body")"
}
unit_bundle() {
  local plan=${PLANFILE:-.claude/plans/$UNIT.md} f d s
  [[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "peek: a unit name is letters, digits, . _ and - only: '$UNIT'" >&2; exit 2; }
  d=$(git -C "$ROOT" diff --stat main...HEAD 2>/dev/null) || d=""
  out "diff stat main...HEAD" "${d:-(none)}"
  f=$plan; case $f in /*) ;; *) f=$ROOT/$f ;; esac
  # A named --plan file that is absent is a missing item: the live plan is never read in its place.
  if [ -n "$PLANFILE" ] && [ ! -f "$f" ]; then
    out "$plan" "(missing: no such file)"; RC=1
    [ "$CLOSING" = 1 ] || { named ".claude/briefs/$UNIT.md"; named .claude/paved-road.md; }
    return
  fi
  [ "$CLOSING" = 1 ] && { for s in "Decisions" "Accepted failure modes" "Stated limits" "Claims to falsify"; do named "$plan" "$s"; done; return; }
  named ".claude/briefs/$UNIT.md"
  if [ -f "$f" ]; then out "$plan" "$(capped "$plan" "$(plan_no_log "$f")")"; else out "$plan" "(none)"; fi
  named .claude/paved-road.md
}

ITEMS=()
while [ $# -gt 0 ]; do
  case $1 in
    --unit) UNIT=${2:-}; [ -n "$UNIT" ] || { echo "$USAGE" >&2; exit 2; }; shift ;;
    --plan) PLANFILE=${2:-}; [ -n "$PLANFILE" ] || { echo "$USAGE" >&2; exit 2; }; shift ;;
    --closing) CLOSING=1 ;;
    -g) [ $# -ge 3 ] || { echo "$USAGE" >&2; exit 2; }; ITEMS+=("-g	$2	$3"); shift 2 ;;
    *) ITEMS+=("$1") ;;
  esac
  shift
done
[ "$CLOSING" = 0 ] || [ -n "$UNIT" ] || { echo "peek: --closing needs --unit" >&2; exit 2; }
[ -z "$PLANFILE" ] || [ -n "$UNIT" ] || { echo "peek: --plan needs --unit" >&2; exit 2; }
[ -z "$UNIT" ] || unit_bundle
for it in ${ITEMS[@]+"${ITEMS[@]}"}; do
  [ "$STOP" = 1 ] && break
  if [[ $it == -g$'\t'* ]]; then IFS=$'\t' read -r _ gp gf <<<"$it"; grep_item "$gp" "$gf"; else item "$it"; fi
done
exit "$RC"
