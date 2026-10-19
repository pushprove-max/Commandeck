#!/usr/bin/env bash
# plan-worktree-close.sh <unit> [--adopt] [--dry-run] -- close <unit>'s planning worktree (<unit>, made and marked by
# seat.sh) and its panes. Main runs it by hand on a rejected plan. Refused (exit 1, worktree kept) when the worktree
# holds a file that is not identical on local main, or a pane does not close. No planning worktree of that unit:
# silent, exit 0. --dry-run closes and removes nothing.
# --adopt: builder-launch.sh's way into the unit's planning worktree. The same checks and pane close, then the mark
# goes and the worktree stays for the Builder. Exit 0 adopted; exit 1 kept, with one "kept:" line saying why.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
UNIT=${1:?usage: plan-worktree-close.sh <unit> [--adopt] [--dry-run]}
DRY=0 ADOPT=0
for a in "${@:2}"; do case $a in --dry-run) DRY=1 ;; --adopt) ADOPT=1 ;; *) echo "unknown argument: $a" >&2; exit 2 ;; esac; done
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad unit name: $UNIT" >&2; exit 2; }
# Every git below reads $WT's own index and objects, never a routed one (GIT_INDEX_FILE, GIT_DIR, ...).
unset $(git rev-parse --local-env-vars) GIT_CEILING_DIRECTORIES
export GIT_LITERAL_PATHSPECS=1
marked() { [ "$(cat "$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)/commandeck-plan-of" 2>/dev/null)" = "$UNIT" ]; }
WT=$PP_WORKSPACES/$UNIT
# shortcut: a unit planned before 0.18.0 has its planning worktree at <unit>-plan; drop this line once no such unit is open.
[ "$ADOPT" = 1 ] || marked "$WT" || [ ! -d "$WT-plan" ] || WT=$WT-plan
[ -d "$WT" ] || { [ "$ADOPT" = 0 ] || echo "kept: $WT: no such worktree" >&2; exit "$ADOPT"; }
# The lock seat.sh takes to make and mark the worktree; held until this script exits.
mkdir -p "$PP_SCRATCH" && exec {LOCK_FD}>>"$PP_SCRATCH/$UNIT-plan-worktree.lock" && flock -w 600 "$LOCK_FD" \
  || { echo "cannot lock $PP_SCRATCH/$UNIT-plan-worktree.lock; $WT left in place" >&2; exit 1; }
marked "$WT" || { [ "$ADOPT" = 1 ] && echo "kept: $WT: not $UNIT's planning worktree" >&2 || echo "left $WT: not $UNIT's planning worktree"; exit "$ADOPT"; }
LIST=$(mktemp) SETF=$(mktemp); SETDONE=0; trap 'rm -f "$LIST" "$SETF"' EXIT

# "<mode> <id>" of a path on local main, empty when main lacks it.
main_of() { git -C "$WT" ls-tree refs/heads/main -- "$1" | awk -F'[ \t]' 'NR==1 { print $1 " " $3 }'; }
r_head() { git -C "$WT" ls-tree HEAD -- "$1" | awk -F'[ \t]' 'NR==1 { print $1 " " $3 }'; }
r_index() { git -C "$WT" ls-files -s -- "$1" | awk -F'[ \t]' 'NR==1 { print $1 " " $2 }'; }
# The working tree's file as git would store it: a symlink by its link text, 100755 when executable.
r_tree() {
  local f=$WT/$1 m=100644
  if [ -L "$f" ]; then echo "120000 $(readlink -n -- "$f" | git hash-object --stdin)"
  elif [ -f "$f" ]; then [ ! -x "$f" ] || m=100755; echo "$m $(git -C "$WT" hash-object -- "$1")"
  elif [ -e "$f" ]; then echo "not a file"; fi
}
# What worktree-setup.sh leaves behind: the node_modules links to main's, and its settings file.
setup_made() {
  local a
  case $1 in
    node_modules|web/node_modules|infra/node_modules)
      [ -L "$WT/$1" ] && a=$(cd "$WT/$1" 2>/dev/null && pwd -P) && [ -n "$a" ] && [ "$a" = "$(cd "$PP_MAIN/$1" 2>/dev/null && pwd -P)" ] ;;
    .claude/settings.local.json)
      [ -f "$WT/$1" ] && [ ! -L "$WT/$1" ] || return 1
      [ "$SETDONE" = 1 ] || { SETDONE=1; bash "$HERE/worktree-setup.sh" "$WT" --print-settings > "$SETF" 2>/dev/null || : > "$SETF"; }
      # Compared as JSON (members are unordered): an older generator wrote the same keys in another order (issue 204).
      [ -s "$SETF" ] && a=$(jq -S . "$WT/$1" 2>/dev/null) && [ -n "$a" ] && [ "$a" = "$(jq -S . "$SETF")" ] ;;
    *) return 1 ;;
  esac
}
# scan <layer> <reader> <git args> -- every path git lists must read the same as on main; HIT names the first that does not.
scan() {
  local layer=$1 reader=$2 p; shift 2
  git -C "$WT" "$@" > "$LIST" || { HIT="(git $1 failed) ($layer)"; return 0; }
  while IFS= read -r -d '' p; do
    case $layer in untracked|ignored) ! setup_made "$p" || continue ;; esac
    [ "$layer" != ignored ] || { HIT="$p ($layer)"; return 0; }
    [ "$($reader "$p")" = "$(main_of "$p")" ] || { HIT="$p ($layer)"; return 0; }
  done < "$LIST"
  return 1
}
HIT=
dirty() {
  local B; HIT=
  B=$(git -C "$WT" merge-base HEAD refs/heads/main) || { HIT="(no merge base with main) (commits)"; return 0; }
  # git diff skips assume-unchanged and skip-worktree entries, and r_index reads one stage of a conflict: refuse them all.
  L=$(git -C "$WT" ls-files -v -z | tr '\0' '\n') || { HIT="(git ls-files failed) (index flags)"; return 0; }
  L=$(grep -m1 '^[^H] ' <<<"$L") && { HIT="${L#? } (index flags)"; return 0; }
  scan commits r_head diff --no-renames --name-only -z "$B" HEAD && return 0
  scan index r_index diff --cached --no-renames --name-only -z HEAD && return 0
  scan "working tree" r_tree diff --no-renames --name-only -z HEAD && return 0
  scan untracked r_tree ls-files -z --others --exclude-standard && return 0
  scan ignored r_tree ls-files -z --others --ignored --exclude-standard --directory && return 0
  return 1
}
refuse() {
  dirty || return 0
  [ "$ADOPT" = 0 ] || { echo "kept: $WT holds $HIT, not identical on local main; the Builder's launch resets it to main$1" >&2; exit 1; }
  echo "REFUSED: $WT holds $HIT, not identical on local main; left in place (bash $PP_SCRIPTS_Q/plan-worktree-close.sh $UNIT once it is)$1" >&2
  exit 1
}
panes() {
  local out; out=$(timeout 10 orca-ide terminal list --json 2>/dev/null) \
    && jq -e . <<<"$out" >/dev/null && jq -r --arg wt "$WT" "$PP_PNORM"'($wt | pnorm) as $wt | (.result | if type == "array" then . elif (.terminals | type) == "array" then .terminals else error("not a terminal list") end)[]
      | select((wtp | pnorm) == $wt) | .handle' <<<"$out"
}

refuse ""
PL=$(panes) || { echo "kept: $WT: terminal list failed" >&2; exit 1; }
N=0; [ -z "$PL" ] || N=$(printf '%s\n' "$PL" | wc -l | tr -d ' ')
[ "$DRY" = 0 ] || { echo "would close $N panes and $([ "$ADOPT" = 1 ] && echo adopt || echo remove) $WT"; exit 0; }
while IFS= read -r h; do
  [ -z "$h" ] || timeout 20 orca-ide terminal close --terminal "$h" --json >/dev/null 2>&1 || KEPT="${KEPT:-}$h"$'\n'
done <<<"$PL"
bash "$HERE/codex-helpers.sh" stop "$WT" || true
LEFT=$(panes) || { echo "kept: $WT: terminal list failed" >&2; exit 1; }
# A pane that closed non-zero or is still listed.
BAD=$(printf '%s\n%s\n' "${KEPT:-}" "$LEFT" | awk 'NF && !s[$0]++')
if [ -n "$BAD" ]; then
  while IFS= read -r h; do echo "kept: $WT: pane $h did not close" >&2; done <<<"$BAD"
  exit 1
fi
refuse " (written while panes closed)"
[ "$ADOPT" = 0 ] || { rm -f "$(git -C "$WT" rev-parse --absolute-git-dir)/commandeck-plan-of" && echo "adopted $WT"; exit; }
orca-ide worktree remove --worktree "path:$WT" --force >/dev/null || { echo "kept: $WT: worktree remove failed" >&2; exit 1; }
echo "closed ${WT##*/}"
