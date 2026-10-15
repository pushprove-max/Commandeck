#!/usr/bin/env bash
# ONE row per hook invocation: which hook fired, on what event and tool,
# and whether it allowed, advised, asked or blocked. Nothing recorded which
# hooks fire or how often they block, so a hook that never fires and a hook
# that blocks every call looked the same. Read it with
# scripts/hook-fire-log-summary.sh.
#
# Usage, at the top level of a hook, right after its one read of stdin and
# before its first decision (hook-fire-log-coverage.guard.test.sh checks this):
#   . "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT" [fallback-event]
# The fallback event names a hook run with no payload event (a CLI mode, Codex
# notify). This file never reads stdin itself.
#
# THE DECISION. Exit 2 is the harness's block and any other non-zero exit is an
# operational notice, so both are read from the status. What the status cannot
# say, the hook says with a plain assignment before it prints:
#   HOOK_FIRE_BLOCK=1    a refusal that exits 0 (JSON {"decision":"block"})
#   HOOK_FIRE_ASK=1      a permissionDecision "ask": the owner is asked first
#   HOOK_FIRE_ADVISE=1   a warning or advice that lets the call through
# Block outranks ask, ask outranks advice, and ask counts only on exit 0.
# hook-fire-log-coverage.guard.test.sh fails a hook that prints "ask" unmarked.
# Plain assignments, so a hook whose helper did not load runs exactly as
# before. Set in the hook's own shell: a subshell's is lost.
#
# NO PROCESS PER HOOK (main ruling 2026-10-03). The row is built and appended by
# shell builtins from an EXIT trap that keeps the hook's status and prints
# nothing. Only the first write (mkdir), the sampled retention find, and one
# cksum for the fingerprint of a blocked call or of the session's next call
# start a process. Best effort: an unwritable or full disk loses the row, never changes
# the hook. Rows are appended with no lock -- one short O_APPEND write each, so
# concurrent hooks never interleave a row.
#
# TIMING AND AGENT, on every row: ms_body, the hook's run from arming
# to exit -- it EXCLUDES process startup, the stdin read and loading this
# helper, so it undercounts a fast, frequent hook; agent, "codex" under AGENT_KIND=codex or on a Codex exec- call id, else
# "claude"; wait_ms only when the hook set HOOK_FIRE_WAIT_MS to an integer (the
# part of ms it spent waiting on a lock or job it could see).
#
# STORED: timestamp, hook, event, tool, decision, session_id. Each is read only
# from the top-level metadata and kept only in its own shape (session_id a UUID,
# hook_event_name a capitalised word, tool_name an identifier of at most 96), so
# no quote, newline or prose can reach the log and every row is valid JSON under
# 2 KiB. Two additions, each in its own safe shape:
#   use, call   use on a PreToolUse row whose payload carries a tool_use_id;
#               call (cksum CRC and length of the tool name and the whole
#               tool_input, never the bytes) on a block row and on the
#               session's next call. The
#               summary script compares the two.
#   worktree, summary   on a BLOCK row only: the cwd basename and, in at most
#               80 characters, the command's program names, installed ones
#               only (nothing else; _hook_fire_log_summary) or a file tool's
#               path.
#               Allow and advise rows never carry content.
# One log outside the
# repo for main and every worktree, one file per UTC day:
# $HOME/.claude/hook-fire-log/<project>.<YYYY-MM-DD>.jsonl (lib/project.sh). One write
# in 16 deletes day files past 8 days, so the log always holds the last week.
# COMMANDECK_HOOK_FIRE_LOG names one exact file instead, for the self-tests, and
# nothing beside it is ever deleted.
#
. "${BASH_SOURCE[0]%/*}/project.sh"

# Installed for the user, the plugin's hooks are run in every project on the
# machine. A project setup never touched runs none of them: the hook ends here,
# before its first decision and with no log row. The rule is the one in
# codex-dispatch.sh: .claude/commandeck.json in the checkout or its main
# checkout. Claude Code (and the dispatcher) set CLAUDE_PLUGIN_ROOT for a hook
# run from the plugin; a hook run without it (a self-test) is not gated.
_hook_fire_log_set_up() {
  local d=${CLAUDE_PROJECT_DIR:-$PWD} PP_PROJECT PP_PROJECT_DIR
  [ ! -f "$d/.claude/commandeck.json" ] || return 0
  pp_project "$d"
  [ -n "$PP_PROJECT_DIR" ] && [ -f "$PP_PROJECT_DIR/.claude/commandeck.json" ]
}
[ -z "${CLAUDE_PLUGIN_ROOT-}" ] || _hook_fire_log_set_up || exit 0

hook_fire_log_arm() {
  # Metadata precedes tool_input in every payload, so the head is enough for
  # every field; the whole input is kept only for the call fingerprint.
  # LC_ALL=C: a byte cut, not a char walk.
  local LC_ALL=C
  # tool_use_id is the payload's last key, so it is read from the tail.
  _HOOK_FIRE_INPUT=$1 _HOOK_FIRE_HEAD=${1:0:4096} _HOOK_FIRE_TAIL=${1:$(( ${#1} > 512 ? ${#1} - 512 : 0 ))} _HOOK_FIRE_EVENT=${2-} _HOOK_FIRE_HOOK=${BASH_SOURCE[1]##*/} _HOOK_FIRE_FILE=${BASH_SOURCE[1]} _HOOK_FIRE_PID=${BASHPID-} _HOOK_FIRE_T0=${EPOCHREALTIME-}
  HOOK_FIRE_BLOCK='' HOOK_FIRE_ASK='' HOOK_FIRE_ADVISE='' HOOK_FIRE_WAIT_MS=''
  trap _hook_fire_log_exit EXIT
  return 0
}

_hook_fire_log_exit() {
  local rc=$? decision=allow
  set +eu +o pipefail
  # A subshell never writes the row: only the shell that armed the trap. Bash
  # before 5 (no BASHPID, no %()T) writes none at all.
  [ -n "$_HOOK_FIRE_PID" ] && [ "$BASHPID" = "$_HOOK_FIRE_PID" ] && (( BASH_VERSINFO[0] >= 5 )) || return "$rc"
  if [ "$rc" = 2 ] && [ -z "$HOOK_FIRE_BLOCK" ] && _hook_fire_log_repair; then
    _hook_fire_log_write advise >/dev/null 2>&1
    exit 0
  fi
  if [ -n "$HOOK_FIRE_BLOCK" ] || [ "$rc" = 2 ]; then decision=block
  elif [ -n "$HOOK_FIRE_ASK" ] && [ "$rc" = 0 ]; then decision=ask
  elif [ -n "$HOOK_FIRE_ADVISE" ] || [ "$rc" != 0 ]; then decision=advise
  fi
  _hook_fire_log_write "$decision" >/dev/null 2>&1
  return "$rc"
}

# A hook file that no longer parses exits 2 on every call, the edit that would repair it included, so
# the pane is locked out. Says so in plain words, and returns 0 for the one call the broken
# hook stands down for: an Edit, Write or MultiEdit, before it runs, of that file under its real path.
# Anything looser fails open for whatever the hook guards: a symlink, a ".." path, another letter case
# and a shell command all stay refused, and every other hook still judges the repair edit.
# shortcut: a break above the hook's arming line, a hook emptied to nothing (it exits 0) and a broken
# lib file are not seen here, give hooks one dispatcher if any of them locks a pane out.
_hook_fire_log_repair() {
  local file=$_HOOK_FIRE_FILE dir err
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  err=$("$BASH" -n "$file" 2>&1) && return 1
  dir=$(cd -P -- "$(dirname -- "$file")" 2>/dev/null && pwd -P) || return 1
  file=$dir/${file##*/}
  printf 'HOOK BROKEN: %s does not parse: %s\nIt refuses every call it guards until it is repaired. The one call it lets through is an Edit or Write %s (that exact path); a shell command is not.\n' \
    "$file" "${err%%$'\n'*}" "$file" >&2
  jq -e --arg f "$file" '.hook_event_name == "PreToolUse" and (.tool_name | IN("Edit", "Write", "MultiEdit"))
    and .tool_input.file_path == $f and ([.tool_input.edits[]?.file_path? // empty] | length == 0)' <<<"$_HOOK_FIRE_INPUT" >/dev/null 2>&1
}

# The JSON string at the start of the caller's $rest: its raw text (escapes
# kept) into the caller's $value, the rest after its closing quote into $rest.
# Expansions, not a regex: a regex over a 4 KiB prompt costs milliseconds.
_hook_fire_log_string() {
  local tail=${rest:1} chunk slashes
  value=''
  while [[ $tail == *\"* ]]; do
    chunk=${tail%%\"*}
    tail=${tail:${#chunk}+1}
    slashes=${chunk##*[!\\]}
    value+=$chunk
    # An odd run of backslashes before the quote escapes it: the string goes on.
    (( ${#slashes} % 2 )) || { rest=$tail; return 0; }
    value+='"'
  done
  return 1
}

# TOP-LEVEL MEMBERS ONLY: walks the metadata's "key": value pairs in order and
# sets the caller's f_<key> for the three fields. A string value is kept, any
# other scalar is "", and a nested object or array is stepped over token by
# token, so a key inside it never answers for a top-level one. The walk stops at
# anything it cannot read (the cut end included); fields after that are lost.
# ponytail: a payload of thousands of nested brackets costs one regex per token;
# harness metadata carries none before tool_input, where the head is cut.
_hook_fire_log_walk() {
  local rest=$_HOOK_FIRE_META key value depth seen=' '
  local member='^[[:space:]]*,?[[:space:]]*"([^"\\]*)"[[:space:]]*:[[:space:]]*'
  local scalar='^[-+.0-9A-Za-z]+' open='^[{[]'
  local token='^([][{}:,]|[^][{}:,"[:space:]]+)'
  [[ $rest =~ ^[[:space:]]*\{ ]] || return 0
  rest=${rest:${#BASH_REMATCH[0]}}
  while [[ $rest =~ $member ]]; do
    key=${BASH_REMATCH[1]} value=''
    rest=${rest:${#BASH_REMATCH[0]}}
    if [[ $rest == \"* ]]; then
      _hook_fire_log_string || return 0
    elif [[ $rest =~ $scalar ]]; then
      rest=${rest:${#BASH_REMATCH[0]}}
    elif [[ $rest =~ $open ]]; then
      depth=0
      while :; do
        rest=${rest#"${rest%%[![:space:]]*}"}
        if [[ $rest == \"* ]]; then _hook_fire_log_string || return 0; continue; fi
        [[ $rest =~ $token ]] || break
        rest=${rest:${#BASH_REMATCH[0]}}
        case ${BASH_REMATCH[1]} in
          '{' | '[') ((++depth)) ;;
          '}' | ']') ((--depth == 0)) && break ;;
        esac
      done
      value=''
    else
      return 0
    fi
    case $key in
      hook_event_name | tool_name | session_id | cwd)
        [[ $seen == *" $key "* ]] || { seen+="$key "; printf -v "f_$key" '%s' "$value"; } ;;
    esac
  done
  return 0
}

# Sets the caller's $summary: the PROGRAM NAMES of the blocked command, one per
# pipeline segment (`printf | gh`), and nothing else (main ruling 2026-10-10).
# No flag, argument, assignment, URL, quoted string, comment or heredoc body,
# so no credential reaches the log however it is spelled. A secret-form list
# and then a flag-name parser each missed a new spelling. A file tool keeps
# its path in plain characters: a path is the call's identity, not a value.
_hook_fire_log_summary() {
  local rest=${_HOOK_FIRE_HEAD#*\"tool_input\"} value='' key line l w c p prev='' out='' start=1 redir=0 comment=0
  local quoted='\$'\''([^'\''\\]|\\.)*'\''|'\''[^'\'']*'\''|"([^"\\]|\\.)*"'
  # Any word closes a heredoc (<<123, <<E.O.F), not only an identifier.
  local opener='<<(-?)[[:space:]]*\\?['\''"]?([^][:space:]'\''"<>;&|()]+)'
  local -a docs=() words=()
  summary=''
  [ "$rest" != "$_HOOK_FIRE_HEAD" ] || return 0
  [[ $rest =~ \"(command|file_path|notebook_path)\"[[:space:]]*:[[:space:]]*\" ]] || return 0
  key=${BASH_REMATCH[1]}
  rest=\"${rest#*"${BASH_REMATCH[0]}"}
  _hook_fire_log_string || value=${rest:1}
  if [ "$key" != command ]; then
    value=${value//[^-A-Za-z0-9._\/~+@%,=:]/ }
    summary=${value:0:80}
    return 0
  fi
  # JSON escapes back to the shell text they stand for; \u and other escapes
  # become a space (they only ever sit inside a value).
  value=${value//\\\\/$'\001'}
  value=${value//\\n/$'\n'}
  value=${value//\\\"/\"}
  value=${value//\\u[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ }
  value=${value//\\?/ }
  value=${value//$'\001'/\\}
  # Heredoc bodies, every one an opener line names, are dropped up to their
  # closing line; an unclosed body runs to the end and is dropped whole.
  while IFS= read -r line; do
    if (( ${#docs[@]} )); then
      l=$line
      [ "${docs[0]:0:1}" = - ] && l=${l#"${l%%[!$'\t']*}"}
      [ "$l" = "${docs[0]#-}" ] && docs=("${docs[@]:1}")
      continue
    fi
    out+=$line$'\n'
    l=${line//'<<<'/' < '}
    while [[ $l =~ $opener ]]; do
      docs+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]}")
      l=${l#*"${BASH_REMATCH[0]}"}
    done
  done <<< "$value"
  value=$out out=''
  # A backslash-escaped character belongs to its word (`pw\&x` is one value),
  # so it must never read as a separator.
  value=${value//\\$'\n'/}
  value=${value//\\?/_}
  while [[ $value =~ $quoted ]]; do value=${value/"${BASH_REMATCH[0]}"/ }; done
  # An unclosed quote runs to the end: everything after it is a value.
  value=${value%%[\'\"]*}
  value=${value//$'\n'/ $'\002' }
  for c in '|' ';' '&' '(' ')' '`' '<' '>' '{' '}'; do value=${value//"$c"/" $c "}; done
  read -r -a words <<< "$value"
  for w in "${words[@]}"; do
    [ "$w" = $'\002' ] && comment=0 w=';'
    (( comment )) && continue
    p=$prev prev=$w
    case $w in
      '#'*) comment=1; continue ;;
      # `&>` redirects: the `&` just kept was not a separator.
      '<' | '>') [ "$p" = '&' ] && out=${out% &}; redir=1; continue ;;
      '&') (( redir )) && continue ;;
    esac
    case $w in
      '|' | ';' | '&' | '(' | ')' | '`' | '{' | '}') redir=0 start=1; out+=" $w"; continue ;;
    esac
    if (( redir )); then redir=0; continue; fi
    (( start )) || continue
    # An assignment or keyword comes before the program; neither is kept.
    [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue
    case $w in if | then | else | elif | do | while | until | '!' | time | '$') continue ;; esac
    w=${w##*/}
    # Which words are programs cannot be parsed safely (an array value or a
    # misread heredoc body sits in the program's place), so only the name of a
    # command installed here is kept -- a file on PATH or a builtin, never a
    # function -- and every other word is `?`. Builtins only: no process.
    [[ $w =~ ^[A-Za-z0-9_.+][A-Za-z0-9_.+-]{0,39}$ && ! $w =~ [A-Za-z0-9]{20} ]] \
      && { type -P -- "$w" >/dev/null || compgen -b -X "!$w" -- "$w" >/dev/null; } || w='?'
    out+=" $w" start=0
  done
  # Quoted replacements: bash 5.2 reads a bare & there as the matched text.
  out=${out//'& &'/'&&'}
  out=${out//'| |'/'||'}
  while [[ $out == *' ;' ]]; do out=${out% ;}; done
  out=${out:0:81}
  summary=${out# }
}

_hook_fire_log_write() { # decision
  # C locale: a pattern cut over a 4 KiB head in UTF-8 costs milliseconds.
  local -x TZ=UTC0 LC_ALL=C
  local day log agent=claude ms
  printf -v day '%(%F)T' -1
  local PP_PROJECT PP_PROJECT_DIR; pp_project
  log=${COMMANDECK_HOOK_FIRE_LOG:-$HOME/.claude/hook-fire-log/$PP_PROJECT.$day.jsonl}
  # Whole ms from the digits alone: EPOCHREALTIME always carries 6 decimals.
  ms=$(( (${EPOCHREALTIME//[!0-9]/} - ${_HOOK_FIRE_T0//[!0-9]/}) / 1000 ))
  local event='' tool='' session='' hook=${_HOOK_FIRE_HOOK//[^A-Za-z0-9_.-]/} line
  local f_hook_event_name='' f_tool_name='' f_session_id='' f_cwd='' hex='[0-9A-Fa-f]'
  local extra='' ti end h use='' marker pending='' wt summary
  # METADATA ONLY: the harness sends the top-level fields before tool_input and
  # tool_response, so the head is cut at the first of those keys and content can
  # never answer for a metadata key. A payload that put content first loses its
  # fields; it never gains content. Fields past the 4 KiB head are lost too.
  _HOOK_FIRE_META=${_HOOK_FIRE_HEAD%%\"tool_input\"*}
  _HOOK_FIRE_META=${_HOOK_FIRE_META%%\"tool_response\"*}
  _hook_fire_log_walk
  # Each field is kept only in its own shape; anything else is stored as "".
  [[ $f_hook_event_name =~ ^[A-Z][A-Za-z]{2,31}$ ]] && event=$f_hook_event_name
  [ -n "$event" ] || event=${_HOOK_FIRE_EVENT//[^A-Za-z]/}
  [[ $f_tool_name =~ ^[A-Za-z][A-Za-z0-9_-]{0,95}$ ]] && tool=$f_tool_name
  [[ $f_session_id =~ ^$hex{8}-$hex{4}-$hex{4}-$hex{4}-$hex{12}$ ]] && session=$f_session_id
  umask 077
  # Every hook on one call shares its tool_use_id, so a new id is the session's
  # next call. The fingerprint is one cksum (CRC and length) over the WHOLE
  # action: the tool name, then every byte from "tool_input" to "tool_use_id",
  # never the id itself (one input sent to another tool is a different call).
  # A process costs ~10 ms on a loaded host, so only a block row and the rows of
  # that session's next call pay it (main ruling 2026-10-10): the block leaves
  # its id in pending/<session>, the next call hashes and empties it, and every
  # other call pays one file test.
  if [ "$event" = PreToolUse ] && [[ $_HOOK_FIRE_TAIL =~ \"tool_use_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]{1,96})\" ]]; then
    use=${BASH_REMATCH[1]}
    extra=",\"use\":\"$use\""
    marker=${log%/*}/pending/$session
    [ -n "$session" ] && [ -s "$marker" ] && IFS= read -r pending < "$marker"
    if [ "$1" = block ] || { [ -n "$pending" ] && [ "$pending" != "$use" ]; }; then
      ti=${_HOOK_FIRE_HEAD%%\"tool_input\"*}
      end=${_HOOK_FIRE_TAIL%%\"tool_use_id\"*}
      end=$(( ${#_HOOK_FIRE_INPUT} - ${#_HOOK_FIRE_TAIL} + ${#end} ))
      if [ "$ti" != "$_HOOK_FIRE_HEAD" ] && (( end > ${#ti} )) \
        && h=$(cksum <<<"$tool:${_HOOK_FIRE_INPUT:${#ti}:end-${#ti}}") && [[ $h =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        extra+=",\"call\":\"${BASH_REMATCH[1]}.${BASH_REMATCH[2]}\""
      fi
      if [ "$1" != block ]; then
        : > "$marker"
      elif [ -n "$session" ] && { [ -d "${marker%/*}" ] || mkdir -p -m 700 "${marker%/*}"; }; then
        # The newline lets `read` succeed: a failed read ends a `set -e` hook.
        printf '%s\n' "$use" > "$marker"
      fi
    fi
  fi
  if [ "$1" = block ]; then
    # A refused call never runs, so no tool-end follows its tool-start. A
    # Builder's event log (builder-event-log.sh) gets the outcome here, once for
    # every guard; dashboard_builders.jq closes the call by this id.
    local builder=${CLAUDE_PROJECT_DIR-}/.claude/builder-events.jsonl
    [ -n "$use" ] && [ -n "${CLAUDE_PROJECT_DIR-}" ] && { [ "${COMMANDECK_BUILDER-}" = 1 ] || [ -f "$builder" ]; } \
      && printf '{"ts":"%(%Y-%m-%dT%H:%M:%SZ)T","event":"tool-refused","use":"%s","hook":"%s"}\n' -1 "$use" "${hook:0:64}" >> "$builder"
    wt=${f_cwd:-$PWD}
    wt=${wt%/}
    wt=${wt##*/}
    wt=${wt//[^A-Za-z0-9._-]/}
    _hook_fire_log_summary
    extra+=",\"worktree\":\"${wt:0:64}\",\"summary\":\"$summary\""
  fi
  [[ ${HOOK_FIRE_WAIT_MS-} =~ ^[0-9]{1,9}$ ]] && extra+=",\"wait_ms\":$((10#$HOOK_FIRE_WAIT_MS))"
  [ "${AGENT_KIND-}" = codex ] || [[ $use == exec-* ]] && agent=codex
  printf -v line '{"timestamp":"%(%Y-%m-%dT%H:%M:%SZ)T","hook":"%s","event":"%s","tool":"%s","decision":"%s","session_id":"%s","agent":"%s","ms_body":%d%s}' \
    -1 "${hook:0:64}" "${event:0:32}" "$tool" "$1" "$session" "$agent" "$ms" "$extra"
  [ -d "${log%/*}" ] || mkdir -p -m 700 "${log%/*}" || return 0
  # RETENTION IS SAMPLED, default path only: one write in 16 deletes the day
  # files past 8 days. No lock: two deleters remove the same files.
  [ -z "${COMMANDECK_HOOK_FIRE_LOG-}" ] && (( RANDOM % 16 == 0 )) \
    && find "${log%/*}" -maxdepth 1 -type f -name "$PP_PROJECT.*.jsonl" -mtime +8 -delete
  printf '%s\n' "$line" >> "$log"
}
