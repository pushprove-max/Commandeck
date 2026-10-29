#!/usr/bin/env bash
# paths.sh -- sourced, never run. The one home for the primary checkout, the
# Orca workspaces root and the shared scratch, identical on the PC and the Mac.
#
# The primary checkout is the project the script is RUN FOR: the session's
# project (CLAUDE_PROJECT_DIR), else the folder it is run in, taken to that
# checkout's git common dir, so main and every linked worktree resolve the same
# checkout and the same scratch. Never this file's own location: an installed
# plugin sits in Claude Code's plugin cache and serves every project on the
# machine. A second formula anywhere forks scratch state.
# Overrides: COMMANDECK_MAIN and COMMANDECK_WORKSPACES, read by project-main.sh
# alone under the rule written there (inside a linked worktree git decides);
# COMMANDECK_SCRATCH, as given. The PP_* names are outputs only, exported so a child
# script or an embedded Python ledger reads the same values.
#
# The slug transform (every non-alphanumeric byte to '-') is Claude Code's own
# project-folder naming, so PP_MAIN_SLUG and PP_WORKSPACES_SLUG also name the
# ~/.claude/projects folders the ledgers read.
# Issue 395: every line below is Bash 4; under zsh or dash it failed far from here, so another shell is refused at once.
[ -n "${BASH_VERSION:-}" ] || { echo "paths.sh: source this from bash; this shell is not bash" >&2; return 1 2>/dev/null || exit 1; }
pp_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }
# pp_rm_rf <path>... -- rm -rf, removing nothing when any path is in a git folder (a file too), is a .git, or is a
# folder that holds a .git or a git folder at any depth, holds this project's checkout, or is HOME or / (dashboard.sh's
# exit trap once removed a main checkout). A git folder is known by what it holds (a HEAD file beside an objects
# folder, git's own test), never by its name or by asking git, whose answer the caller's GIT_* variables change.
# Every script that reads this file removes a folder through it; project-main.test.sh lists the few that may not.
pp_rm_rf() {
  local p r d m
  m=$(cd "${PP_MAIN:-/nonexistent}" 2>/dev/null && pwd -P) || m=
  for p in "$@"; do
    [ -n "$p" ] && [ -e "$p" ] && [ ! -L "$p" ] || continue
    if [ -d "$p" ]; then r=$(cd "$p" && pwd -P); else r=$(cd "$(dirname -- "$p")" && pwd -P); fi || return 1
    d=$r; while [ ! -f "$d/HEAD" ] || [ ! -d "$d/objects" ]; do [ "$d" = / ] && { d=; break; }; d=$(dirname -- "$d"); done
    if [ -n "$d" ] || [ "${p##*/}" = .git ] \
      || { [ -d "$p" ] && { [ "$r" = / ] || [ "$r" = "$(cd "$HOME" && pwd -P)" ] || case $m/ in "$r"/*) true ;; *) false ;; esac \
        || [ -n "$(find "$r" \( -name .git -o -name HEAD -type f -exec sh -c 'test -d "${1%/*}/objects"' _ {} \; \) -print -quit 2>/dev/null)" ]; }; }; then
      echo "paths.sh: refusing to remove $p: it is or holds a checkout or git data, HOME, / or $PP_MAIN; nothing was removed" >&2
      return 1
    fi
  done
  rm -rf -- "$@"
}

# Preflight. requirements.sh puts Homebrew's folders ahead of the system ones
# on a Mac's PATH, starts a script the Mac's own Bash 3.2 ran again under
# Homebrew's, and holds the one requirements list. What every script needs
# from that list is checked here on a Mac (its own tools are BSD ones and its
# Bash is 3.2); anything missing stops the caller before any work. It asks
# uname, not COMMANDECK_HOST_OS: a self-test's pretend Mac has no Homebrew.
. "$(dirname "${BASH_SOURCE[0]}")/requirements.sh"
if [ "$REQ_UNAME" = Darwin ] && ! req_check all; then
  { echo "paths.sh: Mac preflight failed."; req_report
    echo "setup installs what it can on a yes: bash $(printf '%q' "$REQ_DIR")/setup.sh --profile claude|claude-openai --install-missing"; } >&2
  return 1
fi

. "$(dirname "${BASH_SOURCE[0]}")/project-main.sh"
pp_main_resolve || { echo "paths.sh: no project here: no git checkout found (tried: $PP_TRIED); run it in the project, or set COMMANDECK_MAIN" >&2
  return 1; }
PP_MAIN_SLUG=$(pp_slug "$PP_MAIN")
# Issue 309: the same checkout as the physical path, for a ruling logged under that spelling (/private/tmp for /tmp).
PP_MAIN_P=$(cd "$PP_MAIN" 2>/dev/null && pwd -P) || PP_MAIN_P=$PP_MAIN
PP_WORKSPACES_SLUG=$(pp_slug "$PP_WORKSPACES")
PP_SCRATCH=${COMMANDECK_SCRATCH:-$HOME/.commandeck/scratch/$PP_MAIN_SLUG}
# The Orca run this project's orchestrator is bound to; board.sh is its one
# writer. Never Orca's ~/.config/orca/current-run: every project on the machine
# shares that file. hooks/lib/project.sh pp_run_file spells the same path.
PP_RUN_FILE=$PP_SCRATCH/current-run
# pp_owed_clear <time> -- removes $PP_SCRATCH/cos-owed, the owner's message main owes the relay a reply to, when it was
# marked before <time>. to-main.sh writes the mark under cos-owed.lock, and this holds that lock from its read to its
# removal: a newer mark written between the two was removed with the old one. cos-watch-inbox.sh takes it too.
pp_owed_clear() {
  local at
  { flock -w 10 9 && IFS=$'\t' read -r at _ < "$PP_SCRATCH/cos-owed" && [ "$at" -lt "$1" ] && rm -f "$PP_SCRATCH/cos-owed"; } 9>>"$PP_SCRATCH/cos-owed.lock" 2>/dev/null
}
export PP_MAIN PP_MAIN_P PP_WORKSPACES PP_MAIN_SLUG PP_WORKSPACES_SLUG PP_SCRATCH
PP_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The same path as one shell word, for a command that is printed to be run.
PP_SCRIPTS_Q=$(printf '%q' "$PP_SCRIPTS")
# The project rules a Builder never loads (worktree-setup.sh --builder excludes them; every worker
# excludes the first).
PP_BUILDER_RULES_OFF="orchestration agents planning adversarial-reviews worktree-sessions"
# Issue 397: the standing helper line a plan-author prompt and a fix-round hand-off carry; the Builder brief template holds it word for word.
PP_HELPER_LINE="Use helper subagents wherever the work allows: general-purpose (runs on the configured Sonnet model) for independent build cuts, research and test writing, Explore (runs on the configured Haiku model) for search and proof; this pane keeps only cut ordering, cross-cut contracts and final integration. For a search, a trace or a second opinion you may also ask Codex, read-only: bash <plugin scripts>/codex-ask.sh '<question>' (it cannot edit; writing stays with Sonnet helpers)."

# A part brief's `Review base:` sha is rewritten by any rebase, and
# review-round.sh refuses a base that is not an ancestor of HEAD. Count before
# the rebase, restore after: the base keeps its distance below the tip.
# ponytail: a commit the rebase drops as already upstream shifts it by one;
# review-round.sh still refuses loudly.
pp_review_base_count() {  # <worktree> <brief file>; prints nothing without a base
  local b; b=$(sed -n 's/^Review base: `\{0,1\}\([0-9a-f]\{7,40\}\)`\{0,1\}.*/\1/p' "$2" 2>/dev/null | head -1)
  [ -z "$b" ] || git -C "$1" rev-list --count "$b..HEAD"
}
pp_review_base_restore() {  # <worktree> <brief file> <count from pp_review_base_count>
  [ -n "${3:-}" ] || return 0
  sed -i.bak "s/^Review base: .*/Review base: \`$(git -C "$1" rev-parse --short=8 "HEAD~$3")\`/" "$2" && rm -f "$2.bak"
}

# pp_session_log <worktree> -- the worktree's newest Claude session record, or nothing.
# pp_session_log_at <worktree> -- the epoch that record was last written, or null: a seat in one long model
# turn writes it while its event log shows nothing, so the dashboard and main-watch.sh both read it.
pp_session_log() { ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$1")"/*.jsonl 2>/dev/null | head -1; }
pp_session_log_at() {
  local f
  f=$(pp_session_log "$1")
  [ -n "$f" ] && stat -c %Y "$f" 2>/dev/null || echo null
}
# pp_session_bg_open <worktree> -- how many background shell jobs the newest session record started (a tool result's
# toolUseResult.backgroundTaskId) and holds no <task-notification> or successful TaskStop for, or null with no record (issue 203). A background
# call ends at once in the event log, so a Builder idle while its job runs is working, not QUIET; the notification row is
# the job's own completion, whatever its status. A notification quoted in the record can only clear a job, which lets
# QUIET fire, never hide it.
pp_session_bg_open() {
  local f
  f=$(pp_session_log "$1")
  [ -n "$f" ] || { echo null; return; }
  comm -23 \
    <(grep -F backgroundTaskId "$f" | jq -Rr 'fromjson? | .toolUseResult | objects | .backgroundTaskId | strings' 2>/dev/null | sort -u) \
    <({ grep -F '<task-notification>' "$f" | grep -o '<task-id>[A-Za-z0-9_-]*</task-id>' | sed 's/<[^>]*>//g'
        # A TaskStop sends no notification: its successful result ends the job, as read-verdict.sh reads it.
        grep -F 'Successfully stopped' "$f" | jq -Rr 'fromjson? | select(.message.content | tostring | contains("Successfully stopped"))
          | .toolUseResult | objects | .task_id | strings' 2>/dev/null; } | sort -u) | wc -l | tr -d ' '
}
# pp_session_cache <worktree> -- the parent's prompt cache from the last 400 lines of the newest session record, as
# {ttl, ctx, at, ended} or null (issue 203). Main-thread rows only (a helper writes its own subagents/agent-*.jsonl; an
# isSidechain row is skipped). ctx: the newest reply carrying usage, the context the parent's cache holds. at: when that
# reply's request started, the newest user row before its first block (every block repeats message.id): the TTL runs from
# request start, so a reply's end would let a slow reply ping a lapsed cache. No such row in the window is at null, and
# WARM never pings on it. ttl: the newest reply that wrote cache says which one applied (1h tokens 3600, 5m tokens 300).
# ended: the newest assistant or user row is an end_turn reply, so the parent is at its prompt. No usage row, or no
# cache write in the window, is null, and null means no ping. An optional second argument names the session log to
# read instead of the newest one (issue 445: a fix round reads the log of the session live in the Builder's own pane,
# never another session's newer transcript).
pp_session_cache() {
  local f
  f=${2:-$(pp_session_log "$1")}
  [ -n "$f" ] && [ -f "$f" ] || { echo null; return; }
  tail -n 400 "$f" | jq -cRn '
    def ep: sub("\\.[0-9]+"; "") | fromdateiso8601;
    def rk: .message.id // .uuid // .timestamp;
    [inputs | fromjson? | objects | select(.isSidechain != true and (.type == "assistant" or .type == "user"))] as $rows
    | [$rows[] | select(.type == "assistant" and .message.usage != null)] as $rep
    | ([$rep[] | select((.message.usage.cache_creation_input_tokens // 0) > 0)] | last) as $w
    | ($w.message.usage.cache_creation // {}) as $c
    | (if ($c.ephemeral_1h_input_tokens // 0) > 0 then 3600 elif ($c.ephemeral_5m_input_tokens // 0) > 0 then 300 else null end) as $ttl
    | ($rep | last) as $n
    | if $ttl == null or $n == null then null
      else ($n | rk) as $k
      | ([range($rows | length) | select($rows[.] | .type == "assistant" and rk == $k)] | first) as $i
      | {ttl: $ttl,
         ctx: (($n.message.usage.input_tokens // 0) + ($n.message.usage.cache_read_input_tokens // 0) + ($n.message.usage.cache_creation_input_tokens // 0)),
         at: ([$rows[:$i][] | select(.type == "user" and .timestamp != null)] | last | .timestamp | if . then ep else null end),
         ended: ($rows | last | .type == "assistant" and .message.stop_reason == "end_turn")}
      end' 2>/dev/null || echo null
}

# pp_session_summary <worktree> -- what pp_session_log, pp_session_log_at, pp_session_bg_open and pp_session_cache give,
# in one read, for a reader that asks every cycle (issue 299): sets PP_SESSION_LOG (the record, or empty), PP_SESSION_AT,
# PP_SESSION_BG and PP_SESSION_CACHE (each null with no record). The record is read from the offset the last call
# stopped at; the jobs started and ended and the cache's running values are kept per record path in
# ${CACHE:-$PP_SCRATCH}/session-summary.json, so a job opened hours ago still counts. A record that shrank is read from
# its start, a path no longer there drops, a state that does not parse is a cold start, and a half-written last line
# waits for the next call. Sets globals: call it in the current shell.
# shortcut: the cache values come from the whole record, not pp_session_cache's last 400 lines, so a cache write or a
# request start more than 400 lines back has its value here and null there; drop the window there if the two must agree.
pp_session_summary() {
  PP_SESSION_LOG=$(pp_session_log "$1") PP_SESSION_AT=null PP_SESSION_BG=null PP_SESSION_CACHE=null
  [ -n "$PP_SESSION_LOG" ] || return 0
  local out
  out=$(python3 - "${CACHE:-$PP_SCRATCH}/session-summary.json" "$PP_SESSION_LOG" <<'PY'
import calendar, json, os, re, sys, time
state_path, path = sys.argv[1:3]
try:
    with open(state_path) as f:
        held = json.load(f)
    if held["version"] != 1 or not isinstance(held["records"], dict):
        raise ValueError("another version")
except (OSError, ValueError, KeyError, TypeError):
    held = {"version": 1, "records": {}}
records = {p: e for p, e in held["records"].items() if os.path.exists(p)}
# c: the cache's running values, as pp_session_cache reads them: ttl of the newest reply that wrote cache; the newest
# reply with usage (ctx, at); the newest assistant row's key and the user row before its first block; the newest
# user row's time; whether the newest assistant or user row is an end_turn reply.
COLD = {"ttl": None, "ctx": None, "at": None, "ak": None, "aat": None, "uat": None, "ended": False}
try:
    e = records[path]
    off, started, ended, c = e["off"], set(e["started"]), set(e["ended"]), dict(COLD, **e["cache"])
    if not isinstance(off, int):
        raise TypeError("offset")
except (KeyError, TypeError, ValueError, AttributeError):
    off, started, ended, c = 0, set(), set(), dict(COLD)
alt = lambda *v: next((x for x in v if x is not None and x is not False), None)  # jq's //
def ep(s):
    return calendar.timegm(time.strptime(re.sub(r"\.[0-9]+", "", s, count=1), "%Y-%m-%dT%H:%M:%SZ"))
try:
    st = os.stat(path)
    if st.st_size < off:
        off, started, ended, c = 0, set(), set(), dict(COLD)
    with open(path, "rb") as f:
        f.seek(off)
        for line in f:
            if not line.endswith(b"\n"):
                break
            off += len(line)
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if not isinstance(r, dict):
                continue
            m = r.get("message") if isinstance(r.get("message"), dict) else {}
            t = r.get("toolUseResult") if isinstance(r.get("toolUseResult"), dict) else {}
            if b"backgroundTaskId" in line and isinstance(t.get("backgroundTaskId"), str):
                started.add(t["backgroundTaskId"])
            if b"<task-notification>" in line:
                ended.update(x.decode() for x in re.findall(rb"<task-id>([A-Za-z0-9_-]*)</task-id>", line))
            # A TaskStop sends no notification: its successful result ends the job, as read-verdict.sh reads it.
            if b"Successfully stopped" in line and isinstance(t.get("task_id"), str):
                body = m.get("content")
                if "Successfully stopped" in (body if isinstance(body, str) else json.dumps(body)):
                    ended.add(t["task_id"])
            if r.get("isSidechain") is True or r.get("type") not in ("assistant", "user"):
                continue
            if r["type"] == "user":
                c["ended"] = False
                if r.get("timestamp") is not None:
                    c["uat"] = r["timestamp"]
                continue
            k = alt(m.get("id"), r.get("uuid"), r.get("timestamp"))
            if k != c["ak"]:
                c["ak"], c["aat"] = k, c["uat"]
            c["ended"] = m.get("stop_reason") == "end_turn"
            u = m.get("usage")
            if u is None:
                continue
            u = u if isinstance(u, dict) else {}
            if (u.get("cache_creation_input_tokens") or 0) > 0:
                w = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else {}
                c["ttl"] = 3600 if (w.get("ephemeral_1h_input_tokens") or 0) > 0 else 300 if (w.get("ephemeral_5m_input_tokens") or 0) > 0 else None
            c["at"] = c["aat"]
            c["ctx"] = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
except OSError:
    print("null null null")
    sys.exit(0)
records[path] = {"off": off, "started": sorted(started), "ended": sorted(ended), "cache": c}
try:
    tmp = f"{state_path}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump({"version": 1, "records": records}, f)
    os.replace(tmp, state_path)
except OSError:
    pass
try:
    at = None if c["at"] is None else ep(c["at"])
    cache = None if c["ttl"] is None or c["ctx"] is None else {"ttl": c["ttl"], "ctx": c["ctx"], "at": at, "ended": c["ended"]}
except (ValueError, TypeError):
    cache = None
print(int(st.st_mtime), len(started - ended), json.dumps(cache, separators=(",", ":")))
PY
  ) || out='null null null'
  read -r PP_SESSION_AT PP_SESSION_BG PP_SESSION_CACHE <<<"$out"
}

# pp_waited_on <handle> [now] [turn text] -- a `seat.sh wait` watches this pane:
# it is still waiting (its pid, line 1 of $PP_SCRATCH/waiting-<handle>), or under
# 5 minutes ago it saw the marker this turn's text prints on a line of its own
# (`seen <epoch> <marker>`; a warm pane's next marker is a new event). That wait
# is the pane's report, so main-watch.sh and the turn-complete hooks do not wake
# main a second time. The line match is seat.sh wait's own marker_count.
# One wait reports one finish: a caller that names its event (`<who>:<id>`, the
# 4th argument) is refused a marker it already took for another event, so a
# follow-up turn that ends on the same line within the 5 minutes still wakes main.
# Scratch survives a reboot, so the pid alone proves nothing: the file also
# holds the wait's start time (pp_wait_mark), and a pid that is gone or started
# at another time is a stale file, removed here.
pp_wait_mark() { printf '%s\nstart %s\n' "$$" "$(LC_ALL=C ps -o lstart= -p "$$" | xargs)"; }
pp_waited_on() {
  local f=$PP_SCRATCH/waiting-$1 seen at m pid u
  [ -n "$1" ] && [ -f "$f" ] || return 1
  seen=$(sed -n 's/^seen //p' "$f")
  if [ -z "$seen" ]; then
    pid=$(sed -n 1p "$f"); at=$(sed -n 's/^start //p' "$f")
    [ -n "$at" ] && [ "$(LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null | xargs)" = "$at" ] && return 0
    rm -f "$f"; return 1
  fi
  read -r at m <<<"$seen"
  [ -n "$m" ] && [ $(( ${2:-$(date +%s)} - at )) -lt 300 ] \
    && printf '%s\n' "${3:-}" | sed -E 's/^[[:space:]*`•]+//; s/[[:space:]*`"]+$//' | grep -qxF -- "$m" || return 1
  [ -n "${4:-}" ] || return 0
  u=$PP_SCRATCH/waited-$1.${4%%:*}
  [ "$(sed -n 1p "$u" 2>/dev/null)" != "$at" ] || [ "$(sed -n 2p "$u")" = "$4" ] || return 1
  printf '%s\n%s\n' "$at" "$4" > "$u"
}
# Issue 320: a seat's finish has two signs, its marker and its own report; the helpers below read the second.
# pp_seat_record <handle> -- the path of the seat-*.txt record this host launched (no origin=) naming that pane.
pp_seat_record() {
  [ -n "$1" ] && grep -lxF "handle=$1" "$PP_SCRATCH"/seat-*.txt 2>/dev/null | while read -r f; do grep -q '^origin=' "$f" || { echo "$f"; break; }; done | grep .
}
# pp_seat_turn <record> -- read-verdict.sh --state on the seat's session log: state= and prompted=, its latest prompt.
pp_seat_turn() {
  local w l s
  w=$(sed -n 's/^unit=//p; s/^worktree=//p' "$1" | tail -1) l=$(sed -n 's/^launched=//p' "$1" | tail -1)
  s=$(sed -n 's/^spec=//p; s/^tag=//p' "$1" | tail -1)
  PP_FAIL_RE=$PP_FAIL_RE timeout 20 bash "$PP_SCRIPTS/read-verdict.sh" --state --worktree "$PP_WORKSPACES/$w" --launched "${l:-0}" ${s:+--spec "$s"} 2>/dev/null || true
}
# pp_turn_quiet <pp_seat_turn output> [states] -- the reader answered: the turn's state is one of [states] (an ERE
# alternation, default complete) and no background command is live. A fixed list, never a deny-list: any other
# answer, an unknown one or a failed read included, is not finished.
pp_turn_quiet() { grep -qxE "state=(${2:-complete})" <<<"$1" && grep -qx 'outstanding=' <<<"$1"; }
# pp_seat_since <record> [prompted] -- the current episode's start: the seat's latest prompt in its session log (one
# read here when not given), never earlier than its launch. Only with no log read does main-watch's follow-up episode
# stand in for the prompt: an observer's own start (a wait, a tick) never moves it.
pp_seat_since() {
  local h t p; h=$(sed -n 's/^handle=//p' "$1" | tail -1) t=$(sed -n 's/^task=//p' "$1" | tail -1)
  p=${2-$(pp_seat_turn "$1" | sed -n 's/^prompted=//p')}
  { sed -n 's/^launched=//p' "$1"; if [ -n "$p" ]; then echo "$p"; else cat "$PP_SCRATCH/main-watch/episode-seat-$h-$t" 2>/dev/null; fi; echo 0; } \
    | grep -xE '[0-9]+' | sort -n | tail -1
}
# pp_plan_committed <record> [since] -- a plan author's plan, committed after the episode began, differs from the one at launch (planref=),
# and the working plan is that commit: a staged or unstaged edit after it is unfinished work, never certified by it.
pp_plan_committed() {
  local u w b at
  [[ $(sed -n 's/^role=//p' "$1" | tail -1) == plan-author* ]] || return 1
  u=$(sed -n 's/^unit=//p' "$1" | tail -1) w=$(sed -n 's/^worktree=//p' "$1" | tail -1)
  w=$PP_WORKSPACES/${w:-$u}
  b=$(git -C "$w" rev-parse -q --verify "HEAD:.claude/plans/$u.md" 2>/dev/null) && [ "$b" != "$(sed -n 's/^planref=//p' "$1" | tail -1)" ] || return 1
  # The bytes themselves, staged and on disk: git's own diff trusts index flags, fsmonitor and filters (issue 320).
  [ "$(git -C "$w" hash-object --no-filters -- ".claude/plans/$u.md" 2>/dev/null)" = "$b" ] \
    && [ "$(git -C "$w" rev-parse -q --verify ":.claude/plans/$u.md" 2>/dev/null)" = "$b" ] || return 1
  at=$(git -C "$w" log -1 --format=%ct -- ".claude/plans/$u.md" 2>/dev/null) && [ -n "$at" ] && [ "$at" -gt "${2:-$(pp_seat_since "$1")}" ]
}
# pp_seat_done <record> [recipient handle...] -- prints `message` when the seat's own message since its latest prompt,
# to the run, main's live pane (to-main.sh's address) or a recipient (none named: the run's coordinator), is a finish and
# has reached main: its type wakes main (wakeKinds) or it is read. A message to any other pane (a helper's) is no finish.
# `plan-commit` when pp_plan_committed; else `note` for such a finish main has not seen (its delivery is still owed);
# else nothing, exit 1. Only a turn its session log reads complete, with no background
# command live, and not ending on a question or refusal (asked=0), has finished (pp_turn_quiet): a committed plan or a
# 'Plan revised' message is no answer to what the turn asks. A failed read counts as nothing: the caller's alert still fires.
# A finish is a fixed list, never a parse (issue 320): the raw subject starts `Plan written` or
# `Plan revised`, or the whole body, outer whitespace trimmed, is one marker of the list; and no `QUESTION:` or
# `BLOCKED` (PLAN-BLOCKED included) anywhere. The list is a plan author's own markers, PLAN-DONE and <UNIT>-DONE: a
# verdict line is not one. A marker quoted, fenced, decorated or under other text is not a finish: main gets the alert.
pp_seat_done() {
  local r=$1 kv since d; shift
  kv=$(pp_seat_turn "$r"); pp_turn_quiet "$kv" && grep -qx 'asked=0' <<<"$kv" || return 1
  since=$(pp_seat_since "$r" "$(sed -n 's/^prompted=//p' <<<"$kv")")
  d=$(pp_seat_inbox "$r" "$since" "$@")
  # Uncertain is not finished: an inbox that did not answer, a full page (newest first, no paging) that does not reach back
  # to the seat's prompt, or a failure the seat reported (a verdict line of any spelling is no plan finish), vetoes every branch below.
  grep -qx ok <<<"$d" && ! grep -qx fail <<<"$d" || return 1
  grep -qx true <<<"$d" && { echo message; return 0; }
  if pp_plan_committed "$r" "$since"; then echo plan-commit; elif grep -qx false <<<"$d"; then echo note; else return 1; fi
}
# PP_FAIL_RE / pp_failed_text <text> -- the one test for text that asks or reports a failure: a `QUESTION:`, `BLOCKED`
# (PLAN-BLOCKED included) anywhere, or a verdict line of any spelling (a plan author's finish never carries one). Used
# on the seat's final reply (the Stop hook) and on every message it sent (pp_seat_inbox), whoever the message went to.
PP_FAIL_RE='QUESTION:|BLOCKED|(^|\n)[ \t]*\**VERDICT:'
pp_failed_text() { jq -Rse --arg re "$PP_FAIL_RE" 'test($re)' <<<"$1" >/dev/null 2>&1; }
# pp_wake_log <from> <to> <reason> <result> [error] -- one JSON line per attempt to wake main or the relay, appended to
# $PP_SCRATCH/wake-log.jsonl by every waker. Results: turn_started, no_turn (typed, no turn), sent (inbox mail Orca took),
# sent_blocked (sent, but the pane shows an open prompt), refused, queued, no_pane, unreadable (screen read failed), blocked
# (open prompt, nothing typed), held (Orca's own nudge holds the claim; not a failure), gave_up, woke (a waiter exited with
# items). Past 1 MiB the file moves to .1 (one kept). Never fails its caller: a log that cannot be written is no reason to
# stop a wake.
pp_wake_log() {
  local f=$PP_SCRATCH/wake-log.jsonl
  mkdir -p "$PP_SCRATCH" 2>/dev/null || return 0
  [ ! -e "$f" ] || [ "$(wc -c < "$f")" -le 1048576 ] || mv -f "$f" "$f.1" 2>/dev/null
  jq -nc --arg at "$(date -u +%FT%TZ)" --arg from "$1" --arg to "$2" --arg reason "$3" --arg result "$4" --arg error "${5:-}" \
    '{at: $at, from: $from, to: $to, reason: $reason, result: $result, error: $error}' >> "$f" 2>/dev/null || true
  return 0
}
# pp_worker_done_since <handle> <epoch> -- did pane <handle> report to main after <epoch>? Reads `orchestration inbox
# --json` on stdin: a worker_done from that handle. Orca files a worker_done only once it accepts it, so a refused send,
# another message type or another pane's report proves nothing. An unreadable inbox answers no. Orca stamps whole
# seconds, so only a later second is proof: one from <epoch>'s own second may predate it.
# Callers: main-watch.sh reported(), claude-worker-notify.sh.
pp_worker_done_since() {
  jq -e --arg h "$1" --argjson s "$2" '.result.messages | any(.[]?;
      ((.created_at // "" | sub("\\.[0-9]+"; "") | fromdateiso8601?) // 0) > $s
      and .type == "worker_done" and .from_handle == $h)' >/dev/null 2>&1
}
# pp_seat_log <worktree> <session> -- the seat's session log, when it exists: a Claude session id is looked up in the
# config folder's projects/<worktree slug>/, a path (a Codex log seat.sh bound) is the log itself. Empty for none.
# main-watch.sh grew_at and seat.sh collect both name the log through this, so their delivery receipts agree.
pp_seat_log() {
  local f
  case ${2:-} in '') return 0 ;; /*) f=$2 ;; *) f=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(pp_slug "$1")/$2.jsonl ;; esac
  [ ! -f "$f" ] || printf '%s' "$f"
}
# pp_seat_clear <record> [recipient handle...] -- succeeds when the inbox answered in full and the seat reported no
# failure since its prompt: the one test pp_seat_done and the Stop hook's PLAN-DONE request share.
pp_seat_clear() {
  local r=$1 d; shift
  d=$(pp_seat_inbox "$r" "$(pp_seat_since "$r" "$(pp_seat_turn "$r" | sed -n 's/^prompted=//p')")" "$@")
  grep -qx ok <<<"$d" && ! grep -qx fail <<<"$d"
}
# pp_seat_inbox <record> <since> [recipient handle...] -- the seat's own inbox lines since <since>: `ok` once the inbox
# answered in full; `fail` for a message of the seat's that asks or reports a failure, to anyone; else one line per finish
# sent to the run or a recipient: true when it reached main.
pp_seat_inbox() {
  local r=$1 since=$2 h u run k; shift 2
  h=$(sed -n 's/^handle=//p' "$r" | tail -1) u=$(sed -n 's/^unit=//p' "$r" | tail -1)
  [ -n "$h" ] || return 1
  run=${COMMANDECK_RUN:-$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")}
  [ $# -gt 0 ] || set -- "$(pp_run_coord "$run")"
  k=$(pp_option wakeKinds) || k=
  timeout 10 orca-ide orchestration inbox --limit 500 --json 2>/dev/null | jq -r --arg h "$h" --argjson s "$since" --arg k "$k" --arg fre "$PP_FAIL_RE" \
    --argjson to "$(printf '%s\n' "${run:+run:$run}" "$(pp_seat_pane main "$PP_MAIN")" "$@" | jq -Rsc 'split("\n") | map(select(. != "" and . != "?"))')" \
    --argjson done "$(jq -nc --arg u "${u^^}-DONE" '["PLAN-DONE", $u]')" "$PP_JQ_WAKES"'
    def at: (.created_at // "") | sub("\\.[0-9]+"; "") | fromdateiso8601? // 0;
    (if (.result.messages | type) == "array" and ((.result.messages | length) < 500 or any(.result.messages[]; at <= $s)) then "ok" else empty end),
    (.result.messages[]? | select(.from_handle == $h and at > $s)
    | (.subject // "") as $sub | (.body // "" | gsub("^\\s+|\\s+$"; "")) as $b
    | if "\($sub)\n\($b)" | test($fre) then "fail"
      elif (.to_handle as $t | any($to[]; . == $t)) and (($sub | test("^plan (written|revised)"; "i")) or any($done[]; . == $b))
        then (.read // 0) != 0 or wakes($k | split(","); [])
      else empty end)' 2>/dev/null
}
# pp_run_coord <run> -- the run's coordinator handle (empty when the run has none); fails when the run list does not answer.
pp_run_coord() {
  orca-ide orchestration run-list --json 2>/dev/null | jq -er --arg r "$1" \
    '.result.runs | if type == "array" then (first(.[] | select(.id == $r) | .coordinator_handle) // "") else error end' 2>/dev/null
}
# pp_sender [handle...] -- the --from a send needs (Orca refuses one it cannot attribute): the first non-empty argument,
# this pane's own handle, main's live pane, or the run's live coordinator. Nothing, exit 1, when none: a service has no pane.
pp_sender() {
  local h
  for h in "$@" "${ORCA_TERMINAL_HANDLE:-}"; do [ -z "$h" ] || { echo "$h"; return 0; }; done
  h=$(pp_seat_pane main "$PP_MAIN"); [ -z "$h" ] || { echo "$h"; return 0; }
  h=$(pp_run_coord "$(tr -d '[:space:]' 2>/dev/null < "$PP_RUN_FILE")") && [ -n "$h" ] || return 1
  timeout 10 orca-ide terminal list --json 2>/dev/null | jq -e --arg h "$h" '[(.result | if type == "array" then . else (.terminals // []) end)[]?
    | select(.handle == $h and .connected != false and .orphaned != true)] | length > 0' >/dev/null 2>&1 && echo "$h"
}

# pp_main_foreground -- true in main's own foreground: the main checkout, a terminal or a Claude session, and not a
# child of pp_detach or of run-shell-tests.sh (COMMANDECK_FOREGROUND). pp_detach <log> <label> <cmd>... runs the
# command detached with its output in <log>, prints the pid and the log, and sends main the result as a question
# (issue 230): a merge or a full suite takes minutes, and main's turn waited on it. A question, not a status: it is the
# only word of that result, and a status is held until the next wake (issue 318).
pp_main_foreground() {
  [ -z "${COMMANDECK_FOREGROUND:-}" ] && { [ -t 0 ] || [ -n "${CLAUDECODE:-}" ]; } \
    && [ "$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)" = "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ]
}
pp_detach() {
  local log=$1 label=$2; shift 2
  mkdir -p "${log%/*}" || return 1
  COMMANDECK_FOREGROUND=1 nohup bash -c 'log=$1 label=$2; shift 2; "$@" > "$log" 2>&1; rc=$?
    bash "$0" question "$label: exit $rc" "$(tail -n 5 "$log")" >/dev/null 2>&1' "$PP_SCRIPTS/to-main.sh" "$log" "$label" "$@" </dev/null >/dev/null 2>&1 &
  echo "$label: running detached as pid $!; watch $log. Its result comes to main as a message; wait for it, never run it again (issue 317)."
}
# Issue 317: the merge's state sits beside its lock in main's git dir. merge-unit-local.state is written while one merge
# holds main (unit, sha: the unit's tip when asked, tip: after its rebase, pid, started, stage, main, log), and
# merge-unit-local.queue/<unit>@<sha> holds the pid of each request waiting on the lock. A pid that is gone makes
# either stale: it blocks nothing.
# shortcut: a pid the system gave to another process since reads as live; rare, and the next merge replaces the file.
# pp_merge_active <unit> <sha> [--register] -- 0, printing where it stands, when <unit> at <sha> is the running merge
# or waits on the lock. With --register a request that is not yet there is entered in the queue under this shell's pid
# and the answer is 1: the caller goes on to the lock. Registrations take the queue's .lock one at a time, from the read
# to the entry: two that found the same stale entry would each remove the other's. A lock still busy after 10 s (or
# a queue folder that cannot be made) answers 2 and enters nothing: the lock's owner could register between an
# unlocked read and write, and an unentered request is no duplicate anyone sees.
pp_merge_active() {
  local u=$1 sha=$2 d s q pid
  d=$(git -C "$PP_MAIN" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  s=$d/merge-unit-local.state q=$d/merge-unit-local.queue/$u@$sha
  if [ "${3:-}" = --register ]; then
    mkdir -p "${q%/*}" || return 2
    { flock -w 10 9 || return 2
      pp_merge_active "$u" "$sha" && return 0; echo $$ > "$q"; return 1; } 9>>"${q%/*}/.lock"
  fi
  # The queue before the state: a merge writes its state before it leaves the queue, so one of the two names it.
  if pid=$(cat "$q" 2>/dev/null) && kill -0 "$pid" 2>/dev/null; then echo "$u at ${sha:0:8} is already queued behind the running merge (pid $pid)"; return 0; fi
  if [ "$(sed -n 's/^unit=//p' "$s" 2>/dev/null)" = "$u" ] && pid=$(sed -n 's/^pid=//p' "$s") && kill -0 "$pid" 2>/dev/null \
     && { [ "$(sed -n 's/^sha=//p' "$s")" = "$sha" ] || [ "$(sed -n 's/^tip=//p' "$s")" = "$sha" ]; }; then
    echo "$u at ${sha:0:8} is already merging (pid $pid, stage $(sed -n 's/^stage=//p' "$s"); log $(sed -n 's/^log=//p' "$s"))"; return 0
  fi
  return 1
}
# pp_inbox_actionable <run> [main's handle] -- issue 318: main's unread messages whose type wakes it (wakeKinds), as one
# JSON array, oldest first. Both forms that reach main count: the run, and main's terminal handle (to-main.sh's). Any
# sender: main-watch and pp_detach send from main's own handle. Fails when Orca does not answer in 10 s, or the page is
# full (the inbox is the whole machine's, newest first): the caller then wakes.
pp_inbox_actionable() {
  local k; k=$(pp_option wakeKinds) || return 1
  timeout 10 orca-ide orchestration inbox --limit 500 --json 2>/dev/null | jq -ec --arg r "run:$1" --arg h "${2:-}" --arg k "$k" \
    --argjson relay "$(pp_relay_handles)" "$PP_JQ_WAKES"'($k | split(",")) as $k
    | .result.messages | if type == "array" and length < 500 then [.[] | select(.read == 0 and (.to_handle == $r or ($h != "" and .to_handle == $h))
      and wakes($k; $relay))] | sort_by(.created_at // "") else error end' 2>/dev/null
}
# pp_owner_bound -- issue 305: the text of a question on stdin names the owner or is a repeat-class stop-and-ask: it goes on
# the owner's decision queue, not behind main's read. orca-wait.sh (main's drain) and cos-watch-inbox.sh (the relay's poll) both ask.
pp_owner_bound() { grep -qiE 'owner|repeat.class|stop.and.ask'; }
# Issue 324: the relay's (Chief-of-Staff's) messages always wake main and always print, whatever their type, with or
# without a ruling id, and whatever wakeKinds says. The relay is its pane, any pane in $PP_WORKSPACES/Chief-of-Staff,
# never a sender name. pp_relay_handles -- those panes' handles as a JSON array; [] when Orca does not answer.
pp_relay_handles() {
  timeout 10 orca-ide terminal list --json 2>/dev/null | jq -c --arg p "$PP_WORKSPACES/Chief-of-Staff" "$PP_PNORM"'($p | pnorm) as $p
    | [(.result | if type == "array" then . else (.terminals // []) end)[]? | select((wtp | pnorm) == $p) | .handle]' 2>/dev/null | grep . || echo '[]'
}
# PP_JQ_WAKES -- the one wake test pp_inbox_actionable and orca-wait.sh share: wakes($kinds; $relay) holds for a
# wakeKinds type, or for a message from a relay pane (pp_relay_handles); never for a heartbeat, which the drain
# neither prints nor keeps.
PP_JQ_WAKES='def wakes($k; $relay): (.type // "") as $t | $t != "heartbeat" and (any($k[]; . == $t) or ((.from_handle // "") as $f | any($relay[]; . == $f)));'
# pp_wake_window_open <pp_inbox_actionable array> <now> -- true while its oldest message is younger than
# wakeWindowSeconds: what arrives meanwhile wakes main once, when the window closes. A time it cannot read is past.
pp_wake_window_open() {
  local w; w=$(pp_option wakeWindowSeconds) || return 1
  jq -e --argjson now "$2" --argjson w "$w" 'length > 0 and ($now - (.[0].created_at // "" | sub("\\.[0-9]+"; "")
    | try fromdateiso8601 catch 0)) < $w' <<<"$1" >/dev/null 2>&1
}
# pp_wake_claim <now> -- issue 318: main's one wake per window, taken by Orca's nudge (cos-own-echo.sh) and
# main-watch's typed wake alike, so the two cannot both start a turn for the same messages: true, and the claim is
# <now>, unless the last is younger than wakeWindowSeconds. Anything that fails takes the wake. Only this and
# pp_wake_release change the claim, both under its lock.
pp_wake_claim() {
  local w at f=$PP_SCRATCH/main-watch/unread-since
  w=$(pp_option wakeWindowSeconds) && mkdir -p "${f%/*}" || return 0
  { flock -w 10 9 || return 0
    at=$(cat "$f" 2>/dev/null); ! [[ $at =~ ^[0-9]+$ ]] || [ $(($1 - at)) -ge "$w" ] || return 1
    echo "$1" > "$f"; } 9>>"$f.lock"
}
# pp_wake_release <at> -- give back the claim pp_wake_claim took at <at> (a wake that started no turn), only while it
# is still that one: a nudge may have taken a newer one while the wake waited for its receipt.
pp_wake_release() {
  local f=$PP_SCRATCH/main-watch/unread-since
  { flock -w 10 9 || return 0
    [ "$(cat "$f" 2>/dev/null)" != "$1" ] || rm -f "$f"; } 9>>"$f.lock"
}
# pp_close_items <handle>... -- complete main-watch's open item task of each of these seats (issue 227): the
# script that handled the item (a merge, an answer, a collect) closes it, as main did by hand. A close that fails
# is said and costs nothing else.
pp_close_items() {
  local h f t
  for h in "$@"; do
    for f in "$PP_SCRATCH/main-watch"/item-*seat-"$h"-*; do
      [ -f "$f" ] && ! grep -qx handled "$f" || continue
      t=$(sed -n 's/^task=//p' "$f"); [ -n "$t" ] && [ "$t" != none ] || continue
      ! pp_task_close "$t" completed || echo "closed main-watch item task $t"
    done
  done
  return 0
}
# pp_open_ask <handle> <task ids> <since epoch> [<other ids>] -- does the seat hold any question since <since> (its
# launch: an older one is another episode) still unanswered (host issue 2998)? 0 open (the oldest such id in
# PP_OPEN_ASK_ID), 1 none open, 2 cannot tell: the inbox or a row in it cannot be read, or the read stops at the row
# limit before reaching back to <since> with no open question in it, so one may lie past the cut.
# A question is a `question` that opens its own thread (Orca leaves thread_id null on one) whose sender
# (`dispatch:<id>` for `orchestration ask` under a dispatch), payload taskId or payload dispatchId is ANY id the seat
# holds: the handle, the task ids, the other ids (earlier panes, dispatch ids); ids are space-separated. It is answered
# ONLY by a reply in its own thread, which answer-worker.sh posts once given the question's id. EVERY question counts,
# not a chosen one, and no transcript is read: a question answered another way keeps its task unsettled, loudly.
pp_open_ask() {
  local in
  in=$(orca-ide orchestration inbox --limit 5000 --json 2>/dev/null) || return 2
  PP_OPEN_ASK_ID=$(jq -er --arg ids "$1 $2 ${4:-}" --argjson s "${3:-0}" '
    def ep: .created_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    def pl: ((.payload // "{}") | fromjson? // {});
    [$ids | splits("\\s+") | select(. != "") | ., "dispatch:" + .] as $ids
    | .result.messages as $m | if ($m | type) != "array" then error else
    [$m[] | select(.type == "question" and (.thread_id // .id) == .id and ep >= $s
        and any(.from_handle, pl.taskId, pl.dispatchId; IN($ids[])))
      | . as $q | select(any($m[]; .id != $q.id and .thread_id == $q.id) | not)] as $open
    | if $open != [] then ($open | min_by(ep) | .id)
      elif ($m | length) >= 5000 and ([$m[] | ep] | min) >= $s then error
      else "none" end end' <<<"$in" 2>/dev/null) || return 2
  [ "$PP_OPEN_ASK_ID" != none ]
}
# pp_seat_open_ask <handle> <seat record> -- pp_open_ask over every id the seat record holds: its pane, earlier panes
# (prior_pane=), every task (task=, answer_task=), each task's dispatch id, and the seat's launch (launched=). The one
# place that says which questions count, shared by pp_task_close and answer-worker.sh (issue 351) so the answer and the
# task close agree. Returns pp_open_ask's code; a dispatch read that fails or is unshaped is 2, "cannot tell".
pp_seat_open_ask() {
  local tasks other t d
  tasks=$(sed -n 's/^\(answer_\)\{0,1\}task=//p' "$2"); other=$(sed -n 's/^prior_pane=//p' "$2")
  for t in $tasks; do
    # A task with no dispatch reads null.
    d=$(orca-ide orchestration dispatch-show --task "$t" --json 2>/dev/null \
      | jq -er '.result | if has("dispatch") then .dispatch.id // "" else error end' 2>/dev/null) || return 2
    other+=" $d"
  done
  pp_open_ask "$1" "$tasks" "$(sed -n 's/^launched=\([0-9][0-9]*\)$/\1/p' "$2" | head -1)" "$other"
}
# Close an Orca task whose work has SETTLED. While the task's supervised
# dispatch is active Orca refuses (task_not_startable), and a warm pane with an
# active dispatch refuses the next one, so the dispatch is settled with
# worker-abandon (no process or filesystem action; the pane keeps its context),
# then worker-release, and the close retried once. Abandoned but unreleased, the
# pane still refused the next dispatch; release never closes a pane we opened
# ourselves, only one Orca created. Never for a worker still working: abandon fences it.
pp_task_close() { # task status [result-json]
  local args=(--id "$1" --status "$2" --json) out d h rec busy ask=
  [ -z "${3:-}" ] || args+=(--result "$3")
  # A live dispatch is never settled under its pane (host issue 2998). The pane is the seat record's handle for this
  # task, by `task=` or by `answer_task=` (an answer sent by dispatch). Settling needs every check READ clear: the pane
  # idle (pane_is_busy 1) and no open question since the seat's launch (pp_open_ask 1) from ANY id the record holds:
  # its pane, earlier panes (prior_pane=), every task, and each task's dispatch. Working, an open question and any
  # check that could not be read (pane state, a dispatch, the inbox) all refuse. A task with no record takes the path
  # below as before.
  read -r h rec < <(awk -F= -v t="$1" 'FNR==1{h=""} /^handle=/{h=$2} /^(answer_)?task=/ && h && $2==t {print h, FILENAME; exit}' "$PP_SCRATCH"/seat-*.txt 2>/dev/null) || true
  if [ -n "$h" ]; then
    busy=0; ( . "$PP_SCRIPTS/codex-helpers.sh" && pane_is_busy "$h" ) || busy=$?
    if [ "$busy" = 1 ]; then ask=0; pp_seat_open_ask "$h" "$rec" || ask=$?; fi
    if [ "$ask" = 0 ]; then
      echo "task $1: its pane $h has open question $PP_OPEN_ASK_ID; answer it with bash $PP_SCRIPTS/answer-worker.sh $h \"<text>\" $PP_OPEN_ASK_ID (or reply in its thread); not settled" >&2
      return 1
    elif [ "$busy" != 1 ] || [ "$ask" != 1 ]; then
      echo "task $1: its pane $h is working or could not be read (pane state, a dispatch or inbox); not settled" >&2
      return 1
    fi
  fi
  out=$(orca-ide orchestration task-update "${args[@]}" 2>&1 || true)
  jq -e '.ok' <<<"$out" >/dev/null 2>&1 && return 0
  # A driver's own launchd/systemd terminal holds no run binding; act as the
  # handle run-bound.sh names (the same rebind close-round.sh does) and retry.
  if grep -q run_required <<<"$out" && h=$("$PP_SCRIPTS/run-bound.sh"); then
    export ORCA_TERMINAL_HANDLE=$h
    out=$(orca-ide orchestration task-update "${args[@]}" 2>&1 || true)
    jq -e '.ok' <<<"$out" >/dev/null 2>&1 && return 0
  fi
  if grep -q task_not_startable <<<"$out"; then
    d=$(orca-ide orchestration dispatch-show --task "$1" --json 2>/dev/null | jq -r '.result.dispatch.id // empty' 2>/dev/null || true)
    if [ -n "$d" ] && orca-ide orchestration worker-abandon --dispatch "$d" --json >/dev/null 2>&1 \
      && jq -e '.ok' <<<"$(orca-ide orchestration worker-release --dispatch "$d" --json 2>/dev/null)" >/dev/null 2>&1; then
      out=$(orca-ide orchestration task-update "${args[@]}" 2>&1 || true)
      jq -e '.ok' <<<"$out" >/dev/null 2>&1 && return 0
    fi
  fi
  d=$(jq -r '.error | select(.) | "\(.code): \(.message)"' <<<"$out" 2>/dev/null || true)
  echo "could not close task $1 ($2): ${d:-${out:-no answer from orca-ide}}" >&2
  return 1
}
# Every script close of an agent pane goes through here (host issue 3009: panes vanished and nobody could say who closed
# them). One tab-separated line lands in $PP_SCRATCH/pane-closes.log: UTC time, handle, the calling script, the
# cause, then `ok` or `refused: <Orca's answer>`. A pane closed by hand, the Orca UI or Orca itself is not in the
# log. Orca can refuse a close with exit 0, so only `.ok == true` counts; the answer is left in PP_CLOSE_RES for the
# caller's own message. A failed log write never blocks or fakes the close.
pp_pane_close() { # <handle> <cause>
  local rc=1
  PP_CLOSE_RES=$(timeout 20 orca-ide terminal close --terminal "$1" --json 2>&1) && jq -e '.ok == true' <<<"$PP_CLOSE_RES" >/dev/null 2>&1 && rc=0
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${0##*/}" "$2" \
    "$([ "$rc" = 0 ] && echo ok || echo "refused: $(printf %s "$PP_CLOSE_RES" | tr '\n\t' '  ' | cut -c1-200)")" >> "$PP_SCRATCH/pane-closes.log" 2>/dev/null || true
  return $rc
}
# pp_worktree_panes <worktree> -- the handles of the panes Orca lists in <worktree>, one a line, matched by wtp (any
# of the three fields Orca names a worktree in). Non-zero when the listing cannot be read: a failed call, an empty
# answer, or one that is not a terminal list. A caller that deletes on "no pane" reads it again after its closes.
pp_worktree_panes() {
  local out; out=$(timeout 10 orca-ide terminal list --json 2>/dev/null) \
    && jq -e . <<<"$out" >/dev/null 2>&1 && jq -r --arg wt "$1" "$PP_PNORM"'($wt | pnorm) as $wt | (.result | if type == "array" then . elif (.terminals | type) == "array" then .terminals else error("not a terminal list") end)[]
      | select((wtp | pnorm) == $wt) | .handle' <<<"$out" 2>/dev/null
}

# A pane waiting on a person: Claude's and Codex's permission and approval
# prompts, and Claude's AskUserQuestion picker. Nothing is ever typed into one
# (unit-loop.sh's stall nudge, main-watch.sh's wake).
PROMPT_BLOCKED='Do you want to (proceed|make this edit|create|allow)|Would you like to (run|make|allow)|Allow (command|once|this)|Yes, and don.t ask again|requires approval|approve this|Press enter to confirm|Enter to select'

# THE ROUTING READER. config/routing.json is the one home of
# every role's model, effort and launch settings; nothing else names a model.
# Every launch, review, fix, gate and judge resolves its seat here, and every
# call validates the WHOLE file first, so a malformed entry anywhere stops a
# launch before a pane opens. Nothing is read until a caller asks. The file is
# the one beside this script unless COMMANDECK_ROUTING names another. Values are
# checked against a safe character set and quoted for the pane's shell; no
# configuration text is ever evaluated.
pp_routing() { printf '%s\n' "${COMMANDECK_ROUTING:-$PP_SCRIPTS/../config/routing.json}"; }
PP_ROUTE_JQ='
def fail($m): error("routing: " + $m);
def efforts: ["low", "medium", "high", "xhigh", "max"];
def wiring: ["claude", "codex", "exec", "-p"];
def slot: {model: "model", context: "model", effort: "effort", fast: "fast", advisor: "advisor", tools: "tools",
  memory: "env", reviewer: "env", codexHome: "env", compactLimit: "compact", sandbox: "sandbox",
  approval: "approval", network: "network", shellEnv: "shellenv", mcpDisabled: "mcp", disabledSkills: "skills",
  disablePlugins: "plugins", projectDocMaxBytes: "projectdoc"};
def is($re): type == "string" and test($re);
def bool: type == "boolean";
def count: type == "number" and . >= 0 and floor == .;
def template_of: .agent + (if .headless then "-headless" else "" end);
def check_seat($name; $root):
  . as $s
  | if type != "object" then fail("\($name) is not an object") else . end
  | if (.agent | IN("claude", "codex")) | not then fail("\($name).agent must be claude or codex") else . end
  | if .inherit then
      (keys - ["agent", "inherit", "edits", "note"]) as $x
      | if ($x | length) > 0 then fail("\($name) inherits its model, so \($x[0]) has no place on it") else . end
    else
      (keys - (slot | keys) - ["agent", "headless", "unboxed", "edits", "note", "triggers", "role", "claude", "first", "helpers"]) as $x
      | if ($x | length) > 0 then fail("\($name) has unknown field \($x[0])") else . end
      | if (.model | is("^[a-z0-9][a-z0-9._-]*$")) | not then fail("\($name).model is missing or not a model id") else . end
      | if has("effort") | not then fail("\($name).effort must be present (null omits it)") else . end
      | if .effort != null and (.effort | IN(efforts[]) | not) then fail("\($name).effort \(.effort) is not one of \(efforts | join(", "))") else . end
      | if has("context") and .context != "1m" then fail("\($name).context must be 1m") else . end
      | if ([.fast, .reviewer, .network, .disablePlugins, .headless, .unboxed] | map(select(. != null)) | all(bool)) | not then fail("\($name) has a non-boolean switch") else . end
      | if has("memory") and (.memory | is("^[0-9]+[KMGT]?$") | not) then fail("\($name).memory must look like 12G") else . end
      | if has("helpers") and ((.helpers | type) != "object" or (.helpers | to_entries | all(.value | is("^[a-z][a-z0-9.-]*$")) | not)) then fail("\($name) has a bad helpers entry \(if (.helpers | type) == "object" then (.helpers | to_entries | map(select(.value | is("^[a-z][a-z0-9.-]*$") | not))[0].key) else "helpers" end)") else . end
      | if has("advisor") and (.advisor | is("^[a-z0-9][a-z0-9._-]*$") | not) then fail("\($name).advisor is not a model alias") else . end
      | if has("tools") and ((.tools | type) != "array" or (.tools | length) == 0 or (.tools | all(is("^[A-Za-z]+$")) | not)) then fail("\($name).tools must be tool names") else . end
      | if has("codexHome") and (.codexHome | is("^~?/[A-Za-z0-9._/-]+$") | not) then fail("\($name).codexHome must be a path") else . end
      | if has("sandbox") and (.sandbox | IN("read-only", "workspace-write") | not) then fail("\($name).sandbox must be read-only or workspace-write") else . end
      | if has("approval") and (.approval | IN("untrusted", "on-failure", "on-request", "never") | not) then fail("\($name).approval is not a Codex approval policy") else . end
      | if has("shellEnv") and ((.shellEnv | type) != "object" or (.shellEnv | to_entries | all((.key | is("^[A-Z_][A-Z0-9_]*$")) and (.value | is("^[A-Za-z0-9_./:@%+,-]+$"))) | not)) then fail("\($name).shellEnv must map NAMES to plain values") else . end
      | if has("mcpDisabled") and ((.mcpDisabled | type) != "array" or (.mcpDisabled | all(is("^[a-z0-9_-]+$")) | not)) then fail("\($name).mcpDisabled must be server names") else . end
      | if has("disabledSkills") and ($root.launch.skillSets[.disabledSkills] | type) != "array" then fail("\($name).disabledSkills names no launch.skillSets entry") else . end
      | if ([.compactLimit, .projectDocMaxBytes] | map(select(. != null)) | all(count)) | not then fail("\($name) has a limit that is not a whole number") else . end
      | if (.headless or .unboxed or $root.launch.paneBox != null) | not then fail("\($name) is boxed but launch.paneBox is not set; set unboxed: true") else . end
      | if .headless and ([has("memory"), has("reviewer"), has("unboxed")] | any) then fail("\($name) is headless: it has no pane for memory, reviewer or box") else . end
      | ($root.launch.templates[template_of] // fail("\($name): no launch.templates.\(template_of) for its agent")) as $t
      | ($t | [scan("\\{([a-z]+)\\}")[0]]) as $have
      | ([to_entries[] | select(.value != null) | (if .key == "shellEnv" and $s.agent == "claude" then "env" else slot[.key] end) // empty] - $have) as $missing
      | if ($missing | length) > 0 then fail("\($name) sets a {\($missing[0])} setting its \(template_of) template has no place for") else . end
    end;
# The one rule for a template: its placeholders and executable, in order, are
# exactly this sequence. {box} and {env} must precede the executable (after it
# they are arguments to it), and no placeholder may go missing or repeat.
def canonical: {
  claude: "{box} {env} claude {model} {effort} {tools} {advisor} {fast}",
  codex: "{box} {env} codex {compact} {model} {effort} {fast} {sandbox} {approval} {network} {shellenv} {mcp} {skills} {plugins}",
  "claude-headless": "{env} claude {model} {effort} {tools} {fast}",
  "codex-headless": "{env} codex {sandbox} {projectdoc} {model} {effort} {fast}"};
def check_templates:
  (.launch.templates // fail("launch.templates is missing")) | to_entries[]
  | .key as $k | (.value | split(" ") | map(select(. != ""))) as $w
  | (canonical[$k] // fail("launch.templates.\($k) is not a known template")) as $c
  | ($w[] | select(test("^\\{[a-z]+\\}$") or IN(wiring[]) | not)
     | fail("launch.templates.\($k): \(.) is neither a placeholder nor wiring; settings live in role fields"))
  , (if [$w[] | select(test("^\\{[a-z]+\\}$") or IN("claude", "codex"))] != ($c | split(" ")) then fail("launch.templates.\($k) must follow \($c) around its wiring") else empty end);
# The values a role setting takes (issue 312): fixed lists, never the models the rows happen to name. A Codex model is
# a family pp_codex_model resolves, or an exact id (any a seat takes, gpt-5.3-codex-spark included), never a Claude alias.
def claude_models: ["opus", "sonnet", "fable"];
def model_ok($agent):
  if $agent == "claude" then IN(claude_models[]) else is("^[a-z0-9][a-z0-9._-]*$") and (IN(claude_models[], "haiku") | not) end;
# A Claude seat that never writes denies all three writing tools; Write alone leaves Edit and NotebookEdit.
def denies_writes: (["Write", "Edit", "NotebookEdit"] - (.tools // [])) == [];
# A Claude reviewer or judge seat, however the owner wrote it, keeps the contract of the overlay the plugin ships ($c):
# every writing tool denied, and its shape, headless or pane, which its caller needs. Its model and effort stay.
def review_contract($c):
  (if $c.headless then del(.memory, .reviewer, .unboxed, .advisor) + {headless: true} else del(.headless) + ($c | {reviewer, unboxed}) end)
  | .tools = ((.tools // []) as $t | $t + ($c.tools - $t));
# The row a seat of <role>[.<candidate>] reads: a row of candidates has its agent and model on each, so the one named,
# else the first when every candidate runs on its agent.
def role_row($spec):
  ($spec | split(".")) as [$r, $i]
  | .roles[$r] // null
  | if . == null or (.candidates | not) then .
    elif $i != null then try .candidates[$i | tonumber] catch null
    elif ([.candidates[].agent] | unique | length) == 1 then .candidates[0]
    else null end;
# The one reader of the settings of a row on agent $a: the row itself when on $a,
# else its claude overlay for Claude, else the row the plugin ships (ship) for $a. The edits and note of the row stay.
def for_agent($r; $a):
  ($ARGS.named.ship // [] | .[0].roles[$r] // {}) as $s
  | if .agent == $a then .
    elif $a == "claude" and .claude then {edits, note} + .claude + {agent: "claude"}
    elif $s.agent == $a then {edits, note} + ($s | del(.claude, .first, .edits, .note))
    else fail("\($r) has no \($a) choice in routing") end
  | if $a == "claude" and $s.claude then review_contract($s.claude) else . end;
def role_value($role; $field; $agent):
  if $field == "agent" then IN("codex", "claude")
  elif IN($field; "enabled", "fast") then IN("true", "false")
  elif ($field | startswith("first")) and . == "builder" then true
  elif ($field | test("[Mm]odel$")) then model_ok($agent)
  else IN((if $role == "builder" then ["low", "medium", "high", "max"] else efforts end)[]) end;
def seat_at($root; $spec):
  ($spec | capture("^(?<r>[a-z0-9-]+)(\\.(?<i>[0-9]+))?$") // fail("\($spec) is not a role name")) as $p
  | ($root.roles[$p.r] // fail("no role \($p.r)")) as $role
  | if $role.candidates then
      if $p.i == null then fail("\($p.r) has candidates; name one as \($p.r).<index>") else . end
      | ($role.candidates[$p.i | tonumber] // fail("\($p.r) has no candidate \($p.i)")) + {edits: $role.edits}
    elif $p.i != null then fail("\($p.r) has no candidates")
    else $role end
  | . + {role: $p.r}
  # The role /plugin config keys, checked by pp_role_option and handed in by pp_route_json (issue 312): the agent picks
  # the row settings for_agent gives; model and effort replace the row values; fast, on a role with a Fast key,
  # is the owner answer and never the routing file itself (it changes what a run costs). No quote mark here: this is inside one.
  | ($ARGS.named.opts // {}) as $o
  | (if $o.agent then for_agent($p.r; $o.agent) + {role: $p.r} else . end)
  | del(.claude, .first)
  | . + ($o | {model, effort} | with_entries(select(.value != null)))
  | if $o | has("fast") then .fast = $o.fast else . end;
def validate:
  . as $root
  | ([check_templates] | length) as $_
  | (.profile | . == null or IN("claude", "claude-openai") or fail("profile must be claude or claude-openai")) as $_
  | (.launch.paneBox | . == null or is("^(\\$HOME)?/[A-Za-z0-9._/-]+$") or fail("launch.paneBox must be a path")) as $_
  | ([.launch.skillSets // {} | .[][] | select(is("^(\\$HOME)?/[A-Za-z0-9._/-]+$") | not)] | if length > 0 then fail("launch.skillSets holds a value that is not a path: \(.[0])") else . end) as $_
  | ([.roles | to_entries[] | .key as $k | .value
      | if .candidates then (.candidates | to_entries[] | .value | check_seat("\($k).\(.key)"; $root)) else check_seat($k; $root) end] | length) as $_
  # A Claude reviewer or judge never writes: its overlay denies every writing tool, and is a seat of its own.
  | ([.roles | to_entries[] | select(.value.claude) | .key as $k | .value
      | if (.claude | denies_writes | not) then fail("\($k).claude must deny Write, Edit and NotebookEdit in its tools: a Claude reviewer or judge never writes") else . end
      | {edits, note} + .claude + {agent: "claude"} | check_seat("\($k).claude"; $root)] | length) as $_
  | ([.roles | to_entries[] | select(.value.first) | .key as $k | .value.first
      | if type != "object" or (keys - ["model", "effort"] | length) > 0 then fail("\($k).first holds only model and effort") else . end
      | if (.model // "builder" | . == "builder" or model_ok("claude")) | not then fail("\($k).first.model \(.model) is not builder or one of \(claude_models | join(", "))") else . end
      | if (.effort // "builder" | . == "builder" or IN(efforts[])) | not then fail("\($k).first.effort \(.effort) is not builder or one of \(efforts | join(", "))") else . end] | length) as $_
  | ([.review // fail("review is missing") | to_entries[] | .key as $k | .value
      | (if type == "array" then .[] elif keys != ["with"] then fail("review.\($k) holds only its substitute seat, with") else .with end)
      | ($root.roles[.role] // fail("review.\($k) names no role \(.role)")) as $r
      | if $r.headless or $r.inherit or $r.candidates then fail("review.\($k) seat \(.role) is not a pane seat") else . end
      | if keys != ["role"] then fail("review.\($k) sets \(keys - ["role"] | .[0]); settings live on the role") else . end] | length) as $_
  | ([.automations // {} | to_entries[] | .key as $k | .value
      | if ($root.roles[.agent].inherit | not) then fail("automations.\($k).agent must name an inherit role") else . end
      | if (.prompt | type) != "string" then fail("automations.\($k).prompt must be text") else . end
      | .judges[] | if ($root.roles[.].headless | not) then fail("automations.\($k) judge \(.) is not a headless role") else . end] | length) as $_
  | $root;
def banner:
  if .agent == "claude" then
    (.model | capture("^claude-(?<n>[a-z]+)-(?<v>[0-9]+(-[0-9]+)*)$") // null) as $c
    | if $c then ($c.n[:1] | ascii_upcase) + $c.n[1:] + " " + ($c.v | gsub("-"; ".")) else .model end
  else .model end;
def family:
  if .agent == "claude" then "claude"
  else ((.model | capture("^gpt-[0-9.]+-(?<f>[a-z]+)$") | .f) // .model) end;
# A read-only Codex seat with network runs the Codex read-only permission profile with network on: file writes stay
# blocked, gh reaches GitHub (issue 316). --sandbox would override the profile, so such a seat gets no sandbox word.
def ghread: ["-c", "permissions.ghread.extends=\":read-only\"", "-c", "permissions.ghread.network.enabled=true"];
def boxwords:
  if .sandbox == "read-only" and .network then {sandbox: [], network: (ghread + ["-c", "default_permissions=\"ghread\""])}
  else {sandbox: (if .sandbox then ["--sandbox", .sandbox] else [] end),
        network: (if .network then ["-c", "sandbox_workspace_write.network_access=true"] else [] end)} end;
# The same sandbox as `codex sandbox` takes it, for the gh read of a launch: a profile by -P, a mode by -c.
def probebox:
  if .sandbox == "read-only" and .network then ghread + ["-P", "ghread"]
  else (if .sandbox then ["-c", "sandbox_mode=\"\(.sandbox)\""] else [] end)
    + (if .network then ["-c", "sandbox_workspace_write.network_access=true"] else [] end) end;
def words($root):
  . as $s
  | {box: (if .headless or .unboxed then [] else [$root.launch.paneBox] end),
     env: ((if .memory then ["COMMANDECK_PANE_MEMMAX=\(.memory)"] else [] end)
       + (if .reviewer then ["COMMANDECK_REVIEWER=1"] else [] end)
       + (if .codexHome then ["CODEX_HOME=\(.codexHome)"] else [] end)
       # Left out, --advisor gives Claude Code its default advisor; this variable is its one off switch (#85).
       + (if .agent == "claude" and (.advisor | not) then ["CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1"] else [] end)
       # Claude has no shell policy flag, so shellEnv rides the environment words; Codex keeps {shellenv}.
       + (if .agent == "claude" and .shellEnv then [.shellEnv | to_entries[] | "\(.key)=\(.value)"] else [] end)),
     model: ["--model", .model + (if .context then "[\(.context)]" else "" end)],
     effort: (if .effort == null then [] elif .agent == "codex" then ["-c", "model_reasoning_effort=\(.effort)"] else ["--effort", .effort] end),
     fast: (if .agent == "codex" then ["-c", "service_tier=" + (if .fast == true then "fast" else "default" end)] elif .fast == true then ["--settings", "{\"fastMode\":true}"] else [] end),
     advisor: (if .advisor then ["--advisor", .advisor] else [] end),
     tools: (if .tools then ["--disallowedTools", (.tools | join(","))] else [] end),
     compact: (if .compactLimit != null then ["-c", "model_auto_compact_token_limit=\(.compactLimit)"] else [] end),
     sandbox: boxwords.sandbox,
     approval: (if .approval then ["-a", .approval] else [] end),
     network: boxwords.network,
     shellenv: (if .shellEnv then ["-c", "shell_environment_policy.set={" + (.shellEnv | to_entries | map("\(.key)=\"\(.value)\"") | join(",")) + "}"] else [] end),
     mcp: [(.mcpDisabled // [])[] | "-c", "mcp_servers.\(.).enabled=false"],
     skills: (if .disabledSkills then ["-c", "skills.config=[" + ($root.launch.skillSets[.disabledSkills] | map("{path=\"\(.)\",enabled=false}") | join(",")) + "]"] else [] end),
     # Reviewer and judge seats start no helpers: a Codex one loses sub-agents here, a Claude one denies Agent in tools.
     plugins: ((if .disablePlugins then ["--disable", "plugins"] else [] end)
       + (if .agent == "codex" and .reviewer then ["--disable", "multi_agent"] else [] end)),
     projectdoc: (if .projectDocMaxBytes != null then ["-c", "project_doc_max_bytes=\(.projectDocMaxBytes)"] else [] end)} as $w
  | $root.launch.templates[template_of] | split(" ") | map(select(. != "") | if test("^\\{[a-z]+\\}$") then $w[.[1:-1]][] else . end);
def shellword:
  if test("^[A-Za-z0-9_./:@%+=,~-]+$") or test("^\\$HOME[A-Za-z0-9_./:@%+=,-]*$") then .
  elif contains("$HOME") then "\"" + gsub("\""; "\\\"") + "\""
  else ([39] | implode) as $q | $q + . + $q end;
def argword($home):
  gsub("\\$HOME"; $home) | if test("^[A-Za-z_][A-Za-z0-9_]*=~/") then sub("=~/"; "=" + $home + "/") else . end;
def resolve($root; $effort; $model):
  (if $effort != "" then .effort = $effort else . end) | (if $model != "" then .model = $model else . end)
  | check_seat(.role; $root)
  | . + {readonly: ((.sandbox == "read-only") or denies_writes),
         probebox: probebox, banner: banner, family: family, model: (.model + (if .context then "[\(.context)]" else "" end)), words: words($root)}
  | if .headless then . + {argv: [.words[] | argword($home)]} else . + {cmd: (.words | map(shellword) | join(" "))} end
  | del(.words);
def seat($spec; $effort; $model; $advisor):
  . as $root | seat_at($root; $spec) | (if $advisor == "none" then del(.advisor) else . end) | resolve($root; $effort; $model);
'
pp_routing_valid() { # the whole file validates; prints why when it does not
  local cfg; cfg=$(pp_routing)
  [ -f "$cfg" ] || { echo "routing: no config at $cfg" >&2; return 2; }
  jq -e --arg home "$HOME" "$PP_ROUTE_JQ"' validate | true' "$cfg" >/dev/null
}
# pp_codex_proxy -- the proxy Codex's config.toml sends it through: the base URL and the name of the
# env var holding its key (empty for a proxy that signs in by itself, as a Copilot API proxy does),
# tab-separated. Nothing when Codex goes direct. The proxy is the top-level model_provider's base_url.
# Read with tomllib, as setup's requirements already need (Python 3.11): a hand-rolled reader lost key
# and string boundaries (a quoted name with a dot, "base_url =" inside another value). With no tomllib
# nothing is guessed: it says so, and returns 3 with no proxy.
pp_codex_proxy() {
  python3 -c 'import tomllib' 2>/dev/null \
    || { echo "routing: proxy model discovery needs Python 3.11 or newer (tomllib); Codex's config.toml was not read for a proxy" >&2; return 3; }
  python3 -c '
import sys, tomllib
try: c = tomllib.load(open(sys.argv[1], "rb"))
except (OSError, ValueError): sys.exit()
p = (c.get("model_providers") or {}).get(c.get("model_provider"))
u = p.get("base_url") if isinstance(p, dict) else None
if isinstance(u, str) and u:
    k = p.get("env_key")
    print(u + "\t" + (k if isinstance(k, str) else ""))' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null
}
pp_codex_route() { # one plain line for doctor, setup and a refusal
  local px rc=0; px=$(pp_codex_proxy 2>/dev/null) || rc=$?
  if [ "$rc" = 3 ]; then echo "Codex's proxy setting was not read: proxy model discovery needs Python 3.11 or newer"
  elif [ -n "$px" ]; then echo "Codex goes through the proxy ${px%%$'\t'*}"
  else echo "Codex goes direct to its provider (no model_provider with a base_url in ${CODEX_HOME:-$HOME/.codex}/config.toml)"; fi
}
# routing.json names a Codex model by family (sol); Codex takes a model id: the
# newest gpt-<version>-<family> in the account's own list. Behind a proxy that
# list is the proxy's (models_cache.json is then empty or stale), with the
# cache as the fallback. A family neither list carries fails here, before a
# pane opens or a pass starts. A name that is not a bare family is a model id
# and is printed as written: a role's /plugin config model key (pp_role_option)
# takes either, and no plugin update replaces it. [role] only names that key in a refusal.
pp_codex_model() { # <family or model id> [role]
  local list=${CODEX_HOME:-$HOME/.codex}/models_cache.json id= px url key
  local newest='[.[] | select(test("^gpt-[0-9.]+-\($f)$"))] | sort_by(capture("^gpt-(?<v>[0-9.]+)-").v | split(".") | map(tonumber)) | last // empty'
  [[ $1 =~ ^[a-z]+$ ]] || { printf '%s\n' "$1"; return 0; }
  px=$(pp_codex_proxy) || px=
  if [ -n "$px" ]; then
    url=${px%%$'\t'*} key=${px#*$'\t'}
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [ -n "${!key:-}" ] || key=
    # The key goes on stdin, never on the command line, where ps shows it.
    id=$({ [ -z "$key" ] || printf 'Authorization: Bearer %s\n' "${!key}"; } \
      | curl -fsS --max-time 5 ${key:+-H @-} "${url%/}/models" 2>/dev/null | jq -r --arg f "$1" "[.data[]?.id | strings] | $newest" 2>/dev/null || true)
  fi
  [ -n "$id" ] || id=$(jq -r --arg f "$1" "[.models[]?.slug | strings] | $newest" "$list" 2>/dev/null || true)
  if [ -z "$id" ]; then
    local via= or=" Or run codex once while signed in."
    [ -z "$px" ] || { via=", and its model list has none" or=; }
    echo "routing: no gpt-<version>-$1 model for the Codex family $1. $(pp_codex_route)$via; $list lists none either. Name the model id: $(pp_role_key "${2:-codex-reviewer}" model)=<model id> in /plugin config.$or" >&2
    return 2
  fi
  printf '%s\n' "$id"
}
# pp_registered -- the dashboard's registry has a line naming this project, both sides through pp_norm.
pp_registered() {
  local q m f=$HOME/.commandeck/dashboard/projects; m=$(pp_norm "$PP_MAIN")
  [ -f "$f" ] || return 1
  while IFS= read -r q; do [ "$(pp_norm "$q")" != "$m" ] || return 0; done < "$f"
  return 1
}
# pp_pane_of <worktree path> -- the live Claude pane in that worktree, found at
# the moment of asking: a pane's handle changes each time its session restarts,
# so a handle saved earlier may name a pane that is gone. Nothing when none is live.
# Live as live_pane_with_title has it: connected and not orphaned.
# shortcut: a review pane is told from the seat by its launch title; one that retitled itself is not, when a pane is a reviewer by more than its title, match that.
pp_pane_of() {
  timeout 10 orca-ide terminal list --json 2>/dev/null | jq -r --arg wt "$1" \
    "$PP_PNORM"'($wt | pnorm) as $wt | first((.result | if type == "array" then . else (.terminals // []) end)[]?
      | select((wtp | pnorm) == $wt and .agentIdentity == "claude" and .connected != false and .orphaned != true)
      | select((.title // "") | test("^(Reviewer|Claude reviewer|Codex reviewer|Luna reviewer|Refuter|Certifier|Judge)\\b") | not) | .handle) // empty' 2>/dev/null
}
# pp_seat_pane <seat key> <worktree> -- the live pane of main (key main) or of a
# Builder (key unit-<unit>): the handle its last session start recorded
# (inbox-drain.sh), when Orca still lists it live in that worktree. Nothing when
# the seat is down. A Builder whose recorded pane is gone, or that no session start
# recorded, has the pane its launch names in its seat record (seat.sh); other
# panes in its worktree (a design co-author) are never taken for it. Only main,
# alone in its checkout, falls back to pp_pane_of in main's pane folder
# (COMMANDECK_MAIN_PANE_DIR, else the worktree), for a session that began before
# the record or whose recorded pane has closed (a handoff the new pane's own start
# has not yet recorded).
pp_seat_pane() {
  local hs h=; hs=$(tail -1 "$PP_SCRATCH/handles/$1" 2>/dev/null)
  [ "$1" = main ] || hs="$hs $(sed -n 's/^handle=//p' "$PP_SCRATCH/seat-${1#unit-}-builder.txt" 2>/dev/null | tail -1)"
  [ -z "${hs// /}" ] || h=$(timeout 10 orca-ide terminal list --json 2>/dev/null | jq -r --arg wt "$2" --arg hs "$hs" \
    "$PP_PNORM"'($wt | pnorm) as $wt | [(.result | if type == "array" then . else (.terminals // []) end)[]?
      | select((wtp | pnorm) == $wt and .connected != false and .orphaned != true) | .handle] as $live
      | first($hs | splits(" +") | select(. != "" and IN($live[]))) // empty' 2>/dev/null)
  [ -n "$h" ] || [ "$1" != main ] || h=$(pp_pane_of "${COMMANDECK_MAIN_PANE_DIR:-$2}")
  [ -z "$h" ] || printf '%s\n' "$h"
}
# pp_handle_record <key> <handle> -- the pane that now answers to <key> (main, unit-<unit>), newest last; the 4 before
# it are kept, because an older handle's mail was shown by a session since. The one write of handles/<key>:
# session start (inbox-drain.sh) and a handoff (context-clear-restart.sh) both call it.
pp_handle_record() {
  local f=$PP_SCRATCH/handles/$1
  mkdir -p "${f%/*}" && { grep -vxF -- "$2" "$f" 2>/dev/null | tail -4; echo "$2"; } > "$f.new" && mv "$f.new" "$f"
}
# pp_worktree_new <name> -- a new Orca worktree of this project at
# $PP_WORKSPACES/<name>, on local main and not Orca's origin/main default. The
# one place a worktree is created: a Builder's (builder-launch.sh) and the
# relay's (setup.sh). Says why not on stderr.
pp_worktree_new() {
  local wt=$PP_WORKSPACES/$1 head
  orca-ide worktree create --repo "path:$PP_MAIN" --name "$1" --base-branch main \
    --parent-worktree "path:$PP_MAIN" --setup run --json >/dev/null \
    || { echo "worktree create failed for $1" >&2; return 1; }
  [ -d "$wt" ] || { echo "worktree create reported success but $wt does not exist" >&2; return 1; }
  head=$(git -C "$PP_MAIN" rev-parse refs/heads/main)
  [ "$(git -C "$wt" rev-parse HEAD)" = "$head" ] || git -C "$wt" reset --hard "$head" >/dev/null \
    || { echo "could not base $1 on local main $head" >&2; return 1; }
}
# pp_sync_main <checkout> [--check] -- fetch origin's main and fast-forward local
# main to it, before a Builder branches or a merge rebases: a release marked
# published on origin and not fetched here gets its files rebuilt as a draft.
# No origin is nothing to fetch. A fetch that fails, or a local main that has
# diverged, refuses with the reason. --check moves nothing (a dry run).
pp_sync_main() {
  local c=$1 got
  git -C "$c" remote get-url origin >/dev/null 2>&1 || return 0
  git -C "$c" fetch -q origin main 2>/dev/null && got=$(git -C "$c" rev-parse -q --verify 'FETCH_HEAD^{commit}') \
    || { echo "could not fetch main from origin; fetch it by hand (git fetch origin main), then run this again" >&2; return 1; }
  git -C "$c" merge-base --is-ancestor "$got" refs/heads/main && return 0
  git -C "$c" merge-base --is-ancestor refs/heads/main "$got" \
    || { echo "local main has diverged from origin's main and cannot fast-forward; reconcile them (git pull --rebase origin main, or push main), then run this again" >&2; return 1; }
  [ "${2:-}" != --check ] || return 0
  if [ "$(git -C "$c" branch --show-current)" = main ]; then
    git -C "$c" merge -q --ff-only "$got" || { echo "could not fast-forward main to origin's $got (uncommitted work in the way?)" >&2; return 1; }
  else
    git -C "$c" update-ref refs/heads/main "$got" || return 1
  fi
}
# Codex fast mode: on only with the owner's yes (codexReviewerFast). No answer and an unreadable one are off.
# COMMANDECK_CODEX_FAST=false turns it off for one call and no value of it turns it on: set-up's own
# preflight runs before the new answer is saved, and has checked the tier for that answer itself.
pp_codex_fast() { [ "${COMMANDECK_CODEX_FAST:-}" != false ] && [ "$(pp_role_option codex-reviewer fast 2>/dev/null)" = true ]; }
# pp_review_loop <key> <default> <regex> -- a review-loop setting setup saved
# in this project's config (reviewLoop.<key>), as the owner typed it, else the
# default. A saved value the regex does not take says so on stderr and fails:
# the file can be edited by hand, and a wrong number must not pass for a setting.
# COMMANDECK_REVIEW_LOOP: setup's own check reads the answers it is about to save, not the old ones.
pp_review_loop() {
  local f=$PP_MAIN/.claude/commandeck.json v src=/dev/stdin o=
  # The owner's /config answer beats the project's (issue 245); setup's own check reads the answers it saves.
  if case $1:${COMMANDECK_REVIEW_LOOP:-} in passCap:) o=reviewPassCap v=$(pp_config_option reviewPassCap) ;;
       blockAt:) o=reviewBlockSeverity v=$(pp_config_option reviewBlockSeverity) ;;
       freshClosing:) o=freshClosingReviewer v=$(pp_config_option freshClosingReviewer) ;;
       closingPass:) o=closingPass v=$(pp_config_option closingPass) ;; *) false ;; esac; then
    [[ $v =~ $3 ]] || { echo "$o = \"$v\" in /config is not a value it takes; change it with /config" >&2; return 1; }
    echo "$v"; return 0
  fi
  # Setup's answers come in on stdin: a <(...) file is closed before the next line could read it.
  [ -n "${COMMANDECK_REVIEW_LOOP:-}" ] || { [ -e "$f" ] || { echo "$2"; return 0; }; src=$f; }
  # No config is the defaults; one that cannot be read is no setting, and says so.
  v=$(jq -r --arg k "$1" '.reviewLoop | if . == null then {} elif type == "object" then . else error("reviewLoop is not an object") end
    | .[$k] | if . == null then empty else tostring end' "$src" 2>&1 <<<"{\"reviewLoop\": ${COMMANDECK_REVIEW_LOOP:-}}") \
    || { echo "$f: reviewLoop.$1 cannot be read ($v); answer it again with /commandeck:setup" >&2; return 1; }
  [ -n "$v" ] || { echo "$2"; return 0; }
  [[ $v =~ $3 ]] || { echo "$PP_MAIN/.claude/commandeck.json has reviewLoop.$1 = \"$v\", which is not a value it takes; answer it again with /commandeck:setup" >&2; return 1; }
  echo "$v"
}
# pp_keep_worktrees -- the standing worktrees (issue 431) the sweep never closes a pane in and the checkpoint does not
# list: keepWorktrees in this project's config, a JSON array of names, printed one per line. Only an explicit empty
# array keeps nothing. No file, no key, a value that is not an array or a file that does not parse keeps the
# worktrees the plugin creates, so a project that updated without re-running setup loses no protection (main's
# answer, 2026-10-28). This is the one home of that default.
pp_keep_worktrees() {
  local f=$PP_MAIN/.claude/commandeck.json v
  v=$(jq -r '.keepWorktrees | if type == "array" then .[] | strings else error end' "$f" 2>/dev/null) \
    || v=$(printf '%s\n' Research E2EWalkthroughs Fast-lane Research-lane Chief-of-Staff)
  [ -z "$v" ] || printf '%s\n' "$v"
}
# Issue 245: the settings that are the same in every project are also the plugin's options (userConfig in
# .claude-plugin/plugin.json), set in /config. The owner's /config answer beats the project's saved one. It is read
# from the user's settings file, not CLAUDE_PLUGIN_OPTION_*: that reaches hooks only, and may carry the manifest's
# default, which would hide the project's answer.
# PP_OPTS_KEY -- jq's key: the commandeck@<marketplace> the plugin is enabled under, else one with options that is not
# disabled; a disabled install's leftover options are not the running plugin's.
PP_OPTS_KEY='def key: . as $s | first(((.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key),
  ((.pluginConfigs // {}) | keys[] | select(($s.enabledPlugins // {})[.] != false)), ((.enabledPlugins // {}) | keys[])
  | select(startswith("commandeck@"))) // "commandeck@commandeck";'
# pp_config_option <key> -- the /config answer in the form the project's file saves it; fails when there is none.
# COMMANDECK_OPTIONS: setup's own answers ({key: value}), read first by its preflight before they are saved.
pp_config_option() {
  local a=${COMMANDECK_OPTIONS:-}
  { cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null || echo '{}'; } \
    | jq -er --arg k "$1" --argjson a "${a:-null}" "$PP_OPTS_KEY"' (if $a // {} | has($k) then $a[$k] else .pluginConfigs[key].options[$k]? end)
    | select(. != null and . != "project")
    | if $k == "closingPass" or $k == "freshClosingReviewer" then (if . then "yes" else "no" end) else tostring end' 2>/dev/null
}
# Issue 312: every role's settings are /plugin config keys, <role in camelCase><Field> (plan-judge-sol model:
# planJudgeSolModel). A key the manifest does not list is no setting: orchestrator, builder and codex-reviewer have no
# Enabled key, as none of them can be off. Precedence, one order for every role: a launch's own --model or --effort,
# then the key, then routing's field.
PP_ROLE_FIELDS='agent model effort enabled fast firstModel firstEffort'
pp_role_key() { local k=$1 t; while [[ $k == *-* ]]; do t=${k#*-}; k=${k%%-*}${t^}; done; printf '%s%s\n' "$k" "${2^}"; }
pp_role_has() { jq -e --arg k "$(pp_role_key "$1" "$2")" '.userConfig | has($k)' "$PP_SCRIPTS/../.claude-plugin/plugin.json" >/dev/null 2>&1; }
# pp_role_option <role>[.<candidate>] <field> -- that role setting's value, checked against the fixed lists in PP_ROUTE_JQ
# on the agent of the candidate named (the key is the role's); prints nothing and fails (1) when unset. A value it does
# not take is REFUSED naming the key (2): the file can be edited by hand, and a wrong value must not pass for a setting.
pp_role_option() {
  local r=${1%%.*} k v a=
  pp_role_has "$r" "$2" || return 1
  k=$(pp_role_key "$r" "$2")
  v=$(pp_config_option "$k") || return 1
  case $2 in agent|enabled|fast) ;; *) a=$(pp_role_agent "$1") || return 2 ;; esac
  jq -ne --arg v "$v" --arg r "$r" --arg f "$2" --arg a "$a" "$PP_ROUTE_JQ"' $v | role_value($r; $f; $a)' >/dev/null \
    || { echo "REFUSED: /plugin config $k = $v is not a ${a:+$a }$2 for $1" >&2; return 2; }
  printf '%s\n' "$v"
}
# pp_role_agent <role>[.<candidate>] -- the agent the role runs on: its Agent key, else routing's.
pp_role_agent() {
  local a rc=0
  a=$(pp_role_option "${1%%.*}" agent) || rc=$?
  [ "$rc" != 2 ] || return 2
  [ -n "$a" ] || a=$(jq -r --arg s "$1" "$PP_ROUTE_JQ"' role_row($s).agent // empty' "$(pp_routing)" 2>/dev/null)
  [ -n "$a" ] || { echo "routing: no role $1, or its candidates run on more than one agent (name one as ${1%%.*}.<index>)" >&2; return 2; }
  printf '%s\n' "$a"
}
# pp_role_enabled <role> -- fails, saying so, when the role is off (its Enabled key false); a role with no such key is on.
pp_role_enabled() {
  local v rc=0
  v=$(pp_role_option "$1" enabled) || rc=$?
  [ "$rc" != 2 ] || return 2
  [ "$v" != false ] || { echo "$1 is off ($(pp_role_key "$1" enabled)=false in /plugin config)" >&2; return 1; }
}
# pp_option <key> [source] -- the value a reader takes: the /config answer, else the project's saved one (the
# dashboard's: this machine's), else what the reader took before 0.22.0. With "source", where that value is from.
# This is the one statement of the precedence (issue 293): /config, then the project's saved answer, then routing's
# default. builderModel's and builderEffort's manifest default is "project", read as no answer: the /config dialog
# may save a default untouched, and a fixed one would hide the project's answer.
pp_option() {
  local f=$PP_MAIN/.claude/commandeck.json p d= v src=/config r rk fl rc
  # A role key (issue 312): its checked value, else routing's field; where it is from as for every other key.
  for r in $(jq -r '.roles | keys[]' "$(pp_routing)" 2>/dev/null); do rk=$(pp_role_key "$r" ""); for fl in $PP_ROLE_FIELDS; do
    [ "$rk${fl^}" = "$1" ] || continue
    pp_config_option "$1" >/dev/null || src=default
    rc=0; v=$(pp_role_option "$r" "$fl" 2>/dev/null) || rc=$?
    case $rc in
      1) v=$(jq -r --arg r "$r" --arg f "$fl" "$PP_ROUTE_JQ"' (.roles[$r] | {first}) + (role_row($r) // {}) | if $f == "enabled" then true elif $f == "fast" then .fast // false
           elif ($f | startswith("first")) then .first[$f[5:] | ascii_downcase] else .[$f] end | values | tostring' "$(pp_routing)") ;;
      2) v="$(pp_config_option "$1") (refused: not a value it takes)" ;;
    esac
    pp_option_out "${2:-}"; return 0
  done; done
  case $1 in
    maxBuilders) p=.builder.maxBuilders ;;
    reviewBlockSeverity) p=.reviewLoop.blockAt d=P2 ;; reviewPassCap) p=.reviewLoop.passCap d=5 ;;
    freshClosingReviewer) p=.reviewLoop.freshClosing d=yes ;; closingPass) p=.reviewLoop.closingPass d=yes ;;
    fullSuiteBeforeFinal) p=.fullSuiteBeforeFinal d=false ;;
    autoDecideSeats) p=.autoDecideSeats d=chiefOfStaff ;;
    unitsBand) p=.units.band d=auto ;; unitsPane) p=.units.pane d=auto ;; unitsStatus) p=.units.status d=auto ;;
    trustAllHooks) p=.trustAllHooks d=false ;;
    mainPromptCacheTtl) p=.mainCacheTtl ;; workerPromptCacheTtl) p=.workerCacheTtl ;; relayPromptCacheTtl) p=.chiefOfStaff.cacheTtl ;;
    dashboardBind) p=.dashboard.bind f=$HOME/.commandeck/install/_machine.json ;;
    dashboardPort) p=.dashboard.port f=$HOME/.commandeck/install/_machine.json ;;
    wakeKinds) p=.wakeKinds d=worker_done,escalation,question,decision_gate,merge_ready ;;
    wakeWindowSeconds) p=.wakeWindowSeconds d=60 ;;
    *) echo "pp_option: no option $1" >&2; return 2 ;;
  esac
  if ! v=$(pp_config_option "$1"); then
    src=$f v=$(jq -r "$p | if . == null then empty else tostring end" "$f" 2>/dev/null) || v=
    [ -n "$v" ] || src=default v=$d
  fi
  # Issue 318: a kinds list that names no kind would never wake main, and a window must be whole seconds.
  case $1 in
    wakeKinds) v=${v//[[:space:]]/}; [[ ,$v, =~ ,(worker_done|escalation|question|decision_gate|merge_ready|status|dispatch|handoff), ]] || src=default v=$d ;;
    wakeWindowSeconds) [[ $v =~ ^[0-9]+$ ]] || src=default v=$d ;;
    # Issue 333: the seats that may decide for the owner; anything else is the default (the relay alone).
    autoDecideSeats) case $v in chiefOfStaff|chiefOfStaff,main|off) ;; *) src=default v=$d ;; esac ;;
    # Issue 349: the units mod's three views; the doctor shows them, no shell script reads them.
    unitsBand|unitsPane|unitsStatus) case $v in auto|on|off) ;; *) src=default v=$d ;; esac ;;
  esac
  pp_option_out "${2:-}"
}
# pp_option_out <mode> -- pp_option's answer from its locals; "both" (source, tab, value) is one lookup where the
# doctor's line per option took two, each a dozen processes.
pp_option_out() { case $1 in source) echo "$src" ;; both) printf '%s\t%s\n' "$src" "$v" ;; *) echo "$v" ;; esac; }
# Issue 315: Codex opens a pane on its "hooks need review" menu when any hook in its home is untrusted, and a tool
# update rewrites its own hook. pp_codex_retrust [<launch command>] trusts the home again right before a Codex launch
# (the plugin's hooks; every hook when the owner answered yes to setup's trust-all question). The home is the one the
# launch command names (CODEX_HOME=...), else this shell's. A hook the script cannot hash is said on stderr, not fatal:
# pp_codex_blocked then names it from the pane.
pp_codex_home() {
  local h; h=$(sed -nE 's/^(.*[ ;])?CODEX_HOME=([^ ;]+).*/\2/p' <<<"${1-}" | tail -1)
  h=${h:-${CODEX_HOME:-$HOME/.codex}}; printf '%s\n' "${h/#\~/$HOME}"
}
pp_codex_retrust() {
  local a=; [ "$(pp_option trustAllHooks)" != true ] || a=--all
  python3 "$PP_SCRIPTS/codex-hook-trust.py" ${a:+"$a"} "$(pp_codex_home "${1-}")" >/dev/null || true
}
# pp_codex_blocked <codex home> <pane text> -- when the pane text is Codex's review menu, say so (the count it shows,
# the home, the fix and every hook not trusted there) and succeed; any other text fails.
pp_codex_blocked() {
  local n names
  grep -qE 'hooks? needs? review' <<<"$2" || return 1
  n=$(grep -oE '[0-9]+ hooks? needs? review' <<<"$2" | head -1 | grep -oE '^[0-9]+' || true)
  names=$(python3 "$PP_SCRIPTS/codex-hook-trust.py" --check --all "$1" 2>&1 | sed 's/^/  /' || true)
  echo "Codex pane blocked: ${n:-some} hooks need review in $1; run /hooks there or turn on trust-all (setup.sh --trust-all-hooks on)"
  [ -z "$names" ] || printf '%s\n' "$names"
}
# pp_issue_sizing -- setup's issue sizing line (issueSizing: tokens, or off), default 40000. A saved value it does
# not take fails, naming the key, as pp_review_loop does.
pp_issue_sizing() {
  local v; v=$(jq -r '.issueSizing // 40000' "$PP_MAIN/.claude/commandeck.json" 2>/dev/null) || v=40000
  [[ $v =~ ^(off|[1-9][0-9]*)$ ]] || { echo "$PP_MAIN/.claude/commandeck.json has issueSizing = \"$v\", which is not a value it takes; answer it again with /commandeck:setup" >&2; return 1; }
  echo "$v"
}
# The tier is the Codex home's own setting: a pass runs on what its config says. Read with tomllib, as
# pp_codex_proxy is: the default profile's service_tier over the top-level one, the key in any TOML spelling.
pp_codex_fast_home() {
  python3 -c 'import tomllib' 2>/dev/null \
    || { echo "Codex fast mode needs Python 3.11 or newer (tomllib) to read Codex's config.toml" >&2; return 1; }
  python3 -c '
import sys, tomllib
try: c = tomllib.load(open(sys.argv[1], "rb"))
except (OSError, ValueError): sys.exit(1)
p = (c.get("profiles") or {}).get(c.get("profile"))
sys.exit((p if isinstance(p, dict) and "service_tier" in p else c).get("service_tier") != "fast")' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null
}
pp_route_json() { # <role>[.<candidate>] [effort] [model] [none: this launch has no advisor] -- the resolved seat, as JSON
  local cfg r=${1%%.*} m=${3:-} o a v f rc; cfg=$(pp_routing)
  [ -f "$cfg" ] || { echo "routing: no config at $cfg" >&2; return 2; }
  # The role's /plugin config keys, each checked (issue 312); a refused one stops the launch.
  a=$(pp_role_agent "$1") || return 2
  o=$(jq -nc --arg a "$a" '{agent: $a}')
  for f in model effort fast; do
    rc=0; v=$(pp_role_option "$1" "$f") || rc=$?
    case $rc in 0) o=$(jq -c --arg f "$f" --arg v "$v" '.[$f] = (if $f == "fast" then $v == "true" else $v end)' <<<"$o") ;; 1) ;; *) return 2 ;; esac
  done
  # A Fast key's no answer is off; COMMANDECK_CODEX_FAST=false is setup's preflight, which checks the tier itself.
  ! pp_role_has "$r" fast || o=$(jq -c '.fast = (.fast == true)' <<<"$o")
  [ "$r" != codex-reviewer ] || [ "${COMMANDECK_CODEX_FAST:-}" != false ] || o=$(jq -c '.fast = false' <<<"$o")
  # Every Codex model goes through the resolver: the launch's own pick, else the key, else routing's family.
  if [ "$a" = codex ]; then
    m=${m:-$(jq -r '.model // empty' <<<"$o")}
    m=${m:-$(jq -r --arg r "$r" --arg s "$1" --slurpfile ship "$PP_SCRIPTS/../config/routing.json" "$PP_ROUTE_JQ"' role_row($s) | for_agent($r; "codex").model // empty' "$cfg" 2>/dev/null)}
    m=$(pp_codex_model "$m" "$r") || return 2
  fi
  jq -ce --arg spec "$1" --arg effort "${2:-}" --arg model "$m" --arg advisor "${4:-}" --arg home "$HOME" --argjson opts "$o" --slurpfile ship "$PP_SCRIPTS/../config/routing.json" "$PP_ROUTE_JQ"' validate | seat($spec; $effort; $model; $advisor)' "$cfg"
}
# The model one Builder launch may run: an alias routing.json already names, the
# check pp_role_option makes for the builderModel key. builder-launch.sh asks before it
# creates anything and seat.sh asks again, so a seat launched by hand is held to it.
pp_builder_model_ok() { # <alias> -- says why not
  jq -ne --arg a "$1" "$PP_ROUTE_JQ"' $a | model_ok("claude")' >/dev/null 2>&1 \
    || { echo "REFUSED: --model ${1:-(none)} is not one of $(jq -rn "$PP_ROUTE_JQ"' claude_models | join(", ")')" >&2; return 2; }
}
# The model a plan seat may be launched on: one of the agent it runs on (its Agent key), so a Codex judge is never
# handed a Claude model.
pp_seat_model_ok() { # <role> <alias> -- says why not
  local a; a=$(pp_role_agent "$1") || return 2
  jq -ne --arg m "$2" --arg a "$a" "$PP_ROUTE_JQ"' $m | model_ok($a)' >/dev/null 2>&1 \
    || { echo "REFUSED: --model ${2:-(none)} is not a $a model for $1" >&2; return 2; }
}
# pp_plan_seat <role> [model] -- "<role> <agent> <model>": the plan seat as it launches, on its own agent, model and
# effort keys, or on the launch's own model when one is named. A seat on Codex where no codex is installed is refused,
# naming the key that moves it.
pp_plan_seat() {
  local r=$1 a j
  a=$(pp_role_agent "$r") || return 2
  [ "$a" != codex ] || command -v codex >/dev/null 2>&1 \
    || { echo "REFUSED: $r runs on Codex, which is not installed here; set $(pp_role_key "$r" agent)=claude, or $(pp_role_key "$r" enabled)=false, in /plugin config" >&2; return 2; }
  j=$(pp_route_json "$r" "" "${2:-}") || return 2
  echo "$r $a $(jq -r .model <<<"$j")"
}
# The effort one Builder launch may run: medium or high, never under the project's Builder default. Asked the
# same two places as the model, so a seat launched by hand cannot lower it either.
pp_builder_effort_ok() { # <level> <the Builder's default effort, or none> -- says why not
  [[ $1 == medium || $1 == high ]] || { echo "REFUSED: --effort takes medium or high ('$1' given): main may raise a Builder, never lower it" >&2; return 2; }
  # A default that is no level (none) indexes to null, which every level is at or above.
  jq -ne --arg e "$1" --arg d "$2" "$PP_ROUTE_JQ"' efforts | index($e) >= index($d)' >/dev/null \
    || { echo "REFUSED: --effort $1 is below this project's Builder default $2; a launch may only raise it" >&2; return 2; }
}
pp_route() { # same arguments; sets RT_AGENT RT_MODEL RT_EFFORT RT_READONLY RT_BANNER RT_FAMILY RT_CMD
  local json f
  json=$(pp_route_json "$@") || return 2
  mapfile -t f < <(jq -r '.agent, .model, (.effort // ""), (if .readonly then 1 else 0 end), .banner, .family, (.cmd // "")' <<<"$json")
  RT_AGENT=${f[0]} RT_MODEL=${f[1]} RT_EFFORT=${f[2]} RT_READONLY=${f[3]} RT_BANNER=${f[4]} RT_FAMILY=${f[5]} RT_CMD=${f[6]}
}
# pp_gh_read [--host] [--new] <role> <dir> [effort] [model] -- one gh read, made the way <role>'s seat makes it, from
# <dir>, the seat's target checkout (issue 316): its Codex sandbox, Codex home and shellEnv, or the env of the settings
# Claude Code applies to a Claude seat's shell (none for the restricted Claude reviewer). Fails with "<reason>: <first error line>. Fix: <fix>" on one line,
# returning 1. --host reads outside the sandbox (the review pass hands the Codex reviewer host reads); --new reads the
# settings a worktree cut from local main will have, for a plan seat's first launch.
pp_gh_read() {
  local host= new= j role dir agent e=() u=() w=() n h f fs out rc=0 err reason fix
  while [[ ${1:-} == --* ]]; do case $1 in --host) host=1 ;; --new) new=1 ;; *) return 2 ;; esac; shift; done
  role=$1 dir=$2
  j=$(pp_route_json "$role" "${3:-}" "${4:-}") || return 2
  git -C "$dir" remote get-url origin >/dev/null 2>&1 \
    || { echo "no GitHub remote in $dir: there is no repository to read. Fix: give that checkout an origin remote on GitHub"; return 1; }
  agent=$(jq -r .agent <<<"$j")
  # shellEnv first: a Claude seat gets it as env words, and its settings env (below) overrides them.
  mapfile -t e < <(jq -r '.shellEnv // {} | to_entries[] | "\(.key)=\(.value)"' <<<"$j")
  # The review pass runs the Claude reviewer with --restricted, which reads no settings file: its env is shellEnv alone.
  if [ "$agent" = claude ] && [ "$role" != codex-reviewer ]; then
    # Claude Code applies the env of the user's settings, then the checkout's; the later one wins.
    fs=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"); [ -n "$new" ] || fs+=("$dir/.claude/settings.json" "$dir/.claude/settings.local.json")
    for f in "${fs[@]}"; do
      mapfile -t -O "${#e[@]}" e < <(jq -r '.env | objects | to_entries[] | "\(.key)=\(.value)"' "$f" 2>/dev/null || true)
    done
    [ -z "$new" ] || mapfile -t -O "${#e[@]}" e < <(git -C "$PP_MAIN" show main:.claude/settings.json 2>/dev/null | jq -r '.env | objects | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || true)
  fi
  if [ "$agent" = codex ] && [ -z "$host" ]; then
    # codex sandbox keeps the host's *KEY*, *SECRET* and *TOKEN* variables, which a seat's shell policy drops (measured).
    for n in $(compgen -e); do case ${n^^} in *KEY*|*SECRET*|*TOKEN*) u+=(-u "$n") ;; esac; done
    h=$(jq -r '.codexHome // empty' <<<"$j"); [ -z "$h" ] || u+=("CODEX_HOME=${h/#\~/$HOME}")
    mapfile -t w < <(jq -r '.probebox[]' <<<"$j")
    out=$(cd "$dir" && timeout 20 env "${u[@]}" codex sandbox "${w[@]}" -- env "${e[@]}" gh repo view --json nameWithOwner 2>&1) || rc=$?
  else
    out=$(cd "$dir" && timeout 20 env "${e[@]}" gh repo view --json nameWithOwner 2>&1) || rc=$?
  fi
  [ "$rc" != 0 ] || return 0
  err=$(grep -m1 . <<<"$out" | cut -c1-200)
  if [ "$rc" = 127 ] || grep -qiE 'command not found|no such file' <<<"$out"; then
    reason="no gh on PATH" fix="install the GitHub CLI, then run: gh auth login"
  elif grep -qiE 'error connecting|could not resolve host|network is unreachable|dial tcp' <<<"$out"; then
    if [ -n "$host" ]; then reason="no network on this machine" fix="check the connection to api.github.com"
    else reason="no network in the sandbox" fix="set network: true on the seat's read-only Codex role in routing.json"; fi
  elif grep -qiE 'gh auth login|not logged in|http 401|bad credentials' <<<"$out"; then
    if gh auth status >/dev/null 2>&1; then
      reason="no credentials visible in the sandbox" fix="the seat's environment hides gh's sign-in; check the role's shellEnv and codexHome, and any GH_TOKEN in the checkout's .claude/settings*.json env"
    else reason="not signed in to gh" fix="run: gh auth login"; fi
  else reason="gh read failed" fix="run it by hand to see why: gh repo view --json nameWithOwner"; fi
  echo "$reason: $err. Fix: $fix"
  return 1
}
# pp_unit_briefs <briefs dir> <unit> -- the unit's own files there, one a line:
# its brief, evidence, main's rulings, round files and later-cut briefs. Never
# "$unit"*.md: unit "pre" would then own the briefs of "prefab" and "pre-other".
pp_unit_briefs() {
  local f b
  for f in "$1/$2".md "$1/$2"-*.md; do
    [ -e "$f" ] || continue
    b=${f##*/}; b=${b#"$2"}
    [[ $b =~ ^(\.md|-evidence\.md|-main-rulings\.md|-review-cap\.md|-r[0-9a-z]+-reports\.md|-cut[0-9][^/]*\.md)$ ]] && printf '%s\n' "$f"
  done
  return 0
}
# pp_builder_lock <unit> -- one Builder launch of a unit at a time, held until this process exits: two launches of
# one unit would each open a pane on the same records, so seat.sh takes it for every Builder launch.
# Taken once per process: builder-launch.sh execs seat.sh with it held, and a second flock on a new open would wait on itself.
pp_builder_lock() {
  [ "${PP_BUILDER_LOCKED:-}" != "$1" ] || return 0
  mkdir -p "$PP_SCRATCH" && exec {PP_BUILDER_LOCK_FD}>>"$PP_SCRATCH/$1-builder-launch.lock" && flock -w 600 "$PP_BUILDER_LOCK_FD" \
    || { echo "cannot lock $PP_SCRATCH/$1-builder-launch.lock; the Builder was not launched" >&2; return 1; }
  export PP_BUILDER_LOCKED=$1
}
# pp_unit_name <unit> -- pp_unit_briefs tells a unit's papers by name alone, so
# no unit may be named like one: `u-evidence` would lose its brief to `u`.
# Refuses with the rule and the part of the name it hit.
pp_unit_name() {
  [[ $1 =~ (-evidence|-main-rulings|-review-cap|-r[0-9a-z]+-reports)$|(-cut[0-9]+) ]] || return 0
  echo "unit $1 may not be named like a paper (it has ${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}): a name ending in -evidence, -main-rulings, -review-cap or -r<N>-reports, or holding -cut<N>, is how another unit's brief files are told from its own. Pick another name" >&2
  return 1
}
# pp_merge_held <unit> <worktree> -- exit 0, printing why, when the unit may not merge on its own (issues 254, 258):
# `Merge: hold` in its brief, or an owner decision still open on it. Its questions are recorded as <unit>-<message
# id>; one that waits on main is not the owner's. main-watch's gate asks, and merge-unit-local.sh --auto under its lock.
pp_merge_held() {
  local j
  grep -qE '^Merge: hold[[:space:]]*$' "$2/.claude/briefs/$1.md" 2>/dev/null && { echo "Merge: hold in its brief"; return 0; }
  j=$(jq -rRn --arg p "$1-" '[inputs | fromjson? | objects] | group_by(.id) | map(last)
    | map(select((.id | tostring | startswith($p)) and .answer == null and .waitsOn != "main")) | first | .id // empty' \
    "$PP_MAIN/.claude/metrics/decisions.jsonl" 2>/dev/null) && [ -n "$j" ] && { echo "open owner decision $j"; return 0; }
  return 1
}
# pp_gate_key <unit> <worktree> -- what a kept merge-gate result stands for: the tip and the unit's round files, so a
# new pass on an unchanged commit is checked again. main-watch.sh writes it, orca-wait.sh reads it.
pp_gate_key() { echo "$(git -C "$2" rev-parse HEAD 2>/dev/null) $(cat "$2/.claude/briefs/$1"-r*-reports.md 2>/dev/null | cksum | tr ' ' :)"; }
# The review pass: the reviewer's agent, codexReviewerAgent (the Claude-only profile sets it to claude), else codex.
pp_pass() { pp_role_agent codex-reviewer; }
pp_argv() { # <headless role> [effort] -- its command, one argv word per line
  local json
  json=$(pp_route_json "$1" "${2:-}") || return 2
  jq -er '.argv // error("routing: \(.role) is not a headless role") | .[]' <<<"$json"
}

# The one reading of a finding's severity, shared by close-round.sh (each raw
# reviewer report) and review-round.sh (a round's combined reports file, whose
# finding lines close-round.sh prefixes with an id). Here because both already
# source this file, and every test that stages them copies it.
#
# EVERY P0-P2 A REVIEWER FILES STANDS AT ITS STATED SEVERITY. No
# reviewer test runs at close, and a passing one never withdraws its finding:
# the fixer runs each test red from the packet. Prints the lowest severity
# filed, or 9 when the report carries no finding at all.
#
# A second argument picks a count instead: `count` is every finding line,
# resolved ones included, so a refusal (no finding at all) is told apart from a
# GO that resolved its findings; `standing` is the P0-P2 ones that stand (not
# resolved, not pre-existing); `pre` is the [PRE-EXISTING] ones; `unowned` is
# the fenced test blocks no parsed finding owns -- a finding in a shape the
# parser missed. A fence is read as refute.sh reads it.
#
# The one fence rule for every reader of a report or plan (PP_AWK_FENCE) lives in fence.sh.
. "$(dirname "${BASH_SOURCE[0]}")/fence.sh"
# pp_ask_lines <reply text> -- every `QUESTION:` or `BLOCKED:` line outside a fence (decoration stripped), in order, by the
# one fence rule above: a closed fence quotes an example, a blockquote line never starts with the word, and a fence that
# never closes quotes nothing (a missed question costs more than a spare one). Both Stop hooks read their asks with it.
pp_ask_lines() {
  printf '%s\n' "$1" | awk "$PP_AWK_FENCE"'{ f = fence($0); if (f) { if (f == 2) b = ""; next } if (flen) { b = b $0 "\n"; next } print } END { printf "%s", b }' \
    | sed -E 's/^[[:space:]*`•]+//' | grep -E '^(QUESTION|BLOCKED):'
}
surviving_severity() {  # <reviewer report> [count|standing|pre|unowned|unpatched]
  # Two passes: the first records every verdict line, so a finding can be read
  # against the verdict of its own report.
  # One finding-id pattern for the finding regex and own_go(), so the shapes
  # the one accepts are the shapes the other can judge by their own verdict.
  # The seat segment is any reviewer family, so a report from a family no
  # longer configured still reads the same.
  awk -v mode="${2:-}" -v fid='[A-Za-z0-9._-]+-r[0-9]+-[a-z]+-[0-9]+' "$PP_AWK_FENCE"'
    BEGIN {
      worst = 9
      lead = "^[[:space:]]*(([0-9]+\\.|[-*])[[:space:]]*)?(#+[[:space:]]*)?(\\*\\*)?"
      idline = lead fid "[^[:alnum:]]"
      finding = "^[[:space:]]*(" fid "[[:space:]]+)?(([0-9]+\\.|[-*])[[:space:]]*)?(#+[[:space:]]*)?(\\*\\*)?(" fid "[^[:alnum:]]{0,8})?(\\[PRE-EXISTING\\][[:space:]]*)?\\[?P[0-3]\\]?([[:space:]]|-|:|\\*)"
    }
    NR == FNR {
      f = fence($0)   # a verdict in a fenced test is fixture text
      if (!f && !flen && $0 ~ /^[[:space:]]*VERDICT:[[:space:]]*(GO|NO-GO)[[:space:]]*$/) { nv++; vline[nv] = FNR; vgo[nv] = ($0 !~ /NO-GO/) }
      next
    }
    FNR == 1 { report_go = nv ? vgo[nv] : 0; flen = 0 }
    { f = fence($0) }
    # A single report is judged by its last verdict. In the combined file every
    # report ends on its own verdict, so a line carrying a finding id -- the
    # close-round.sh prefix or the id a reviewer wrote first -- is judged by the
    # first verdict after it, never a later reviewer.
    function own_go(   i) {
      if ($0 !~ idline) return report_go
      for (i = 1; i <= nv; i++) if (vline[i] > FNR) return vgo[i]
      return report_go
    }
    function close_finding() {
      if (open && sev < worst) worst = sev
      if (open && sev <= 2) { standing++; if (!patched) unpatched++ }
      open = 0
    }
    # A finding line in every shape the reviewers write: "- [P1]", "1. **[P1]",
    # "**P1 --", "### P2 --", "### P2-1 --", and the shape where the reviewer
    # writes the finding id itself first: "**<unit>-r2-claude-1 -- [P2] ...".
    # The id segment is optional but must be id-shaped, so prose that mentions a
    # level mid-sentence ("confirmed the P2") never starts a line this way. The
    # leading "<unit>-r2-sol-1 " is the id close-round.sh gives each finding line
    # in the combined file, ahead of any of those shapes.
    # No mode reads a finding line inside a fence: that is a fixture in a
    # reviewer test. Counted, it raised the worst severity and the standing
    # count, closed the real finding before its diff, and owned a test that an
    # unparsed finding should have left unowned.
    $0 ~ finding && !f && !flen {
      close_finding(); found++; preopen = 0; resolved = 0; patched = 0
      # A [PRE-EXISTING] finding is for main to file and never gates the unit;
      # its fences belong to nothing that blocks.
      if ($0 ~ /\[PRE-EXISTING\]/) { pre++; preopen = 1; next }
      # A GO report can describe findings it resolved while reviewing. Those
      # are history, not work that survived the round. NO-GO keeps every line.
      # The last field is the exact failing command, which may hold any word.
      lower = tolower($0)
      if (split(lower, fields, " -- ") >= 4) lower = fields[1] " " fields[2] " " fields[3]
      if (own_go() && lower ~ /(^|[^[:alpha:]])(fixed|closed|resolved|refuted|no longer)([^[:alpha:]]|$)/) { resolved = 1; next }
      match($0, /P[0-3]/); sev = substr($0, RSTART + 1, 1) + 0
      open = 1; next
    }
    # A [PRE-EXISTING] or resolved finding owns only the fences right after it:
    # the first prose line outside a fence is some other finding the parser
    # missed, and its fence must stay unowned so the round fails closed.
    # A finding owns a patch when a finder diff (the apply-patch.sh block shape)
    # follows its line; unpatched counts the standing ones without one.
    # Only a line that OPENS a fence is a patch or a test: the same text inside
    # an outer fence is a sample in a fixture.
    open && f == 1 && /^[[:space:]]*```diff path=/ { patched = 1 }
    (preopen || resolved) && !f && !flen && NF { preopen = 0; resolved = 0 }
    f == 1 && !/^[[:space:]]*(```+|~~~+)diff/ && !(open || preopen || resolved) {   # a diff fence is a fix, never a test
      t = $0; sub(/^[[:space:]]*(```+|~~~+)/, "", t); sub(/^[a-zA-Z]*[[:space:]]+/, "", t); sub(/^path=/, "", t)
      if (t ~ /\//) unowned++
    }
    END {
      close_finding()
      print (mode == "count" ? found + 0 : mode == "standing" ? standing + 0 : mode == "pre" ? pre + 0 : mode == "unowned" ? unowned + 0 : mode == "unpatched" ? unpatched + 0 : worst)
    }
  ' "$1" "$1"
}

# pp_link_node_modules <main checkout> <other checkout> -- link main's
# node_modules (gitignored, so a new checkout has none) into the other one.
pp_link_node_modules() {
  local d
  for d in "" web infra; do
    # Nothing to share in a repo that has none; a link to nothing breaks tools that follow it.
    [ -d "$1/$d/node_modules" ] && [ -d "$2/$d" ] || continue
    [ -e "$2/$d/node_modules" ] || ln -sfn "$1/$d/node_modules" "$2/$d/node_modules"
  done
}

# pp_fix_stated <batch> [<file>...] -- 0 when every issue the batch names (brief-issues.sh: its numbered list, text
# items with no number skipped) or a `Closes:` line of the batch or the files names has a Fix case
# (plan-check.sh --issue-cases), so its bundle gets one plan and one judge round with no revise session (issue 444). An
# issue that cannot be read is not fix-stated, and no issue at all is not either. Caller: builder-launch.sh.
pp_fix_stated() {
  local nums n cases
  nums=$({ bash "$PP_SCRIPTS/brief-issues.sh" "$1" | jq -r '.[] | numbers'; cat -- "$@" | grep '^Closes:' | grep -oE '#[0-9]+' | tr -d '#'; } | sort -un || true)
  [ -n "$nums" ] || return 1
  for n in $nums; do
    cases=$(bash "$PP_SCRIPTS/plan-check.sh" --issue-cases "$n" 2>/dev/null) || return 1
    grep -q '^Fix ' <<<"$cases" || return 1
  done
}
