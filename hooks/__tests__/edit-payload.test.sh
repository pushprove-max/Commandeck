#!/usr/bin/env bash
# Self-test for lib/edit-payload.sh, the ONE extractor every content-screening
# hook reads its text through. The class defect it exists to end: a MultiEdit
# puts its text in edits[].new_string and carries NEITHER tool_input.content NOR
# tool_input.new_string, so a hook reading only those two saw an empty string
# and passed the batch unscreened.
set -u

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib/edit-payload.sh"
# shellcheck source=../lib/edit-payload.sh
source "$LIB"
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected '$2', got '$3')"; fi }

write()  { jq -cn --arg s "$1" '{tool_name:"Write", tool_input:{file_path:"a.ts", content:$s}}'; }
edit()   { jq -cn --arg o "$1" --arg n "$2" '{tool_name:"Edit", tool_input:{file_path:"a.ts", old_string:$o, new_string:$n}}'; }
multi()  { jq -cn --arg n1 "$1" --arg n2 "$2" '{tool_name:"MultiEdit", tool_input:{file_path:"a.ts", edits:[{old_string:"o1", new_string:$n1},{old_string:"o2", new_string:$n2}]}}'; }
bash_c() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }

# --- new text: all three tool shapes ------------------------------------------
check "Write new text is .content"                 "hello"      "$(hook_new_text "$(write hello)")"
check "Edit new text is .new_string"               "after"      "$(hook_new_text "$(edit before after)")"
check "MultiEdit new text folds EVERY edit"        $'one\ntwo'  "$(hook_new_text "$(multi one two)")"

# THE DECISIVE CASE. Offending text in a LATER edit, with no .content and no
# .new_string anywhere on tool_input -- the exact payload that walked past
# eleven hooks. `grep -c` proves the second edit is not merely present but read.
check "text in a non-first edit is returned"       1 \
  "$(hook_new_text "$(multi 'const ok = 1;' 'DANGEROUS_MARKER')" | grep -c 'DANGEROUS_MARKER')"

# --- old text -----------------------------------------------------------------
check "Edit old text is .old_string"               "before"     "$(hook_old_text "$(edit before after)")"
check "MultiEdit old text folds EVERY edit"        $'o1\no2'    "$(hook_old_text "$(multi one two)")"
check "a Write removes nothing, so old text is empty" ""        "$(hook_old_text "$(write hello)")"

# --- pairs: the exemption belongs to the FILE, not to the payload -------------
PAIRS=$(hook_edit_pairs "$(jq -cn '{tool_name:"MultiEdit", tool_input:{edits:[
  {file_path:"src/a.test.ts", old_string:"x", new_string:"benign"},
  {file_path:"src/api.ts",    old_string:"y", new_string:"offending"}]}}')")
check "one pair record per edit"                   2            "$(printf '%s\n' "$PAIRS" | wc -l)"
check "each pair keeps its OWN path"               "src/api.ts" \
  "$(printf '%s\n' "$PAIRS" | tail -1 | cut -f1 | base64 -d)"
check "each pair keeps its OWN text"               "offending" \
  "$(printf '%s\n' "$PAIRS" | tail -1 | cut -f2 | base64 -d)"
# A newline or tab in the text must not split a record -- that is why both
# fields are base64 rather than raw.
NL_PAIRS=$(hook_edit_pairs "$(write $'line1\tcol2\nline3')")
check "a newline in the text does not split a record" 1 "$(printf '%s\n' "$NL_PAIRS" | wc -l)"
check "the text survives the round trip" $'line1\tcol2\nline3' \
  "$(printf '%s\n' "$NL_PAIRS" | cut -f2 | base64 -d)"

# --- a payload with no edit text yields nothing, and never errors -------------
# --- triples: both sides of each edit, in one call ----------------------------
# The question the pooled text cannot answer: did THIS edit add an occurrence.
# For a MultiEdit the pooled old side spans the whole batch, so one retained
# occurrence anywhere in it excused every edit in it.
d64() { printf '%s' "$1" | base64 -d; }
TRI=$(hook_edit_triples "$(multi one two)")
check "one record per edit"                        2 "$(printf '%s\n' "$TRI" | grep -c .)"
check "each record carries its own new side"       "two" \
  "$(d64 "$(printf '%s\n' "$TRI" | sed -n 2p | cut -f2)")"
check "each record carries its own old side"       "o2" \
  "$(d64 "$(printf '%s\n' "$TRI" | sed -n 2p | cut -f3)")"
check "an Edit is one record with both sides"      "before|after" \
  "$(T=$(hook_edit_triples "$(edit before after)"); printf '%s|%s' "$(d64 "$(printf '%s' "$T" | cut -f3)")" "$(d64 "$(printf '%s' "$T" | cut -f2)")")"
check "a Write removes nothing, so its old side is empty" "" \
  "$(d64 "$(hook_edit_triples "$(write hello)" | cut -f3)")"
check "a pure deletion is still a record"          1 \
  "$(hook_edit_triples "$(edit gone '')" | grep -c .)"
check "a Bash payload has no triples"              "" "$(hook_edit_triples "$(bash_c 'rm -rf /tmp/x')")"
check "malformed JSON yields no triples"           "" "$(hook_edit_triples 'not json at all')"

# A hook must stay a tripwire, not a wedge: a Bash call, an empty tool_input or
# malformed JSON has to come back empty and succeed.
check "a Bash payload has no new text"             ""  "$(hook_new_text "$(bash_c 'rm -rf /tmp/x')")"
check "a Bash payload has no old text"             ""  "$(hook_old_text "$(bash_c 'rm -rf /tmp/x')")"
check "a Bash payload has no pairs"                ""  "$(hook_edit_pairs "$(bash_c 'rm -rf /tmp/x')")"
check "an empty tool_input yields nothing"         ""  "$(hook_new_text '{"tool_name":"Edit","tool_input":{}}')"
check "malformed JSON yields nothing"              ""  "$(hook_new_text 'not json at all')"
check "malformed JSON still SUCCEEDS"              0   "$(hook_new_text 'not json at all' >/dev/null 2>&1; echo $?)"

# --- the size shape ----------------------------------------------------
# file-size-cop.sh kept a private jq for this. The pairs and the triples cannot
# answer it: a Write states the whole file, while an insertion whose old text is
# empty looks identical in both, and the two have different baselines.
size() { hook_edit_size "$1" | while IFS=$'\t' read -r p k n; do
  printf '%s %s %s\n' "$(printf '%s' "$p" | base64 -d)" "$k" "$n"; done; }
check "a Write states the whole file's length"     'a.ts write 2' "$(size "$(write $'one\ntwo')")"
check "an Edit states the NET lines it adds"       'a.ts edit 1'  "$(size "$(edit 'o1' $'n1\nn2')")"
check "a MultiEdit sums every edit's delta"        'a.ts edit 2'  "$(size "$(multi $'a\nb' $'c\nd')")"
# A swap applied an unknown number of times has no line arithmetic. Silence is
# the answer; a guessed number would be believed.
check "a replace_all edit yields nothing"          "" \
  "$(hook_edit_size "$(jq -cn '{tool_name:"Edit",tool_input:{file_path:"a.ts",old_string:"o",new_string:"n",replace_all:true}}')")"
check "a replace_all inside a MultiEdit yields nothing" "" \
  "$(hook_edit_size "$(jq -cn '{tool_name:"MultiEdit",tool_input:{file_path:"a.ts",edits:[{old_string:"o",new_string:"n"},{old_string:"p",new_string:"q",replace_all:true}]}}')")"
# One record per PATH. Summing a two-file batch against the payload-level path
# would judge one file on another file's growth.
check "a two-path MultiEdit yields one record each" $'a.ts edit 1\nb.ts edit 2' \
  "$(size "$(jq -cn '{tool_name:"MultiEdit",tool_input:{file_path:"a.ts",edits:[
       {file_path:"a.ts",old_string:"o",new_string:"n1\nn2"},
       {file_path:"b.ts",old_string:"o",new_string:"n1\nn2\nn3"}]}}')")"
check "a Bash payload has no size shape"           ""  "$(hook_edit_size "$(bash_c 'rm -rf /tmp/x')")"
check "malformed JSON has no size shape"           ""  "$(hook_edit_size 'not json at all')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
