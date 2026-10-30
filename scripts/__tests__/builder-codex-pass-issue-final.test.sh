#!/usr/bin/env bash
# builder-codex-pass-issue-final.test.sh -- issue 486: a two-issue unit walked to its merge. The final cycle and the merge wait
# for every issue; the issues' round files and reviewer sessions are never the final record. One walk, so it is the last file.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

GO=$'Fine.\nVERDICT: GO'
ipass() { # <issue> <reply>: one --issue pass of the unit; prints its exit code; output in $TMP/out and $TMP/err
  local n; n=$(($(cat "$TMP/seq" 2>/dev/null || echo 0) + 1)); echo "$n" > "$TMP/seq"
  (cd "$W" && env TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-s$n "STUB_REPLY=$2" \
    bash "$PASS_SH" --issue "$1" "$U" >"$TMP/out" 2>"$TMP/err"); echo $?
}
raw() { # <N> <kind>: one plain pass whose exit code is the answer; its output is in $TMP/out and $TMP/err
  sites "$1"
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1 bash "$PASS_SH" "$U" "$1" "$2" >"$TMP/out" 2>"$TMP/err"); echo $?
}
fix() { printf 'echo %s\n' "$1" > "$W/$1.sh"; } # <name>: a change for the next review to read
seen() { sed -n "${2:-1}p" "$CODEX_HOME/seen-thr-$1-1.txt" 2>/dev/null; } # <N> [line]: what reviewer 1 of pass N saw when it started
(cd "$REPO" && bash "$REAL/scripts/review-cap.sh" "$U" 20 >/dev/null)

# Main chose per-issue for issues 1 and 2 before the build: the issues are reviewed first, the usual passes after.
printf 'Fix #1 and #2.\nReview workflow: per-issue #1 #2\nbash x/builder-codex-pass.sh %s 1 adversarial\n' "$U" > "$MAINBRIEF"

# Catches a closing review that starts while an issue is open: the final cycle must wait for every issue.
fix i1a; RA=$(ipass 1 "$GO"); fix i1b; RB=$(ipass 1 "$GO")
fix i2; RC=$(raw 1 final)
check "final_waits_for_every_issue: with issue 1 done and issue 2 not started, the closing pass is refused naming issue 2 only" "0 0 2:1:0" \
  "$RA $RB $RC:$(grep -c 'issue #2 is not done' "$TMP/err"):$(grep -c 'issue #1 is not done' "$TMP/err")"
fix i2a; ipass 2 "$GO" >/dev/null; fix i2b; ipass 2 "$GO" >/dev/null
fix base; pass 1 adversarial

# Catches an issue's own session passing for the merge's proof: the Builder could name it in the round file's header.
THREAD=$(sed -n 's/^Codex thread: //p' "$B"/$U-issue-2-round-2.md)
cp "$B/$U-r1-reports.md" "$TMP/r1.bak"; sed -i.orig "s/^Codex thread: .*/Codex thread: $THREAD/" "$B/$U-r1-reports.md"
check "merge_refuses_issue_thread: a round file naming a per-issue session is no proof for the merge" "2" "$(verify)"
cp "$TMP/r1.bak" "$B/$U-r1-reports.md"; rm -f "$B/$U-r1-reports.md.orig"

# Catches the final cycle never opening once every issue is done, or the issue sessions spoiling the final record.
fix whole; D=$(raw 2 final)
check "final_runs_after_issues: with every issue done the closing pass runs and the merge takes it" "0 0" "$D $(verify)"

# Catches a merge of a unit whose issue never had its own review: the whole-branch GO alone would carry it.
printf 'Fix #1 and #2.\nReview workflow: per-issue #1 #2 #3\n' > "$MAINBRIEF"
check "merge_refuses_unfinished_issue (the merge of a per-issue unit with an issue not done is refused, naming it)" "2:1" \
  "$(verify):$(grep -c 'issue #3 is not done' "$TMP/verr")"
printf 'Fix #1 and #2.\nReview workflow: per-issue #1 #2\n' > "$MAINBRIEF"

# Catches the issue round files reaching the closing reviewer's clean copy, even committed.
git -C "$W" add -f "$B"/$U-issue-*-round-*.md; git -C "$W" commit -qm "issue round files, committed"
fix again; raw 3 final >/dev/null
check "closing_copy_drops_rounds: at reviewer launch the closing copy holds no per-issue round file" "0" \
  "$(seen 3 3 | tr ' ' '\n' | grep -c -- "^$U-issue-")"

# Catches the merge's clean-up leaving per-issue round files behind (or taking another unit's).
touch "$B/${U}x-issue-1-round-1.md"
check "cleanup_takes_rounds: the files the merge archives and removes include the unit's per-issue round files and not a neighbour unit's" "4 0" \
  "$(. "$REAL/scripts/paths.sh" && pp_unit_briefs "$B" "$U" | grep -c -- "-issue-[12]-round-") $(. "$REAL/scripts/paths.sh" && pp_unit_briefs "$B" "$U" | grep -c -- "${U}x-")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
