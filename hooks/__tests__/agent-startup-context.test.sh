#!/usr/bin/env bash
# agent-startup-context.test.sh -- what a session loads at start, read from a hand-written commandeck.json and rule
# files (no setup run). What this pins: a path the session prints names the plugin by its stable link, which
# outlives an update; the owner's own startup file loads, and the plugin's main-session when the owner chose it;
# with rules merge a plugin rule the project's rule files already state is not loaded twice, read as Claude Code
# reads them: a path-scoped file, an excluded one, a Builder's excluded agents.md and frontmatter not read for
# sure stand in for no plugin rule (a duplicate line beats a lost rule); keep-mine and keep-both are honoured; and
# each seat decides for the merged block when it starts.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME"; unset CLAUDE_CONFIG_DIR # the caller's profile is never read
# project <dir> <config json> -- a checkout with that commandeck.json and nothing else of the plugin's.
project() { git init -q -b main "$1" && git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first; mkdir -p "$1/.claude/rules"; jq -n "{version: 1, profile: \"claude\"} + ($2)" > "$1/.claude/commandeck.json"; }
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }
# ctx <dir> [builder] -- the session-start context of a seat in that checkout.
ctx() { (cd "$1" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u COMMANDECK_SCRATCH ${2:+COMMANDECK_BUILDER=1} bash "$REAL/hooks/agent-startup-context.sh" </dev/null 2>/dev/null); }
ex() { jq -n --arg x "$2" '{claudeMdExcludes: [$x]}' > "$1"; }
# one1 <template> <n> -- its nth one-line top-level bullet that names no path the session hook rewrites.
one1() { awk '/^- / && !/scripts\/|hooks\/|templates\/|200K/ { if (p) print p; p = $0; next } { if (p && ($0 == "" || /^- /)) print p; p = "" }' "$1" | sed -n "${2}p"; }
MS() { awk '/^## Details \(not injected\)/ {exit} 1' "$REAL/templates/main-session.md"; }   # the part sessions load
S1=$(one1 "$REAL/templates/AGENT_STARTUP.md" 1) S2=$(one1 "$REAL/templates/AGENT_STARTUP.md" 2) M1=$(one1 <(MS) 1)
# Another rule sessions load, by its id and its first line (merge-rules.py --units).
U=$(python3 "$REAL/scripts/merge-rules.py" <(MS) --units | awk -F'\t' -v m="$M1" 'length($2) < 100 && $2 ~ /^- / && $2 != m && $2 !~ /scripts\/|hooks\/|templates\/|200K/' | head -1)
ID=${U%%$'\t'*} M2=${U#*$'\t'}
# A rule 0.14.1 reworded (5c61b810, made from 0.7.1's 34ec1023: merge-rules.py MADE_FROM), by its first line.
M3=$(python3 "$REAL/scripts/merge-rules.py" <(MS) --units | awk -F'\t' '$1 == "5c61b810" { print $2 }')

# Issue 228: Claude Code passes a hook print over 10,240 bytes as a 2 KB preview, and a project's long rule file
# crossed that live. The print stays under it: a part that does not fit is one pointer line naming its file.
P2=$T/proj-long; project "$P2" '{}'
{ echo 'Our persona.'; echo; echo '## Ours'; for i in $(seq 1 250); do echo "- house rule $i: keep this line about eighty characters long, words."; done; } > "$P2/.claude/main-session.md"
LONG=$(ctx "$P2")
check "a 20 KB rule file: the print stays under 10,240 bytes, and the file is one pointer line" "yes 1 0" \
  "$([ "$(printf '%s\n' "$LONG" | LC_ALL=C wc -c)" -lt 10240 ] && echo yes) $(grep -c "^\[left out to fit the 10,240-byte startup print: Read $P2/.claude/main-session.md" <<<"$LONG") $(grep -c 'house rule 1:' <<<"$LONG")"

# Issue 328: a reply the duplicate-agent guard blocks is retried, never dropped. The rule sits above the Details heading,
# the part sessions load (MS): under Details no session loads it.
check "main-session's loaded part carries the rule that a reply the duplicate-agent guard blocks is never dropped" 1 \
  "$(MS | tr '\n' ' ' | grep -c 'A reply the duplicate-agent guard blocks is never dropped.*retry it after that seat.s turn ends, or send it as  *an orchestration reply')"

# --- the plugin by its stable link; the owner's own files ---
P=$T/proj; project "$P" '{ownFiles: {".claude/main-session.md": "replace"}, rules: "merge"}'
mkdir -p "$HOME/.commandeck" && ln -s "$REAL" "$HOME/.commandeck/plugin"
printf '# Our startup\n\n- Run make before you push.\n' > "$P/AGENT_STARTUP.md"
printf 'Our persona.\n\n## Ours\n\n- Main merges.\n' > "$P/.claude/main-session.md"
printf '# House\n\n%s\n' "$M1" > "$P/.claude/rules/house.md"
ctx "$P" > "$T/ctx"
check "a session's startup context names the plugin by its stable link" 1 "$(grep -c "^# Commandeck plugin folder: $HOME/.commandeck/plugin\. " "$T/ctx")"
check "sessions load the owner's startup file, and the plugin's main-session the owner chose" '1:0:1' \
  "$(grep -c '^# AGENT_STARTUP.md (auto-loaded' "$T/ctx"):$(grep -c '^# .claude/main-session.md (main only' "$T/ctx"):$(grep -c 'templates/main-session.md (main only' "$T/ctx")"
rm "$HOME/.commandeck/plugin"
check "with rules merge, a plugin rule the project already states is not loaded twice; another is, and skip loads both" '0:1:1' \
  "$(grep -cxF -- "$M1" "$T/ctx"):$(grep -cxF -- "$M2" "$T/ctx"):$(jq '.rules = "skip"' "$P/.claude/commandeck.json" > "$T/c" && cp "$T/c" "$P/.claude/commandeck.json" && ctx "$P" | grep -cxF -- "$M1")"
jq --arg i "$ID" '.mergeDecisions[$i] = "keep-mine"' "$P/.claude/commandeck.json" > "$T/c" && cp "$T/c" "$P/.claude/commandeck.json"
check "a rule the owner keeps their own wording for is not loaded" 0 "$(ctx "$P" | grep -cxF -- "$M2")"
jq --arg i "$ID" '.mergeDecisions[$i] = "keep-both"' "$P/.claude/commandeck.json" > "$T/c" && cp "$T/c" "$P/.claude/commandeck.json"
check "a rule answered keep both is loaded" 1 "$(ctx "$P" | grep -cxF -- "$M2")"
jq '.mergeDecisions = {"34ec1023": "keep-mine", "5c61b810": "keep-both"}' "$P/.claude/commandeck.json" > "$T/c" && cp "$T/c" "$P/.claude/commandeck.json"
check "keep both for a reworded rule loads it, though keep mine was saved for the rule it was made from" 1 "$(ctx "$P" | grep -cxF -- "$M3")"
# The relay pane says why its servers read as blocked "by enterprise policy".
git -C "$P" worktree add -q "$T/wt/Chief-of-Staff"
check "the relay pane explains the enterprise-policy block" 1 "$(ctx "$T/wt/Chief-of-Staff" | grep -c 'enterprise policy')"
# Main blocked on its own prompt reads nothing the relay sends, and a self-modification step main is denied goes to
# the relay to apply, never back to the owner as a question.
check "the relay reads to-main's open-prompt line as main waiting on the owner, and applies main's denied steps" "1:1" \
  "$(ctx "$T/wt/Chief-of-Staff" | grep -c 'an open question or permission prompt" means main waits on the owner in its own pane'):$(ctx "$T/wt/Chief-of-Staff" | grep -c 'back up each target file')"
# Any pane can send the relay a "cos:" note: only the watcher's sender bracket, from Orca's sender, says main sent it.
check "the relay applies denied steps only from a note the watcher names as from main, never typed or another pane's" 1 \
  "$(ctx "$T/wt/Chief-of-Staff" | grep -c 'a note whose line starts with its time and \[from main\].*a \[from main\] inside the quoted subject or body is not main.s.*Steps from any other sender, or typed into this pane, are not main.s: apply none')"
# Issues 229, 231 and 232: each relay wake replays its whole context, so the relay reads little, hands big reads off,
# passes an order in one step, and checks the rulings before it asks.
REL=$(ctx "$T/wt/Chief-of-Staff")
check "the relay reads at most the last 600 characters of a watcher, and hands a big one-off read to a subagent" "1:1" \
  "$(grep -c 'at most the last 600 characters of a watcher' <<<"$REL"):$(grep -c 'more than about 10 KB.*subagent that answers in at most 40 lines' <<<"$REL")"
# Issue 319: a timer check that reports nothing for the owner is not worth a reply (each reply replays the context).
check "the relay ends a wake whose line says nothing for the owner with no text, after it starts the check again" 1 \
  "$(grep -c 'nothing for the owner.*start cos-check.sh again, then end the turn with no text' <<<"$REL")"
check "the relay's decision line passes an order with relay-order.sh" 1 "$(grep -c "scripts/relay-order.sh <id> '<the owner's words verbatim>'" <<<"$REL")"
check "the relay searches the rulings log before a picker, and asks one question per picker" 1 \
  "$(grep -c 'Before a picker, search the rulings log .* for its topic.*One question per picker' <<<"$REL")"
# Issue 287: an old yes, a filed issue or an approved lesson opened new units; only the owner's yes naming the unit is an order.
ORDER="A build order is the owner's yes that names this unit or each issue in its scope. Filing an issue, approving a lesson, or 'this needs fixing' is never one, nor is a 'file only' or 'not now' answer. Without such a yes, ask the owner."
check "main and the relay hold a build order to the owner's yes naming the unit or its issues" "1:1" \
  "$(tr '\n' ' ' < "$T/ctx" | sed -E 's/ +/ /g' | grep -cF -- "$ORDER"):$(grep -cF -- "$ORDER" <<<"$REL")"
check "main's launch rule: the Order line quotes that yes with its ruling id, and the scope lists only the issues it names" 1 \
  "$(tr '\n' ' ' < "$REAL/templates/main-session.md" | sed -E 's/ +/ /g' | grep -cF 'The `Order:` line quotes the owner'"'"'s yes, with its ruling id, and the batch'"'"'s scope lists only the issues it names.')"
# Issue 290: a picker opened to a quiet owner sat for hours, and a dead watcher went unseen until the owner asked.
check "the relay opens no picker when the owner has been quiet 30 minutes, and runs the timer check as a fifth job" "1:1:1" \
  "$(grep -c 'owner quiet for 30 minutes or more, open no picker; leave the question on the decision queue and ask when the owner next types' <<<"$REL"):$(grep -c 'scripts/cos-check.sh' <<<"$REL"):$(grep -c 'without all five running' <<<"$REL")"
check "main sends a denied self-modification step to the relay" 1 "$(grep -c 'Denied a self-modification step' "$T/ctx")"
# Every finding, P0 to P3, blocks the merge: main never merges a NO-GO build, it gets a fix round.
check "main never merges a NO-GO build: it gets a fix round" "1 0" \
  "$(grep -c 'NO-GO never merges: it gets a fix round' "$T/ctx") $(grep -c "owner's word, even under the P2-tail rule" "$T/ctx")"
# Issue 237: main offered merges the merge's own gate then refused. Issues 254 and 306 (R11): main-watch runs that gate
# on every DONE and merges what passes, so main offers a merge only for a unit it held or refused.
check "main offers a merge only for a unit the gate held or refused" 1 "$(grep -c 'offer a merge only for one it held or refused' "$T/ctx")"
# Issue 235: long end-of-turn reports cost the owner a read every turn.
check "main ends each turn with one status line" 1 "$(grep -c 'End each turn with one status line' "$T/ctx")"
# Issue 230: main met the same guards turn after turn; its rules open with what to do instead, each with its command.
check "main's rules open with the do-not list, five lines, each with a command" "1 5" \
  "$(grep -c 'Do not -> instead' "$T/ctx") $(awk '/Do not -> instead/ {p = 1; next} p && /^  - .* -> .*`/ {n++} p && !/^  - / {exit} END {print n + 0}' "$T/ctx")"

# --- a path-scoped rule loads only for its paths, and a Builder never loads agents.md: neither stands in ---
P3=$T/proj3; project "$P3" '{rules: "merge"}'
printf -- '---\npaths: ["docs/**"]\n---\n\n%s\n' "$S1" > "$P3/.claude/rules/docs.md"
printf '%s\n' "$S2" > "$P3/.claude/rules/agents.md"; commit "$P3" own
CTX=$(ctx "$P3")
check "main still loads a plugin rule that only a path-scoped rule states, and not one an always-on rule states" '1:0' \
  "$(grep -cxF -- "$S1" <<<"$CTX"):$(grep -cxF -- "$S2" <<<"$CTX")"
git -C "$P3" worktree add -q "$T/wt/b3"; ex "$T/wt/b3/.claude/settings.local.json" "$T/wt/b3/.claude/rules/agents.md"
check "a Builder, which never loads agents.md, still gets the plugin rule it states" 1 "$(ctx "$T/wt/b3" 1 | grep -cxF -- "$S2")"

# --- frontmatter is read as YAML, and only what is read for sure counts as always loaded ---
P4=$T/proj4; project "$P4" '{rules: "merge"}'; L4=$P4/.claude/settings.local.json
n=0
for fm in '"paths": ["docs/**"]' "'paths': [docs/**]" 'paths : [docs/**]' '{paths: [docs/**]}' $'? paths\n: [docs/**]' $'"trigger": always_off\n"paths": [docs/**]'; do
  n=$((n + 1)); printf -- '---\n%s\n---\n\n%s\n' "$fm" "$(cat "$REAL/templates/AGENT_STARTUP.md")" > "$P4/.claude/rules/docs.md"
  check "a rules file scoped by paths: spelling $n stands in for no plugin rule" 1 "$(ctx "$P4" | grep -cxF -- "$S1")"
done
printf '\357\273\277---\r\npaths: [docs/**]\r\n---\r\n\r\n%s\r\n' "$S1" > "$P4/.claude/rules/docs.md"
check "a rules file scoped by paths: behind a byte-order mark, with CRLF lines, stands in for no plugin rule" 1 "$(ctx "$P4" | grep -cxF -- "$S1")"
printf -- '---\n"description": a rule\n---\n\n%s\n' "$S1" > "$P4/.claude/rules/docs.md"
check "a rules file with no paths: in its frontmatter stands in for the plugin rule" 0 "$(ctx "$P4" | grep -cxF -- "$S1")"
printf -- '\n%s\n' "$S1" > "$P4/.claude/rules/docs.md"
check "and so does a rules file with no frontmatter" 0 "$(ctx "$P4" | grep -cxF -- "$S1")"
# Fail safe (main's ruling): any paths key, and any frontmatter this cannot read for sure, keeps the plugin rule.
n=0
for fm in $'"trigger": "always_on"\n"paths": [docs/**]' '  paths: [docs/**]' $'description: a rule\n  paths: [docs/**]' \
  $'paths:\n  - docs/**' '  description: a rule' 'this is not yaml' $'base: &b {paths: [docs/**]}\n<<: *b' \
  $'description: a rule\ndescription: again'; do
  n=$((n + 1)); printf -- '---\n%s\n---\n\n%s\n' "$fm" "$S1" > "$P4/.claude/rules/docs.md"
  check "a rules file whose frontmatter has paths: or is not read for sure ($n) stands in for no plugin rule" 1 "$(ctx "$P4" | grep -cxF -- "$S1")"
done
printf -- '---\npaths: [docs/**]\n\n%s\n' "$S1" > "$P4/.claude/rules/docs.md"
check "a rules file whose frontmatter never closes stands in for no plugin rule" 1 "$(ctx "$P4" | grep -cxF -- "$S1")"
rm "$P4/.claude/rules/docs.md"; printf '# House\n\n%s\n\n%s\n' "$S1" "$M1" > "$P4/.claude/rules/house.md"
# An exclude is a glob as Claude Code reads it: ** spans no folder too, so it takes a direct child.
n=0
for x in "$P4/.claude/rules/**/*.md" "$P4/**" "$P4/**/house.md" "$P4/.claude/rules/{house,other}.md" "$P4/.claude/rules/hous?.md" "$P4/.claude/rules/[h]ouse.md"; do
  n=$((n + 1)); ex "$L4" "$x"
  check "a rules file excluded by glob $n stands in for no plugin rule" 1 "$(ctx "$P4" | grep -cxF -- "$S1")"
done
rm "$L4"

# --- the merged blocks are committed, and a seat may exclude what main loads: each seat decides when it starts ---
printf '# Ours\n\n- Run make before you push.\n<!-- commandeck:merge:begin -->\n%s\n<!-- commandeck:merge:end -->\n' "$S1" > "$P4/AGENT_STARTUP.md"
printf 'Our persona.\n\n<!-- commandeck:merge:begin -->\n%s\n<!-- commandeck:merge:end -->\n\n## Details (not injected)\n\nLong notes.\n' "$M1" > "$P4/.claude/main-session.md"
commit "$P4" merged
check "main, which loads the house rules, gets neither plugin rule they state twice" '0:0' "$(ctx "$P4" | grep -cxF -- "$S1"):$(ctx "$P4" | grep -cxF -- "$M1")"
git -C "$P4" worktree add -q "$T/wt/b4"; ex "$T/wt/b4/.claude/settings.local.json" "$T/wt/b4/.claude/rules/house.md"
check "a Builder whose own settings exclude the house rules gets the merged startup rule they state" 1 "$(ctx "$T/wt/b4" 1 | grep -cxF -- "$S1")"
ex "$L4" "$P4/.claude/rules/house.md"
check "main, once its settings exclude them, gets the merged main-session rule they state" 1 "$(ctx "$P4" | grep -cxF -- "$M1")"

# The injected bullets of the plugin's main-session.md point at its Details; an owner's file has none of those rules,
# so main is told where they are: the plugin's own template.
check "main with its own main-session.md is pointed at the plugin template's Details for the moved rules" 1 \
  "$(ctx "$P4" | grep -c "^\[Details.*$REAL/templates/main-session.md")"

# Issue 226: the limit panel reads the login of main's newest session, so main records its Claude config folder.
P5=$T/p5; project "$P5" '{}'
(cd "$P5" && CLAUDE_CONFIG_DIR=$T/cfg-b ctx "$P5" >/dev/null)
check "main records its Claude config folder for the limit panel" "$T/cfg-b" \
  "$(cat "$HOME/.commandeck/scratch/${P5//[^A-Za-z0-9]/-}/claude-config-dir" 2>/dev/null)"

# The drain takes a queued message off once printed: printed into the held startup print, a hook killed before its
# exit (here while a stalled check of an old handle runs) lost it. Printed straight out, the killed hook still showed it.
P6=$T/p6; project "$P6" '{}'; S6=$HOME/.commandeck/scratch/${P6//[^A-Za-z0-9]/-}
mkdir -p "$S6/queue" "$S6/handles" "$T/bin6"; echo term_old > "$S6/handles/main"
jq -nc '{type: "note", subject: "kept", body: "the queued body", at: "now"}' > "$S6/queue/main.jsonl"
printf '#!/bin/sh\nsleep 20\n' > "$T/bin6/orca-ide"; chmod +x "$T/bin6/orca-ide"
K6=$(cd "$P6" && PATH=$T/bin6:$PATH ORCA_TERMINAL_HANDLE=term_new env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN -u COMMANDECK_SCRATCH \
  timeout -s KILL 3 bash "$REAL/hooks/agent-startup-context.sh" </dev/null 2>/dev/null)
check "a hook killed after the drain took a queued message has printed it" "1:gone" \
  "$(grep -c 'the queued body' <<<"$K6"):$([ -e "$S6/queue/main.jsonl" ] || [ -e "$S6/queue/main.jsonl.taking" ] || echo gone)"

# F18: main's start keeps MEMORY.md (the index Claude Code loads) to the active memories; a memory marked
# `status: archived` moves to MEMORY-archive.md. A worker's start leaves the index alone.
mem_dir() { printf '%s/projects/%s/memory' "$1" "$(printf '%s' "$2" | sed 's/[^A-Za-z0-9]/-/g')"; }
PM=$T/proj-mem; project "$PM" '{}'
MD=$(mem_dir "$HOME/.claude" "$PM"); mkdir -p "$MD"
printf -- '---\nname: live\n---\nlive\n' > "$MD/live.md"; printf -- '---\nname: old\nstatus: archived\n---\nold\n' > "$MD/old.md"
printf -- '# Memory\n- [Live](live.md): active\n- [Old](old.md): archived one\n' > "$MD/MEMORY.md"
git -C "$PM" worktree add -q "$T/wt/mem" && ctx "$T/wt/mem" >/dev/null
check "a worker's session start does not touch MEMORY.md" 2 "$(grep -c '(live.md)\|(old.md)' "$MD/MEMORY.md")"
ctx "$PM" >/dev/null; A=$(cat "$MD/MEMORY.md" "$MD/MEMORY-archive.md"); ctx "$PM" >/dev/null
check "main's session start leaves MEMORY.md linking the active file and the archive line only, the archive linking the archived one" "1:0:1:1" \
  "$(grep -c '(live.md)' "$MD/MEMORY.md"):$(grep -c '(old.md)' "$MD/MEMORY.md"):$(grep -c '(MEMORY-archive.md)' "$MD/MEMORY.md"):$(grep -c '(old.md)' "$MD/MEMORY-archive.md")"
check "and a second start changes neither file" "$A" "$(cat "$MD/MEMORY.md" "$MD/MEMORY-archive.md")"
printf -- '---\nname: old\n---\nold\n' > "$MD/old.md"; ctx "$PM" >/dev/null
check "a memory made active again goes back into MEMORY.md, and the archive line goes with the last one" "1:0" \
  "$(grep -c '(old.md)' "$MD/MEMORY.md"):$(grep -c 'MEMORY-archive' "$MD/MEMORY.md")$([ -e "$MD/MEMORY-archive.md" ] && echo x)"
# Under an Orca profile the memory folder is the profile's, not the home one.
PROF=$T/profile; MP=$(mem_dir "$PROF" "$PM"); mkdir -p "$MP"; cp "$MD/live.md" "$MP/"; printf -- '---\nstatus: archived\n---\n' > "$MP/old.md"
printf -- '- [Live](live.md): a\n- [Old](old.md): b\n' > "$MP/MEMORY.md"; printf -- '---\nstatus: archived\n---\n' > "$MD/old.md"; printf -- '- [Old](old.md): b\n' > "$MD/MEMORY.md"
(cd "$PM" && env -u CLAUDE_PROJECT_DIR -u COMMANDECK_MAIN CLAUDE_CONFIG_DIR="$PROF" bash "$REAL/hooks/agent-startup-context.sh" </dev/null >/dev/null 2>&1)
check "under CLAUDE_CONFIG_DIR the index in that profile's projects folder is the one rewritten" "0:1" \
  "$(grep -c '(old.md)' "$MP/MEMORY.md"):$(grep -c '(old.md)' "$MD/MEMORY.md")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
