#!/usr/bin/env bash
# builder-codex-pass.sh <unit> <N> adversarial|review|final -- run one Builder
#     review pass and write its round file,
#     .claude/briefs/<unit>-r<N>-reports.md, from the reviewer's own session
#     records. A Builder never writes its review record by hand: a self-written
#     GO is self-attestation.
#       adversarial  the whole branch, the first pass: three reviewers at once, one
#                    angle each, or one reviewer with all three angles when the
#                    build is under 200 changed lines and not a risky launch
#       review       narrowed: the changes since the last pass and its findings;
#                    run as final when main's brief or rulings changed since then
#       final        the whole branch, one reviewer; the closing pass
# builder-codex-pass.sh --verify <worktree> <unit> <tip> -- the merge's check
#     (merge-unit-local.sh, Builder worktrees only). The last round file only
#     names the pass's sessions; the verdict and the reviewed SHA come from
#     each session's own file (Codex: ${CODEX_HOME:-~/.codex}/sessions), which
#     must have run in <worktree>, on <tip> or on a commit <tip> is a clean
#     rebase of (a merge-tree of it onto <tip>'s base gives <tip>'s tree), from
#     this script's prompt, and end its final reply with VERDICT: GO. Every
#     reviewer of the pass must be named, and the pass must have read the whole
#     branch: a narrowed pass's GO merges nothing. That is the closing pass, or
#     the first pass when nothing was committed after it: the same check of
#     the same commit. A first pass of one reviewer counts only where the size
#     rule allowed it: the merge counts the commit that pass read itself
#     (build_size).
#     The review threshold (issue 366): a pass that names no open finding at the blocking severity
#     (reviewBlockSeverity, P2 by default: P0 to P2) ends GO, so a lower one never holds
#     the merge; from the REVIEW_CAP-th pass (reviewPassCap, 5 by default) on the reviewer's record, a closing NO-GO that names no P0 or P1
#     merges too (a cap stop); a P0 or P1 is never capped, and one still held two passes past the cap stops
#     the unit for the owner (REVIEW STOP). What is open at the merge is printed, one Open finding line
#     each, for main to file. A finding blocks only when normal use would hit the bug (issue 325): a
#     bypass or odd-setup finding is a known gap, a plain line with
#     no level and no class tag, which the gate below does not count. With no closing pass (reviewLoop.closingPass no), a
#     narrowed pass's GO merges when narrowed passes read every commit after
#     the last first pass. The proof's first line ends with the rule: closing
#     GO, threshold stop, cap stop, first-pass GO or no closing pass.
#     Each pass but the closing one lists, in its prompt, every earlier pass the reviewer's session
#     files held for the worktree at its launch (session, end time, findings);
#     the merge takes such a pass's GO only while that list is still exactly the record. The closing
#     pass is handed no earlier finding; every other pass on record must have ended before it began.
# builder-codex-pass.sh --preflight -- print `<model>\t<companion>` or fail;
#     builder-launch.sh runs it so a Builder never starts without a working pass.
# builder-codex-pass.sh --ack-rulings <unit> -- say main's rulings file was read.
# builder-codex-pass.sh --check <unit> <N> <kind> -- run a launch's own checks up to the Codex sign-in check,
#     the evidence-file ones included, in a copy of the index: it stages, commits and launches nothing.
#
# Each Codex pass is a persisted `task` thread of the Codex plugin companion: its
# review threads are ephemeral and leave no session record to check. The pass
# commits the worktree (`.claude/briefs/` excepted) before the reviewer reads it,
# so the session's commit is exactly the reviewed content. The model and effort
# come from roles["codex-reviewer"], fast mode from set-up's saved answer; the
# companion runs on ${CODEX_HOME:-~/.codex}, so a fast seat needs service_tier = "fast" there.
# The Codex prompt is the installed Codex plugin's prompts/adversarial-review.md,
# read at every run and never copied here: that plugin's built-in review has no
# prompt file, so the review pass sends the same template with a correctness
# focus. --verify reads no plugin file: each pass keeps the prompt it sent in
# <reviewer home>/builder-pass-prompts/<session>, and the session's prompt must
# be that text, whole, and carry the text this script puts into the template. A
# plugin update between a pass and its merge costs nothing; a session with no
# such record was not started by a pass.
#
# The reviewer's agent is codexReviewerAgent in /plugin config (the Claude-only
# profile sets it to claude). On claude each reviewer is a headless session on
# codex-reviewer's claude overlay, its record is its transcript under
# ~/.claude/projects/*/<session id>.jsonl, its prompt is the template in this
# file (that profile has no Codex plugin), and the reviewed commit is the one
# this script names after the prompt (a transcript carries no commit hash).
# --verify reads either round file, by its id lines, and takes only the pass
# the configured agent uses.
# Ceiling: a same-user process could still forge the reviewer's own session
# files or that record; the upgrade path is a merge-side re-run.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
die() { echo "REFUSED: $*" >&2; exit 2; }
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
# Which reviewer this run is: codexReviewerAgent (COMMANDECK_PASS is the self-test's switch). --verify reads it
# from the round file instead.
BY=${COMMANDECK_PASS:-$(pp_pass)} || exit 2
case $BY in codex) NAME="Codex thread" RHOME=$CODEX_DIR ;; claude) NAME="Claude session" RHOME=$CLAUDE_DIR ;; *) die "COMMANDECK_PASS must be codex or claude, not $BY" ;; esac
# pass_waits -- find the reviewer's program (the Codex plugin's companion, or
# claude) and set the pass's two fixed waits: how long it waits for the record
# of a reply (30 s) and the step of the wait for a reviewer's helper to start
# (0.2 s). They are set here and read from nowhere else, so no variable a pane
# inherits shortens a real pass. The self-test's switch is a file beside its
# STUB reviewer, which neither program has as it ships: it names a shorter
# record wait, in seconds.
pass_waits() {
  if [ "$BY" = claude ]; then
    COMPANION=$(command -v claude) || die "no claude on PATH; the Claude-only review pass runs it headless"
  else
    COMPANION=$(ls -d "$CLAUDE_DIR"/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1 || true)
    [ -n "$COMPANION" ] || die "no Codex plugin companion under $CLAUDE_DIR/plugins/cache/openai-codex/codex"
  fi
  RECORD_WAIT=30 HELPER_STEP=0.2
  [ -e "${COMPANION%/*}/commandeck-test-waits" ] || return 0
  RECORD_WAIT=$(cat "${COMPANION%/*}/commandeck-test-waits")
  [[ $RECORD_WAIT =~ ^[0-9]+$ ]] || die "${COMPANION%/*}/commandeck-test-waits must hold a number of seconds"
  HELPER_STEP=0.02
}
[ "${1:-}" != --waits ] || { pass_waits; echo "record_wait=$RECORD_WAIT helper_step=$HELPER_STEP"; exit 0; }
# The lowest severity that holds a merge (reviewBlockSeverity: P1, P2 or P3), as a digit, with the words the prompt
# and the messages use for it. The default is P2: P0 to P2 hold, a P3 never does.
BLOCK_AT=$(pp_review_loop blockAt P2 '^P[123]$') || exit 2
BLK=${BLOCK_AT#P}
case $BLK in
  1) BLOCK_LEVELS='P0 or P1' BLOCK_NONE='P2 and P3 findings and known gaps' BELOW='P2 and P3' CAP_LEVELS=P2 ;;
  2) BLOCK_LEVELS='P0, P1 or P2' BLOCK_NONE='P3 findings and known gaps' BELOW=P3 CAP_LEVELS=P2 ;;
  3) BLOCK_LEVELS='P0, P1, P2 or P3' BLOCK_NONE='known gaps' BELOW=no CAP_LEVELS='P2 or P3' ;;
esac
# What this script puts into the template. The Codex plugin's one output block
# asks for JSON against a schema only that plugin's own review command
# attaches; FORMAT replaces that block's content, so the prompt carries one
# output instruction, and every other block goes out as the plugin wrote it.
FORMAT='No schema is provided, so do not return JSON. List each finding as one line: - [P<0-3>] (class: <tag>) <title> -- <file>:<line> -- <why it matters> -- <the exact failing input or command>. Leave out a finding you cannot give one for, whatever its level, and never invent one. The class is one short kebab-case tag for the kind of defect (for example old-format-case), the same tag for the same kind in every pass. Under each blocking finding write one line, Class search: rg <arguments>, a read-only rg search run from the repository root whose hits are every place with the same mistake, the <file>:<line> of that finding among them; the author must answer for each hit. A known gap carries no Class search line. P0 is critical, P1 high, P2 medium, P3 low. A gap in documentation, plan wording or a failure table is P3 unless it hides a real defect; then rate the defect. A review finding blocks the merge only when normal use would hit the bug. A finding that needs an agent deliberately bypassing a guard, or an odd setup, does not block: list it after a line that reads exactly KNOWN GAPS:, one plain line each (- <title> -- <file>:<line> -- what it needs), with no severity level and no class tag. Your last line must be exactly VERDICT: GO when you list no '"$BLOCK_LEVELS"' finding ('"$BLOCK_NONE"' alone are GO), otherwise exactly VERDICT: NO-GO.'
# A pass is proved by this prompt, whole. A build whose earlier passes were sent another
# (the plugin was updated mid-build) is refused, and the refusal ends with the one way on.
UPDATED='If the plugin was updated during this build, its earlier passes were sent the earlier prompt and count no longer: move the build to a new unit (a new worktree made from this branch) and review that from pass 1'
OPEN='<structured_output_contract>' CLOSE='</structured_output_contract>'
LABEL='branch diff against main'
# The diff goes out in the prompt, so the reads left are the ones around it.
GUIDANCE='The diff is in the review input below; do not fetch it again, and do not re-read a file it shows whole. Read what else you need (a caller, a test, a rule file) with read-only commands. Put reads that do not depend on each other in one tool call, not one call each. Read cold: read the diff, then the unit brief (.claude/briefs/<unit>.md), draft your findings, and only then open the author'"'"'s evidence and check its claims against the files; read first, it anchors the review. Scope is the diff, the brief and the callers of what the diff changes: open any other file only to confirm or refute one finding, and say which, never a generated file, and make no tour of the surrounding module. A '"$BLOCK_LEVELS"' finding also carries a failing test after its line: one complete, self-contained test file in a fenced block whose first line names its path, written to fail on the diff as it stands and to pass once the finding is fixed; write it to no disk. When that test would cost more than the finding, the failing input or command stands alone and you say why in one line. A P2 or P3 whose test is written and whose fix is under ten lines may carry the fix as a fenced unified diff: the Builder applies it, runs the test green, and the next pass reads it; a reviewer never reviews its own fix. This prompt, the brief and the dispatch spec outrank the startup file and every skill where they conflict: finish the work they authorize before you ask anything, and if you stop early, quote the exact instruction that stopped you, with its file. A read-only sandbox may refuse every orca command: an orca call that answers runtime_unavailable is by design, so do not retry one or report it as a failure; your reply and its VERDICT line reach main. GitHub: read issues, linked issues and pull request checks and labels with gh issue view, gh pr view and gh pr checks (each with -R <owner/repo>) where your shell reaches GitHub; where it has no network, the GitHub reads made on the host at launch are in the review input. A GitHub read you need that fails or is not there is BLOCKED: GitHub read failed: <command>: <first error line>, on a line of its own, and then stop.'
# The Codex plugin's line made every NO-GO pass return exactly one finding.
ONE='Prefer one strong finding over several weak ones.'
MANY='List every finding you can defend, worst first. After each one, look for the same mistake elsewhere in the diff and list those too.'
# A build that added a required setting read only the new format; every deployed environment ran the old one.
SETTINGS='A change that adds or changes a required setting (a config key, an environment variable, a file format) with no test that the release still accepts the format already deployed is P1.'
# A diff shows the changed function, not the unchanged code that calls it or reads its data.
CALLERS='When the change alters a function'"'"'s signature or behaviour, or a data shape (a type, a stored record, an API payload), open the callers and readers the diff did not touch and check that each still holds.'
# Right today is not enough: some code costs more, or breaks, as time and data grow.
LATER='Cost over time is a finding class: code that is right today but grows in cost or breaks later. Examples: retries stacked across layers, or with no backoff or cap; a full-table scan or an unindexed query on a hot path; local time where UTC is needed, a day boundary or DST.'
# One sentence for the full pass and the behaviour angle: a reviewer that stops at the first failing ordering returns the next one each round.
ORDERINGS='When the diff involves timers, background loads, retries, concurrent writes or tab or page switches, list EVERY ordering of those events in this first pass, check each, and report every ordering that fails, not the first.'
# Issue 341: a build whose state had no owner, reset or retry path found the same fault in pass after pass. The first
# pass reads the brief's Data design section before the diff.
DATA_DESIGN='Before anything else, check the Data design section of the unit brief: for each piece of state it names (where it lives, who writes it, who reads it, when it resets, what a retry runs), the diff must keep to it. Report as P1 (class: data-design) state the diff adds or changes that the section does not name, an owner, reset or retry the diff contradicts, and a section that is empty or still the template'"'"'s placeholder.'
# Issue 282: an exception a comment justified hid a real gap for months.
EXCEPTION='An exception, allowlist or exemption entry in a guard or its test stands only when the same test proves the alternative it claims, or the entry cites an owner ruling id. A comment is not proof. Report an entry that has neither as P1.'
FOCUS_REVIEW="Correctness bugs, security problems and missing tests in the changed lines. $SETTINGS $CALLERS $LATER $ORDERINGS $EXCEPTION"
# Asked in every pass and by every reviewer, after its focus.
LENS="Paved road: does this change hand-build something .claude/paved-road.md or a published standard already covers, or break its area's standard? Such a finding cites the registry row (its area)."
# The Claude reviewer's template: the same slots and the same two lines this
# script replaces, so one function fills both.
CLAUDE_TEMPLATE="You are reviewing a code change. Target: {{TARGET_LABEL}}.
Focus: {{USER_FOCUS}}
{{REVIEW_COLLECTION_GUIDANCE}}
$ONE
$OPEN
$CLOSE

{{REVIEW_INPUT}}"
# The first pass is these reviewers at once, each leading with one angle and
# handed all three; on a small build it is one reviewer (SMALL_BUILD).
ANGLES=(
  "Angle 1 of 3, bypass and trust: can any check, guard, proof or gate in this change be skipped, forged or made to pass when it should refuse? Look at every input the change trusts. $EXCEPTION"
  "Angle 2 of 3, behaviour: wrong results, edge cases, failure paths and callers the change breaks. Trace each changed branch with a concrete input. $SETTINGS $CALLERS $LATER $ORDERINGS"
  'Angle 3 of 3, tests and words: a changed behaviour with no test, a test that cannot fail, and comments, rule text or docs the change leaves untrue.'
)
# The first line of the review input says which pass this is, then "Reviewer <k>
# of <n>, round <N>." The merge reads the pass's kind, its reviewers and its
# round from that line, so a GO of another kind or another round is not taken
# for the closing pass's; no diff line and no finding line can spell it, since
# each starts with its own mark.
HEAD_FULL='Review input: the whole branch diff against main (git diff main...HEAD).'
HEAD_FIX='Review input: a narrowed pass, not the closing review. Only the changes since the last pass are below.'
HEAD_FINAL='Review input: the closing pass, the whole branch diff against main (git diff main...HEAD).'
# Host change (owner order 2026-10-25): a final whose commit changes no code is read for its design alone; its GO merges nothing.
HEAD_DESIGN='Review input: a design-only pass, not the closing review. The last commit changes only the plan, the briefs or the metrics, so judge the design and expect the code to follow. The whole branch diff against main (git diff main...HEAD) is below.'
# The same mistake came back pass after pass, one finding at a time.
# The block runs from this line to EARLIER_END and is the one place the merge
# looks for what the closing reviewer was handed: no diff line can spell
# either line, or a line inside the block, since each starts with its own mark.
EARLIER_HEAD='Findings of the earlier passes on this branch, already with the author. Report one again only if it is still there, and ask what else in the diff is like these:'
EARLIER_END='End of the earlier passes.'
# Issue 261: a variant of an earlier finding under a new tag hid that one class came back.
SAME_CLASS='A finding of the same kind of input in the same function as an earlier one keeps that finding'"'"'s class tag.'
# Issue 265: a fix round changed a behaviour the owner still had an open question on.
HOLD_HEAD='The owner'"'"'s decisions that name this unit. A finding on a behaviour an open question below covers ends its title with [HOLD <id>]: the author sends it to main and does not fix it:'
# A finding line in a reviewer's reply: a level token or a class tag on any line but the verdict. The owner chose
# a fixed rule over a Markdown parser, since each parser missed a new wrap; one copy, read as ERE and as Python re: the gate,
# the hand-on to the next reviewer and the tests per finding all count the same lines.
FINDING='(^|[^A-Za-z0-9])P[0-3]([^0-9]|$)|\(class:'
# Issue 362: the plan's list of what can go wrong, and the Builder's search for the other sites of a NO-GO's pattern.
CASES_HEAD='What can go wrong, from the plan: check the code and its tests against each case; a case the code breaks, or whose named test is missing or cannot fail, is a finding. A finding on a case not in this list ends with (not in the plan list).'
SITES_HEAD='Sites checked: the Builder'"'"'s search for other places with the pattern of the last pass'"'"'s findings, with each site marked fixed or not affected. A site of the pattern that is missing from this list, or marked not affected for a wrong reason, is a finding:'
NEWCODE_HEAD='New code checked: the Builder'"'"'s check of each read, write or check its last fix added or changed against the plan'"'"'s rules (Data design, What can go wrong, the failure table). A site the fix added that is missing from this list, or that breaks the plan line it names, is a finding:'
# Issue 359 (5c): the plan's claims to falsify and its decisions, read after the diff and tried against it, never taken as fact.
CLAIMS_HEAD='From the plan, after the diff: its claims to falsify and its decisions. These are claims to falsify, not facts: try to break each checkable one against the diff and the code, and report a claim the diff or its tests do not hold.'
# Issue 366 (O2): the plan's accepted failure modes go to every reviewer, the fresh closing one included, after the diff.
# The host's fresh-closing line, narrowed to the files that hold review history: the plugin's diff still carries the
# plan, and the unit brief's Data design binds every pass (DATA_DESIGN), so the brief stays open.
FRESH_HEAD='This is the fresh closing pass. Do not open the evidence file, the round reports or fix hand-offs under .claude/briefs (<unit>-r<N>-*, <unit>-fix-r<N>.md), or git log: they carry the review history this pass is kept clear of. The unit brief itself you may read.'
ACCEPTED_HEAD='Accepted failure modes, from the plan: each is a cost the plan accepts. A finding that is one of these is not a finding unless it proves the item'"'"'s premise false with a concrete counterexample; otherwise cite the item and do not list the finding:'
# The host's reopen rule and stated-limits heading: a finding reopens an accepted item only on a concrete counterexample, and a finding beyond a limit is a follow-up.
LIMITS_HEAD='Stated limits of this build, set by main (every reviewer is handed these; a finding beyond one is out of scope: a follow-up issue, never a blocker). A finding reopens an accepted failure mode, a decision or a stated limit only when it proves the item'"'"'s factual premise false or shows the goal defeated, with a concrete counterexample; otherwise cite the item'"'"'s line and do not list the finding. A finding inside a stated limit is not a finding: do not list it:'
DEFERRED_HEAD='Known and deferred to main: each item below needs main'"'"'s own hands (a settings file entry, a file only main edits), and main has it. Do not report a listed item again. Report anything else, a new defect in the same file included, and report a listed item that this branch could fix itself, since that is not main-only:'
# The Builder's own lines for round N in its evidence file, "Different fix r<N>: <why>" and
# "Other cases checked r<N>: <which>": a fix other than the one a finding named, and the
# other cases of the same fault a fix covers, go to the reviewer with the diff.
AUTHOR_HEAD="The author's notes on this round, from its evidence file: why it took a fix other than the one a finding named, and which other cases of the same fault it checked. Check each against the diff:"
# shortcut: past this many bytes the files do not go out whole, only the plain diff; raise it when the reviewer model's window grows.
DIFF_MAX=${COMMANDECK_PASS_DIFF_MAX:-400000}
# Codex refuses an input over 1048576 characters. Past this many a deleted file is named and its old text left out.
DIFF_HARD=${COMMANDECK_PASS_DIFF_HARD:-900000}

# session_proof <session id> <worktree> <sha> [wait-s] -- for the reviewer $BY
# names, print the verdict line, then
# "<full|fix|final|design> <k> <n> <round> <began> <ended> <read> <since> <said>" (the pass's kind, reviewer
# k of n, its round, when the record says the turn began and ended, "-" when it does not, and
# the three parts the no-closing-pass chain follows), then the final
# reply without its verdict; refuse (exit 2) when the session does not bind them.
# The pass waits: Codex flushes task_complete about a second after the companion returns.
# The prompt is checked against this script's own text only: the merge
# reads no plugin file, so a plugin update after a pass does not undo the pass.
session_proof() {
  BLK=$BLK python3 - "$BY" "$1" "$2" "$3" "${4:-0}" "$RHOME" "$HEAD_FULL" "$HEAD_FIX" "$HEAD_FINAL" "$HEAD_DESIGN" "$OPEN"$'\n'"$FORMAT"$'\n'"$CLOSE" "$UPDATED" "$FINDING" "$HERE" "$LABEL" "$GUIDANCE" "$MANY" "$LENS" <<'PY'
import glob, json, os, re, subprocess, sys, time
by, tid, wt, sha, wait, home, head_full, head_fix, head_final, head_design, block, updated, finding, here, *fixed = sys.argv[1:]
sys.path.insert(0, here)
from unit_folders import belongs
name, where = ("Claude session", "projects") if by == "claude" else ("Codex thread", "sessions")
def die(msg):
    print(f"REFUSED: {msg}", file=sys.stderr)
    sys.exit(2)
stamp = lambda t: t if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z", t) else "-"
if not re.fullmatch(r"[A-Za-z0-9-]+", tid):
    die(f"bad {name} id {tid!r}")
def read_claude():
    # A prompt is a user row with text of its own; a tool result has none. Each
    # one starts a turn, and a turn's reply is its last assistant text.
    files = glob.glob(os.path.join(home, "projects", "*", f"{tid}.jsonl"))
    meta, user, turns = None, [], []
    global began, ended
    began = ended = "-"
    for line in open(files[0], encoding="utf-8") if len(files) == 1 else []:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict) or row.get("isSidechain") or row.get("isMeta"):
            continue
        c = (row.get("message") or {}).get("content")
        text = c if isinstance(c, str) else "\n".join(
            b.get("text") or "" for b in c or [] if isinstance(b, dict) and b.get("type") == "text")
        if row.get("type") == "user" and text.strip():
            turns.append(None)
            body, _, asked = text.strip().rpartition("\nCommit under review: ")
            user.append(body.strip())
            if meta is None:
                meta, began = {"id": row.get("sessionId"), "cwd": row.get("cwd"), "git": {"commit_hash": asked}}, row.get("timestamp") or "-"
        elif row.get("type") == "assistant" and text.strip() and turns:
            turns[-1] = text
            if len(turns) == 1:
                ended = row.get("timestamp") or "-"
    return files, meta, user, [t for t in turns if t], ["task_started"] * len(turns)
def read():
    if by == "claude":
        return read_claude()
    files = glob.glob(os.path.join(home, "sessions", "**", f"rollout-*-{tid}.jsonl"), recursive=True)
    meta, user, replies, events = None, [], [], []
    global began, ended
    began = ended = "-"
    for line in open(files[0], encoding="utf-8") if len(files) == 1 else []:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        p = row.get("payload") or {}
        if row.get("type") == "session_meta" and meta is None:
            meta, began = p, row.get("timestamp") or "-"
        elif row.get("type") == "response_item" and p.get("role") == "user":
            user += [c.get("text") for c in p.get("content") or [] if isinstance(c, dict)]
        elif row.get("type") == "event_msg":
            events.append(p.get("type"))
            if p.get("type") == "task_complete":
                replies.append(p.get("last_agent_message"))
                if len(replies) == 1:
                    ended = row.get("timestamp") or "-"
    return files, meta, user, replies, events
deadline = time.monotonic() + float(wait)
files, meta, user, replies, events = read()
while not replies and time.monotonic() < deadline:
    time.sleep(0.5)
    files, meta, user, replies, events = read()
# No sha: the caller is asking what an EARLIER pass of this worktree found
# (pass_threads says which threads those are). One with no finished reply,
# cut off or still running, prints when it began and exits 3: earlier_passes says
# what that means to its caller. Any other
# is read from its first turn, the review itself, so resuming it takes nothing
# out; whatever then cannot be read refuses (exit 2), a missing prompt copy too.
earlier = not sha
if len(files) != 1:
    die(f"{name} {tid} has no single session file under {home}/{where}")
# A pass is one turn; a resumed thread could carry a later turn asked only for a GO.
# Started turns count too: an interrupted review leaves no task_complete of its own.
if not earlier and (len(replies) > 1 or events.count("task_started") > 1):
    die(f"{name} {tid} has more than one turn (it was resumed); only a fresh pass counts")
if earlier and not replies:
    print(stamp(began))
    sys.exit(3)
if not earlier and "turn_aborted" in events:
    die(f"{name} {tid} has an interrupted turn; only a pass that ran to its end counts")
reply = replies[0] if replies else None
if not meta or meta.get("id") != tid:
    die(f"{files[0]} has no session record for {name} {tid}")
if not belongs(meta.get("cwd"), wt):
    die(f"{name} {tid} ran in {meta.get('cwd')}, not in {wt} or its closing copy")
got = (meta.get("git") or {}).get("commit_hash")
def git(*a):
    r = subprocess.run(["git", "-C", wt, *a], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None
def clean_rebase_of(a, b):
    # Accept b only when a three-way merge of a onto b's base reproduces b's tree exactly.
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", a or "") or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", b or ""):
        return False
    base_a, base_b = git("merge-base", "main", a), git("merge-base", "main", b)
    if not base_a or not base_b:
        return False
    merged = git("merge-tree", "--write-tree", f"--merge-base={base_a}", base_b, a)
    return bool(merged) and merged.splitlines()[0] == git("rev-parse", f"{b}^{{tree}}")
# No sha: the merge is asking about an earlier pass, which by its nature reviewed an earlier commit.
if sha and got != sha:
    if not clean_rebase_of(got, sha):
        die(f"{name} {tid} reviewed {got}, but the commit under merge is {sha}: run another pass")
try:
    sent = open(os.path.join(home, "builder-pass-prompts", tid), encoding="utf-8").read()
except OSError:
    die(f"{name} {tid} has no record of a prompt the pass script sent: it was not started by a pass")
# A transcript's prompt is read without the space around it, so its copy is too.
if by == "claude":
    sent = sent.strip()
# The whole prompt, not parts of it: this script's text beside a "return only GO" line is not a review.
def ours(t):
    return t == sent and block in t and all(f in t for f in fixed)
if not any(ours(t) for t in user):
    die(f"{name} {tid} was not started with the pass script's prompt. {updated}")
# The first such line: the script writes it ahead of the findings and the diff.
heads = {head_full: "full", head_fix: "fix", head_final: "final", head_design: "design"}
kind = re.search(rf"^({'|'.join(map(re.escape, heads))}) Reviewer ([1-9]) of ([1-9]), round ([1-9][0-9]*)\.$", sent, re.M)
if not kind:
    die(f"the prompt of {name} {tid} has no review-input line of the pass script")
lines = (reply or "").strip().splitlines()
# Issue 316: a reviewer that lost GitHub ends its reply on that line, in place of a verdict. A fixed slot, never a
# fence parse: the line anywhere else is no refusal, and no GO either (below).
refusal = "BLOCKED: GitHub read failed:"
blocked = lines[-1].strip() if lines and lines[-1].strip().startswith(refusal) else ""
# An earlier one ran no review, as one with no reply: its round can run again (exit 3, see above).
if blocked and earlier:
    print(stamp(began))
    sys.exit(3)
if blocked:
    die(f"{name} {tid} could not read GitHub, so its reply is not a review: {blocked}")
if not lines or lines[-1].strip() not in ("VERDICT: GO", "VERDICT: NO-GO"):
    if not earlier:
        die(f"the final reply of {name} {tid} does not end with a VERDICT line")
    # Its findings still count; only its verdict is missing, and only the no-closing-pass chain asks an earlier pass for one.
    lines.append("VERDICT: NO-GO")
    said = "none"
else:
    said = ""
verdict = lines[-1].strip()
# Markdown around or inside a severity tag (**[P3]**, `[P2]`, [__P2__]) comes off here, and any list mark (+, *, 1.)
# reads "- ", so every reader of the report sees "- [P3]". The gate below does not depend on it.
lines = [re.sub(r"^(\s*)((?:[-*+]|\d+[.)])\s+)?[*_`]*\[[*_`]*(P[0-3])[*_`]*\][*_`]*",
                lambda m: f"{m[1]}{'- ' if m[2] else ''}[{m[3]}]", l) for l in lines]
# A GO beside a finding that holds the loop is not a GO (issue 366): a finding at or above the blocking severity
# (BLK, P2 by default), or a class tag with no level. A line whose every level is below it holds nothing. A known gap (issue 325) carries no level and no class tag, so it is no
# finding here. Nor is a GO beside the refusal line, quoted or not: a lost GitHub read may sit above it.
def holds(l):
    levels = re.findall(r"(?:^|[^A-Za-z0-9])P([0-3])(?=[^0-9]|$)", l)
    return bool(re.search(finding, l)) and (not levels or min(levels) <= os.environ["BLK"])
if any(holds(l) or refusal in l for l in lines[:-1]):
    verdict = "VERDICT: NO-GO"
said = said or verdict[9:]
print(verdict)
# What the no-closing-pass chain follows: the commit Codex says it read, where a narrowed pass's
# range began ("whole" for a whole-branch pass), and the verdict as the reply gave it. "?" is
# a part the record does not hold; only that rule refuses on one.
sha_of = lambda t: t if re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", t or "") else "?"
since = re.match(r"\nThe range is git diff ([0-9a-f]+)\.\.HEAD\. ", sent[kind.end():])
print(heads[kind.group(1)], kind.group(2), kind.group(3), kind.group(4), stamp(began), stamp(ended),
      sha_of(got), sha_of(since and since.group(1)) if heads[kind.group(1)] == "fix" else "whole", said)
print("\n".join(lines[:-1]).rstrip())
PY
}
# round_files <worktree> <unit> -- "<N> <path>" for each round file, in no order.
round_files() {
  local f n
  for f in "$1/.claude/briefs/$2-r"[0-9]*-reports.md; do
    [ -e "$f" ] || continue
    n=${f##*/}; n=${n#"$2-r"}; n=${n%-reports.md}
    [[ $n =~ ^[0-9]+$ ]] && echo "$n $f"
  done
  return 0
}
# Issue 366: the review cap. From this many passes on the reviewer's record, a closing NO-GO that names no P0 or P1
# ends the loop (a cap stop: main files what is open, then merges). A P0 or P1 is never capped; one still held at
# REVIEW_CAP + 2 passes stops the unit for the owner (REVIEW STOP). The owner's reviewPassCap (5 by default).
REVIEW_CAP=$(pp_review_loop passCap 5 '^[1-9][0-9]*$') || exit 2
# passes_on_record <earlier_passes text> <round> -- the passes on the reviewer's record: its distinct rounds, <round>
# (the pass launched or verified) among them. Never the round number N, which the Builder chooses.
passes_on_record() { { awk '$1 == "@" { print $6 }' <<<"$1"; echo "$2"; } | sort -u | grep -c .; }
# p01_count -- how many lines on stdin name a P0 or P1 (a line's level is the lowest it names).
p01_count() { grep -cE '(^|[^A-Za-z0-9])P[01]([^0-9]|$)' || true; }
# cappable_count -- how many lines on stdin are findings the cap merges: P2 up to the blocking severity (none when only
# P0 and P1 block). A line that starts with the tag, as session_proof writes it.
cappable_count() { if [ "$BLK" -ge 2 ]; then grep -cE "^[[:space:]]*(- )?\[P[2-$BLK]\]" || true; else cat >/dev/null; echo 0; fi; }
# review_stop_id <earlier_passes text> -- "review-stop-<unit>-r<N>" when the passes on record reach REVIEW_CAP + 2 and
# the latest, N (the one that ended last, never the highest N), still holds a P0 or P1; nothing otherwise. The launch
# gate, the pass's own stop and --verify all ask this one function. A code pass's finding list is the open list, so
# the walk from the latest pass back ends at the first code pass whose every declared reviewer is on record. A
# design-only pass never clears a code finding (only the latest of a run of them is read for its own), and a pass with
# a reviewer missing from the record clears nothing (main's ruling: a pass clears an earlier P0 or P1 only when every
# reviewer it declared is on record and none names one). Three cases are "missing" (#376), and each holds as one unknown
# P1 of its round: a short round (fewer reviewers than it declared), a round whose every reviewer was cut off (a `cut`
# row only), and a reviewer whose reply had no verdict (said none). A round run again after an abandoned launch has its
# cut row and a whole set of rows: it is whole.
review_stop_id() {
  python3 - "$UNIT" "$REVIEW_CAP" "$1" <<'PY'
import re, sys
unit, cap, passes = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rounds, cur = {}, None
for l in passes.splitlines():
    f = l.split(" ")
    if l.startswith("@ ") and len(f) >= 6:
        cur = rounds.setdefault(int(f[5]), {"kind": "", "of": 0, "got": set(), "held": [], "end": "-"})
        cur["end"] = max(cur["end"], f[7])
        # A cut row (a launch with no answer) names no reviewer; nor does a reply with no verdict (said none).
        if f[2] != "cut":
            cur["kind"], cur["of"] = f[2], int(f[4])
            if f[10:] != ["none"]:
                cur["got"].add(int(f[3]))
    elif cur is not None and min(re.findall(r"(?:^|[^A-Za-z0-9])P([0-3])(?=[^0-9]|$)", l) or ["9"]) < "2":
        cur["held"].append(l)
if len(rounds) < cap + 2:
    sys.exit(0)
held, design_read = [], False
# Latest first by the time the pass ended, never by its round number, which the Builder picks (a "-" end sorts oldest).
order = sorted(rounds, key=lambda r: (rounds[r]["end"], r), reverse=True)
for r in order:
    p = rounds[r]
    whole = p["of"] > 0 and p["got"] == set(range(1, p["of"] + 1))
    # A round that is not whole is an unknown P1 where the walk reads its findings.
    unknown = [] if whole else [f"[P1] round {r}: a declared reviewer's verdict is missing"]
    if p["kind"] == "design":
        if not design_read:
            held += p["held"] + unknown
            design_read = whole
        continue
    held += p["held"] + unknown
    if whole:
        break
if held:
    print(f"review-stop-{unit}-r{order[0]}")
PY
}

# A first pass is ONE reviewer when the commit it reads is under this many
# changed lines and main did not launch the build with --risky, else three.
# The owner's number, asked at setup; 200 when not answered; off makes no build small.
SMALL_BUILD=$(pp_review_loop smallBuild 200 '^(off|[1-9][0-9]*)$') || exit 2
# Whether a closing pass over the whole branch runs (asked at setup): with "no",
# a narrowed GO that follows the first pass over every commit merges.
CLOSING=$(pp_review_loop closingPass yes '^(yes|no)$') || exit 2
# Whether the closing pass is a fresh reviewer, handed no review history (freshClosingReviewer). With "no" it is
# handed the history like any pass, and the merge checks what it was handed.
FRESHC=$(pp_review_loop freshClosing yes '^(yes|no)$') || exit 2
# build_size <worktree> <commit> -- print "<lines changed> <files with no count> <risky>" of the
# commit against its fork from main: insertions plus deletions, .claude/briefs/
# left out as the merge leaves it out (collect.py's lines_changed counts the
# same way). <risky> is 1 for a build main launched with builder-launch.sh
# --risky, read from the "## Risky launch" section that launch writes into the
# brief it keeps in main's own checkout, never from a copy in <worktree>: those
# are the Builder's to edit. It is 2 when that copy cannot be read as the
# launcher's brief for this unit (missing, unreadable, or without the first-pass
# line every launch writes): one reviewer needs a positive "not risky" reading,
# and a read that failed is never one.
build_size() {
  local base changed main risky=0
  base=$(git -C "$1" merge-base main "$2" 2>/dev/null) || die "cannot find where commit $2 left main in $1, so its lines changed cannot be counted"
  # Per file, each side whole (no rename pairing, no attribute's own diff or text filter). A file git gives no
  # count for (binary, or marked -diff) is the second number: its size is unknown, so it never reads as small.
  changed=$(git -C "$1" diff --numstat --no-renames --no-ext-diff --no-textconv "$base" "$2" -- . ':(exclude).claude/briefs') || die "cannot count the lines changed between $base and $2 in $1"
  main=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "$1 is not a git worktree, so its launch cannot be read"
  main=${main%/.git}/.claude/briefs/$UNIT-builder-brief.md
  if ! grep -qF -- "-pass.sh $UNIT 1 adversarial" "$main" 2>/dev/null; then risky=2; elif grep -qx '## Risky launch' "$main"; then risky=1; fi
  echo "$(awk '$1 == "-" || $2 == "-" { unknown++; next } NF { n += $1 + $2 } END { print n + 0, unknown + 0 }' <<<"$changed") $risky"
}
# size_words <"lines unknown risky"> -- the three numbers as the pass's line and the merge's refusal say them.
size_words() {
  local n u r
  read -r n u r <<<"$1"
  case $r in 0) r="not a risky launch" ;; 1) r="a risky launch" ;; *) r="no launch brief in main's checkout to say the launch was not risky" ;; esac
  echo "$n lines changed$([ "$u" = 0 ] || echo " and $u file(s) git gives no line count for"), $r"
}
# one_reviewer_fits <"lines unknown risky"> -- the rule itself.
one_reviewer_fits() { [ "$SMALL_BUILD" != off ] && [ "$1" != "${1% 0 0}" ] && [ "${1%% *}" -lt "$SMALL_BUILD" ]; }
# The rule in words, for the pass's line and its refusal.
SMALL_WORDS="one reviewer under $SMALL_BUILD changed lines and no risky launch"
[ "$SMALL_BUILD" != off ] || SMALL_WORDS="never one reviewer: this project turned the small build off"
# one_reviewer_allowed <worktree> <commit a one-reviewer first pass read> <what to call that pass> -- refuse unless the rule allowed it there.
one_reviewer_allowed() {
  local size
  size=$(build_size "$1" "$2") || exit 2
  one_reviewer_fits "$size" \
    || die "$3 is a first pass of one reviewer on a commit of $(size_words "$size"): the rule is $SMALL_WORDS. Run: builder-codex-pass.sh $UNIT <N> adversarial"
}

# pass_threads <worktree> -- "<session id> <round>" for every pass the reviewer $BY names
# has a session of in this worktree: a session file whose recorded cwd is the
# worktree and whose first turn was asked with this script's review-input line.
# Read from the reviewer's own files and not from builder-pass-prompts: that
# folder is this script's, and a pass whose copy there is gone, or was never
# written, still happened. Any other session in the worktree is not a pass.
# shortcut: only session files of the last 14 days are read, longer than a unit lives; widen it if one ever outlasts that.
pass_threads() {
  python3 - "$BY" "$1" "$RHOME" "$HERE" "$HEAD_FULL" "$HEAD_FIX" "$HEAD_FINAL" "$HEAD_DESIGN" <<'PY'
import glob, json, os, re, sys, time
by, wt, home, here, *heads = sys.argv[1:]
sys.path.insert(0, here)
from unit_folders import belongs
head = re.compile(rf"^(?:{'|'.join(map(re.escape, heads))}) Reviewer [1-9] of [1-9], round ([1-9][0-9]*)\.$", re.M)
def claude(path):
    # The first row with a cwd places the session; its first prompt says whether it was a pass.
    here = False
    for raw in open(path, encoding="utf-8", errors="replace"):
        try:
            row = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(row, dict) or row.get("isSidechain") or row.get("isMeta"):
            continue
        if not here and row.get("cwd"):
            if not belongs(row["cwd"], wt):
                return
            here = True
        c = (row.get("message") or {}).get("content")
        text = c if isinstance(c, str) else "\n".join(
            b.get("text") or "" for b in c or [] if isinstance(b, dict) and b.get("type") == "text")
        if here and row.get("type") == "user" and text.strip():
            if m := head.search(text):
                print(os.path.basename(path)[:-6], m.group(1))
            return
pattern = ("projects", "*", "*.jsonl") if by == "claude" else ("sessions", "**", "rollout-*.jsonl")
for path in sorted(glob.glob(os.path.join(home, *pattern), recursive=True)):
    if os.path.getmtime(path) < time.time() - 14 * 86400:
        continue
    if by == "claude":
        claude(path)
        continue
    tid = None
    for raw in open(path, encoding="utf-8", errors="replace"):
        try:
            row = json.loads(raw)
        except ValueError:
            continue
        p = row.get("payload") or {}
        if tid is None:
            if row.get("type") != "session_meta":
                continue
            # Sessions of other worktrees end here, on their first row.
            if not belongs(p.get("cwd"), wt):
                break
            tid = str(p.get("id"))
        elif row.get("type") == "response_item" and p.get("role") == "user":
            if m := next(filter(None, (head.search(c.get("text") or "") for c in p.get("content") or [] if isinstance(c, dict))), None):
                print(tid, m.group(1))
                break
        elif row.get("type") == "event_msg" and p.get("type") in ("task_complete", "turn_aborted"):
            break
PY
}
# stop_strays <worktree> <session ids> -- stops every reviewer process a pass of
# the worktree started and everything under it: a pass's own broker (its socket
# is under a pp-pass.* folder), the companion reading a round's prompt file, a
# Claude reviewer by its session id. Fails if one is still there afterwards.
stop_strays() {
  local found pids="" p i cp
  cp=$(python3 "$HERE/unit_folders.py" copy "$1") || return 1
  alive() { local s; s=$(ps -o stat= -p "$1" 2>/dev/null) && [ -n "$s" ] && [[ $s != Z* ]]; }
  found=$(ps -axo pid=,command= | awk -v wt="$1" -v cp="$cp" -v ids="$2" -v unit="$UNIT" '
    BEGIN { n = split(ids, id, " ") }
    { line = $0 " "; hit = (index(line, "/pp-pass.") && (index(line, " --cwd " wt " ") || index(line, " --cwd " cp " "))) || index(line, " --prompt-file " wt "/.claude/briefs/" unit "-r")
      for (i = 1; i <= n; i++) hit = hit || index(line, " --session-id " id[i] " ")
      if (hit) print $1 }')
  while [ -n "$found" ]; do pids+=" $found"; found=$(for p in $found; do pgrep -P "$p" || true; done); done
  [ -n "$pids" ] || return 0
  kill $pids 2>/dev/null || true
  for i in $(seq 1 40); do
    [ "$i" != 20 ] || kill -9 $pids 2>/dev/null || true
    for p in $pids; do ! alive "$p" || { sleep 0.25; continue 2; }; done
    return 0
  done
  return 1
}
# earlier_passes <worktree> [session ids to leave out] -- the passes the reviewer
# has on record for this worktree: one line "@ <session> <kind> <k> <n> <round>
# <began> <ended> <read> <since> <said>" each, then its finding lines. A pass reads this once, at its
# launch, and hands it to its reviewers; the merge reads it again and compares.
# The round files are the Builder's to edit or remove, so neither reads them.
# A pass cut off before any answer, or still running, is the row "@ <session> cut 0 0 <round> <began> <began> - - cut"
# with no finding lines (#376: a wholly cut-off round would otherwise vanish from the count and from the
# missing-reviewer check). Every reader of the rows skips or holds on kind cut.
# A pass on record that cannot be read in full refuses (exit 2).
# The one rule of which round proves a merge (CUT=refuse, the merge, with the
# round under merge in $ROUND): only the highest round that launched a reviewer
# can, so a session of a later round refuses whatever became of it. A session
# with no finished reply (session_proof's 3) refuses too, unless the pass script
# has it on record as abandoned; that record lets its round be run again and
# never gives an older round its proof back.
# The record is written in one place (CUT=mark, a pass at its launch): the launch
# holds the pass lock, so no pass of the worktree runs, and a reviewer still alive
# is a dead launcher's. It is stopped first, and the launch refuses if it will not stop.
earlier_passes() {
  local tids tid round rc proof line
  tids=$(pass_threads "$1") || die "the reviewer's session files under $RHOME cannot be listed, so the passes of $1 are not known"
  [ "${CUT:-}" != mark ] || stop_strays "$1" "$(cut -d' ' -f1 <<<"$tids" | paste -sd' ' -)" \
    || die "a reviewer of an earlier pass of $1 is still running and could not be stopped, so its pass is not recorded as abandoned and no pass starts beside it. Stop it by hand (ps shows it with --cwd $1), then run this pass again"
  while read -r tid round; do
    [ -n "$tid" ] || continue
    [ "${CUT:-}" != refuse ] || [ "$round" -le "$ROUND" ] \
      || die "round $round of this worktree launched a reviewer ($NAME $tid) and has no round file, so round $ROUND proves nothing: only the last round that launched a reviewer can prove a merge, whatever became of that reviewer. Run round $round again in full"
    [[ " ${2:-} " != *" $tid "* ]] || continue
    rc=0; proof=$(session_proof "$tid" "$1" "" 2>/dev/null) || rc=$?
    if [ "$rc" = 3 ]; then
      case ${CUT:-} in
        mark) { mkdir -p "$RHOME/builder-pass-prompts" && : > "$RHOME/builder-pass-prompts/$tid.abandoned"; } \
          || die "cannot record under $RHOME/builder-pass-prompts that $NAME $tid was abandoned" ;;
        refuse) [ -e "$RHOME/builder-pass-prompts/$tid.abandoned" ] \
          || die "a pass of this worktree ($NAME $tid) has not answered and is not on record as abandoned, so it may still find a blocker. If it is running, wait for it to end. If it will never end, run its round again: the launch stops its reviewer and records it as abandoned" ;;
      esac
      # A round with no answer is still on record, as a cut row (#376); session_proof printed when it began.
      [ -n "$proof" ] && [ "$proof" != - ] \
        || die "the record of an earlier pass of this worktree ($NAME $tid) does not say when it began, so its place among the passes is not known. $UPDATED"
      echo "@ $tid cut 0 0 $round $proof $proof - - cut"
      continue
    fi
    line=$(sed -n 2p <<<"$proof")
    [ "$rc" = 0 ] && [ -n "$line" ] && [[ "$line " != *' - '* ]] \
      || die "the record of an earlier pass of this worktree ($NAME $tid) cannot be read in full, so what it found cannot be handed on or checked. $UPDATED"
    echo "@ $tid $line"
    # A finding line that opens with "@" is escaped, so it never reads as the record of a pass.
    sed 1,2d <<<"$proof" | { grep -E "$FINDING" || true; } | sed 's/^\([[:space:]]*\)@/\1\\@/'
  done <<<"$tids"
}
# open_findings <finding lines of the pass under merge> <earlier_passes text> -- issue 366: what is open at a merge, one
# "Open finding: <class> <line>" each. That is every finding line of the pass under merge, and the P3 lines of every
# earlier round whose every declared reviewer is on record and said GO (a GO round gets no fix round, so its P3s were
# never fixed; a NO-GO round's went to its fix round). Deduped by exact line. A class is the first <file>:<line> the
# line cites, the line dropped; no-file when it cites none.
open_findings() {
  { printf '%s\n' "$1"
    awk -v blk="$BLK" -v low="(^|[^A-Za-z0-9])P[0-$BLK]([^0-9]|\$)" -v high="(^|[^A-Za-z0-9])P[$((BLK + 1))-3]([^0-9]|\$)" '$1 == "@" && $3 == "cut" { cur = ""; next }
      $1 == "@" { r = $6; if (!(r in of)) { of[r] = $5; ok[r] = 1; order[++n] = r } got[r, $4] = 1; if ($11 != "GO") ok[r] = 0; cur = r; next }
      blk < 3 && $0 ~ high && $0 !~ low { p3[cur] = p3[cur] $0 "\n" }
      END { for (i = 1; i <= n; i++) { r = order[i]; for (k = 1; k <= of[r]; k++) if (!got[r, k]) ok[r] = 0; if (ok[r]) printf "%s", p3[r] } }' <<<"$2"; } \
    | awk 'NF && !seen[$0]++ { c = "no-file"; if (match($0, "[-A-Za-z0-9_./]+\\.[A-Za-z0-9]+:[0-9]+")) { c = substr($0, RSTART, RLENGTH); sub(/:[0-9]+$/, "", c) } print "Open finding: " c " " $0 }'
}

if [ "${1:-}" = --verify ]; then
  WT=${2:?worktree} UNIT=${3:?unit} TIP=${4:?tip}
  # A pass still running may yet find a blocker, and its session reads as "found nothing yet" until it ends.
  HOLDER=$(cat "$(git -C "$WT" rev-parse --absolute-git-dir 2>/dev/null)/builder-pass.lock/pid" 2>/dev/null || true)
  ! { [[ $HOLDER =~ ^[0-9]+$ ]] && kill -0 "$HOLDER" 2>/dev/null; } || die "a pass of $UNIT is still running (pid $HOLDER), and what it finds is not in yet. Wait for it to end, then merge"
  LAST=$(round_files "$WT" "$UNIT" | sort -n | tail -1 | cut -d' ' -f2-)
  [ -n "$LAST" ] || die "no Builder round file for $UNIT under $WT/.claude/briefs"
  # The header only, up to its first empty line: below it is the reviewer's own text.
  BY=codex NAME="Codex thread" RHOME=$CODEX_DIR
  TIDS=$(sed -n '/^$/q; s/^Codex thread: \([A-Za-z0-9-]*\)$/\1/p' "$LAST")
  [ -n "$TIDS" ] || { BY=claude NAME="Claude session" RHOME=$CLAUDE_DIR; TIDS=$(sed -n '/^$/q; s/^Claude session: \([A-Za-z0-9-]*\)$/\1/p' "$LAST"); }
  [ -n "$TIDS" ] || die "${LAST##*/} names no Codex thread or Claude session: it was not written by builder-codex-pass.sh"
  # A Builder does not pick its reviewer: codexReviewerAgent does.
  [ "$BY" = "$(pp_pass)" ] || die "${LAST##*/} is a $BY pass, and codexReviewerAgent in /plugin config reviews with $(pp_pass)"
  # No commit subject is exempt: a commit after the review is unreviewed whatever it is called.
  WANT=$(git -C "$WT" rev-parse --verify -q "$TIP^{commit}") || die "no commit $TIP in $WT"
  SEEN="" OF="" WHAT="" RULE="" STEPS=""
  MAIN_OF_WT=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && MAIN_OF_WT=${MAIN_OF_WT%/.git} || die "$WT is not a git worktree"
  ROUND=${LAST##*/}; ROUND=${ROUND#"$UNIT-r"}; ROUND=${ROUND%-reports.md}
  # Issue 366 (O4): a P0 or P1 held two passes past the cap waits for the owner, whatever the pass's kind. Asked first,
  # so the one line orca-wait.sh and main-watch read says so, and not that the pass was design-only or NO-GO.
  ALLP=$(earlier_passes "$WT") || exit 2
  COUNT=$(passes_on_record "$ALLP" "$ROUND") STOP_ID=$(review_stop_id "$ALLP") CAPPED="" NOW_LINES=""
  [ -z "$STOP_ID" ] || die "REVIEW STOP: ${LAST##*/} holds a P0 or P1 two passes past the cap (pass $COUNT on record); decision $STOP_ID; it waits for the owner's answer, no fix round runs"
  for TID in $TIDS; do
    PROOF=$(session_proof "$TID" "$WT" "$WANT") || exit 2
    read -r READ K OF_THIS OF_ROUND BEGAN _ WAS_READ SINCE _ <<<"$(sed -n 2p <<<"$PROOF")"
    # The reviewer's record, never the round file, says what this pass found: the Builder can edit a round file.
    NOW_LINES+=$({ tail -n +3 <<<"$PROOF" | grep -E "$FINDING" || true; })$'\n'
    # Issue 366: a finding at or above the blocking severity holds the merge (session_proof reads a GO beside one as NO-GO), until the cap; a P0 or
    # P1 is never capped. A finding main cleared is handed to the next reviewer as out of scope; it never turns a
    # NO-GO into a merge.
    if [ "${PROOF%%$'\n'*}" != "VERDICT: GO" ]; then
      [ "$(tail -n +3 <<<"$PROOF" | p01_count)" = 0 ] || die "$NAME $TID (${LAST##*/}) ended NO-GO with a P0 or P1: a P0 or P1 is never capped (pass $COUNT on record). Fix it, then run the next pass: builder-codex-pass.sh $UNIT <N> review"
      [ "$READ" = final ] && [ "$COUNT" -ge "$REVIEW_CAP" ] || die "$NAME $TID (${LAST##*/}) ended NO-GO: a $BLOCK_LEVELS holds the merge below the cap (pass $COUNT on record, cap $REVIEW_CAP), and a finding main cleared does not turn a NO-GO into a merge. Fix it, then run the next pass: builder-codex-pass.sh $UNIT <N> review"
      # The cap merges an open P2 for main to file. A NO-GO that names none (only P3s, an untagged level, a refusal
      # line, no finding) is no cap stop: it would merge with nothing to file.
      [ "$(tail -n +3 <<<"$PROOF" | cappable_count)" -gt 0 ] || die "$NAME $TID (${LAST##*/}) ended NO-GO but names no open $CAP_LEVELS, so it is no cap stop (pass $COUNT on record): only an open $CAP_LEVELS is merged at the cap, for main to file. Run the closing pass again: builder-codex-pass.sh $UNIT <N> final"
      CAPPED=1
    fi
    case $READ in
      # session_proof has just bound this pass to the tip, so nothing was committed after it.
      final) NOW="closing pass" RULE="closing GO" ;;
      # session_proof has just bound this GO to the tip, so a closing pass would read the same commit again.
      full) NOW="first pass" RULE="first-pass GO" ;;
      fix) NOW="narrowed pass" RULE="no closing pass"
        [ "$CLOSING" = no ] || die "${LAST##*/} is a narrowed pass: it read only the changes since the pass before it, and a narrowed pass's GO merges nothing. Run the closing pass: builder-codex-pass.sh $UNIT <N> final"
        STEPS+="$TID $WAS_READ $SINCE"$'\n' ;;
      # Host change (owner order 2026-10-25): a commit with no code was read for its design, so nothing was merged on it.
      design) die "${LAST##*/} is a design-only pass (its commit changed only the plan): its GO approves the design and merges nothing. Write the code, then run builder-codex-pass.sh $UNIT $((ROUND + 1)) final" ;;
      *) die "$NAME $TID (${LAST##*/}) is not a pass of builder-codex-pass.sh" ;;
    esac
    # The round file is the Builder's to edit: a thread of another round, GO there, proves nothing about this one.
    [ "$OF_ROUND" = "$ROUND" ] || die "$NAME $TID is a reviewer of round $OF_ROUND, not of ${LAST##*/}"
    [ "${OF:-$OF_THIS}" = "$OF_THIS" ] && [ "${WHAT:-$NOW}" = "$NOW" ] || die "${LAST##*/} names Codex threads of different passes"
    SEEN+="$K"$'\n' OF=$OF_THIS WHAT=$NOW
  done
  # The round file is the Builder's to edit: a reviewer left out of it is a verdict left out.
  [ "$(sort -un <<<"${SEEN%$'\n'}" | paste -sd' ' -)" = "$(seq 1 "$OF" | paste -sd' ' -)" ] \
    || die "${LAST##*/} names $(sort -un <<<"${SEEN%$'\n'}" | wc -l | tr -d ' ') of the $OF reviewers of that pass; every reviewer's thread must be in it and GO"
  # One reviewer is a first pass only where the size rule allowed it, counted here on the commit the reviewer says it read:
  # the round file's own line is the Builder's to edit.
  [ "$WHAT" != "first pass" ] || [ "$OF" -gt 1 ] || one_reviewer_allowed "$WT" "$WAS_READ" "${LAST##*/}"
  # The pass whose GO merges, the closing one or a first pass on the unchanged
  # tip, is the last word on the review the passes before it made. Which
  # those were is the reviewer's record, read now: every other pass of
  # this worktree on record must be one it listed at its launch, thread and
  # end time, and must have ended before it began. A pass that ran beside or
  # after it is on record and not listed; one listed and gone from the record
  # is not on record. Either leaves the GO unproven.
  [ "$BEGAN" != - ] || die "the reviewer's record of the $WHAT (${LAST##*/}) does not say when it began, so the passes before it cannot be told from the ones after"
  PASSES=$(CUT=refuse earlier_passes "$WT" "$(paste -sd' ' - <<<"$TIDS")") || exit 2
  # A `cut` row (an abandoned launch) has no end and no findings, so it is in neither list; the chain below judges it.
  ON_RECORD=$(awk '$1 == "@" && $3 != "cut" { print "Earlier pass " $2 " ended " $8 }' <<<"$PASSES" | sort)
  while read -r mark EARLIER_TID EARLIER_KIND _ _ _ _ ENDED _; do
    [ "$mark" != @ ] || [ "$EARLIER_KIND" = cut ] || [[ $ENDED < $BEGAN ]] \
      || die "the $WHAT (${LAST##*/}) was not built on the passes the reviewer has on record for this worktree: $NAME $EARLIER_TID ended $ENDED, not before the $WHAT began ($BEGAN). Run the closing pass again once every other pass has ended"
  done <<<"$PASSES"
  # Issue 366 (O2): the closing pass is handed no earlier finding, so only the passes before it are checked above.
  [ "$WHAT" = "closing pass" ] && [ "$FRESHC" = yes ] || for TID in $TIDS; do
    # Only the block of earlier passes counts: a finding's words in the diff below it were never handed to the reviewer as a finding.
    BLOCK=$(awk -v head="$EARLIER_HEAD" -v end="$EARLIER_END" '$0 == end { exit } on { print } $0 == head { on = 1 }' "$RHOME/builder-pass-prompts/$TID")
    [ "$(grep -E '^Earlier pass [A-Za-z0-9-]+ ended [^ ]+$' <<<"$BLOCK" | sort)" = "$ON_RECORD" ] \
      || die "the $WHAT (${LAST##*/}, $NAME $TID) was not built on the passes the reviewer has on record for this worktree: the passes it listed at its launch and the ones on record now differ. A pass that ran beside or after it, or one whose record is gone, leaves its GO unproven. Run the closing pass again once every other pass has ended"
    EARLIER_TID=""
    while IFS= read -r finding; do
      if [[ $finding == '@ '* ]]; then EARLIER_TID=${finding#@ }; EARLIER_TID=${EARLIER_TID%% *}; continue; fi
      [ -z "$finding" ] || grep -qxF -- "$finding" <<<"$BLOCK" \
        || die "the reviewer $TID of the $WHAT was not handed this finding of an earlier pass ($NAME $EARLIER_TID): $finding. Run the closing pass again"
    done <<<"$PASSES"
  done
  # A closing pass closes a review the first pass opened, so one of the passes
  # before it must be that: every reviewer of one round, each a first-pass
  # thread. Its verdict is not asked for; it is usually NO-GO. With no such pass
  # of several reviewers, a first pass of one reviewer is it, where the size
  # rule allowed one on the commit it read.
  [ "$WHAT" = "first pass" ] || awk '$1 == "@" && $3 == "full" && $5 > 1 && $4 >= 1 && $4 <= $5 && !seen[$6, $5, $4]++ { got[$6 " " $5]++ }
       END { for (pass in got) { split(pass, of, " "); if (got[pass] == of[2]) found = 1 } exit !found }' <<<"$PASSES" \
    || {
      SOLO=$(awk '$1 == "@" && $3 == "full" && $5 == 1 { print $2, $9 }' <<<"$PASSES")
      [ -n "$SOLO" ] || die "no pass before ${LAST##*/} is the first pass of $UNIT: the closing pass's GO merges only on top of it. Run: builder-codex-pass.sh $UNIT <N> adversarial, then the closing pass again"
      while read -r SOLO_TID SOLO_READ; do one_reviewer_allowed "$WT" "$SOLO_READ" "$NAME $SOLO_TID, before ${LAST##*/},"; done <<<"$SOLO"
    }
  # With the full suite on (issue 243), a closing pass merges only on a green run of the commit it read, as its own
  # recorded prompt states it on the line after its head line: the round file is the Builder's to edit.
  # The line is printed as "Suite proof:", the one copy of it the merge may reuse (issue 307).
  SUITE_PROOF=""
  if [ "$WHAT" = "closing pass" ] && [ "$(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal)" = true ]; then
    for TID in $TIDS; do
      SUITE_PROOF=$(awk 'p { print; exit } / Reviewer [0-9]+ of [0-9]+, round [0-9]+\.$/ { p = 1 }' "$RHOME/builder-pass-prompts/$TID" | grep -E "^Suite: $WAS_READ pass ") \
        || die "the closing pass (${LAST##*/}, $NAME $TID) has no green full-suite line for the commit it read ($WAS_READ), and fullSuiteBeforeFinal is on (from $(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal source)). Run the closing pass again: builder-codex-pass.sh $UNIT <N> final"
    done
  fi
  # Issue 366: what is open is printed before the proof line (main-watch reads the last line), and names the rule.
  OPEN_LINES=$(open_findings "$NOW_LINES" "$PASSES")
  if [ "$RULE" = "closing GO" ]; then
    if [ -n "$CAPPED" ]; then RULE="cap stop"; elif [ -n "$OPEN_LINES" ]; then RULE="threshold stop"; fi
  fi
  [ -z "$OPEN_LINES" ] || printf '%s\n' "$OPEN_LINES"
  if [ "$RULE" = "no closing pass" ]; then
    # The owner chose no closing pass at setup: the last first pass anchors the chain, and
    # narrowed passes read every commit after it up to the tip, the one under merge ending GO.
    # It was handed every earlier finding (checked above), so its GO is the last word on them.
    # All of it is read from the reviewer's records: the commit each pass read and where each narrowed range began.
    AGAIN="Fix it, then run another narrowed pass: builder-codex-pass.sh $UNIT <N> review"
    read -r C_ENDED C_TID COVERED _ <<<"$(awk '$1 == "@" && $3 == "full" { print $8, $2, $9 }' <<<"$PASSES" | sort | tail -1)"
    # Each pass after the first one, oldest first, then the pass under merge.
    # A cut-off pass is listed unless its round was run again and answered (the rows of that rerun judge the round).
    AFTER=$(awk -v c="$C_ENDED" '$1 == "@" && $8 > c { n++; line[n] = $8 " " $2 " " $3 " " $9 " " $10 " " $11; rnd[n] = $6; kind[n] = $3 }
      $1 == "@" && $3 != "cut" { real[$6] = 1 }
      END { for (i = 1; i <= n; i++) if (kind[i] != "cut" || !(rnd[i] in real)) print line[i] }' <<<"$PASSES" | sort)
    while read -r _ TID READ WAS_READ SINCE SAID; do
      [ -n "$TID" ] || continue
      [ "$READ" != cut ] || die "the pass of $NAME $TID, after the first pass $C_TID, was cut off before it answered: its verdict is unknown, so it holds the merge. $AGAIN"
      [ "$READ" = fix ] || die "a whole-branch pass ($NAME $TID) ran after the first pass $C_TID and is not the pass under merge. $AGAIN"
      [ "$SAID" != none ] || die "the reviewer's record of the narrowed pass $TID holds no verdict, so what it found cannot be trusted as all of it. $AGAIN"
      [ "$SAID" = GO ] || awk -v t="$TID" '$1 == "@" { on = ($2 == t); next } on { found = 1 } END { exit !found }' <<<"$PASSES" \
        || die "the narrowed pass $TID ended NO-GO and names no finding with a severity, so what it found was not handed on. $AGAIN"
      STEPS="$TID $WAS_READ $SINCE"$'\n'$STEPS
    done <<<"$(sort -r <<<"$AFTER")"
    while read -r TID WAS_READ SINCE; do
      [ -n "$TID" ] || continue
      # A narrowed range may start at or before the last commit read, never after it, and must end at or after it.
      git -C "$WT" merge-base --is-ancestor "$SINCE" "$COVERED" 2>/dev/null && git -C "$WT" merge-base --is-ancestor "$COVERED" "$WAS_READ" 2>/dev/null \
        || die "no pass read the commits between $COVERED and where the narrowed pass $TID began ($SINCE): every commit after the first pass $C_TID must be read. $AGAIN"
      COVERED=$WAS_READ
    done <<<"$STEPS"
    echo "Builder proof: ${LAST##*/}: no closing pass (chosen at setup); narrowed passes read every commit after the first pass ($NAME $C_TID), and the last ($NAME(s) $(paste -sd' ' - <<<"$TIDS")) ended GO in $WT on $WANT or the commit it is a clean rebase of; rule: no closing pass"
    exit 0
  fi
  ENDED_AS=GO; [ -z "$CAPPED" ] || ENDED_AS="NO-GO with no P0 or P1 at pass $COUNT on record"
  echo "Builder proof: ${LAST##*/}: $NAME(s) $(paste -sd' ' - <<<"$TIDS") ended $ENDED_AS in $WT on $WANT or the commit it is a clean rebase of; rule: $RULE"
  [ -z "$SUITE_PROOF" ] || echo "Suite proof: $SUITE_PROOF"
  exit 0
fi

pass_waits
if [ "$BY" = claude ]; then
  TEMPLATE="the Claude reviewer's template in ${BASH_SOURCE[0]##*/}"
else
  TEMPLATE=${COMPANION%/scripts/*}/prompts/adversarial-review.md
  [ -r "$TEMPLATE" ] || die "the Codex plugin has no prompt file $TEMPLATE; the passes have no other prompt"
fi
SLOT='{{REVIEW_INPUT}}'
# plugin_prompt <focus> -- the template with everything of this script's in it
# but the review input, whose slot is left for the pass to fill last: a diff of
# a file that spells a placeholder must not be read as the template's own.
plugin_prompt() {
  local t own
  if [ "$BY" = claude ]; then t=$CLAUDE_TEMPLATE; else t=$(<"$TEMPLATE"); fi
  [[ $t == *"$OPEN"*"$CLOSE"* ]] || die "$TEMPLATE has no $OPEN ... $CLOSE block; the verdict format has nowhere else to go"
  t=${t%%"$OPEN"*}$OPEN$'\n'$FORMAT$'\n'$CLOSE${t#*"$CLOSE"}
  [[ $t == *"$ONE"* ]] || die "$TEMPLATE no longer says \"$ONE\"; the every-finding line has nothing to replace"
  t=${t//"$ONE"/"$MANY"}
  t=${t//'{{TARGET_LABEL}}'/"$LABEL"}; t=${t//'{{USER_FOCUS}}'/"$1 $LENS"}
  t=${t//'{{REVIEW_COLLECTION_GUIDANCE}}'/"$GUIDANCE"}
  [[ ${t//"$SLOT"/} =~ \{\{[A-Z_]+\}\} ]] && die "$TEMPLATE has a placeholder this script does not fill: ${BASH_REMATCH[0]}"
  # session_proof looks for each of these: a template that drops one would fail every pass after Codex ran.
  for own in "$LABEL" "$1" "$LENS" "$GUIDANCE" "$SLOT"; do
    [[ $t == *"$own"* ]] || die "$TEMPLATE has no place for this script's text: $own"
  done
  printf '%s' "$t"
}
plugin_prompt "$FOCUS_REVIEW" >/dev/null

# Issue 316: the pass reads GitHub as its reviewer does and refuses, before any reviewer starts, when it cannot. The
# Claude reviewer's shell is unsandboxed, so its own read is checked. The Codex companion pins a read-only sandbox with
# no network (codex-companion.mjs "sandbox: read-only"), which this pass cannot change: its GitHub reads are made here,
# on the host, and handed in with the prompt (gh_hand_in), so the host read is what is checked.
review_gh_check() { # <dir>
  local why
  if [ "$BY" = claude ]; then why=$(pp_gh_read codex-reviewer "$1" 2>&1) || die "the Claude reviewer cannot read GitHub: $why"
  else why=$(pp_gh_read --host codex-reviewer "$1" 2>&1) || die "the Codex reviewer's sandbox has no network, so its GitHub reads are made on the host, and the host cannot read GitHub: $why"; fi
}
# The Closes: issues and the brief's work items (brief-issues.sh, the one reader), every issue or pull request their
# bodies and comments link (one level), and the unit branch's pull request state, read on the host now, whole, with the
# reviewer's shellEnv as its preflight read was. --json, not --comments: off a terminal that prints the comments and no
# body, and --json also reads a pull request's number. A failed read refuses the pass; no pull request is a state, not
# a failure.
gh_hand_in() {
  local closes html="" seen="" n r m repo out br e f=title,state,labels,body,comments a='Accept: application/vnd.github.full+json'
  mapfile -t e < <(jq -r '.shellEnv // {} | to_entries[] | "\(.key)=\(.value)"' <<<"$SOL")
  closes=$({ grep -E '^Closes:' "$WT/.claude/briefs/$UNIT.md" 2>/dev/null | grep -oE '#[0-9]+' | tr -d '#'
    bash "$HERE/brief-issues.sh" "$WT/.claude/briefs/$UNIT.md" "$MAIN_OF_WT/.claude/briefs/$UNIT-main-rulings.md" \
      | jq -r '.[] | numbers'; } | awk '!s[$0]++')
  for n in $closes; do
    out=$(cd "$WT" && env "${e[@]}" gh issue view "$n" --json "$f" 2>&1) || die "GitHub read failed on the host: gh issue view $n --json $f: $(grep -m1 . <<<"$out")"
    printf 'GitHub issue #%s with its comments, read on the host at launch:\n%s\n\n' "$n" "$out"
    # What is a link is GitHub's call, not a Markdown parse here: the links are the hrefs of the HTML GitHub renders
    # for the body and every page of comments.
    out=$(cd "$WT" && env "${e[@]}" gh api -H "$a" "repos/{owner}/{repo}/issues/$n" 2>&1) && html+=$(jq -r .body_html <<<"$out")$'\n' \
      && seen+=$(jq -r '"href=\"\(.html_url)\""' <<<"$out")$'\n' \
      && out=$(cd "$WT" && env "${e[@]}" gh api --paginate -H "$a" "repos/{owner}/{repo}/issues/$n/comments" 2>&1) && html+=$(jq -r '.[].body_html' <<<"$out")$'\n' \
      || die "GitHub read failed on the host: gh api repos/{owner}/{repo}/issues/$n: $(grep -m1 . <<<"$out")"
  done
  # A link is an href to github.com/<owner>/<repo>/(issues|pull)/<n>, ended by the path's end, /, ? or #; scheme, host
  # and owner/repo are case-insensitive. The Closes: issues' own URLs come first, so a link to one is not read again.
  for r in $(grep -oiE 'href="https?://github\.com/[^/"]+/[^/"]+/(issues|pull)/[0-9]+[/?#"]' <<<"$seen$html" | awk -F/ '{r = tolower($4 "/" $5) "#" ($7 + 0)} !s[r]++ && NR > '"$(grep -c . <<<"$seen")"' {print r}'); do
    m=${r##*#} repo=${r%"#$m"}
    out=$(cd "$WT" && env "${e[@]}" gh issue view "$m" -R "$repo" --json "$f" 2>&1) || die "GitHub read failed on the host: gh issue view $r --json $f: $(grep -m1 . <<<"$out")"
    printf 'GitHub issue or pull request %s, linked from the issue above, read on the host at launch:\n%s\n\n' "$r" "$out"
  done
  br=$(git -C "$WT" branch --show-current)
  out=$(cd "$WT" && env "${e[@]}" gh pr view "$br" --json state,labels,statusCheckRollup 2>&1) \
    || { grep -q 'no pull requests found' <<<"$out" && out="no pull request for branch $br" || die "GitHub read failed on the host: gh pr view $br: $(grep -m1 . <<<"$out")"; }
  printf 'Pull request of the unit branch %s, read on the host at launch:\n%s\n' "$br" "$out"
}

# The reviewer's seat as it resolves: its /plugin config keys over routing's row, on the agent it runs.
# Its warnings stay on stderr: one beside a resolved Codex id is not part of the id.
WHY=$(mktemp) || die "cannot make a temp file"
SOL=$(pp_route_json codex-reviewer 2>"$WHY") || { MODEL=$(<"$WHY"); rm -f "$WHY"; die "codex-reviewer: ${MODEL#REFUSED: }"; }
cat "$WHY" >&2; rm -f "$WHY"
[ "$(jq -r .agent <<<"$SOL")" = "$BY" ] || die "this pass runs on $BY, but codexReviewerAgent in /plugin config puts the reviewer on $(jq -r .agent <<<"$SOL")"
MODEL=$(jq -r .model <<<"$SOL")
if [ "$BY" = claude ]; then
  mapfile -t ARGV < <(jq -r '.argv[]?' <<<"$SOL")
  [ "${#ARGV[@]}" -gt 0 ] || die "codex-reviewer's claude overlay in $(pp_routing) is not a usable headless role"
else
  EFFORT=$(jq -r '.effort // empty' <<<"$SOL")
  [ -n "$EFFORT" ] || die "no roles.codex-reviewer effort in $(pp_routing); the passes never run on the Codex home's own effort"
  # Fast mode is the owner's codexReviewerFast (no answer is off), never routing.json's.
  if pp_codex_fast; then
    pp_codex_fast_home || die "codexReviewerFast is on but $CODEX_DIR/config.toml has no service_tier = \"fast\"; the Codex passes would run on the slow tier. Add that line, or turn it off: codexReviewerFast=false in /plugin config"
  fi
  if [ "${1:-}" = --preflight ]; then
    # The companion runs the Codex CLI under the owner's sign-in; the plugin alone is not enough.
    command -v codex >/dev/null || die "no codex on PATH; the Codex plugin runs the Codex CLI"
    codex login status >/dev/null 2>&1 || die "the Codex CLI is not signed in; run: codex login"
  fi
fi
if [ "${1:-}" = --preflight ]; then review_gh_check "$PP_MAIN"; printf '%s\t%s\n' "$MODEL" "$COMPANION"; exit 0; fi

# --ack-rulings <unit> runs no pass: the round and kind below are only stand-ins for it.
CHECK=0; [ "${1:-}" != --check ] || { CHECK=1; shift; }
ACK=0; [ "${1:-}" != --ack-rulings ] || { ACK=1; set -- "${2:-}" 1 review; }
UNIT=${1:?usage: builder-codex-pass.sh [--check] <unit> <N> adversarial|review|final}; N=${2:?round number}; KIND=${3:?adversarial, review or final}
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "bad unit name: $UNIT"
[[ $N =~ ^[1-9][0-9]*$ ]] || die "bad round number: $N"
# The owner's answer (2026-10-25): a pass with no rg refuses at once, so no reviewer's class search is skipped unseen.
[ "$ACK" = 1 ] || command -v rg >/dev/null || die "no rg (ripgrep) on PATH: after a NO-GO the pass runs each reviewer's Class search line with it. Install ripgrep (brew install ripgrep, or sudo apt-get install -y ripgrep), then run the pass again"
# Each reviewer leads with its own angle and carries the whole checklist: the rule gives every reviewer the same full scope.
case $KIND in adversarial) FOCI=(); for a in "${ANGLES[@]}"; do FOCI+=("$DATA_DESIGN $a Lead with that angle, and cover all three as fully: ${ANGLES[*]}"); done ;; review|final) FOCI=("$FOCUS_REVIEW") ;; *) die "pass must be adversarial, review or final, not $KIND" ;; esac
WT=$PP_WORKSPACES/$UNIT
[ "$(jq -r '.env.COMMANDECK_BUILDER // empty' "$WT/.claude/settings.local.json" 2>/dev/null)" = 1 ] || die "$WT is not a Builder worktree"
[ "$ACK" = 1 ] || review_gh_check "$WT"  # an acknowledgement reads no GitHub
# Main's rulings for the unit: a Builder once ran twelve passes without
# reading three of them. Main writes the file in its own checkout; a copy in
# the worktree counts too. No pass starts on rulings the Builder has not
# acknowledged, and an acknowledgement holds for that text only.
# Which checkout is main's is read from the worktree's own git record, not
# from COMMANDECK_MAIN: a Builder that named its own checkout there would
# hide main's rulings and state its own limits.
MAIN_OF_WT=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && MAIN_OF_WT=${MAIN_OF_WT%/.git} \
  || die "$WT is not a git worktree"
# The owner's limit on the rounds of this unit (review-cap.sh), read from main's checkout only. A unit with none has
# no limit on its round number; the review pass cap (reviewPassCap) is a different limit, on the passes on record.
CAP=$MAIN_OF_WT/.claude/briefs/$UNIT-review-cap.md MAX_ROUNDS=
if [ -e "$CAP" ]; then
  MAX_ROUNDS=$(tr -d '[:space:]' < "$CAP") && [[ $MAX_ROUNDS =~ ^[1-9][0-9]*$ ]] || die "$CAP must hold a whole number of rounds; set it with review-cap.sh $UNIT <rounds>"
fi
[ -z "$MAX_ROUNDS" ] || [ "$N" -le "$MAX_ROUNDS" ] \
  || die "round $N is over the $MAX_ROUNDS rounds this project allows (review-cap.sh for $UNIT; the round is the N a pass is given, so a pass that failed still used its number). Run no more passes: report to main what is still open"
RULINGS=()
for f in "$MAIN_OF_WT/.claude/briefs/$UNIT-main-rulings.md" "$WT/.claude/briefs/$UNIT-main-rulings.md"; do
  [ ! -f "$f" ] || RULINGS+=("$f")
done
if [ "${#RULINGS[@]}" -gt 0 ]; then
  ACKED=$(git -C "$WT" rev-parse --absolute-git-dir)/builder-rulings-ack || die "$WT is not a git worktree"
  SUM=$(cat "${RULINGS[@]}" | cksum)
  if [ "$ACK" = 1 ]; then echo "$SUM" > "$ACKED"; echo "acknowledged: ${RULINGS[*]}"; exit 0; fi
  [ "$SUM" = "$(cat "$ACKED" 2>/dev/null)" ] || die "main's rulings for $UNIT have changed since you last acknowledged them: ${RULINGS[*]}
Read the file and do what it says, then acknowledge it and run the pass again: builder-codex-pass.sh --ack-rulings $UNIT"
fi
[ "$ACK" = 0 ] || { echo "no rulings file for $UNIT: nothing to acknowledge"; exit 0; }
OUT=$WT/.claude/briefs/$UNIT-r$N-reports.md
[ -e "$OUT" ] && die "${OUT##*/} exists; a round is never rewritten, use the next number"
# Main's one way to stop or steer a Builder that waits on a pass: the
# pane guard reads the pass as the Builder's own turn, so no message gets in.
STOP=$WT/.claude/briefs/$UNIT-stop
[ -e "$STOP" ] && die "main stopped this Builder with ${STOP##*/}. Run no further pass; do what it says, then end your turn:
$(cat "$STOP")"
# One pass of a worktree at a time: a pass that starts while another
# runs is built without that one's findings.
LOCK=$(git -C "$WT" rev-parse --absolute-git-dir)/builder-pass.lock || die "$WT is not a git worktree"
# The lock is in the git folder, which pp_rm_rf refuses; it holds one pid file, and rmdir cannot remove more.
# Every read or change of the lock runs under flock on a guard file beside it, so the lock never exists without its pid
# (a pass reading one in between took it over as dead), two takeovers cannot interleave, and a pass releases only its own.
guarded() { ( flock -w 30 9 || exit 98; "$@" ) 9>>"$LOCK.guard"; }
take_lock() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    local holder; holder=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [[ $holder =~ ^[0-9]+$ ]] && kill -0 "$holder" 2>/dev/null; then echo "$holder"; return 1; fi
    rm -f "$LOCK/pid" "$LOCK/index"; rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" || return 2
  fi
  echo $$ > "$LOCK/pid"
}
release_lock() {
  [ "$(cat "$LOCK/pid" 2>/dev/null || true)" = "$$" ] || return 0
  rm -f "$LOCK/pid" "$LOCK/index"; rmdir "$LOCK" 2>/dev/null || true
}
unlock() { guarded release_lock; }
TAKE_RC=0; HOLDER=$(guarded take_lock) || TAKE_RC=$?
case $TAKE_RC in
  0) ;;
  1) die "another pass of $UNIT is still running (pid $HOLDER). One pass at a time: wait for it to end, then run this one" ;;
  *) die "cannot take the pass lock $LOCK" ;;
esac
trap unlock EXIT
PASS_T0=$SECONDS
# The passes before this one. The last round file's reviewed commit bounds a
# narrowed pass. What they found goes to this pass's reviewers, each finding
# once, from the reviewer's records and not from the round files.
PREV=$(round_files "$WT" "$UNIT" | awk -v n="$N" '$1 < n' | sort -n | tail -1 | cut -d' ' -f2-)
PASSES=$(CUT=mark earlier_passes "$WT") || exit 2
EARLIER=$(awk '$1 == "@" && $3 == "cut" { next } $1 == "@" { print "Earlier pass " $2 " ended " $8; next } !seen[$0]++' <<<"$PASSES")
[ "$KIND" = adversarial ] || [ -n "$PREV" ] || die "no earlier pass for $UNIT: a narrowed pass reviews the changes since the last one, and the closing pass closes the review the first one opened. Start with: builder-codex-pass.sh $UNIT $N adversarial"
# Issue 366 (O4): no pass of any kind launches, and nothing is committed, while the latest pass on record holds a P0 or
# P1 two passes past the cap and the owner has not answered its decision in main's ledger. Each stop has its own id,
# so an answer to one does not cover the next. A ledger that cannot be read refuses: no answer is never read as one.
# The answer is the row of that id, or the row the printed route leaves: orca-wait.sh records ask-main.sh's question
# as <unit>-msg_<id> with its subject, "<stop id>: ...", first, and answer-worker.sh answers that row.
# A cut row of this very round is the abandoned launch being run again: the rerun's own rows judge the round (#376).
GATE_ROWS=$(awk -v n="$N" '!($1 == "@" && $3 == "cut" && $6 == n)' <<<"$PASSES")
STOP_ID=$(review_stop_id "$GATE_ROWS")
if [ -n "$STOP_ID" ]; then
  LEDGER=$(COMMANDECK_MAIN=$MAIN_OF_WT bash "$HERE/decision.sh" list 2>&1) \
    || die "REVIEW STOP: the latest pass of $UNIT holds a P0 or P1 two passes past the cap (decision $STOP_ID), and the owner's decisions ledger cannot be read ($(tail -n 1 <<<"$LEDGER")), so no answer to it can be found. No commit was made"
  jq -e --arg id "$STOP_ID" --arg s "$UNIT asks" \
    'any(.[]; .answeredAt != null and (.id == $id or (.source == $s and (.question | startswith($id + ":")))))' <<<"$LEDGER" >/dev/null \
    || die "REVIEW STOP: the latest pass of $UNIT holds a P0 or P1 two passes past the cap; decision $STOP_ID waits for the owner's answer, and no pass runs until that row is ANSWERED. Send main one question if you have not: bash $HERE/ask-main.sh \"$STOP_ID: <the finding's class>\" \"<the redesign you propose>\". No commit was made"
fi
# Issue 377: past the cap with no P0 or P1 open, nothing is left for a pass to review. cap_gate_reason <rows> <plan-only
# 0|1> prints `code` when the latest round is a closing pass that is a cap stop by the pass's own rule (NO-GO, no P0 or
# P1, a finding the cap merges), `plan` when the change to review is plan-only, and nothing otherwise: below the cap, a
# P0 or P1 still open (a round with a reviewer missing, or a design-only one, holds the round before it, as
# review_stop_id's walk does), or a latest round that is a closing GO (commits after it still get their narrowed pass).
# A row is `@ tid kind reviewer of round began end ... said`; the lines after it are that round's findings. A `cut` row
# (a launch with no answer) holds its round only while no reviewer of it has answered: a round run again is judged by
# its rerun's rows, in either order, as review_stop_id reads it.
cap_gate_reason() {
  awk -v cap="$REVIEW_CAP" -v blk="$BLK" -v planonly="$2" '
    function note(r) { if (!(r in seen)) { seen[r] = 1; n++ } if ($8 > end[r]) end[r] = $8 }
    $1 == "@" && $3 == "cut" { cur = $6; note(cur); cut[cur] = 1; next }
    $1 == "@" { cur = $6; note(cur); real[cur] = 1; kind[cur] = $3; if ($11 == "none") mute[cur] = 1; if ($11 != "GO") nogo[cur] = 1
      if (!((cur, $4) in got)) { got[cur, $4] = 1; cnt[cur]++ } want[cur] = $5; next }
    cur == "" { next }
    /(^|[^A-Za-z0-9])P[01]([^0-9]|$)/ { hold[cur] = 1 }
    match($0, /^[[:space:]]*(- )?\[P[0-9]\]/) { d = substr($0, RSTART + RLENGTH - 2, 1) + 0; if (d >= 2 && d <= blk) cap_find[cur] = 1 }
    END {
      if (n < cap) exit
      for (r in seen) if (l == "" || end[r] > end[l]) l = r
      if (kind[l] == "final" && !nogo[l] && !mute[l]) exit
      for (r = l; r != ""; r = p) {
        walked[r] = 1
        if (hold[r] || (cut[r] && !real[r]) || mute[r] || cnt[r] < want[r]) exit
        if (kind[r] != "design") break
        p = ""
        for (q in seen) if (!(q in walked) && end[q] <= end[r] && (p == "" || end[q] > end[p])) p = q
      }
      if (kind[l] == "final" && nogo[l] && cap_find[l]) print "code"; else if (planonly == 1) print "plan"
    }' <<<"$1"
}
CHANGED=$(git -C "$WT" status --porcelain --untracked-files=all | sed -E 's/^.{3}//; s/.* -> //') || die "could not list the uncommitted changes in $WT"
PLANONLY=0
{ [ -z "$CHANGED" ] || grep -qvE '^"?\.claude/(plans|briefs|metrics)/' <<<"$CHANGED"; } || PLANONLY=1
CAP_WHY=$(cap_gate_reason "$GATE_ROWS" "$PLANONLY")
case $CAP_WHY in
  code) die "this would be pass $(passes_on_record "$GATE_ROWS" "$N"), past the cap of $REVIEW_CAP, and no P0 or P1 is open: the latest pass was a closing pass that ended NO-GO with only a finding the cap merges, so the review loop has stopped. File the open findings and run merge-unit-local.sh $UNIT --filed '<class>=#<n>'. No pass starts, nothing was committed" ;;
  plan) die "this would be pass $(passes_on_record "$GATE_ROWS" "$N"), past the cap of $REVIEW_CAP, and no P0 or P1 is open: the change to review is plan-only, so there is no code for a pass to read. Write the code first, or file the open findings and run merge-unit-local.sh $UNIT --filed '<class>=#<n>'. No pass starts, nothing was committed" ;;
esac
# Main adds scope in a fix round by changing the brief or its rulings. A narrowed
# pass would read only the fix and leave the new part unread until the closing
# pass, so the first pass after such a change reads the whole branch as a closing
# pass does. What they held at the last pass is kept in the worktree's git directory;
# with no record of it after an earlier pass, a change cannot be ruled out, so the pass reads the whole branch.
# shortcut: the record is a file the Builder can write, so a Builder that rewrites it is not guarded against (main's checkout is the trust boundary).
SCOPE_REC=$(git -C "$WT" rev-parse --absolute-git-dir)/builder-pass-scope
SCOPE=$(cat ${RULINGS[@]+"${RULINGS[@]}"} "$MAIN_OF_WT/.claude/briefs/$UNIT-builder-brief.md" "$WT/.claude/briefs/$UNIT.md" 2>/dev/null | cksum) || true
if [ "$KIND" = review ] && { [ ! -e "$SCOPE_REC" ] || [ "$SCOPE" != "$(cat "$SCOPE_REC")" ]; }; then
  KIND=final
  echo "The brief or main's rulings for $UNIT changed since the last pass, or no record of them was kept: this pass reads the whole branch, as the closing pass does (Pass: final)."
fi
# Issue 341 (F4): a class that came back is redesigned, and the pass after that fix reads the whole branch: a narrowed
# pass would read only the redesign and leave the rest of the branch on the old model.
if [ "$KIND" = review ] && grep -qF 'Fix the design for the whole class (one fence or stamp)' "$WT/.claude/briefs/$UNIT-fix-r$((N - 1)).md" 2>/dev/null; then
  KIND=final
  echo "The fix round before this pass redesigned a class that came back: this pass reads the whole branch, as the closing pass does (Pass: final)."
fi
# Issues 260 and 266: a narrowed GO after a closing pass merges nothing, and the final after it read the same tip
# again. A finding normal use would hit blocks the merge, so after any closing pass the review is the closing pass.
if [ "$KIND" = review ]; then
  read -r C_TID C_SAID <<<"$(awk '$1 == "@" && $3 == "final" { print $8, $2, $11 }' <<<"$PASSES" | sort | tail -1 | cut -d' ' -f2-)"
  if [ -n "${C_TID:-}" ]; then
    if [ "$C_SAID" = GO ]; then WHY="commits came after the closing GO of $C_TID"; else WHY="the closing pass $C_TID ended NO-GO"; fi
    KIND=final; echo "final in place of review: $WHY; this is the closing pass, its GO merges and no separate final follows"
  fi
fi
# Issue 366: from the cap only a closing pass can end the loop, so a narrowed pass runs as one.
COUNT=$(passes_on_record "$PASSES" "$N")
if [ "$KIND" = review ] && [ "$COUNT" -ge "$REVIEW_CAP" ]; then
  KIND=final; echo "final in place of review: this is pass $COUNT on record, at or past the cap of $REVIEW_CAP, where only the closing pass ends the loop"
fi
# Issue 362 (host issue 3168): a fix that mends the named site while the same pattern sits at other call sites costs a
# round per site. After a NO-GO the next pass needs the Builder's search for the pattern's other sites, in the evidence
# file under "## Sites checked (pass <M>)": a Search: line, then a line per site found, fixed and how, or not affected and why.
EV=$WT/.claude/briefs/$UNIT-evidence.md
plan_rel() { grep -ohE '\.claude/plans/[A-Za-z0-9._-]+\.md' "$WT/.claude/briefs/$UNIT.md" 2>/dev/null | head -1 || true; }
plan_file() { local p; p=$(plan_rel); [ -z "$p" ] || [ ! -f "$WT/$p" ] || echo "$WT/$p"; }
# plan_section <heading> -- issue 359: the lines under the plan's heading (matched without case), none for a plan without it.
plan_section() {
  local PF; PF=$(plan_file)
  [ -z "$PF" ] || awk -v h="$(tr '[:upper:]' '[:lower:]' <<<"$1")" 'on && /^#/ { on = 0 } on && NF { print } tolower($0) ~ ("^#+[[:space:]]+" h) { on = 1 }' "$PF"
}
# plan_only <commit> -- true when the commit changes nothing outside the plan, brief and metrics folders: no code (host change, owner order 2026-10-25).
plan_only() {
  local f
  while IFS= read -r f; do
    case $f in .claude/plans/*|.claude/briefs/*|.claude/metrics/*) ;; *) return 1 ;; esac
  done < <(git -C "$WT" show --name-only --format= "$1")
  return 0
}
# evidence_section <heading regex> -- the lines under the evidence file's heading of that name, at any level.
evidence_section() {
  awk -v h="$1" '/^#+[[:space:]]/ { on = ($0 ~ ("^#+[[:space:]]+" h "[[:space:]]*$")); next } on' "$EV" 2>/dev/null || true
}
# new_code_checked <round> <why owed> -- sets NEWCODE from "## New code checked (pass <round>)", or refuses the pass.
new_code_checked() {
  NEWCODE=$(evidence_section "New code checked \\\\(pass $1\\\\)")
  grep -qE '^- ([^ :]+:[0-9]+ (meets .+|no plan rule, .+)|none, .+)' <<<"$NEWCODE" \
    || die "$2, and ${EV#"$WT/"} has no usable '## New code checked (pass $1)' section. Under that heading check every read, write or check you added or changed since that pass against the plan's Data design, What can go wrong and the failure table, one line each: '- <path>:<line> meets <the plan line it follows>', or '- <path>:<line> no plan rule, <why it is safe>'; when you added none, '- none, <why>'. Then run the pass again."
}
# fix_groups <round file> -- the pass's findings in groups that share no file, as "- Group <i> (<files>):" then one
# "  - <finding>" line each, groups in the order their first finding appears. A finding is grouped under every file it cites,
# so two findings that cite a common file land in one group; a finding that cites no file is in no group and stays with the Builder.
fix_groups() {
  local l files
  while IFS= read -r l; do
    files=$(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' <<<"$l" | sed 's/:[0-9]*$//' | sort -u | paste -sd' ' - || true)
    printf '%s\t%s\n' "$files" "${l:0:200}"
  done < <(grep -E '^[[:space:]]*([-*][[:space:]]*)?\[P[0-3]\]' "$1" || true) | awk -F'\t' '
    function find(x) { while (p[x] != x) x = p[x]; return x }
    { text[NR] = $2; n = split($1, f, " "); if (!n) next
      for (i = 1; i <= n; i++) { if (!(f[i] in p)) { p[f[i]] = f[i]; ord[++m] = f[i] } if (i > 1) { a = find(f[1]); b = find(f[i]); if (a != b) p[b] = a } }
      first[NR] = f[1] }
    END {
      for (k = 1; k <= NR; k++) if (k in first) { r = find(first[k]); if (!(r in seen)) { seen[r] = 1; roots[++g] = r } }
      for (x = 1; x <= m; x++) { r = find(ord[x]); files[r] = files[r] (files[r] == "" ? "" : ", ") ord[x] }
      for (i = 1; i <= g; i++) {
        print "- Group " i " (" files[roots[i]] "):"
        for (k = 1; k <= NR; k++) if ((k in first) && find(first[k]) == roots[i]) { t = text[k]; sub(/^[[:space:]]*[-*][[:space:]]*/, "", t); print "  - " t }
      }
    }'
}
# class_sites <round file> <txt> <md> -- runs each reviewer's `Class search: rg ...` line (host change, owner order
# 2026-10-25: a fixer that chose its own search searched its fix's shape, not the bug's). The text is the reviewer's, so
# it runs as rg with no shell, rg's program-running flags refused, and a search must hit its own finding's file:line or
# it owes nothing. A search under KNOWN GAPS: has no finding above it. Writes every hit as path:line to <txt> and the
# searches, refusals and hits to <md>.
class_sites() {
  python3 -I - "$1" "$WT" "$2" "$3" <<'PY'
import re, shlex, subprocess, sys
out, wt, txt, md = sys.argv[1:5]
CAP = 200
FINDING = re.compile(r'^\s*(?:[-*]\s*)?\[P[0-3]\]')
SITE = re.compile(r' -- ([^ :]+):(\d+) -- ')
cur, hits, lines = None, [], []
for line in open(out, encoding='utf-8', errors='replace'):
    line = line.rstrip('\n')
    if line.strip() == 'KNOWN GAPS:':
        cur = None
        continue
    if FINDING.match(line):
        m = SITE.search(line)
        cur = (m.group(1).removeprefix('./'), m.group(2)) if m else None
        continue
    m = re.match(r'^\s*Class search:\s*(.+?)\s*$', line)
    if not m:
        continue
    cmd = m.group(1).strip('`')
    def refuse(why):
        lines.append(f'- refused, {why}: {cmd}')
    try:
        argv = shlex.split(cmd)
    except ValueError as e:
        refuse(f'cannot parse ({e})'); continue
    if not argv or argv[0] != 'rg':
        refuse('not an rg command'); continue
    if any(a.startswith('--pre') or a == '--search-zip' or (re.fullmatch(r'-[A-Za-z]+', a) and 'z' in a) for a in argv[1:]):
        refuse('rg flag that runs a program'); continue
    if cur is None:
        refuse('no finding with a <file>:<line> above it'); continue
    try:
        r = subprocess.run(['rg', '--no-config', '--with-filename', '--line-number', '--no-heading', *argv[1:]],
                           cwd=wt, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        refuse('ran past 60 s'); continue
    if r.returncode not in (0, 1):
        refuse(f'rg failed ({r.stderr.strip()[:160]})'); continue
    found = []
    for l in r.stdout.splitlines():
        h = re.match(r'^(.+?):(\d+):', l)
        if h and (h.group(1).removeprefix('./'), h.group(2)) not in found:
            found.append((h.group(1).removeprefix('./'), h.group(2)))
    if cur not in found:
        refuse(f'does not hit its own finding {cur[0]}:{cur[1]}'); continue
    if len(found) > CAP:
        refuse(f'{len(found)} hits, over {CAP}: too broad to be one class'); continue
    lines.append(f'- {cmd} ({len(found)} hits)')
    for f in found:
        if f not in hits:
            hits.append(f)
with open(txt, 'w') as t:
    t.writelines(f'{p}:{n}\n' for p, n in sorted(hits, key=lambda h: (h[0], int(h[1]))))
with open(md, 'w') as d:
    d.write('\n'.join(lines + [f'  - {p}:{n}' for p, n in hits]) + ('\n' if lines else ''))
PY
}
SITES= NEWCODE=
if [ -n "$PREV" ] && [ "$(grep -v '^[[:space:]]*$' "$PREV" | tail -n 1)" = "VERDICT: NO-GO" ]; then
  SM=${PREV##*/}; SM=${SM#"$UNIT-r"}; SM=${SM%-reports.md}
  SITES=$(evidence_section "Sites checked \\\\(pass $SM\\\\)")
  # The form a Sites line takes follows the hand-off the round was given: the deployed release asked for a bare `fixed`,
  # and a batch handed off by it keeps that record valid. Only a hand-off that names `fixed, <how>` asks for the how.
  FIXED_RE='fixed(, .+)?'
  ! grep -qF 'fixed, <how>' "$WT/.claude/briefs/$UNIT-fix-r$SM.md" 2>/dev/null || FIXED_RE='fixed, .+'
  { grep -qE '^Search: .+' <<<"$SITES" && grep -qE "^- [^ :]+:[0-9]+ ($FIXED_RE|not affected, .+)" <<<"$SITES"; } \
    || die "pass $SM ended NO-GO, and ${EV#"$WT/"} has no usable '## Sites checked (pass $SM)' section. Under that heading write the search for the same pattern at the other call sites: a 'Search: <command>' line for each search you ran, then a '- <path>:<line> fixed, <how>' or '- <path>:<line> not affected, <why>' line for each site it found. Then run the pass again."
  # Every hit of the reviewers' own class searches (class_sites) is owed as listed, fixed (and how) or not affected.
  CS=$WT/.claude/briefs/$UNIT-r$SM-class-sites.txt
  if [ -s "$CS" ]; then
    MISSING=$(grep -vxFf <(sed -nE "s/^- ([^ ]+:[0-9]+) ($FIXED_RE|not affected, .+)\$/\\1/p" <<<"$SITES") "$CS" || true)
    [ -z "$MISSING" ] || die "pass $SM ended NO-GO, and '## Sites checked (pass $SM)' leaves out $(wc -l <<<"$MISSING" | tr -d ' ') hit(s) of the reviewers' class searches (.claude/briefs/$UNIT-r$SM-class-sites.txt): $(head -10 <<<"$MISSING" | paste -sd' ' -). Add each as listed, '- <path>:<line> fixed, <how>' or '- <path>:<line> not affected, <why>'. Then run the pass again."
  fi
  # Host change (owner order 2026-10-25): passes kept finding a defect in the last fix's new code that broke a rule its
  # own plan already stated. The fixer checks its new code against the plan.
  new_code_checked "$SM" "pass $SM ended NO-GO"
elif [ -n "$PREV" ]; then
  # A class redesign is reviewed alone first (its pass commits only the plan); the code written after that GO is new
  # code no pass has seen, so it owes the same check against the plan.
  SM=${PREV##*/}; SM=${SM#"$UNIT-r"}; SM=${SM%-reports.md}
  DC=$(git -C "$WT" log --format='%H %s' HEAD | awk -v s="feat($UNIT): Builder pass r$SM" '{ h = $1; sub(/^[^ ]+ /, "") } !f && $0 == s { print h; f = 1 }')
  if [ -n "$DC" ] && plan_only "$DC"; then
    new_code_checked "$SM" "pass $SM reviewed a design alone (its commit changed only the plan)"
  fi
fi
# Issue 362: pass 1 needs a recorded break run for every `Break: <test file> -- <check label> -- <site>` line of the plan
# (outside fenced blocks): the test was run red with the condition removed. A plan with none, or no plan, owes nothing.
break_gate() {
  local PF BREAKS RUNS NOBREAK= line bt bl
  PF=$(plan_file); [ -n "$PF" ] || return 0
  [ -z "$(round_files "$WT" "$UNIT")" ] || return 0
  BREAKS=$(awk '/^```/ { fence = !fence; next } !fence && /^Break: / { sub(/^Break: /, ""); print }' "$PF")
  RUNS=$(evidence_section "Break runs")
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    bt=${line%% -- *}; bl=${line#* -- }; bl=${bl% -- *}
    grep -F -- "- $bt -- $bl -- red: " <<<"$RUNS" | grep -qE 'red: .*[^[:space:]]' || NOBREAK+="  $bt -- $bl"$'\n'
  done <<<"$BREAKS"
  [ -z "$NOBREAK" ] || die "pass 1 of $UNIT needs a break run for each Break line of the plan, and ${EV#"$WT/"} has none under '## Break runs' for:
${NOBREAK}Run each test red with the condition removed, and under that heading write '- <test file> -- <check label> -- red: <the command that ran it with the condition removed>'. Then run the pass again."
}
# Issue 341: a unit whose Data design (the brief's first such section, the batch's; the template's own comes after) is not "none" has saves to recover,
# so pass 1 needs the evidence file's `## Failure table`: one row per save, with at least one row of four cells under
# the header. A brief with no Data design section, or "none: <why>", owes no table.
table_gate() {
  local DD
  [ -z "$(round_files "$WT" "$UNIT")" ] || return 0
  DD=$(awk '/^#+[[:space:]]/ { if (on) done = 1; on = (!done && tolower($0) ~ /^#+[[:space:]]+data design([[:space:]:]|$)/); req = 0; next }
    !on { next } /^Required:/ { req = 1 } /^[[:space:]]*$/ { req = 0; next } !req && first == "" { first = $0 } END { print first }' "$WT/.claude/briefs/$UNIT.md" 2>/dev/null || true)
  [ -n "$DD" ] && ! grep -qiE '^[-*[:space:]]*none([^[:alnum:]]|$)' <<<"$DD" || return 0
  evidence_section "Failure table" | awk '
    /^[[:space:]]*\|/ { n++; if (n == 1) next; line = $0
      if (line ~ /^[[:space:]]*\|[-:| \t]+\|?[[:space:]]*$/) next
      sub(/^[[:space:]]*\|/, "", line); sub(/\|[[:space:]]*$/, "", line); k = split(line, c, "|"); ok = (k == 4)
      for (i = 1; i <= k; i++) if (c[i] ~ /^[[:space:]]*$/) ok = 0
      if (ok) found = 1 }
    END { exit !found }' \
    || die "the Data design of $UNIT's brief is not 'none', and ${EV#"$WT/"} has no '## Failure table' with a row under its header. Under that heading write one row per save: '| Save | Steps | Left behind if it stops after each step | The one recovery |', then a row of four cells for each save. Then run the pass again."
}
[ "$KIND" != adversarial ] || { break_gate; table_gate; }
# Stages what the pass will commit. --check runs it in a copy of the index, after the launch's own checks above,
# so the Builder learns of a refusal before a launch costs a retry.
stage_and_check() {
  # Staged whole, then the briefs taken back out: an exclude pathspec naming
  # .claude/briefs makes git add fail in a repo that ignores .claude/.
  git -C "$WT" add -A
  git -C "$WT" reset -q -- .claude/briefs
  # A shared template (_*.md) is tracked batch work; -u never adds the unit's own untracked brief, evidence or round files.
  # Only when one is tracked: git fails a pathspec that matches no tracked file.
  TEMPLATES=$(git -C "$WT" ls-files -- '.claude/briefs/_*') || die "could not list the tracked brief templates in $WT"
  [ -z "$TEMPLATES" ] || git -C "$WT" add -u -- '.claude/briefs/_*'
}
# The full suite before the closing pass (issue 243), when main's config asks for it. A pass with nothing to run
# refuses before anything is committed.
SUITE_ON=$(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal)
if [ "$KIND" = final ] && [ "$SUITE_ON" = true ]; then
  TEST_CMD=$(jq -r '.testCommand // empty' "$MAIN_OF_WT/.claude/commandeck.json" 2>/dev/null || true)
  [ -n "$TEST_CMD" ] || die "fullSuiteBeforeFinal is on (from $(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal source)) and main's .claude/commandeck.json has no testCommand, so the closing pass has no suite to run. Set testCommand, or turn the setting off: setup.sh --full-suite off, or in /config"
  # The merge check's own command, run whole: --changed (and the base it may take) is taken off. Its cksum, of the
  # command as configured, ends the Suite line: the merge reuses the run only for the check it would run itself.
  CMD_SUM=$(cksum <<<"$TEST_CMD" | cut -d' ' -f1)
  TEST_CMD=$(sed -E 's/[[:space:]]--changed([[:space:]]+[^-&|;[:space:]][^&|;[:space:]]*)?//g' <<<"$TEST_CMD")
fi
if [ "$CHECK" = 1 ]; then
  cp "$(git -C "$WT" rev-parse --absolute-git-dir)/index" "$LOCK/index" || die "cannot copy the index of $WT"
  GIT_INDEX_FILE=$LOCK/index stage_and_check
  echo "check ok: a launch of $UNIT $N $KIND passes the launch checks. Not run: the Codex sign-in check. Nothing was staged or committed."
  exit 0
fi
# A revoked sign-in made the pass end with no output while `codex login status`
# still said signed in, so a one-word request is the check. It runs outside the
# worktree, where the repo's own Codex Stop hooks cannot slow it past 30 s; under
# load one try can fail, so three tries, COMMANDECK_PROBE_BACKOFF (15 s) then
# twice that apart. --ephemeral leaves no session for the pass's search to find.
if [ "$BY" = codex ]; then
  pp_codex_retrust  # issue 315: a hook a tool update changed since the last launch is trusted again before Codex starts
  PROBE_ERR=$(mktemp) || die "cannot make a temp file for the Codex sign-in check"
  TRY=0 PROBE_OK=0
  while [ "$TRY" -lt 3 ]; do
    TRY=$((TRY + 1)) RC=0
    # 120 s, not 30: a signed-in Codex has taken 9 to 120+ s to say "ok" (issue 361); slow is not signed out.
    (cd "${TMPDIR:-/tmp}" && PATH="$HERE/codex-no-helpers:$PATH" timeout 120 codex exec --ephemeral --skip-git-repo-check -s read-only \
      -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" 'Reply with the one word: ok' </dev/null >/dev/null 2>"$PROBE_ERR") || RC=$?
    [ "$RC" != 0 ] || { PROBE_OK=1; break; }
    if [ "$RC" = 124 ]; then WHY="no answer within 120 s"; else WHY=$(grep . "$PROBE_ERR" | tail -1 || true); fi
    LOAD=$(bash -c '. "$1" && hs_stamp' _ "$HERE/host-services.sh" 2>/dev/null | jq -r '.load1 // empty' 2>/dev/null || true)
    echo "Codex sign-in probe: try $TRY of 3 failed (load ${LOAD:-unknown}): ${WHY:-Codex said nothing}" >&2
    [ "$TRY" = 3 ] || sleep $((${COMMANDECK_PROBE_BACKOFF:-15} * TRY))
  done
  if [ "$PROBE_OK" = 0 ]; then
    ERR=$(tail -5 "$PROBE_ERR"); rm -f "$PROBE_ERR"
    die "launch refused: Codex is not signed in or cannot answer (three one-word requests to $MODEL failed or took over 120 s; codex login status is not trusted for this). Codex said last:
${ERR:-(nothing)}
Run codex login, then run the pass again. No commit, no reviewer, no round file."
  fi
  rm -f "$PROBE_ERR"
fi

stage_and_check
# rebase_and_test -- before a closing (final) pass (issue 344, host issue 3171): the unit is rebased onto current local
# main, so the pass reads what will merge, and when main moved the shell tests that cover the unit's changed files and
# the files main changed since the old base run, so a clash with main fails here and not at the merge. Selection is
# shell-tests-for.sh, never the full suite. A conflict stops the pass: the rebase is aborted, the conflicting files are
# named, nothing is resolved here.
# Issue 356: how long each pre-review step took, in whole seconds, for the round file; "not run" for a step that did not.
T_REBASE='not run' T_TESTS='not run' T_SUITE='not run'
rebase_and_test() {
  local old new conflicts files tests own t log=$PP_SCRATCH/$UNIT-rebase-r$N.log pend t0=$SECONDS
  [ "$KIND" = final ] || return 0
  # A red run leaves the unit already on main, so a retry would find nothing to do: the old base stays on record until the tests pass.
  pend=$(git -C "$WT" rev-parse --absolute-git-dir)/builder-rebase-pending-$UNIT
  old=$(cat "$pend" 2>/dev/null) || old=$(git -C "$WT" merge-base main HEAD) || die "cannot find where $UNIT left local main in $WT"
  new=$(git -C "$WT" rev-parse -q --verify main) || die "cannot find local main in $WT"
  [ "$old" != "$new" ] || return 0
  if ! COMMANDECK_ALLOW_AGENT_GIT=1 git -C "$WT" rebase main >/dev/null 2>&1; then
    conflicts=$(git -C "$WT" diff --name-only --diff-filter=U | paste -sd' ' -)
    COMMANDECK_ALLOW_AGENT_GIT=1 git -C "$WT" rebase --abort >/dev/null 2>&1 || true
    die "REBASE CONFLICT: $UNIT does not rebase onto current local main (${conflicts:-no file named}). The rebase was aborted and the branch is as it was; no reviewer was run. Main resolves the conflict, then run the pass again: builder-codex-pass.sh $UNIT $N final"
  fi
  echo "rebased $UNIT onto local main ${new:0:8} (was based on ${old:0:8})"
  T_REBASE="$((SECONDS - t0)) s" t0=$SECONDS
  echo "$old" > "$pend"
  files=$({ git -C "$WT" diff --name-only "$new...HEAD"; git -C "$WT" diff --name-only "$old" "$new"; } | sort -u)
  tests=$(cd "$WT" && bash "$HERE/shell-tests-for.sh" <<<"$files") || die "shell-tests-for.sh failed in $WT"
  [ -n "$tests" ] || { rm -f "$pend"; echo "no shell test covers the files $UNIT or main changed since the old base"; return 0; }
  mkdir -p "$PP_SCRATCH" || die "cannot make $PP_SCRATCH for the rebase test log"
  # An `# own-lane:` test is skipped by the ordinary run, so it gets its own call, as the merge does.
  own=$(for t in $tests; do sed -n '1,5p' "$WT/$t" | grep -q '^# own-lane:' && echo "$t"; done || true)
  : >"$log"
  # shellcheck disable=SC2086 -- the paths hold no whitespace (shell-tests-for.sh matches [^/]+\.test\.sh)
  { (cd "$WT" && bash "$HERE/run-shell-tests.sh" $tests) >>"$log" 2>&1 \
      && { [ -z "$own" ] || (cd "$WT" && bash "$HERE/run-shell-tests.sh" --own-lane $own) >>"$log" 2>&1; }; } \
    || die "after the rebase onto main, tests that cover what $UNIT or main changed are red (full output $log); no reviewer was run. Fix it, then run the pass again: builder-codex-pass.sh $UNIT $N final
$(grep -E '^(FAIL|       FAIL)' "$log" | head -10)"
  rm -f "$pend"
  T_TESTS="$((SECONDS - t0)) s"
  echo "tests after the rebase: $(grep -E '^[0-9]+ passed' "$log" | tail -1)"
}
# The one authorized Builder commit: the override lifts only the linked-checkout
# and agent-ancestry guards; the protected-file and commit-msg checks still run.
PRE=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" diff --cached --quiet || COMMANDECK_ALLOW_AGENT_GIT=1 git -C "$WT" commit -q -m "feat($UNIT): Builder pass r$N"
# Host change (owner order 2026-10-25): a final whose own commit changes no code is a design-only pass; with no commit
# of its own it is a closing pass. SHA is set here first: under set -u an unset SHA ends the pass, and one inherited from
# the caller would judge another commit.
SHA=$(git -C "$WT" rev-parse HEAD)
# The check reads the pass commit's own tip, before the rebase moves it.
DESIGN=; [ "$KIND" != final ] || [ "$SHA" = "$PRE" ] || ! plan_only "$SHA" || DESIGN=design
rebase_and_test
SHA=$(git -C "$WT" rev-parse HEAD)
# The suite runs on the tip just committed, before any reviewer starts. Its line goes first in the review input,
# where --verify reads it from the prompt the pass recorded; a red run makes the pass NO-GO whatever the reviewer says.
SUITE="" SUITE_RED=""
if [ -n "${TEST_CMD:-}" ]; then
  SUITE_LOG=$PP_SCRATCH/$UNIT-suite-${SHA:0:8}.log
  mkdir -p "$PP_SCRATCH" || die "cannot make $PP_SCRATCH for the suite's log"
  echo "Full suite before the closing pass: $TEST_CMD (log $SUITE_LOG)"
  T0=$SECONDS RC=0
  # What the tip's tracked files and index hold, before and after: a suite that rewrote or staged one, or
  # committed, tested another tree than the tip, and its green must not reach the merge's reuse (issue 307).
  tracked_state() { git -C "$WT" rev-parse HEAD; git -C "$WT" diff --no-ext-diff --no-textconv --binary HEAD; git -C "$WT" diff --cached --no-ext-diff --no-textconv --binary; }
  BEFORE=$(tracked_state | cksum)
  # An hour: the whole suite runs about 12 minutes on an idle machine.
  (cd "$WT" && timeout 3600 bash -c "$TEST_CMD") > "$SUITE_LOG" 2>&1 || RC=$?
  case $RC in 0) R=pass ;; 124) R=timeout ;; *) R=fail ;; esac
  if [ "$(tracked_state | cksum)" != "$BEFORE" ]; then
    R=changed
    echo "The suite changed tracked files, the index or HEAD of $WT: $(git -C "$WT" status --porcelain --untracked-files=no | head -5 | paste -sd' ' -)" >> "$SUITE_LOG"
  fi
  TOTALS=$(grep -E '[0-9]+ (passed|failed)' "$SUITE_LOG" | tail -1 | tr -s ' \t' ' ' | sed 's/^ //; s/ $//' || true)
  T_SUITE="$((SECONDS - T0)) s"
  SUITE="Suite: $SHA $R ${TOTALS:-no totals printed} $((SECONDS - T0))s $SUITE_LOG cmd:$CMD_SUM"
  # Set on the run's exit, never left empty: a red run whose log names nothing still forces the NO-GO below.
  [ "$R" = pass ] || SUITE_RED="$R (exit $RC)${TOTALS:+, $TOTALS}: $(grep -m5 'FAIL' "$SUITE_LOG" || tail -n 1 "$SUITE_LOG")"
  echo "$SUITE"
fi
# The first pass's reviewers, by the size rule on the commit just made; the line goes into the round file.
RULE_LINE=""
if [ "$KIND" = adversarial ]; then
  SIZE=$(build_size "$WT" "$SHA") || exit 2
  ! one_reviewer_fits "$SIZE" || FOCI=("$DATA_DESIGN All three angles, in this one review. ${ANGLES[*]}")
  RULE_LINE="Reviewers: ${#FOCI[@]} ($(size_words "$SIZE"); $SMALL_WORDS, else three)"
  echo "$RULE_LINE"
fi
FROM=""; [ -z "$PREV" ] || FROM=$(sed -n 's/^Reviewed: \([0-9a-f]*\)$/\1/p' "$PREV" | head -1)
# What the round changed, files and lines, so a finding reported fixed by a
# round with no code line in it stands out.
if [ -n "$FROM" ]; then
  echo "Changed since ${PREV##*/}:"
  git -C "$WT" diff --numstat --no-renames --no-ext-diff --no-textconv "$FROM" "$SHA" -- . ':(exclude).claude/briefs' | awk -F'\t' '{ print "  " $3 " +" $1 " -" $2 }' || true
  git -C "$WT" diff -U0 --no-renames --no-ext-diff --no-textconv --no-color "$FROM" "$SHA" -- . ':(exclude).claude/briefs' \
    | awk '/^diff --git / { h = 0 } /^@@/ { h = 1; next } h && /^[-+]/ && !/^[-+][[:space:]]*(#|\/\/|\/\*|\*|<!--|$)/ { code = 1 } END { exit code }' \
    && echo "No code changed in this round: only comments or blank lines, or nothing. A finding it reports fixed is not fixed in code."
fi
# The review input is the diff itself, each changed file whole with its
# changes marked (one diff gives both), so the reviewer fetches neither.
if [ "$KIND" = review ]; then
  [ -n "$FROM" ] || die "${PREV##*/} names no reviewed commit: it was not written by the pass script"
  [ "$FROM" != "$SHA" ] || die "nothing changed since ${PREV##*/} reviewed $SHA: a narrowed pass has nothing to read. A whole-branch pass that ended GO there merges as it is; otherwise the closing pass is: builder-codex-pass.sh $UNIT $N final"
  RANGE=$FROM..HEAD HEAD_LINE=$HEAD_FIX
  NOTE="The range is git diff $FROM..HEAD. Check that each earlier finding is fixed, that the fix is right, and that it breaks nothing beside it."
else
  RANGE=main...HEAD NOTE=""
  [ "$KIND" = final ] && HEAD_LINE=$HEAD_FINAL || HEAD_LINE=$HEAD_FULL
  [ -z "$DESIGN" ] || HEAD_LINE=$HEAD_DESIGN
fi
# A diff driver or text filter the repo configures is a program: the prompt carries git's own diff.
DIFF=$(git -C "$WT" diff --no-ext-diff --no-textconv --no-color -U100000 "$RANGE") || die "cannot diff $RANGE in $WT"
[ "${#DIFF}" -le "$DIFF_MAX" ] || DIFF=$(git -C "$WT" diff --no-ext-diff --no-textconv --no-color "$RANGE") || die "cannot diff $RANGE in $WT"
[ "${#DIFF}" -le "$DIFF_HARD" ] || DIFF=$(git -C "$WT" diff --no-ext-diff --no-textconv --no-color --irreversible-delete "$RANGE") || die "cannot diff $RANGE in $WT"
# Still over the limit: the diff is not pasted, the reviewers read it file by file.
if [ "${#DIFF}" -gt "$DIFF_HARD" ]; then
  DIFF=$(git -C "$WT" diff --no-ext-diff --no-textconv --no-color --stat=200 "$RANGE"; git -C "$WT" diff --no-ext-diff --no-textconv --name-only "$RANGE") || die "cannot diff $RANGE in $WT"
  NOTE+="${NOTE:+ }The diff is over the reviewer's input limit, so only its file list follows. Read it file by file, from the review worktree: git diff $RANGE -- <path>."
fi
# Issue 250: a change to a hook is checked by running the hook, not only by reading it.
if git -C "$WT" diff --name-only "$RANGE" -- 'hooks/*.sh' | grep -q .; then
  NOTE+="${NOTE:+ }This change touches hooks/. Run at least one probe of a changed hook from the review worktree and put its output in the report: bash $HERE/hook-probe.sh <hook> '<command>' [--tool <tool> '<tool_input json>'] prints allow, refuse (<exit>) or ask, and the hook's message. If your sandbox refuses the probe's scratch folder, list the probes you would run instead."
fi
# The limits main stated, from the brief and from its rulings: without them each
# pass raised the same accepted limit again with a new wrapping case. Read from
# main's checkout only (the launcher's copy of the brief, main's rulings file):
# a limit or a cleared finding takes a finding off the list, and the Builder can write the worktree's copies.
LIMITS=$(for f in "$MAIN_OF_WT/.claude/briefs/$UNIT-builder-brief.md" "$MAIN_OF_WT/.claude/briefs/$UNIT-main-rulings.md"; do
  [ ! -f "$f" ] || awk 'on && /^#/ { on = 0 } on && NF { print } /^#+ (Stated limits|Cleared findings)/ { on = 1 }' "$f"
done)
CASES=$(plan_section 'what can go wrong')
# Issue 359 (5c): the plan's claims and decisions go after the diff, so the reviewer reads the trace instruction and the diff first.
CLAIMS=$({ plan_section 'claims to falsify'; plan_section decisions; })
AUTHOR=$(grep -E "^(Different fix|Other cases checked) r$N: " "$WT/.claude/briefs/$UNIT-evidence.md" 2>/dev/null || true)
# Main-only items the Builder lists in its evidence file: without them every pass raised the same one again.
DEFERRED=$(awk 'on && /^#/ { on = 0 } on && NF { print } /^#+ Main-only \(deferred\)/ { on = 1 }' "$WT/.claude/briefs/$UNIT-evidence.md" 2>/dev/null || true)
SUITE_TEXT=""
[ -z "$SUITE" ] || SUITE_TEXT="$SUITE"$'\n'"The project's full test command ran on this tip before this pass; the line above is its result. GO only when that run is green for this exact tip."${SUITE_RED:+$'\n'"Failing: $SUITE_RED"}
# The owner's decisions that name this unit, from main's ledger; the fix hand-off reads them again as it is written.
holds() { COMMANDECK_MAIN=$MAIN_OF_WT bash "$HERE/decision.sh" holds "$UNIT" 2>/dev/null \
  || echo "The owner's decisions ledger ($MAIN_OF_WT/.claude/metrics/decisions.jsonl) could not be read, so an open question naming $UNIT cannot be ruled out: end the title of a finding that changes a behaviour the owner may have asked about with [HOLD unknown]."; }
HOLDS=$(holds)
ACCEPTED=$(plan_section 'accepted failure modes')
# Issue 366 (O2): the closing pass over code is a fresh reviewer (freshClosingReviewer, on by default), handed no
# review history: no earlier finding, no
# Main-only list, no sites or new-code list and no author's notes on a fix (the host's: no rebuttal or fix history),
# and is told not to open the files that hold that history. It keeps the diff, the stated limits, the plan's cases,
# claims and accepted failure modes and the owner's decisions. A narrowed or design-only pass keeps all of it (a design
# is judged against the findings it answers). The fix hand-off below still lists every finding.
HANDED=$EARLIER FRESH=
if [ "$KIND" = final ] && [ -z "$DESIGN" ] && [ "$FRESHC" = yes ]; then HANDED= SITES= NEWCODE= DEFERRED= AUTHOR= FRESH=$FRESH_HEAD; fi
REST=${SUITE_TEXT:+$SUITE_TEXT$'\n'}${NOTE:+$NOTE$'\n'}${FRESH:+$FRESH$'\n'}${AUTHOR:+$'\n'$AUTHOR_HEAD$'\n'$AUTHOR$'\n'}${HOLDS:+$'\n'$HOLD_HEAD$'\n'$HOLDS$'\n'}${HANDED:+$'\n'$EARLIER_HEAD$'\n'$SAME_CLASS$'\n'$HANDED$'\n'$EARLIER_END$'\n'}${LIMITS:+$'\n'$LIMITS_HEAD$'\n'$LIMITS$'\n'}${CASES:+$'\n'$CASES_HEAD$'\n'$CASES$'\n'}${SITES:+$'\n'$SITES_HEAD$'\n'$SITES$'\n'}${NEWCODE:+$'\n'$NEWCODE_HEAD$'\n'$NEWCODE$'\n'}${DEFERRED:+$'\n'$DEFERRED_HEAD$'\n'$DEFERRED$'\n'}$'\n'$DIFF${CLAIMS:+$'\n\n'$CLAIMS_HEAD$'\n'$CLAIMS$'\n'}${ACCEPTED:+$'\n\n'$ACCEPTED_HEAD$'\n'$ACCEPTED$'\n'}
[ "$BY" != codex ] || { GH_HAND=$(gh_hand_in) || exit 2; REST+=$'\n'$GH_HAND$'\n'; }
# Rows are written here, not by a hook: a background Bash call returns before Codex ends.
LOG=$WT/.claude/builder-events.jsonl
log_codex() { printf '{"ts":"%s","event":"%s","pass":"%s","round":%s%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$KIND" "$N" "${2:-}" >> "$LOG" || true; }
# The row names the model and effort the pass runs on (the dashboard's launch roster); jq quotes them, so no value breaks the row.
log_codex codex-start ",$(jq -nr --arg m "$MODEL" --arg e "${EFFORT:-}" '"\"model\":\($m | tojson),\"effort\":\(if $e == "" then null else $e end | tojson)"')"
# The pass's own temp folder: a short path, since a socket path past 104 bytes is invalid.
SOCKS=$(mktemp -d "${TMPDIR:-/tmp}/pp-pass.XXXXXX") || die "cannot make a temp directory for the pass"
BROKERS=()
SEAT=$PP_SCRATCH/seat-$UNIT-builder.txt
no_handoff() { # <reason> -- the fix round did not start (issue 355): print why and, when a Builder seat exists, tell main
  local msg="NO FIX HAND-OFF after pass $N: $1; this session fixes on its launch model" rc=0
  echo "$msg"
  [ -f "$SEAT" ] || return 0
  bash "$HERE/to-main.sh" question "$UNIT: no fix hand-off after pass $N" "$msg. Re-run the pass from the Builder's pane to hand off." >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 3 ] || echo "(main could not be told: the send to main failed)"
}
# The fix hand-off being written: set while its file is half-written, so an exit in between cleans up and says so.
WRITING=
# Issue 378: a fresh closing reviewer reads a detached copy of the pass commit, with the unit's review files taken out
# (unit_folders.py names the folder). COPY is set only once the copy exists, so the EXIT trap touches nothing before.
COPY=
# drop_copy <copy> -- git removes the copy (one --force: git refuses a locked worktree), then prunes. Never a raw rm -rf:
# a copy git still lists is kept and named, and a leftover folder git does not list goes through pp_rm_rf, which refuses
# a folder holding a .git. Returns 1 when the copy is still there.
drop_copy() {
  local c=$1 real
  [ -e "$c" ] || { git -C "$WT" worktree prune >/dev/null 2>&1 || true; return 0; }
  real=$(cd "$c" && pwd -P) || return 1
  git -C "$WT" worktree remove --force "$c" >/dev/null 2>&1 || true
  git -C "$WT" worktree prune >/dev/null 2>&1 || true
  if git -C "$WT" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $real"; then
    echo "closing copy $c kept: git refused to remove it (a locked worktree?); nothing in it was removed"
    return 1
  fi
  [ ! -e "$c" ] || pp_rm_rf "$c"
}
pass_end() { # rc -- each broker and the Codex under it, the copy, the temp folder, then the log row
  local b
  if [ -n "$WRITING" ] && [ "$1" != 0 ]; then
    rm -f "$WRITING.tmp" || true
    no_handoff "writing $WRITING failed (exit $1)"
  fi
  for b in ${BROKERS[@]+"${BROKERS[@]}"}; do pkill -P "$b" 2>/dev/null || true; kill "$b" 2>/dev/null || true; done
  [ -z "$COPY" ] || drop_copy "$COPY" || true
  pp_rm_rf "$SOCKS" || true; unlock
  log_codex codex-end ",\"rc\":$1"
}
trap 'pass_end $?' EXIT
# The fresh closing reviewer reads a clean copy, not the worktree: a prompt line asks it not to open the round reports,
# hand-offs and evidence, and a copy without them leaves nothing to open. A stale copy (a killed pass) is replaced; a
# copy git will not remove (locked) is kept and no pass starts over it. The round files, prompts and raw outputs stay in
# the worktree (RUN): only the reviewer's working folder moves.
if [ -n "$FRESH" ]; then
  CLOSING_COPY=$(python3 "$HERE/unit_folders.py" copy "$WT") || die "cannot name the closing copy of $WT; no reviewer ran"
  drop_copy "$CLOSING_COPY" || die "the closing copy $CLOSING_COPY is kept, so no closing pass starts; unlock or remove it, then run the pass again"
  mkdir -p "${CLOSING_COPY%/*}" && git -C "$WT" worktree add -q --detach "$CLOSING_COPY" "$SHA" \
    || { drop_copy "$CLOSING_COPY" || true; die "cannot make the closing copy $CLOSING_COPY of $SHA; no reviewer ran"; }
  COPY=$CLOSING_COPY
  [ ! -d "$WT/node_modules" ] || ln -s "$WT/node_modules" "$COPY/node_modules" || die "cannot link node_modules into the closing copy"
  copy_artifacts() { # a copy of a branch that tracks no briefs has no briefs folder: nothing to remove
    [ ! -d "$COPY/.claude/briefs" ] || find "$COPY/.claude/briefs" -maxdepth 1 \( -name "$UNIT-r[0-9]*-*" -o -name "$UNIT-fix-r*.md" -o -name "$UNIT-handoff*.md" -o -name "$UNIT-after-r*.md" -o -name "$UNIT-evidence.md" \)
  }
  copy_artifacts | while IFS= read -r f; do rm -f -- "$f"; done
  [ -z "$(copy_artifacts)" ] || die "the closing copy $COPY still holds the unit's review files after they were removed; no reviewer ran"
  # The launcher writes the unit brief untracked and the pass never commits it, so a copy of the pass commit has none: the
  # reviewer is told to read it (FRESH_HEAD), so the worktree's current brief goes in.
  [ ! -f "$WT/.claude/briefs/$UNIT.md" ] || { mkdir -p "$COPY/.claude/briefs" && cp "$WT/.claude/briefs/$UNIT.md" "$COPY/.claude/briefs/$UNIT.md"; } \
    || die "cannot put the unit brief into the closing copy $COPY; no reviewer ran"
fi
RCWD=${COPY:-$WT}
# Each of the pass's readers gets a session of its own, all at once; the prompt goes by file, since it carries the diff.
RUN=$WT/.claude/briefs/$UNIT-r$N
PIDS=() SIDS=()
for i in "${!FOCI[@]}"; do
  BASE=$(plugin_prompt "${FOCI[i]}")
  printf '%s' "${BASE/"$SLOT"/"$HEAD_LINE Reviewer $((i + 1)) of ${#FOCI[@]}, round $N."$'\n'"$REST"}" > "$RUN-prompt-$((i + 1)).md"
done
if [ "$BY" = claude ]; then
  # The session may read and run git's read commands, no more. git's read
  # commands write too: --output (git takes any cut of the word) names any file
  # on the machine, and the tree check below cannot see one outside the
  # worktree. Its `git` is this wrapper; a call by another path matches no
  # allowed rule.
  # A diff driver or text filter the repo configures is a program too, and the
  # session's shell is not sandboxed: git's reads are told to run neither.
  { printf '#!/usr/bin/env bash\nREAL=%q\nWT=%q\nWTP=%q\n' "$(command -v git)" "$RCWD" "$(cd "$RCWD" && pwd -P)"; cat <<'WRAP'
unset GIT_EXTERNAL_DIFF
args=() sub= paths=
refuse() { echo "git: $a is refused in a review: $1" >&2; exit 2; }
for a in "$@"; do
  args+=("$a")
  # git reads any file it is pointed at (two paths outside the checkout are a
  # --no-index diff), and the session's file tools stop at the worktree.
  v=$a; [[ $a != -*=* ]] || v=${a#*=}
  [[ $v != /* || $v/ == "$WT"/* || $v/ == "$WTP"/* ]] || refuse "the reviewer reads this worktree, not $v"
  [[ ! $v =~ (^|/)\.\.(/|$) ]] || refuse "the reviewer reads this worktree, not a path that climbs out of it"
  [ -z "$paths" ] || continue
  case $a in
    --) paths=1 ;;
    --ou*|--ext*|--textc*)
      [[ $a == --output-indicator* ]] || refuse "the reviewer reads, it writes no file and runs no program" ;;
    --no-ind*) refuse "the reviewer reads this worktree, not files outside a repository" ;;
    -*) # before the command these point git at another repository or config (-C, -c, --git-dir)
      [ -n "$sub" ] || case $a in --no-pager|-P|--no-optional-locks) ;; *) refuse "the reviewer reads this worktree as it is" ;; esac ;;
    *) [ -n "$sub" ] || { sub=$a; case $a in diff|log|show) args+=(--no-ext-diff --no-textconv) ;; esac; } ;;
  esac
done
exec "$REAL" ${args[@]+"${args[@]}"}
WRAP
  } > "$SOCKS/git" && chmod +x "$SOCKS/git" || die "could not make the reviewer's git wrapper"
  # This pass's own prompt and output files are not the session's doing.
  tree() { git -C "$RCWD" status --porcelain --untracked-files=all | grep -vF "?? .claude/briefs/$UNIT-r$N-" || true; }
  BEFORE=$(tree)
  for i in "${!FOCI[@]}"; do
    K=$((i + 1))
    SIDS+=("$(python3 -c 'import uuid; print(uuid.uuid4())')")
    # The prompt goes in on stdin (a tool list would swallow a trailing word) and
    # the commit is named after it. --allowedTools only adds to what the settings
    # files allow, and a Builder worktree's allow node, cp and mv. --restricted
    # reads none of them and keeps the file tools inside the worktree; --tools
    # gives the shell back for git, and with nobody to ask, a command not listed
    # here is refused.
    { cat "$RUN-prompt-$K.md"; printf '\nCommit under review: %s\n' "$SHA"; } \
      | (cd "$RCWD" && env PATH="$SOCKS:$PATH" "${ARGV[@]}" --session-id "${SIDS[i]}" --restricted --tools 'Read,Grep,Glob,Bash' \
          --allowedTools 'Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(gh issue view:*),Bash(gh pr view:*),Bash(gh pr checks:*)') > "$RUN-claude-$K.json" &
    PIDS+=($!)
  done
else
  # No helper (MCP) servers. The Codex plugin would reuse the worktree's
  # shared Codex server, started with every helper by whoever came first, so
  # each thread gets a broker of this pass's own, started through
  # codex-no-helpers/codex and stopped when the pass ends. A broker serves one
  # turn at a time, hence one each. With no broker at all the plugin closes its
  # Codex a third of a second after the answer and the session record ends
  # "interrupted", which session_proof refuses.
  # Fast mode not chosen is off for this run whatever the owner's Codex config says: the wrapper adds the
  # normal tier to its own command line, and that file is never edited.
  TIER=default; ! pp_codex_fast || TIER=
  BROKER=${COMPANION%/*}/app-server-broker.mjs
  [ -f "$BROKER" ] || die "no Codex plugin broker beside $COMPANION"
  pp_codex_retrust  # the probe above may be minutes old
  for i in "${!FOCI[@]}"; do
    K=$((i + 1))
    PATH="$HERE/codex-no-helpers:$PATH" COMMANDECK_CODEX_TIER=$TIER node "$BROKER" serve --endpoint "unix:$SOCKS/$K.sock" --cwd "$RCWD" > "$SOCKS/$K.log" 2>&1 &
    BROKERS+=($!)
  done
  : > "$SOCKS/launched"
  for i in "${!FOCI[@]}"; do
    K=$((i + 1))
    for _ in $(seq 1 150); do [ -e "$SOCKS/$K.sock" ] && break; kill -0 "${BROKERS[i]}" 2>/dev/null || break; sleep "$HELPER_STEP"; done
    [ -e "$SOCKS/$K.sock" ] || die "the Codex broker of reviewer $K did not start: $(tail -3 "$SOCKS/$K.log" 2>/dev/null)"
    CODEX_COMPANION_APP_SERVER_ENDPOINT="unix:$SOCKS/$K.sock" \
      node "$COMPANION" task --json --model "$MODEL" --effort "$EFFORT" --cwd "$RCWD" --prompt-file "$RUN-prompt-$K.md" > "$RUN-codex-$K.json" &
    PIDS+=($!)
  done
fi
# A launch that never reaches Codex leaves no session, and one pass once sat 41
# minutes on it: with no session of this worktree by the limit, the
# companions are stopped and the pass ends without a round file.
SESSION_WAIT=${COMMANDECK_PASS_SESSION_WAIT:-180}
# Each reviewer needs a session of its own: its prompt carries "Reviewer K of
# M, round N.", so one reviewer's session never stands in for another's.
reviewer_session() {
  local f
  while IFS= read -r f; do
    ! grep -qF -- "Reviewer $1 of ${#FOCI[@]}, round $N." "$f" 2>/dev/null || { echo "$f"; return; }
  done < <(find "$CODEX_DIR/sessions" -name 'rollout-*.jsonl' -newer "$SOCKS/launched" -exec grep -lF -- "$RCWD" {} + 2>/dev/null)
}
# shortcut: a headless Claude reviewer has no such limit; it fails at once when it cannot start. Add one if a Claude pass ever hangs before its session.
WATCH=""
if [ "$BY" = codex ]; then
  ( sleep "$SESSION_WAIT"
    for i in "${!FOCI[@]}"; do
      [ -n "$(reviewer_session "$((i + 1))")" ] || printf '%s ' "$((i + 1))" >> "$SOCKS/no-session"
    done
    [ ! -e "$SOCKS/no-session" ] || kill "${PIDS[@]}" 2>/dev/null ) &
  WATCH=$!
fi
# A pass that waits silently reads as a hung one: say it started, then once a minute that it runs.
echo "pass $N: ${#FOCI[@]} reviewer(s) started"
( T0=$SECONDS
  while sleep "${COMMANDECK_PASS_TICK:-60}"; do
    L="pass $N: reviewers running, $(((SECONDS - T0) / 60)) min"
    if [ "$BY" = codex ]; then
      for i in "${!FOCI[@]}"; do L+=", reviewer $((i + 1)) session $([ -n "$(reviewer_session "$((i + 1))")" ] && echo found || echo 'not yet')"; done
    fi
    echo "$L"
  done ) &
TICKER=$!
FAILED="" NOJSON=""
for i in "${!PIDS[@]}"; do wait "${PIDS[i]}" || FAILED+=" $((i + 1))"; done
[ -z "$WATCH" ] || { pkill -P "$WATCH" 2>/dev/null || true; kill "$WATCH" 2>/dev/null || true; }
pkill -P "$TICKER" 2>/dev/null || true; kill "$TICKER" 2>/dev/null || true
# reviewer_id <k> -- the session of reviewer k: Claude's is the id this pass gave it, Codex's the thread it returned.
reviewer_id() {
  if [ "$BY" = claude ]; then echo "${SIDS[$1 - 1]}"; else jq -r '.threadId // empty' "$RUN-codex-$1.json" 2>/dev/null || true; fi
}
# What this pass sent, kept beside the reviewer's sessions for session_proof to
# compare whole. Every reviewer that returned a session is recorded before anything can
# refuse the pass: a pass that fails for one reviewer still happened for
# the others, and what they found is owed to the passes after it. A reviewer
# stopped at the session limit returned no thread, so its id is read from the
# session it opened: Codex may still finish that session.
for i in "${!FOCI[@]}"; do
  TID=$(reviewer_id "$((i + 1))")
  [ "$BY" = claude ] || jq -e . "$RUN-codex-$((i + 1)).json" >/dev/null 2>&1 || NOJSON+=" $((i + 1))"
  if [ -z "$TID" ]; then
    S=$(reviewer_session "$((i + 1))")
    [ -z "$S" ] || TID=$(head -1 "$S" | jq -r '.payload.id // empty' 2>/dev/null || true)
  fi
  [[ $TID =~ ^[A-Za-z0-9-]+$ ]] || continue
  mkdir -p "$RHOME/builder-pass-prompts" && cp "$RUN-prompt-$((i + 1)).md" "$RHOME/builder-pass-prompts/$TID" \
    || die "cannot record the prompt of $NAME $TID under $RHOME/builder-pass-prompts"
done
[ ! -e "$SOCKS/no-session" ] || die "no Codex session appeared within ${SESSION_WAIT}s of the launch for reviewer(s) $(tr -s ' ' < "$SOCKS/no-session" | sed 's/ $//'), so this was not a pass and no round file is written. Run the same pass again: builder-codex-pass.sh $UNIT $N $KIND"
[ -z "$FAILED" ] || die "the $BY $KIND pass failed for reviewer(s)$FAILED; raw output in $RUN-$BY-<k>.json"
# A companion that answers without JSON gave no thread and no verdict: the pass
# ended here with no word and no round file, and read as one still running.
[ -z "$NOJSON" ] || die "reviewer$NOJSON answered without JSON, so this pass has no verdict and no round file is written; what the companion printed is in $RUN-codex-<k>.json. Run the same pass again: builder-codex-pass.sh $UNIT $N $KIND"
# A Claude reviewer's shell is not sandboxed as Codex's is, so the tree is
# checked as well, files it added included.
# shortcut: a change to a file that was already untracked is not seen; sandbox the session when Claude Code can.
[ "$BY" != claude ] || { [ "$(git -C "$RCWD" rev-parse HEAD)" = "$SHA" ] && [ "$(tree)" = "$BEFORE" ]; } \
  || die "the Claude reviewer changed the worktree during the $KIND pass; restore it and run the pass again"
TIDS=() T_BEGAN=() T_ENDED=() BODY="" VERDICT="VERDICT: GO" THIS=""
for i in "${!FOCI[@]}"; do
  K=$((i + 1)) RAW=$RUN-$BY-$((i + 1)).json
  TID=$(reviewer_id "$K")
  [ -n "$TID" ] || die "the reviewer returned no session id; raw output in $RAW"
  [[ $TID =~ ^[A-Za-z0-9-]+$ ]] || die "bad $NAME id $TID; raw output in $RAW"
  PROOF=$(session_proof "$TID" "$WT" "$SHA" "$RECORD_WAIT") || exit 2
  # One reviewer's NO-GO is the pass's verdict.
  [ "${PROOF%%$'\n'*}" = "VERDICT: GO" ] || VERDICT="VERDICT: NO-GO"
  # Line 1 is the verdict and line 2 the pass kind; $( ) dropped the trailing newline, so a verdict-only reply has no third.
  SAID=$(tail -n +3 <<<"$PROOF")
  read -r _ _ _ _ T_B T_E _ <<<"$(sed -n 2p <<<"$PROOF")"
  T_BEGAN+=("$T_B") T_ENDED+=("$T_E")
  # This pass as earlier_passes will list it, for the stop below: read from the record, never from the round file.
  THIS+="@ $TID $(sed -n 2p <<<"$PROOF")"$'\n'$({ grep -E "$FINDING" <<<"$SAID" || true; } | sed 's/^\([[:space:]]*\)@/\1\\@/')$'\n'
  [ "${#FOCI[@]}" = 1 ] || SAID="Reviewer $K of ${#FOCI[@]} (${FOCI[i]%%:*}):"$'\n'$SAID
  TIDS+=("$TID") BODY+=${BODY:+$'\n\n'}$SAID
done
HEAD_NAME=Sol; [ "$BY" = codex ] || HEAD_NAME="Claude reviewer"
# A red suite is the pass's NO-GO with no reviewer's word needed.
[ -z "$SUITE_RED" ] || { VERDICT="VERDICT: NO-GO" BODY+=${BODY:+$'\n\n'}"The full suite is red on $SHA: $SUITE_RED"; }
# Issue 271: the pass began with its first reviewer and ended with its last; "-" is a time a record did not give ("-" sorts first).
TIMING="$(printf '%s\n' "${T_BEGAN[@]}" | sort | sed -n 1p) $(printf '%s\n' "${T_ENDED[@]}" | sort | sed -n '$p')"
[[ " ${T_ENDED[*]} " != *" - "* ]] || TIMING="${TIMING% *} -"
{ printf '## %s (%s, read-only)\nReviewed: %s\n' "$HEAD_NAME" "$MODEL" "$SHA"; printf "$NAME: %s\n" "${TIDS[@]}"
  printf 'Pass: %s\nTiming: %s\nPre-review: rebase %s, tests %s, suite %s\n%s%s\n%s\n\n%s\n' "${DESIGN:-$KIND}" "$TIMING" "$T_REBASE" "$T_TESTS" "$T_SUITE" "${SUITE:+$SUITE$'\n'}" "${RULE_LINE:+$RULE_LINE$'\n'}" "$BODY" "$VERDICT"; } > "$OUT"
echo "$SCOPE" > "$SCOPE_REC"
echo "${OUT##*/}: $VERDICT ($KIND pass on $SHA, $NAME(s) ${TIDS[*]})"
# Issue 366: whether the loop goes on, read from the reviewers' records and the count, never from N or a round file. A
# stop ends the pass here: no NARROWED or DESIGN GO line, no class searches, no fix hand-off.
STOP_ID=$(review_stop_id "$PASSES"$'\n'"$THIS")
if [ -n "$STOP_ID" ]; then
  echo "REVIEW STOP: ${OUT##*/} holds a P0 or P1 two passes past the cap (pass $COUNT on record); decision $STOP_ID. Write no fix and run no pass: send main one question, which waits for its answer: bash $HERE/ask-main.sh \"$STOP_ID: <the finding's class>\" \"<the redesign you propose>\". The next pass launches only once the owner has answered $STOP_ID."
  exit 0
fi
FILE_THEN_MERGE="Print your DONE line and run no fix round: main files one issue per open finding class (builder-codex-pass.sh --verify $WT $UNIT HEAD lists them), then merges: merge-unit-local.sh $UNIT --filed '<class>=#<n>' ..."
if [ "$KIND" = final ] && [ -z "$DESIGN" ] && [ -z "$SUITE_RED" ]; then
  # What is open is read over the whole record, as --verify reads it: this pass's findings and the P3s of earlier GO rounds.
  NOW_FOUND=$(grep -v '^@ ' <<<"$THIS")
  if [ "$VERDICT" = "VERDICT: GO" ] && [ -n "$(open_findings "$NOW_FOUND" "$PASSES")" ]; then
    echo "STOP (threshold): ${OUT##*/} names no $BLOCK_LEVELS, so the review loop ends with only $BELOW findings open. $FILE_THEN_MERGE"
    exit 0
  elif [ "$VERDICT" = "VERDICT: NO-GO" ] && [ "$COUNT" -ge "$REVIEW_CAP" ] && [ "$(p01_count <<<"$NOW_FOUND")" = 0 ] \
    && [ "$(cappable_count <<<"$NOW_FOUND")" -gt 0 ]; then
    echo "STOP (cap): ${OUT##*/} is pass $COUNT on record, at or past the cap of $REVIEW_CAP, and names an open $CAP_LEVELS but no P0 or P1, so the review loop ends with its findings open. $FILE_THEN_MERGE"
    exit 0
  fi
fi
# Issue 352: a narrowed GO with the closing pass on merges nothing; say the next command so no done marker follows it.
[ "$VERDICT" = "VERDICT: GO" ] && [ "$KIND" = review ] && [ "$CLOSING" != no ] \
  && echo "NARROWED GO: this GO merges nothing. Next: builder-codex-pass.sh $UNIT $((N + 1)) final; print your DONE line only after that pass's GO."
# Host change (owner order 2026-10-25): a design-only GO approves the design and merges nothing; say the next command too.
[ "$VERDICT" = "VERDICT: GO" ] && [ -n "$DESIGN" ] \
  && echo "DESIGN GO: this GO approves the design and merges nothing. Next: write the code, then builder-codex-pass.sh $UNIT $((N + 1)) final; print your DONE line only after that pass's GO."
# The reviewers' class searches run on every NO-GO, before any hand-off check, so a pass with no hand-off writes them too.
CS_TXT=$WT/.claude/briefs/$UNIT-r$N-class-sites.txt CS_MD=$WT/.claude/briefs/$UNIT-r$N-class-sites.md
[ "$VERDICT" != "VERDICT: NO-GO" ] || class_sites "$OUT" "$CS_TXT" "$CS_MD" || die "could not run the reviewers' class searches of ${OUT##*/}"

# A fix round starts in a fresh session of the same pane instead of a context grown through the whole build.
# A fix round goes to the seat record's pane whoever ran the pass; a long GO pass hands over only in the Builder's own pane, from its own worktree.
# The hand-off stands alone: main's rulings are inlined, since a worker cannot read main's checkout.
# Issue 302: a pass that ran long ends GO in a context grown through it, so the next round starts fresh too.
{ [ "$VERDICT" = "VERDICT: NO-GO" ] || [ $((SECONDS - PASS_T0)) -gt "${COMMANDECK_LONG_PASS_SECONDS:-600}" ]; } || exit 0
# Issue 355: a hand-off that is skipped says which check failed (exit 0 still: the pass itself succeeded). Only a NO-GO
# is a fix round main waits on, so only it is said; main is told when a Builder seat exists, since otherwise main or a
# test ran the pass and reads the printed reason.
SEAT_HANDLE=$(sed -n 's/^handle=//p' "$SEAT" 2>/dev/null | head -1 || true)
TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
# Issue 355: a NO-GO's fix round is the Builder's pane's to take (the seat record's handle), whoever ran the pass: main, a
# test or a second pane. A long GO pass keeps the own-pane rule, since a pass run elsewhere grew no Builder context.
if [ -n "${ORCA_TERMINAL_HANDLE:-}" ] && [ "$SEAT_HANDLE" = "$ORCA_TERMINAL_HANDLE" ] && [ "$TOP" = "$(git -C "$WT" rev-parse --show-toplevel)" ]; then IN_PANE=1; else IN_PANE=; fi
if [ "$VERDICT" = "VERDICT: NO-GO" ]; then
  [ -n "$SEAT_HANDLE" ] || { no_handoff "the seat record names no pane for the Builder"; exit 0; }
  PANE=$SEAT_HANDLE
else
  [ -n "$IN_PANE" ] || exit 0
  PANE=$ORCA_TERMINAL_HANDLE
fi
TASK=$(sed -n 's/^task=//p' "$SEAT" | head -1)
where() { # <what the brief is opened for> -- the lines both hand-offs open with
  printf 'You are the Builder of %s, in a fresh session of the same pane: the session that ran pass %s was cleared, so this file and the files it names are all you have.\n\n' "$UNIT" "$N"
  printf -- '- Worktree: %s. Orca handle: %s. Orca task: %s; your dispatch id is .result.dispatchId of `orca-ide orchestration check --terminal %s --json`, which also reads your inbox.\n' "$WT" "$PANE" "${TASK:-not in $SEAT; ask main}" "$PANE"
  printf -- '- The brief still binds you, but do not read it at start: %s: %s\n' "$1" "$WT/.claude/briefs/$UNIT.md"
}
if [ "$VERDICT" = "VERDICT: GO" ]; then
  HAND=$WT/.claude/briefs/$UNIT-after-r$N.md
  { printf '# %s: after pass %s\n\n' "$UNIT" "$N"; where "the evidence file says where you are. Open it for the next step"
    printf -- '- Pass %s ended GO; continue from the evidence file, which says what is built, verified and left: %s\n' "$N" "$WT/.claude/briefs/$UNIT-evidence.md"
  } > "$HAND"
  mkdir -p "$PP_SCRATCH"
  bash "$HERE/builder-fresh-round.sh" "$ORCA_TERMINAL_HANDLE" "$HAND" "$SEAT" > "$PP_SCRATCH/$UNIT-after-r$N.log" 2>&1 &
  echo "FRESH SESSION after pass $N: end your turn now and start nothing new in this session. The pass took over $(( ${COMMANDECK_LONG_PASS_SECONDS:-600} / 60 )) minutes, so a fresh session goes on from ${HAND##*/} once this pane is idle; keep anything it needs in the evidence file before you stop. If nothing is typed within 15 minutes, $PP_SCRATCH/$UNIT-after-r$N.log says why, main is told, and the work stays here."
  exit 0
fi
HAND=$WT/.claude/briefs/$UNIT-fix-r$N.md
# Open decisions naming the unit, read again now: one opened during the pass binds this round too.
OPEN=$(holds | grep -v '^The owner answered ' || true)
# Issue 362: this round against EVERY earlier round, GO rounds included, not only the one before it: a class that comes
# back after a GO round is the same flaw seen again. The latest earlier round that shares a class names it.
REPEAT= WHEN='in two passes in a row'
while read -r en ef; do
  [ "$en" -lt "$N" ] || continue
  rl=$(bash "$HERE/read-verdict.sh" --repeat-class "$OUT" "$ef" 2>/dev/null | sed -n 's/^REPEAT CLASS: //p' || true)
  [ -z "$rl" ] || { REPEAT=$rl; if [ "$en" = $((N - 1)) ]; then WHEN='in two passes in a row'; else WHEN='after an earlier pass'; fi; }
done < <(round_files "$WT" "$UNIT" | sort -n)
# Issue 341 (F3): every finding of the build so far, by class, with this pass's included.
FSF=$({ grep -E "$FINDING" <<<"$EARLIER" || true; grep -E "$FINDING" "$OUT" || true; } | grep -vE '^(Earlier pass |VERDICT)' | awk '
  function cls(l) { if (match(l, /\(class: [^)]*\)/)) return substr(l, RSTART + 8, RLENGTH - 9); return "no class" }
  !seen[$0]++ { c = cls($0); if (!(c in n)) order[++k] = c; n[c]++; list[c] = list[c] $0 "\n" }
  END { for (i = 1; i <= k; i++) { c = order[i]; printf "### %s (%d finding%s)\n\n%s\n", c, n[c], n[c] == 1 ? "" : "s", list[c] } }')
# Written to a temp file and published by rename only when every write succeeded (issue 355): the block runs under
# set -e, so a failed write exits at once, pass_end removes the temp file and says so, and nothing sits half-written at
# $HAND.
WRITING=$HAND
{
  printf '# %s: fix round after pass %s\n\n' "$UNIT" "$N"
  where "the findings say what to fix. Open it only when a finding needs it"
  printf -- '- The evidence file says what is built, verified and left. Open it when a finding needs it, and to update it before the next pass: %s\n' "$WT/.claude/briefs/$UNIT-evidence.md"
  printf -- '- Fix what pass %s found (below) red first, the whole class of each bug, then run the next pass as the brief says (round %s).\n' "$N" "$((N + 1))"
  # Issue 362: the next pass refuses without this section, and its reviewers get it.
  printf -- '- Before pass %s, add `## Sites checked (pass %s)` to the evidence file: search the repo for the same pattern as each finding below, one `Search: <command>` line per search, then one line per site it turned up, `- <path>:<line> fixed, <how>` or `- <path>:<line> not affected, <why>`. The next pass refuses to start without it, and its reviewers treat a site of the pattern missing from the list, or wrongly marked not affected, as a finding.\n' "$((N + 1))" "$N"
  printf -- '- Before pass %s, also add `## New code checked (pass %s)` to the evidence file: check every read, write or check your fix adds or changes against the plan'"'"'s Data design, What can go wrong and the failure table, one line each, `- <path>:<line> meets <the plan line it follows>` or `- <path>:<line> no plan rule, <why it is safe>` (`- none, <why>` when the fix added none). A new site follows the rule the plan already has for its kind (a read the plan says is strongly consistent is strongly consistent everywhere). The next pass refuses to start without it, and its reviewers check each line against the plan.\n' "$((N + 1))" "$N"
  printf -- '- A finding marked `(not in the plan list)` is fixed AND added, with its test, to the What can go wrong section of the plan (%s) in the same commit.\n' "$(plan_rel | grep . || echo ".claude/plans/$UNIT.md")"
  printf -- '- A finding'"'"'s severity is the reviewer'"'"'s: never lower one in a round file or the evidence (the loop'"'"'s stop reads the reviewer'"'"'s record, not the round file). Send a dispute to main as a question.\n'
  printf -- '- A fix that changes when a state is trusted (narrows or widens it) reruns the existing cases with the state swapped in before the next pass, and the evidence file records the result.\n'
  printf -- '- A closing (final) pass first rebases this unit onto current local main and, when main moved, runs the shell tests that cover what you or main changed. A conflict or a red test stops it before the reviewer: fix a red test, send a conflict to main as a question.\n\n'
  printf '## Findings so far\n\nEvery finding of this build'"'"'s passes so far, this pass'"'"'s included, by class. A class with several findings, or one that returns, is one flaw seen again and again: fix it as a class.\n\n%s\n' "${FSF:-None with a level or a class tag.}"
  printf 'A fix that touches a save updates that save'"'"'s row in the evidence file'"'"'s failure table (its steps, what is left after each, the one recovery) in the same commit; the next reviewer checks the code against the table.\n'
  printf '\n## What pass %s found (%s)\n\n' "$N" "${OUT##*/}"; cat "$OUT"
  # Findings in separate files can be fixed at once; the Builder runs the helpers, this only names the groups.
  FIXGROUPS=$(fix_groups "$OUT")
  if [ "$(grep -c '^- Group ' <<<"$FIXGROUPS")" -ge 2 ]; then
    printf '\n## Parallel fix groups\n\nThese findings share no file, so each group can be fixed on its own. Run one Agent helper per group, each with `isolation: "worktree"`, and give it only its group'"'"'s findings and files. Apply the helpers'"'"' diffs here in group order; if two diffs touch one file, drop the parallel run and fix the rest serially. Run the round'"'"'s tests once on the combined tree. A finding that cites no file is yours. It is still one commit and one pass.\n\n%s\n' "$FIXGROUPS"
  fi
  if [ -s "$CS_MD" ]; then
    printf '\n## Class sites (from the reviewers'"'"' searches)\n\nThe reviewers'"'"' own class searches, run by the pass. Every hit below goes into `## Sites checked (pass %s)` as listed, `- <path>:<line> fixed, <how>` or `- <path>:<line> not affected, <why>`; the next pass refuses while one is missing. A refused search owes nothing: run your own search for that finding'"'"'s class.\n\n' "$N"
    cat "$CS_MD"
  fi
  [ -z "$OPEN" ] || printf '\n## Open decisions (HOLD)\n\n%s\n\nDo not fix a finding tagged [HOLD <id>] or one that touches these questions: send it to main as a question with the id, and fix the rest.\n' "$OPEN"
  # Issues 261, 303 and 2894: a class back in two passes in a row is fixed as a design, once, not input by input, and
  # main hears nothing for it. A class that comes back after a design fix (the previous hand-off carries this block's
  # second-return line) is a redesign: the Builder asks main one question, through ask-main.sh (issue 335).
  if [ -n "$REPEAT" ]; then
    printf '\n## The same class again\n\nFindings of class %s came back %s (%s). Do not fix them input by input: write in the evidence file the approach that fixes the whole class (for example a fixed list in place of a parser). Fix the design for the whole class (one fence or stamp) and add one test that covers every ordering found so far, in this order. First update the Data design answers in the plan and the failure table in the evidence file so they account for every case found so far, and commit nothing else: run the next pass (final) on that design alone (a commit with no code runs as a design-only pass: its reviewer judges the design, and its GO merges nothing) and fix the design until a pass is GO. Only then change the code to match them, and run the next pass on the whole branch (final). Send main nothing for it. The class fix has one retry path that does not depend on where the state came from, and its test removes each piece of state between two runs (ticks) and shows the retry still happens. Start one background read-only agent now (an Explore helper, with the issue in its description): it lists every site in the changed files, and the scripts they source, where the flaw of this class can occur, checked against the class'"'"'s ruling, as a compact list. Fix or justify each site before the next pass, and write one line per site in the evidence file: `Sweep: <file>:<line>: fixed` or `Sweep: <file>:<line>: safe, <why>`. If the approach touches an open decision, ask main first.\n' \
      "${REPEAT% (*}" "$WHEN" "$(sed 's/.* (\(.*\))$/\1/' <<<"$REPEAT")"
    if grep -qF 'Fix the design for the whole class (one fence or stamp)' "$WT/.claude/briefs/$UNIT-fix-r$((N - 1)).md" 2>/dev/null; then
      printf '\nThis class has now returned three times. Fix the other findings first, then ask main one question, which waits for its answer: bash %s/ask-main.sh "%s: third return" "<the redesign you propose>". Build what main answers (a redesign by default; main asks the owner only for a policy call).\n' \
        "$HERE" "${REPEAT%% (*}"
    fi
  fi
  # Issue 264: each finding's test, by the rule run-shell-tests.sh --changed uses for a same-name test.
  # A finding's place is the first " -- <path>:<line> -- " on its line: one its text quotes comes later.
  TPF=$({ grep -E "$FINDING" "$OUT" || true; } | awk 'match($0, / -- [^ :]+:[0-9]+ -- /) { p = substr($0, RSTART + 4, RLENGTH - 8); sub(/:/, " ", p); if (!seen[p]++) print p }' | while read -r p l; do
    # Leading-paren patterns: bash 3.2 cannot parse a bare `pat)` case inside $( ).
    case $p in (*.test.*) t=$p ;; (hooks/*|scripts/*) t=${p%%/*}/__tests__/$(basename "${p%.*}").test.sh ;; (*) t="" ;; esac
    if [ -n "$t" ] && [ -f "$WT/$t" ]; then
      v=$(sed -n '/^#/!q;p' "$WT/$t" | grep -oE '[A-Z][A-Z0-9_]*_TEST_CASE' | head -1 || true)
      printf -- "- %s:%s: test %s%s; run: %sbash %s %s\n" "$p" "$l" "$t" "${v:+, one case with $v=<case label>}" \
        "${v:+$v='<case label>' }" "$HERE/run-shell-tests.sh" "$t"
    else echo "- $p:$l: no same-name test: name the test file in the evidence before the fix."; fi
  done)
  [ -z "$TPF" ] || printf '\n## Tests per finding\n\n%s\n' "$TPF"
  printf '\n## Main'"'"'s rulings\n\n'
  if [ "${#RULINGS[@]}" -gt 0 ]; then for f in "${RULINGS[@]}"; do printf 'From %s:\n\n' "$f"; cat "$f"; echo; done
  else echo 'None for this unit.'; fi
  printf '\n## Test files this build touched\n\nA fix round re-runs only the files it touches.\n\n'
  { git -C "$WT" diff --name-only main...HEAD | grep -E '\.test\.' || true; } | sed 's/^/- /'
} > "$HAND.tmp"
[ ! -d "$HAND" ]
mv -f "$HAND.tmp" "$HAND"
WRITING=
mkdir -p "$PP_SCRATCH"
bash "$HERE/builder-fresh-round.sh" "$PANE" "$HAND" "$SEAT" > "$PP_SCRATCH/$UNIT-fix-r$N.log" 2>&1 &
if [ -n "$IN_PANE" ]; then
  echo "FIX ROUND $N: end your turn now and start no fix in this session. Once this pane is idle, a fresh session takes the fix round from ${HAND##*/}; keep anything it needs in the evidence file before you stop. If nothing is typed within 15 minutes, $PP_SCRATCH/$UNIT-fix-r$N.log says why, main is told, and the fix round stays here."
else
  echo "FIX ROUND $N: this session is not the Builder's pane, so the Builder's pane ($PANE) takes the fix round from ${HAND##*/} once it is idle; fix nothing here. If nothing is typed within 15 minutes, $PP_SCRATCH/$UNIT-fix-r$N.log says why and main is told."
fi
