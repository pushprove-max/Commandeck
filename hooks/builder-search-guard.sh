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
# Self-test: bash scripts/__tests__/builder.test.sh
LIMIT=3
GAP=600
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
{
  IFS=$'\001' read -r AID SID TOOL PTH EVT
  CMD=$(cat)
} < <(jq -r '([.agent_id // "", .session_id // "", .tool_name // "", (.tool_input.path // .tool_input.relative_path // ""), .hook_event_name // ""] | join("\u0001")),
  (.tool_input.command // "")' <<<"$INPUT" 2>/dev/null)
[ -z "$AID" ] || exit 0
STREAK=/tmp/claude-builder-search-streak-${SID:-none}
ROOT=${CLAUDE_PROJECT_DIR:-}
ROOT=${ROOT%/}
WHOLE=0

case "$TOOL" in
  Edit|Write|MultiEdit|Agent|Task) : > "$STREAK"; exit 0 ;;
  Grep|Glob|mcp__serena__search_for_pattern)
    P=${PTH%/}
    case "$P" in ''|.) WHOLE=1 ;; *) [ -n "$ROOT" ] && [ "$P" = "$ROOT" ] && WHOLE=1 ;; esac ;;
  mcp__codebase-memory__search_code|mcp__codebase-memory__search_graph) ;;
  Bash)
    P=${CMD//[\'\"\\]/}
    case "$P" in *rg*|*grep*|*find*) ;; *) exit 0 ;; esac
    # shellcheck source=lib/strip-quoted.sh
    . "${BASH_SOURCE[0]%/*}/lib/strip-quoted.sh" 2>/dev/null || exit 0
    M=$'\x01'
    # strip_quoted drops an empty quoted argument; keep its place, or the flag
    # after `-e ""` is read as the pattern.
    E=${CMD//\"\"/\"$M\"}; E=${E//\'\'/\'$M\'}
    S=$(strip_quoted "$E" "$M")
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
        rg) FOUND=1 ;;
        git) [ "${W[i+1]:-}" = grep ] && FOUND=1 ;;
        grep)
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
    [ "$FOUND" = 1 ] || exit 0 ;;
  *) exit 0 ;;
esac

N=0 AT=''
{ read -r N AT < "$STREAK"; } 2>/dev/null
case "$N" in ''|*[!0-9]*) N=0 ;; esac
printf -v NOW '%(%s)T' -1
case "$AT" in ''|*[!0-9]*) ;; *) [ $((NOW - AT)) -le "$GAP" ] || N=0 ;; esac
case "$EVT" in PostToolUse*) printf '%s %s\n' $((N+1)) "$NOW" > "$STREAK"; exit 0 ;; esac
if [ "$WHOLE" = 1 ]; then
  REASON=whole-repo
  MSG='A whole-repo search is a large search. Hand it to an Explore subagent (Agent, subagent_type Explore), or name a directory.'
else
  [ "$N" -ge "$LIMIT" ] || exit 0
  REASON=streak
  MSG="This is now a large search ($((LIMIT+1))+ lookups). Hand it to an Explore subagent (Agent, subagent_type Explore)."
fi

ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
if [ -n "$ROOT" ] && mkdir -p "$ROOT/.claude"; then
  # use: a refused call never runs, so no tool-end follows its tool-start; dashboard_builders.jq closes it by this id.
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg t "$TOOL" --arg r "$REASON" --arg u "$(jq -r '.tool_use_id // empty' <<<"$INPUT")" \
    '{ts: $ts, event: "search-refused", tool: $t, reason: $r, use: (if $u == "" then null else $u end)}' >> "$ROOT/.claude/builder-events.jsonl"
fi
echo "$MSG" >&2
exit 2
