#!/usr/bin/env bash
# revoke.sh [[undo] rule <rule> | [undo] auto-mode <line> | status-line [--keep] | option <plugin> <key> [--keep] |
#   undo status-line | undo option <plugin> <key>] -- the owner's
# choice about one value setup put in this Claude profile's settings file, kept at every launch. At a launch the
# SessionStart repair (hooks/profile-settings.sh) puts setup's values back after Orca copies the home file over the
# profile's, and never reads a removal from the file: a hand edit is undone at the next launch. This writes the choice
# on the manifest's list for the file (`revoked`), which every pane on the profile shares, then makes the file match:
# a rule or auto-mode line is taken out; the status line or an option is taken out, or with --keep the value the file
# holds now (yours, not setup's) is the one a launch puts back. Setup leaves a value on the list out too. undo takes
# the value off the list (this is the only command that writes or clears it): setup's value is back at the next launch.
# No argument: setup's values for this file, one a line, as this command names them, a chosen one marked. Exit 0: done
# or listed; 1: no record of this file, not a value setup put there, nothing of yours to keep, or (undo) not on the
# list; 2: usage.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -14; exit 0 ;; esac
set -uo pipefail
usage() { echo "usage: revoke.sh [[undo] rule <rule> | [undo] auto-mode <line> | status-line [--keep] | option <plugin> <key> [--keep] | undo status-line | undo option <plugin> <key>]" >&2; exit 2; }
KEEP= UNDO=
[ "${1-}" != undo ] || { UNDO=1; shift; [ $# -gt 0 ] || usage; }
case ${1-} in
  '') ;;
  rule|auto-mode) [ $# = 2 ] || usage ;;
  status-line) [ $# = 1 ] || { [ $# = 2 ] && [ "$2" = --keep ] && KEEP=1; } || usage ;;
  option) [ $# = 3 ] || { [ $# = 4 ] && [ "$4" = --keep ] && KEEP=1; } || usage ;;
  *) usage ;;
esac
[ -z "$UNDO" ] || [ -z "$KEEP" ] || usage
. "$(dirname "${BASH_SOURCE[0]}")/paths.sh" || exit 1
. "$PP_SCRIPTS/install-lib.sh" || exit 1
F=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json
# From the read to the last write: a launch's repair in another pane waits, and does not write from a stale read.
[ ! -d "$IL_DIR" ] || il_profile_lock 30 || exit 1
REC=$(il_profile_record "$IL_MACHINE" "$F")
[ -n "$REC" ] || { echo "revoke: setup never wrote $F" >&2; exit 1; }
if [ $# = 0 ]; then
  jq -r '.revoked as $v | def mark(c): if c then "  (chosen)" else "" end;
    ((.added // [])[] as $x | "rule \($x)" + mark(($v.added // []) | index($x))),
    ((.autoMode.added // [])[] as $x | "auto-mode \($x)" + mark(($v.autoMode // []) | index($x))),
    (select((.statusLine.set // null) != null) | "status-line" + mark($v | has("statusLine"))),
    (.optionsWant | to_entries[] | .key as $p | .value | keys[] as $x | "option \($p) \($x)" + mark(($v.options[$p] // {}) | has($x)))' <<<"$REC"
  exit 0
fi
DOC=$(il_read "$F") || exit 1; [ -n "${DOC//[[:space:]]/}" ] || DOC='{}'
# One jq: refuse a value setup did not put there (undo: one not on the list), else the list's entry and the file as
# it will be, made by the rule every writer uses (IL_CHOICES). The entry keeps setup's value, so a launch can take it
# out with no other part of the record.
OUT=$(jq -c --argjson r "$REC" --arg k "$1" --arg a "${2-}" --arg b "${3-}" --arg keep "$KEEP" --arg undo "$UNDO" --arg what "$*" "$IL_CHOICES"'
  . as $doc | $r.revoked as $rv
  | (if $undo != "" then
      if $k == "rule" and (($rv.added // []) | index($a)) then {path: ["added"], v: ($rv.added - [$a])}
      elif $k == "auto-mode" and (($rv.autoMode // []) | index($a)) then {path: ["autoMode"], v: ($rv.autoMode - [$a])}
      elif $k == "status-line" and ($rv | has("statusLine")) then {path: ["statusLine"], del: true}
      elif $k == "option" and (($rv.options[$a] // {}) | has($b)) then {path: ["options", $a, $b], del: true}
      else {no: "\($what) is not on the list of your choices"} end
    elif $k == "rule" then
      if ($r.added // []) | index($a) | not then {no: "\($a) is not a rule setup added"}
      else {path: ["added"], v: (($rv.added // []) + [$a] | unique)} end
    elif $k == "auto-mode" then
      if ($r.autoMode.added // []) | index($a) | not then {no: "that is not an auto-mode line setup added"}
      else {path: ["autoMode"], v: (($rv.autoMode // []) + [$a] | unique)} end
    elif $k == "status-line" then
      if ($r.statusLine.set // null) == null then {no: "setup set no status line"}
      elif $keep != "" and (.statusLine == null or .statusLine == $r.statusLine.set) then {no: "the status line in the file is setup'"'"'s or none: set your own first"}
      elif $keep != "" then {path: ["statusLine"], v: {keep: .statusLine}}
      else {path: ["statusLine"], v: {keep: null, set: $r.statusLine.set, was: $r.statusLine.was}} end
    else
      (try .pluginConfigs[$a].options[$b] catch null) as $c
      | if $r.optionsWant[$a] // {} | has($b) | not then {no: "\($a) \($b) is not an option setup set"}
      elif $keep != "" and ($c == null or $c == $r.optionsWant[$a][$b]) then {no: "\($a) \($b) holds setup'"'"'s value or none: set your own in /config first"}
      elif $keep != "" then {path: ["options", $a, $b], v: {keep: $c}}
      else {path: ["options", $a, $b], v: {keep: null, set: $r.optionsWant[$a][$b]}} end
    end) as $o
  | if $o.no or $undo != "" then $o else $o + {doc: ($doc | choices($r | .revoked |= setpath($o.path; $o.v)))} end' <<<"$DOC" 2>/dev/null) \
  || { echo "revoke: $F is not JSON; left as it is" >&2; exit 1; }
NO=$(jq -r '.no // empty' <<<"$OUT")
[ -z "$NO" ] || { echo "revoke: $NO in $F (revoke.sh with no argument lists setup's values)" >&2; exit 1; }
# The list first: if the file write fails, the next launch still honours the choice.
il_set "$IL_MACHINE" --arg f "$F" --argjson o "$OUT" '.entries[$f].revoked |= ((. // {}) | if $o.del then delpaths([$o.path]) else setpath($o.path; $o.v) end
  | if has("options") then .options |= with_entries(select(.value != {})) else . end)' || exit 1
[ -n "$UNDO" ] || [ "$(jq -cS .doc <<<"$OUT")" = "$(jq -cS . <<<"$DOC")" ] || jq .doc <<<"$OUT" | il_write "$F" || exit 1
[ -z "$UNDO" ] || { echo "$*: off your list in $F; setup's value is back at the next launch"; exit 0; }
WHAT="$*"; echo "${WHAT% --keep}: $([ -n "$KEEP" ] && echo "your value is kept" || echo "taken out") in $F; a launch keeps it that way"
