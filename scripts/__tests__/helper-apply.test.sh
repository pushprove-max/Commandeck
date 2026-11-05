#!/usr/bin/env bash
# helper-apply.test.sh -- issue 591: a helper's worktree stayed after its diff was applied, about 70 in three days.
# helper-apply.sh applies the helper's whole delta (commits since the fork, uncommitted edits, untracked files), proves
# every byte reached the parent, then removes the worktree and branch; any delta it cannot carry keeps everything.
# The periodic sweep (worktree-sweep.sh) still removes idle old scratch worktrees and keeps busy ones.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected [$2], got [$3])"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'kill $BUSY 2>/dev/null; rm -rf "$T"' EXIT
BUSY=
P=$T/p SC=$T/scratch; mkdir -p "$SC"
g() { git -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main "$P"; printf 'one\n' > "$P/a.txt"; printf '.claude/worktrees/\nignored/\n' > "$P/.gitignore"
g -C "$P" add -A; g -C "$P" commit -q -m first
E=(env -u CLAUDE_PROJECT_DIR -u COMMANDECK_WORKSPACES COMMANDECK_MAIN="$P" COMMANDECK_SCRATCH="$SC")
ha() { (cd "$P" && "${E[@]}" bash "$REAL/scripts/helper-apply.sh" "$1" 2>&1); }
mkh() { git -C "$P" worktree add -q "${2:-$P/.claude/worktrees/$1}" -b "$1"; } # <branch> [path]
there() { [ -d "$1" ] && echo kept || echo gone; }
branch() { git -C "$P" rev-parse -q --verify "refs/heads/$1" >/dev/null && echo branch || echo nobranch; }
reset() { git -C "$P" checkout -q -- .; git -C "$P" clean -qfd -e .claude; }

H=$P/.claude/worktrees/h1; mkh h1; printf 'two\n' > "$H/a.txt"; printf 'new\n' > "$H/n.txt"
OUT=$(ha "$H")
check "applied helper worktree is removed" "applied:gone:nobranch:two:new" \
  "$(grep -c "^applied $H$" <<<"$OUT" | sed 's/1/applied/'):$(there "$H"):$(branch h1):$(cat "$P/a.txt"):$(cat "$P/n.txt" 2>/dev/null)"
reset

H=$P/.claude/worktrees/h2; mkh h2; printf 'A\n' > "$H/c.txt"; g -C "$H" add c.txt; g -C "$H" commit -q -m A; printf 'B\n' > "$H/a.txt"
OUT=$(ha "$H")
check "committed helper change is applied before removal" "A:B:gone:nobranch" "$(cat "$P/c.txt" 2>/dev/null):$(cat "$P/a.txt"):$(there "$H"):$(branch h2)"
reset

H=$P/.claude/worktrees/h3; mkh h3; printf 'staged\n' > "$H/a.txt"; g -C "$H" add a.txt; printf 'working\n' > "$H/a.txt"
OUT=$(ha "$H")
check "staged change hidden by working tree refuses removal" "1:kept:branch:one" \
  "$(grep -c '^REFUSED: a.txt has staged content that differs from its working tree; nothing removed$' <<<"$OUT"):$(there "$H"):$(branch h3):$(cat "$P/a.txt")"

H=$P/.claude/worktrees/h4; mkh h4; git -C "$H" update-index --assume-unchanged a.txt; printf 'hidden\n' > "$H/a.txt"
OUT=$(ha "$H")
check "assume-unchanged edit in helper refuses removal" "1:kept:one" \
  "$(grep -c '^REFUSED: a.txt is marked assume-unchanged or skip-worktree; nothing removed$' <<<"$OUT"):$(there "$H"):$(cat "$P/a.txt")"

H=$T/elsewhere; mkh h5 "$H"; printf 'out\n' > "$H/a.txt"
OUT=$(ha "$H")
check "path outside helper folders is refused" "1:kept:one" "$(grep -c '^REFUSED: .* is not under ' <<<"$OUT"):$(there "$H"):$(cat "$P/a.txt")"

H=$P/.claude/worktrees/h6; mkh h6; printf 'child\n' > "$H/a.txt"; printf 'new6\n' > "$H/n6.txt"; printf 'parent\n' > "$P/a.txt"
OUT=$(ha "$H")
check "diff that does not apply removes nothing" "1:kept:branch:parent:none" \
  "$(grep -c '^REFUSED: the diff of .* does not apply here; nothing removed$' <<<"$OUT"):$(there "$H"):$(branch h6):$(cat "$P/a.txt"):$(cat "$P/n6.txt" 2>/dev/null || echo none)"
reset

H=$P/.claude/worktrees/h7; mkh h7; mkdir -p "$H/ignored"; printf 'local\n' > "$H/ignored/x"; printf 'seven\n' > "$H/a.txt"
OUT=$(ha "$H")
check "ignored file only in helper refuses removal" "1:kept:one" \
  "$(grep -c '^REFUSED: ignored/x is ignored and the parent lacks it or holds other bytes (0 more); copy or delete it, then rerun; nothing removed$' <<<"$OUT"):$(there "$H"):$(cat "$P/a.txt")"

# pass 4: an untracked symlink was copied as the bytes it points at (cp -p follows it), the proof compared those bytes,
# and the helper was removed with the link lost; a dangling one was skipped by the proof. Both arrive as links.
H=$P/.claude/worktrees/h8; mkh h8; ln -s a.txt "$H/link"; ln -s missing "$H/dangle"
OUT=$(ha "$H")
check "untracked symlink is applied as a link" "applied:gone:a.txt:missing" \
  "$(grep -c "^applied $H$" <<<"$OUT" | sed 's/1/applied/'):$(there "$H"):$([ -L "$P/link" ] && readlink "$P/link"):$([ -L "$P/dangle" ] && readlink "$P/dangle")"
reset

# The sweep: a clean scratch worktree idle over 24 h goes; one a process works in stays.
old() { local gd; gd=$(git -C "$1" rev-parse --absolute-git-dir); touch -t 202001010000 "$gd/index" "$gd/logs/HEAD"; }
sweep() { (cd "$P" && "${E[@]}" bash "$REAL/scripts/worktree-sweep.sh" 2>&1); }
S1=$SC/s1; git -C "$P" worktree add -q --detach "$S1"; old "$S1"
OUT=$(sweep)
check "idle old scratch worktree is swept" "1:gone" "$(grep -c "^removed $S1$" <<<"$OUT"):$(there "$S1")"
S2=$SC/s2; git -C "$P" worktree add -q --detach "$S2"; old "$S2"
(cd "$S2" && exec sleep 60) & BUSY=$!; sleep 0.5
OUT=$(sweep); kill "$BUSY" 2>/dev/null; wait "$BUSY" 2>/dev/null
check "busy scratch worktree is kept" "1:kept" "$(grep -c "^kept $S2: a process works in it$" <<<"$OUT"):$(there "$S2")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
