#!/usr/bin/env bash
export COMMANDECK_HOOK_TIER=strict
# Self-test for file-size-cop.sh.
#
# The defect it pins (2026-08-31): the hook was registered on `Write` alone and
# read only tool_input.content, so it could only judge a file written whole --
# which is not how a file gets long. Files grow by Edit and MultiEdit, one hunk
# at a time, and every one of those passed unmeasured.
#
# It also pins the narrowing: only the caps the rules STATE are enforced --
# 500 for a .ts, 400 for a .tsx. The universal 800-line block for every file
# type came from no rule, and it refused a long markdown reference on a number
# nobody chose while letting a .tsx past its stated 400 with a warning.
#
# It also pins where the hook DECLINES to answer: a replace_all edit applies its
# swap an unknown number of times, so the resulting size is not computable from
# the payload and the hook stays silent rather than reporting a number it made
# up.
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/file-size-cop.sh"
SETTINGS="$(cd "$(dirname "$0")/.." && pwd)/hooks.json"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0

check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
run()     { bash "$HOOK" >/dev/null 2>&1 <<<"$1"; echo $?; }
run_err() { bash "$HOOK" 2>&1 >/dev/null <<<"$1"; }

lines() { seq 1 "$1" | sed 's/^/const x/;s/$/ = 1;/'; }

BIG="$TMP/big.ts"; lines 490 > "$BIG"          # near the stated 500-line .ts cap
SMALL="$TMP/small.ts"; lines 100 > "$SMALL"
TSX="$TMP/panel.tsx"; lines 390 > "$TSX"       # near the stated 400-line .tsx cap
HUGE="$TMP/huge.ts"; lines 900 > "$HUGE"       # ALREADY past the cap
MD="$TMP/reference.md"; lines 790 > "$MD"      # long, and no rule caps it

write() { jq -cn --arg fp "$1" --arg s "$2" '{tool_name:"Write", tool_input:{file_path:$fp, content:$s}}'; }
edit()  { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n}}'; }
multi() { jq -cn --arg fp "$1" --argjson e "$2" '{tool_name:"MultiEdit", tool_input:{file_path:$fp, edits:$e}}'; }
edit_all() { jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:$o, new_string:$n, replace_all:true}}'; }

# --- Write: the payload IS the file, exactly as before ------------------------
check "a 550-line .ts Write blocks"              2 "$(run "$(write "$TMP/new.ts" "$(lines 550)")")"
check "a 410-line .tsx Write blocks"             2 "$(run "$(write "$TMP/new.tsx" "$(lines 410)")")"
check "a Write under the cap passes"             0 "$(run "$(write "$TMP/new.ts" "$(lines 100)")")"
# a file exactly at the cap, trailing newline included, is not one over.
check "a 500-line .ts Write with a trailing newline passes" 0 \
  "$(run "$(write "$TMP/new.ts" "$(lines 500)"$'\n')")"
check "a 501-line .ts Write blocks"              2 "$(run "$(write "$TMP/new.ts" "$(lines 501)"$'\n')")"
check "the block names the cap"                  0 \
  "$(run_err "$(write "$TMP/new.ts" "$(lines 550)")" | grep -q 'cap is 500' && echo 0 || echo 1)"
check "a 450-line .ts Write is SILENT"           "" "$(run_err "$(write "$TMP/new.ts" "$(lines 450)")")"
check "a 390-line .tsx Write is SILENT"          "" "$(run_err "$(write "$TMP/new.tsx" "$(lines 390)")")"

# --- the universal 800-line rule is gone --------------------------------------
# No rule states it. A long markdown reference, a generated fixture and a shell
# script were all refused on a number nobody chose.
check "a 900-line markdown Write passes"         0 "$(run "$(write "$TMP/doc.md" "$(lines 900)")")"
check "a 900-line markdown Write is SILENT"      "" "$(run_err "$(write "$TMP/doc.md" "$(lines 900)")")"
check "an Edit growing a markdown file past 800 passes" 0 \
  "$(run "$(edit "$MD" "const x1 = 1;" "$(lines 20)")")"

# --- THE DEFECT: an Edit that pushes a file past the cap ----------------------
# 790 on disk, one line replaced by 20 = 809. Before this fix the hook read no content
# from an Edit payload, exited on its first test and measured nothing.
ADD20=$(lines 20)
# A feature growing an existing file past its cap goes ahead with a warning;
# the shrink is a follow-up unit, never a refactor folded into the feature.
check "an Edit that grows a .ts past its cap passes" 0 "$(run "$(edit "$BIG" "const x1 = 1;" "$ADD20")")"
check "a MultiEdit that grows a .ts past its cap passes" 0 \
  "$(run "$(multi "$BIG" "$(jq -cn --arg n "$ADD20" '[{old_string:"const x1 = 1;", new_string:"const x1 = 2;"},{old_string:"const x2 = 1;", new_string:$n}]')")")"
check "the warning reports the RESULTING line count and the follow-up" 0 \
  "$(run_err "$(edit "$BIG" "const x1 = 1;" "$ADD20")" | grep -q '509-line.*follow-up unit' && echo 0 || echo 1)"

# --- an edit that does not grow the file, or shrinks it, passes ---------------
check "a same-size Edit passes"                  0 "$(run "$(edit "$BIG" "const x1 = 1;" "const x1 = 2;")")"
check "a same-size Edit is SILENT"               "" "$(run_err "$(edit "$BIG" "const x1 = 1;" "const x1 = 2;")")"
check "an Edit that SHRINKS a big file passes"   0 \
  "$(run "$(edit "$BIG" "$(lines 50)" "const x1 = 1;")")"
check "an Edit on a small file passes"           0 "$(run "$(edit "$SMALL" "const x1 = 1;" "$ADD20")")"
check "an Edit that crosses the .tsx cap passes"  0 "$(run "$(edit "$TSX" "const x1 = 1;" "$ADD20")")"
check "the .tsx warning names the .tsx cap" 0 \
  "$(run_err "$(edit "$TSX" "const x1 = 1;" "$ADD20")" | grep -q 'cap is 400' && echo 0 || echo 1)"

# An edit to a file ALREADY past a threshold is usually the repair. Warning on
# every one of those -- or blocking them -- turns a long file into a file nobody
# can shorten, so a threshold fires only on the change that CROSSES it.
check "an Edit inside an already-long file is SILENT" "" \
  "$(run_err "$(edit "$BIG" "const x1 = 1;" "const x1 = 2;
const x1b = 3;")")"
check "an Edit inside an already-oversized file passes" 0 \
  "$(run "$(edit "$TMP/huge.ts" "const x1 = 1;" "const x1 = 2;
const x1b = 3;")")"

# --- where it declines to answer, deliberately -------------------------------
# A number the hook cannot compute must not be reported as fact.
check "a replace_all Edit is SILENT rather than guessing" "" \
  "$(run_err "$(edit_all "$BIG" "const x1 = 1;" "$ADD20")")"
check "a replace_all Edit passes"                0 "$(run "$(edit_all "$BIG" "const x1 = 1;" "$ADD20")")"
check "a replace_all edit inside a MultiEdit is SILENT" "" \
  "$(run_err "$(multi "$BIG" "$(jq -cn --arg n "$ADD20" '[{old_string:"const x1 = 1;", new_string:$n, replace_all:true}]')")")"
check "an Edit to a file not on disk passes"     0 "$(run "$(edit "$TMP/absent.ts" "a" "$ADD20")")"

# --- a tripwire never wedges an unrelated call -------------------------------
check "a Bash payload passes"                    0 "$(run "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')")"
check "malformed JSON passes rather than wedging" 0 "$(run 'not json')"

# --- one shared definition of the payload's shape ---------------------
# The hook used to keep its own jq over `.tool_input.edits`, beside the one in
# lib/edit-payload.sh. A second definition is how eleven guards went blind to
# MultiEdit for a month, so the shape moved into the helper.
check "the hook takes its shape from the shared helper" 0 \
  "$(grep -q 'hook_edit_size' "$HOOK" && echo 0 || echo 1)"
check "and keeps no private jq over the payload" 0 \
  "$(grep -vE '^[[:space:]]*#' "$HOOK" | grep -qE 'tool_input\.(edits|content|new_string)' && echo 1 || echo 0)"
# Without this, the helper going missing turns the cap into a silent no-op.
# The hook and helper are copied into $TMP first: tests run in parallel, and a
# chmod on the real helper blinds every hook test running at the same moment.
mkdir -p "$TMP/hooks"
cp "$HOOK" "$TMP/hooks/"; cp -R "$(dirname "$HOOK")/lib" "$TMP/hooks/"
REAL_HOOK=$HOOK HOOK="$TMP/hooks/file-size-cop.sh"
chmod 000 "$TMP/hooks/lib/edit-payload.sh" 2>/dev/null
LOADFAIL=$(run "$(write "$SMALL" "$(lines 10)")")
LOADMSG=$(run_err "$(write "$SMALL" "$(lines 10)")")
chmod 644 "$TMP/hooks/lib/edit-payload.sh"
HOOK=$REAL_HOOK
check "an unreadable helper BLOCKS instead of passing" 2 "$LOADFAIL"
check "and it says what to do" 0 \
  "$(grep -qF 'hooks/lib/edit-payload.sh did not load' <<<"$LOADMSG" && grep -qF 'Reinstall the plugin' <<<"$LOADMSG" && echo 0 || echo 1)"
check "the real helper was never touched" 0 "$([ -r "$(dirname "$HOOK")/lib/edit-payload.sh" ] && echo 0 || echo 1)"

# ONE BATCH, TWO FILES, JUDGED SEPARATELY. The old private extractor summed
# every edit against the payload-level path, so a small file's growth was
# charged to whichever file tool_input named.
TWO=$(jq -cn --arg big "$BIG" --arg small "$SMALL" --arg n "$ADD20" \
  '{tool_name:"MultiEdit",tool_input:{file_path:$small,edits:[
     {file_path:$small,old_string:"const x1 = 1;",new_string:$n},
     {file_path:$big,old_string:"const x1 = 1;",new_string:$n}]}}')
check "a two-file batch passes with a warning on the file that crosses" 0 "$(run "$TWO")"
check "and the warning names THAT file" 0 \
  "$(grep -qF "$BIG" <<<"$(run_err "$TWO")" && echo 0 || echo 1)"

# --- producer/consumer: registered where its fields exist ---------------------
# Registered on `Write` alone, it could never see the Edit payloads above.
check "registered under the Edit|Write|MultiEdit matcher" 0 \
  "$(jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit") | .hooks[] | select(.command | endswith("file-size-cop.sh\""))' "$SETTINGS" >/dev/null && echo 0 || echo 1)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
