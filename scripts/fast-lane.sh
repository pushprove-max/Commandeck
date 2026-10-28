#!/usr/bin/env bash
# fast-lane.sh review|land -- the Fast lane's landing step: main merges the exact commit a reviewer reviewed.
#     review  run in the lane: one read-only reviewer session (the codex-reviewer route, Codex or Claude) reads the
#             lane's tip, git diff main...<sha>, and ends its reply with a VERDICT line. Records the sha, the
#             reviewer and its session in $PP_SCRATCH/fast-lane.review. Refuses (exit 2) with a tracked change.
#     land    run by main in the main checkout, on main: takes the verdict, commit and folder from the reviewer's
#             own session record, never from a line the lane typed, and runs git merge --ff-only <sha>. Refuses
#             (exit 2), main untouched, with no record, a session of another commit, folder or prompt, more than
#             one turn, a reply not ending VERDICT: GO or listing a P0, P1 or P2 finding above it, a lane tip that moved
#             since the review, or a staged change in main's checkout. Prints landed only when main's index is the
#             reviewed tree, every file the lane changes is its text on disk and every path it deletes is absent; an
#             unstaged edit on any other path is allowed and named. A refusal after the merge leaves main at the
#             reviewed commit and keeps the record; a retry checks the same lane paths, and the record goes only when
#             land prints landed.
# The reviewer's record is the one builder-codex-pass.sh --verify reads for merge-unit-local.sh; a lane has no unit
# brief or round files, which that merge needs. Ceiling: a same-user process could forge the reviewer's own files.
case ${1-} in -h|--help) sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/paths.sh"
die() { echo "REFUSED: $*" >&2; exit 2; }
case ${1-}:$# in review:1|land:1) ;; *) echo "usage: fast-lane.sh review|land" >&2; exit 2 ;; esac
REC=$PP_SCRATCH/fast-lane.review LANE=$PP_WORKSPACES/Fast-lane
CODEX_DIR=${CODEX_HOME:-$HOME/.codex}
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

review() {
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "the lane has a tracked change: commit it, then review"
  local sha dir prompt session home
  sha=$(git rev-parse HEAD) dir=$(git rev-parse --show-toplevel)
  pp_route codex-reviewer || exit 2
  prompt="You are a read-only reviewer of one commit. Review git diff main...$sha, run with read-only commands; write nothing. List each finding as one line: - [P<0-3>] <title> -- <file>:<line> -- <why it matters>. P0 is critical, P1 high, P2 medium, P3 low. Your last line must be exactly VERDICT: GO when you list no P0, P1 or P2 finding (P3 findings alone are GO), otherwise exactly VERDICT: NO-GO.
Commit under review: $sha"
  work=$(mktemp -d) && trap 'pp_rm_rf "$work"' EXIT
  printf '%s' "$prompt" > "$work/prompt"
  if [ "$RT_AGENT" = claude ]; then
    home=$CLAUDE_DIR session=$(python3 -c 'import uuid; print(uuid.uuid4())')
    local argv; mapfile -t argv < <(pp_argv codex-reviewer)
    # The pass's git wrapper (builder-codex-pass.sh, the claude branch), copied: git's read
    # commands write too (--output names any file), point at another repository (-C, -c) or
    # run a configured diff driver, and the session's shell is not sandboxed.
    mkdir "$work/bin"
    { printf '#!/usr/bin/env bash\nREAL=%q\nWT=%q\nWTP=%q\n' "$(command -v git)" "$dir" "$(cd "$dir" && pwd -P)"; cat <<'WRAP'
unset GIT_EXTERNAL_DIFF
args=() sub= paths=
refuse() { echo "git: $a is refused in a review: $1" >&2; exit 2; }
for a in "$@"; do
  args+=("$a")
  v=$a; [[ $a != -*=* ]] || v=${a#*=}
  [[ $v != /* || $v/ == "$WT"/* || $v/ == "$WTP"/* ]] || refuse "the reviewer reads this worktree, not $v"
  [[ ! $v =~ (^|/)\.\.(/|$) ]] || refuse "the reviewer reads this worktree, not a path that climbs out of it"
  [ -z "$paths" ] || continue
  case $a in
    --) paths=1 ;;
    --ou*|--ext*|--textc*)
      [[ $a == --output-indicator* ]] || refuse "the reviewer reads, it writes no file and runs no program" ;;
    --no-ind*) refuse "the reviewer reads this worktree, not files outside a repository" ;;
    -*) [ -n "$sub" ] || case $a in --no-pager|-P|--no-optional-locks) ;; *) refuse "the reviewer reads this worktree as it is" ;; esac ;;
    *) [ -n "$sub" ] || { sub=$a; case $a in diff|log|show) args+=(--no-ext-diff --no-textconv) ;; esac; } ;;
  esac
done
exec "$REAL" ${args[@]+"${args[@]}"}
WRAP
    } > "$work/bin/git" && chmod +x "$work/bin/git" || die "could not make the reviewer's git wrapper"
    # The pass's read-only tool flags (builder-codex-pass.sh): --tools gives the shell back for git, and with nobody to ask, a command not listed is refused.
    (cd "$dir" && env PATH="$work/bin:$PATH" "${argv[@]}" --session-id "$session" --restricted --tools 'Read,Grep,Glob,Bash' \
      --allowedTools 'Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)' < "$work/prompt" > "$work/reply") \
      || die "the Claude reviewer session failed"
  else
    home=$CODEX_DIR
    # Not --ephemeral: the session file is the record land reads.
    (cd "$dir" && PATH="$PP_SCRIPTS/codex-no-helpers:$PATH" codex exec --json -s read-only -C "$dir" -m "$RT_MODEL" \
      -c "model_reasoning_effort=\"$RT_EFFORT\"" -o "$work/reply" - < "$work/prompt" > "$work/events") \
      || die "the Codex reviewer session failed"
    session=$(jq -r 'select(.type == "thread.started").thread_id' "$work/events" | head -1)
    [ -n "$session" ] || die "the Codex reviewer printed no thread.started row"
  fi
  mkdir -p "$home/fast-lane-prompts" "$PP_SCRATCH"
  cp "$work/prompt" "$home/fast-lane-prompts/$session"
  printf 'sha=%s\nby=%s\nsession=%s\n' "$sha" "$RT_AGENT" "$session" > "$REC.tmp" && mv "$REC.tmp" "$REC"
  cat "$work/reply"
}

land() {
  local sha by session home tip
  local nore="no reviewer record for the Fast lane's review: run fast-lane.sh review"
  [ -f "$REC" ] || die "$nore"
  sha=$(sed -n 's/^sha=//p' "$REC" | head -1) by=$(sed -n 's/^by=//p' "$REC" | head -1) session=$(sed -n 's/^session=//p' "$REC" | head -1)
  # The record's own `verdict=` line, if any, is never read.
  [[ $sha =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ && $by =~ ^(codex|claude)$ && $session =~ ^[A-Za-z0-9-]+$ ]] || die "$nore"
  [ "$(git -C "$PP_MAIN" symbolic-ref --short -q HEAD || true)" = main ] || die "land runs in the main checkout, on main"
  [ "$by" = claude ] && home=$CLAUDE_DIR || home=$CODEX_DIR
  python3 -I - "$by" "$session" "$sha" "$home" "$LANE" <<'PY'
import glob, json, os, re, sys
by, tid, sha, home, lane = sys.argv[1:]
name = "Claude session" if by == "claude" else "Codex thread"
def die(msg):
    print(f"REFUSED: {msg}", file=sys.stderr)
    sys.exit(2)
meta, user, replies, started, aborted = None, [], [], 0, False
if by == "claude":
    files = glob.glob(os.path.join(home, "projects", "*", f"{tid}.jsonl"))
    rows = [json.loads(l) for l in open(files[0], encoding="utf-8") if l.strip()] if len(files) == 1 else []
    for row in rows:
        if not isinstance(row, dict) or row.get("isSidechain") or row.get("isMeta"):
            continue
        c = (row.get("message") or {}).get("content")
        text = c if isinstance(c, str) else "\n".join(b.get("text") or "" for b in c or [] if isinstance(b, dict) and b.get("type") == "text")
        if row.get("type") == "user" and text.strip():
            started += 1
            user.append(text.strip())
            replies.append(None)
            if meta is None:
                asked = re.findall(r"^Commit under review: (\S+)$", text.strip(), re.M)
                meta = {"id": row.get("sessionId"), "cwd": row.get("cwd"), "git": {"commit_hash": asked[-1] if asked else None}}
        elif row.get("type") == "assistant" and text.strip() and replies:
            replies[-1] = text
    replies = [r for r in replies if r]
else:
    files = glob.glob(os.path.join(home, "sessions", "**", f"rollout-*-{tid}.jsonl"), recursive=True)
    for line in open(files[0], encoding="utf-8") if len(files) == 1 else []:
        try:
            row = json.loads(line)
        except ValueError:
            continue
        p = row.get("payload") or {}
        if row.get("type") == "session_meta" and meta is None:
            meta = p
        elif row.get("type") == "response_item" and p.get("role") == "user":
            user += [c.get("text") for c in p.get("content") or [] if isinstance(c, dict)]
        elif row.get("type") == "event_msg":
            started += p.get("type") == "task_started"
            aborted = aborted or p.get("type") == "turn_aborted"
            if p.get("type") == "task_complete":
                replies.append(p.get("last_agent_message"))
if len(files) != 1:
    die(f"no reviewer record for the Fast lane's review ({name} {tid} has no single session file under {home}): run fast-lane.sh review")
if len(replies) > 1 or started > 1:
    die(f"{name} {tid} has more than one turn (it was resumed); only a fresh review counts")
if aborted or not replies:
    die(f"{name} {tid} has no finished reply; only a review that ran to its end counts")
if not meta or meta.get("id") != tid:
    die(f"{files[0]} has no session record for {name} {tid}")
real = os.path.realpath
if not (real(meta.get("cwd") or "/nonexistent") + os.sep).startswith(real(lane) + os.sep):
    die(f"{name} {tid} ran in {meta.get('cwd')}, not in the Fast lane {lane}")
got = (meta.get("git") or {}).get("commit_hash")
if got != sha:
    die(f"{name} {tid} reviewed {got}, but the record names {sha}: review the lane's tip")
try:
    sent = open(os.path.join(home, "fast-lane-prompts", tid), encoding="utf-8").read()
except OSError:
    die(f"{name} {tid} has no copy of a prompt fast-lane.sh sent: it was not started by fast-lane.sh review")
if by == "claude":
    sent = sent.strip()
# The whole prompt, not a part: a one-line codex exec in the lane ends GO when asked to.
if sent not in user:
    die(f"{name} {tid} was not started with fast-lane.sh's prompt")
lines = (replies[0] or "").strip().splitlines()
if not lines or lines[-1].strip() != "VERDICT: GO":
    die(f"the final reply of {name} {tid} does not end with VERDICT: GO")
# A GO beside a finding that blocks is not a GO, as builder-codex-pass.sh --verify reads it (issue 366): a line above
# the verdict holding P0, P1 or P2 anywhere, in any markup (**[P1]**, `[P2]`, "* ", "1. ", "... [P1]"). P3 alone is GO.
for l in lines[:-1]:
    levels = re.findall(r"(?:^|[^A-Za-z0-9])P([0-3])(?=[^0-9]|$)", l)
    if levels and min(levels) <= "2":
        die(f"the final reply of {name} {tid} ends VERDICT: GO but lists a P0-P2 finding: {l.strip()}")
PY
  tip=$(git -C "$LANE" rev-parse HEAD 2>/dev/null) || die "no Fast lane at $LANE"
  [ "$tip" = "$sha" ] || die "Fast lane moved since its review (reviewed $sha, tip $tip): review the new tip"
  # Issue 428: a staged change would ride along with the merge, so it is refused before main moves. An unstaged edit
  # on a path the lane changes makes git merge refuse; one on any other path is allowed, and named below.
  git -C "$PP_MAIN" diff --cached --quiet HEAD || die "main's checkout has a staged change: commit or unstage it, then land"
  # The record's base= is main's HEAD before the merge, written before main moves: a refusal below leaves main at $sha
  # and keeps the record, and a retry checks the paths that merge changed, not the empty range $sha..$sha. A base
  # that is not an ancestor of $sha (none, or hand-edited) checks every tracked path. review rewrites the record without it.
  local old; old=$(git -C "$PP_MAIN" rev-parse HEAD)
  if [ "$old" != "$sha" ]; then
    { grep -v '^base=' "$REC"; echo "base=$old"; } > "$REC.tmp" && mv "$REC.tmp" "$REC" \
      || die "could not record main's HEAD in $REC; main is untouched"
  else
    old=$(sed -n 's/^base=//p' "$REC" | head -1)
    [[ $old =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] && git -C "$PP_MAIN" merge-base --is-ancestor "$old" "$sha" \
      || old=$(git -C "$PP_MAIN" hash-object -t tree /dev/null)
  fi
  git -C "$PP_MAIN" merge --ff-only "$sha" || die "git merge --ff-only $sha failed; main is untouched"
  # landed only when main's index is the reviewed tree, every file the lane changes is its text on disk, and every path
  # it deletes is absent (a recreated one is untracked, so diff misses it). -z and --no-renames list each old and new
  # path unquoted; --literal-pathspecs makes a name like g*.txt a path, not a glob.
  local off p
  off=$({ git -C "$PP_MAIN" diff --cached --name-only "$sha"
    git -C "$PP_MAIN" diff -z --no-renames --name-only "$old" "$sha" | while IFS= read -r -d '' p; do
      if git -C "$PP_MAIN" cat-file -e "$sha:$p" 2>/dev/null; then
        git -C "$PP_MAIN" --literal-pathspecs diff --quiet -- "$p" || echo "$p"
      elif [ -e "$PP_MAIN/$p" ] || [ -L "$PP_MAIN/$p" ]; then echo "$p"; fi
    done; } | sort -u | paste -sd' ' -)
  [ -z "$off" ] || die "main has moved to $sha, but main's checkout is not $sha at: $off"
  rm -f "$REC"
  echo "landed $sha"
  off=$(git -C "$PP_MAIN" diff --name-only | paste -sd' ' -)
  [ -z "$off" ] || echo "main's checkout also has unstaged edits land did not touch: $off"
}

"$1"
