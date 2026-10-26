#!/usr/bin/env bash
# release-backfill.sh [--plan] -- for each version in .claude-plugin/plugin.json's history, oldest first, tag the
# commit that set it (v<version>) and publish a release with its CHANGELOG section, unless origin has the tag or the
# release exists. Run once by the owner from the repository; --plan prints "v<version> <commit> <what is missing>" and changes nothing.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
[ $# -eq 0 ] || [ "$*" = --plan ] || { echo "usage: release-backfill.sh [--plan]" >&2; exit 1; }
PLAN=0; [ $# -eq 0 ] || PLAN=1
HERE=$(cd "$(dirname "$0")" && pwd)
SEEN=" "
while read -r c; do
  v=$(git show "$c:.claude-plugin/plugin.json" 2>/dev/null | jq -er '.version' 2>/dev/null) || continue
  case $SEEN in *" $v "*) continue ;; esac
  SEEN="$SEEN$v "
  # The remote's tag, not a local one: a push that failed after `git tag` leaves the tag only here, and the rerun pushes it.
  tag=$(git ls-remote --exit-code --tags origin "refs/tags/v$v" >/dev/null 2>&1 && echo has-tag || echo no-tag)
  if [ $PLAN = 1 ]; then echo "v$v ${c:0:7} $tag"; continue; fi
  [ "$tag" = has-tag ] || { git rev-parse -q --verify "refs/tags/v$v" >/dev/null || git tag "v$v" "$c"; git push origin "v$v"; }
  gh release view "v$v" >/dev/null 2>&1 || gh release create "v$v" --title "v$v" --verify-tag \
    --notes "$(bash "$HERE/release-notes.sh" "$v" 2>/dev/null || echo "Version $v.")"
done < <(git log --reverse --format=%H -G'"version"' -- .claude-plugin/plugin.json)
