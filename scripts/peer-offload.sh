#!/usr/bin/env bash
# peer-offload.sh -- sourced, never run. Runs a command on the peer (the PC) against this checkout's exact tree, so a
# Mac linked worktree's shell tests run there, not here (owner ruling 2026-10-25; ported from the host's pr_stage and
# pr_offload). The peer is ~/.config/devenv/peer on this host, an ssh destination.
PO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pr_ssh() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$@"; }
pr_peer() { tr -d '[:space:]' 2>/dev/null < "$HOME/.config/devenv/peer"; }

# pr_stage <checkout> <target> <bundle file> -- stage <checkout>'s HEAD, unpushed commits included, on the peer. Sets
# PR_HEAD, PR_TREE, PR_BASE (the merge-base with this host's origin/main) and PR_STAGE: remote lines, run in the
# peer's repository, that fetch that base by id when it is missing (from the peer repository's origin, then from this
# checkout's origin URL), apply a bundle of the commits on top of it, and refuse unless PR_HEAD then exists there with
# the exact tree.
pr_stage() {
  local co=$1 target=$2 bundle=$3 base fetch= url
  PR_HEAD=$(git -C "$co" rev-parse HEAD) && PR_TREE=$(git -C "$co" rev-parse 'HEAD^{tree}') || return 2
  base=$(git -C "$co" merge-base HEAD origin/main) || { echo "HEAD shares no base with origin/main to stage it on $target from; nothing started" >&2; return 2; }
  PR_BASE=$base
  if [ "$base" != "$PR_HEAD" ]; then
    git -C "$co" bundle create "$bundle" HEAD "^$base" 2>/dev/null || { echo "cannot bundle $PR_HEAD on top of $base; nothing started" >&2; return 2; }
    fetch="b=\$(mktemp) && base64 -d > \"\$b\" <<'PEER_BUNDLE' || exit 2
$(base64 < "$bundle")
PEER_BUNDLE
git fetch -q \"\$b\" HEAD || { echo 'the bundle for $PR_HEAD did not apply on $target; nothing started'; rm -f \"\$b\"; exit 2; }
rm -f \"\$b\""
    rm -f "$bundle"
  fi
  # Fetching by id moves no ref anywhere; </dev/null keeps a nested ssh off this script's stdin.
  url=$(git -C "$co" remote get-url origin 2>/dev/null)
  PR_STAGE="for src in origin $(printf '%q' "$url"); do
  git cat-file -e '$base^{commit}' 2>/dev/null && break
  [ -z \"\$src\" ] || GIT_TERMINAL_PROMPT=0 git fetch -q \"\$src\" '$base' </dev/null 2>/dev/null
done
git cat-file -e '$base^{commit}' 2>/dev/null || { echo \"\$PWD on $target lacks the common base $base and cannot fetch it from its origin or ${url:-an origin URL}; nothing started\"; exit 2; }
$fetch
[ \"\$(git rev-parse '$PR_HEAD^{tree}' 2>/dev/null)\" = $PR_TREE ] || { echo '$PR_HEAD with tree $PR_TREE is not on $target; nothing started'; exit 2; }"
}

# pr_offload <command> [args...] -- run a command on the peer against this checkout's exact tree: HEAD staged with
# pr_stage, the uncommitted work (untracked files included) as a patch applied in a scratch worktree of the peer's
# repository (~/.cache/commandeck-offload/repo, created on first use), and the tree there compared with the one hashed
# here. The command runs from the checkout's top folder; an argument under this checkout is rewritten to the scratch
# copy. Output streams; the control lines are `offload: started on <peer> tree <short>`, printed only once the memory
# cage has started the command, and `offload: exit <rc>`.
#   0 green; 1 the command ran there and was red (its own 2, 3 and 4 become 1; a red run is never run again here), or
#   no status came back from a session that was established (the PC may still be running it; never run again here);
#   2 refused: the PC's nonce refusal line, or a failure here once the run is routed (snapshot, staging, temp files,
#   the nonce, a script or git that fails); 3 not routed; 4 unreachable (no peer, or ssh failed before the session was
#   established). The code is the whole outcome (Decision G13-3, revision 7): a caller runs the command here only on
#   exactly 3 or 4, and every other code is final.
# Routes only a Mac linked worktree whose chain host is pc, outside a test run (COMMANDECK_HOOK_FIRE_LOG unset) and
# not on the peer itself (COMMANDECK_OFFLOADED unset). Run from the checkout's top folder.
pr_offload() {
  [ -z "${COMMANDECK_OFFLOADED:-}" ] || return 3
  . "$PO_DIR/host-services.sh" || { echo "offload: $PO_DIR/host-services.sh did not load" >&2; return 2; }
  local peer root gdir cdir idx= tree patch= bundle= log= slog= nonce envs='' argv='' arg v rc orc
  [ -z "${COMMANDECK_HOOK_FIRE_LOG:-}" ] && [ "$(hs_os)" = Darwin ] && [ "$(hs_chain_host 2>/dev/null)" = pc ] || return 3
  root=$(git rev-parse --show-toplevel 2>/dev/null) \
    && gdir=$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P) && cdir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P) \
    || { echo "offload: git could not name this checkout's folders" >&2; return 2; }
  [ "$gdir" != "$cdir" ] || return 3
  peer=$(pr_peer || true)
  [ -n "$peer" ] || { echo "offload: no peer in ~/.config/devenv/peer; running here" >&2; return 4; }
  # unavail <code> <reason>: the one line a caller that runs the command here (4), or fails (2), prints first.
  unavail() { echo "offload: $2" >&2; rm -f "$idx" "$patch" "$bundle" "$log" "$slog"; return "$1"; }
  idx=$(mktemp) && patch=$(mktemp) && bundle=$(mktemp) && log=$(mktemp) && slog=$(mktemp) \
    || { unavail 2 "could not make the hand-off's temp files in ${TMPDIR:-/tmp}"; return; }
  # -p keeps the mtime git's racy-entry check needs.
  cp -p "$(git rev-parse --path-format=absolute --git-path index)" "$idx" \
    && GIT_INDEX_FILE=$idx git add -A >/dev/null 2>&1 \
    && GIT_INDEX_FILE=$idx git diff --cached --binary --no-renames HEAD > "$patch" \
    || { unavail 2 "could not snapshot this tree"; return; }
  tree=$(GIT_INDEX_FILE=$idx git write-tree) || { unavail 2 "could not hash this tree"; return; }
  pr_stage "$root" "$peer" "$bundle" || { unavail 2 "staging $root for $peer failed (above)"; return; }
  # An argument under this checkout is the scratch copy's on the peer; %q keeps each one word there.
  for arg in "$@"; do
    case $arg in "$root"|"$root"/*) arg=@@ROOT@@${arg#"$root"} ;; esac
    argv+=$(printf '%q ' "$arg")
  done
  # The selectors the runner and its tests read travel; nothing else of this host's environment does.
  for v in $(compgen -e); do
    case $v in COMMANDECK_SHELL_TEST_*|*_TEST_CASE) ;; *) continue ;; esac
    envs+="export $v=$(printf '%q' "${!v}")"$'\n'
  done
  nonce=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
  [[ $nonce =~ ^[0-9a-f]{16}$ ]] || { unavail 2 "could not make a nonce for the run's status lines"; return; }
  # ssh's own log (-E, apart from the remote output) holds `Authenticated to` once the session is established, before
  # the command is sent; a shared connection would log none, so this call never rides one (Decision G13-3).
  pr_ssh -E "$slog" -o LogLevel=VERBOSE -o ControlMaster=no -o ControlPath=none -o ServerAliveInterval=15 -o ServerAliveCountMax=4 \
    "$peer" 'PATH=/opt/homebrew/bin:$PATH exec bash -s' <<EOF | tee "$log" | sed -u '/^offload-done: /d;/^offload-exit: /d;/^offload-started: /d;/^offload-refused: /d'
R=\$HOME/.cache/commandeck-offload/repo
S=
# Every refusal here exits 2 before the command starts; this trap then says so on a nonce line, the one proof of a
# refusal. A 2 after the start marker is the command's own.
trap 'rc=\$?; [ "\$rc" != 2 ] || { [ -n "\$S" ] && [ -e "\$S/started" ]; } || echo "offload-refused: $nonce"
[ -z "\$S" ] || { git -C "\$R" worktree remove --force "\$S/w" 2>/dev/null; rm -rf "\$S"; }' EXIT
[ -d "\$R/.git" ] || { mkdir -p "\$R" && git -C "\$R" init -q; } || { echo "cannot create \$R on $peer"; exit 2; }
cd "\$R" || exit 2
$PR_STAGE
S=\$(mktemp -d "\$HOME/.cache/commandeck-offload/run.XXXXXX") || exit 2
git worktree add -q --detach "\$S/w" $PR_HEAD || exit 2
W=\$S/w
cd "\$W"
base64 -d > "\$S/p.diff" <<'PEER_PATCH' || exit 2
$(base64 < "$patch")
PEER_PATCH
[ ! -s "\$S/p.diff" ] || git apply --whitespace=nowarn "\$S/p.diff" || { echo "the patch did not apply on $peer at $PR_HEAD; nothing ran"; exit 2; }
[ "\$(git add -A >/dev/null 2>&1; git write-tree)" = $tree ] || { echo "the tree on $peer after the patch is not the tree sent ($tree); nothing ran"; exit 2; }
$envs
export COMMANDECK_OFFLOADED=1
unset COMMANDECK_HOST_OS
ARGV=( $argv )
for i in "\${!ARGV[@]}"; do ARGV[i]=\${ARGV[i]//@@ROOT@@/\$W}; done
. "\$W/scripts/host-services.sh" && hs_cage 16G || { echo 'no memory cage on $peer'; exit 2; }
# "started" is printed from inside the cage, so a cage that fails to start never claims it; no exit line is the
# refused path. The marker is the only proof the command ran: one that cannot be written stops it before the exec.
"\${HS_CAGE[@]}" bash -c ': > "\$1" || exit 1; shift; echo "offload-started: $nonce"; echo "offload: started on $peer tree ${tree:0:8}"; exec "\$@"' _ "\$S/started" "\${ARGV[@]}" </dev/null
rc=\$?
[ -e "\$S/started" ] || { echo "REFUSED: the memory cage on $peer, or its start marker, failed (exit \$rc) before the command started; nothing ran"; exit 2; }
echo "offload-exit: $nonce \$rc"
echo "offload: exit \$rc"
echo "offload-done: $nonce"
EOF
  orc=${PIPESTATUS[0]}
  # The nonce makes the status the script's own, never a line the command printed. A status that arrived is the
  # result even if the connection then dropped.
  rc=$(sed -n "s/^offload-exit: $nonce \([0-9][0-9]*\)\$/\1/p" "$log" | tail -1)
  if [ -n "$rc" ]; then
    rm -f "$idx" "$patch" "$bundle" "$log" "$slog"
    case $rc in 2|3|4) rc=1 ;; esac
    return "$rc"
  fi
  grep -qx "offload-refused: $nonce" "$log" && { unavail 2 "the PC refused the run (reason above)"; return; }
  # No status line: what did not arrive proves nothing about what the PC did. Only ssh's own failure before the
  # session was established (255, no `Authenticated to` in its log) proves nothing started there.
  # grep's 1 is "read it, no such line"; its 2 (an unreadable log) proves nothing.
  grep -q '^Authenticated to ' "$slog"; v=$?
  if [ "$orc" = 255 ] && [ "$v" = 1 ]; then
    unavail 4 "ssh to $peer failed: unreachable or asleep"; return
  fi
  rm -f "$idx" "$patch" "$bundle" "$log" "$slog"
  echo "offload: no result came back from $peer (ssh exit $orc); the PC may still be running it, and it is not run again here" >&2
  return 1
}
