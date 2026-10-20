#!/usr/bin/env bash
# Codex hook dispatcher: runs the plugin's hooks for Codex.
#
# WHY. hooks/hooks.json is the one list of which guard runs on which tool.
# Claude Code reads it; Codex does not, so every mechanical rule -- heap cap,
# git safety, the write guards, the orchestrator lane -- would be prose for
# Codex and enforcement for Claude. Rather than a second copy of the rule list
# in `~/.codex/hooks.json`, one entry per EVENT points here
# (templates/codex-hooks.json) and this script reads hooks.json.
#
# WHICH PROJECTS. The registration is user-level, so Codex hands this script
# every folder it opens. The hooks run only in a project that is both set up
# for the plugin (.claude/commandeck.json in the checkout or its main
# checkout) and trusted by Codex -- see the two gates below. Anything else is
# exit 0 and nothing runs: another project's own tooling is left alone.
#
# SHAPE MAP (https://developers.openai.com/codex/hooks). Codex's payload is
# already Claude-shaped: `hook_event_name`, `cwd`, `tool_name`, `tool_input`.
#   Codex `Bash`         -> Claude `Bash`   (tool_input.command, identical)
#   A group is selected by matching the payload's tool name against the group's
#   matcher REGEX, exactly as Claude Code does -- not by string equality.
#
#   Codex `apply_patch`  -> one Claude `Write`/`Edit` payload per file in the
#                           patch, so the ~20 Edit|Write hooks see the shape
#                           they were written against (lib/edit-payload.sh).
#   Codex `Stop`         -> the Stop matcher's hooks, payload UNCHANGED. Codex's
#                           Stop event already carries `cwd`, `session_id`,
#                           `stop_hook_active` and `transcript_path` under the
#                           same names, plus `last_assistant_message`, which
#                           Claude Code does not send.
# `Delete File` sections produce no payload: no content hook screens a removal.
#
# THE PAYLOAD'S OWN EVENT DECIDES, and only the five events below are dispatched.
# The tool name used to decide alone, so a Codex PostToolUse Bash payload ran the
# PRE-tool Bash guards a second time and reached none of the post ones -- the
# read tracker, the staged-index warning and the rerun guard's completion record
# were Claude-only, and so were the post-edit typecheck and brief freshness
# passes behind an apply_patch. An event this script does not know is not
# guessed at: it exits 0 rather than running some other event's rules.
#
# WARNINGS ARE OUTPUT TOO. Half the post hooks say their piece and exit 0
# (a freshness note, an ignore warning, an audit result). Relaying stderr only
# for a non-zero exit dropped every one of them, which is the whole value of the
# post events. Anything a hook writes to stderr is relayed; for SessionStart and
# UserPromptSubmit, whose product is context on STDOUT, stdout is relayed too.
#
# The registration in each Codex home names the events it sends. An event
# missing there never reaches this script, so adding a case here is half of
# turning it on.
#
# CEILING, stated. The `old_string` synthesised for an Update is the hunk's
# context+removed lines, which is an approximation of what Claude's Edit tool
# would send. The content tripwires need the NEW text and the path, and both are
# exact. Hosted Codex tools (WebSearch) never reach a hook at all.
#
# Testing a change here means invoking this file directly with a payload, not
# launching Codex and watching.
#
# A hook that CANNOT work for Codex -- one keyed to Claude-only session state,
# or one whose whole message is "use the Read tool" -- carries `# codex: skip`
# in its own header, and every skip is logged so a silently-absent rule is
# visible. That marker is the only per-hook knob; there is no second list here.
#
# Codex-safe by construction: bash, jq, git, python3. No Claude env, no MCP.
#
# A DISPATCHER THAT COULD NOT RUN MUST NEVER READ AS A CLEAN TURN. Exit 2 is a
# denial and exit 0 is an allow, so "I could not run" is exit 1 and one line --
# A silent 0 here is worse than anywhere else: it takes every hook in
# hooks.json down with it, so a Codex
# turn ends looking guarded by rules that never fired.
#
# Self-test: bash hooks/__tests__/codex-dispatch.test.sh

cannot_run() { echo "codex-dispatch: $1 -- the hooks did NOT run for this turn." >&2; exit 1; }

# STEP TRACE. Off unless COMMANDECK_CODEX_TRACE names a file; off costs
# one builtin test per step and no process. On, each step appends one row:
# epoch seconds, pid, event:tool, step. Hook names and exit codes only, never a
# payload. It is read from the hook's own environment, which Codex sets and a
# sandboxed command cannot. Needs bash 5 for EPOCHREALTIME, like the fire log.
T0=${EPOCHREALTIME:-}
trace() { # step, [timestamp]
  [ -n "${COMMANDECK_CODEX_TRACE:-}" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "${2:-${EPOCHREALTIME:-}}" "$$" "$EVENT:$TOOL" "$1" >>"$COMMANDECK_CODEX_TRACE" 2>/dev/null
}

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"

# The three tools this script itself needs. jq reads every payload, python3
# parses the trust table and the patch, git resolves the checkout: without any
# one of them nothing below can run at all.
for tool in jq python3 git; do
  command -v "$tool" >/dev/null 2>&1 || cannot_run "$tool is not installed"
done

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || cannot_run 'the payload carries no usable cwd'

# The project is the SESSION cwd's checkout; the hooks are this script's own
# plugin.
#
# Exit 0, not 1: the registration is user-level, so Codex opens plenty of
# folders that are no checkout at all. No hook applies there, which is
# not-applicable rather than a failure.
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/commandeck/codex-dispatch.log"
mkdir -p "${LOG%/*}" 2>/dev/null

# ONLY A CHECKOUT CODEX ALREADY TRUSTS GETS TO RUN CODE THROUGH THIS SCRIPT.
# The registration is user-level, and Codex loads user hooks in UNTRUSTED
# projects too, so without this gate opening any unrelated repo in Codex would
# run the hooks there on the first tool call. Claude Code runs them only after
# its own trust prompt; this is the matching gate. A linked worktree counts
# when its MAIN checkout is trusted -- the Orca worktrees are not in that table
# themselves, and a ROOT-only test would silently un-guard every Codex pane.
#
# Both exits below are 0 on purpose, and neither is a could-not-run: an
# untrusted project and a config too broken to name one are the same answer --
# we do not know this checkout is trusted, so we run none of its code.
CODEX_CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
MAIN=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
MAIN=${MAIN%/.git}
python3 - "$CODEX_CONFIG" "$ROOT" "$MAIN" <<'PY' || {
import sys, tomllib
try:
    projects = tomllib.load(open(sys.argv[1], "rb")).get("projects", {})
except Exception:
    sys.exit(1)
sys.exit(0 if any(projects.get(p, {}).get("trust_level") == "trusted"
                  for p in sys.argv[2:]) else 1)
PY
  printf '%s\t%s\t%s\tuntrusted\n' "$(date -Is)" "-" "$ROOT" >>"$LOG" 2>/dev/null
  exit 0
}

# Exit 0 for the same reason as the checkout test above: a project setup never
# touched has nothing this script could have failed to run.
[ -f "$ROOT/.claude/commandeck.json" ] || [ -f "$MAIN/.claude/commandeck.json" ] || exit 0
PLUGIN=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd) || cannot_run 'the plugin folder could not be resolved'
SETTINGS="$PLUGIN/hooks/hooks.json"
[ -f "$SETTINGS" ] || cannot_run "$SETTINGS is missing"

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
trace start "$T0"; trace gate
# The names of what Codex handed the hook, never the values: the one enumerated
# field aside, a value can be a command, a prompt or a path.
[ -n "${COMMANDECK_CODEX_TRACE:-}" ] && trace "keys $(printf '%s' "$INPUT" | jq -r '(keys_unsorted | join(" ")) + " permission_mode=" + (.permission_mode // "" | tostring)' 2>/dev/null)"

# The existing hooks resolve their own paths from CLAUDE_PROJECT_DIR and take
# their Claude/Codex branch from AGENT_KIND (default `claude`, so nothing
# changes for Claude Code, which never sets it).
export AGENT_KIND=codex
export CLAUDE_PROJECT_DIR="$ROOT" CLAUDE_PLUGIN_ROOT="$PLUGIN"

# Every hook command this event+tool reaches, in file order.
#
# The matcher is a REGEX over tool names, so the group is chosen by matching,
# never by string equality. Equality worked only while every group's matcher was
# spelled `Edit|Write|MultiEdit` verbatim: the moment a hook that can only act on
# a Write was narrowed to a `Write` group, Codex stopped reaching it entirely,
# because the apply_patch lane asked for the literal three-tool string. An event
# with no tool (Stop) takes the `*` groups. Each line is the hook's `onFailure`
# (`-` when it has none), a tab, then its command.
hook_commands() {
  jq -r --arg e "$1" --arg t "$2" '
    .hooks[$e][]?
    | select((.matcher // "*") as $m
             | $m == "*" or $m == ""
               or (($t != "") and ($t | test("^(" + $m + ")$"))))
    | .hooks[]? | select(.command) | "\(.onFailure // "-")\t\(.command)"' "$SETTINGS" 2>/dev/null
}

# A READ-ONLY RUN RUNS ONLY THE GUARDS ON THIS KEEP-LIST (owner rulings
# 2026-10-12). A
# review reads, with no write access and no network, so every other guard is
# dropped for that run, on every tool. A new guard is dropped for a read-only
# run unless it is added here. Warning: the read-only proof below is then the
# only thing between a write-capable run and almost no guards; never loosen it.
READ_ONLY_KEEP=' bash-guardrails.sh suite-rerun-guard.sh '

# Whether THIS run is read-only, decided once per dispatch and only when a
# guard off the keep-list comes up. Codex's payload names no sandbox (its permission_mode
# reads bypassPermissions in a read-only run), so the answer is the session
# record Codex itself writes and names in transcript_path. It counts only when
# no sandboxed run could have written it:
#   - its real path, links followed, is under the sessions folder of a real
#     Codex home. The two homes are typed here because the repo has no one list
#     of them; a pattern would make any folder named like one a home.
#   - it is outside the run's own folder, which a workspace-write run can write.
#   - EVERY turn row says read-only with approvals off, exactly. A run that was
#     ever write-capable, or that may ask to run a command outside the sandbox,
#     skips nothing. Rows are parsed, so prompt text spelling one is not one.
# A record that is missing, unreadable or has no turn row skips nothing.
# HOME is the dispatcher's own, set by whoever started Codex, not by a command.
# Ceiling: a full-access run can rewrite its own record. It can rewrite
# hooks.json too, so this gives it nothing it lacked.
# Emptied here: a READ_ONLY inherited from the environment is not an answer.
READ_ONLY=
read_only_run() {
  if [ -z "${READ_ONLY:-}" ]; then
    READ_ONLY=0
    python3 - "$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)" \
      "$CWD" "$ROOT" "${HOME:-/nonexistent}/.codex" "${HOME:-/nonexistent}/.codex-review" <<'PY' 2>/dev/null && READ_ONLY=1
import json, os, sys

path, cwd, root, *homes = sys.argv[1:]
if not path:
    sys.exit(1)
real = os.path.realpath(path)


def under(folder):
    folder = os.path.realpath(folder)
    return os.path.commonpath([real, folder]) == folder


rows = 0
try:
    if not any(under(os.path.join(home, "sessions")) for home in homes):
        sys.exit(1)
    if under(cwd) or under(root):
        sys.exit(1)
    with open(real, "rb") as record:
        for line in record:
            if b'"turn_context"' not in line:
                continue
            row = json.loads(line)
            if row.get("type") != "turn_context":
                continue
            turn = row.get("payload") or {}
            if turn.get("sandbox_policy") != {"type": "read-only"} or turn.get("approval_policy") != "never":
                sys.exit(1)
            rows += 1
except Exception:
    sys.exit(1)
sys.exit(0 if rows else 1)
PY
  fi
  [ "$READ_ONLY" = 1 ]
}

# Run one event+tool's hooks against one payload. Relays ANY stderr a hook
# writes, whatever it exits with: a hook that says "I could not run" exits 1, and
# a hook that WARNS exits 0 -- both were swallowed while only failures were
# relayed. SessionStart and UserPromptSubmit deliver their product on stdout, so
# that is passed through for those two. Returns 2 on the FIRST denial, 0
# otherwise. A denial is exit 2, or the JSON Claude Code takes on stdout with
# exit 0: `decision: block` (the Stop hooks speak only this) or
# `permissionDecision: deny`. Its reason goes to stderr, where Codex reads one.
run_matcher() {
  local event=$1 tool=$2 payload=$3
  local cmd script rc out reason onfail ctx relay_stdout=0

  case "$event" in SessionStart|UserPromptSubmit) relay_stdout=1 ;; esac

  while IFS=$'\t' read -r onfail cmd; do
    [ -n "$cmd" ] || continue

    # The script path for the marker check. hooks.json spells every command
    # as the launcher, then `"${CLAUDE_PLUGIN_ROOT}/hooks/<name>"`: the hook is
    # the path after the launcher, and what sits between the root and the
    # closing quote (or the first space) is the whole parse; anything else is
    # left to the shell below, which runs the command exactly as Claude Code
    # does.
    script=${cmd#\"\$\{CLAUDE_PLUGIN_ROOT\}/hooks/lib/run-hook.sh\" }
    script=${script#\"}; script=${script#\$\{CLAUDE_PLUGIN_ROOT\}}
    script=$PLUGIN${script%%[\" ]*}

    if [ -f "$script" ] && head -40 "$script" | grep -q '^# codex: skip'; then
      printf '%s\t%s\t%s\tskipped\n' "$(date -Is)" "${TOOL:-$event}" "${script##*/}" >>"$LOG" 2>/dev/null
      trace "skip ${script##*/}"
      continue
    fi

    # Stop too: a turn-end check reads the worktree's pending edits, never a read-only run's own.
    if { [ -n "$tool" ] || [ "$event" = Stop ]; } && [[ $READ_ONLY_KEEP != *" ${script##*/} "* ]] && read_only_run; then
      printf '%s\t%s\t%s\tskipped-read-only\n' "$(date -Is)" "${tool:-$event}" "${script##*/}" >>"$LOG" 2>/dev/null
      trace "skip-read-only ${script##*/}"
      continue
    fi

    trace "hook-start ${script##*/}"
    # stderr is not captured, so a warning lands on this script's stderr
    # whatever the exit code. stdout is read for a refusal, then relayed only
    # when this event's product IS stdout.
    out=$(printf '%s' "$payload" | (cd "$ROOT" && eval "$cmd"))
    rc=$?
    [ "$rc" -eq 2 ] && return 2
    if [ "$rc" -ne 0 ]; then
      # A hook that broke (or is missing: 127) screened nothing. One marked
      # `onFailure: block` in hooks.json refuses the call; any other lets it
      # run, as Claude Code does. Either way Codex is told which hook it was.
      printf '%s\t%s\t%s\texit %s\n' "$(date -Is)" "${TOOL:-$event}" "${script##*/}" "$rc" >>"$LOG" 2>/dev/null
      if [ "$onfail" = block ]; then
        echo "BLOCKED: codex-dispatch: ${script##*/} exited $rc, so it could not screen this call, and it is a guard that must (onFailure: block). Reinstall the plugin (\`claude plugin install commandeck@commandeck\`) or run its doctor (\`/commandeck:doctor\`)." >&2
        return 2
      fi
      echo "codex-dispatch: ${script##*/} exited $rc, so its rule did not run for this call" >&2
      continue
    fi
    reason=$(jq -rs --arg h "${script##*/}" '.[0] | objects
      | select(.decision == "block" or .hookSpecificOutput.permissionDecision == "deny")
      | .reason // .hookSpecificOutput.permissionDecisionReason // ("refused by " + $h)' <<<"$out" 2>/dev/null)
    if [ -n "$reason" ]; then printf '%s\n' "$reason" >&2; return 2; fi
    # A passing tool hook's advice (hookSpecificOutput.additionalContext) is
    # for the model: kept here, printed once by context_out when every hook passed.
    if [ "$relay_stdout" = 0 ]; then
      ctx=$(jq -rs '.[0] | objects | .hookSpecificOutput.additionalContext | strings' <<<"$out" 2>/dev/null)
      [ -z "$ctx" ] || CONTEXT+=${CONTEXT:+$'\n'}$ctx
    fi
    [ "$relay_stdout" = 0 ] || [ -z "$out" ] || printf '%s\n' "$out"
  done < <(hook_commands "$event" "$tool")

  return 0
}

CONTEXT=
context_out() {
  [ -z "$CONTEXT" ] || jq -cn --arg e "$EVENT" --arg c "$CONTEXT" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
}

# The three tool-less events go straight through: their hooks take the `*`
# groups and read the fields Codex already spells the same way.
case "$EVENT" in
  Stop|SessionStart|UserPromptSubmit)
    run_matcher "$EVENT" '' "$INPUT" || exit 2
    exit 0
    ;;
  PreToolUse|PostToolUse) ;;
  *) exit 0 ;;
esac

case "$TOOL" in
  # MCP calls pass through too: read-tracker.sh counts serena and
  # codebase-memory use for the symbol-first hooks.
  Bash|mcp__*)
    run_matcher "$EVENT" "$TOOL" "$INPUT" || exit 2
    ;;

  apply_patch)
    # One Claude-shaped Edit/Write payload per file in the patch, as JSON lines.
    PAYLOADS=$(printf '%s' "$INPUT" | CWD="$CWD" EVENT="$EVENT" python3 -c '
import json, os, sys

try:
    event = json.load(sys.stdin)
except Exception:
    sys.exit(0)

patch = (event.get("tool_input") or {}).get("command") or ""
cwd = os.environ.get("CWD", "")

files, cur = [], None
# split("\n"), not splitlines(): splitlines() eats the \r of a CRLF line, and
# edit-content-tripwires.sh screens for exactly that character. The header paths are
# .strip()ed, so a stray \r never reaches a file_path.
for line in patch.split("\n"):
    for verb in ("Add File", "Update File", "Delete File"):
        marker = "*** %s: " % verb
        if line.startswith(marker):
            cur = {"verb": verb, "path": line[len(marker):].strip(),
                   "hunks": [{"old": [], "new": []}]}
            files.append(cur)
            break
    else:
        # A rename is `Update File: <old>` then `Move to: <new>`; the hooks
        # must screen the path the content lands at, not the one it left.
        move = "*** Move to: "
        if line.startswith(move) and cur is not None:
            cur["left"] = cur["path"]
            cur["path"] = line[len(move):].strip()
            continue
        if line.startswith("*** End Patch"):
            # Closes the last section, so the empty string after the final
            # newline is not appended to it as a context line.
            cur = None
            continue
        if line.startswith("@@") and cur is not None:
            # Each hunk is its own edit: joined, lines far apart read as one change.
            if cur["hunks"][-1]["old"] or cur["hunks"][-1]["new"]:
                cur["hunks"].append({"old": [], "new": []})
            # `@@ <line>`: the hunk lands after that line of the file.
            if line[2:].strip():
                cur["hunks"][-1]["at"] = line[2:].strip()
            continue
        if line.startswith("***") or line.startswith("@@"):
            continue
        if cur is None:
            continue
        h = cur["hunks"][-1]
        if line.startswith("+"):
            h["new"].append(line[1:])
        elif line.startswith("-"):
            h["old"].append(line[1:])
        else:
            # Context: it is in the file both before and after the edit.
            body = line[1:] if line.startswith(" ") else line
            h["old"].append(body)
            h["new"].append(body)

def full(path):
    return path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))

def emit(tool, tool_input):
    print(json.dumps({
        "session_id": event.get("session_id", ""),
        "cwd": cwd,
        "hook_event_name": os.environ.get("EVENT", "PreToolUse"),
        "tool_name": tool,
        "tool_input": tool_input,
    }))

batch = sorted({full(f["path"]) for f in files if f["verb"] != "Delete File"})
for f in files:
    # A file that goes away (deleted, or moved from) is an Edit with no text:
    # the hooks that decide by whose file it is must see its path.
    gone = f["path"] if f["verb"] == "Delete File" else f.get("left")
    if gone:
        emit("Edit", {"file_path": full(gone), "old_string": "", "new_string": ""})
    if f["verb"] == "Delete File":
        continue
    path = full(f["path"])
    # Where an Edit lands: after its hunk`s `@@` line and every hunk before it.
    # Not a Claude field; a hook that applies the edit to the file reads it.
    before = []
    # Not a Claude field: every hunk of this file, for a hook that must read
    # the file the whole patch makes (one hunk alone may leave broken JSON).
    whole = [dict({"old_string": "\n".join(h["old"]), "new_string": "\n".join(h["new"])}, **({"anchors": [h["at"]]} if h.get("at") else {})) for h in f["hunks"]]
    for h in f["hunks"]:
        tool_input = {"file_path": path}
        if len(whole) > 1 and f["verb"] != "Add File":
            tool_input["file_edits"] = whole
        # Not a Claude field: a moved file`s text is still at the old name, and
        # a hook that applies the edit to the file reads it there.
        if f.get("left"):
            tool_input["source_path"] = full(f["left"])
        # Not a Claude field either: a hook that counts the files of one change
        # set sees these one at a time, none written yet.
        if len(batch) > 1:
            tool_input["batch_paths"] = batch
        if f["verb"] == "Add File":
            tool = "Write"
            tool_input["content"] = "\n".join(h["new"])
        else:
            tool = "Edit"
            tool_input["old_string"] = "\n".join(h["old"])
            tool_input["new_string"] = "\n".join(h["new"])
            before = before + [h["at"]] if h.get("at") else before
            if before:
                tool_input["anchors"] = before
            before = before + [tool_input["old_string"]] if h["old"] else before
        emit(tool, tool_input)
' 2>/dev/null) || cannot_run 'the apply_patch payload could not be adapted'

    while IFS= read -r one; do
      [ -n "$one" ] || continue
      # Each adapted payload names its own tool: an "Add File" becomes a Write
      # and must reach the Write-only groups too.
      run_matcher "$EVENT" "$(printf '%s' "$one" | jq -r '.tool_name // empty' 2>/dev/null)" "$one" || exit 2
    done <<<"$PAYLOADS"
    ;;
esac

context_out
exit 0
