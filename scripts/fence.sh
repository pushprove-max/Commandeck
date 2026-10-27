# fence.sh -- sourced, never run. ONE FENCE RULE FOR EVERY READER OF MARKDOWN.
# A reviewer report's readers (surviving_severity in paths.sh, close-round.sh's stable ids, read-verdict.sh's verdict
# line) and a plan's (plan-check.sh, the Break lines of builder-codex-pass.sh) all put this ahead of their awk program,
# so no two of them can disagree about what is fixture text. Its own file so plan-check.sh, which runs outside any
# project, needs no paths.sh. A fence opens on a line of three or more backticks or tildes, indented or not, and closes
# only on a line of the same character, at least as long, with nothing after it -- so a longer outer fence holds
# shorter delimiter text without closing. fence(line) returns 1 when the line opens a fence, 2 when it closes one and 0
# otherwise; flen is non-zero while inside one.
PP_AWK_FENCE='
  function fence(line,   run, ch) {
    if (!match(line, /^[[:space:]]*(```+|~~~+)/)) return 0
    run = substr(line, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", run); ch = substr(run, 1, 1)
    if (!flen) { fch = ch; flen = length(run); return 1 }
    if (ch == fch && length(run) >= flen && substr(line, RSTART + RLENGTH) ~ /^[[:space:]]*$/) { flen = 0; return 2 }
    return 0
  }'
