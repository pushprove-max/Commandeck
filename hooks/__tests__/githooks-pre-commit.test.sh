#!/usr/bin/env bash
# Self-test for .githooks/pre-commit -- the guard that keeps a linked worker checkout and a headless
# `claude -p` process from committing.
#
# It is the ONLY lens on that rule, and it is a wide one: it runs at the git layer, so a commit made from inside a
# script and a commit made outside Claude Code entirely are all judged the same. A hook that stopped blocking would
# take the rule with it -- which is why this runs the hook end to end rather than grepping it.
set -u

ROOT=$(git rev-parse --show-toplevel)
PRECOMMIT="$ROOT/.githooks/pre-commit"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX"' EXIT

# Role is checkout topology, not provider identity. Exercise real primary and
# linked checkouts, plus controlled process ancestry and Git lookup failures.
REAL_GIT=$(command -v git)
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/git" <<EOF
#!/usr/bin/env bash
case "\${COMMANDECK_TEST_GIT_TOPOLOGY:-}" in
  failed) case "\$*" in *rev-parse*) exit 1 ;; esac ;;
  empty) case "\$*" in *rev-parse*) exit 0 ;; esac ;;
esac
exec "$REAL_GIT" "\$@"
EOF
cat > "$SANDBOX/ancestor-driver" <<'EOF'
#!/usr/bin/env bash
kind=$1 hook=$2
case "$kind" in
  none) bash "$hook" ;;
  codex|bwrap)
    exec -a "$kind" python3 -c 'import subprocess, sys; raise SystemExit(subprocess.run(["bash", sys.argv[1]]).returncode)' "$hook"
    ;;
  claude-p|claude-print|claude-text)
    case "$kind" in
      claude-p) flag=-p ;;
      claude-print) flag=--print ;;
      claude-text) flag=prefix--print ;;
    esac
    # bash, not python3: Homebrew's python3 re-execs itself and drops argv0.
    exec -a claude bash -c 'bash "$1"; exit $?' _ "$hook" "$flag"
    ;;
esac
EOF
chmod +x "$SANDBOX/bin/git" "$SANDBOX/ancestor-driver"

run_role_precommit() {  # $1 = primary|subdir|linked, $2 = ancestry; rest = env
  local topology=$1 ancestry=$2 target; shift 2
  rm -rf "$SANDBOX/primary" "$SANDBOX/linked"
  mkdir -p "$SANDBOX/primary/subdir"
  (
    cd "$SANDBOX/primary" || exit 1
    "$REAL_GIT" init -q . && "$REAL_GIT" config user.email t@t.t && "$REAL_GIT" config user.name t
    echo seed > seed.txt && "$REAL_GIT" add seed.txt && "$REAL_GIT" commit -qm seed
  )
  case "$topology" in
    primary) target="$SANDBOX/primary" ;;
    subdir) target="$SANDBOX/primary/subdir" ;;
    linked)
      "$REAL_GIT" -C "$SANDBOX/primary" worktree add -q --detach "$SANDBOX/linked" HEAD
      target="$SANDBOX/linked"
      ;;
  esac
  echo ordinary > "$target/notes.md"
  "$REAL_GIT" -C "$target" add notes.md
  (
    cd "$target" || exit 1
    env -i PATH="$SANDBOX/bin:$PATH" "$@" "$SANDBOX/ancestor-driver" "$ancestry" "$PRECOMMIT"
  ) > /dev/null 2>"$SANDBOX/role.err"
  echo $?
}

# Catches a guard that stops reading the real checkout and lets a primary commit fail or a worker commit pass.
check "primary checkout passes with provider env unset" 0 "$(run_role_precommit primary none)"
check "primary subdirectory passes with provider env set" 0 "$(run_role_precommit subdir none CODEX_HOME=/tmp/provider CODEX_OTHER=present)"
check "foreground codex ancestry in primary passes" 0 "$(run_role_precommit primary codex)"
check "foreground bwrap ancestry in primary passes" 0 "$(run_role_precommit primary bwrap)"
# Catches a topology guard that waves a linked worker through.
check "a bare linked commit is refused" 1 "$(run_role_precommit linked none)"
check "a bare linked commit is refused: the refusal carries the agent-guard diagnostic" 0 \
  "$(grep -q 'agent-guard: BLOCKED' "$SANDBOX/role.err" && echo 0 || echo 1)"
# Catches a guard that trusts provider env as authority.
check "provider-marked linked worker is refused" 1 "$(run_role_precommit linked none CODEX_HOME=/tmp/provider)"
check "provider-marked linked refusal carries the agent-guard diagnostic" 0 \
  "$(grep -q 'agent-guard: BLOCKED' "$SANDBOX/role.err" && echo 0 || echo 1)"
# Catches a topology guard that fails open when git cannot answer.
check "failed Git topology is refused" 1 "$(run_role_precommit primary none COMMANDECK_TEST_GIT_TOPOLOGY=failed)"
check "empty Git topology is refused" 1 "$(run_role_precommit primary none COMMANDECK_TEST_GIT_TOPOLOGY=empty)"
# Catches an ancestry walk that misses a headless claude, or blocks on text that only looks like the flag.
check "headless -p git is refused (exact claude -p)" 1 "$(run_role_precommit primary claude-p)"
check "headless -p git is refused (exact claude --print)" 1 "$(run_role_precommit primary claude-print)"
check "flag-like claude argument text passes" 0 "$(run_role_precommit primary claude-text)"
# Catches an override that no longer reaches the guard (the plugin's own scripts commit in linked worktrees with it).
check "the agent override permits linked commit" 0 \
  "$(run_role_precommit linked none COMMANDECK_ALLOW_AGENT_GIT=1)"
check "the override lets it through: a bare linked commit without it stays refused" "0 1" \
  "$(a=$(run_role_precommit linked none COMMANDECK_ALLOW_AGENT_GIT=1); b=$(run_role_precommit linked none); echo "$a $b")"

# The Fast lane is the one linked worktree that may commit: the canonical $COMMANDECK_WORKSPACES/Fast-lane of this
# repo, interactive. Every case sets HOME or COMMANDECK_WORKSPACES inside the sandbox, never the real $HOME.
WS="$SANDBOX/ws"; LANE="$WS/Fast-lane"
cat > "$SANDBOX/lane-commit" <<'EOF'
#!/usr/bin/env bash
kind=$1 lane=$2
exec -a "$kind" bash -c 'git -C "$1" commit --allow-empty -m helper; exit $?' _ "$lane"
EOF
chmod +x "$SANDBOX/lane-commit"
mk_lane() {  # rebuilds the repo with the canonical Fast-lane (staged notes.md), a Fast-lane-x and an out-of-path helper/Fast-lane
  rm -rf "$SANDBOX/primary" "$WS" "$SANDBOX/helper"; mkdir -p "$SANDBOX/primary" "$WS" "$SANDBOX/helper"
  (
    cd "$SANDBOX/primary" || exit 1
    "$REAL_GIT" init -q . && "$REAL_GIT" config user.email t@t.t && "$REAL_GIT" config user.name t \
      && "$REAL_GIT" config core.hooksPath "$ROOT/.githooks"
    echo seed > seed.txt && "$REAL_GIT" add seed.txt && "$REAL_GIT" commit -qnm seed
  )
  "$REAL_GIT" -C "$SANDBOX/primary" worktree add -q -b lane "$LANE" HEAD
  "$REAL_GIT" -C "$SANDBOX/primary" worktree add -q -b lanex "$WS/Fast-lane-x" HEAD
  "$REAL_GIT" -C "$SANDBOX/primary" worktree add -q -b helper "$SANDBOX/helper/Fast-lane" HEAD
  for d in "$LANE" "$WS/Fast-lane-x"; do echo ordinary > "$d/notes.md"; "$REAL_GIT" -C "$d" add notes.md; done
}
lane_precommit() {  # $1 = checkout, $2 = ancestry; rest = env
  local dir=$1 ancestry=$2; shift 2
  ( cd "$dir" && env -i PATH="$PATH" HOME="$SANDBOX/nohome" COMMANDECK_WORKSPACES="$WS" "$@" "$SANDBOX/ancestor-driver" "$ancestry" "$PRECOMMIT" ) >/dev/null 2>"$SANDBOX/role.err"
  echo $?
}
lane_commits() { "$REAL_GIT" -C "$1" rev-list --count HEAD; }
lane_helper_commit() {  # $1 = argv0 of the ancestor, $2 = checkout: exit code and commits gained
  local before rc; before=$(lane_commits "$2")
  env -i PATH="$PATH" HOME="$SANDBOX" COMMANDECK_WORKSPACES="$WS" "$SANDBOX/lane-commit" "$1" "$2" >/dev/null 2>"$SANDBOX/role.err"; rc=$?
  echo "$rc $(( $(lane_commits "$2") - before ))"
}
mk_lane
# Catches a Fast lane that is refused like any other worker, or a lane check that lets any Fast-lane-looking folder in.
check "only the canonical Fast lane commits (an interactive pane in the Fast lane may commit)" 0 "$(lane_precommit "$LANE" none)"
check "a headless claude in the Fast lane is still refused" 1 "$(lane_precommit "$LANE" claude-p)"
check "only the canonical Fast lane commits (a look-alike Fast-lane-x worker is refused)" 1 "$(lane_precommit "$WS/Fast-lane-x" none)"
check "only the canonical Fast lane commits (a linked worktree named Fast-lane outside the lane path is refused)" "1 0" \
  "$(echo helper > "$SANDBOX/helper/Fast-lane/h.md"; "$REAL_GIT" -C "$SANDBOX/helper/Fast-lane" add h.md
     b=$(lane_commits "$SANDBOX/helper/Fast-lane")
     env -i PATH="$PATH" HOME="$SANDBOX" COMMANDECK_WORKSPACES="$WS" "$REAL_GIT" -C "$SANDBOX/helper/Fast-lane" commit --allow-empty -m helper >/dev/null 2>&1; rc=$?
     echo "$rc $(( $(lane_commits "$SANDBOX/helper/Fast-lane") - b ))")"
check "a Codex process in the Fast lane may commit to the lane branch" "0 1" "$(lane_helper_commit codex "$LANE")"
check "an Agent helper under the lane's interactive claude may commit to the lane branch" "0 1" "$(lane_helper_commit claude "$LANE")"

# D13: the lane folder is COMMANDECK_WORKSPACES only when that is the checkout's real parent, else
# $HOME/orca/workspaces/<main folder name>. Catches a stray value (unset, empty, trailing slash, another folder) that
# moves the lane, which would refuse the real Fast lane or bless a folder that is not it.
mk_lane
DEF="$SANDBOX/home/orca/workspaces/primary"; mkdir -p "$DEF" "$SANDBOX/stray"
"$REAL_GIT" -C "$SANDBOX/primary" worktree add -q -b deflane "$DEF/Fast-lane" HEAD
echo ordinary > "$DEF/Fast-lane/notes.md"; "$REAL_GIT" -C "$DEF/Fast-lane" add notes.md
def_precommit() {  # rest = env for the default-folder lane
  ( cd "$DEF/Fast-lane" && env -i PATH="$PATH" HOME="$SANDBOX/home" "$@" "$SANDBOX/ancestor-driver" none "$PRECOMMIT" ) >/dev/null 2>&1
  echo $?
}
check "a stray workspaces value keeps the default lane (unset)" 0 "$(def_precommit)"
check "a stray workspaces value keeps the default lane (empty)" 0 "$(def_precommit COMMANDECK_WORKSPACES=)"
check "a stray workspaces value keeps the default lane (another folder)" 0 "$(def_precommit COMMANDECK_WORKSPACES="$SANDBOX/stray")"
check "a stray workspaces value keeps the default lane (a nonexistent folder)" 0 "$(def_precommit COMMANDECK_WORKSPACES="$SANDBOX/none")"
check "a stray workspaces value keeps the default lane (trailing slash)" 0 "$(def_precommit COMMANDECK_WORKSPACES="$SANDBOX/stray/")"
check "a stray workspaces value keeps the default lane (it blesses no other Fast-lane)" 1 \
  "$(lane_precommit "$SANDBOX/helper/Fast-lane" none COMMANDECK_WORKSPACES="$SANDBOX/stray")"
# Catches a lane that ignores a valid override: a Fast lane under a non-default parent commits only when that parent is named.
check "a workspaces value that is the real parent moves the lane" "0 1" \
  "$(echo ordinary > "$SANDBOX/helper/Fast-lane/notes.md"; "$REAL_GIT" -C "$SANDBOX/helper/Fast-lane" add notes.md
     a=$(lane_precommit "$SANDBOX/helper/Fast-lane" none COMMANDECK_WORKSPACES="$SANDBOX/helper"); b=$(lane_precommit "$SANDBOX/helper/Fast-lane" none)
     echo "$a $b")"

# D35: an absolute hooksPath makes an older linked worktree run main's guard, not its own stale copy. The old base
# holds a pre-commit that passes everything; main's tip holds the real guard. A relative path would run the stale one.
OLD="$SANDBOX/older"; rm -rf "$OLD"; mkdir -p "$OLD/main/.githooks"
(
  cd "$OLD/main" || exit 1
  "$REAL_GIT" init -q . && "$REAL_GIT" config user.email t@t.t && "$REAL_GIT" config user.name t
  printf '#!/usr/bin/env bash\nexit 0\n' > .githooks/pre-commit && chmod +x .githooks/pre-commit
  "$REAL_GIT" add -A && "$REAL_GIT" commit -qnm stale-hook
  "$REAL_GIT" worktree add -q --detach "$OLD/linked" HEAD
  cp "$ROOT/.githooks/lib-agent-guard.sh" "$ROOT/.githooks/pre-commit" .githooks/
  "$REAL_GIT" add -A && "$REAL_GIT" commit -qnm real-hook
  "$REAL_GIT" config core.hooksPath "$(pwd -P)/.githooks"
)
echo ordinary > "$OLD/linked/notes.md"; "$REAL_GIT" -C "$OLD/linked" add notes.md
check "an older linked worktree runs main's guard" 1 \
  "$(env -i PATH="$PATH" HOME="$SANDBOX/nohome" "$REAL_GIT" -C "$OLD/linked" commit -qm try >/dev/null 2>&1; echo $?)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
