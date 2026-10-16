#!/usr/bin/env bash
# SessionStart hook: load the startup file into the session's context, by seat.
#
# An instruction to read a file is only as good as the reading; printing it
# here makes it mechanical. The project's own AGENT_STARTUP.md and
# .claude/main-session.md win (unless setup's answer was the plugin's);
# without them the plugin's templates are used.
# Output over 10 KB reaches the model as a 2 KB preview, so every seat's whole
# output stays under 10240 bytes (startup-size.sh measures it).
#
# Never blocks: a session that starts without this context is worse off, but a
# session that cannot start at all is worse still.

[ -t 0 ] || IFS= read -r -d '' INPUT
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "${INPUT-}" SessionStart
PLUGIN=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
# The paths printed below ride into checkpoints and outlive this session, and the
# plugin's own folder is versioned: an update leaves them naming the old one. So
# they name setup's stable link to it whenever that link points here.
[ "$(readlink -f "$HOME/.commandeck/plugin" 2>/dev/null)" != "$(readlink -f "$PLUGIN")" ] || PLUGIN=$HOME/.commandeck/plugin
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$REPO_ROOT" ] && exit 0

# Setup writes the config in the main checkout only: a worktree reads it there.
CONFIG=$( . "${BASH_SOURCE[0]%/*}/lib/project.sh" 2>/dev/null && pp_project "$REPO_ROOT" && printf '%s' "$PP_PROJECT_DIR")/.claude/commandeck.json
[ -f "$CONFIG" ] || CONFIG="$REPO_ROOT/.claude/commandeck.json"
# own <file> -- the project's own copy of a startup file loads, unless the owner chose the plugin's at setup (ownFiles).
own() { [ -f "$REPO_ROOT/$1" ] && [ "$(jq -r --arg f "$1" '.ownFiles[$f] // empty' "$CONFIG" 2>/dev/null)" != replace ]; }
STARTUP="$REPO_ROOT/AGENT_STARTUP.md"
own AGENT_STARTUP.md || STARTUP="$PLUGIN/templates/AGENT_STARTUP.md"
MAIN_ONLY="$REPO_ROOT/.claude/main-session.md"
own .claude/main-session.md || MAIN_ONLY="$PLUGIN/templates/main-session.md"
# inject <file> -- stdin to stdout. A plugin template names the plugin's scripts
# by their repo path and the default clear line; a session runs in the project,
# so each path becomes the full one and the line the configured one. The path
# goes in as one shell word (the text names commands to run), with what sed
# would read in it escaped. In the project's own file only the plugin's rules
# setup merged in (its marked block, kept machine-free for git) are rewritten.
inject() {
  local q r=''; q=$(printf '%q' "$PLUGIN" | sed 's/[\\&#]/\\&/g')
  [ "${1#"$PLUGIN"/}" != "$1" ] || r='/^<!-- commandeck:merge:begin -->$/,/^<!-- commandeck:merge:end -->$/ '
  sed -E "${r}s#(^|[ \`(])(scripts|hooks|templates)/#\1$q/\2/#g; ${r}s/200K/$(( $(pp_clear_line 2>/dev/null || echo 200000) / 1000 ))K/g"
}

# rules_cut <file> -- stdin less the plugin's rules the owner already has (setup's "rules": "merge": exact
# matches in the project's CLAUDE.md and .claude/rules/) and those the owner keeps their own wording for
# (mergeDecisions: keep-mine drops a rule, keep-both keeps it, the rule's own answer over one saved for the
# rule it was made from), by merge-rules.py. For a plugin template, and for the rules setup merged into the owner's
# own file (its marked block, committed, so cut here for the seat that loads it); anything else, or a failed
# cut, as it came. Only a file this seat loads counts: merge-rules.py takes this seat's settings' excludes
# (claudeMdExcludes: a Builder's agents.md) and counts a path-scoped rules file for nothing.
rules_cut() {
  local t a=() d f tpl=
  t=$(cat)
  [ "${1#"$PLUGIN"/}" = "$1" ] || tpl=1
  [ -n "$tpl" ] || ! grep -qxF '<!-- commandeck:merge:begin -->' <<<"$t" || a=(--block)
  if [ ${#a[@]} -gt 0 ] || { [ -n "$tpl" ] && [ "$(jq -r '.rules // empty' "$CONFIG" 2>/dev/null)" = merge ]; }; then
    while IFS= read -r d; do [ -z "$d" ] || a+=(--exclude "$d"); done < <(for f in "$REPO_ROOT/.claude/settings.local.json" "$REPO_ROOT/.claude/settings.json" "$HOME/.claude/settings.json"; do jq -r '.claudeMdExcludes[]? | strings' "$f" 2>/dev/null; done)
    for f in "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT"/.claude/rules/*.md; do [ ! -f "$f" ] || a+=(--against "$f"); done
  fi
  [ -z "$tpl" ] && [ ${#a[@]} = 0 ] || while IFS= read -r d; do a+=("$d"); done < <(jq -r '.mergeDecisions // {} | to_entries[] | select(.value == "keep-mine" or .value == "keep-both") | (if .value == "keep-mine" then "--drop" else "--keep" end), .key' "$CONFIG" 2>/dev/null)
  [ ${#a[@]} -gt 0 ] && python3 "$PLUGIN/scripts/merge-rules.py" - "${a[@]}" <<<"$t" 2>/dev/null || printf '%s\n' "$t"
}

# Seat before any output. A linked worktree is a worker whether or not its
# rules file exists; main is a plain checkout that is not a reviewer pane.
GD=$(git rev-parse --git-dir 2>/dev/null)
GC=$(git rev-parse --git-common-dir 2>/dev/null)
TOP=$(git rev-parse --show-toplevel 2>/dev/null)
LINKED=0 MAIN=0 COS=0
[ -n "$GD" ] && [ "$GD" != "$GC" ] && LINKED=1
[ -n "$GD" ] && [ "$LINKED" = 0 ] && [ "${COMMANDECK_REVIEWER:-}" != 1 ] && MAIN=1
# Main's persona leads its context; the first line of main-session.md is its
# one home, and resume-context.sh reads the same line.
[ "$MAIN" = 1 ] && head -1 "$MAIN_ONLY"
# A relay chosen at set-up is a pane of its own, in the Chief-of-Staff worktree. A session in the main
# checkout was once taken for it and acted as the orchestrator, so main is told in one line which it is.
if [ "$MAIN" = 1 ] && RELAY=$(jq -re '.chiefOfStaff.name // empty' "$CONFIG" 2>/dev/null); then
  RELAY_WT=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep '/Chief-of-Staff$' | head -1)
  if [ -n "$RELAY_WT" ]; then echo "# This pane is the orchestrator, NOT the relay $RELAY: the relay is the pane in $RELAY_WT."
  else echo "# This pane is the orchestrator, NOT the relay $RELAY; no relay pane exists yet: bash $(printf '%q' "$PLUGIN")/scripts/setup.sh makes its Chief-of-Staff worktree and opens the pane."; fi
fi
# The Chief-of-Staff worktree is the owner's relay pane; it stays a worker seat otherwise.
[ "$LINKED" = 1 ] && [ "${TOP##*/}" = Chief-of-Staff ] && [ "${COMMANDECK_REVIEWER:-}" != 1 ] && COS=1
COS_STATE=$(. "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_cos_key && printf '%s' "$COS_KEY").md
if [ "$COS" = 1 ]; then
  PERSONA=$(jq -r '.chiefOfStaff.persona // empty' "$CONFIG" 2>/dev/null)
  RELAY=$(jq -r '.chiefOfStaff.name // empty' "$CONFIG" 2>/dev/null)
  echo "# Chief of Staff${RELAY:+, named $RELAY}: ${PERSONA:-plain speech, no personality.} Every turn, including resumed sessions, you relay between the owner and the main orchestrator and never answer for the owner; facts and plain English stay rigorous."
fi

# The plugin's files and messages name its own files as scripts/..., hooks/...
# and templates/...; a session runs in the project, where none of them is.
echo "# Commandeck plugin folder: $PLUGIN. A path that starts scripts/, hooks/ or templates/ in the plugin's files and messages is under it, not in this project."
# Main and a Builder restart under a new handle: what was sent while the seat was down comes first (to-main.sh queues it).
if [ "$MAIN" = 1 ]; then timeout 30 bash "$PLUGIN/scripts/inbox-drain.sh" main 2>/dev/null
elif [ "$LINKED" = 1 ] && [ "${COMMANDECK_BUILDER:-}" = 1 ]; then timeout 30 bash "$PLUGIN/scripts/inbox-drain.sh" --unit "${TOP##*/}" 2>/dev/null; fi

# Codex cuts hook output past ~10K bytes out of the middle, so a Codex seat
# reads the file itself, once, as its first step.
if [ "${AGENT_KIND:-claude}" = codex ]; then
  echo "# The startup file is not injected for Codex: read $STARTUP in full as your first step."
elif [ "$COS" = 1 ]; then
  # The relay never reads code, and the startup file is all build workflow: it
  # gets its saved state instead, whole lines up to a 5000-byte share.
  echo "# The startup file is not injected for the Chief-of-Staff pane: you relay and never read code."
  # Claude Code names the cause of this pane's blocked servers "enterprise policy", which reads as the owner's employer.
  echo "# If the owner asks why an MCP server or plugin here is blocked \"by enterprise policy\": Commandeck turned the code tools off in this worktree's .claude/settings.local.json (worktree-setup.sh), because the relay never reads code; that is the name Claude Code gives the setting. Add-ons are installed from the main checkout (/commandeck:setup there), never here."
  # It is deaf between turns unless a watcher is running: each one exits when
  # it has something, which wakes the pane.
  cat <<EOF
# Wake-ups: run each in the background (run_in_background) and start it again when it exits. A turn may not end without all four running.
- \`bash $(printf '%q' "$PLUGIN")/scripts/cos-watch-inbox.sh${ORCA_TERMINAL_HANDLE:+ $ORCA_TERMINAL_HANDLE}\`: main's messages for you or the owner.
- \`bash $(printf '%q' "$PLUGIN")/scripts/cos-watch-decisions.sh\`: open decisions. Ask the owner with the question picker, then run \`bash $(printf '%q' "$PLUGIN")/scripts/decision.sh answer <id> '<answer>'\` and append its printed \`seen\` value to ${COS_STATE%.md}.decisions-seen
- \`bash $(printf '%q' "$PLUGIN")/scripts/cos-watch-alerts.sh\` and \`bash $(printf '%q' "$PLUGIN")/scripts/cos-watch-limit.sh\`: dashboard alerts and the 7-day limit. Tell the owner, then append the alert id to ${COS_STATE%.md}.alerts-seen
# To main: \`bash $(printf '%q' "$PLUGIN")/scripts/to-main.sh question '<subject>' '<the owner's answer verbatim>'\`. It finds main's live pane itself; "message queued" means main is down and sees it first when it starts.
EOF
  if [ -f "$COS_STATE" ]; then
    echo
    echo "# $COS_STATE (your saved state; keep it current)"
    awk -v max=5000 -v f="$COS_STATE" '{ n += length($0) + 1; if (n > max) { print "[cut to fit " max " bytes; Read the rest from " f "]"; exit } print }' "$COS_STATE"
  fi
else
  echo "# ${STARTUP#"$REPO_ROOT"/} (auto-loaded by the commandeck plugin)"
  rules_cut "$STARTUP" < "$STARTUP" | inject "$STARTUP"
  # The project's own commands, as setup recorded them.
  jq -r '"\n## This project\n" + ([(.testCommand // empty | "- Test: `\(.)`"), (.buildCommand // empty | "- Build: `\(.)`")] | join("\n")) | select(test("`"))' "$CONFIG" 2>/dev/null
fi

# Worker rules only where they bind: a linked worktree. A Builder runs its own
# subagents and review passes and hands back a branch, so they do not fit it.
if [ "$LINKED" = 1 ] && [ "${COMMANDECK_BUILDER:-}" = 1 ]; then
  echo
  echo "# Builder pane (COMMANDECK_BUILDER=1): worker rules do not apply to you."
  echo "Build the batch in .claude/briefs/${TOP##*/}.md: your own Explore subagents, your review passes only through the pass script that brief names."
  echo "Never commit by hand or push; main merges your branch with merge-unit-local.sh."
elif [ "$LINKED" = 1 ]; then
  if [ -f "$REPO_ROOT/.claude/rules/worktree-sessions.md" ]; then
    echo
    echo "# .claude/rules/worktree-sessions.md (you are in a linked worktree; these bind you)"
    # Strip a leading frontmatter block; a file without one passes through whole.
    awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {fm=0; next} !fm' \
      "$REPO_ROOT/.claude/rules/worktree-sessions.md"
  fi
elif [ "$MAIN" = 1 ]; then
  echo
  echo "# ${MAIN_ONLY#"$REPO_ROOT"/} (main only; worker panes never load it)"
  # Line 1, the persona, already leads the output. The file's own Details
  # section stays on disk, under the 10 KB limit.
  tail -n +2 "$MAIN_ONLY" | awk '/^## Details \(not injected\)/ {exit} 1' | rules_cut "$MAIN_ONLY" | inject "$MAIN_ONLY"
  echo "[Details (not injected): Read $MAIN_ONLY from its '## Details (not injected)' heading when a bullet points there]"
  if [ -f "$REPO_ROOT/todo/main-todo.md" ]; then
    # Main's todo list survives a restart because it is a file. A pointer: its
    # full text does not fit the limit.
    echo
    echo "# todo/main-todo.md (main's persistent todo, $(wc -l < "$REPO_ROOT/todo/main-todo.md" | tr -d ' ') lines; Read it first and keep it current)"
  fi
fi

# MEASURE WHAT RIDES EVERY TURN. The always-on files are re-read from cache on
# every turn, not once per session. This cuts nothing; it is one line, so the
# measurement is not its own problem. Always-on means: both CLAUDE.md files,
# the startup file when it is injected, main's injected part, and every rule
# that is not path-gated (merge-rules.py reads the frontmatter; one it cannot read for sure counts as gated).
ALWAYS=("$REPO_ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md")
[ "${AGENT_KIND:-claude}" = codex ] || [ "$COS" = 1 ] || ALWAYS+=("$STARTUP")
[ "$MAIN" = 1 ] && ALWAYS+=("$MAIN_ONLY")
RULES=(); for RULE in "$REPO_ROOT"/.claude/rules/*.md; do [ ! -f "$RULE" ] || RULES+=(--against "$RULE"); done
[ ${#RULES[@]} = 0 ] || while IFS= read -r RULE; do ALWAYS+=("$RULE"); done < <(python3 "$PLUGIN/scripts/merge-rules.py" /dev/null "${RULES[@]}" --sources 2>/dev/null)
TOTAL=0 COUNT=0 BIGGEST="" BIGGEST_BYTES=0
for FILE in "${ALWAYS[@]}"; do
  [ -f "$FILE" ] || continue
  if [ "$MAIN" = 1 ] && [ "$FILE" = "$MAIN_ONLY" ]; then
    # Only the injected part rides every turn; its Details stay on disk.
    BYTES=$(awk '/^## Details \(not injected\)/ {exit} 1' "$FILE" | wc -c | tr -d ' ')
  else
    BYTES=$(wc -c < "$FILE" | tr -d ' ')
  fi
  TOTAL=$((TOTAL + BYTES)); COUNT=$((COUNT + 1))
  [ "$BYTES" -le "$BIGGEST_BYTES" ] || { BIGGEST_BYTES=$BYTES; BIGGEST=${FILE#"$REPO_ROOT"/}; }
done
echo
echo "# always-on context: $COUNT repo/user files, $TOTAL bytes (~$((TOTAL / 4)) tokens) re-read from cache on EVERY turn; largest $BIGGEST at $BIGGEST_BYTES bytes"
exit 0
