#!/usr/bin/env bash
# Self-test for .githooks/commit-msg: it strips AI attribution trailers, and refuses a
# message that names a home path or a .local host.
#
# Every case runs in a THROWAWAY repo under mktemp: staging a fixture in the
# real index would collide with work in progress.
set -u

ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/.githooks/commit-msg"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected '$2', got '$3')"; fi }

SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX"' EXIT

# $1 = file to stage (empty for none), $2 = commit message. Prints the exit code.
run_msg() {
  (
    cd "$SANDBOX" || exit 1
    rm -rf .git msg.txt ./*.ts src && git init -q . && git config user.email t@t.t && git config user.name t
    if [ -n "$1" ]; then
      mkdir -p "$(dirname "$1")" && printf 'x\n' > "$1" && git add -f "$1"
    fi
    printf '%s\n' "$2" > msg.txt
    bash "$HOOK" msg.txt
  ) >/dev/null 2>&1
  echo $?
}
msg_after() { cat "$SANDBOX/msg.txt"; }

# --- the privacy refusal ---------------------------------------------------------
# A home path or a .local hostname in a message is refused at commit time, not
# found by the push-time grep after the commit exists.
# Built from pieces so this file carries no machine literal.
H=home U=Users
# Catches a hook that lets a home path into history.
check "a home-path message is refused (/Users path)" 1 "$(run_msg '' "see /$U/alice/repos/x")"
check "a .local host is refused"            1 "$(run_msg '' 'ssh build-box.local')"
check "a .local host at a sentence end"     1 "$(run_msg '' 'host build-box.local.')"
check "a /home path in parentheses"         1 "$(run_msg '' "in (/$H/alice/repo)")"
check "a user@host.local peer address"      1 "$(run_msg '' 'peer u@peerhost.local')"
# Catches a pattern so wide that ordinary messages are refused.
check "the Builder pass title passes"       0 "$(run_msg '' 'feat(tooling-guards-2026-10-20): Builder pass r1')"
check "a bare 'update' word passes"         0 "$(run_msg '' 'feat: update guard')"
check "a repo path ending pages/home passes" 0 "$(run_msg '' "changed web/src/pages/$H/index.tsx and observed red")"
check "a bare repo home path passes"        0 "$(run_msg '' "web/src/pages/$H/index.tsx")"
check "local-ish names and ~ paths pass"    0 "$(run_msg '' 'settings.local.json ~/.config/devenv/peer /tmp/proj/x localhost .env.local')"
check "a ledger title passes"               0 "$(run_msg '' 'chore(metrics): ledger rows for tooling-guards-2026-10-20')"
check "a squash title with Closes passes"   0 "$(run_msg '' 'feat(tooling): b6

Closes: #1 #2')"
# Catches a hook that refuses or errors on a message git itself would reject (the empty-message abort is git's).
check "an empty message is left to git"     0 "$(run_msg '' '')"
check "a comment-only message is left to git" 0 "$(run_msg '' '# nothing here')"

# Real commits, so the scan is judged against what git keeps, not a guess at its
# cleanup: `-m` and `-F` keep # lines and a typed scissors tail. $1 = editor
# (empty for none), the rest = git commit args. Prints the exit code.
run_git() {
  (
    cd "$SANDBOX" || exit 1
    rm -rf .git .h msg.txt ./*.ts src notes.txt && git init -q . && git config user.email t@t.t && git config user.name t
    mkdir .h && printf '#!/bin/sh\nexec bash "%s" "$1"\n' "$HOOK" > .h/commit-msg && chmod +x .h/commit-msg
    git config core.hooksPath .h
    printf 'see /%s/alice/repo\n' "$U" > notes.txt && git add notes.txt
    GIT_EDITOR=${1:-true} git commit -q "${@:2}"
  ) >/dev/null 2>&1
  echo $?
}
CUT='# ------------------------ >8 ------------------------'
# Catches a scan that skips # lines or text below a scissors line, which git then keeps.
check "a # line git -m keeps is refused"     1 "$(run_git '' -m "fix: document failure
# /$U/alice/repo")"
check "text below a typed scissors line is refused" 1 "$(run_git '' -m "fix: document failure
$CUT
/$U/alice/repo")"
# The hook is never told git's cleanup mode, so it cannot know which text git
# drops: the full cut block typed under --cleanup=whitespace stays in the log,
# and a `-v` diff below git's own block is refused with it (the accepted cost;
# the way round is committing without -v).
check "a typed full cut block with a path below it is refused" 1 "$(run_git '' --cleanup=whitespace -m "fix: document failure
$CUT
# Do not modify or remove the line above.
# Everything below it will be ignored.
/$U/alice/repo")"
check "a -v diff naming a home path below git's cut block is refused" 1 \
  "$(run_git 'f() { printf "fix: verbose\n" | cat - "$1" > "$1.n" && mv "$1.n" "$1"; }; f' -v)"
check "a clean -m commit passes"             0 "$(run_git '' -m 'fix: ordinary')"

# --- the attribution trailers ------------------------------------------------
# Catches a hook that lets a Claude co-author or session trailer reach GitHub, or one that eats the message or a human co-author.
run_msg '' 'feat: a thing

Co-Authored-By: Claude <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_x' >/dev/null
check "Claude trailers are stripped (Co-Authored-By: Claude)" "" "$(msg_after | grep 'Co-Authored-By' || true)"
check "Claude trailers are stripped (Claude-Session)"        "" "$(msg_after | grep 'Claude-Session' || true)"
check "the real message survives"          "feat: a thing" "$(msg_after | head -1)"

run_msg '' 'fix: keep this

Co-Authored-By: Jane Doe <jane@example.com>' >/dev/null
check "a human co-author is kept"          0 "$(msg_after | grep -q 'Jane Doe' && echo 0 || echo 1)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
