#!/usr/bin/env bash
# release-backfill.sh [--plan] -- for each version in .claude-plugin/plugin.json's history, oldest first, tag the
# commit that set it (v<version>) and publish a release with its CHANGELOG section, unless origin has the tag or the
# release exists. Run once by the owner from the repository; --plan prints "v<version> <commit> <what is missing>" and changes nothing.
# A section the style guard refuses is never published: every body is checked first, and one refusal stops the run
# before any tag, push or gh call. A version with no section at all gets the body "Version <x>."; a section with no notes, or a CHANGELOG that cannot be read, stops the run.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
[ $# -eq 0 ] || [ "$*" = --plan ] || { echo "usage: release-backfill.sh [--plan]" >&2; exit 1; }
PLAN=0; [ $# -eq 0 ] || PLAN=1
HERE=$(cd "$(dirname "$0")" && pwd)
# The remote's tag, not a local one: a push that failed after `git tag` leaves the tag only here, and the rerun pushes it.
tag_state() { git ls-remote --exit-code --tags origin "refs/tags/v$1" >/dev/null 2>&1 && echo has-tag || echo no-tag; }
SEEN=" "; VERS=(); COMMITS=()
while read -r c; do
  v=$(git show "$c:.claude-plugin/plugin.json" 2>/dev/null | jq -er '.version' 2>/dev/null) || continue
  case $SEEN in *" $v "*) continue ;; esac
  SEEN="$SEEN$v "
  VERS+=("$v"); COMMITS+=("$c")
done < <(git log --reverse --format=%H -G'"version"' -- .claude-plugin/plugin.json)
if [ $PLAN = 1 ]; then
  for i in "${!VERS[@]}"; do echo "v${VERS[$i]} ${COMMITS[$i]:0:7} $(tag_state "${VERS[$i]}")"; done
  exit 0
fi
# Pass 1: every body, before any tag, push or gh call. Exit 1 from the extractor (no section) is the one absence that
# keeps the fallback; any other non-zero status (2 refused, 3 no notes or unreadable, a crash) prints its lines, and any one
# stops the run with nothing published.
BODIES=(); BAD=0
for i in "${!VERS[@]}"; do
  v=${VERS[$i]}; rc=0
  BODIES[$i]=$(bash "$HERE/release-notes.sh" "$v" 2>/dev/null) || rc=$?
  case $rc in
    0) ;;
    1) BODIES[$i]="Version $v." ;;
    *) why=$(bash "$HERE/release-notes.sh" "$v" 2>&1 >/dev/null || true)
       [ -n "$why" ] || why="release-notes: release-notes.sh exited $rc"
       printf '%s\n' "$why" | sed "s/^release-notes: /release-backfill: v$v: /" >&2; BAD=1 ;;
  esac
done
[ $BAD = 0 ] || exit 1
# Pass 2: tag, push and publish each version with the body pass 1 kept.
for i in "${!VERS[@]}"; do
  v=${VERS[$i]}
  [ "$(tag_state "$v")" = has-tag ] || { git rev-parse -q --verify "refs/tags/v$v" >/dev/null || git tag "v$v" "${COMMITS[$i]}"; git push origin "v$v"; }
  gh release view "v$v" >/dev/null 2>&1 || gh release create "v$v" --title "v$v" --verify-tag --notes "${BODIES[$i]}"
done
