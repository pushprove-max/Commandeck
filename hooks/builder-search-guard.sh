#!/usr/bin/env bash
# Builder search guard: a Builder's main session may run LIMIT searches
# in a row; the next one, or any whole-repo search, is refused toward an Explore
# subagent. An Edit, Write or Agent call restarts the count. Subagents (non-empty
# agent_id) are never counted or refused. Registered only in a Builder worktree's
# settings.local.json by worktree-setup.sh --builder. Refusals are appended to
# <worktree>/.claude/builder-events.jsonl.
# Only a search that ran counts: the count is taken after the call
# (PostToolUse, PostToolUseFailure), which never comes for a call another guard
# refused. Before the call the guard only reads the count.
# LIMIT is a starting value, not measured: tune it from the search-refused and
# subagent-start rows. Reads are deliberately not counted: the hook cannot know
# which file is about to be edited.
# A search more than GAP seconds after the last counted one starts the count
# again: single lookups spread over a fix round with no edit between
# them are separate questions, not one large search. The streak file holds the
# count and the time of the last counted search. GAP is a starting value too.
# Reads sent together in one turn are ONE lookup: allowed, and counted once. The searches
# of a turn are the tool_use blocks sharing one message id in the transcript that this guard
# counts as searches and lets through, each distinct one once; other calls beside one search make no batch.
# A whole-repo search is refused whatever the turn carries.
# Self-test: bash hooks/__tests__/builder-search-guard.test.sh
LIMIT=3
GAP=600
SIB=${COMMANDECK_SEARCH_SIBLING_MS:-1500}
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
{
  IFS=$'\001' read -r AID SID TOOL PTH EVT TUID TXP PAT
  CMD=$(cat)
} < <(jq -r '([.agent_id // "", .session_id // "", .tool_name // "", (.tool_input.path // .tool_input.relative_path // ""), .hook_event_name // "", .tool_use_id // "", .transcript_path // "", (.tool_input.pattern // "" | gsub("[\u0001\n]"; " "))] | join("\u0001")),
  (.tool_input.command // "")' <<<"$INPUT" 2>/dev/null)
[ -z "$AID" ] || exit 0
STREAK=/tmp/claude-builder-search-streak-${SID:-none}
ROOT=${CLAUDE_PROJECT_DIR:-}
ROOT=${ROOT%/}

case "$TOOL" in Edit|Write|MultiEdit|Agent|Task) : > "$STREAK"; exit 0 ;; esac
# operand <index> -- PAT is the first word of W from there that is no flag: the pattern, as a search names it.
operand() { local A; for A in "${W[@]:$1}"; do case "$A" in -*) ;; *) PAT=$A; return ;; esac; done; }
# search <tool> <path> <command> -- 0 for a search, with WHOLE=1 for a whole-repo one; 1 for any other call.
search() {
  local P M E S FOUND SEG W k V i C SKIP A OP CMD=$3
  WHOLE=0
  case "$1" in
  Grep|Glob|mcp__serena__search_for_pattern)
    P=${2%/}
    case "$P" in ''|.) WHOLE=1 ;; *) [ -n "$ROOT" ] && [ "$P" = "$ROOT" ] && WHOLE=1 ;; esac ;;
  mcp__codebase-memory__search_code|mcp__codebase-memory__search_graph) ;;
  Bash)
    P=${CMD//[\'\"\\]/}
    case "$P" in *rg*|*grep*|*find*) ;; *) return 1 ;; esac
    # shellcheck source=lib/strip-quoted.sh
    . "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null || return 1
    M=$'\x01'
    # An empty quoted argument prints the mark, so the flag after `-e ""` is not read as the pattern.
    S=$(strip_quoted "$CMD" "$M")
    S=${S//||/$'\n'}; S=${S//&/$'\n'}; S=${S//;/$'\n'}; S=${S//(/$'\n'}; S=${S//\`/$'\n'}
    FOUND=0
    while IFS= read -r SEG; do
      SEG=${SEG%%|*}
      read -ra W <<<"$SEG"
      # A quoted word is the argument bash passes, so it is read like a typed one.
      # A quoted span of prose stays the bare mark: an operand, never a command or a root.
      for k in "${!W[@]}"; do V=${W[k]//$M/}; [ -z "$V" ] || W[k]=$V; done
      i=0
      while [ "$i" -lt "${#W[@]}" ]; do
        case "${W[i]}" in *=*|env) i=$((i+1)) ;; *) break ;; esac
      done
      C=${W[i]:-}; C=${C##*/}
      case "$C" in
        rg) FOUND=1; operand $((i+1)) ;;
        git) [ "${W[i+1]:-}" = grep ] && FOUND=1 && operand $((i+2)) ;;
        grep)
          operand $((i+1))
          SKIP=0
          for A in "${W[@]:i+1}"; do
            [ "$SKIP" = 0 ] || { SKIP=0; continue; }
            case "$A" in
              --) break ;;
              --recursive|--dereference-recursive|--directories=recurse) FOUND=1; break ;;
              --regexp|--file) SKIP=1 ;;
              --*) ;;
              -?*)
                # A letter that takes a value ends the cluster: the rest of the
                # word, or the next word, is a pattern or a file, not flags.
                V=${A#-}
                while [ -n "$V" ]; do
                  case "$V" in
                    [rR]*) FOUND=1; break 2 ;;
                    [efmABCdD]) SKIP=1; break ;;
                    [efmABCdD]*) break ;;
                  esac
                  V=${V#?}
                done ;;
            esac
          done ;;
        find)
          FOUND=1; OP=""
          for A in "${W[@]:i+1}"; do
            case "$A" in -[LHP]) ;; -*|\!) break ;; *) OP=${A%/}; break ;; esac
          done
          case "$OP" in ''|.|'$CLAUDE_PROJECT_DIR'|'${CLAUDE_PROJECT_DIR}'|'$PWD') WHOLE=1 ;; *) [ -n "$ROOT" ] && [ "$OP" = "$ROOT" ] && WHOLE=1 ;; esac ;;
      esac
    done <<<"$S"
    [ "$FOUND" = 1 ] || return 1 ;;
  *) return 1 ;;
  esac
  return 0
}
search "$TOOL" "$PTH" "$CMD" || exit 0
# allow -- let the search run; a search for one bare identifier is told the symbol lookup that answers it in one call.
allow() {
  [[ $EVT == PreToolUse && $PAT =~ ^[A-Za-z_][A-Za-z0-9_]{3,}$ ]] && HOOK_FIRE_ADVISE=1 \
    && jq -cn --arg m "Note: \`$PAT\` is one identifier. A symbol lookup answers it in one call: mcp__serena__find_symbol (name_path $PAT, include_body for its source) or find_referencing_symbols for its callers, instead of a search and a read." \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
  exit 0
}

# Prints "<searches in this call's turn> <message id>"; 0 when the call is not on disk yet (the transcript lags the hook).
# Only distinct searches that are let through count: a lone search sent with any other call, a whole-repo search
# (always refused) or the same search again is no batch. Records end in NUL, so a command keeps its newlines and
# its heredoc data stays data.
turn_calls() {
  local n=0 id='' t p c W0=$WHOLE P0=$PAT
  [ -n "$TUID" ] && [ -r "$TXP" ] || { echo "0 "; return; }
  {
    read -r -d '' id
    while IFS=$'\001' read -r -d '' t p c; do ! search "$t" "$p" "$c" || [ "$WHOLE" = 1 ] || n=$((n + 1)); done
  } < <(tail -n 400 "$TXP" | grep -F '"type":"assistant"' | jq -js --arg u "$TUID" '
    (map(select(any((.message.content // [])[]; .type == "tool_use" and .id == $u))) | last) as $m
    | if $m == null or $m.message.id == null then empty
      else $m.message.id as $id | $id + "\u0000", ([map(select(.message.id == $id))[] | (.message.content // [])[] | select(.type == "tool_use")]
        | unique_by([.name, .input])[] | [.name, (.input.path // .input.relative_path // ""), (.input.command // "")] | join("\u0001") + "\u0000") end' 2>/dev/null)
  WHOLE=$W0 PAT=$P0
  [ -n "$id" ] || n=0
  echo "$n $id"
}
N=0 AT='' MID=''
{ read -r N AT MID < "$STREAK"; } 2>/dev/null
case "$N" in ''|*[!0-9]*) N=0 ;; esac
NOW=$(date +%s)
case "$AT" in ''|*[!0-9]*) ;; *) [ $((NOW - AT)) -le "$GAP" ] || N=0 ;; esac
case "$EVT" in PostToolUse*)
  # Every counted call keeps its message id: a sibling that reaches the transcript late is then not counted again.
  read -r _ CMID < <(turn_calls)
  [ -z "$CMID" ] || [ "$CMID" != "$MID" ] || exit 0
  printf '%s %s %s\n' $((N+1)) "$NOW" "$CMID" > "$STREAK"; exit 0 ;;
esac
if [ "$WHOLE" = 1 ]; then
  REASON=whole-repo
  MSG='A whole-repo search is a large search. Hand it to an Explore subagent (Agent, subagent_type Explore), or name a directory.'
else
  [ "$N" -ge "$LIMIT" ] || allow
  # The first call of a batch can be checked before its siblings are on disk: wait one sibling window, then count again.
  if [ -n "$TUID" ] && [ -r "$TXP" ]; then
    sleep "$((SIB / 1000)).$(printf '%03d' $((SIB % 1000)))"
    read -r CALLS _ < <(turn_calls); [ "${CALLS:-0}" -lt 2 ] || allow
  fi
  REASON=streak
  # The refusal names the forms that run now: each refusal costs a request, and a retry that guesses costs another.
  MSG="This is now a large search ($((LIMIT+1))+ lookups in a row). Allowed now, and not counted: the Read tool, or a plain \`grep -n <pattern> <file>...\` with no -r, for files you already know; mcp__serena__find_symbol or find_referencing_symbols for a symbol; an Explore subagent (Agent, subagent_type Explore) for anything wider. An Edit, Write or Agent call, or $((GAP / 60)) minutes with no search, starts the count again."
fi

ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
if [ -n "$ROOT" ] && mkdir -p "$ROOT/.claude"; then
  # use: a refused call never runs, so no tool-end follows its tool-start; dashboard_builders.jq closes it by this id.
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg t "$TOOL" --arg r "$REASON" --arg u "$(jq -r '.tool_use_id // empty' <<<"$INPUT")" \
    '{ts: $ts, event: "search-refused", tool: $t, reason: $r, use: (if $u == "" then null else $u end)}' >> "$ROOT/.claude/builder-events.jsonl"
fi
echo "$MSG" >&2
exit 2
