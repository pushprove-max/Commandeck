#!/usr/bin/env bash
# ONE definition of "the text a content-screening hook should look at".
#
# WHY THIS FILE EXISTS. `hooks/hooks.json` routes several hooks on the matcher
# `Edit|Write|MultiEdit`. The three tools put their text in DIFFERENT places:
#
#   Write      tool_input.content
#   Edit       tool_input.new_string      (+ tool_input.old_string)
#   MultiEdit  tool_input.edits[].new_string  (+ .old_string) -- and NEITHER
#              tool_input.content NOR tool_input.new_string exists
#
# A hook that reads only the first two gets an empty string on a MultiEdit,
# hits its `[ -z "$CONTENT" ] && exit 0` line, and passes the batch without
# screening one character. That is not a theory: the edits[] fold was applied
# to four hooks on 2026-07-27 and never carried to their eleven siblings, so a
# MultiEdit walked past every one of them until 2026-08-31.
#
# Sibling drift on a security-relevant contract is fixed by having one
# definition, not by fixing eleven hooks eleven times. EVERY content-screening
# hook sources this file -- including the four that already worked -- so the
# next tool shape is added here once.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh"
#   INPUT=$(cat)
#   CONTENT=$(hook_new_text "$INPUT")   # text about to be WRITTEN
#   OLD=$(hook_old_text "$INPUT")       # text about to be REPLACED/REMOVED
#
# All three functions print nothing and succeed on a payload that carries no
# edit text at all (a Bash payload, malformed JSON, an empty tool_input). A
# hook must stay a tripwire, never a wedge on unrelated tool calls.

# Everything this tool call is about to write, newline-joined across a batch.
hook_new_text() {
  printf '%s' "$1" | jq -r '[
    .tool_input.content // empty,
    .tool_input.new_string // empty,
    (.tool_input.edits // [] | .[] | .new_string // empty)
  ] | join("\n")' 2>/dev/null || true
}

# Everything this tool call is about to replace. A Write has none (a new file
# removes nothing), which is what keeps removal checks from firing on creates.
hook_old_text() {
  printf '%s' "$1" | jq -r '[
    .tool_input.old_string // empty,
    (.tool_input.edits // [] | .[] | .old_string // empty)
  ] | join("\n")' 2>/dev/null || true
}

# One record per (path, about-to-be-written text) pair, for a hook whose
# exemption is a property of the FILE rather than of the payload. Pooling the
# text and testing one path let an exempt path -- `src/a.test.ts` in the first
# edit -- carry a violation in `src/api.ts` in the second.
#
# Both fields are base64 so a newline or a tab in either cannot split a record;
# jq's @base64 emits one unwrapped line, unlike base64(1)'s 76-column default.
# A per-edit file_path wins over the payload-level one; in this repo's payloads
# MultiEdit keeps the path on tool_input.file_path, so the fallback is what
# usually applies.
#
# Read it with:  while IFS=$'\t' read -r P64 C64; do ... done <<< "$PAIRS"
hook_edit_pairs() {
  printf '%s' "$1" | jq -r '
    .tool_input as $t
    | [
        { p: ($t.file_path // ""), c: ($t.content    // empty) },
        { p: ($t.file_path // ""), c: ($t.new_string // empty) },
        ($t.edits // [] | .[] | { p: (.file_path // $t.file_path // ""),
                                  c: (.new_string // empty) })
      ]
    | .[] | select(.c != "") | "\(.p | @base64)\t\(.c | @base64)"' 2>/dev/null || true
}

# One record per edit, carrying BOTH sides: path, text being written, text being
# replaced. A hook that must ask "did THIS edit add an occurrence" cannot answer
# it from the pooled region -- for a MultiEdit the pooled old text spans the
# whole batch, so one retained occurrence anywhere in it excused every edit in
# it. This is also the one call that answers everything: a hook can join the
# records to get the pooled text instead of paying a second and third jq.
#
# Records where BOTH sides are empty are dropped; a pure deletion (new empty,
# old set) is kept, because the removal is what some rules read.
#
# Read it by splitting each line on the tabs yourself -- NOT `IFS=$'\t' read`:
# a tab is IFS whitespace, so a deletion's empty new text collapses and the old
# text lands in N64:
#   while IFS= read -r REC; do P64=${REC%%$'\t'*} R=${REC#*$'\t'}; N64=${R%%$'\t'*} O64=${R#*$'\t'}; ...
hook_edit_triples() {
  printf '%s' "$1" | jq -r '
    .tool_input as $t
    | [
        { p: ($t.file_path // ""), n: ($t.content    // ""), o: "" },
        { p: ($t.file_path // ""), n: ($t.new_string // ""), o: ($t.old_string // "") },
        ($t.edits // [] | .[] | { p: (.file_path // $t.file_path // ""),
                                  n: (.new_string // ""),
                                  o: (.old_string // "") })
      ]
    | .[] | select(.n != "" or .o != "")
    | "\(.p | @base64)\t\(.n | @base64)\t\(.o | @base64)"' 2>/dev/null || true
}

# THE SIZE SHAPE. A content guard asks what TEXT a call writes; a size
# guard asks what the call does to a file's LENGTH, and neither the pairs nor
# the triples can answer that: a Write states the whole file, while an insertion
# whose old text is empty looks identical to it in both. file-size-cop.sh kept a
# private jq over `.tool_input.edits` for exactly this, and a second definition
# is how eleven guards went blind to MultiEdit for a month. One record per path:
#
#   <path base64>\twrite\t<lines the file will have>
#   <path base64>\tedit\t<net lines this call adds to the file on disk>
#
# Prints NOTHING when any edit sets `replace_all`: a swap applied an unknown
# number of times has no line arithmetic, and a guessed number would either
# block a legitimate write or, reported as fact, be believed.
hook_edit_size() {
  printf '%s' "$1" | jq -r '
    .tool_input as $t
    | if ([$t] + ($t.edits // []) | any(.replace_all == true)) then empty
      elif ($t.content // null) != null then
        # A trailing newline ends the last line; it does not start another (wc -l).
        "\(($t.file_path // "") | @base64)\twrite\t\($t.content | rtrimstr("\n") | split("\n") | length)"
      else
        [ ([$t | select(.new_string != null)] + ($t.edits // []))[]
          | { p: (.file_path // $t.file_path // ""),
              d: (((.new_string // "") | split("\n") | length)
                 - ((.old_string // "") | split("\n") | length)) } ]
        | group_by(.p)[]
        | "\((.[0].p) | @base64)\tedit\t\(map(.d) | add)"
      end' 2>/dev/null || true
}

# LOAD SENTINEL, and the reason it is the LAST thing in this file. Every content
# guard sources this file. If the file is missing, unreadable, or truncated, the
# extractor is undefined, the guard's CONTENT comes back empty and it exits
# clean -- the exact silent-guard shape this whole unit exists to kill, now with
# twenty hooks depending on one file.
#
# So every call site runs `hook_payload_loaded` immediately after sourcing. A
# missing file leaves the name undefined and the call fails; a file truncated
# anywhere above leaves it undefined too, because it is defined LAST. The call
# site then BLOCKS the tool call rather than passing the write unscreened.
# Keep this at the bottom: moved up, it stops proving the file loaded whole.
hook_payload_loaded() { return 0; }
