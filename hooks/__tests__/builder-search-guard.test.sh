#!/usr/bin/env bash
# Self-test for builder-search-guard.sh. Run: bash hooks/__tests__/builder-search-guard.test.sh
#
# Pinned: three searches in a row are small, the fourth goes to Explore, and an
# Edit, Write or Agent call starts the count again -- without that reset a
# Builder would be locked out of searching for the rest of its session. A
# whole-repo search is refused on call 1; a subagent is never counted.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; rm -f /tmp/claude-builder-search-streak-gs-*' EXIT
GUARD=$REAL/hooks/builder-search-guard.sh
mkdir -p "$TMP/g"
ev() { CLAUDE_PROJECT_DIR=$TMP/g bash "$GUARD" <<<"$(jq -c --arg e "$1" --arg s "$2" '. + {hook_event_name:$e, session_id:$s}' <<<"$3")"; }
sgr() { ev PreToolUse "$1" "$2" 2>"$TMP/gerr"; echo $?; } # sgr <session> <json>: asked only, as when another guard refuses the call; prints the exit code, stderr in $TMP/gerr
sg() { local rc; rc=$(sgr "$1" "$2"); [ "$rc" != 0 ] || ev PostToolUse "$1" "$2"; echo "$rc"; } # a call that ran when let through
tool() { jq -cn --arg t "$1" --argjson i "$2" '{tool_name:$t, tool_input:$i}'; }
bash_() { tool Bash "$(jq -cn --arg c "$1" '{command:$c}')"; }
GREP=$(tool Grep '{"pattern":"x","path":"src"}'); GLOB=$(tool Glob '{"pattern":"*.ts","path":"src"}')
# The refusal names what runs at once: each refusal costs a request, and a retry that guesses costs another.
EXPLORE_LINE='This is now a large search (4+ lookups in a row). Allowed now, and not counted: the Read tool, or a plain `grep -n <pattern> <file>...` with no -r, for files you already know; mcp__serena__find_symbol or find_referencing_symbols for a symbol; an Explore subagent (Agent, subagent_type Explore) for anything wider. An Edit, Write or Agent call, or 10 minutes with no search, starts the count again.'
rm -f /tmp/claude-builder-search-streak-gs-*
check "searches 1-3 of a streak pass" "0 0 0" "$(echo "$(sg gs-1 "$GREP") $(sg gs-1 "$GLOB") $(sg gs-1 "$(bash_ 'rg x src')")")"
check "the 4th is refused" 2 "$(sg gs-1 "$GREP")"
check "the refusal is one line naming Agent and Explore" "1 $EXPLORE_LINE" "$(wc -l < "$TMP/gerr" | tr -d ' ') $(cat "$TMP/gerr")"
check "an Agent call resets the streak" "0 0" "$(echo "$(sg gs-1 "$(tool Agent '{"subagent_type":"Explore"}')") $(sg gs-1 "$GREP")")"
for t in Edit Write; do
  sg gs-1 "$GREP" >/dev/null; sg gs-1 "$GREP" >/dev/null; sg gs-1 "$GREP" >/dev/null
  check "a $t call resets after a refusal" "2 0 0" "$(echo "$(sg gs-1 "$GREP") $(sg gs-1 "$(tool $t '{"file_path":"a"}')") $(sg gs-1 "$GREP")")"
done
check "a whole-repo Grep and Glob (no path) are refused on call 1" "2 2" "$(echo "$(sg gs-2 "$(tool Grep '{"pattern":"x"}')") $(sg gs-3 "$(tool Glob '{"pattern":"*"}')")")"
check "find . is whole-repo on call 1" 2 "$(sg gs-4 "$(bash_ 'find . -name y')")"
check "find on a directory is a small search" 0 "$(sg gs-5 "$(bash_ 'find src -name y')")"
# A refused or counted Explore subagent would leave the Builder no way to do a large search.
SUB=$(jq -c '. + {agent_id:"a1", agent_type:"Explore"}' <<<"$GREP")
check "four subagent searches all pass, and the main session is still on call 1" "0 0 0 0 0" \
  "$(echo "$(sg gs-6 "$SUB") $(sg gs-6 "$SUB") $(sg gs-6 "$SUB") $(sg gs-6 "$SUB") $(sg gs-6 "$GREP")")"
# Reads sent together in one turn are ONE lookup. A Builder refused on turns that
# carried several reads went on to read one file per turn, each turn replaying the whole context.
# A turn's calls are the tool_use blocks sharing one message id in the transcript.
export COMMANDECK_SEARCH_SIBLING_MS=0
aged() { printf '3 %s\n' $(( $(date +%s) - $2 )) > "/tmp/claude-builder-search-streak-$1"; } # aged <session> <seconds>: three lookups, the last that long ago
TX=$TMP/gs-tx.jsonl
tx() { local m=$1 i; shift; for i in "$@"; do jq -cn --arg m "$m" --arg i "$i" '{type:"assistant",message:{id:$m,content:[{type:"tool_use",id:$i,name:"Grep",input:{pattern:$i,path:"src"}}]}}'; done >> "$TX"; } # tx <message id> <tool_use id>...: one scoped search per block, one line per block, as Claude Code writes them
inb() { jq -c --arg u "$2" --arg t "$TX" '. + {tool_use_id:$u, transcript_path:$t}' <<<"$1"; } # inb <call json> <tool_use id>
: > "$TX"; tx msg-a u1 u2 u3; aged gs-b 1
check "a batch of three reads is allowed where a lone fourth lookup is refused" "0 0 0" \
  "$(echo "$(sg gs-b "$(inb "$GREP" u1)") $(sg gs-b "$(inb "$GLOB" u2)") $(sg gs-b "$(inb "$(bash_ 'rg x src')" u3)")")"
check "and the batch counts once: three lookups became four, not six" 4 "$(cut -d' ' -f1 /tmp/claude-builder-search-streak-gs-b)"
: > "$TX"; tx msg-b v1 v2 v3; rm -f /tmp/claude-builder-search-streak-gs-c
check "a batch is one lookup: it and two more are allowed, the next lone lookup is the fourth and is refused" "0 0 0 0 0 2" \
  "$(echo "$(for u in v1 v2 v3; do sg gs-c "$(inb "$GREP" $u)"; done | paste -sd' ' -) $(sg gs-c "$GREP") $(sg gs-c "$GREP") $(sg gs-c "$GREP")")"
: > "$TX"; tx msg-c w1 w2
check "a whole-repo search is still refused inside a batch" "2 2" \
  "$(echo "$(sg gs-d "$(inb "$(tool Grep '{"pattern":"x"}')" w1)") $(sg gs-d2 "$(inb "$(bash_ 'find . -name y')" w2)")")"
check "a lone lookup that the transcript shows as the only call of its turn is still counted and refused" 2 \
  "$(: > "$TX"; tx msg-d x1; aged gs-e 1; sg gs-e "$(inb "$GREP" x1)")"
check "a call the transcript does not hold yet is a lone lookup: refused" 2 \
  "$(: > "$TX"; tx msg-f y1 y2; aged gs-f 1; sg gs-f "$(inb "$GREP" y9)")"
# Only searches make a batch: a lone search sent with any other call each turn would never be refused.
txc() { jq -cn --arg m "$1" --arg i "$2" --arg t "$3" --argjson in "$4" '{type:"assistant",message:{id:$m,content:[{type:"tool_use",id:$i,name:$t,input:$in}]}}' >> "$TX"; } # txc <message id> <tool_use id> <tool> <input>
check "a lone search sent with a call that is no search is refused, a Read or a Bash that searches nothing" "2 2" \
  "$(: > "$TX"; txc msg-g z1 Grep '{"path":"src"}'; txc msg-g z2 Bash '{"command":"true"}'; txc msg-h z3 Grep '{"path":"src"}'; txc msg-h z4 Read '{"file_path":"a"}'
     aged gs-g 1; aged gs-h 1; echo "$(sg gs-g "$(inb "$GREP" z1)") $(sg gs-h "$(inb "$GREP" z3)")")"
check "a Bash sibling that searches still makes a batch" 0 \
  "$(: > "$TX"; txc msg-i z5 Grep '{"path":"src"}'; txc msg-i z6 Bash '{"command":"cd src &&\nrg -n x"}'; aged gs-i 1; sg gs-i "$(inb "$GREP" z5)")"
# Pass 2: a sibling that adds no allowed lookup makes no batch either. Heredoc data is no search (the command's
# newlines are kept), a refused whole-repo search never runs, and the same search twice is one lookup.
check "a lone search sent with a Bash whose search is heredoc data is refused" 2 \
  "$(: > "$TX"; txc msg-k k1 Grep '{"pattern":"x","path":"src"}'; txc msg-k k2 Bash '{"command":"cat <<EOF\nrg x src\nEOF"}'; aged gs-k 1; sg gs-k "$(inb "$GREP" k1)")"
check "a lone search sent with a refused whole-repo search is refused, a Grep with no path or a find ." "2 2" \
  "$(: > "$TX"; txc msg-l l1 Grep '{"pattern":"x","path":"src"}'; txc msg-l l2 Grep '{"pattern":"x"}'; txc msg-m m1 Grep '{"pattern":"x","path":"src"}'; txc msg-m m2 Bash '{"command":"find . -name y"}'
     aged gs-l 1; aged gs-m 1; echo "$(sg gs-l "$(inb "$GREP" l1)") $(sg gs-m "$(inb "$GREP" m1)")")"
check "a lone search sent with itself again is refused" 2 \
  "$(: > "$TX"; txc msg-n n1 Grep '{"pattern":"x","path":"src"}'; txc msg-n n2 Grep '{"pattern":"x","path":"src"}'; aged gs-n 1; sg gs-n "$(inb "$GREP" n1)")"
check "a comment line before a search keeps the search: a batch" 0 \
  "$(: > "$TX"; txc msg-o o1 Grep '{"pattern":"x","path":"src"}'; txc msg-o o2 Bash '{"command":"# look in src\nrg -n x src"}'; aged gs-o 1; sg gs-o "$(inb "$GREP" o1)")"
# A batch's first call can end before its siblings are on disk: the batch still counts once, by its message id.
rm -f /tmp/claude-builder-search-streak-gs-j; : > "$TX"; tx msg-j j1
ev PostToolUse gs-j "$(inb "$GREP" j1)"; tx msg-j j2; ev PostToolUse gs-j "$(inb "$GREP" j2)"
check "a batch whose siblings reach the transcript late still counts once" 1 "$(cut -d' ' -f1 /tmp/claude-builder-search-streak-gs-j)"
unset COMMANDECK_SEARCH_SIBLING_MS

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
