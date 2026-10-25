#!/usr/bin/env bash
# builder-codex-pass.sh and GitHub (issue 316): a review launched with no GitHub read is refused before any reviewer
# starts, with or without a Closes: line; the Codex reviewer, whose sandbox has no network, is handed the live issue,
# the issues it links and the pull request state, read on the host; the Claude reviewer gets gh read rules; a reviewer
# reply that says it lost GitHub is refused, not read as a verdict.
# The fixture is the one builder-codex-pass.test.sh uses.
set -uo pipefail
. "$(dirname "$0")/fixtures/builder-codex-pass-setup.sh"

printf 'echo built\n' > "$W/a.sh"
# A pass of the real script, from the Builder's worktree; prints its exit code. Env words after the kind are the pass's.
try() { local n=$1 k=$2; shift 2; sites "$n"
  (cd "$W" && env TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$n "$@" bash "$PASS_SH" "$U" "$n" "$k" >"$TMP/out" 2>"$TMP/err"); echo $?; }
CL='COMMANDECK_OPTIONS={"codexReviewerAgent": "claude"}'
# The reviewer stand-ins write a mark when they run: the Codex companion leaves a session record, the claude stub a log.
printf '#!/bin/sh\necho "$*" >> "%s/claude.log"\nexit 1\n' "$TMP" > "$TMP/cli/claude"; chmod +x "$TMP/cli/claude"
# issue <n> <body> [comment] [body HTML] [comment HTML...]: what gh holds for issue (or pull request) <n>; the HTML is
# GitHub's rendering of the body and of each comment (by default the text itself, with no link).
issue() { local n=$1 b=$2 c=${3:-} h=${4:-$2}; shift $(($# < 4 ? $# : 4)); [ $# -gt 0 ] || set -- ${c:+"$c"}
  jq -n --arg b "$b" --arg c "$c" '{title: "t", state: "OPEN", labels: [], body: $b, comments: [$c | select(. != "") | {body: .}]}' > "$TMP/gh/issue-$n.txt"
  jq -n --arg u "https://github.com/o/proj/issues/$n" --arg h "$h" '{html_url: $u, body_html: $h, comments: [$ARGS.positional[] | {body_html: .}]}' --args "$@" > "$TMP/gh/api-$n.json"; }
# A link GitHub resolved, as it renders one (measured 2026-10-23 with gh api markdown): its href is canonical.
ref() { printf '<a class="issue-link js-issue-link" data-url="https://github.com/%s" data-hovercard-type="issue" href="https://github.com/%s">#x</a> ' "$1" "$1"; }
sessions() { find "$CODEX_HOME/sessions" -name 'rollout-*' 2>/dev/null | wc -l | tr -d ' '; }

echo "error connecting to api.github.com" > "$TMP/gh-fail"
check "no GitHub read for the Codex reviewer: the pass is refused with the reason, and no reviewer ran" "2:1:0:no" \
  "$(try 1 adversarial):$(grep -c "REFUSED: the Codex reviewer's sandbox has no network, so its GitHub reads are made on the host, and the host cannot read GitHub: no network" "$TMP/err"):$(sessions):$([ -e "$B/$U-r1-reports.md" ] && echo yes || echo no)"
check "no GitHub read for the Claude reviewer: the pass is refused with the reason, and the reviewer never started" "2:1:no" \
  "$(try 1 adversarial "$CL" COMMANDECK_PASS=claude):$(grep -c 'REFUSED: the Claude reviewer cannot read GitHub: no network' "$TMP/err"):$([ -e "$TMP/claude.log" ] && echo yes || echo no)"
check "the preflight a launch runs first refuses the same way" "2:1" \
  "$( (cd "$REPO" && PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --preflight >/dev/null 2>"$TMP/err"); echo $?):$(grep -c 'host cannot read GitHub' "$TMP/err")"
rm -f "$TMP/gh-fail"

# The Codex reviewer is handed what its sandbox cannot read.
printf 'Closes: #7\n' >> "$B/$U.md"
issue 7 'ISSUE-7-BODY, see #8' 'COMMENT-7, see o/other#9' "ISSUE-7-BODY, see $(ref o/proj/issues/8)" "COMMENT-7, see $(ref o/other/issues/9)"
issue 8 LINKED-8-BODY
check "a linked issue (here in another repo) that cannot be read refuses the pass, naming it, before a reviewer runs" "2:1:0" \
  "$(try 1 adversarial):$(grep -c 'GitHub read failed on the host: gh issue view o/other#9 --json title,state,labels,body,comments' "$TMP/err"):$(sessions)"
issue 9 LINKED-9-BODY; : > "$TMP/gh.log"
# Nothing is dropped unsaid: a long body keeps its tail, and every link GitHub rendered is read (here 15, a six-digit
# one, a pull request's URL, URLs with an upper-case scheme or host or a path after the number, and a link in the second
# page of comments). What GitHub does not link is not read: a code span, an anchor, another site, a file's line, and
# the issue itself. No issue 30 to 33 exists, so a read of one would refuse the pass.
issue 7 "ISSUE-7-BODY, see #8, #100000 and https://github.com/o/proj/pull/42$(printf '\nsee #%s' $(seq 10 20)) https://GitHub.com/o/proj/issues/43 HTTPS://github.com/o/proj/issues/44 https://github.com/O/Proj/pull/45/files \`#30\` page#31 https://example.com/page#31 https://notgithub.com/o/proj/issues/32 https://github.com/o/proj/blob/main/a.sh#L33 #7$(printf '\n%030001d\nISSUE-7-TAIL' 0)" \
  'COMMENT-7, see o/other#9' \
  "ISSUE-7-BODY, see $(ref o/proj/issues/8)$(ref o/proj/issues/100000)$(ref o/proj/pull/42)$(for n in $(seq 10 20); do ref "o/proj/issues/$n"; done)<a href=\"https://GitHub.com/o/proj/issues/43\">u</a> <a href=\"HTTPS://github.com/o/proj/issues/44\">u</a> <a href=\"https://github.com/O/Proj/pull/45/files\">u</a> <code class=\"notranslate\">#30</code> page#31 <a href=\"https://example.com/page#31\">u</a> <a href=\"https://notgithub.com/o/proj/issues/32\">u</a> <a href=\"https://github.com/o/proj/blob/main/a.sh#L33\">u</a> $(ref o/proj/issues/7)ISSUE-7-TAIL" \
  "COMMENT-7, see $(ref o/other/issues/9)" "COMMENT-7-PAGE-2, see $(ref o/proj/issues/46)"
for n in $(seq 10 20) 42 43 44 45 46 100000; do issue "$n" "LINKED-$n-BODY"; done
check "with every read answered the pass runs" 0 "$(try 1 adversarial)"
P=$B/$U-r1-prompt-1.md
check "the prompt holds the Closes: issue's body and comments, the issue it links, one in another repo, and no pull request for the branch" "1:1:1:1:1" \
  "$(grep -c 'ISSUE-7-BODY' "$P"):$(grep -c 'COMMENT-7' "$P"):$(grep -c 'LINKED-8-BODY' "$P"):$(grep -c 'LINKED-9-BODY' "$P"):$(grep -c 'no pull request for branch builder/unit' "$P")"
check "past 30,000 bytes the issue is whole, and the 11th link on, a six-digit one and a pull request's URL are read too" "1:1:1:1" \
  "$(grep -c 'ISSUE-7-TAIL' "$P"):$(grep -c 'LINKED-20-BODY' "$P"):$(grep -c 'LINKED-100000-BODY' "$P"):$(grep -c 'LINKED-42-BODY' "$P")"
check "a URL with an upper-case scheme or host or a path after the number, and a link in a later page of comments, are read; the issue itself is read once" \
  "1:1:1:1:1" \
  "$(grep -c 'LINKED-43-BODY' "$P"):$(grep -c 'LINKED-44-BODY' "$P"):$(grep -c 'LINKED-45-BODY' "$P"):$(grep -c 'LINKED-46-BODY' "$P"):$(grep -c '^issue view 7 ' "$TMP/gh.log")"
check "the URL's pull request is read in its repo" 1 "$(grep -c '^issue view 42 -R o/proj --json title,state,labels,body,comments$' "$TMP/gh.log")"
check "the other repo's issue is read with -R" 1 "$(grep -c '^issue view 9 -R o/other --json title,state,labels,body,comments$' "$TMP/gh.log")"
check "the prompt tells the reviewer a read it needs that is missing is a BLOCKED line" 1 "$(grep -c 'BLOCKED: GitHub read failed: <command>: <first error line>' "$P")"

# A brief with no Closes: line still gets the check (above) and the pull request state.
printf 'echo two\n' > "$W/a.sh"; sed -i.bak '/^Closes:/d' "$B/$U.md"; rm -f "$B/$U.md.bak"
printf '{"state":"OPEN","labels":[],"statusCheckRollup":[]}\n' > "$TMP/gh/pr.txt"
# The host reads are made with the reviewer's routed shellEnv, as the preflight read was, not the caller's credentials.
cp "$COMMANDECK_ROUTING" "$TMP/routing.keep"
jq '.roles["codex-reviewer"].shellEnv = {GH_TOKEN: "seat-token"}' "$TMP/routing.keep" > "$COMMANDECK_ROUTING"
mv "$TMP/cli/gh" "$TMP/cli/gh-real"
printf '#!/bin/sh\n[ "${GH_TOKEN:-}" = seat-token ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }\nexec "%s" "$@"\n' "$TMP/cli/gh-real" > "$TMP/cli/gh"; chmod +x "$TMP/cli/gh"
check "the pull request state of the unit branch is handed in, read with the reviewer's own token" "0:1" "$(try 2 review GH_TOKEN=bad-token):$(grep -c '"state":"OPEN"' "$B/$U-r2-prompt-1.md")"
# A batch brief names its work items under "The issues", often with no Closes: line: the reviewer, told to read them,
# cannot from its sandbox, so they are handed in too (a pass once ended BLOCKED on gh issue view of one).
rm -f "$B/$U-r2-reports.md"; printf '\n## The issues\n\n1. #7: t\n' >> "$B/$U.md"
check "a brief with no Closes: line hands in the work items its The issues list names, whole" "0:1:1" \
  "$(try 2 review):$(grep -c 'ISSUE-7-BODY' "$B/$U-r2-prompt-1.md"):$(grep -c 'LINKED-8-BODY' "$B/$U-r2-prompt-1.md")"
mv "$TMP/cli/gh-real" "$TMP/cli/gh"; mv "$TMP/routing.keep" "$COMMANDECK_ROUTING"

# A reviewer that lost GitHub ends its reply on that line: the reply is not a verdict. No fence is parsed: only the last
# line refuses, and the line anywhere else (quoted, in a broken or nested fence, or bare) makes the reply a NO-GO review.
printf 'echo three\n' > "$W/a.sh"
L='BLOCKED: GitHub read failed: gh issue view 5: no network in the review sandbox'
check "a reviewer reply that ends on a BLOCKED: GitHub read failed line refuses the pass, quoting it" "2:1" \
  "$(try 3 review "STUB_REPLY=Read what I could."$'\n'"$L"):$(grep -c "$L" "$TMP/err")"
# Its round runs again with each piece of the refused pass's state gone in turn, its abandoned mark, then its
# session: the retry depends on none of them. Each run is a review whose verdict is NO-GO, never GO, never refused.
# The refused pass is thread thr-3-1 (the stub names a thread <STUB_THREAD>-<reviewer>).
F=$'~~~text\n```text\n'
n=0 got=
for reply in "Example:"$'\n```text\n'"$L"$'\n```\n'"VERDICT: GO" "$F$L"$'\n```\n~~~\n'"VERDICT: GO" "$F~~~\n$L"$'\n'"VERDICT: GO" \
             "$L"$'\n'"VERDICT: GO" $'```\n'"$L"$'\n'"VERDICT: GO" "- [P3] a.sh:1 -- see:"$'\n'"$F$L"$'\n```\n~~~\n'"VERDICT: NO-GO"; do
  n=$((n + 1)); rm -f "$B/$U-r3-reports.md"
  [ "$n" != 3 ] || rm -f "$CODEX_HOME/builder-pass-prompts/thr-3-1.abandoned"
  [ "$n" != 4 ] || find "$CODEX_HOME/sessions" -name '*-thr-3-1.jsonl' -exec rm -f {} +
  got+="$(try 3 review STUB_THREAD=thr-3r$n "STUB_REPLY=$reply"):$(grep -c '^VERDICT: NO-GO$' "$B/$U-r3-reports.md" 2>/dev/null) "
done
check "the line quoted, in a nested or broken fence, or bare above a GO is a NO-GO review in a rerun of that round" \
  "0:1 0:1 0:1 0:1 0:1 0:1 " "$got"

# The Claude reviewer runs --restricted, which reads no settings file: a token only the checkout's settings carry is
# not one it has, so the read is made without it.
printf 'echo four\n' > "$W/a.sh"; rm -f "$TMP/claude.log"
cp "$W/.claude/settings.local.json" "$TMP/settings.keep"
jq '.env.GH_TOKEN = "seat-token"' "$TMP/settings.keep" > "$W/.claude/settings.local.json"
mv "$TMP/cli/gh" "$TMP/cli/gh-real"
printf '#!/bin/sh\n[ "${GH_TOKEN:-}" = seat-token ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }\nexec "%s" "$@"\n' "$TMP/cli/gh-real" > "$TMP/cli/gh"; chmod +x "$TMP/cli/gh"
check "a token in the checkout's settings, which the restricted Claude reviewer never reads, does not pass its check" "2:1:no" \
  "$(try 4 review "$CL" COMMANDECK_PASS=claude GH_TOKEN=bad-token):$(grep -c 'REFUSED: the Claude reviewer cannot read GitHub: ' "$TMP/err"):$([ -e "$TMP/claude.log" ] && echo yes || echo no)"
mv "$TMP/cli/gh-real" "$TMP/cli/gh"; mv "$TMP/settings.keep" "$W/.claude/settings.local.json"

# The Claude reviewer reads issues, pull requests and checks itself, and nothing that writes.
rm -f "$TMP/claude.log"; try 4 review "$CL" COMMANDECK_PASS=claude >/dev/null
check "the Claude reviewer's tool list allows gh issue view, gh pr view and gh pr checks, and no gh api" "1:1:1:0" \
  "$(grep -c 'Bash(gh issue view:\*)' "$TMP/claude.log"):$(grep -c 'Bash(gh pr view:\*)' "$TMP/claude.log"):$(grep -c 'Bash(gh pr checks:\*)' "$TMP/claude.log"):$(grep -c 'gh api' "$TMP/claude.log")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
