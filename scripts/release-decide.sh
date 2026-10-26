#!/usr/bin/env bash
# release-decide.sh <before sha> <after sha> -- the one decision for a push to main, run in the repository. Prints
# "release v<version>" when .claude-plugin/plugin.json's version at <after> differs from the one at <before> and the
# version is not published: no tag v<version>, or the tag with no GitHub release (`gh release view` fails), the state
# a run leaves when its Tag step pushed and its Publish failed, so a rerun publishes. A version that did not change
# is published the same way when its tag exists and its release does not: the later commit that finds that tag as its
# base. Otherwise "skip: <why>". Exit 0 either way; exit 1 when a version cannot be read. A <before> of all zeros (a new
# branch) has no version.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -7; exit 0 ;; esac
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: release-decide.sh <before sha> <after sha>" >&2; exit 1; }
version_at() { git show "$1:.claude-plugin/plugin.json" 2>/dev/null | jq -er '.version' 2>/dev/null || { echo "release-decide: no version in .claude-plugin/plugin.json at $1" >&2; return 1; }; }
NOW=$(version_at "$2")
if [[ $1 =~ ^0+$ ]]; then WAS=; else WAS=$(version_at "$1"); fi
TAGGED= PUBLISHED=
if git rev-parse -q --verify "refs/tags/v$NOW" >/dev/null; then
  TAGGED=1
  if gh release view "v$NOW" >/dev/null 2>&1; then PUBLISHED=1; fi
fi
if [ "$NOW" = "$WAS" ]; then
  # Nothing new to release, except a version a run tagged and could not publish: its tag is the next commit's base, so the
  # version reads as unchanged there, and only the release is missing.
  { [ -n "$TAGGED" ] && [ -z "$PUBLISHED" ]; } || { echo "skip: version $NOW did not change"; exit 0; }
elif [ -n "$PUBLISHED" ]; then echo "skip: release v$NOW exists"; exit 0; fi
echo "release v$NOW"
