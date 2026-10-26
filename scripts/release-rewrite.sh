#!/usr/bin/env bash
# release-rewrite.sh [--plan] -- set every published release's body to its CHANGELOG section (release-notes.sh <version>).
# Pass 1 checks every release's section and edits nothing when one is missing or refused; pass 2 edits each release
# with the body pass 1 kept. --plan prints "v<version> <body lines>" per release and edits nothing. Run by main from the repository.
# The repository is this checkout's origin; GH_REPO is ignored.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
die() { echo "release-rewrite: $*" >&2; exit 1; }
[ $# -eq 0 ] || [ "$*" = --plan ] || { echo "usage: release-rewrite.sh [--plan]" >&2; exit 1; }
PLAN=0; [ $# -eq 0 ] || PLAN=1
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
unset GH_REPO
# The destination comes from origin and nothing else: a GitHub URL, reduced to <owner>/<name>.
URL=$(git -C "$ROOT" remote get-url origin 2>/dev/null) || die "this checkout has no origin"
GH_URL='^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)'
printf '%s\n' "$URL" | grep -q -E "$GH_URL" || die "origin $URL is not a GitHub repository"
REPO=$(printf '%s\n' "$URL" | sed -E "s#$GH_URL##; s#\.git\$##")
printf '%s\n' "$REPO" | grep -q -E '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || die "origin $URL is not an <owner>/<name> repository"
LIST=$(gh release list --repo "$REPO" --limit 1000 --json tagName | jq -r '.[].tagName') || die "could not list the releases of $REPO"
[ -n "$LIST" ] || die "$REPO has no releases"
# Pass 1: every body, before any edit.
TAGS=(); BODY=(); BAD=0
for t in $LIST; do
  rc=0
  b=$(bash "$HERE/release-notes.sh" "${t#v}" 2>/dev/null) || rc=$?
  if [ $rc -ne 0 ]; then
    bash "$HERE/release-notes.sh" "${t#v}" 2>&1 >/dev/null | sed "s/^release-notes: /release-rewrite: $t: /" >&2 || true
    BAD=1; continue
  fi
  TAGS+=("$t"); BODY+=("$b")
done
[ $BAD -eq 0 ] || exit 1
# Pass 2: edit each release with the body pass 1 kept, so a CHANGELOG changed meanwhile publishes nothing unchecked.
for i in "${!TAGS[@]}"; do
  if [ $PLAN -eq 1 ]; then echo "${TAGS[$i]} $(printf '%s\n' "${BODY[$i]}" | wc -l | tr -d ' ')"; continue; fi
  printf '%s\n' "${BODY[$i]}" | gh release edit "${TAGS[$i]}" --repo "$REPO" --notes-file - >/dev/null || die "${TAGS[$i]}: gh release edit failed, no later release was edited"
  echo "release-rewrite: edited ${TAGS[$i]}"
done
