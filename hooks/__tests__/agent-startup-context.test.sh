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
export HOME=$T/home; mkdir -p "$HOME"
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
# A rule 0.7.2 reworded (8aa8b56d, made from 0.7.1's c99218c7: merge-rules.py MADE_FROM), by its first line.
M3=$(python3 "$REAL/scripts/merge-rules.py" <(MS) --units | awk -F'\t' '$1 == "8aa8b56d" { print $2 }')

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
jq '.mergeDecisions = {c99218c7: "keep-mine", "8aa8b56d": "keep-both"}' "$P/.claude/commandeck.json" > "$T/c" && cp "$T/c" "$P/.claude/commandeck.json"
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
check "main sends a denied self-modification step to the relay" 1 "$(grep -c 'Denied a self-modification step' "$T/ctx")"

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

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
