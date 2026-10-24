#!/usr/bin/env bash
# context-overhead.sh <plugin root> [--one-bash '<command>'] -- the bytes a scripted main session's hooks attach to the
# model's context, per hook and in total (issue 327). It replays a fixed session through every hook that
# <plugin root>/hooks/hooks.json wires for each event and tool: a SessionStart, 3 prompts, 12 Reads of distinct files
# (5 in one folder), then 12 routine Bash calls (git status, git log -1, rg -n, ls, sed -n, jq), every call its own turn
# so the lone-look streak builds. --one-bash replays one Bash call alone. Run it on two plugin roots (a base worktree
# and the tip) to compare them.
#
# What counts is what Claude Code passes to the model (Claude Code hooks reference, "Hook input and output": Exit code
# output and JSON output): SessionStart and UserPromptSubmit plain stdout; any `additionalContext`; a
# `permissionDecisionReason` or `reason`; and the stderr of an exit 2. Other stdout and stderr stay in the debug log or the
# UI. The fixture project sets strictHooks, so the strict-tier hooks main runs only then are measured too. The harness's
# own attachments (skill listing, instructions, task reminders) are not hook output and are not measured; the project's
# path-scoped rule files, which the harness attaches when a matching file is read, are listed by size at the end.
# Prints "<bytes> <event> <tool> <hook>" for each hook that attached anything, then "total <bytes>".
case ${1-} in -h|--help|'') sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p;}' "$0" | head -3; exit 0 ;; esac
set -uo pipefail
ROOT=$(cd "$1" && pwd) || exit 2; shift
ONE= ; [ "${1-}" != --one-bash ] || { ONE=${2:?--one-bash takes a command}; }
[ -f "$ROOT/hooks/hooks.json" ] || { echo "context-overhead: no hooks/hooks.json under $ROOT" >&2; exit 2; }
HERE=$PWD
S=$(mktemp -d "${TMPDIR:-/tmp}/context-overhead.XXXXXX") || exit 2
S=$(cd "$S" && pwd -P)
sid="co-$$-$RANDOM"
trap 'rm -rf "$S"; rm -f /tmp/claude-*-"$sid"' EXIT # the hooks keep their per-session state under /tmp, named for the session
P=$S/proj; mkdir -p "$S/home" "$S/tmp" "$P/.claude" "$P/src" "$P/docs"
git init -q -b main "$P" && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
echo '{"version": 1, "profile": "claude", "strictHooks": true}' > "$P/.claude/commandeck.json"
# The plugin names itself by this stable link in what it prints, so two roots of different path length print the same text.
mkdir -p "$S/home/.commandeck" && ln -s "$ROOT" "$S/home/.commandeck/plugin"
for i in $(seq 1 12); do d=docs; [ "$i" -le 5 ] && d=src; seq 1 30 | sed "s/^/line /" > "$P/$d/f$i.txt"; done

# run <event> <tool> <payload json> -- every hook wired for that event and tool, on that payload.
run() {
  local ev=$1 tool=$2 payload=$3 m cmd out err rc n
  while IFS=$'\t' read -r m cmd; do
    [[ $tool =~ ^($m)$ ]] || continue
    out=$(cd "$P" && printf '%s' "$payload" | env -i PATH="$PATH" HOME="$S/home" TMPDIR="$S/tmp" LC_ALL=C CLAUDE_PLUGIN_ROOT="$ROOT" \
      COMMANDECK_HOOK_FIRE_LOG="$S/fire.jsonl" BATCH_SIBLING_MS=0 bash -c "$cmd" 2>"$S/err"); rc=$?
    err=$(<"$S/err")
    if [ "$rc" = 2 ]; then n=${#err}
    else
      n=$(jq -r '[.hookSpecificOutput.additionalContext?, .hookSpecificOutput.permissionDecisionReason?, .reason?, .additionalContext?]
        | map(select(type == "string")) | join("")' <<<"$out" 2>/dev/null) \
        || { case $ev in SessionStart|UserPromptSubmit) n=$out ;; *) n= ;; esac; }
      n=${#n}
    fi
    [ "$n" -eq 0 ] || { cmd=${cmd##*/hooks/}; cmd=${cmd%%[\" ]*}; echo "$n $ev ${tool:--} $cmd" >> "$S/rows"; }
  done < <(jq -r --arg e "$ev" '.hooks[$e] // [] | .[] | (.matcher // ".*") as $m | .hooks[] | [$m, .command] | @tsv' "$ROOT/hooks/hooks.json")
}
: > "$S/rows"
pay() { jq -cn --arg e "$1" --arg t "${2-}" --arg s "$sid" --arg d "$P" --argjson i "${3:-null}" --arg p "${4-}" \
  '{hook_event_name: $e, session_id: $s, cwd: $d, tool_name: $t, tool_input: $i, tool_response: {stdout: "", stderr: "", interrupted: false}}
   + (if $p == "" then {} else {prompt: $p} end)'; }
call() { # <tool> <tool_input json>
  run PreToolUse "$1" "$(pay PreToolUse "$1" "$2")"; run PostToolUse "$1" "$(pay PostToolUse "$1" "$2")"; }
if [ -n "$ONE" ]; then call Bash "$(jq -cn --arg c "$ONE" '{command: $c}')"
else
  run SessionStart "" "$(pay SessionStart)"
  for p in "check the build" "what changed" "continue"; do run UserPromptSubmit "" "$(pay UserPromptSubmit "" null "$p")"; done
  for i in $(seq 1 12); do d=docs; [ "$i" -le 5 ] && d=src; call Read "$(jq -cn --arg f "$P/$d/f$i.txt" '{file_path: $f}')"; done
  for c in 'git status' 'git log -1' 'rg -n line src' 'ls docs' 'sed -n 1,5p docs/f6.txt' 'jq -r .profile .claude/commandeck.json' \
           'git status' 'git log -1' 'rg -n line docs' 'ls src' 'sed -n 1,5p src/f1.txt' 'jq -r .version .claude/commandeck.json'; do
    call Bash "$(jq -cn --arg c "$c" '{command: $c}')"
  done
fi
awk '{ b[$2" "$3" "$4] += $1; t += $1 } END { for (k in b) print b[k], k; print "total", t + 0 }' "$S/rows" | sort -k1,1nr | awk '$1 != "total"; $1 == "total" { t = $0 } END { print t }'
if [ -z "$ONE" ]; then
  echo "path-scoped rule files in $HERE (the harness attaches one when a matching file is read; whose they are is the project's):"
  { rg -l '^paths:' "$HERE/.claude/rules" 2>/dev/null || true; } | while read -r f; do echo "  $(wc -c < "$f" | tr -d ' ') bytes $f"; done
fi
