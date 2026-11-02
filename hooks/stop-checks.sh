#!/usr/bin/env bash
# Stop hook: run the commands the project lists in .claude/stop-checks, in the worktree whose Stop fired, so an edit
# that breaks a check holds the turn (issue 518). Self-test: bash hooks/__tests__/stop-checks.test.sh
#
# The file is read from main's checkout (pp_project), one command per line, `#` comments, and an optional
# `seconds: <n>` (default 30, cap 120): ONE deadline for the whole run. A Stop entry has no `onFailure`, so a run must
# end inside the entry's own timeout (135 s): each command gets `timeout -k 2 <seconds left>`, and at the deadline the
# commands left do not run and the text names them. Each line runs under `bash -c`, with this hook's environment.
# A failed command leaves the rest to run.
#
# Order: stop_hook_active; main's checkout; the file; tracked check; key; replay; run.
#  - Main's checkout is skipped: the issue is about edits between review passes.
#  - A file git tracks runs nothing, whatever path reaches it (a link, a linked .claude folder): a tracked file could
#    bring a clone's commands to run here. The check reads the file's realpath and asks the checkout that owns it.
#  - The key is the worktree's tree (a temp index: no real index or tree changes; .claude/briefs holds no code and is
#    left out) plus the cksum of the file. The same key replays the last answer, a red included, so a repeat Stop is
#    never promoted to a pass; a new tree or a changed file runs. State: <git dir>/commandeck-stop-checks, the
#    message beside it as .msg, written after each run.
#  - A refusal exits 2 and says failed, deadline or could not run; a check that never ran never reads as a pass.
#  - The second Stop on a red tree passes (stop_hook_active), so a turn cannot loop.
INPUT=$(cat)
. "${BASH_SOURCE[0]%/*}/lib/hook-fire-log.sh" 2>/dev/null && hook_fire_log_arm "$INPUT"
# Retire when: no project lists a command in .claude/stop-checks across 90 days of rows
. "${BASH_SOURCE[0]%/*}/lib/project.sh"
[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" = true ] && exit 0

CWD=$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD=$PWD
WT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
GD=$(git -C "$WT" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
[ "$GD" != "$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ] || exit 0

pp_project "$WT"
FILE=$PP_PROJECT_DIR/.claude/stop-checks
[ -f "$FILE" ] || exit 0

# refuse <slug> <text> -- hold the turn.
refuse() { HOOK_FIRE_REASON=$1; printf '%s\n' "$2" >&2; exit 2; }

REAL=$(realpath -- "$FILE" 2>/dev/null) \
  || refuse checks-could-not-run "BLOCKED: .claude/stop-checks could not run: \`realpath $FILE\` failed, so the file cannot be checked against git."
if [ -n "$(git -C "${REAL%/*}" ls-files -- "${REAL##*/}" 2>/dev/null)" ]; then
  # Exit 1: a notice, not a hold. The file stays untouched and nothing in it ran.
  printf 'stop-checks ran nothing: %s is tracked in git, and a tracked file could bring a clone'"'"'s commands to run here. Untrack it with `git -C %q rm --cached -- %q`.\n' \
    "$REAL" "${REAL%/*}" "${REAL##*/}" >&2
  exit 1
fi

TI=$(mktemp "${TMPDIR:-/tmp}/stop-checks-index.XXXXXX") || refuse checks-could-not-run "BLOCKED: stop-checks could not run: \`mktemp\` failed."
rm -f "$TI"
[ ! -f "$GD/index" ] || cp "$GD/index" "$TI" 2>/dev/null
TREE=$(export GIT_INDEX_FILE=$TI
  git -C "$WT" add -A >/dev/null 2>&1 && git -C "$WT" rm -rq --cached --ignore-unmatch -- .claude/briefs >/dev/null 2>&1 \
    && git -C "$WT" write-tree 2>/dev/null)
rm -f "$TI" "$TI.lock"
[ -n "$TREE" ] || refuse checks-could-not-run "BLOCKED: .claude/stop-checks could not run: \`git -C $WT write-tree\` gave no tree."
CKS=$(cksum < "$FILE"); CKS=${CKS%% *}

STATE=$GD/commandeck-stop-checks
if [ -f "$STATE" ]; then
  read -r PT PC PR < "$STATE"
  # A line with no plain rc is no key: the checks run again, so a cut line never reads as green.
  if [ "$PT" = "$TREE" ] && [ "$PC" = "$CKS" ] && [[ ${PR-} =~ ^[0-9]+$ ]]; then
    [ "$PR" != 0 ] || exit 0
    HOOK_FIRE_REASON=checks-replayed
    cat "$STATE.msg" >&2 2>/dev/null
    exit 2
  fi
fi

command -v timeout >/dev/null 2>&1 \
  || refuse checks-could-not-run "BLOCKED: .claude/stop-checks could not run: there is no \`timeout\` command. Run \`brew install coreutils\`, or /commandeck:setup."
SECS=30 CMDS=()
while IFS= read -r RAW || [ -n "$RAW" ]; do
  LINE=${RAW//$'\r'/}
  LINE="${LINE#"${LINE%%[![:space:]]*}"}"
  LINE="${LINE%"${LINE##*[![:space:]]}"}"
  [ -n "$LINE" ] || continue
  case $LINE in \#*) continue ;; esac
  if [[ $LINE =~ ^seconds:[[:space:]]*([0-9]+)$ ]]; then SECS=$((10#${BASH_REMATCH[1]})); continue; fi
  CMDS+=("$LINE")
done < "$FILE"
[ "$SECS" -ge 1 ] || SECS=1
[ "$SECS" -le 120 ] || SECS=120

now_ms() { local t=${EPOCHREALTIME-}; if [ -n "$t" ]; then t=${t/[.,]/}; echo $((t / 1000)); else echo $((SECONDS * 1000)); fi; }
OUTF=$(mktemp "${TMPDIR:-/tmp}/stop-checks-out.XXXXXX") || refuse checks-could-not-run "BLOCKED: stop-checks could not run: \`mktemp\` failed."
DEADLINE=$(( $(now_ms) + SECS * 1000 ))
MSG="" NOTRUN="" DEAD="" CUT="" CNR=""
tailed() { tail -n 15 "$OUTF" 2>/dev/null | sed 's/^/    /'; }
for i in "${!CMDS[@]}"; do
  cmd=${CMDS[$i]}
  left=$(( DEADLINE - $(now_ms) ))
  if [ "$left" -le 0 ]; then DEAD=1; NOTRUN=$(printf ', `%s`' "${CMDS[@]:$i}"); break; fi
  (cd "$WT" && timeout -k 2 "$(printf '%d.%03d' $((left / 1000)) $((left % 1000)))" bash -c "$cmd" </dev/null >"$OUTF" 2>&1); rc=$?
  case $rc in
    0) ;;
    124|137) DEAD=1 CUT=$cmd; [ $((i + 1)) -ge ${#CMDS[@]} ] || NOTRUN=$(printf ', `%s`' "${CMDS[@]:$((i + 1))}"); break ;;
    126|127) CNR=1; MSG="$MSG
could not run: \`$cmd\` (exit $rc: the command is missing or not executable)
$(tailed)" ;;
    *) MSG="$MSG
failed: \`$cmd\` (exit $rc)
$(tailed)" ;;
  esac
done
rm -f "$OUTF"
if [ -n "$DEAD" ]; then
  MSG="$MSG
deadline fired: the \`seconds: $SECS\` budget of .claude/stop-checks ran out${CUT:+ while running \`$CUT\`}${NOTRUN:+; not run:${NOTRUN#,}}."
fi

if [ -z "$MSG" ]; then
  printf '%s %s 0\n' "$TREE" "$CKS" > "$STATE" 2>/dev/null; rm -f "$STATE.msg"
  exit 0
fi
MSG="BLOCKED: .claude/stop-checks held this turn.$MSG
Fix what it names and end the turn again; a command can be run on its own with \`bash -c '<command>'\` in this worktree."
printf '%s %s 2\n' "$TREE" "$CKS" > "$STATE" 2>/dev/null
printf '%s\n' "$MSG" > "$STATE.msg" 2>/dev/null
if [ -n "$DEAD" ]; then HOOK_FIRE_REASON=checks-deadline
elif [ -n "$CNR" ]; then HOOK_FIRE_REASON=checks-could-not-run
else HOOK_FIRE_REASON=checks-failed; fi
printf '%s\n' "$MSG" >&2
exit 2
