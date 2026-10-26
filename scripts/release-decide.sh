#!/usr/bin/env bash
# release-decide.sh <before sha> <after sha> -- the one decision for a push to main, run in the repository. Prints
# "release v<version>" when .claude-plugin/plugin.json's version at <after> differs from the one at <before> and the
# version is not published: no tag v<version>, or the tag with no GitHub release (`gh release view` fails), the state
# a run leaves when its Tag step pushed and its Publish failed, so a rerun publishes. Otherwise "skip: <why>". Exit 0
# either way; exit 1 when a version cannot be read. A <before> of all zeros (a new branch) has no version.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -5; exit 0 ;; esac
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: release-decide.sh <before sha> <after sha>" >&2; exit 1; }
version_at() { git show "$1:.claude-plugin/plugin.json" 2>/dev/null | jq -er '.version' 2>/dev/null || { echo "release-decide: no version in .claude-plugin/plugin.json at $1" >&2; return 1; }; }
NOW=$(version_at "$2")
if [[ $1 =~ ^0+$ ]]; then WAS=; else WAS=$(version_at "$1"); fi
[ "$NOW" != "$WAS" ] || { echo "skip: version $NOW did not change"; exit 0; }
if git rev-parse -q --verify "refs/tags/v$NOW" >/dev/null && gh release view "v$NOW" >/dev/null 2>&1; then
  echo "skip: release v$NOW exists"
else echo "release v$NOW"; fi
