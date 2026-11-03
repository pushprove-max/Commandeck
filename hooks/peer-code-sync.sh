#!/usr/bin/env bash
# SessionStart hook (main checkout on branch main only, strict tier): code reaches GitHub only at push time, so
# another machine often holds newer main. This fast-forwards local main to the newest of origin/main and the peer's
# main when local main is a strict ancestor of it, and prints exactly one line. The peer is COMMANDECK_PEER_REPO
# (`<ssh host>:<path>`); unset, origin only. It never writes to the peer, merges, rebases or resets: every other
# case changes nothing. An unreachable peer is skipped; when origin still moved main the "synced" line wins. It
# stands down, with one line, while a merge holds main (merge-unit-local.state names a live pid, or the merge's
# lock is held): the fetch runs unlocked, the ancestry check and fast-forward run under that lock.
# Retire when: the peer machine is gone, or main is no longer a working checkout
set -u
IFS= read -r -d '' INPUT 2>/dev/null || true
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
[ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] || exit 0
[ "$(git symbolic-ref -q --short HEAD 2>/dev/null)" = main ] || exit 0
. "${BASH_SOURCE[0]%/*}/lib/project.sh" 2>/dev/null || exit 0
pp_is_main_pane || exit 0
pp_strict || exit 0
export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=5' GIT_TERMINAL_PROMPT=0
peer=${COMMANDECK_PEER_REPO:-}
CGD=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
BUSY="merge in progress, main not moved"
# live <common git dir>: a merge holds main with a live pid; a dead pid is stale (merge-lock-guard.sh's test).
PID=$(sed -n 's/^pid=//p' "$CGD/merge-unit-local.state" 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then echo "$BUSY"; exit 0; fi

was=$(git rev-parse HEAD) || exit 0
names=() shas=() peer_down=
if timeout 7 git fetch -q origin main </dev/null 2>/dev/null; then names+=(origin); shas+=("$(git rev-parse FETCH_HEAD)"); fi
if [ -n "$peer" ]; then
  if timeout 7 git fetch -q "$peer" main </dev/null 2>/dev/null; then
    names+=(peer); shas+=("$(git rev-parse FETCH_HEAD)")
  else
    peer_down=1
  fi
fi

sync_main() {
  local best= from= i c err
  for i in "${!shas[@]}"; do
    c=${shas[$i]}
    git merge-base --is-ancestor "$c" "$was" && continue
    git merge-base --is-ancestor "$was" "$c" \
      || { HOOK_FIRE_ADVISE=1; echo "WARN: diverged from ${names[$i]} (local main $was, ${names[$i]} $c); nothing changed"; return; }
    if [ -z "$best" ] || { [ "$c" != "$best" ] && git merge-base --is-ancestor "$best" "$c"; }; then
      best=$c from=${names[$i]}
    elif ! git merge-base --is-ancestor "$c" "$best"; then
      HOOK_FIRE_ADVISE=1; echo "WARN: diverged: origin $best and peer $c are both ahead of local main on different lines; nothing changed"; return
    fi
  done
  if [ -z "$best" ]; then
    if [ -n "$peer_down" ]; then echo "peer unreachable, skipped"; else echo "up to date"; fi
    return
  fi
  if ! err=$(git merge --ff-only -q "$best" 2>&1); then
    HOOK_FIRE_ADVISE=1; echo "WARN: fast-forward refused to $best from $from: $(printf '%s\n' "$err" | head -1)"; return
  fi
  echo "synced to $best from $from"
}
# A merge that started during the fetch holds this lock; the sync then leaves main alone.
{ flock -n 9 || { echo "$BUSY"; exit 0; }; sync_main; } 9>"$CGD/merge-unit-local.lock"
exit 0
