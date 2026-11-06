#!/usr/bin/env bash
# Self-test for the publishing guards in .githooks/pre-push: a push from a linked worker checkout, or under a
# headless `claude -p` process, is refused.
#
# The refs being pushed arrive on stdin as <local ref> <local sha> <remote ref> <remote sha>. Every case pushes the
# all-zero (deleted) sha, so the shell-test run behind the guards never starts: only the guards are judged.
#
# Every case runs the hook end to end in a throwaway repo. Grep cannot tell a
# gate that blocks from one that prints and exits 0.
set -u

ROOT=$(git rev-parse --show-toplevel)
PREPUSH="$ROOT/.githooks/pre-push"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX"' EXIT

cat > "$SANDBOX/ancestor-driver" <<'EOF'
#!/usr/bin/env bash
kind=$1 hook=$2 local_sha=$3 remote_sha=$4
case "$kind" in
  none) bash "$hook" origin git@example:x.git <<<"refs/heads/main $local_sha refs/heads/main $remote_sha" ;;
  codex|bwrap)
    exec -a "$kind" python3 -c 'import subprocess, sys; line=f"refs/heads/main {sys.argv[2]} refs/heads/main {sys.argv[3]}\n"; raise SystemExit(subprocess.run(["bash", sys.argv[1], "origin", "git@example:x.git"], input=line, text=True).returncode)' "$hook" "$local_sha" "$remote_sha"
    ;;
  claude-p|claude-print)
    [ "$kind" = claude-p ] && flag=-p || flag=--print
    # bash, not python3: Homebrew's python3 re-execs itself and drops argv0.
    exec -a claude bash -c 'bash "$1" origin git@example:x.git <<<"refs/heads/main $2 refs/heads/main $3"; exit $?' \
      _ "$hook" "$local_sha" "$remote_sha" "$flag"
    ;;
esac
EOF
chmod +x "$SANDBOX/ancestor-driver"

# A sandbox repo with two commits: `base` stands in for the remote's tip, `tip` adds a file.
build_repo() {  # <path>[:<content>] ... added by the second commit
  rm -rf "$SANDBOX"/repo "$SANDBOX"/linked && mkdir -p "$SANDBOX"/repo
  (
    cd "$SANDBOX"/repo || exit 1
    git init -q -b main . && git config user.email t@t.t && git config user.name t
    echo seed > README.md && git add -A && git commit -qm base
    git update-ref refs/remotes/origin/main HEAD
    for spec in "$@"; do
      path=${spec%%:*}; content=${spec#*:}; [ "$content" = "$path" ] && content='note'
      mkdir -p "$(dirname "$path")" && printf '%s\n' "$content" > "$path"
    done
    git add -A && git commit -qm tip
  ) >/dev/null 2>&1
}

sha() { git -C "$SANDBOX"/repo rev-parse "$1"; }

run_role_prepush() {  # $1 = primary|subdir|linked, $2 = ancestry; rest = env
  local topology=$1 ancestry=$2 target; shift 2
  build_repo docs/notes.md
  mkdir -p "$SANDBOX/repo/subdir"
  case "$topology" in
    primary) target="$SANDBOX/repo" ;;
    subdir) target="$SANDBOX/repo/subdir" ;;
    linked)
      git -C "$SANDBOX/repo" worktree add -q --detach "$SANDBOX/linked" HEAD
      target="$SANDBOX/linked"
      ;;
  esac
  (
    cd "$target" || exit 1
    env -i PATH="$PATH" "$@" \
      "$SANDBOX/ancestor-driver" "$ancestry" "$PREPUSH" "$ZERO" "$(sha HEAD~1)"
  ) > /dev/null 2>"$SANDBOX/role.err"
  echo $?
}

# Publishing authority comes from checkout topology, not provider identity.
ZERO=0000000000000000000000000000000000000000
# Catches a guard that blocks the primary checkout, or one that stops reading ancestry or topology.
check "primary push role passes with provider env unset" 0 "$(run_role_prepush primary none)"
check "primary subdirectory push role passes with provider env set" 0 \
  "$(run_role_prepush subdir none CODEX_HOME=/tmp/provider CODEX_OTHER=present)"
check "foreground codex ancestry in primary passes push role" 0 "$(run_role_prepush primary codex)"
check "foreground bwrap ancestry in primary passes push role" 0 "$(run_role_prepush primary bwrap)"
# Catches a pre-push that drops its topology call: a linked worker would publish.
check "a linked push is refused" 1 "$(run_role_prepush linked none)"
check "a linked push is refused: the refusal occurs in agent guard" 0 \
  "$(grep -q 'agent-guard: BLOCKED' "$SANDBOX/role.err" && echo 0 || echo 1)"
check "provider-marked linked worker is refused by agent guard" 1 \
  "$(run_role_prepush linked none CODEX_HOME=/tmp/provider)"
check "linked-worktree override permits the push role" 0 \
  "$(run_role_prepush linked none COMMANDECK_ALLOW_WORKTREE_PUSH=1)"
# Catches a pre-push that drops its ancestry call: the worktree override must not excuse a headless claude.
check "headless -p is refused with the override (claude -p)" 1 \
  "$(run_role_prepush primary claude-p COMMANDECK_ALLOW_WORKTREE_PUSH=1)"
check "headless -p is refused with the override (claude --print)" 1 \
  "$(run_role_prepush primary claude-print COMMANDECK_ALLOW_WORKTREE_PUSH=1)"
# macOS has no /proc; the ps branch must refuse the same ancestry, and the
# foreground push must still pass through it.
check "headless claude -p ancestry is refused on the Mac branch" 1 \
  "$(run_role_prepush primary claude-p COMMANDECK_ALLOW_WORKTREE_PUSH=1 COMMANDECK_HOST_OS=Darwin)"
check "headless claude --print ancestry is refused on the Mac branch" 1 \
  "$(run_role_prepush primary claude-print COMMANDECK_ALLOW_WORKTREE_PUSH=1 COMMANDECK_HOST_OS=Darwin)"
check "primary push role passes on the Mac branch" 0 \
  "$(run_role_prepush primary none COMMANDECK_HOST_OS=Darwin)"
# The Fast lane may commit but never push: only pre-commit lets it through.
build_repo docs/notes.md
mkdir -p "$SANDBOX/ws"
git -C "$SANDBOX/repo" worktree add -q --detach "$SANDBOX/ws/Fast-lane" HEAD
LANE_PUSH_RC=$(cd "$SANDBOX/ws/Fast-lane" && env -i PATH="$PATH" COMMANDECK_WORKSPACES="$SANDBOX/ws" \
  "$SANDBOX/ancestor-driver" none "$PREPUSH" "$ZERO" "$(sha HEAD~1)" >/dev/null 2>"$SANDBOX/role.err"; echo $?)
check "a push from the Fast lane worktree is still refused" "1 0" \
  "$LANE_PUSH_RC $(grep -q 'agent-guard: BLOCKED' "$SANDBOX/role.err" && echo 0 || echo 1)"

# Issue 667, never a full retest: unlike the cases above, these pushes run the shell tests, through the real runner
# copied into the repo. Each push tests in its own temporary worktree, so a pass is reused only if the ledger outlives
# it. p3 reads target3.sh and fails while $PPRED exists; p1 and p2 read nothing that changes.
PP=$SANDBOX/pp; mkdir -p "$PP/scripts/__tests__" "$PP/docs"; cp "$ROOT"/scripts/*.sh "$PP/scripts/"
for n in 1 2; do printf '#!/usr/bin/env bash\necho p%s >> "$PPRAN"\n' "$n" > "$PP/scripts/__tests__/p$n.test.sh"; done
printf '#!/usr/bin/env bash\n# reads target3.sh\necho p3 >> "$PPRAN"\n[ ! -e "$PPRED" ]\n' > "$PP/scripts/__tests__/p3.test.sh"
echo v1 > "$PP/scripts/target3.sh"; echo n1 > "$PP/docs/notes.md"
git -C "$PP" init -q -b main && git -C "$PP" add -A && git -C "$PP" -c user.name=t -c user.email=t@t commit -qm c1
export PPRAN=$SANDBOX/ppran PPRED=$SANDBOX/ppred
# pp_push <file> <text>: commit the change (none for the first push), push HEAD to main, log `<rc>:<files run>`.
pp_push() {
  [ -z "${1-}" ] || { echo "$2" > "$PP/$1"; git -C "$PP" -c user.name=t -c user.email=t@t commit -qam "$1"; }
  : > "$PPRAN"
  (cd "$PP" && printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" "$ZERO" | bash "$PREPUSH" origin x) > /dev/null 2>&1
  PPLOG+="$?:$(sort "$PPRAN" | paste -sd, -) "
}
PPLOG=; touch "$PPRED"; pp_push; rm -f "$PPRED"
pp_push scripts/target3.sh v2; pp_push docs/notes.md n2; pp_push scripts/target3.sh v3
check "pre_push_reuses_passed_files_for_same_inputs: after p3 fails, a push changing its input runs p3 alone, a push changing no input runs nothing, a later change to it runs p3 again" \
  "1:p1,p2,p3 0:p3 0: 0:p3 " "$PPLOG"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
