#!/usr/bin/env bash
# PreToolUse hook (Edit|Write): block NEW content that reaches for a pattern
# with a blessed path or a known-defect history, unless annotated with a
# stated reason.
#
# CHARTER: hooks are TRIPWIRES against sloppiness, not security boundaries.
# Every rule here is seeded by a real incident; a rule that fires on ordinary
# work gets muted, and a muted hook protects nothing.
#
# Matching runs against what is being WRITTEN (new_string/content), never the
# on-disk file -- so it fires exactly when the pattern is introduced or
# rewritten, and pre-existing occurrences cause no churn. That is also why
# none of these rules needs a repo-wide migration: 470 existing cast sites
# stay untouched; only new writing pays the toll.
#
# Rule format (@@ delimiter -- patterns need alternation, see
# companion-read-guard.sh for the `|` incident):
#   pattern@@applies-path-regex@@exempt-path-regex@@annotation@@message
# `applies` and `exempt` match the repo-relative path; the rule fires only
# when the path matches `applies` and not `exempt`. The annotation is the
# escape hatch and must appear WITH A REASON in the written region.

INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Strict tier: off unless the project turned it on (lib/project.sh).
{ . "${BASH_SOURCE[0]%/*}/lib/project.sh" && pp_strict; } 2>/dev/null || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/lib/edit-payload.sh" 2>/dev/null
. "${BASH_SOURCE[0]%/*}/lib/screen-code.sh" 2>/dev/null
# A guard that cannot read the payload must NOT pass the write: see the load
# sentinel at the bottom of lib/edit-payload.sh.
hook_payload_loaded 2>/dev/null || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not load hooks/lib/edit-payload.sh, so it cannot screen this write. Reinstall the plugin (\`claude plugin install commandeck@commandeck\`) and retry." >&2; exit 2; }

# ONE PARSE. Every rule below reads some slice of the payload -- the path, the
# text going in, the text coming out, or all three per edit -- and each slice
# used to cost its own jq. `hook_edit_triples` answers all of them in one call:
# the pooled region is the records joined, and the per-edit question the rules
# table asks is the records read one at a time.
TRIPLES=$(hook_edit_triples "$INPUT")

# ONE FILE AT A TIME. Every check below that reads FILE_PATH reads the first
# record's, so a batch whose first edit is in an exempt file carried the other
# files past them. A payload over several files is screened once per file.
_paths=$(cut -f1 <<<"$TRIPLES" | grep . | sort -u)
if [ "$(grep -c . <<<"$_paths")" -gt 1 ]; then
  while IFS= read -r _p64; do
    _one=$(jq -c --arg p "$(printf '%s' "$_p64" | base64 -d 2>/dev/null)" '.tool_input |= (. as $t
      | (if ($t.file_path // "") == $p then . else del(.content, .new_string, .old_string) end)
      | .edits = [($t.edits // [])[] | select((.file_path // $t.file_path // "") == $p)] | .file_path = $p)' <<<"$INPUT") \
      || { echo "BLOCKED: ${BASH_SOURCE[0]##*/} could not split a batch over several files, so it cannot screen this write. Send one \`Edit\` call per file." >&2; exit 2; }
    printf '%s' "$_one" | bash "${BASH_SOURCE[0]}" || exit $?
  done <<<"$_paths"
  exit 0
fi
FILE_PATH=""
REGION=""
OLD_REGION=""
while IFS= read -r _rec; do
  [ -n "$_rec" ] || continue
  _p64=${_rec%%$'\t'*} _r=${_rec#*$'\t'}; _n64=${_r%%$'\t'*} _o64=${_r#*$'\t'} # split by hand: see hook_edit_triples
  [ -n "$FILE_PATH" ] || FILE_PATH=$(printf '%s' "$_p64" | base64 -d 2>/dev/null)
  _n=$(printf '%s' "$_n64" | base64 -d 2>/dev/null)
  _o=$(printf '%s' "$_o64" | base64 -d 2>/dev/null)
  [ -n "$_n" ] && REGION="${REGION:+$REGION
}$_n"
  [ -n "$_o" ] && OLD_REGION="${OLD_REGION:+$OLD_REGION
}$_o"
done <<< "$TRIPLES"

# CR NEVER ENTERS THE TREE. Every path, no exemption by directory -- the repo is
# LF only, and a stray CR in a shell script or a JSON file is as bad as one in
# source. It runs before the FILE_PATH test because a payload with content and
# no path still must not carry one.
#
# A CARRIAGE RETURN, not the two-character sequence. grep works one line at a
# time and strips the \n that terminates each line, so `grep -P '\r\n'` can
# never match line-internally -- that check could not fire in the environment a
# hook actually runs in (found 2026-08-31). A bare \r is what is banned anyway:
# a lone CR (old Mac ending) is no more welcome than CRLF.
if [[ "$REGION" == *$'\r'* ]]; then
  # A FILE THAT ALREADY CARRIES CR IS EXEMPT. Five tracked files do -- two
  # skills docs, two archived audit reports, one archived plan -- and matching a
  # bare \r without this would block every edit to them, including the edit that
  # cleans them up. This stops CR ENTERING the tree; a file that is already
  # non-conforming is a cleanup task, not this write's fault.
  #
  # Stated ceiling: such a file can gain more CR. Fixing that means cleaning the
  # five files, not blocking work on them.
  if ! { [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ] && grep -qU $'\r' "$FILE_PATH" 2>/dev/null; }; then
    echo "BLOCKED: Write to ${FILE_PATH:-unknown} contains CRLF line endings. Use LF only (Unix-style). Remove all \\r characters." >&2
    exit 2
  fi
fi

# A HOOK MUST STILL PARSE AFTER THE EDIT. One that does not exits 2 on every
# call, and the harness reads 2 as a refusal: every tool call the hook is
# registered for is refused, the edit that repairs it included (2026-10-13, an
# apostrophe in a single-quoted jq block). The text the file would hold is
# built from the payload and given to `bash -n`. A file that already fails to
# parse takes any edit, so this never refuses a repair.
# Limits: a hook broken by a merge, a checkout or a hand outside the Edit and
# Write tools still locks its pane out until it is repaired from outside; a
# write through serena or another MCP tool is not seen; `bash -n` finds syntax
# errors only.
# A hook is a .sh file under a folder named hooks: a project's .claude/hooks
# and this plugin's own hooks alike. It is known by where the file is, with
# links resolved and letter case ignored, not by how the path is spelled.
# Each edit of a batch is judged by its own path, the top-level one when it
# has none. A payload this cannot rebuild is let through, not refused.
PARSE=$(printf '%s' "$INPUT" | python3 -c '
import json, os, re, subprocess, sys
def parse(s):
    r = subprocess.run(["bash", "-n", "/dev/stdin"], input=s, capture_output=True, text=True)
    return r.stderr.strip().replace("/dev/stdin: ", "") if r.returncode else ""
t = json.load(sys.stdin).get("tool_input") or {}
by = {}
for e in t.get("edits") or [t]:
    p = e.get("file_path") or t.get("file_path")
    if isinstance(p, str) and re.search(r"/hooks/.*\.sh$", os.path.realpath(p), re.I):
        by.setdefault(p, []).append(e)
bad = []
for p, edits in by.items():
    try:
        s = open(p, encoding="utf-8").read()
    except OSError:
        s = ""
    if parse(s):
        continue
    for e in edits:
        if "content" in e:
            s = e["content"]
        if "old_string" in e:
            s = s.replace(e["old_string"], e.get("new_string") or "", -1 if e.get("replace_all") else 1)
    if parse(s):
        bad.append(os.path.basename(p) + " would no longer parse (bash -n says: " + parse(s) + ")")
if bad:
    print("; ".join(bad))
    sys.exit(2)') || {
  [ $? -ne 2 ] || {
    echo "BLOCKED: after this edit $PARSE. A hook that does not parse refuses every call it is registered for, its own repair included. Fix the text; \`bash -n <file>\` reads it the same way." >&2
    exit 2
  }
}

# Hardcoded localhost HTTP target in app code. In a container or a cloud function,
# localhost does not resolve to the service the author meant; the URL belongs in
# an env var or a service name. A `curl` to a local port in a shell is ordinary
# local development and is deliberately NOT screened -- a Bash payload carries no
# content field and never reaches here.
#
# EACH EDIT IS JUDGED BY ITS OWN PATH, so a MultiEdit is decomposed into
# (path, text) pairs and every pair is tested alone. Pooling the text and
# testing one path let a single exempt path -- `src/a.test.ts` in the first
# edit -- carry a violation in `src/api.ts` in the second.
#
# `hooks/` is exempt because the guards and their fixtures QUOTE the
# pattern in order to ban it, the same carve-out test-skip-only-blocker and
# xss-blocker already carry; without it this rule blocks every edit to itself.
#
# It runs ABOVE the top-level-path guard below: a MultiEdit can put file_path on
# each edit and send none at the top, and such a payload must still be judged.
# Every rule below is about THIS project: the one the session runs in, its
# worktrees included. A file outside it (a memory note under ~/.claude, a file
# in another repo) is not screened. The project is asked by where it is, never
# by what it carries: an installed plugin's hooks are not in the project. A new
# file in a new directory walks up to an existing parent, so a fresh path
# inside the checkout is still in scope.
pp_project "$(pwd -P)"; _SESSION_PROJECT=$PP_PROJECT_DIR
in_project_tree() {
  local d p PP_PROJECT PP_PROJECT_DIR
  # A symlink outside the tree that points into it is judged by its target.
  p=$(readlink -f "$1" 2>/dev/null) || p=$1
  d=$(dirname "$p")
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do d=$(dirname "$d"); done
  d=$(cd "$d" 2>/dev/null && pwd -P) || return 1
  pp_project "$d"
  [ -n "$_SESSION_PROJECT" ] && [ "$PP_PROJECT_DIR" = "$_SESSION_PROJECT" ]
}

_LOCALHOST_RE="fetch\\s*\\(\\s*['\"]https?://localhost|http://127\\.0\\.0\\.1|axios.*localhost"
while IFS= read -r _rec; do
  _p64=${_rec%%$'\t'*} _r=${_rec#*$'\t'}; _c64=${_r%%$'\t'*} # split by hand: see hook_edit_triples
  [ -n "$_c64" ] || continue
  _pair_path=$(printf '%s' "$_p64" | base64 -d 2>/dev/null)
  in_project_tree "$_pair_path" || continue
  case "$_pair_path" in
    *.test.*|*__tests__*|*vite.config*|*jest*|*.env*|*e2e/*) continue ;;
    */hooks/*.sh|hooks/*.sh) continue ;;  # the hook scripts quote the form; a project's src/hooks does not
  esac
  if printf '%s' "$_c64" | base64 -d 2>/dev/null | grep -qE "$_LOCALHOST_RE"; then
    echo "BLOCKED: HTTP fetch to a local address in $_pair_path. In containers, localhost doesn't resolve to the expected service. Use the service name or environment variable for the URL." >&2
    exit 2
  fi
done <<< "$TRIPLES"

[ -z "$FILE_PATH" ] && exit 0

# The memory index loads into every session and is re-sent on every call, so it
# is capped. It lives under ~/.claude, outside the tree, hence above the scope
# check. Only growth past the cap blocks: the edit that shrinks an over-cap
# index must pass. Edits apply in order, each to the previous result, as the
# tool applies them; split/join is literal, never a regex.
case "$FILE_PATH" in
  */memory/MEMORY.md|memory/MEMORY.md)
    _mem_cap=18000
    _mem_cur=$(wc -c 2>/dev/null < "$FILE_PATH" || echo 0)
    _mem_src=$FILE_PATH; [ -f "$_mem_src" ] || _mem_src=/dev/null
    _mem_new=$(jq -r --rawfile cur "$_mem_src" '.tool_input as $t
      | if $t.content != null then ($t.content | utf8bytelength)
        else reduce ($t.edits // [$t])[] as $e ($cur;
          ($e.old_string // "") as $o | ($e.new_string // "") as $n
          | if $o == "" then . + $n
            elif $e.replace_all == true then split($o) | join($n)
            else split($o) as $p | if ($p | length) < 2 then . else $p[0] + $n + ($p[1:] | join($o)) end end)
          | utf8bytelength end' <<< "$INPUT" 2>/dev/null)
    if [ "${_mem_new:-0}" -gt "$_mem_cap" ] && [ "$_mem_new" -gt "$_mem_cur" ]; then
      echo "BLOCKED: this leaves $FILE_PATH at $_mem_new bytes, over the $_mem_cap-byte cap. Move entries for merged or closed work to ARCHIVE.md, or shorten hooks, then retry." >&2
      exit 2
    fi
  ;;
esac

in_project_tree "$FILE_PATH" || exit 0

# A linked worktree checkout lives under .claude/worktrees/<name>/; files
# there are ordinary repo content, not Claude-internal. Scope-check the
# collapsed path so the .claude exemption below cannot silently disable this
# hook for entire worktree sessions (2026-08-04). FILE_PATH itself stays
# untouched -- downstream logic needs the real on-disk path.
SCOPE_PATH="$FILE_PATH"
case "$SCOPE_PATH" in
  */.claude/worktrees/*) _wt_rest="${SCOPE_PATH#*/.claude/worktrees/}"; SCOPE_PATH="${SCOPE_PATH%%/.claude/worktrees/*}/${_wt_rest#*/}" ;;
esac
[ -z "$REGION" ] && exit 0
# A patch carries the unchanged lines around its change in new_string. The bans
# on what a line says (credits, deferred-work markers, suppressions) read only
# the lines this edit adds: a marker already in the file is not this edit's.
# shortcut: a second copy of a line the edit carries reads as carried; diff the two texts if that shows up.
ADDED=$REGION
[ -z "$OLD_REGION" ] || ADDED=$(printf '%s\n' "$REGION" | grep -vxFf <(printf '%s\n' "$OLD_REGION") || true)

# Contributor-credit markers never re-enter the tree (owner ruling 2026-08-30,
# the same-day scrub removed the existing ones).
# EVERY file including markdown, except .claude/ and .githooks/, whose rules
# and guards quote the banned patterns in order to ban them.
case "$SCOPE_PATH" in
  */.claude/*|*/.githooks/*) : ;;
  *)
    if printf '%s' "$ADDED" | grep -qiE 'co-authored-by:.*claude|noreply@anthropic\.com|generated with .{0,3}\[?claude code|claude-session:'; then
      cat >&2 <<EOF
BLOCKED: $FILE_PATH adds a Claude contributor credit (Co-Authored-By /
noreply@anthropic.com / Generated with Claude Code / Claude-Session).
Credits are banned repo-wide.
EOF
      exit 2
    fi
  ;;
esac


# Ownerless deferred-work markers and vague placeholders. An ISSUE-REFERENCED
# TODO is allowed: `TODO(#<issue>): ...` passes, and this
# bans only the ownerless kind. grep -E is POSIX ERE with no lookahead, so the
# allowed form is neutralised before matching rather than excluded inside the
# pattern -- the substitute keeps a word character next to TODO, so the `\b` arm
# cannot re-match it.
case "$SCOPE_PATH" in
  */.claude/*|*.md|*backlog*) : ;;
  *)
    SCREENED=$(printf '%s' "$ADDED" | sed -E 's/TODO\(#[0-9]+\):/TODO_WITH_ISSUE:/g')
    if printf '%s' "$SCREENED" | grep -qiE '//\s*(TODO|FIXME|HACK|XXX|TEMP|TEMPORARY)\b|/\*\s*(TODO|FIXME|HACK)'; then
      MATCH=$(printf '%s' "$SCREENED" | grep -oiE '(TODO|FIXME|HACK|XXX|TEMP)\b[^"]*' | head -1)
      echo "BLOCKED: Deferred work marker in $FILE_PATH: '$MATCH'. Fix it now or remove the comment." >&2
      echo "An ownerless marker is what is banned. A TODO carrying an issue number -- TODO(#<issue>): ... -- is allowed." >&2
      exit 2
    fi
    if printf '%s' "$ADDED" | grep -qiE '//\s*(implement later|temporary fix|placeholder|will be replaced|needs refactor|come back to this)'; then
      echo "BLOCKED: Vague placeholder comment in $FILE_PATH. Either implement it now or remove the comment." >&2
      exit 2
    fi
  ;;
esac

# Issue 398: placeholder copy in screen code ("coming soon") is built only when the plan or main's rulings name its
# complete line. The path made repo-relative by screen_rel decides what is screen code; the unit and main come from
# that file's own checkout, never the session's working folder. Always-disabled controls are the merge's: one home for
# their refusal and its per-line approval count.
if type screen_rel >/dev/null 2>&1 && _sr=$(screen_rel "$FILE_PATH") && [ -n "$_sr" ]; then
  _rel=${_sr%%$'\n'*} _root=${_sr#*$'\n'}
  _main=$(pp_project "$_root"; printf '%s' "$PP_PROJECT_DIR")
  SCREEN_PREFIXES=$(screen_prefixes "$_main")
  if is_screen "$_rel"; then
    _copy=""
    while IFS= read -r _l; do
      printf '%s' "$_l" | grep -qiE "$PLACEHOLDER_COPY" || continue
      placeholder_requested "$_rel" "$_l" "${_root##*/}" "$_root" "$_main" || _copy="${_copy:+$_copy; }\"$(_sc_trim "$_l")\""
    done <<<"$ADDED"
    if [ -n "$_copy" ]; then
      echo "BLOCKED: placeholder copy in $FILE_PATH: $_copy. Build only what the plan asks for; a mockup element the plan does not build is left out and sent to main as a question. Allowed only when the plan or main's rulings name the complete line: Placeholder: $_rel | <complete source line> | <why>" >&2
      exit 2
    fi
  fi
fi

# Type/lint suppression directives in application src/. These escape hatches
# silence the type check and hide real defects; fix the underlying
# error instead. Tests are exempt (@ts-expect-error is legitimate in a type
# test), as are declaration files and everything outside src/.
case "$FILE_PATH" in
  */src/*)
    case "$FILE_PATH" in
      *.test.*|*.spec.*|*__tests__*|*.d.ts) ;;
      *)
        if printf '%s' "$ADDED" | grep -qE '@ts-(ignore|expect-error|nocheck)\b'; then
          MATCH=$(printf '%s' "$ADDED" | grep -oE '@ts-(ignore|expect-error|nocheck)' | head -1)
          echo "BLOCKED: '$MATCH' in $FILE_PATH suppresses TypeScript instead of fixing it." >&2
          echo "Resolve the underlying type error; do not route around the type check." >&2
          exit 2
        fi
        if printf '%s' "$ADDED" | grep -qE 'eslint-disable'; then
          echo "BLOCKED: 'eslint-disable' in $FILE_PATH. Fix the lint violation rather than disabling the rule." >&2
          exit 2
        fi
      ;;
    esac
  ;;
esac

case "$SCOPE_PATH" in
  */.claude/*|*.md|*.json) exit 0 ;;
esac
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
REL="${FILE_PATH#"$ROOT"/}"

# Comments and string literals are not code: `// never write x as any here`
# is ordinary documentation, not a cast (Codex round-1 P2). Patterns
# match the stripped region; the ANNOTATION check runs on the raw region,
# because annotations ARE comments.
#
# Quote-stripping runs BEFORE the // expression (Claude round-2 P3): the
# other order let a `//` inside a string ("http://...") truncate the rest of
# the line and swallow a genuinely new pattern beside it.
strip_noise() {
  sed -e "s:'[^']*'::g" -e 's:"[^"]*"::g' -e 's:`[^`]*`::g' -e 's://.*::' \
    | perl -0777 -pe 's{/\*.*?\*/}{}gs' 2>/dev/null
}

# Reviewer names in code comments
# ("COMMENTS SAY WHAT, NOT WHO", owner ruling 2026-08-27): a comment describes
# the code's behaviour; who filed the finding and at what severity belongs in
# the review record. Such markers outlive the round they came from and read as
# authority to the next person in the file.
#
# This rule cannot ride the RULES table below: those patterns match
# CODE_REGION, which has every comment stripped out. It matches the raw region,
# and only lines that OPEN with a comment marker -- a reviewer name inside a
# string literal (UI copy, a log message) is content, not review history.
#
# Test files are exempt: a test NAMES the case it pins, and the clearest name
# for a regression test is often the finding it came from.
_reviewer_scope=1
case "$REL" in
  *.test.*|*.spec.*|*/__tests__/*|*/test/*|*/tests/*) _reviewer_scope=0 ;;
esac
if [ "$_reviewer_scope" = 1 ]; then
  _names='Codex|Claude|Opus|reviewer'
  _who_what="\\b($_names)\\b.*\\bP[0-3]\\b|\\bP[0-3]\\b.*\\b($_names)\\b"
  _who_round="\\b($_names)\\b.*\\bround[[:space:]]+[0-9]+\\b|\\bround[[:space:]]+[0-9]+\\b.*\\b($_names)\\b"
  _phrases='Codex flagged|Claude flagged|per review'
  _matches=$(printf '%s\n' "$REGION" \
    | grep -E '^[[:space:]]*(//|/\*|\*|#)' \
    | grep -E "$_who_what|$_who_round|$_phrases" || true)
  while IFS= read -r _line; do
    [ -z "$_line" ] && continue
    # A comment the edit merely CARRIES ALONG pays no toll (same posture as the
    # retained-occurrence check below): only newly written history blocks.
    printf '%s\n' "$OLD_REGION" | grep -qxF "$_line" && continue
    cat >&2 <<EOF
BLOCKED: $REL names a reviewer, a round or a severity in a code comment.

  line: $_line

  Comments say what the code does, not who asked for it. Review history lives
  in the round files.
EOF
    exit 2
  done <<< "$_matches"
fi

RULES=(
  # Type-safety escapes. `as never` type-checked a call that threw on the
  # first ring (2026-07-27) -- the cast hid exactly the mismatch the compiler
  # was reporting. In TEST files the same escape is how a fake drifts from the
  # real symbol unnoticed: the 2026-09-02 mock audit found 220 doubles whose
  # shape production no longer has, every one handed over through a cast.
  # A lint rule cannot carry this where pre-existing sites make a repo-wide
  # error untenable, so the toll applies to NEW writing only.
  '\bas never\b|\bas any\b|\bas unknown as\b@@\.(ts|tsx|mts|cts)$@@^$@@cast-ok@@a cast (as never / as any / as unknown as) hides whatever shape mismatch the compiler was about to report; in a test it lets a fake drift from the real symbol while the test stays green -- type the value against the real symbol, or state why the cast is sound: // cast-ok: <reason>'

  # JSON.stringify equality on objects compares KEY ORDER: it reported records
  # diverged that were content-identical. Compare a key-sorted form instead.
  'JSON\.stringify\([^)]*\)\s*[!=]==?\s*JSON\.stringify@@\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$@@^$@@stringify-compare-ok@@JSON.stringify equality compares KEY ORDER, not content -- two objects with identical content routinely differ in key order. Compare a key-sorted form; if byte-order equality is genuinely intended, annotate: // stringify-compare-ok: <reason>'
)

# ONE EDIT AT A TIME, AND ONLY WHAT IT ADDS. Each edit is judged by its own
# path -- for a MultiEdit the pooled path was the payload's, so a batch whose
# first edit hit an exempt file carried the second one's violation -- and the
# toll is on ADDITIONS: the pattern must occur MORE times in what this edit
# writes than in what it replaces. Asking only "was it there before" excused an
# edit that added a second cast beside a retained one, and for a batch it
# excused every edit in it.
#
# With ~1,160 cast sites in runtime code, a rule that charged for merely
# touching a line someone else's cast lives on would get this hook muted, which
# is why the comparison is per edit and not against the file.
for RULE in "${RULES[@]}"; do
  PATTERN="${RULE%%@@*}"
  REST="${RULE#*@@}"
  APPLIES="${REST%%@@*}"
  REST="${REST#*@@}"
  EXEMPT="${REST%%@@*}"
  REST="${REST#*@@}"
  ANNOTATION="${REST%%@@*}"
  MESSAGE="${REST#*@@}"

  while IFS= read -r _rec; do
    # Split by hand: read drops an empty field between two tabs, and a deletion's new text is one.
    _p64=${_rec%%$'\t'*} _r=${_rec#*$'\t'}; _n64=${_r%%$'\t'*} _o64=${_r#*$'\t'}
    [ -n "$_n64" ] || continue
    _epath=$(printf '%s' "$_p64" | base64 -d 2>/dev/null)
    [ -n "$_epath" ] || _epath="$FILE_PATH"
    _erel="${_epath#"$ROOT"/}"

    echo "$_erel" | grep -qE "$APPLIES" || continue
    echo "$_erel" | grep -qE "$EXEMPT" && continue

    # Tests: only the cast rule applies (a test may legitimately name a
    # JSON.stringify compare or a reviewer as the case it pins).
    case "$_erel" in
      */__tests__/*|*.test.ts|*.test.tsx|*.spec.ts)
        [ "$ANNOTATION" = cast-ok ] || continue
      ;;
    esac

    _enew=$(printf '%s' "$_n64" | base64 -d 2>/dev/null)
    _n_count=$(printf '%s' "$_enew" | strip_noise | grep -oE "$PATTERN" | wc -l | tr -d ' ')
    [ "${_n_count:-0}" -gt 0 ] || continue
    _o_count=$(printf '%s' "$_o64" | base64 -d 2>/dev/null | strip_noise | grep -oE "$PATTERN" | wc -l | tr -d ' ')
    [ "$_n_count" -gt "${_o_count:-0}" ] || continue
    # Annotated WITH a reason (bare marker does not pass), in the text this
    # edit writes.
    printf '%s' "$_enew" | grep -qE "//[[:space:]]*$ANNOTATION:[[:space:]]*\S" && continue

    cat >&2 <<EOF
BLOCKED: $_erel introduces a pattern with a known defect history.

  pattern: $PATTERN

  $MESSAGE

  If this use is deliberate, annotate it in the same edit: // $ANNOTATION: <reason>
EOF
    exit 2
  done <<< "$TRIPLES"
done

exit 0
