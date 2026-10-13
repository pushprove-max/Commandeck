#!/usr/bin/env bash
# Only top-level metadata reaches the fire log: a key inside tool_input
# or tool_response never answers for session_id, hook_event_name or tool_name,
# whatever the JSON key order.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export COMMANDECK_HOOK_FIRE_LOG="$T/fires.jsonl"
fire() {
  (
    . "$ROOT/hooks/lib/hook-fire-log.sh"
    hook_fire_log_arm "$1"
  )
}
fire '{"hook_event_name":"PostToolUse","tool_name":"Bash","session_id":null,"tool_response":{"session_id":"PRIVATE-RESPONSE-TOKEN"}}'
jq -e '.session_id == ""' "$COMMANDECK_HOOK_FIRE_LOG"

# tool_response BEFORE a top-level null session: the nested value is UUID-shaped,
# so only the cut at tool_response keeps it out, not the shape check.
NESTED=0f0e0d0c-0b0a-4908-8706-050403020100
fire "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_response\":{\"session_id\":\"$NESTED\",\"tool_name\":\"Evil\"},\"session_id\":null}"
tail -1 "$COMMANDECK_HOOK_FIRE_LOG" |
  jq -e '.event == "PostToolUse" and .tool == "Bash" and .session_id == ""'

# Content first, metadata past it and past the 4 KiB head. Main ruling
# (round 1): such metadata is accepted as lost and the head is not widened, so
# the row still lands with empty fields -- never with content's values, which
# here sit inside the head, so only the cut at tool_input keeps them out.
printf -v padding '%5000s' ''
fire "{\"tool_input\":{\"session_id\":\"$NESTED\",\"tool_name\":\"Evil\",\"hook_event_name\":\"Evil\",\"content\":\"$padding\"},\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"session_id\":\"11111111-2222-4333-8444-555555555555\"}"
[ "$(wc -l < "$COMMANDECK_HOOK_FIRE_LOG")" -eq 3 ]
tail -1 "$COMMANDECK_HOOK_FIRE_LOG" |
  jq -e '.event == "" and .tool == "" and .session_id == "" and .decision == "allow"'
! grep -q -e "$NESTED" -e Evil -e PRIVATE "$COMMANDECK_HOOK_FIRE_LOG" || exit 1

# A BLOCK row also names the worktree and the first words of the blocked call
#, so a noisy guard can be judged without the transcript. Never a
# secret: a --body, a token, key or password, or a long opaque run ends it.
fire_block() {
  (
    . "$ROOT/hooks/lib/hook-fire-log.sh"
    hook_fire_log_arm "$1"
    exit 2
  ) || true
}
block_row() { # command -> the block row's "worktree|summary"
  fire_block "$(jq -cn --arg c "$1" '{session_id:"11111111-2222-4333-8444-555555555555",cwd:"/w/tooling-batch-x",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')"
  tail -1 "$COMMANDECK_HOOK_FIRE_LOG" | jq -r '"\(.worktree)|\(.summary)"'
}
# The summary is the PROGRAM NAMES only, one per segment, and only names of
# commands installed here (main ruling 2026-10-10): no flag, argument,
# assignment, quoted string, URL, comment or heredoc body, and any word that is
# not an installed command is `?`, so no credential can reach it, however it is
# spelled. Stubs make the installed set the same on every machine.
mkdir "$T/bin"
for p in npm curl gh sshpass orca a; do printf '#!/bin/sh\n' > "$T/bin/$p"; chmod +x "$T/bin/$p"; done
PATH="$T/bin:$PATH"
[ "$(block_row 'npm test -- --grep "a b"')" = 'tooling-batch-x|npm' ]
# A builtin is a command; a function, or a word nothing on PATH answers, is not.
[ "$(block_row 'cd x && hook_fire_log_arm y; nosuchtool42 z | echo')" = 'tooling-batch-x|cd && ? ; ? | echo' ]
[ "$(block_row 'curl -ubob:pw --proxy-user x https://h | gh auth login --with-token')" = 'tooling-batch-x|curl | gh' ]
[ "$(block_row 'SSHPASS=pw sshpass -e ssh host && /usr/bin/env')" = 'tooling-batch-x|sshpass && env' ]
[ "$(block_row 'orca orchestration send --body "PRIVATE-BODY"')" = 'tooling-batch-x|orca' ]
# No dashed word of any kind survives: short, long, attached, after `--`, or in
# a program's place.
s=$(block_row 'npm -a --bee -c=1 -ubob -- --dee x | --eff y; -g')
[ "$s" = 'tooling-batch-x|npm | ? ; ?' ] && [[ ${s#*|} != *-* ]]
LONG=$(printf 'abc | %.0s' {1..40})
[ "$(block_row "$LONG" | wc -c)" -le 97 ]
for secret in 'GITHUB_TOKEN=PRIVATEx1 gh pr list' 'curl -H "Authorization: Bearer PRIVATEx2"' \
  'aws configure set aws_secret_access_key PRIVATEx3' 'mysql --password=PRIVATEx4' 'echo AKIA0PRIVATE0X5ABCDEFGHIJ' \
  'curl -u bob:PRIVATEx6 https://example.com' 'git clone https://bob:PRIVATEx7@example.com/r' 'mysql -pPRIVATEx8 db' \
  'curl --user bob:PRIVATEx9 h' 'curl -su bob:PRIVATEy1 h' 'redis-cli --pass PRIVATEy2' 'tool --password PRIVATEy3' \
  'sshpass -p PRIVATEy4 ssh h' 'DB_PASS=PRIVATEy5 run' 'MY_API_KEY=PRIVATEy6 run' 'CLIENT_SECRET=PRIVATEy7 run' \
  'GH_TOKEN=PRIVATEy8 gh' 'redis-cli -a PRIVATEy9 ping' \
  'cat /srv/u/PRIVATEz1-notes.txt' $'gh auth login --with-token <<EOF\nPRIVATEz2\nEOF' 'echo ok # PRIVATEz3' \
  $'cat <<A <<B\nx\nA\nPRIVATEz4\nB' 'X=$(echo PRIVATEz5) run' $'echo "a\nPRIVATEz6" | x' \
  'printf %s PRIVATEz7 | redis-cli -x AUTH' $'cat <<EOF\nunclosed\nPRIVATEz8' \
  'curl --user bob:short\&PRIVATEw1 https://e; npm test' 'redis-cli --pass --PRIVATEw2 ping' \
  $'gh auth login --with-token <<123\nPRIVATEw3\n123\nnpm test' $'cat <<\'a b\'\nPRIVATEw4\na b'; do
  if block_row "$secret" | grep -q PRIVATE; then echo "secret reached the log: $secret"; exit 1; fi
done
# Allow and advise rows stay metadata-only.
fire "$(jq -cn '{cwd:"/w/tooling-batch-x",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"ls"}}')"
tail -1 "$COMMANDECK_HOOK_FIRE_LOG" | jq -e 'has("worktree") or has("summary") | not' >/dev/null
# Every block row stays one valid JSON line: quotes, backslashes and control
# characters in the call never reach it.
[ "$(block_row $'a"b\\c\nd\te')" = 'tooling-batch-x|a' ]
jq -e . "$COMMANDECK_HOOK_FIRE_LOG" >/dev/null
if grep -q PRIVATE "$COMMANDECK_HOOK_FIRE_LOG"; then echo "a secret reached the log"; exit 1; fi
echo "hook-fire-log-metadata: pass"
