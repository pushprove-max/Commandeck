#!/usr/bin/env bash
# context_size <transcript.jsonl> -- print the session's current context in
# tokens, or return 1 when the transcript carries no usage row.
#
# One home for the number three hooks gate on: context-line.sh (the nag),
# context-clear-stop.sh (the checkpoint block) and pane-budget-gate.sh (the
# worker ceiling). They each had their own copy of the sum and each inherited
# the same lie.
#
# A usage row is the whole prompt for THAT request, and some requests carry a
# payload that never enters the conversation. On 2026-09-13 main's transcript
# climbed 160K, 163K, 164K, then one row read 336K, then the next read 171K,
# and the Stop hook demanded a checkpoint for a session that was really at
# 170K. Real context grows a few thousand tokens per turn and never doubles,
# so a value far above the previous DISTINCT one is that transient payload.
#
# The last turn's output counts too (issue 267): auto-compact counts it, and
# a sum without it ran below the point compaction acts on.
#
# Dedupe consecutive rows of one input count first, keeping the last one's
# output: one request is recorded several times while it streams, its output
# growing, so the last five rows can all be copies of one outlier.
context_size() {
  local transcript=$1 sums
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1
  # Parse each line on its own: the tail can start mid-line, and plain `jq -r`
  # stops at that cut line and prints nothing for the whole rest.
  sums=$(tail -c 3000000 "$transcript" \
    | grep '"cache_read_input_tokens"' \
    | jq -rR 'fromjson? | .message.usage
             | "\((.cache_read_input_tokens // 0)
                + (.input_tokens // 0)
                + (.cache_creation_input_tokens // 0)) \(.output_tokens // 0)"' 2>/dev/null \
    | awk 'NF { if (row != "" && $1 != prev) print row; prev = $1; row = $0 } END { if (row != "") print row }' \
    | tail -2)
  [ -n "$sums" ] || return 1
  # 1.4x is the reject line: it catches both observed spikes (1.58x and 2.05x)
  # and tolerates a turn that genuinely reads 40% of the context in one go.
  # A wrongly rejected jump costs ONE turn -- the next row becomes the new
  # baseline and the one after it is accepted. The input counts are compared;
  # the output is added after.
  printf '%s\n' "$sums" | awk '
    NR == 1 { prev = $1; pout = $2 }
    NR == 2 { last = $1; lout = $2 }
    END {
      if (NR < 2)                   { print prev + pout }
      else if (last > prev * 7 / 5) { print prev + pout }
      else                          { print last + lout }
    }'
}
