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
#     One more tip merges, the P2 tail: the last closing pass ended NO-GO on
#     P2/P3 only and narrowed passes read every commit after it, the last one
#     named in the round file and bound to <tip>; or no commit came after that
#     closing pass and it is itself bound to <tip>. The proof's first line ends
#     with the rule: closing GO, first-pass GO or P2 tail.
#     Each pass lists, in its prompt, every earlier pass the reviewer's session
#     files held for the worktree at its launch (session, end time, findings);
#     the merge takes a GO only while that list is still exactly the record, so
#     one pass of a worktree runs at a time.
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
# builder-claude-pass.sh runs this same body with COMMANDECK_PASS=claude: each
# reviewer is then a headless session on roles["claude-reviewer"], its record is
# its transcript under ~/.claude/projects/*/<session id>.jsonl, its prompt is
# the template in this file (that profile has no Codex plugin), and the
# reviewed commit is the one this script names after the prompt (a transcript
# carries no commit hash). --verify reads either round file, by its id lines,
# and takes only the pass the configured profile uses.
# Ceiling: a same-user process could still forge the reviewer's own session
# files or that record; the upgrade path is a merge-side re-run.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
. "$HERE/lib-mutation-note.sh"
die() { echo "REFUSED: $*" >&2; exit 2; }
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
# Which reviewer this run is: builder-claude-pass.sh sets claude. --verify reads it from the round file instead.
BY=${COMMANDECK_PASS:-codex}
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
    COMPANION=$(ls -d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1 || true)
    [ -n "$COMPANION" ] || die "no Codex plugin companion under $HOME/.claude/plugins/cache/openai-codex/codex"
  fi
  RECORD_WAIT=30 HELPER_STEP=0.2
  [ -e "${COMPANION%/*}/commandeck-test-waits" ] || return 0
  RECORD_WAIT=$(cat "${COMPANION%/*}/commandeck-test-waits")
  [[ $RECORD_WAIT =~ ^[0-9]+$ ]] || die "${COMPANION%/*}/commandeck-test-waits must hold a number of seconds"
  HELPER_STEP=0.02
}
[ "${1:-}" != --waits ] || { pass_waits; echo "record_wait=$RECORD_WAIT helper_step=$HELPER_STEP"; exit 0; }
# What this script puts into the template. The Codex plugin's one output block
# asks for JSON against a schema only that plugin's own review command
# attaches; FORMAT replaces that block's content, so the prompt carries one
# output instruction, and every other block goes out as the plugin wrote it.
FORMAT='No schema is provided, so do not return JSON. List each finding as one line: - [P<0-3>] (class: <tag>) <title> -- <file>:<line> -- <why it matters> -- <the exact failing input or command>. Leave out a finding you cannot give one for, whatever its level, and never invent one. The class is one short kebab-case tag for the kind of defect (for example old-format-case), the same tag for the same kind in every pass. P0 is critical, P1 high, P2 medium, P3 low. P0-P2 block the merge; P3 is a nit. Your last line must be exactly VERDICT: GO when no finding is P0-P2, otherwise exactly VERDICT: NO-GO.'
# A pass is proved by this prompt, whole. A build whose earlier passes were sent another
# (the plugin was updated mid-build) is refused, and the refusal ends with the one way on.
UPDATED='If the plugin was updated during this build, its earlier passes were sent the earlier prompt and count no longer: move the build to a new unit (a new worktree made from this branch) and review that from pass 1'
OPEN='<structured_output_contract>' CLOSE='</structured_output_contract>'
LABEL='branch diff against main'
# The diff goes out in the prompt, so the reads left are the ones around it.
GUIDANCE='The diff is in the review input below; do not fetch it again, and do not re-read a file it shows whole. Read what else you need (a caller, a test, a rule file) with read-only commands. Put reads that do not depend on each other in one tool call, not one call each.'
# The Codex plugin's line made every NO-GO pass return exactly one finding.
ONE='Prefer one strong finding over several weak ones.'
MANY='List every finding you can defend, worst first. After each one, look for the same mistake elsewhere in the diff and list those too.'
# A build that added a required setting read only the new format; every deployed environment ran the old one.
SETTINGS='A change that adds or changes a required setting (a config key, an environment variable, a file format) with no test that the release still accepts the format already deployed is P1.'
# A diff shows the changed function, not the unchanged code that calls it or reads its data.
CALLERS='When the change alters a function'"'"'s signature or behaviour, or a data shape (a type, a stored record, an API payload), open the callers and readers the diff did not touch and check that each still holds.'
# Right today is not enough: some code costs more, or breaks, as time and data grow.
LATER='Cost over time is a finding class: code that is right today but grows in cost or breaks later. Examples: retries stacked across layers, or with no backoff or cap; a full-table scan or an unindexed query on a hot path; local time where UTC is needed, a day boundary or DST.'
# Issue 282: an exception a comment justified hid a real gap for months.
EXCEPTION='An exception, allowlist or exemption entry in a guard or its test stands only when the same test proves the alternative it claims, or the entry cites an owner ruling id. A comment is not proof. Report an entry that has neither as P1.'
FOCUS_REVIEW="Correctness bugs, security problems and missing tests in the changed lines. $SETTINGS $CALLERS $LATER $EXCEPTION"
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
# The first pass is these reviewers at once, one angle each; on a small build
# it is one reviewer handed all of them (SMALL_BUILD).
ANGLES=(
  "Angle 1 of 3, bypass and trust: can any check, guard, proof or gate in this change be skipped, forged or made to pass when it should refuse? Look at every input the change trusts. $EXCEPTION"
  "Angle 2 of 3, behaviour: wrong results, edge cases, failure paths and callers the change breaks. Trace each changed branch with a concrete input. $SETTINGS $CALLERS $LATER"
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
# A finding line, and a blocker's, in a reviewer's reply.
FINDING='^[[:space:]]*([-*][[:space:]]*)?\[P[0-3]\]' BLOCKER='^[[:space:]]*([-*][[:space:]]*)?\[P[01]\]'
LIMITS_HEAD='Stated limits of this build, set by main. A finding inside a stated limit is reported as P3 "inside a stated limit", never P0 to P2:'
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
# "<full|fix|final> <k> <n> <round> <began> <ended> <read> <since> <said>" (the pass's kind, reviewer
# k of n, its round, when the record says the turn began and ended, "-" when it does not, and
# the three parts the P2 tail rule follows), then the final
# reply without its verdict; refuse (exit 2) when the session does not bind them.
# The pass waits: Codex flushes task_complete about a second after the companion returns.
# The prompt is checked against this script's own text only: the merge
# reads no plugin file, so a plugin update after a pass does not undo the pass.
session_proof() {
  python3 - "$BY" "$1" "$2" "$3" "${4:-0}" "$RHOME" "$HEAD_FULL" "$HEAD_FIX" "$HEAD_FINAL" "$OPEN"$'\n'"$FORMAT"$'\n'"$CLOSE" "$UPDATED" "$LABEL" "$GUIDANCE" "$MANY" "$LENS" <<'PY'
import glob, json, os, re, subprocess, sys, time
by, tid, wt, sha, wait, home, head_full, head_fix, head_final, block, updated, *fixed = sys.argv[1:]
name, where = ("Claude session", "projects") if by == "claude" else ("Codex thread", "sessions")
def die(msg):
    print(f"REFUSED: {msg}", file=sys.stderr)
    sys.exit(2)
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
# cut off or still running, exits 3: earlier_passes says what that means to
# its caller. Any other
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
    sys.exit(3)
if not earlier and "turn_aborted" in events:
    die(f"{name} {tid} has an interrupted turn; only a pass that ran to its end counts")
reply = replies[0] if replies else None
if not meta or meta.get("id") != tid:
    die(f"{files[0]} has no session record for {name} {tid}")
if os.path.realpath(meta.get("cwd") or "/nonexistent") != os.path.realpath(wt):
    die(f"{name} {tid} ran in {meta.get('cwd')}, not in {wt}")
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
heads = {head_full: "full", head_fix: "fix", head_final: "final"}
kind = re.search(rf"^({'|'.join(map(re.escape, heads))}) Reviewer ([1-9]) of ([1-9]), round ([1-9][0-9]*)\.$", sent, re.M)
if not kind:
    die(f"the prompt of {name} {tid} has no review-input line of the pass script")
lines = (reply or "").strip().splitlines()
if not lines or lines[-1].strip() not in ("VERDICT: GO", "VERDICT: NO-GO"):
    if not earlier:
        die(f"the final reply of {name} {tid} does not end with a VERDICT line")
    # Its findings still count; only its verdict is missing, and only the P2 tail rule asks an earlier pass for one.
    lines.append("VERDICT: NO-GO")
    said = "none"
else:
    said = ""
verdict = lines[-1].strip()
# A GO beside a blocking finding is not a GO.
if any(re.match(r"\s*([-*]\s*)?\[P[0-2]\]", l) for l in lines):
    verdict = "VERDICT: NO-GO"
said = said or verdict[9:]
print(verdict)
stamp = lambda t: t if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z", t) else "-"
# What the P2 tail rule follows: the commit Codex says it read, where a narrowed pass's
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

# A first pass is ONE reviewer when the commit it reads is under this many
# changed lines and main did not launch the build with --risky, else three.
# The owner's number, asked at setup; 200 when not answered; off makes no build small.
SMALL_BUILD=$(pp_review_loop smallBuild 200 '^(off|[1-9][0-9]*)$') || exit 2
# Whether a closing pass over the whole branch runs (asked at setup): with "no",
# a narrowed GO that follows the first pass over every commit merges.
CLOSING=$(pp_review_loop closingPass yes '^(yes|no)$') || exit 2
# build_size <worktree> <commit> -- print "<lines changed> <files with no count> <risky>" of the
# commit against its fork from main: insertions plus deletions, .claude/briefs/
# left out as the merge leaves it out (collect.py's lines_changed counts the
# same way). <risky> is 1 for a build main launched with builder-launch.sh
# --risky, read from the "## Design check" section that launch writes into the
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
  if ! grep -qF -- "-pass.sh $UNIT 1 adversarial" "$main" 2>/dev/null; then risky=2; elif grep -qx '## Design check' "$main"; then risky=1; fi
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
    || die "$3 is a first pass of one reviewer on a commit of $(size_words "$size"): the rule is $SMALL_WORDS. Run: builder-$BY-pass.sh $UNIT <N> adversarial"
}

# pass_threads <worktree> -- "<session id> <round>" for every pass the reviewer $BY names
# has a session of in this worktree: a session file whose recorded cwd is the
# worktree and whose first turn was asked with this script's review-input line.
# Read from the reviewer's own files and not from builder-pass-prompts: that
# folder is this script's, and a pass whose copy there is gone, or was never
# written, still happened. Any other session in the worktree is not a pass.
# shortcut: only session files of the last 14 days are read, longer than a unit lives; widen it if one ever outlasts that.
pass_threads() {
  python3 - "$BY" "$1" "$RHOME" "$HEAD_FULL" "$HEAD_FIX" "$HEAD_FINAL" <<'PY'
import glob, json, os, re, sys, time
by, wt, home, *heads = sys.argv[1:]
wt = os.path.realpath(wt)
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
            if os.path.realpath(row["cwd"]) != wt:
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
            if os.path.realpath(p.get("cwd") or "/nonexistent") != wt:
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
  local found pids="" p i
  alive() { local s; s=$(ps -o stat= -p "$1" 2>/dev/null) && [ -n "$s" ] && [[ $s != Z* ]]; }
  found=$(ps -axo pid=,command= | awk -v wt="$1" -v ids="$2" -v unit="$UNIT" '
    BEGIN { n = split(ids, id, " ") }
    { line = $0 " "; hit = (index(line, "/pp-pass.") && index(line, " --cwd " wt " ")) || index(line, " --prompt-file " wt "/.claude/briefs/" unit "-r")
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
      continue
    fi
    line=$(sed -n 2p <<<"$proof")
    [ "$rc" = 0 ] && [ -n "$line" ] && [[ "$line " != *' - '* ]] \
      || die "the record of an earlier pass of this worktree ($NAME $tid) cannot be read in full, so what it found cannot be handed on or checked. $UPDATED"
    echo "@ $tid $line"
    sed 1,2d <<<"$proof" | grep -E '^[[:space:]]*([-*][[:space:]]*)?\[P[0-3]\]' || true
  done <<<"$tids"
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
  [ -n "$TIDS" ] || die "${LAST##*/} names no Codex thread or Claude session: it was not written by builder-codex-pass.sh or builder-claude-pass.sh"
  # A Builder does not pick its reviewer: the profile does.
  [ "$BY" = "$(pp_pass)" ] || die "${LAST##*/} is a $BY pass, and the profile in $(pp_routing) reviews with builder-$(pp_pass)-pass.sh"
  # No commit subject is exempt: a commit after the review is unreviewed whatever it is called.
  WANT=$(git -C "$WT" rev-parse --verify -q "$TIP^{commit}") || die "no commit $TIP in $WT"
  SEEN="" OF="" WHAT="" RULE="" LEFT="" STEPS="" NOT_GO=""
  # A finding main ruled out is named under "Cleared findings" in main's rulings file by its own first two parts,
  # "<title> -- <file>:<line>" (a finding's class tag is not part of it): it then blocks nothing and is not open at merge, and the proof prints it as cleared.
  # Read from main's checkout only, as the limits are: the Builder can write the worktree's copy.
  MAIN_OF_WT=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && MAIN_OF_WT=${MAIN_OF_WT%/.git} || die "$WT is not a git worktree"
  export PP_CLEARED; PP_CLEARED=$(awk 'on && /^#/ { on = 0 } on && NF { sub(/^[[:space:]]*[-*][[:space:]]*/, ""); sub(/^\[P[0-3]\][[:space:]]*/, ""); sub(/^\(class: [^)]*\)[[:space:]]*/, ""); print }
    /^#+ Cleared findings/ { on = 1 }' "$MAIN_OF_WT/.claude/briefs/$UNIT-main-rulings.md" 2>/dev/null || true)
  CLEARED=$(mktemp) || die "cannot make a temp file"; trap 'rm -f "$CLEARED"' EXIT
  # uncleared -- the finding lines on stdin less those main's ruling clears, which go to $CLEARED.
  uncleared() { awk -v out="$CLEARED" 'BEGIN { n = split(ENVIRON["PP_CLEARED"], c, "\n"); for (i = 1; i <= n; i++) want[c[i]] = 1 }
    { s = $0; sub(/^[[:space:]]*([-*][[:space:]]*)?\[P[0-3]\][[:space:]]*/, "", s); sub(/^\(class: [^)]*\)[[:space:]]*/, "", s); split(s, f, " -- ")
      if ((f[1] " -- " f[2]) in want) { sub(/^[[:space:]]*/, ""); print "Cleared by main'\''s ruling: " $0 >> out } else print }'; }
  cleared() { [ ! -s "$CLEARED" ] || awk '!seen[$0]++' "$CLEARED"; }
  ROUND=${LAST##*/}; ROUND=${ROUND#"$UNIT-r"}; ROUND=${ROUND%-reports.md}
  for TID in $TIDS; do
    PROOF=$(session_proof "$TID" "$WT" "$WANT") || exit 2
    read -r READ K OF_THIS OF_ROUND BEGAN _ WAS_READ SINCE _ <<<"$(sed -n 2p <<<"$PROOF")"
    # A narrowed pass or the closing pass may end NO-GO and still merge: the P2 tail rule weighs what it found.
    [ "$READ" = fix ] || [ "$READ" = final ] || [ "${PROOF%%$'\n'*}" = "VERDICT: GO" ] || die "$NAME $TID (${LAST##*/}) ended NO-GO"
    case $READ in
      final) NOW="closing pass" RULE="closing GO"
        # session_proof has just bound this pass to the tip, so nothing was committed after it and
        # there is no fix for a narrowed pass to read. What it left open is weighed here, as a narrowed pass's is.
        ALL=$(sed 1,2d <<<"$PROOF" | grep -E "$FINDING" || true); FOUND=$(uncleared <<<"$ALL")
        # A passing whole-branch pass may still name a finding; it is open at merge like any other.
        if [ "${PROOF%%$'\n'*}" = "VERDICT: GO" ]; then LEFT+=${FOUND:+$FOUND$'\n'}
        else
          ! grep -qE "$BLOCKER" <<<"$FOUND" || die "$NAME $TID (${LAST##*/}), the closing pass, found a P0 or P1: only a closing pass that left P2 and P3 alone merges without a GO. Fix it, then run the closing pass again: builder-$BY-pass.sh $UNIT <N> final"
          [ -n "$ALL" ] || die "$NAME $TID (${LAST##*/}), the closing pass, ended NO-GO and names no finding with a severity, so it is not known to be a P2/P3 tail. Run the closing pass again: builder-$BY-pass.sh $UNIT <N> final"
          RULE="P2 tail" LEFT+=${FOUND:+$FOUND$'\n'}
        fi ;;
      # session_proof has just bound this GO to the tip, so a closing pass would read the same commit again.
      full) NOW="first pass" RULE="first-pass GO"
        FOUND=$(sed 1,2d <<<"$PROOF" | grep -E "$FINDING" | uncleared || true); LEFT+=${FOUND:+$FOUND$'\n'} ;;
      fix) NOW="narrowed pass" RULE="P2 tail"
        ALL=$(sed 1,2d <<<"$PROOF" | grep -E "$FINDING" || true); FOUND=$(uncleared <<<"$ALL")
        ! grep -qE "$BLOCKER" <<<"$FOUND" || die "$NAME $TID (${LAST##*/}) found a P0 or P1: only a tail of P2 and P3 merges without a closing GO. Fix it, then run the closing pass: builder-$BY-pass.sh $UNIT <N> final"
        [ "${PROOF%%$'\n'*}" = "VERDICT: GO" ] || NOT_GO=1
        [ -z "$NOT_GO" ] || [ -n "$ALL" ] || die "$NAME $TID (${LAST##*/}) ended NO-GO and names no finding with a severity, so what it left open cannot be read. Run another pass"
        LEFT+=${FOUND:+$FOUND$'\n'} STEPS+="$TID $WAS_READ $SINCE"$'\n' ;;
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
  ON_RECORD=$(awk '$1 == "@" { print "Earlier pass " $2 " ended " $8 }' <<<"$PASSES" | sort)
  while read -r mark EARLIER_TID _ _ _ _ _ ENDED _; do
    [ "$mark" != @ ] || [[ $ENDED < $BEGAN ]] \
      || die "the $WHAT (${LAST##*/}) was not built on the passes the reviewer has on record for this worktree: $NAME $EARLIER_TID ended $ENDED, not before the $WHAT began ($BEGAN). Run the closing pass again once every other pass has ended"
  done <<<"$PASSES"
  for TID in $TIDS; do
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
      [ -n "$SOLO" ] || die "no pass before ${LAST##*/} is the first pass of $UNIT: the closing pass's GO merges only on top of it. Run: builder-$BY-pass.sh $UNIT <N> adversarial, then the closing pass again"
      while read -r SOLO_TID SOLO_READ; do one_reviewer_allowed "$WT" "$SOLO_READ" "$NAME $SOLO_TID, before ${LAST##*/},"; done <<<"$SOLO"
    }
  # With the full suite on (issue 243), a closing pass merges only on a green run of the commit it read, as its own
  # recorded prompt states it on the line after its head line: the round file is the Builder's to edit.
  if [ "$WHAT" = "closing pass" ] && [ "$(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal)" = true ]; then
    for TID in $TIDS; do
      awk 'p { print; exit } / Reviewer [0-9]+ of [0-9]+, round [0-9]+\.$/ { p = 1 }' "$RHOME/builder-pass-prompts/$TID" | grep -qE "^Suite: $WAS_READ pass " \
        || die "the closing pass (${LAST##*/}, $NAME $TID) has no green full-suite line for the commit it read ($WAS_READ), and fullSuiteBeforeFinal is on (from $(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal source)). Run the closing pass again: builder-$BY-pass.sh $UNIT <N> final"
    done
  fi
  if [ "$RULE" = "P2 tail" ] && [ "$WHAT" = "closing pass" ]; then
    # The tail with nothing after it: the closing pass under merge is the last word on the
    # whole branch, checked above like a closing GO, and every finding it left is printed as open.
    echo "Builder proof: ${LAST##*/}: the closing pass ($NAME $(paste -sd' ' - <<<"$TIDS")) left P2/P3 only and no commit came after it, in $WT on $WANT or the commit it is a clean rebase of; rule: $RULE"
    sed '/^$/d; s/^[[:space:]]*/Open at merge: /' <<<"$LEFT"
    cleared; exit 0
  fi
  if [ "$RULE" = "P2 tail" ]; then
    # The P2 tail rule: the last closing pass ended NO-GO on P2/P3
    # only, and narrowed passes read every commit after it up to the tip. All of
    # it is read from the reviewer's records: the commit each pass read, where each
    # narrowed range began, and the findings in each reply. Any other state
    # with no closing GO refuses.
    # shortcut: a P0 or P1 a reviewer states only in prose, with no "[P1]" finding line, is not read; the pass prompt demands the line.
    AGAIN="Run the closing pass: builder-$BY-pass.sh $UNIT <N> final"
    found_by() { awk -v t="$1" '$1 == "@" { on = ($2 == t); next } on' <<<"$PASSES"; }
    read -r C_ENDED C_TID COVERED C_SAID <<<"$(awk '$1 == "@" && $3 == "final" { print $8, $2, $9, $11 }' <<<"$PASSES" | sort | tail -1)"
    ANCHOR="closing pass" NOCLOSE=""
    if [ -z "${C_TID:-}" ] && [ "$CLOSING" = no ]; then
      # The owner chose no closing pass at setup: the last first pass anchors the chain instead, and
      # the narrowed pass under merge must end GO. It was handed every earlier finding (checked above),
      # so a P0 or P1 an earlier narrowed pass found is cleared by its GO, as a closing GO clears one.
      ANCHOR="first pass" NOCLOSE=1 AGAIN="Fix it, then run another narrowed pass: builder-$BY-pass.sh $UNIT <N> review"
      [ -z "$NOT_GO" ] || die "${LAST##*/} ended NO-GO, and this project runs no closing pass (reviewLoop.closingPass): only a narrowed pass that ends GO merges. $AGAIN"
      read -r C_ENDED C_TID COVERED _ <<<"$(awk '$1 == "@" && $3 == "full" { print $8, $2, $9 }' <<<"$PASSES" | sort | tail -1)"
    else
      [ -n "${C_TID:-}" ] || die "${LAST##*/} is a narrowed pass with no closing pass before it: it read only the changes since the pass before it, and its GO merges nothing. $AGAIN"
      [ "$C_SAID" != none ] || die "the reviewer's record of the closing pass (thread $C_TID) holds no verdict, so what it found cannot be trusted as all of it. $AGAIN"
      [ "$C_SAID" = NO-GO ] || die "the closing pass ($NAME $C_TID) ended GO and commits came after it: a narrowed pass over them merges nothing. $AGAIN"
      ALL=$(found_by "$C_TID"); FOUND=$(uncleared <<<"$ALL")
      [ -n "$ALL" ] || die "the closing pass ($NAME $C_TID) ended NO-GO and names no finding with a severity, so it is not known to be a P2/P3 tail. $AGAIN"
      ! grep -qE "$BLOCKER" <<<"$FOUND" || die "the closing pass ($NAME $C_TID) found a P0 or P1: only a closing pass that left P2 and P3 alone can be followed by narrowed passes. $AGAIN"
    fi
    # Each pass after the closing one, oldest first, then the pass under merge.
    AFTER=$(awk -v c="$C_ENDED" '$1 == "@" && $8 > c { print $8, $2, $3, $9, $10, $11 }' <<<"$PASSES" | sort)
    while read -r _ TID READ WAS_READ SINCE SAID; do
      [ -n "$TID" ] || continue
      [ "$READ" = fix ] || die "a whole-branch pass ($NAME $TID) ran after the $ANCHOR $C_TID and is not the pass under merge. $AGAIN"
      [ "$SAID" != none ] || die "the reviewer's record of the narrowed pass $TID holds no verdict, so what it found cannot be trusted as all of it. $AGAIN"
      ALL=$(found_by "$TID"); FOUND=$(uncleared <<<"$ALL")
      [ -n "$NOCLOSE" ] || ! grep -qE "$BLOCKER" <<<"$FOUND" || die "the narrowed pass $TID, after the closing pass $C_TID, found a P0 or P1: a later narrowed GO does not clear it. $AGAIN"
      [ "$SAID" = GO ] || [ -n "$ALL" ] || die "the narrowed pass $TID ended NO-GO and names no finding with a severity, so what it left open cannot be read. $AGAIN"
      STEPS="$TID $WAS_READ $SINCE"$'\n'$STEPS
    done <<<"$(sort -r <<<"$AFTER")"
    while read -r TID WAS_READ SINCE; do
      [ -n "$TID" ] || continue
      # A narrowed range may start at or before the last commit read, never after it, and must end at or after it.
      git -C "$WT" merge-base --is-ancestor "$SINCE" "$COVERED" 2>/dev/null && git -C "$WT" merge-base --is-ancestor "$COVERED" "$WAS_READ" 2>/dev/null \
        || die "no pass read the commits between $COVERED and where the narrowed pass $TID began ($SINCE): every commit after the $ANCHOR $C_TID must be read. $AGAIN"
      COVERED=$WAS_READ
    done <<<"$STEPS"
    if [ -n "$NOCLOSE" ]; then
      echo "Builder proof: ${LAST##*/}: no closing pass (chosen at setup); narrowed passes read every commit after the first pass ($NAME $C_TID), and the last ($NAME(s) $(paste -sd' ' - <<<"$TIDS")) ended GO in $WT on $WANT or the commit it is a clean rebase of; rule: no closing pass"
      [ -n "$LEFT" ] && sed '/^$/d; s/^[[:space:]]*/Open at merge: /' <<<"$LEFT" || echo "Nothing open at merge: the last narrowed pass ended GO and named no finding"
      cleared; exit 0
    fi
    echo "Builder proof: ${LAST##*/}: the closing pass ($NAME $C_TID) left P2/P3 only and narrowed passes read every commit after it, the last ($NAME(s) $(paste -sd' ' - <<<"$TIDS")) in $WT on $WANT or the commit it is a clean rebase of; rule: $RULE"
    # What merges open, by Codex's record: the merge cannot read the Builder's DONE report.
    # One "Open at merge:" line per finding and no other line with those words: the merge counts them.
    [ -n "$LEFT" ] && sed '/^$/d; s/^[[:space:]]*/Open at merge: /' <<<"$LEFT" || echo "Nothing open at merge: the last narrowed pass ended GO and named no finding"
    cleared; exit 0
  fi
  echo "Builder proof: ${LAST##*/}: $NAME(s) $(paste -sd' ' - <<<"$TIDS") ended GO in $WT on $WANT or the commit it is a clean rebase of; rule: $RULE"
  # What a passing whole-branch pass still named, once however many of its reviewers named it.
  [ -z "$LEFT" ] || sed '/^$/d; s/^[[:space:]]*/Open at merge: /' <<<"$LEFT" | awk '!seen[$0]++'
  cleared; exit 0
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

if [ "$BY" = claude ]; then
  MODEL=$(jq -re '.roles["claude-reviewer"].model // empty' "$(pp_routing)") || die "no roles.claude-reviewer model in $(pp_routing)"
  mapfile -t ARGV < <(pp_argv claude-reviewer)
  [ "${#ARGV[@]}" -gt 0 ] || die "roles.claude-reviewer in $(pp_routing) is not a usable headless role"
else
  SOL=$(jq -ce '.roles["codex-reviewer"] | select(.model)' "$(pp_routing)") || die "no roles.codex-reviewer model in $(pp_routing)"
  MODEL=$(jq -r .model <<<"$SOL")
  EFFORT=$(jq -r '.effort // empty' <<<"$SOL")
  [ -n "$EFFORT" ] || die "no roles.codex-reviewer effort in $(pp_routing); the passes never run on the Codex home's own effort"
  # A family name becomes the newest model id the account lists, or the id setup saved (paths.sh).
  # Its warnings stay on stderr: one beside a resolved id is not part of the id.
  WHY=$(mktemp) || die "cannot make a temp file"
  MODEL=$(pp_codex_model "$MODEL" codex-reviewer 2>"$WHY") || { MODEL=$(<"$WHY"); rm -f "$WHY"; die "roles.codex-reviewer: ${MODEL#routing: }"; }
  cat "$WHY" >&2; rm -f "$WHY"
  # Fast mode is the owner's saved answer (set-up asks; no answer is off), never routing.json's.
  if pp_codex_fast; then
    pp_codex_fast_home || die "this project chose Codex fast mode but $CODEX_DIR/config.toml has no service_tier = \"fast\"; the Codex passes would run on the slow tier. Add that line, or turn it off: setup.sh --no-codex-fast"
  fi
  if [ "${1:-}" = --preflight ]; then
    # The companion runs the Codex CLI under the owner's sign-in; the plugin alone is not enough.
    command -v codex >/dev/null || die "no codex on PATH; the Codex plugin runs the Codex CLI"
    codex login status >/dev/null 2>&1 || die "the Codex CLI is not signed in; run: codex login"
  fi
fi
if [ "${1:-}" = --preflight ]; then printf '%s\t%s\n' "$MODEL" "$COMPANION"; exit 0; fi

# --ack-rulings <unit> runs no pass: the round and kind below are only stand-ins for it.
CHECK=0; [ "${1:-}" != --check ] || { CHECK=1; shift; }
ACK=0; [ "${1:-}" != --ack-rulings ] || { ACK=1; set -- "${2:-}" 1 review; }
UNIT=${1:?usage: builder-$BY-pass.sh [--check] <unit> <N> adversarial|review|final}; N=${2:?round number}; KIND=${3:?adversarial, review or final}
[[ $UNIT =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "bad unit name: $UNIT"
[[ $N =~ ^[1-9][0-9]*$ ]] || die "bad round number: $N"
MAX_ROUNDS=$(pp_review_loop maxRounds '' '^[1-9][0-9]*$') || exit 2
case $KIND in adversarial) FOCI=("${ANGLES[@]}") ;; review|final) FOCI=("$FOCUS_REVIEW") ;; *) die "pass must be adversarial, review or final, not $KIND" ;; esac
WT=$PP_WORKSPACES/$UNIT
[ "$(jq -r '.env.COMMANDECK_BUILDER // empty' "$WT/.claude/settings.local.json" 2>/dev/null)" = 1 ] || die "$WT is not a Builder worktree"
# Main's rulings for the unit: a Builder once ran twelve passes without
# reading three of them. Main writes the file in its own checkout; a copy in
# the worktree counts too. No pass starts on rulings the Builder has not
# acknowledged, and an acknowledgement holds for that text only.
# Which checkout is main's is read from the worktree's own git record, not
# from COMMANDECK_MAIN: a Builder that named its own checkout there would
# hide main's rulings and state its own limits.
MAIN_OF_WT=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && MAIN_OF_WT=${MAIN_OF_WT%/.git} \
  || die "$WT is not a git worktree"
# The owner's extra rounds for this unit (review-cap.sh), read from main's checkout only, before the project's limit.
CAP=$MAIN_OF_WT/.claude/briefs/$UNIT-review-cap.md LIMIT_FROM='reviewLoop.maxRounds, chosen at setup, or maxReviewRounds in /config'
if [ -e "$CAP" ]; then
  MAX_ROUNDS=$(tr -d '[:space:]' < "$CAP") && [[ $MAX_ROUNDS =~ ^[1-9][0-9]*$ ]] || die "$CAP must hold a whole number of rounds; set it with review-cap.sh $UNIT <rounds>"
  LIMIT_FROM="review-cap.sh for $UNIT"
fi
[ -z "$MAX_ROUNDS" ] || [ "$N" -le "$MAX_ROUNDS" ] \
  || die "round $N is over the $MAX_ROUNDS rounds this project allows ($LIMIT_FROM; the round is the N a pass is given, so a pass that failed still used its number). Run no more passes: report to main what is still open"
RULINGS=()
for f in "$MAIN_OF_WT/.claude/briefs/$UNIT-main-rulings.md" "$WT/.claude/briefs/$UNIT-main-rulings.md"; do
  [ ! -f "$f" ] || RULINGS+=("$f")
done
if [ "${#RULINGS[@]}" -gt 0 ]; then
  ACKED=$(git -C "$WT" rev-parse --absolute-git-dir)/builder-rulings-ack || die "$WT is not a git worktree"
  SUM=$(cat "${RULINGS[@]}" | cksum)
  if [ "$ACK" = 1 ]; then echo "$SUM" > "$ACKED"; echo "acknowledged: ${RULINGS[*]}"; exit 0; fi
  [ "$SUM" = "$(cat "$ACKED" 2>/dev/null)" ] || die "main's rulings for $UNIT have changed since you last acknowledged them: ${RULINGS[*]}
Read the file and do what it says, then acknowledge it and run the pass again: builder-$BY-pass.sh --ack-rulings $UNIT"
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
# shortcut: a lock whose holder is gone is taken over without a second lock around the takeover; the merge's check is what refuses a closing pass another pass overlapped.
LOCK=$(git -C "$WT" rev-parse --absolute-git-dir)/builder-pass.lock || die "$WT is not a git worktree"
# The lock is in the git folder, which pp_rm_rf refuses; it holds one pid file, and rmdir cannot remove more.
unlock() { rm -f "$LOCK/pid" "$LOCK/index"; rmdir "$LOCK" 2>/dev/null || true; }
if ! mkdir "$LOCK" 2>/dev/null; then
  HOLDER=$(cat "$LOCK/pid" 2>/dev/null || true)
  [[ $HOLDER =~ ^[0-9]+$ ]] && kill -0 "$HOLDER" 2>/dev/null \
    && die "another pass of $UNIT is still running (pid $HOLDER). One pass at a time: wait for it to end, then run this one"
  unlock; mkdir "$LOCK" || die "cannot take the pass lock $LOCK"
fi
echo $$ > "$LOCK/pid"
trap unlock EXIT
PASS_T0=$SECONDS
# The passes before this one. The last round file's reviewed commit bounds a
# narrowed pass. What they found goes to this pass's reviewers, each finding
# once, from the reviewer's records and not from the round files.
PREV=$(round_files "$WT" "$UNIT" | awk -v n="$N" '$1 < n' | sort -n | tail -1 | cut -d' ' -f2-)
PASSES=$(CUT=mark earlier_passes "$WT") || exit 2
EARLIER=$(awk '$1 == "@" { print "Earlier pass " $2 " ended " $8; next } !seen[$0]++' <<<"$PASSES")
[ "$KIND" = adversarial ] || [ -n "$PREV" ] || die "no earlier pass for $UNIT: a narrowed pass reviews the changes since the last one, and the closing pass closes the review the first one opened. Start with: builder-$BY-pass.sh $UNIT $N adversarial"
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
# Issues 260 and 266: a narrowed GO after a closing pass that found a P0 or P1 or named nothing, or after commits on a
# closing GO, merged nothing, and the final after it read the same tip again. That review is the closing pass.
# shortcut: a P0 or P1 main cleared still makes the review a closing pass; it only reads more.
if [ "$KIND" = review ]; then
  read -r C_ENDED C_TID C_SAID <<<"$(awk '$1 == "@" && $3 == "final" { print $8, $2, $11 }' <<<"$PASSES" | sort | tail -1)"
  WHY=""
  if [ -n "${C_TID:-}" ]; then
    while read -r P_TID P_SAID; do
      [ -n "$P_TID" ] || continue
      FOUND=$(awk -v t="$P_TID" '$1 == "@" { on = ($2 == t); next } on' <<<"$PASSES")
      if grep -qE "$BLOCKER" <<<"$FOUND"; then WHY="pass $P_TID found a P0 or P1"
      elif [ "$P_SAID" != GO ] && [ -z "$FOUND" ]; then WHY="pass $P_TID ended NO-GO naming no finding"; fi
    done <<<"$(awk -v c="$C_ENDED" '$1 == "@" && $8 >= c { print $2, $11 }' <<<"$PASSES")"
    [ -n "$WHY" ] || [ "$C_SAID" != GO ] || WHY="commits came after the closing GO of $C_TID"
  fi
  [ -z "$WHY" ] || { KIND=final; echo "final in place of review: $WHY; this is the closing pass, its GO merges and no separate final follows"; }
fi
# Stages what the pass will commit and refuses on the evidence-file checks; sets NOTES for the commit message.
# --check runs it in a copy of the index, so the Builder learns of a refusal before a launch costs a retry.
stage_and_check() {
  # Staged whole, then the briefs taken back out: an exclude pathspec naming
  # .claude/briefs makes git add fail in a repo that ignores .claude/.
  git -C "$WT" add -A
  git -C "$WT" reset -q -- .claude/briefs
  # A shared template (_*.md) is tracked batch work; -u never adds the unit's own untracked brief, evidence or round files.
  # Only when one is tracked: git fails a pathspec that matches no tracked file.
  TEMPLATES=$(git -C "$WT" ls-files -- '.claude/briefs/_*') || die "could not list the tracked brief templates in $WT"
  [ -z "$TEMPLATES" ] || git -C "$WT" add -u -- '.claude/briefs/_*'
  # commit-msg demands a mutation note when a guard-class test is added; the pass
  # carries the evidence file's notes, and refuses here rather than at the hook.
  NOTES=$(grep -E '^Mutation-verified: ' "$WT/.claude/briefs/$UNIT-evidence.md" 2>/dev/null || true)
  GUARDS=$(git -C "$WT" diff --cached --name-only --diff-filter=A | guard_class_tests)
  [ -n "$GUARDS" ] && [ -z "$NOTES" ] && die "this pass adds guard-class tests ($(paste -sd' ' - <<<"$GUARDS")) and .claude/briefs/$UNIT-evidence.md has no line of the form
  Mutation-verified: <what you broke and how the test went red>
Add one per guard test, then rerun the pass."
  return 0
}
# The full suite before the closing pass (issue 243), when main's config asks for it. A pass with nothing to run
# refuses before anything is committed.
SUITE_ON=$(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal)
if [ "$KIND" = final ] && [ "$SUITE_ON" = true ]; then
  TEST_CMD=$(jq -r '.testCommand // empty' "$MAIN_OF_WT/.claude/commandeck.json" 2>/dev/null || true)
  [ -n "$TEST_CMD" ] || die "fullSuiteBeforeFinal is on (from $(PP_MAIN=$MAIN_OF_WT pp_option fullSuiteBeforeFinal source)) and main's .claude/commandeck.json has no testCommand, so the closing pass has no suite to run. Set testCommand, or turn the setting off: setup.sh --full-suite off, or in /config"
  # The merge check's own command, run whole: --changed (and the base it may take) is taken off.
  TEST_CMD=$(sed -E 's/[[:space:]]--changed([[:space:]]+[^-&|;[:space:]][^&|;[:space:]]*)?//g' <<<"$TEST_CMD")
fi
if [ "$CHECK" = 1 ]; then
  cp "$(git -C "$WT" rev-parse --absolute-git-dir)/index" "$LOCK/index" || die "cannot copy the index of $WT"
  GIT_INDEX_FILE=$LOCK/index stage_and_check
  echo "check ok: a launch of $UNIT $N $KIND passes the evidence-file checks. Not run: the Codex sign-in check. Nothing was staged or committed."
  exit 0
fi
# A revoked sign-in made the pass end with no output while `codex login status`
# still said signed in, so a one-word request is the check. It runs outside the
# worktree, where the repo's own Codex Stop hooks cannot slow it past 30 s; under
# load one try can fail, so three tries, COMMANDECK_PROBE_BACKOFF (15 s) then
# twice that apart. --ephemeral leaves no session for the pass's search to find.
if [ "$BY" = codex ]; then
  PROBE_ERR=$(mktemp) || die "cannot make a temp file for the Codex sign-in check"
  TRY=0 PROBE_OK=0
  while [ "$TRY" -lt 3 ]; do
    TRY=$((TRY + 1)) RC=0
    (cd "${TMPDIR:-/tmp}" && PATH="$HERE/codex-no-helpers:$PATH" timeout 30 codex exec --ephemeral --skip-git-repo-check -s read-only \
      -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" 'Reply with the one word: ok' </dev/null >/dev/null 2>"$PROBE_ERR") || RC=$?
    [ "$RC" != 0 ] || { PROBE_OK=1; break; }
    if [ "$RC" = 124 ]; then WHY="no answer within 30 s"; else WHY=$(grep . "$PROBE_ERR" | tail -1 || true); fi
    LOAD=$(bash -c '. "$1" && hs_stamp' _ "$HERE/host-services.sh" 2>/dev/null | jq -r '.load1 // empty' 2>/dev/null || true)
    echo "Codex sign-in probe: try $TRY of 3 failed (load ${LOAD:-unknown}): ${WHY:-Codex said nothing}" >&2
    [ "$TRY" = 3 ] || sleep $((${COMMANDECK_PROBE_BACKOFF:-15} * TRY))
  done
  if [ "$PROBE_OK" = 0 ]; then
    ERR=$(tail -5 "$PROBE_ERR"); rm -f "$PROBE_ERR"
    die "launch refused: Codex is not signed in or cannot answer (three one-word requests to $MODEL failed or took over 30 s; codex login status is not trusted for this). Codex said last:
${ERR:-(nothing)}
Run codex login, then run the pass again. No commit, no reviewer, no round file."
  fi
  rm -f "$PROBE_ERR"
fi

stage_and_check
# The one authorized Builder commit: the override lifts only the linked-checkout
# and agent-ancestry guards; the protected-file and commit-msg checks still run.
git -C "$WT" diff --cached --quiet || COMMANDECK_ALLOW_AGENT_GIT=1 git -C "$WT" commit -q -m "feat($UNIT): Builder pass r$N${NOTES:+$'\n\n'$NOTES}"
SHA=$(git -C "$WT" rev-parse HEAD)
# The suite runs on the tip just committed, before any reviewer starts. Its line goes first in the review input,
# where --verify reads it from the prompt the pass recorded; a red run makes the pass NO-GO whatever the reviewer says.
SUITE="" SUITE_RED=""
if [ -n "${TEST_CMD:-}" ]; then
  SUITE_LOG=$PP_SCRATCH/$UNIT-suite-${SHA:0:8}.log
  mkdir -p "$PP_SCRATCH" || die "cannot make $PP_SCRATCH for the suite's log"
  echo "Full suite before the closing pass: $TEST_CMD (log $SUITE_LOG)"
  T0=$SECONDS RC=0
  # An hour: the whole suite runs about 12 minutes on an idle machine.
  (cd "$WT" && timeout 3600 bash -c "$TEST_CMD") > "$SUITE_LOG" 2>&1 || RC=$?
  case $RC in 0) R=pass ;; 124) R=timeout ;; *) R=fail ;; esac
  TOTALS=$(grep -E '[0-9]+ (passed|failed)' "$SUITE_LOG" | tail -1 | tr -s ' \t' ' ' | sed 's/^ //; s/ $//' || true)
  SUITE="Suite: $SHA $R ${TOTALS:-no totals printed} $((SECONDS - T0))s $SUITE_LOG"
  # Set on the run's exit, never left empty: a red run whose log names nothing still forces the NO-GO below.
  [ "$R" = pass ] || SUITE_RED="$R (exit $RC)${TOTALS:+, $TOTALS}: $(grep -m5 'FAIL' "$SUITE_LOG" || tail -n 1 "$SUITE_LOG")"
  echo "$SUITE"
fi
# The first pass's reviewers, by the size rule on the commit just made; the line goes into the round file.
RULE_LINE=""
if [ "$KIND" = adversarial ]; then
  SIZE=$(build_size "$WT" "$SHA") || exit 2
  ! one_reviewer_fits "$SIZE" || FOCI=("All three angles, in this one review. ${ANGLES[*]}")
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
  [ "$FROM" != "$SHA" ] || die "nothing changed since ${PREV##*/} reviewed $SHA: a narrowed pass has nothing to read. A whole-branch pass that ended GO there merges as it is; otherwise the closing pass is: builder-$BY-pass.sh $UNIT $N final"
  RANGE=$FROM..HEAD HEAD_LINE=$HEAD_FIX
  NOTE="The range is git diff $FROM..HEAD. Check that each earlier finding is fixed, that the fix is right, and that it breaks nothing beside it."
else
  RANGE=main...HEAD NOTE=""
  [ "$KIND" = final ] && HEAD_LINE=$HEAD_FINAL || HEAD_LINE=$HEAD_FULL
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
# a limit makes a blocker a P3, and the Builder can write the worktree's copies.
LIMITS=$(for f in "$MAIN_OF_WT/.claude/briefs/$UNIT-builder-brief.md" "$MAIN_OF_WT/.claude/briefs/$UNIT-main-rulings.md"; do
  [ ! -f "$f" ] || awk 'on && /^#/ { on = 0 } on && NF { print } /^#+ (Stated limits|Cleared findings)/ { on = 1 }' "$f"
done)
AUTHOR=$(grep -E "^(Different fix|Other cases checked) r$N: " "$WT/.claude/briefs/$UNIT-evidence.md" 2>/dev/null || true)
# Main-only items the Builder lists in its evidence file: without them every pass raised the same one again.
DEFERRED=$(awk 'on && /^#/ { on = 0 } on && NF { print } /^#+ Main-only \(deferred\)/ { on = 1 }' "$WT/.claude/briefs/$UNIT-evidence.md" 2>/dev/null || true)
SUITE_TEXT=""
[ -z "$SUITE" ] || SUITE_TEXT="$SUITE"$'\n'"The project's full test command ran on this tip before this pass; the line above is its result. GO only when that run is green for this exact tip."${SUITE_RED:+$'\n'"Failing: $SUITE_RED"}
# The owner's decisions that name this unit, from main's ledger; the fix hand-off reads them again as it is written.
holds() { COMMANDECK_MAIN=$MAIN_OF_WT bash "$HERE/decision.sh" holds "$UNIT" 2>/dev/null \
  || echo "The owner's decisions ledger ($MAIN_OF_WT/.claude/metrics/decisions.jsonl) could not be read, so an open question naming $UNIT cannot be ruled out: end the title of a finding that changes a behaviour the owner may have asked about with [HOLD unknown]."; }
HOLDS=$(holds)
REST=${SUITE_TEXT:+$SUITE_TEXT$'\n'}${NOTE:+$NOTE$'\n'}${AUTHOR:+$'\n'$AUTHOR_HEAD$'\n'$AUTHOR$'\n'}${HOLDS:+$'\n'$HOLD_HEAD$'\n'$HOLDS$'\n'}${EARLIER:+$'\n'$EARLIER_HEAD$'\n'$SAME_CLASS$'\n'$EARLIER$'\n'$EARLIER_END$'\n'}${LIMITS:+$'\n'$LIMITS_HEAD$'\n'$LIMITS$'\n'}${DEFERRED:+$'\n'$DEFERRED_HEAD$'\n'$DEFERRED$'\n'}$'\n'$DIFF
# Rows are written here, not by a hook: a background Bash call returns before Codex ends.
LOG=$WT/.claude/builder-events.jsonl
log_codex() { printf '{"ts":"%s","event":"%s","pass":"%s","round":%s%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$KIND" "$N" "${2:-}" >> "$LOG" || true; }
log_codex codex-start
# The pass's own temp folder: a short path, since a socket path past 104 bytes is invalid.
SOCKS=$(mktemp -d "${TMPDIR:-/tmp}/pp-pass.XXXXXX") || die "cannot make a temp directory for the pass"
BROKERS=()
pass_end() { # rc -- each broker and the Codex under it, the temp folder, then the log row
  local b
  for b in ${BROKERS[@]+"${BROKERS[@]}"}; do pkill -P "$b" 2>/dev/null || true; kill "$b" 2>/dev/null || true; done
  pp_rm_rf "$SOCKS" || true; unlock
  log_codex codex-end ",\"rc\":$1"
}
trap 'pass_end $?' EXIT
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
  { printf '#!/usr/bin/env bash\nREAL=%q\nWT=%q\nWTP=%q\n' "$(command -v git)" "$WT" "$(cd "$WT" && pwd -P)"; cat <<'WRAP'
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
  tree() { git -C "$WT" status --porcelain --untracked-files=all | grep -vF "?? .claude/briefs/$UNIT-r$N-" || true; }
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
      | (cd "$WT" && env PATH="$SOCKS:$PATH" "${ARGV[@]}" --session-id "${SIDS[i]}" --restricted --tools 'Read,Grep,Glob,Bash' \
          --allowedTools 'Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)') > "$RUN-claude-$K.json" &
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
  for i in "${!FOCI[@]}"; do
    K=$((i + 1))
    PATH="$HERE/codex-no-helpers:$PATH" COMMANDECK_CODEX_TIER=$TIER node "$BROKER" serve --endpoint "unix:$SOCKS/$K.sock" --cwd "$WT" > "$SOCKS/$K.log" 2>&1 &
    BROKERS+=($!)
  done
  : > "$SOCKS/launched"
  for i in "${!FOCI[@]}"; do
    K=$((i + 1))
    for _ in $(seq 1 150); do [ -e "$SOCKS/$K.sock" ] && break; kill -0 "${BROKERS[i]}" 2>/dev/null || break; sleep "$HELPER_STEP"; done
    [ -e "$SOCKS/$K.sock" ] || die "the Codex broker of reviewer $K did not start: $(tail -3 "$SOCKS/$K.log" 2>/dev/null)"
    CODEX_COMPANION_APP_SERVER_ENDPOINT="unix:$SOCKS/$K.sock" \
      node "$COMPANION" task --json --model "$MODEL" --effort "$EFFORT" --cwd "$WT" --prompt-file "$RUN-prompt-$K.md" > "$RUN-codex-$K.json" &
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
  done < <(find "$CODEX_DIR/sessions" -name 'rollout-*.jsonl' -newer "$SOCKS/launched" -exec grep -lF -- "$WT" {} + 2>/dev/null)
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
FAILED="" NOJSON=""
for i in "${!PIDS[@]}"; do wait "${PIDS[i]}" || FAILED+=" $((i + 1))"; done
[ -z "$WATCH" ] || { pkill -P "$WATCH" 2>/dev/null || true; kill "$WATCH" 2>/dev/null || true; }
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
[ ! -e "$SOCKS/no-session" ] || die "no Codex session appeared within ${SESSION_WAIT}s of the launch for reviewer(s) $(tr -s ' ' < "$SOCKS/no-session" | sed 's/ $//'), so this was not a pass and no round file is written. Run the same pass again: builder-$BY-pass.sh $UNIT $N $KIND"
[ -z "$FAILED" ] || die "the $BY $KIND pass failed for reviewer(s)$FAILED; raw output in $RUN-$BY-<k>.json"
# A companion that answers without JSON gave no thread and no verdict: the pass
# ended here with no word and no round file, and read as one still running.
[ -z "$NOJSON" ] || die "reviewer$NOJSON answered without JSON, so this pass has no verdict and no round file is written; what the companion printed is in $RUN-codex-<k>.json. Run the same pass again: builder-$BY-pass.sh $UNIT $N $KIND"
# A Claude reviewer's shell is not sandboxed as Codex's is, so the tree is
# checked as well, files it added included.
# shortcut: a change to a file that was already untracked is not seen; sandbox the session when Claude Code can.
[ "$BY" != claude ] || { [ "$(git -C "$WT" rev-parse HEAD)" = "$SHA" ] && [ "$(tree)" = "$BEFORE" ]; } \
  || die "the Claude reviewer changed the worktree during the $KIND pass; restore it and run the pass again"
TIDS=() BODY="" VERDICT="VERDICT: GO"
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
  [ "${#FOCI[@]}" = 1 ] || SAID="Reviewer $K of ${#FOCI[@]} (${FOCI[i]%%:*}):"$'\n'$SAID
  TIDS+=("$TID") BODY+=${BODY:+$'\n\n'}$SAID
done
HEAD_NAME=Sol; [ "$BY" = codex ] || HEAD_NAME="Claude reviewer"
# A red suite is the pass's NO-GO with no reviewer's word needed.
[ -z "$SUITE_RED" ] || { VERDICT="VERDICT: NO-GO" BODY+=${BODY:+$'\n\n'}"The full suite is red on $SHA: $SUITE_RED"; }
{ printf '## %s (%s, read-only)\nReviewed: %s\n' "$HEAD_NAME" "$MODEL" "$SHA"; printf "$NAME: %s\n" "${TIDS[@]}"
  printf 'Pass: %s\n%s%s\n%s\n\n%s\n' "$KIND" "${SUITE:+$SUITE$'\n'}" "${RULE_LINE:+$RULE_LINE$'\n'}" "$BODY" "$VERDICT"; } > "$OUT"
echo "$SCOPE" > "$SCOPE_REC"
echo "${OUT##*/}: $VERDICT ($KIND pass on $SHA, $NAME(s) ${TIDS[*]})"

# A fix round starts in a fresh session of the same pane instead of a context grown through the whole build.
# Only the Builder's own pane (its seat record's handle) running its own pass from its own worktree hands over.
# The hand-off stands alone: main's rulings are inlined, since a worker cannot read main's checkout.
SEAT=$PP_SCRATCH/seat-$UNIT-builder.txt
# Issue 302: a pass that ran long ends GO in a context grown through it, so the next round starts fresh too.
{ [ "$VERDICT" = "VERDICT: NO-GO" ] || [ $((SECONDS - PASS_T0)) -gt "${COMMANDECK_LONG_PASS_SECONDS:-600}" ]; } && [ -n "${ORCA_TERMINAL_HANDLE:-}" ] \
  && [ "$(sed -n 's/^handle=//p' "$SEAT" 2>/dev/null | head -1)" = "$ORCA_TERMINAL_HANDLE" ] \
  && [ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(git -C "$WT" rev-parse --show-toplevel)" ] || exit 0
TASK=$(sed -n 's/^task=//p' "$SEAT" | head -1)
where() { # <what the brief is opened for> -- the lines both hand-offs open with
  printf 'You are the Builder of %s, in a fresh session of the same pane: the session that ran pass %s was cleared, so this file and the files it names are all you have.\n\n' "$UNIT" "$N"
  printf -- '- Worktree: %s. Orca handle: %s. Orca task: %s; your dispatch id is .result.dispatchId of `orca-ide orchestration check --terminal %s --json`, which also reads your inbox.\n' "$WT" "$ORCA_TERMINAL_HANDLE" "${TASK:-not in $SEAT; ask main}" "$ORCA_TERMINAL_HANDLE"
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
REPEAT=$(bash "$HERE/read-verdict.sh" --repeat-class "$OUT" 2>/dev/null | sed -n 's/^REPEAT CLASS: //p' || true)
{
  printf '# %s: fix round after pass %s\n\n' "$UNIT" "$N"
  where "the findings say what to fix. Open it only when a finding needs it"
  printf -- '- The evidence file says what is built, verified and left. Open it when a finding needs it, and to update it before the next pass: %s\n' "$WT/.claude/briefs/$UNIT-evidence.md"
  printf -- '- Fix what pass %s found (below) red first, the whole class of each bug, then run the next pass as the brief says (round %s).\n\n' "$N" "$((N + 1))"
  printf '## What pass %s found (%s)\n\n' "$N" "${OUT##*/}"; cat "$OUT"
  [ -z "$OPEN" ] || printf '\n## Open decisions (HOLD)\n\n%s\n\nDo not fix a finding tagged [HOLD <id>] or one that touches these questions: send it to main as a question with the id, and fix the rest.\n' "$OPEN"
  # Issues 261 and 303: a class back in two passes in a row is fixed as a class, once, not input by input.
  [ -z "$REPEAT" ] || printf '\n## The same class again\n\nFindings of class %s came back in two passes in a row (%s). Do not fix them input by input: write in the evidence file the approach that fixes the whole class (for example a fixed list in place of a parser), fix the other findings first, then send main that approach as a question. The class fix has one retry path that does not depend on where the state came from, and its test removes each piece of state between two runs (ticks) and shows the retry still happens. If the approach touches an open decision, ask main first.\n' \
    "${REPEAT% (*}" "$(sed 's/.* (\(.*\))$/\1/' <<<"$REPEAT")"
  # Issue 264: each finding's test, by the rule run-shell-tests.sh --changed uses for a same-name test.
  TPF=$({ grep -E "$FINDING" "$OUT" || true; } | sed -nE 's/.* -- ([^ :]+):([0-9]+) -- .*/\1 \2/p' | awk '!seen[$0]++' | while read -r p l; do
    # Leading-paren patterns: bash 3.2 cannot parse a bare `pat)` case inside $( ).
    case $p in (*.test.*) t=$p ;; (hooks/*|scripts/*) t=${p%%/*}/__tests__/$(basename "${p%.*}").test.sh ;; (*) t="" ;; esac
    if [ -n "$t" ] && [ -f "$WT/$t" ]; then
      v=$(sed -n '/^#/!q;p' "$WT/$t" | grep -oE '[A-Z][A-Z0-9_]*_TEST_CASE' | head -1 || true)
      printf -- "- %s:%s: test %s%s; run: bash %s %s; red proof: %sbash %s %s %s '<replacement>' -- bash %s %s\n" "$p" "$l" "$t" "${v:+, one case with $v=<case label>}" \
        "$HERE/run-shell-tests.sh" "$t" "${v:+$v='<case label>' }" "$HERE/red-proof.sh" "$p" "$l" "$HERE/run-shell-tests.sh" "$t"
    else echo "- $p:$l: no same-name test: name the test file in the evidence before the fix."; fi
  done)
  [ -z "$TPF" ] || printf '\n## Tests per finding\n\n%s\n' "$TPF"
  printf '\n## Main'"'"'s rulings\n\n'
  if [ "${#RULINGS[@]}" -gt 0 ]; then for f in "${RULINGS[@]}"; do printf 'From %s:\n\n' "$f"; cat "$f"; echo; done
  else echo 'None for this unit.'; fi
  printf '\n## Test files this build touched\n\nA fix round re-runs only the files it touches.\n\n'
  { git -C "$WT" diff --name-only main...HEAD | grep -E '\.test\.' || true; } | sed 's/^/- /'
} > "$HAND"
mkdir -p "$PP_SCRATCH"
bash "$HERE/builder-fresh-round.sh" "$ORCA_TERMINAL_HANDLE" "$HAND" "$SEAT" > "$PP_SCRATCH/$UNIT-fix-r$N.log" 2>&1 &
echo "FIX ROUND $N: end your turn now and start no fix in this session. Once this pane is idle, a fresh session takes the fix round from ${HAND##*/}; keep anything it needs in the evidence file before you stop. If nothing is typed within 15 minutes, $PP_SCRATCH/$UNIT-fix-r$N.log says why, main is told, and the fix round stays here."
