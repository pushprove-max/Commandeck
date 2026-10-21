#!/usr/bin/env bash
# uninstall.sh [--delete-data]
# Takes the plugin back out of the project this runs in, and out of the machine
# when this was the last project set up on it. Every path setup changed goes
# back to what the install manifest recorded (install-lib.sh): the plugin's own
# files are removed, its entries are taken out of the files it merged into, and
# a file that then holds what it held before gets its exact prior bytes back.
# A file edited since setup is left as it is, without the plugin's entries, and
# named in a "changed since setup" line.
#
# The data the plugin gathered is kept unless --delete-data: this project's
# ledgers (.claude/metrics), scratch, hook log, rulings, Chief-of-Staff state
# and finished-builds record, and with the last project the dashboard's folder. It can be run again
# later with --delete-data. Briefs, review rounds and the orchestrator's
# checkpoints (~/.claude/checkpoints/*.md) are the owner's work and are never
# touched. Removing the plugin itself is Claude Code's:
# `claude plugin uninstall commandeck`.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/paths.sh"
. "$HERE/host-services.sh"
. "$HERE/install-lib.sh"
DELETE=
case ${1:-} in '') ;; --delete-data) DELETE=1 ;; *) echo "usage: uninstall.sh [--delete-data]" >&2; exit 2 ;; esac
. "$HERE/../hooks/lib/project.sh"; pp_project "$PP_MAIN"; PROJECT=$PP_PROJECT   # the name the logs are keyed by
# The install record is named for the path with every odd character a dash, so
# /x/a-b and /x/a_b are one record: it is this checkout's only if it says so.
OWNER=$(jq -r '.project // empty' "$IL_PROJECT" 2>/dev/null || true)
[ -z "$OWNER" ] || [ "$(pp_norm "$OWNER")" = "$(pp_norm "$PP_MAIN")" ] \
  || { echo "uninstall: the install record $IL_PROJECT belongs to the project at $OWNER, not to $PP_MAIN. Nothing was changed; run this in $OWNER to take that project out." >&2; exit 1; }

if [ -s "$IL_PROJECT" ]; then
  bash "$HERE/main-watch.sh" --uninstall >/dev/null
  # Only a registration setup made: a line the owner put there first stays.
  ! jq -e '.registered == true' "$IL_PROJECT" >/dev/null 2>&1 || [ ! -e "$HOME/.commandeck/dashboard/projects" ] || bash "$HERE/dashboard.sh" --unregister "$PP_MAIN" >/dev/null
  ! il_has "$IL_PROJECT" "$IL_AGENTS" || il_block "$IL_AGENTS"
  ! il_has "$IL_PROJECT" "$IL_EXCLUDE" || il_lines "$IL_PROJECT" "$IL_EXCLUDE"
  S=$PP_MAIN/.claude/settings.json
  ! il_has "$IL_PROJECT" "$S" || [ ! -e "$S" ] || { il_workflows "$IL_PROJECT" "$S" off; il_advisor_off "$IL_PROJECT" "$S" off; il_cache_ttl "$IL_PROJECT" "$S" off; il_allow_set "$IL_PROJECT" "$S" '[]'; }
  S=$PP_MAIN/.claude/settings.local.json
  ! il_has "$IL_PROJECT" "$S" || [ ! -e "$S" ] || il_allow_set "$IL_PROJECT" "$S" '[]'
  # The plugin's rules merged into the owner's own startup files: only the marked block goes.
  for S in "$PP_MAIN/AGENT_STARTUP.md" "$PP_MAIN/.claude/main-session.md"; do
    ! il_has "$IL_PROJECT" "$S" || [ ! -e "$S" ] || IL_BEGIN='<!-- commandeck:merge:begin -->' IL_END='<!-- commandeck:merge:end -->' il_block "$S"
  done
  # The seats setup added to a routing file of the owner's own, by the manifest's path, not today's COMMANDECK_ROUTING.
  il_drop_relative_keys "$IL_PROJECT" "$PP_MAIN"
  while IFS= read -r S; do il_routing_seats "$IL_PROJECT" "$S" - off; done < <(jq -r '.entries | to_entries[] | select(.value.roles) | .key' "$IL_PROJECT")
  il_restore "$IL_PROJECT"
  echo "commandeck is out of $PP_MAIN"
else
  echo "uninstall: no install manifest for $PP_MAIN ($IL_PROJECT); nothing of the project's to put back"
fi

LAST=; [ -n "$(il_projects)" ] || LAST=1
if [ -n "$LAST" ] && [ -s "$IL_MACHINE" ]; then
  bash "$HERE/dashboard.sh" --uninstall >/dev/null
  # The relative keys an older setup left (a relative CODEX_HOME) name no folder it was read from.
  il_drop_relative_keys "$IL_MACHINE" "this machine" "a Codex path"
  # Every Codex home setup wrote to, by the manifest: CODEX_HOME today may not be the one it was then.
  while IFS= read -r h; do
    IL_CODEX=${h%/hooks.json}
    # The trust entries name the hooks by position: they go first.
    [ ! -e "$IL_CODEX/hooks.json" ] || [ ! -e "$IL_CODEX/config.toml" ] || python3 "$HERE/codex-hook-trust.py" --forget "$IL_CODEX" >/dev/null
    il_codex_hooks ''
    il_notify ''
    # The owner's wrapper is theirs to edit: uninstall only says which line now calls nothing.
    W=$(il_notify_wrapper)
    [ -z "$W" ] || ! il_notify_hooks "$W" | grep -qxF "$IL_LINK/hooks/codex-notify.sh" \
      || echo "codex notify: the wrapper $W still calls $IL_LINK/hooks/codex-notify.sh, which uninstall has removed; take this line out of it: $(grep -v '^[[:space:]]*#' "$W" | grep -F "$IL_LINK/hooks/codex-notify.sh" | head -1)"
  done < <(jq -r '.entries | keys[] | select(endswith("/hooks.json"))' "$IL_MACHINE")
  ! il_has "$IL_MACHINE" "$IL_GLOBAL" || [ ! -e "$IL_GLOBAL" ] || il_global_out
  il_profiles_out "$IL_MACHINE"
  il_restore "$IL_MACHINE"
  pp_rm_rf "$IL_DIR/blobs"; rmdir "$IL_DIR" 2>/dev/null || true
  echo "commandeck is out of this machine: Codex's hooks, the dashboard job and the permission rules"
elif [ -z "$LAST" ]; then
  echo "the machine's parts stay for: $(il_projects | xargs -n1 jq -r .project | paste -sd' ' -)"
fi

if [ -n "$DELETE" ]; then
  # Only the plugin's own ledgers (and their locks): the folder may hold the
  # owner's or another tool's files, which setup never recorded.
  pp_rm_rf "$PP_MAIN/.claude/metrics/"{decisions,seat-events,unit-ledger,subagent-usage}.jsonl* "$PP_SCRATCH"
  rmdir "$PP_MAIN/.claude/metrics" 2>/dev/null || true
  # These three are kept by folder name. A project set up at another path
  # under the same name (this checkout moved) writes them now: they are its.
  SAME=
  while IFS= read -r m; do
    o=$(jq -r '.project // empty' "$m" 2>/dev/null || true); n=${o##*/}
    if [ -n "$o" ] && [ "$(pp_norm "$o")" != "$(pp_norm "$PP_MAIN")" ] && [ "${n//[^A-Za-z0-9_.-]/-}" = "$PROJECT" ]; then SAME=$o; fi
  done < <(il_projects)
  if [ -n "$SAME" ]; then
    echo "kept: the hook log, rulings and Chief-of-Staff state named $PROJECT; the project set up at $SAME uses them now"
  else
    rm -f "$HOME/.claude/hook-fire-log/$PROJECT".*.jsonl* "$HOME/.claude/rulings/$PROJECT.jsonl" "$HOME/.commandeck/chief-of-staff/$PROJECT".*
  fi
  # The finished-builds record is named by the folder's name too, and each line names the checkout that wrote it:
  # only this checkout's lines go, whoever else is or was set up under the name. A line that names no checkout, or
  # does not parse, is not this checkout's. A link is not a file the plugin made and is left alone. The read, the
  # rewrite and the removal of the emptied folder hold the lock a merge appends under, so a line a same-named
  # checkout's merge adds is never lost. The lock is on the home folder: this very step removes the builds folder.
  BUILDS=$HOME/.commandeck/builds/$PROJECT.jsonl
  if [ ! -L "${BUILDS%/*}" ]; then
    ( exec 8<"$HOME" && flock -w 5 8 || exit 1
      if [ -f "$BUILDS" ] && [ ! -L "$BUILDS" ]; then
        REST=$(mktemp "$BUILDS.XXXXXX") || exit 1
        jq -Rr --arg main "$(cd "$PP_MAIN" && pwd -P)" \
          '. as $l | (try fromjson catch null) as $j | select(($j | type) != "object" or $j.main != $main) | $l' "$BUILDS" > "$REST" \
          && { if [ -s "$REST" ]; then mv -f "$REST" "$BUILDS"; else rm -f "$REST" "$BUILDS"; fi; } || { rm -f "$REST"; exit 1; }
      fi
      rmdir "${BUILDS%/*}" 2>/dev/null || true
    ) || echo "uninstall: could not rewrite $BUILDS; the finished-builds record is left as it was" >&2
  fi
  if [ -n "$LAST" ]; then
    # Kept by session, not by project, so they can only go with the last one: the hook
    # log's retry markers and the restart hook's own log.
    pp_rm_rf "${XDG_CACHE_HOME:-$HOME/.cache}/commandeck" "$HOME/.claude/hook-fire-log/pending"
    rm -f "$HOME/.claude/checkpoints/clear-hook.log"
    # A project registered by hand keeps its line; the rest of the folder is the collector's output.
    D=$HOME/.commandeck/dashboard
    if [ -s "$D/projects" ]; then find "$D" -mindepth 1 ! -name projects -delete; else pp_rm_rf "$D"; fi
  fi
  # Only what is empty now: another project's data, or the owner's own folders, stay.
  for d in "$HOME/.claude/hook-fire-log" "$HOME/.claude/rulings" "$HOME/.claude/checkpoints" "$HOME/.commandeck/scratch" "$HOME/.commandeck/chief-of-staff" \
           "$HOME/.commandeck" "$PP_WORKSPACES" "${PP_WORKSPACES%/*}" "$HOME/orca" "$PP_MAIN/.claude"; do
    rmdir "$d" 2>/dev/null || true
  done
  echo "this project's data is deleted"
else
  echo "the data is kept (ledgers, scratch, logs); delete it with: bash $(printf '%q' "$HERE")/uninstall.sh --delete-data"
fi
