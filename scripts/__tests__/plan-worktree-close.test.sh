#!/usr/bin/env bash
# plan-worktree-close.test.sh -- plan-worktree-close.sh on a real planning worktree (git worktree add, marked as
# seat.sh marks it, then the real worktree-setup.sh run on it) with an orca-ide stand-in. What this pins: the planning
# worktree and its panes close only when everything in it is identical on local main, so a plan, a rename, a staged
# or unstaged revision, an ignored file, a changed link or settings file is never lost to a close; a pane that does
# not close, or a file written while the panes close, keeps the worktree; and another unit's or an unmarked worktree
# is never touched. --adopt, the Builder launch's way into the unit's planning worktree, runs the same checks and
# closes the same panes, then drops the mark and keeps the worktree; a plain close still finds a unit planned
# before 0.18.0 in <unit>-plan.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME" "$T/bin"
P=$T/proj WS=$T/ws WT=$T/ws/u
G() { git -C "$P" -c user.name=t -c user.email=t@t "$@"; }
W() { git -C "$WT" -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$P/.claude/plans" "$P/node_modules" "$WS"
git init -q -b main "$P"
echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"
printf 'node_modules/\n.env\n.claude/briefs/\n' > "$P/.gitignore"
echo plan > "$P/.claude/plans/toy.md"; echo a > "$P/a.txt"; echo old > "$P/f"; touch "$P/node_modules/x"
G add -A && G commit -q -m base; BASE=$(G rev-parse HEAD)
# The orca-ide stand-in: one pane in the worktree while $T/pane exists; $T/close-fail, close-noop, list-fail and
# close-hook make the close exit 1, leave the pane listed, fail the list, or run a command as the pane closes;
# ids-only lists the pane with its worktree only in worktreeId and ptyId.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/orca.log"
case "\$*" in
  "terminal list"*) [ ! -e "$T/list-fail" ] || exit 1
    [ ! -e "$T/list-bad" ] || { echo '{"ok":false,"error":"service unavailable"}'; exit 0; }
    [ ! -e "$T/list-empty" ] || exit 0
    [ ! -e "$T/list-blank" ] || { echo; exit 0; }
    [ ! -e "$T/list-null" ] || { echo null; exit 0; }
    [ ! -e "$T/pane" ] || [ ! -e "$T/ids-only" ] || { echo '{"result":{"terminals":[{"handle":"h1","worktreeId":"id::$WT","ptyId":"id::$WT@@ab12"}]}}'; exit 0; }
    [ -e "$T/pane" ] && echo '{"result":{"terminals":[{"handle":"h1","worktreePath":"$WT"}]}}' || echo '{"result":{"terminals":[]}}' ;;
  "terminal close"*) [ ! -e "$T/close-fail" ] || exit 1
    [ ! -e "$T/close-hook" ] || bash "$T/close-hook"
    [ -e "$T/close-noop" ] || rm -f "$T/pane" ;;
  "worktree remove"*) p="\$*"; p=\${p#*path:}; git -C "$P" worktree remove --force "\${p%% *}" ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
run() { (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR COMMANDECK_WORKSPACES="$WS" COMMANDECK_SCRATCH="$T/scratch" PATH="$T/bin:$PATH" "$@"); }
# fresh [ref] -- a marked planning worktree of unit u on <ref> (default main), set up by the real worktree-setup.sh,
# one pane open, as seat.sh and builder-launch.sh leave it.
fresh() {
  rm -rf "$T/pane" "$T/close-fail" "$T/close-noop" "$T/list-fail" "$T/list-bad" "$T/list-empty" "$T/list-blank" "$T/list-null" "$T/close-hook" "$T/ids-only"
  git -C "$P" worktree remove --force "$WT" 2>/dev/null; rm -rf "$WT"; git -C "$P" worktree prune
  git -C "$P" worktree add -q --detach "$WT" "${1:-main}" && echo u > "$(git -C "$WT" rev-parse --absolute-git-dir)/commandeck-plan-of"
  run bash "$REAL/scripts/worktree-setup.sh" "$WT" >/dev/null 2>&1; touch "$T/pane"; : > "$T/orca.log"
}
close() { run bash "$REAL/scripts/plan-worktree-close.sh" u "$@" >"$T/out" 2>"$T/err"; RC=$?; }
calls() { grep -c "^$1" "$T/orca.log"; }
# refused <name> <path> <layer> -- exit 1, one REFUSED line naming the path and layer, the worktree and pane left alone.
refused() {
  close
  check "$1" "1:1:1:0:0" "$RC:$(grep -c "^REFUSED: .* holds $2 ($3), not identical on local main; left in place" "$T/err"):$([ -d "$WT" ] && echo 1 || echo 0):$(calls 'terminal close'):$(calls 'worktree remove')"
}

# --- closes ---
fresh; echo plan2 > "$WT/.claude/plans/p2.md"; cp "$WT/.claude/plans/p2.md" "$P/.claude/plans/p2.md"; G add -A; G commit -q -m p2
close
check "only setup's own files and an untracked plan identical to main's: the pane closes, the worktree is removed, exit 0" "0:closed u:1:1:no" \
  "$RC:$(cat "$T/out"):$(calls 'terminal close'):$(calls 'worktree remove'):$([ -d "$WT" ] && echo yes || echo no)"
rm -f "$P/.claude/plans/p2.md"; G add -A; G commit -q -m drop-p2

# --- refused: each layer of what main lacks or has differently ---
fresh; echo x > "$WT/.claude/plans/nomain.md"
refused "an untracked file main lacks" .claude/plans/nomain.md untracked
fresh; echo x > "$WT/.claude/plans/c.md"; W add -A; W commit -q -m c
refused "a committed file main lacks" .claude/plans/c.md commits
fresh; echo edit >> "$WT/.claude/plans/toy.md"
refused "a plan edited after its commit" .claude/plans/toy.md "working tree"
fresh; echo edit >> "$WT/a.txt"; W add a.txt; W show HEAD:a.txt > "$WT/a.txt"
refused "a staged revision with its working copy restored to HEAD" a.txt index
fresh; chmod +x "$WT/a.txt"
refused "chmod +x on a tracked file (same id, other mode)" a.txt "working tree"
fresh; ln -sfn "$T" "$WT/node_modules"
refused "node_modules linked somewhere else" node_modules untracked
fresh; mv "$P/node_modules" "$P/nm2"
refused "node_modules dangling, its readlink unchanged" node_modules untracked
mv "$P/nm2" "$P/node_modules"
fresh; jq '.env.LOCAL_NOTE = "x"' "$WT/.claude/settings.local.json" > "$T/s.json" && cp "$T/s.json" "$WT/.claude/settings.local.json"
refused "settings plus a custom key" .claude/settings.local.json ignored
fresh; echo k > "$WT/.env"
refused "an ignored .env" .env ignored
fresh; mkdir -p "$WT/.claude/briefs"; echo d > "$WT/.claude/briefs/draft.md"
refused "an ignored brief draft" .claude/briefs/ ignored

# --- refused: renames list the deleted path too, and a revision can hide in the index or the working tree ---
echo a > "$P/b.txt"; G add -A; G commit -q -m copy-b
fresh "$BASE"; W mv a.txt b.txt; W commit -q -m rename
refused "a committed rename a.txt -> b.txt where main kept a.txt and copied it to b.txt" a.txt commits
fresh "$BASE"; W mv a.txt b.txt
refused "a staged rename a.txt -> b.txt, same" a.txt index
# B has f=old; HEAD and main have f=new (each its own commit).
echo new > "$P/f"; G commit -q -am f-new
fresh "$BASE"; echo new > "$WT/f"; W commit -q -am f-new
echo old > "$WT/f"; W add f; echo new > "$WT/f"
refused "f staged back to the merge-base's content, working copy at HEAD's" f index
fresh "$BASE"; echo new > "$WT/f"; W commit -q -am f-new; echo old > "$WT/f"
refused "f unstaged back to the merge-base's content, index at HEAD" f "working tree"

# --- refused: what git's own diff cannot see (index flags, conflicts), a routed index, a terminal list that is not a list ---
fresh; W update-index --assume-unchanged a.txt; echo unsaved > "$WT/a.txt"
refused "a tracked edit hidden by assume-unchanged" a.txt "index flags"
fresh; W update-index --skip-worktree a.txt; echo unsaved > "$WT/a.txt"
refused "a tracked edit hidden by skip-worktree" a.txt "index flags"
fresh; b=$(W rev-parse main:a.txt); o=$(echo unique | W hash-object -w --stdin)
printf '0 %s\ta.txt\n100644 %s 1\ta.txt\n100644 %s 2\ta.txt\n' "$(printf 0%.0s {1..40})" "$b" "$o" | W update-index --index-info
refused "an unmerged entry whose stage 1 and working file match main" a.txt "index flags"
fresh; echo unique > "$WT/a.txt"; W add a.txt; W show HEAD:a.txt > "$WT/a.txt"
GIT_INDEX_FILE=$P/.git/index refused "a staged revision hidden by GIT_INDEX_FILE routed at main's index" a.txt index
fresh; touch "$T/list-bad"; close
check "a terminal list that is an error envelope, not a list: kept, no close, no removal" "1:1:0:0" "$RC:$(grep -c '^kept: .*: terminal list failed$' "$T/err"):$(calls 'terminal close'):$(calls 'worktree remove')"
for m in empty blank null; do
  fresh; touch "$T/list-$m"; close
  check "a terminal list that is $m (exit 0): kept, no close, no removal" "1:1:0:0" "$RC:$(grep -c '^kept: .*: terminal list failed$' "$T/err"):$(calls 'terminal close'):$(calls 'worktree remove')"
done

# --- the order: a pane that does not close, a file written as the panes close, a failed list ---
fresh; printf 'echo late > "%s/.claude/plans/late.md"\n' "$WT" > "$T/close-hook"
close
check "a file written while the pane closes: refused at the second check, kept, not removed" "1:1:1:1:0" \
  "$RC:$(grep -c '^REFUSED: .* holds .claude/plans/late.md (untracked), not identical on local main; .* (written while panes closed)$' "$T/err"):$([ -f "$WT/.claude/plans/late.md" ] && echo 1 || echo 0):$(calls 'terminal close'):$(calls 'worktree remove')"
fresh; touch "$T/close-fail"; close
check "a terminal close exiting 1: one kept line naming the pane, no removal" "1:1:0" "$RC:$(grep -c '^kept: .*: pane h1 did not close$' "$T/err"):$(calls 'worktree remove')"
fresh; touch "$T/close-noop"; close
check "a pane still listed after the close: one kept line naming the pane, no removal" "1:1:0" "$RC:$(grep -c '^kept: .*: pane h1 did not close$' "$T/err"):$(calls 'worktree remove')"
fresh; touch "$T/list-fail"; close
check "a failed terminal list: kept, no close, no removal" "1:1:0:0" "$RC:$(grep -c '^kept: .*: terminal list failed$' "$T/err"):$(calls 'terminal close'):$(calls 'worktree remove')"

# --- not this unit's, and --dry-run ---
fresh; rm "$(git -C "$WT" rev-parse --absolute-git-dir)/commandeck-plan-of"; echo x > "$WT/stray"; close
check "an unmarked worktree named u (a Builder unit's): left, exit 0, nothing closed" "0:1:0:0" \
  "$RC:$(grep -c "^left .*: not u's planning worktree" "$T/out"):$(calls 'terminal close'):$(calls 'worktree remove')"
echo other > "$(git -C "$WT" rev-parse --absolute-git-dir)/commandeck-plan-of"; close
check "another unit's mark: left, exit 0, nothing closed" "0:1:0:0" \
  "$RC:$(grep -c "^left .*: not u's planning worktree" "$T/out"):$(calls 'terminal close'):$(calls 'worktree remove')"
fresh; close --dry-run
check "--dry-run on a clean worktree: says what it would close, closes nothing" "0:would close 1 panes and remove $WT:0:0" \
  "$RC:$(cat "$T/out"):$(calls 'terminal close'):$(calls 'worktree remove')"
# Issue 162: the plan author's pane listed with no worktreePath was missed and left orphaned.
fresh; touch "$T/ids-only"; close --dry-run
check "--dry-run counts a pane listed with only worktreeId and ptyId" "0:would close 1 panes and remove $WT" "$RC:$(cat "$T/out")"
close
check "and the real run closes it and removes the worktree" "0:1:no" "$RC:$(grep -c '^terminal close --terminal h1' "$T/orca.log"):$([ -d "$WT" ] && echo yes || echo no)"
fresh
echo x > "$WT/stray"; close --dry-run
check "--dry-run on a dirty worktree: refused like the real run" "1:1" "$RC:$(grep -c '^REFUSED: .* holds stray (untracked)' "$T/err")"

# --- --adopt: the Builder takes the planning worktree over, so nothing in it may be lost to the reset to main ---
mark() { cat "$(git -C "$WT" rev-parse --absolute-git-dir)/commandeck-plan-of" 2>/dev/null; }
fresh; close --adopt --dry-run
check "--adopt --dry-run says what it would do, closes nothing, keeps the mark" "0:would close 1 panes and adopt $WT:0:u" \
  "$RC:$(cat "$T/out"):$(calls 'terminal close'):$(mark)"
close --adopt
check "--adopt on a clean marked worktree: its pane closes, the mark goes, the worktree stays, exit 0" "0:adopted $WT:1:0:yes:" \
  "$RC:$(cat "$T/out"):$(calls 'terminal close'):$(calls 'worktree remove'):$([ -d "$WT" ] && echo yes || echo no):$(mark)"
fresh; echo x > "$WT/stray"; close --adopt
check "--adopt on a dirty one keeps all of it, exit 1, one kept line naming the file" "1:1:0:u" \
  "$RC:$(grep -c '^kept: .* holds stray (untracked), not identical on local main' "$T/err"):$(calls 'terminal close'):$(mark)"
fresh; rm "$(git -C "$WT" rev-parse --absolute-git-dir)/commandeck-plan-of"; close --adopt
check "--adopt on an unmarked worktree (a Builder unit's): kept, exit 1, saying why, nothing closed" "1:1:0" \
  "$RC:$(grep -c "^kept: .*: not u's planning worktree" "$T/err"):$(calls 'terminal close')"
rm -rf "$WT"; git -C "$P" worktree prune; close
check "no planning worktree: silent, exit 0" "0::" "$RC:$(cat "$T/out"):$(cat "$T/err")"

# --- a unit planned before 0.18.0, in <unit>-plan, still closes; an unmarked <unit> beside it is a Builder's ---
fresh; rm -f "$T/pane" "$(git -C "$WT" rev-parse --absolute-git-dir)/commandeck-plan-of"; OLD=$T/ws/u-plan
git -C "$P" worktree add -q --detach "$OLD" main && echo u > "$(git -C "$OLD" rev-parse --absolute-git-dir)/commandeck-plan-of"
close
check "a plain close finds the old layout's u-plan and leaves the unmarked u" "0:closed u-plan:no:yes" \
  "$RC:$(cat "$T/out"):$([ -d "$OLD" ] && echo yes || echo no):$([ -d "$WT" ] && echo yes || echo no)"

# --- worktree-setup.sh --print-settings writes nothing in the worktree ---
rm -rf "$WT"; git -C "$P" worktree prune; git -C "$P" worktree add -q --detach "$WT" main
snap() { find "$WT" -not -path "$WT/.git" -exec ls -ld {} + 2>&1; cat "$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir)/info/exclude" 2>&1; }
S1=$(snap); run bash "$REAL/scripts/worktree-setup.sh" "$WT" --print-settings > "$T/printed" 2>/dev/null; S2=$(snap)
check "--print-settings leaves the worktree and info/exclude byte-identical, and prints the settings it would write" "1:1" \
  "$([ "$S1" = "$S2" ] && echo 1 || echo 0):$(jq -e '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW' "$T/printed" >/dev/null 2>&1 && echo 1 || echo 0)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
