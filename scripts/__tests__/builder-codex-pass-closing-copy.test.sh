#!/usr/bin/env bash
# Issue 378: the fresh closing reviewer reads a clean copy of the branch, not the worktree. A prompt line asks it not to
# open the unit's round reports, hand-offs and evidence; a detached copy of the pass commit with those files removed
# leaves nothing to open. The copy is under the scratch folder (unit_folders.py names it), is deleted when the pass ends,
# is replaced when a killed pass left one, and is never removed by force past git: a locked copy is kept and named, and a
# pass that cannot make its copy runs no reviewer. The merge takes a pass run in the copy. Its own file, not a section of
# builder-codex-pass-closing.test.sh: that file runs 84 s at load against the runner's 120 s per-file cap, which no file raises.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

printf 'echo built\n' > "$W/a.sh"
pass 1 adversarial
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 20 >/dev/null)
printf '# evidence\n' > "$B/$U-evidence.md"
# One pass's gate each: every reviewer session but the first pass's and the last pass's is aged out of the 14-day window,
# so no pass here reaches the review cap.
eval "one_$(declare -f pass)"
pass() { find "$CODEX_HOME/sessions" -name 'rollout-*.jsonl' ! -name '*-thr-1-*' ! -name "*-thr-$(($1 - 1))-*" -exec touch -t 200001010000 {} +; one_pass "$@"; }
COPY=$SC/closing-copy/$U
seen() { sed -n "${2:-1}p" "$CODEX_HOME/seen-thr-$1-1.txt" 2>/dev/null; } # <N> [line]: what reviewer 1 of pass N saw when it started
listed() { git -C "$W" worktree list --porcelain | grep -c closing-copy || true; }
raw() { # <N> <kind>: one pass whose exit code is the answer; its output is in $TMP/out and $TMP/err
  sites "$1"
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1 bash "$PASS_SH" "$U" "$1" "$2" >"$TMP/out" 2>"$TMP/err"); echo $?
}

printf 'echo two\n' > "$W/a.sh"
pass 2 final
check "fresh_closing_pass_reads_a_clean_copy: the closing reviewer's --cwd is the copy under the scratch folder, not the worktree; it is gone after the verdict, and the merge still takes the pass" \
  "$COPY gone 0 0" \
  "$(seen 2) $([ -e "$COPY" ] && echo kept || echo gone) $(listed) $(verify)"
# The launcher writes the brief untracked and the pass never commits it, so a copy of the pass commit alone has none: the
# pass puts the worktree's current brief in (r1 finding, class review-context). Pass 2 ran before anything committed it.
check "closing_copy_gets_the_untracked_brief: the brief is untracked in the worktree and the closing reviewer still finds it in the copy" "no 1" \
  "$(git -C "$W" cat-file -e "HEAD:.claude/briefs/$U.md" 2>/dev/null && echo yes || echo no) $(seen 2 3 | tr ' ' '\n' | grep -cx "$U.md")"

# The unit's review files, even committed (a Builder may add -f them), are not in the copy: only the brief is.
printf 'x\n' > "$B/$U-handoff-x.md"; printf 'x\n' > "$B/$U-after-r2.md"; printf 'x\n' > "$B/$U-fix-r2.md"
git -C "$W" add -f "$B/$U-r2-reports.md" "$B/$U-evidence.md" "$B/$U-handoff-x.md" "$B/$U-after-r2.md" "$B/$U-fix-r2.md" "$B/$U.md"
git -C "$W" commit -qm "review files, committed"
printf 'echo three\n' > "$W/a.sh"
pass 3 final
check "closing_copy_holds_no_review_artifacts: at reviewer launch the copy holds no round report, fix hand-off, hand-off, after-round hand-off or evidence file, even one committed; the brief is there" "0 1" \
  "$(seen 3 3 | tr ' ' '\n' | grep -cE -- "^$U-(r[0-9]|fix-r|handoff|after-r|evidence)") $(seen 3 3 | tr ' ' '\n' | grep -cx "$U.md")"
check "and the worktree's own review files are untouched" "1 1" \
  "$([ -s "$B/$U-evidence.md" ] && echo 1 || echo 0) $([ -s "$B/$U-r3-reports.md" ] && echo 1 || echo 0)"

# A killed pass left its copy (with a file of its own in it): the next closing pass replaces it.
git -C "$W" worktree add -q --detach "$COPY" HEAD; echo stale > "$COPY/stale.txt"
printf 'echo four\n' > "$W/a.sh"
pass 4 final
check "a stale closing copy from a killed pass is replaced: the reviewer saw a clean one, and none is left" "$COPY 0 gone 0" \
  "$(seen 4) $(seen 4 2 | tr ' ' '\n' | grep -cx stale.txt) $([ -e "$COPY" ] && echo kept || echo gone) $(listed)"

# A copy that cannot be made: a file where its folder should be. No reviewer runs, no round file is written, no copy is left.
printf 'x\n' > "$SC/closing-copy.keep"; rm -rf "$SC/closing-copy"; printf 'not a folder\n' > "$SC/closing-copy"
printf 'echo five\n' > "$W/a.sh"
R5=$(raw 5 final)
check "a closing pass whose copy cannot be made runs no reviewer, writes no round file and leaves no copy" "2 1 no no 0" \
  "$R5 $(cat "$TMP/out" "$TMP/err" | grep -c 'cannot make the closing copy') $([ -e "$CODEX_HOME/seen-thr-5-1.txt" ] && echo yes || echo no) $([ -e "$B/$U-r5-reports.md" ] && echo yes || echo no) $(listed)"
rm -f "$SC/closing-copy" "$SC/closing-copy.keep"

# A registered, locked copy holding an uncommitted tracked change: git will not remove it, so it is kept and named, no
# reviewer runs, and nothing in it is lost.
git -C "$W" worktree add -q --detach "$COPY" HEAD; git -C "$W" worktree lock "$COPY"; echo changed > "$COPY/a.sh"
printf 'echo six\n' > "$W/a.sh"
R6=$(raw 6 final)
check "closing_copy_locked_kept: a locked closing copy holding an uncommitted tracked change survives the pass with its change intact; the pass exits non-zero, runs no reviewer, and names the copy as kept" "2 1 no 1" \
  "$R6 $(cat "$TMP/out" "$TMP/err" | grep -c "closing copy .*$U kept: git refused to remove it") $([ -e "$CODEX_HOME/seen-thr-6-1.txt" ] && echo yes || echo no) $(grep -c changed "$COPY/a.sh")"
git -C "$W" worktree unlock "$COPY"; git -C "$W" worktree remove --force "$COPY"

# A Claude closing reviewer runs in the copy too, and the merge takes the pass. The stand-in leaves the session record
# Claude Code would, in the project folder named for the folder it ran in.
cat > "$TMP/cli/claude" <<'SH'
#!/bin/sh
sid=; while [ $# -gt 0 ]; do [ "$1" != --session-id ] || sid=$2; shift; done
prompt=$(cat)
# Each session runs a minute after the last, so an earlier pass ends before a later one begins.
n=$(( $(cat "$HOME/stand-in-n" 2>/dev/null || echo 0) + 1 )); echo $n > "$HOME/stand-in-n"; t=$(printf '2026-10-14T00:%02d' $n)
d=$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9' '-'); mkdir -p "$d"
jq -nc --arg p "$prompt" --arg c "$PWD" --arg s "$sid" --arg t "$t:00Z" '{type: "user", sessionId: $s, cwd: $c, timestamp: $t, message: {role: "user", content: $p}}' > "$d/$sid.jsonl"
jq -nc --arg c "$PWD" --arg s "$sid" --arg t "$t:30Z" '{type: "assistant", sessionId: $s, cwd: $c, timestamp: $t, message: {role: "assistant", content: [{type: "text", text: "Clean.\nVERDICT: GO"}]}}' >> "$d/$sid.jsonl"
echo '{}'
SH
chmod +x "$TMP/cli/claude"
printf 'echo seven\n' > "$W/a.sh"
# The pass script reads one reviewer's sessions per run, so the first pass the closing pass closes is a Claude one too.
for k in "7 adversarial" "8 final"; do
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_OPTIONS='{"codexReviewerAgent": "claude"}' COMMANDECK_PASS=claude \
    bash "$PASS_SH" "$U" $k >"$TMP/out" 2>"$TMP/err"); R7=$?
done
CF=$HOME/.claude/projects/$(printf '%s' "$COPY" | tr -c 'A-Za-z0-9' '-')
cverify() { (cd "$REPO" && PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_OPTIONS='{"codexReviewerAgent": "claude"}' COMMANDECK_PASS=claude bash "$PASS_SH" --verify "$W" "$U" "$(git -C "$W" rev-parse HEAD)" >"$TMP/vout" 2>"$TMP/verr"); echo $?; }
check "a Claude closing reviewer runs in the copy too, its session is recorded under the copy's folder, the copy is gone after, and the merge takes the pass" "0 1 1 gone 0" \
  "$R7 $(ls "$CF"/*.jsonl 2>/dev/null | wc -l | tr -d ' ') $(ls "$PROJ"/*.jsonl 2>/dev/null | grep -vc 'old-sid\|new-sid' || true) $([ -e "$COPY" ] && echo kept || echo gone) $(cverify)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
