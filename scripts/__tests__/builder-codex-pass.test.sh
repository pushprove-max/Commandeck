#!/usr/bin/env bash
# builder-codex-pass.sh is all a Builder and its reviewer hear of a round: what
# the pass prints and what its prompt carries. What this pins: the model id a
# family resolves to stays one id when a warning goes to stderr; a pass prints
# the files and lines the round changed and flags a round that changed no code;
# a narrowed pass after main changed the brief reads the whole branch, so the
# new part is reviewed with the old before the closing pass; and the evidence
# file's "Different fix r<N>:" and "Other cases checked r<N>:" lines reach the
# reviewer of round N, and of no other round.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

# A Python with no tomllib (3.10): the proxy check warns on stderr and the cache answers.
printf '#!/usr/bin/env bash\n[ "$*" != "-c import tomllib" ] || exit 1\nexec %q "$@"\n' "$(command -v python3)" > "$TMP/py/python3"; chmod +x "$TMP/py/python3"
OUT=$(PATH=$TMP/py:$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --preflight 2>"$TMP/err")
check "a family resolved from the cache beside a stderr warning is the bare model id" "gpt-6.1-sol" "$(cut -f1 <<<"$OUT")"
check "the warning still goes to stderr" 1 "$(grep -c 'tomllib' "$TMP/err")"

printf 'echo built\n' > "$W/a.sh"
# Pass 8: one pass script runs both reviewers, so a refusal on the Claude reviewer names it, never builder-claude-pass.sh,
# and no command in a script is built from the reviewer's agent.
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_OPTIONS='{"codexReviewerAgent": "claude"}' COMMANDECK_PASS=claude bash "$PASS_SH" "$U" 1 review >"$TMP/out" 2>"$TMP/err")
check "a review pass with no earlier one, on the Claude reviewer, says to start with builder-codex-pass.sh" "1:0" \
  "$(grep -c "Start with: builder-codex-pass.sh $U 1 adversarial" "$TMP/err"):$(grep -c 'builder-claude-pass' "$TMP/err")"
check "no script builds a pass script's name from the reviewer's agent" 0 \
  "$(cat "$REAL"/scripts/*.sh | grep -cE 'builder-\$[^ ]*-pass\.sh')"
# A brief launched --risky has a "## Risky launch" section, so a small build gets three.
printf '## Risky launch\n' >> "$MAINBRIEF"
pass 1 adversarial
check "a first pass has no earlier pass to count a round from" 0 "$(grep -c '^Changed since' "$TMP/out")"
check "a launch brief with ## Risky launch is a risky launch: three reviewers on a small build" 1 \
  "$(grep -c '^Reviewers: 3 (.*, a risky launch;' "$B/$U-r1-reports.md")"
# Issue 292: the dashboard's "launched as" line reads the model and effort the pass really ran from this row.
check "the pass's codex-start row carries the reviewer's resolved model and effort" "gpt-6.1-sol $(jq -r '.roles["codex-reviewer"].effort' "$TMP/routing.json")" \
  "$(jq -rs 'map(select(.event == "codex-start" and .pass == "adversarial")) | last | "\(.model) \(.effort)"' "$W/.claude/builder-events.jsonl")"
# Every reviewer gets the full checklist (global rules, "Working and review"): an angle left to one reviewer
# goes unchecked when that reviewer misses it.
check "each of the three reviewers' prompts carries all three angles" "1 1 1 1 1 1 1 1 1" \
  "$(for p in 1 2 3; do for a in 1 2 3; do grep -c "Angle $a of 3, " "$B/$U-r1-prompt-$p.md"; done; done | paste -sd' ' -)"

# A round of one comment line: the pass names the file and its count, and says no code changed.
printf '# fixed: the finding\n' >> "$W/a.sh"
pass 2 review
check "a pass prints the files and line counts the round changed" 1 "$(grep -cx '  a.sh +1 -0' "$TMP/out")"
check "a round of comments only is flagged" 1 "$(grep -c '^No code changed in this round' "$TMP/out")"
check "the round file is a narrowed pass" 1 "$(grep -cx 'Pass: review' "$B/$U-r2-reports.md")"
# Issue 352: this narrowed GO, with the closing pass on, merges nothing: the pass names the final command, so no done marker follows it.
check "a narrowed GO with the closing pass on prints NARROWED GO and the final command" 1 \
  "$(grep -cF "NARROWED GO: this GO merges nothing. Next: builder-codex-pass.sh $U 3 final; print your DONE line only after that pass's GO." "$TMP/out")"

# Main adds scope to the brief during the fix round; the Builder's evidence says why it took
# another fix than the named one and which other cases it checked, for round 3 only.
printf 'Fix #2, added in the fix round.\n' >> "$MAINBRIEF"
printf 'echo two\n' > "$W/a.sh"
printf 'Different fix r2: an older note.\nDifferent fix r3: the named fix broke the caller in b.sh.\nOther cases checked r3: a.sh and c.sh read the same input.\n' > "$B/$U-evidence.md"
# A finding only main can fix goes under Main-only (deferred): every later pass is told it is known.
printf '\n## Main-only (deferred)\nthe settings.json entry for the new hook: main edits that file.\n\n## Later heading\nnot deferred.\n' >> "$B/$U-evidence.md"
# It leaves a P2 only: after a whole-branch GO a commit makes the next review a closing pass too (issue 266).
STUB_REPLY=$'- [P2] (class: wording) R3-PROBE -- a.sh:1 -- a word -- bash a.sh\nVERDICT: NO-GO' pass 3 review
check "a code round is not flagged" 0 "$(grep -c '^No code changed' "$TMP/out")"
check "after the brief gained scope, the review pass runs as a whole-branch pass and says why" "1 1" \
  "$(grep -cx 'Pass: final' "$B/$U-r3-reports.md") $(grep -c 'changed since the last pass' "$TMP/out")"
check "its prompt is the whole branch against main" "1 1" \
  "$(input 3 | grep -c '^Review input: the closing pass, the whole branch diff') $(input 3 | grep -c '^-echo base$')"
# Issue 366: a closing pass is fresh, so it gets no author's notes; a narrowed pass gets this round's alone
# (builder-codex-pass-threshold.test.sh, case 3).
check "the closing prompt carries no different-fix or other-cases line, of this round or another" "0 0 0" \
  "$(input 3 | grep -cx 'Different fix r3: the named fix broke the caller in b.sh.') $(input 3 | grep -cx 'Other cases checked r3: a.sh and c.sh read the same input.') $(input 3 | grep -c 'r2: an older note')"

# The brief unchanged since, but r3 was a closing pass that ended NO-GO: every finding blocks the merge, so the next
# review pass is the closing pass again.
printf 'echo three\n' > "$W/a.sh"
# The pass lock sits in the worktree's git folder, which pp_rm_rf refuses: released through it, it stayed, and every
# later pass of the worktree was refused. A live holder still refuses a pass; a dead one's lock is taken over.
L=$(git -C "$W" rev-parse --absolute-git-dir)/builder-pass.lock
mkdir "$L"; echo $$ > "$L/pid"
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-4 bash "$PASS_SH" "$U" 4 review >/dev/null 2>"$TMP/err")
check "a pass while another holds the lock is refused, and the holder's lock stays" "1 1" \
  "$(grep -c "another pass of $U is still running (pid $$)" "$TMP/err") $(ls "$L/pid" | wc -l | tr -d ' ')"
echo "$(sh -c 'echo $$')" > "$L/pid"
pass 4 review
check "a dead holder's lock is taken over, and the pass releases it" "1 0" \
  "$(grep -cx 'Pass: final' "$B/$U-r4-reports.md") $(ls -d "$L" 2>/dev/null | wc -l | tr -d ' ')"
# Issue 369: the lock's own functions, run on a hand-made lock. Two passes that start together on a dead holder's lock
# must not both take it over, and a pass that ends must not remove a lock another pass took.
LOCKFNS=$(sed -n '/^guarded()/p;/^take_lock()/,/^}/p;/^release_lock()/,/^}/p;/^unlock()/p' "$PASS_SH")
LK=$TMP/lockcase; mkdir -p "$LK"
as_pass() { LOCK=$LK/builder-pass.lock bash -c "$LOCKFNS"'; '"$1"; }
mkdir "$LK/builder-pass.lock"; echo 99999999 > "$LK/builder-pass.lock/pid"
# The winner stays alive after it takes the lock (as a running pass does), so the loser finds a live holder.
for i in 1 2; do OUTF=$LK/$i.out as_pass 'guarded take_lock >"$OUTF" 2>&1; rc=$?; echo "rc=$rc" >>"$OUTF"; [ $rc != 0 ] || sleep 2' & done
wait
check "two passes started together on a dead holder's lock: one runs and the other is refused" "1 1" \
  "$(cat "$LK"/*.out 2>/dev/null | grep -c '^rc=0$') $(cat "$LK"/*.out 2>/dev/null | grep -c '^rc=1$')"
rm -rf "$LK"; mkdir -p "$LK"; mkdir "$LK/builder-pass.lock"
sleep 30 & OTHER=$!
echo "$OTHER" > "$LK/builder-pass.lock/pid"
as_pass 'guarded release_lock'
check "the first pass's exit leaves the second's lock in place" "$OTHER" "$(cat "$LK/builder-pass.lock/pid" 2>/dev/null)"
kill "$OTHER" 2>/dev/null; wait "$OTHER" 2>/dev/null
as_pass 'guarded take_lock; guarded release_lock'
check "and a pass releases the lock it took" 0 "$(ls -d "$LK/builder-pass.lock" 2>/dev/null | wc -l | tr -d ' ')"
# Issue 366: passes 3 and 4 are closing passes, a fresh reviewer handed no review history, so no main-only list
# (builder-codex-pass-threshold.test.sh covers the list reaching a narrowed pass).
check "a closing pass is not handed the evidence file's main-only list" "0 0 0 0" \
  "$(input 3 | grep -c '^Known and deferred to main') $(input 3 | grep -cx 'the settings.json entry for the new hook: main edits that file.') $(input 4 | grep -cx 'the settings.json entry for the new hook: main edits that file.') $(input 4 | grep -c 'not deferred')"
check "after a P2-only closing NO-GO, a review pass runs as the closing pass over the whole branch" "1 1" \
  "$(grep -cx 'Pass: final' "$B/$U-r4-reports.md") $(input 4 | grep -c '^-echo base$')"
check "a pass with no notes for its round carries none" 0 "$(input 4 | grep -cE '^(Different fix|Other cases checked) ')"

# The record of what the brief held is gone after an earlier pass: the pass cannot tell, so it reads the whole branch.
printf 'Fix #3, added in the fix round.\n' >> "$MAINBRIEF"
rm -f "$(git -C "$W" rev-parse --absolute-git-dir)/builder-pass-scope"
printf 'echo four\n' > "$W/a.sh"
# `codex login status` still says signed in after a revoked sign-in, and the pass then ended
# with no output: a one-word request is the check. Run in the worktree it fires the repo's hooks.
echo 3 > "$TMP/probe-fail"; : > "$TMP/probe"; HEAD5=$(git -C "$W" rev-parse HEAD)
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_PROBE_BACKOFF=0 STUB_THREAD=thr-5 \
  bash "$PASS_SH" "$U" 5 review >"$TMP/out" 2>"$TMP/err"); RC=$?
check "a Codex that fails three one-word requests refuses the pass: no commit, no round file" "1 3 1 no" \
  "$([ "$RC" != 0 ] && echo 1) $(grep -c 'Codex sign-in probe: try' "$TMP/err") $(grep -c 'launch refused: Codex is not signed in' "$TMP/err") \
$([ "$(git -C "$W" rev-parse HEAD)" = "$HEAD5" ] && [ ! -e "$B/$U-r5-reports.md" ] && echo no || echo yes)"
echo 1 > "$TMP/probe-fail"; : > "$TMP/probe"
COMMANDECK_PROBE_BACKOFF=0 pass 5 review
check "one failed try then an answer runs the pass, every try outside the worktree" "2 0" \
  "$(wc -l < "$TMP/probe" | tr -d ' ') $(grep -c "^$W" "$TMP/probe")"
check "with the scope record deleted, a review pass reads the whole branch" 1 "$(grep -cx 'Pass: final' "$B/$U-r5-reports.md")"
# every reviewer is told a new required setting with no deployed-format test blocks the merge. Round 1 is risky (above),
# so its behaviour reviewer is prompt 2 of three.
check "the first and later passes' prompts carry the deployed-format rule" "1 1" \
  "$(grep -c 'format already deployed' "$B/$U-r1-prompt-2.md") $(grep -c 'format already deployed' "$B/$U-r4-prompt-1.md")"
# A diff that changes a function or a data shape can break callers it never shows, and code right today can
# grow in cost later: both are asked of the behaviour reviewer in every pass.
check "the first and later passes' prompts ask about untouched callers and cost over time" "1 1 1 1" \
  "$(grep -c 'callers and readers the diff did not touch' "$B/$U-r1-prompt-2.md") $(grep -c 'Cost over time' "$B/$U-r1-prompt-2.md") $(grep -c 'callers and readers the diff did not touch' "$B/$U-r4-prompt-1.md") $(grep -c 'Cost over time' "$B/$U-r4-prompt-1.md")"
# A reviewer that stops at the first failing ordering of a race returns the next one every round: the first pass lists them all.
check "the full pass and the behaviour angle prompts both carry the every-ordering sentence" "1 1" \
  "$(grep -c 'list EVERY ordering of those events in this first pass, check each, and report every ordering that fails, not the first' "$B/$U-r1-prompt-2.md") $(grep -c 'list EVERY ordering of those events in this first pass, check each, and report every ordering that fails, not the first' "$B/$U-r4-prompt-1.md")"
# Issue 341 (F1): the first pass checks the brief's Data design section before anything else, in every reviewer's prompt; a
# later, narrowed pass is not handed the sentence again.
check "the first pass's prompts lead with the Data design check, and a later pass's do not" "1 1 0" \
  "$(grep -c 'Before anything else, check the Data design section of the unit brief' "$B/$U-r1-prompt-2.md") $(grep -c 'Report as P1 (class: data-design)' "$B/$U-r1-prompt-1.md") $(grep -c 'Data design section of the unit brief' "$B/$U-r4-prompt-1.md")"
# Every pass asks whether the change hand-builds what the project's paved-road registry or a standard covers,
# and has such a finding cite the registry row.
# Issue 282: an exception entry with no proof in its test and no ruling id is P1, asked of the first pass and of later ones.
check "the first and later passes' prompts report an unproven exception entry as P1" "1 1" \
  "$(grep -c 'An exception, allowlist or exemption entry in a guard or its test stands only when the same test proves the alternative it claims, or the entry cites an owner ruling id. A comment is not proof. Report an entry that has neither as P1.' "$B/$U-r1-prompt-1.md") $(grep -c 'Report an entry that has neither as P1' "$B/$U-r4-prompt-1.md")"
check "the first and later passes' prompts ask the paved-road question, citing the registry row" "1 1 1 1" \
  "$(grep -c 'hand-build something .claude/paved-road.md or a published standard already covers' "$B/$U-r1-prompt-1.md") $(grep -c 'cites the registry row' "$B/$U-r1-prompt-1.md") $(grep -c 'hand-build something .claude/paved-road.md' "$B/$U-r4-prompt-1.md") $(grep -c 'cites the registry row' "$B/$U-r4-prompt-1.md")"


# Issue 291: a companion installed only in the selected Claude profile is the one a pass runs, not one under HOME.
mkdir -p "$TMP/profile/plugins/cache/openai-codex/codex" "$TMP/nohome"; cp -R "$PLUG" "$TMP/profile/plugins/cache/openai-codex/codex/"
check "issue 291: the Codex companion is found under CLAUDE_CONFIG_DIR alone" 0 \
  "$(cd "$REPO" && HOME=$TMP/nohome CLAUDE_CONFIG_DIR=$TMP/profile COMMANDECK_MAIN=$REPO bash "$PASS_SH" --waits >/dev/null 2>&1; echo $?)"

# Issue 312: the reviewer's /plugin config keys pick its agent and model; a plugin update replaces routing.json, never
# them. Caught: a key the pass never read, and a Claude reviewer that could write.
opts() { mkdir -p "$HOME/.claude"; jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: $o}}}' > "$HOME/.claude/settings.json"; }
pre() { (cd "$REPO" && PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --preflight 2>"$TMP/err" | cut -f1); }
printf '{"models":[{"slug":"gpt-6.1-sol"},{"slug":"gpt-6.2-astra"}]}\n' > "$CODEX_HOME/models_cache.json"
opts '{}'
check "codexReviewerAgent unset: the pass runs the companion on sol" "gpt-6.1-sol" "$(pre)"
opts '{"codexReviewerModel": "astra"}'
check "codexReviewerModel=astra: the reviewer runs the astra id" "gpt-6.2-astra" "$(pre)"
opts '{"codexReviewerAgent": "claude"}'
check "codexReviewerAgent=claude: the pass runs headless Claude on sonnet and its argv denies Write, Edit and NotebookEdit" \
  "sonnet:1:1" "$(pre):$(cd "$REPO" && bash -c '. "$1/scripts/paths.sh"; pp_argv codex-reviewer' _ "$REAL" | grep -c '^-p$'):$(cd "$REPO" && bash -c '. "$1/scripts/paths.sh"; pp_argv codex-reviewer' _ "$REAL" | grep -cx 'Write,Edit,NotebookEdit')"
# Class caller-mismatch (r3): an owner's pane-shaped Claude reviewer row still runs as the headless pass, on its model.
jq '.roles["codex-reviewer"] = {agent: "claude", model: "opus", effort: "high", unboxed: true, edits: false, tools: ["Write", "Edit", "NotebookEdit"]}' \
  "$REAL/config/routing.json" > "$TMP/pane-routing.json"
check "a pane-shaped Claude reviewer row passes preflight as the headless pass on its model" opus "$(COMMANDECK_ROUTING=$TMP/pane-routing.json pre)"
opts '{"codexReviewerModel": "opus"}'
check "a reviewer model the key does not take is refused naming the key" "1" "$(pre >/dev/null; grep -c 'codexReviewerModel' "$TMP/err")"
rm -f "$HOME/.claude/settings.json"

# Issue 335: a pass that waits on its reviewers in silence reads as a hung one. It says it started, then that it runs.
printf 'echo five\n' > "$W/a.sh"
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-6 STUB_SLEEP=4 COMMANDECK_PASS_TICK=1 \
  bash "$PASS_SH" "$U" 6 review >"$TMP/out" 2>"$TMP/err")
check "a pass whose fake reviewer runs several ticks prints the start line and at least two progress lines" "1 1" \
  "$(grep -c '^pass 6: 1 reviewer(s) started$' "$TMP/out") $([ "$(grep -c '^pass 6: reviewers running, 0 min, reviewer 1 session' "$TMP/out")" -ge 2 ] && echo 1 || echo 0)"

# Issue 361: a signed-in Codex that answers the one-word request in 31 s is slow, not signed out. The one slow case, last.
printf 'echo six\n' > "$W/a.sh"; echo 31 > "$TMP/probe-sleep"; : > "$TMP/probe"; echo 0 > "$TMP/probe-fail"
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_PROBE_BACKOFF=0 STUB_THREAD=thr-7 \
  bash "$PASS_SH" "$U" 7 review >"$TMP/out" 2>"$TMP/err"); RC=$?
check "a probe answering after 31 s passes: one try, no refusal" "0 1 0" \
  "$RC $(wc -l < "$TMP/probe" | tr -d ' ') $(grep -c 'launch refused: Codex is not signed in' "$TMP/err")"

# Issue 359 (5c) and the rule drift items RD1 to RD3: one first pass of three reviewers over a unit whose plan carries claims
# to falsify and decisions, and whose brief states a limit. After the slow case above, since it adds a pass.
mkdir -p "$W/.claude/plans"
printf '# Plan: p\n\n## What can go wrong\n\n| case | x |\n|---|---|\n| CASE-PROBE | y |\n\n## Claims to falsify\n\n1. CLAIM-PROBE the plan says so.\n\n## Decisions\n\n1. DECISION-PROBE a ruling.\n\n## Accepted failure modes\n\n1. ACCEPTED-PROBE not a claim.\n' > "$W/.claude/plans/$U.md"
printf 'Plan: .claude/plans/%s.md\n' "$U" >> "$B/$U.md"
printf '\n## Stated limits\n- LIMIT-PROBE: one measured bound\n' >> "$MAINBRIEF"
printf 'echo seven\n' > "$W/a.sh"
(cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-8 \
  bash "$PASS_SH" "$U" 8 adversarial >"$TMP/out" 2>"$TMP/err") || { echo "FAIL the adversarial pass r8 did not run: $(cat "$TMP/err")"; FAIL=$((FAIL+1)); }
P8=$B/$U-r8-prompt-2.md
at() { grep -n -m1 -- "$1" "$P8" | cut -d: -f1; } # <pattern>: the first line of the behaviour reviewer's prompt that matches
# The raw claims start a line; the same words in the diff start with its + mark. Issue 366: the accepted failure modes
# reach every pass, under their own head after the claims.
check "the review prompt places the plan's claims after the trace instruction" "yes yes yes 1 1 1" \
  "$([ "$(at 'Trace each changed branch with a concrete input')" -lt "$(at '^-echo base$')" ] && echo yes || echo no) \
$([ "$(at '^-echo base$')" -lt "$(at '^[0-9]\. CLAIM-PROBE')" ] && echo yes || echo no) \
$([ "$(at 'claims to falsify, not facts')" -lt "$(at '^[0-9]\. CLAIM-PROBE')" ] && [ "$(at '^[0-9]\. CLAIM-PROBE')" -lt "$(at '^[0-9]\. DECISION-PROBE')" ] && echo yes || echo no) \
$(grep -c '^| CASE-PROBE' "$P8") $(grep -c '^[0-9]\. DECISION-PROBE' "$P8") $(grep -c '^[0-9]\. ACCEPTED-PROBE' "$P8")"
# RD1: a finding reopens a decision, an accepted failure mode or a stated limit only on a concrete counterexample.
check "the review prompt reopens a decision only on a concrete counterexample" "1 1" \
  "$(grep -c "only when it proves the item's factual premise false or shows the goal defeated, with a concrete counterexample" "$P8") $(grep -c '^- LIMIT-PROBE' "$P8")"
# RD2: a limit is a measured bound, and a finding beyond one is a follow-up.
check "a finding beyond a stated limit is a follow-up, never a blocker" 1 \
  "$(grep -c 'a finding beyond one is out of scope: a follow-up issue, never a blocker' "$P8")"
# RD3: the failing-test default, the cold-read order and the scope rule.
check "the review prompt carries the failing-test default, the cold-read order and the scope rule" "1 1 1 1 1 1 1 1" \
  "$(for s in 'written to fail on the diff as it stands' 'whose test is written and whose fix is under ten lines' 'a reviewer never reviews its own fix' \
  'This prompt, the brief and the dispatch spec outrank the startup file' 'runtime_unavailable' "draft your findings, and only then open the author's evidence" \
  'only to confirm or refute one finding, and say which' 'never a generated file'; do grep -cF -- "$s" "$P8"; done | paste -sd' ' -)"

# Issue 362: the Break gate before pass 1, run on a hand-written plan and evidence file (the gate's own function).
GATEFNS=$(sed -n '/^round_files()/,/^}/p;/^plan_rel()/p;/^plan_file()/p;/^evidence_section()/,/^}/p;/^break_gate()/,/^}/p' "$PASS_SH")
GW=$TMP/gate; mkdir -p "$GW/.claude/briefs" "$GW/.claude/plans"
printf 'Plan: .claude/plans/g.md\n' > "$GW/.claude/briefs/g.md"
gate() { (die() { echo "REFUSED: $*" >&2; exit 2; }; WT=$GW UNIT=g EV=$GW/.claude/briefs/g-evidence.md; eval "$GATEFNS"; break_gate) 2>&1; echo "rc=$?"; }
printf '# Plan\n\nBreak: t/a.test.sh -- the first check -- a.sh the gate\nBreak: t/b.test.sh -- the second check -- b.sh the rule\n\n```\nBreak: t/fenced.test.sh -- not a line -- x\n```\n' > "$GW/.claude/plans/g.md"
printf '## Break runs\n\n- t/a.test.sh -- the first check -- red: sed -i s/x/y/ a.sh; bash t/a.test.sh\n' > "$GW/.claude/briefs/g-evidence.md"
OUT=$(gate)
check "pass 1 refuses when a plan Break line has no recorded break run, naming it and not the ones that have one" "rc=2 1 0 0" \
  "$(tail -1 <<<"$OUT") $(grep -c 't/b.test.sh -- the second check' <<<"$OUT") $(grep -c 't/a.test.sh -- the first check' <<<"$OUT") $(grep -c 'fenced' <<<"$OUT")"
printf -- '- t/b.test.sh -- the second check -- red: bash t/b.test.sh with the rule removed\n' >> "$GW/.claude/briefs/g-evidence.md"
check "pass 1 runs when every Break line has a red break run (the fenced one is no line)" "rc=0" "$(gate)"
printf '## Break runs\n\n- t/a.test.sh -- the first check -- red: \n- t/b.test.sh -- the second check -- red: bash t/b.test.sh\n' > "$GW/.claude/briefs/g-evidence.md"
check "a break run with no command does not count" "rc=2" "$(gate | tail -1)"
printf '# Plan\n\nno break lines here\n' > "$GW/.claude/plans/g.md"; : > "$GW/.claude/briefs/g-evidence.md"
check "a plan with no Break line owes nothing" "rc=0" "$(gate)"
printf 'Break: t/a.test.sh -- c -- s\n' > "$GW/.claude/plans/g.md"; printf 'VERDICT: GO\n' > "$GW/.claude/briefs/g-r1-reports.md"
check "a unit with a round file already is past pass 1: the gate owes nothing" "rc=0" "$(gate)"
rm -f "$GW/.claude/briefs/g-r1-reports.md" "$GW/.claude/briefs/g.md"
check "a unit whose brief names no plan owes nothing" "rc=0" "$(gate)"

# Issue 341: the failure table gate before pass 1, on a hand-written brief and evidence file.
TGATEFNS=$(sed -n '/^round_files()/,/^}/p;/^evidence_section()/,/^}/p;/^table_gate()/,/^}/p' "$PASS_SH")
tgate() { (die() { echo "REFUSED: $*" >&2; exit 2; }; WT=$GW UNIT=g EV=$GW/.claude/briefs/g-evidence.md; eval "$TGATEFNS"; table_gate) 2>&1; echo "rc=$?"; }
# The batch comes first in a Builder brief, the template's own Data design section after it.
brief() { printf '## The issues\n\n## Data design\n\n%s\n\n## The batch\n\nx\n\n## Data design\n\nThe batch'"'"'s Data design section above binds.\n' "$1" > "$GW/.claude/briefs/g.md"; }
HEAD4='## Failure table\n\n| Save | Steps | Left behind if it stops after each step | The one recovery |\n|---|---|---|---|\n'
brief '- the reply file: lives in a.json; written by the pass'; printf '## Data design\n\nx\n' > "$GW/.claude/briefs/g-evidence.md"
OUT=$(tgate)
check "pass 1 refuses a unit with a data design and no failure table row, showing the row shape" "rc=2 1" \
  "$(tail -1 <<<"$OUT") $(grep -c '| Save | Steps | Left behind if it stops after each step | The one recovery |' <<<"$OUT")"
printf "$HEAD4" > "$GW/.claude/briefs/g-evidence.md"
check "a table with only its header and separator is no row" "rc=2" "$(tgate | tail -1)"
printf "$HEAD4"'| reply file | write, rename | a half file | rewritten by the next pass |\n' > "$GW/.claude/briefs/g-evidence.md"
check "pass 1 runs for a unit with a data design and a four-cell row" "rc=0" "$(tgate)"
printf "$HEAD4"'| reply file | write, rename | a half file |\n' > "$GW/.claude/briefs/g-evidence.md"
check "a row with three cells is no row" "rc=2" "$(tgate | tail -1)"
printf "$HEAD4"'| reply file | write, rename | | rewritten |\n' > "$GW/.claude/briefs/g-evidence.md"
check "a row with an empty cell is no row" "rc=2" "$(tgate | tail -1)"
brief 'none: no state is added or changed'; : > "$GW/.claude/briefs/g-evidence.md"
check "pass 1 runs for a unit whose data design is none" "rc=0" "$(tgate)"
printf 'no data design heading at all\n' > "$GW/.claude/briefs/g.md"
check "a brief with no Data design section owes no table" "rc=0" "$(tgate)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
