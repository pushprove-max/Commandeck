#!/usr/bin/env bash
# PreToolUse hook (WebFetch): advise agent-browser; do not refuse the fetch.
#
# WHY THE ADVICE: WebFetch is a plain HTTP GET summarised by a small model.
# Sites that gate on JavaScript or a real browser (Reddit, anything behind a
# login or a bot wall) return a block page or nothing, and the summary hides
# that. `agent-browser read <url>` drives a real browser and returns
# agent-readable text for the same cost.
#
# WHY NOT A REFUSAL: an ordinary HTML page fetches fine, and refusing it up
# front bought a forced browser launch on every one. The failure this exists
# for is visible only in the RESULT -- empty or a block page -- so the hook
# says what to do then and lets the cheap path run first.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "WebFetch" ] || exit 0
URL=$(echo "$INPUT" | jq -r '.tool_input.url // empty')
# The one fetch a browser cannot do: claude.ai artifacts ride the CLI login.
case "$URL" in
  https://claude.ai/code/artifact/*) exit 0 ;;
esac
HOOK_FIRE_ADVISE=1
cat >&2 <<EOF
ADVISORY: if this fetch comes back empty, truncated, or as a consent/bot wall,
the page is JS-gated -- re-read it with a real browser rather than retrying:

  agent-browser read '$URL'          # agent-readable text
  agent-browser open '$URL' && agent-browser snapshot   # when read is empty

Load the usage guide once with: agent-browser skills get core
EOF
exit 0
