#!/usr/bin/env bash
# run-audit.sh [--dry-run] -- the platform best-practice audit, run in the project. It exports the project's HEAD to
# a scratch folder and audits only the areas whose paths (.claude/paved-road-areas.tsv) changed since the last
# recorded audit commit, every area when none is recorded or either file changed: one read-only roles.audit-auditor session per area against
# its Standards row in .claude/paved-road.md (run.sh), then one roles.audit-verifier session per area that tries to
# disprove each finding (verify.sh). It writes the merged report to <scratch>/report.md, prints its path, and records
# HEAD as the last audit commit only when every area has both outputs. It changes no code and files no issue.
# --dry-run lists the areas it would audit and launches nothing.
# Start the registry from the plugin's templates/paved-road.md.
# Self-test: bash scripts/__tests__/platform-audit.test.sh
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/../paths.sh"
die() { echo "platform-audit: $*" >&2; exit 2; }
DRY=0
case ${1:-} in --dry-run) DRY=1 ;; '') ;; *) die "usage: run-audit.sh [--dry-run]" ;; esac
REPO=$PP_MAIN
HEAD=$(git -C "$REPO" rev-parse HEAD)
# The registry as HEAD has it, as the copy audited and the commit recorded are: an uncommitted edit that drops an
# area would record HEAD with that area's committed code never audited.
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
mkdir "$TMPD/HEAD" "$TMPD/HEAD/.claude"
REG=$TMPD/HEAD/.claude/paved-road.md AREAS=$TMPD/HEAD/.claude/paved-road-areas.tsv TMPC=$TMPD/changed
git -C "$REPO" show "$HEAD:.claude/paved-road.md" > "$REG" 2>/dev/null && git -C "$REPO" show "$HEAD:.claude/paved-road-areas.tsv" > "$AREAS" 2>/dev/null \
  || die "no .claude/paved-road.md and .claude/paved-road-areas.tsv committed at HEAD in $REPO: start the registry from ${HERE%/scripts/*}/templates/paved-road.md, which says what each holds"
# In the git directory: it outlives a wiped scratch, and no worktree tracks it.
STATE=${COMMANDECK_AUDIT_STATE:-$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/commandeck-platform-audit-commit}
LAST=$(cat "$STATE" 2>/dev/null || true)
ARGS=("$AREAS" "$REG")
if [ -n "$LAST" ]; then
  git -C "$REPO" cat-file -e "$LAST^{commit}" 2>/dev/null || die "the last audit commit $LAST ($STATE) is not in this repo; delete that file to audit every area"
  # A changed registry or areas file changes what every area is held to. -z and --no-renames: every path as it is,
  # a moved file's old place too.
  git -C "$REPO" diff --quiet "$LAST" "$HEAD" -- .claude/paved-road.md .claude/paved-road-areas.tsv \
    && { git -C "$REPO" diff --name-only -z --no-renames "$LAST" "$HEAD" > "$TMPC"; ARGS+=("$TMPC"); }
fi
ROWS=$(python3 "$HERE/select-areas.py" "${ARGS[@]}")
echo "platform-audit: HEAD $HEAD, since ${LAST:-no recorded audit (every area)}"
[ -n "$ROWS" ] || { echo "platform-audit: no area changed; nothing to audit"; exit 0; }
cut -f1 <<<"$ROWS" | sed 's/^/area: /'
[ "$DRY" = 0 ] || exit 0

# Each agent's command is its routing.json role's, resolved once here: run.sh and verify.sh run it in xargs children.
argv_of() { # <role> -- its argv, one word a line; a Codex family becomes the model id the account lists
  local m
  m=$(jq -er --arg r "$1" '.roles[$r] | select(.headless) | .model' "$(pp_routing)") || return 2
  [ "$(jq -r --arg r "$1" '.roles[$r].agent' "$(pp_routing)")" != codex ] || m=$(pp_codex_model "$m" "$1") || return 2
  pp_route_json "$1" "" "$m" | jq -er '.argv[]'
}
AUDITOR_ARGV=$(argv_of audit-auditor) || die "$(pp_routing) has no usable headless audit-auditor role; nothing audited"
VERIFIER_ARGV=$(argv_of audit-verifier) || die "$(pp_routing) has no usable headless audit-verifier role; nothing audited"
export AUDITOR_ARGV VERIFIER_ARGV

A=${COMMANDECK_AUDIT_DIR:-$PP_SCRATCH/platform-audit/$(date -u +%Y%m%dT%H%M%SZ)}
# Every delete and write below is under $A, so it must be a folder a run made (its marker), or new or empty: never
# the project, a folder holding it, or anything else with files in it.
[ -e "$A/.platform-audit" ] || [ ! -e "$A" ] || { [ -d "$A" ] && [ -z "$(ls -A "$A")" ]; } \
  || die "$A is not a platform-audit scratch folder (no .platform-audit marker, and not empty); name a new folder in COMMANDECK_AUDIT_DIR"
mkdir -p "$A" && : > "$A/.platform-audit"
# A fresh copy each run: a file deleted since an earlier run in the same folder must not stay readable.
rm -rf "$A/src"
mkdir -p "$A/src" "$A/out" "$A/logs" "$A/verify" "$A/vlogs" "$A/vrun"
git -C "$REPO" archive "$HEAD" | tar -x -C "$A/src"
echo "$HEAD" > "$A/commit.txt"
printf '%s\n' "$ROWS" > "$A/slices.tsv"
(cd "$REPO" && gh issue list --state open --limit 2000 --json number,title,body,milestone) \
  | jq '[.[] | .body = ((.body // "")[0:600]) | .milestone = (.milestone.title // null)]' > "$A/open-issues.json"
# A failed agent leaves no output (run.sh, verify.sh), so the report below names it as missing.
failed=0
A=$A HERE=$HERE bash "$HERE/run.sh" || failed=1
A=$A HERE=$HERE bash "$HERE/verify.sh" || failed=1

missing=()
{
  echo "# Platform best-practice audit, commit $HEAD"
  echo
  echo "Areas: $(cut -f1 <<<"$ROWS" | paste -sd' ' -). Since: ${LAST:-no recorded audit}."
  while IFS= read -r id; do
    for f in "$A/out/$id.md" "$A/verify/$id.md"; do
      echo
      if [ -s "$f" ]; then cat "$f"; else echo "## $id: MISSING ${f#"$A"/} (coverage gap: see $A/logs and $A/vlogs)"; missing+=("${f#"$A"/}"); fi
    done
  done < <(cut -f1 <<<"$ROWS")
} > "$A/report.md"
echo "report: $A/report.md"
[ "${#missing[@]}" = 0 ] && [ "$failed" = 0 ] || { echo "platform-audit: an agent failed (missing: ${missing[*]:-none}); the last audit commit stays ${LAST:-unrecorded}" >&2; exit 1; }
echo "$HEAD" > "$STATE"
