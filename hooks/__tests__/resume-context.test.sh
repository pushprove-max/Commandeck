#!/usr/bin/env bash
# Self-test for resume-context.sh and the marker context-clear-stop.sh leaves.
#
# A resumed main spent about six turns fetching the board, the run binding and
# the checkpoint by hand, and typing them into the resume prompt fails past
# ~9 KB. So the stop hook leaves a marker and a main-only SessionStart
# hook injects all three, ONCE: a second session must not replay an old
# checkpoint, and a worker in a linked worktree must never see main's state.
# It also carries the owner's last prompts verbatim and records which checkpoint the
# session resumed from, so its own next restart cannot drop that work.
set -u
while read -r v; do unset "$v"; done < <(compgen -e | grep -E '^(ORCA|COMMANDECK)_')

ROOT=$(git rev-parse --show-toplevel)
HOOK="$ROOT/hooks/resume-context.sh"
STOP="$ROOT/hooks/context-clear-stop.sh"
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
has() { grep -qF -- "$1" <<<"$2" && echo 1 || echo 0; }

BOX=$(mktemp -d); trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/bin" "$BOX/home/.claude/checkpoints" "$BOX/home/.config/orca" "$BOX/home/.claude/projects/proj"
# The machine-wide file names another project's run: each project reads its own.
echo run_foreign > "$BOX/home/.config/orca/current-run"
cat > "$BOX/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
[ "${RUNUSE_FAIL:-0}" = 1 ] && { echo '{"ok":false,"error":{"code":"run_not_found"}}'; exit 1; }
echo '{"ok":true}'
STUB
cat > "$BOX/board" <<'STUB'
#!/usr/bin/env bash
echo "RUN=run_test01  BOARD-MARK"
STUB
chmod +x "$BOX/bin/orca-ide" "$BOX/board"
git init -q "$BOX/main" && git -C "$BOX/main" commit -q --allow-empty -m init
PSLUG=$(printf '%s' "$(git -C "$BOX/main" rev-parse --show-toplevel)" | tr -c 'A-Za-z0-9' '-')  # the marker is per repo
mkdir -p "$BOX/home/.commandeck/scratch/$PSLUG" && echo run_test01 > "$BOX/home/.commandeck/scratch/$PSLUG/current-run"
git -C "$BOX/main" worktree add -q "$BOX/wt" -b w
CPD=$BOX/home/.claude/checkpoints
PROJ=$BOX/home/.claude/projects/proj
CP=$CPD/sid1.md
MARK=$CPD/resume-pending.$PSLUG
printf '# Checkpoint sid1\n\nCHECKPOINT-MARK next: arm the waiter\n\n## Queue (in order)\n- CARRY-ITEM merge alpha after its review\n' > "$CP"

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$3" > "%s/helper-cmd"\n' "$BOX" > "$BOX/helper"; chmod +x "$BOX/helper"
hook() { # cwd [new session id] [SessionStart payload; default a real one naming that id]
  local sid=${2:-sidnew} payload
  payload=${3-$(printf '{"session_id":"%s","transcript_path":"%s/%s.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$sid" "$PROJ" "$sid" "$1")}
  # The replacement main is started with the marker's token; TOKEN= names another session's.
  (cd "$1" && printf '%s' "$payload" | PATH="$BOX/bin:$PATH" HOME=$BOX/home CALLS=$BOX/calls ORCA_TERMINAL_HANDLE=term_new \
    COMMANDECK_RESUME_TOKEN="${TOKEN-$(sed -n 2p "$MARK" 2>/dev/null)}" COMMANDECK_BOARD_CMD="bash $BOX/board" bash "$HOOK" 2>&1)
}
stop_for() { # session id, clear line -> the stop hook's stdout
  (cd "$BOX/main" && printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":false}' "$1" "$BOX/t.jsonl" \
    | PATH="$BOX/bin:$PATH" HOME=$BOX/home ORCA_TERMINAL_HANDLE=term_old COMMANDECK_CLEAR_LINE=$2 \
      COMMANDECK_RESTART_HELPER=/bin/true bash "$STOP" 2>/dev/null)
}

# 1. The stop hook past the line with a fresh checkpoint leaves the marker
#    naming that checkpoint. The restart helper is stubbed out.
printf '%s\n' '{"message":{"usage":{"cache_read_input_tokens":500,"input_tokens":1}}}' > "$BOX/t.jsonl"
(cd "$BOX/main" && printf '{"session_id":"sid1","transcript_path":"%s","stop_hook_active":false}' "$BOX/t.jsonl" \
  | PATH="$BOX/bin:$PATH" HOME=$BOX/home ORCA_TERMINAL_HANDLE=term_old COMMANDECK_CLEAR_LINE=10 \
    COMMANDECK_RESTART_HELPER="$BOX/helper" bash "$STOP" >/dev/null 2>&1)
check "the stop hook leaves a marker naming the checkpoint" "$CP" "$(head -1 "$MARK" 2>/dev/null)"
# The marker carries a one-time token and the replacement is started with it:
# the checkout alone does not say which new main session the checkpoint is for.
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BOX/helper-cmd" ] && break; sleep 0.5; done
TOK=$(sed -n 2p "$MARK" 2>/dev/null)
check "the marker carries a token and the replacement's command carries the same one" "1 1" \
  "$([ -n "$TOK" ] && echo 1 || echo 0) $(grep -c "^COMMANDECK_RESUME_TOKEN=$TOK claude" "$BOX/helper-cmd" 2>/dev/null)"
OUT=$(TOKEN=someone-else hook "$BOX/main" sidrace)
check "another main session started first in this checkout gets nothing" "" "$OUT"
check "and leaves the marker for the replacement" 1 "$([ -f "$MARK" ] && echo 1 || echo 0)"
OUT=$(TOKEN= hook "$BOX/main" sidrace2)
check "nor does a main session started with no token" " 1" "$OUT $([ -f "$MARK" ] && echo 1 || echo 0)"

# 2. A linked worktree (a worker) gets nothing and leaves the marker for main.
OUT=$(hook "$BOX/wt" sidwk)
check "a worker session injects nothing" "" "$OUT"
check "and does not consume main's marker" 1 "$([ -f "$MARK" ] && echo 1 || echo 0)"
check "and records no ancestry" 0 "$([ -e "$CPD/sidwk.resumed-from" ] && echo 1 || echo 0)"

# 2b. A reviewer in the main checkout is not main either.
OUT=$(COMMANDECK_REVIEWER=1 hook "$BOX/main" sidrv)
check "a reviewer session injects nothing" "" "$OUT"
check "and does not consume main's marker" 1 "$([ -f "$MARK" ] && echo 1 || echo 0)"
check "and records no ancestry" 0 "$([ -e "$CPD/sidrv.resumed-from" ] && echo 1 || echo 0)"

# Main's voice instruction, written out here so weakening the source
# cannot weaken the expectation.
PERSONA="# Main persona: You are the main orchestrator, every turn, including resumed sessions; plain speech, no personality; facts, plain English and asks stay rigorous; worker/reviewer briefs stay plain."

# 3. Main injects the binding, the board and the checkpoint text.
: > "$BOX/calls"
OUT=$(hook "$BOX/main")
check "a resumed main starts with the persona" "$PERSONA" "$(head -1 <<<"$OUT")"
check "and gets it once" 1 "$(grep -cF "You are the main orchestrator" <<<"$OUT")"
check "main is bound to the run" 1 "$(has 'orchestration run-use --id run_test01' "$(cat "$BOX/calls")")"
check "the board output is injected" 1 "$(has BOARD-MARK "$OUT")"
check "the checkpoint text is injected" 1 "$(has CHECKPOINT-MARK "$OUT")"
check "the marker is consumed" 0 "$([ -f "$MARK" ] && echo 1 || echo 0)"
check "the new session records the exact checkpoint it resumed from" "$CP" "$(cat "$CPD/sidnew.resumed-from" 2>/dev/null)"
echo "injected bytes: ${#OUT}"

# 4. Once only: the next main session injects nothing.
OUT=$(hook "$BOX/main" sidlater)
check "a second session injects nothing" "" "$OUT"

# 4b. The consumed marker is gone, yet the resumed session's own restart is
#     still checked against the checkpoint it inherited, never against the
#     newest file in the directory: an unrelated, newer checkpoint is ignored.
printf '# Checkpoint zzz\n\n## Queue (in order)\nnone\n' > "$CPD/zzz.md"
printf '# Checkpoint sidnew\n\n## Queue (in order)\nnone\n' > "$CPD/sidnew.md"; touch "$CPD/zzz.md"
touch "$CPD/sidnew.handoff"
OUT=$(stop_for sidnew 999999999)
check "a restart that drops inherited work is blocked" block "$(jq -r '.decision // empty' <<<"$OUT" 2>/dev/null)"
check "and the block names the dropped item" 1 "$(has 'CARRY-ITEM merge alpha after its review' "$OUT")"
check "and the baseline it was checked against" 1 "$(has "$CP" "$OUT")"
check "and no restart is published" 0 "$([ -f "$MARK" ] && echo 1 || echo 0)"
printf '# Checkpoint sidnew\n\n## Queue (in order)\n- CARRY-ITEM merge alpha after its review (still waiting)\n' > "$CPD/sidnew.md"
OUT=$(stop_for sidnew 999999999)
check "carrying the item lets the restart through" "$CPD/sidnew.md" "$(head -1 "$MARK" 2>/dev/null)"
rm -f "$MARK" "$CPD/sidnew.handoff"

# 5. A marker older than the checkpoint window is dropped, not replayed.
echo "$CP" > "$MARK"; touch -d '-2 hours' "$MARK"
OUT=$(hook "$BOX/main" sid5)
check "a stale marker injects nothing" "" "$OUT"
check "and is removed" 0 "$([ -f "$MARK" ] && echo 1 || echo 0)"
check "and records no ancestry" 0 "$([ -e "$CPD/sid5.resumed-from" ] && echo 1 || echo 0)"

# 6. A checkpoint that fits the 10 KB resume budget arrives WHOLE: a cut drops
#    the open work at its end, which is exactly what the resumed main must not
#    lose. It outranks the owner's prompts, which get the room left, newest first
#    (resume-context-size.refute.test.sh covers the cuts).
python3 - "$PROJ/sid6old.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for i in range(3):
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": f"FILL{i} " + "y" * 1500}}) + "\n")
PY
{ printf '# Checkpoint sid6old\n\n'; head -c 6000 /dev/zero | tr '\0' x; printf '\nSENTINEL-PAST-6000\n'; } > "$CPD/sid6old.md"
echo "$CPD/sid6old.md" > "$MARK"
OUT=$(hook "$BOX/main" sid6)
check "a checkpoint past 6000 bytes arrives whole" 1 "$([[ $OUT == *"$(cat "$CPD/sid6old.md")"* ]] && echo 1 || echo 0)"
check "and is never cut" 0 "$(has 'checkpoint cut' "$OUT")"
check "the newest prompt fills the room left" 1 "$(has 'FIL''L2 yyy' "$OUT")"
check "and the oldest that does not fit is named as omitted" 0 "$(has 'FIL''L0 yyy' "$OUT")"
check "out loud" 1 "$(has 'over the resume budget' "$OUT")"

# 7. A binding Orca refused is never reported as done: main is told to bind by
#    hand, the board and checkpoint still arrive, and the marker stays so the
#    next main session retries. That retry binds and consumes the marker.
echo "CHECKPOINT-MARK" > "$CP"; echo "$CP" > "$MARK"
OUT=$(RUNUSE_FAIL=1 hook "$BOX/main" sid7)
check "a refused binding still starts with the persona" "$PERSONA" "$(head -1 <<<"$OUT")"
check "a refused binding says NOT BOUND with Orca's error" 1 "$(has 'NOT BOUND: run-use --id run_test01 failed: run_not_found' "$OUT")"
check "and tells main to bind by hand" 1 "$(has 'Run `orca-ide orchestration run-use --id run_test01` yourself' "$OUT")"
check "and never says the state was fetched" 0 "$(has 'do not fetch them again' "$OUT")"
check "and still injects the board" 1 "$(has BOARD-MARK "$OUT")"
check "and the checkpoint" 1 "$(has CHECKPOINT-MARK "$OUT")"
check "and keeps the marker for a retry" 1 "$([ -f "$MARK" ] && echo 1 || echo 0)"
check "and still records the session's ancestry" "$CP" "$(cat "$CPD/sid7.resumed-from" 2>/dev/null)"
OUT=$(hook "$BOX/main" sid7b)
check "the retry binds and says the state was fetched" 1 "$(has 'do not fetch them again' "$OUT")"
check "and consumes the marker" 0 "$([ -f "$MARK" ] && echo 1 || echo 0)"
check "and records its own ancestry" "$CP" "$(cat "$CPD/sid7b.resumed-from" 2>/dev/null)"

# 8. /handoff restarts main below the line: The owner kicks off a handoff before the
#    180K line, so the .handoff marker must stand in for the line, once.
stop2() { # line
  (cd "$BOX/main" && printf '{"session_id":"sid2","transcript_path":"%s","stop_hook_active":false}' "$BOX/t.jsonl" \
    | PATH="$BOX/bin:$PATH" HOME=$BOX/home ORCA_TERMINAL_HANDLE=term_old COMMANDECK_CLEAR_LINE=$1 \
      COMMANDECK_RESTART_HELPER=/bin/true bash "$STOP" >/dev/null 2>&1)
}
CP2=$BOX/home/.claude/checkpoints/sid2.md; echo "CHECKPOINT-2" > "$CP2"; rm -f "$MARK"
stop2 999999999
check "below the line with no /handoff, nothing restarts" 0 "$([ -f "$MARK" ] && echo 1 || echo 0)"
touch "$BOX/home/.claude/checkpoints/sid2.handoff"
stop2 999999999
check "below the line, /handoff restarts main from its checkpoint" "$CP2" "$(head -1 "$MARK" 2>/dev/null)"
# The restart helper consumes it once the new pane takes the prompt (context-clear-restart.test.sh).
check "and the /handoff request is left for the restart helper" 1 "$([ -f "$BOX/home/.claude/checkpoints/sid2.handoff" ] && echo 1 || echo 0)"
rm -f "$MARK"

# 9. The owner's last prompts arrive verbatim, oldest first: the resumed main acts on
#    what he actually asked, not on a summary of it. Only HIS prompts count;
#    tool results, hook output, reminders, notifications and nudges are rows
#    of the same type that he never typed.
python3 - "$PROJ/sidA.jsonl" "$BOX/genuine.json" <<'PY'
import json, sys
rows, genuine = [], []
def user(content, **kw):
    rows.append(dict(type="user", message=dict(role="user", content=content), **kw))
for i in range(1, 11):
    t = f"P{i:02d} plain prompt"
    if i == 4: t = "P04 line one\n  indented line two\n\nline four after a blank\n"
    if i == 6: t = "P06 café — naïve ✓ 日本\n\n"
    if i == 9: t = "P09 quoting the labels: <task-notification>, isMeta, <system-reminder>, Stop hook feedback: and You have 2 orchestration messages."
    genuine.append(t)
    if i == 5: user([{"type": "text", "text": t}, {"type": "image", "source": {"type": "base64", "data": ""}}])
    elif i == 7: user([{"type": "text", "text": "<system-reminder>SYNTH reminder block</system-reminder>"}, {"type": "text", "text": t}])
    # A background task's notice can arrive in the same row as what the owner typed next.
    elif i == 8: user("<task-notification>\n<task-id>t0</task-id>\nSYNTH</task-notification>\n" + t)
    else: user(t)
    rows.append(dict(type="assistant", message=dict(role="assistant", content=[{"type": "text", "text": "SYNTH assistant"}])))
    user([{"type": "tool_result", "tool_use_id": "x", "content": "SYNTH tool result"}])
    user("SYNTH meta row", isMeta=True)
    user("SYNTH compact summary", isCompactSummary=True)
    user("<task-notification>\n<task-id>t1</task-id>\nSYNTH</task-notification>")
    user("\nYou have 1 orchestration message. Run `orca orchestration check --run r` SYNTH")
    user("main-watch: items are waiting in your Orca inbox for run run_x SYNTH")
    user("main-watch: Orca did not take these for run run_x, so they are NOT in your inbox: refused. SYNTH")
    rows.append(dict(type="user", message="SYNTH damaged row"))
    user("<system-reminder>SYNTH reminder only</system-reminder>")
    user([{"type": "text", "text": "<system-reminder>SYNTH reminder only</system-reminder>"}])
    user("<user-prompt-submit-hook>SYNTH</user-prompt-submit-hook>")
    user("Stop hook feedback:\nSYNTH stop hook")
    user("resume from the checkpoint /x/sid0.md (its text, board.sh and the run-use binding are already in your SessionStart context; do not fetch them again, except a part its RESUMED line names as cut) SYNTH")
    rows.append(dict(type="system", content="SYNTH system"))
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
json.dump(genuine, open(sys.argv[2], "w", encoding="utf-8"))
PY
prompts() { # hook-output file, expected-prompts json, how many of its newest -> "ok" or what differs
  python3 - "$@" <<'PY'
import json, sys
out = open(sys.argv[1], encoding="utf-8").read()
exp = json.load(open(sys.argv[2], encoding="utf-8"))
exp = exp[len(exp) - int(sys.argv[3]):]
pos = -1
for i, t in enumerate(exp, 1):
    p = out.find(f"<<< prompt {i} of {len(exp)}\n{t}\n>>> end prompt {i}\n")
    if p <= pos:
        sys.exit(print(f"prompt {i} missing, changed or out of order: {t[:20]!r}"))
    pos = p
n = out.count("<<< prompt ")
print("ok" if n == len(exp) else f"{n} prompts emitted, expected {len(exp)}")
PY
}
resume_from() { # old session id, new session id -> the hook's output in $BOX/out
  [ -f "$CPD/$1.md" ] || printf '# Checkpoint %s\n\nCKPT-%s\n' "$1" "$1" > "$CPD/$1.md"
  echo "$CPD/$1.md" > "$MARK"
  hook "$BOX/main" "$2" > "$BOX/out"
}
resume_from sidA sid9
check "the newest 8 genuine prompts arrive verbatim, oldest first" ok "$(prompts "$BOX/out" "$BOX/genuine.json" 8)"
check "and no synthetic row leaks in" 0 "$(has SYNTH "$(cat "$BOX/out")")"
check "and the older ones are reported as omitted by the count" 1 "$(has 'OMITTED: 2 older prompts beyond the newest 8' "$(cat "$BOX/out")")"
check "the checkpoint still arrives with them" 1 "$(has CKPT-sidA "$(cat "$BOX/out")")"
COMMANDECK_HANDOFF_MESSAGE_COUNT=3 resume_from sidA sid9b
check "the count is set in one place" ok "$(prompts "$BOX/out" "$BOX/genuine.json" 3)"
COMMANDECK_HANDOFF_MESSAGE_COUNT=0 resume_from sidA sid9c
check "a count that is not a positive integer says so" 1 "$(has 'COMMANDECK_HANDOFF_MESSAGE_COUNT=0 is not a positive integer' "$(cat "$BOX/out")")"

# 10. The prompts get the UTF-8 bytes the 10 KB resume budget has left. They are
#     kept whole or left out whole, newest first, and every omission is said
#     out loud.
python3 - "$PROJ/sidB.jsonl" "$BOX/budget.json" "$PROJ/sidC.jsonl" <<'PY'
import json, sys
big = [f"B{i} " + "é" * 2400 for i in range(1, 4)]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.writelines(json.dumps({"type": "user", "message": {"role": "user", "content": t}}) + "\n" for t in big)
json.dump(big, open(sys.argv[2], "w", encoding="utf-8"))
with open(sys.argv[3], "w", encoding="utf-8") as f:
    for t in ["C1 small", "C2BIG " + "z" * 13000]:
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": t}}) + "\n")
PY
resume_from sidB sid10
check "prompts that fit the byte budget arrive whole" ok "$(prompts "$BOX/out" "$BOX/budget.json" 1)"
check "and the whole injection stays under 10240 bytes" 1 "$([ "$(wc -c < "$BOX/out")" -lt 10240 ] && echo 1 || echo 0)"
check "and the older ones are reported as omitted by the budget" 1 "$(has 'OMITTED: 2 older prompts over the resume budget' "$(cat "$BOX/out")")"
resume_from sidC sid10b
check "a newest prompt over the budget is never cut" 0 "$(has C2BIG "$(cat "$BOX/out")")"
check "and nothing older is shown in its place" 0 "$(has '<<< prompt' "$(cat "$BOX/out")")"
check "and one pointer names its size and the transcript" 11 "$(has "left out whole to fit the resume budget (newest is 13006 bytes" "$(cat "$BOX/out")")$(has "read them in $PROJ/sidC.jsonl" "$(cat "$BOX/out")")"

# 11. A missing or damaged transcript is a visible warning, never a lost checkpoint.
resume_from sidGhost sid11
check "a missing transcript warns" 1 "$(has "WARNING: cannot read the transcript $PROJ/sidGhost.jsonl" "$(cat "$BOX/out")")"
check "and the checkpoint still arrives" 1 "$(has CKPT-sidGhost "$(cat "$BOX/out")")"
{ echo 'not json {'; echo '{"type":"user","message":"not an object"}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"D1 after the bad line"}}'; } > "$PROJ/sidD.jsonl"
resume_from sidD sid11b
check "malformed transcript lines and rows warn" 1 "$(has 'WARNING: 2 malformed transcript lines skipped' "$(cat "$BOX/out")")"
check "and the readable prompts still arrive" 1 "$(has 'D1 after the bad line' "$(cat "$BOX/out")")"

# 12. A session already resumed from one checkpoint never silently swaps it for
#     another: its restart would be checked against the wrong work.
echo "$CPD/other.md" > "$CPD/sid12.resumed-from"
resume_from sidA sid12
check "conflicting ancestry fails resume setup visibly" 1 "$(has 'RESUME SETUP FAILED' "$(cat "$BOX/out")")"
check "and keeps the recorded ancestry" "$CPD/other.md" "$(cat "$CPD/sid12.resumed-from")"
check "and keeps the marker" 1 "$([ -f "$MARK" ] && echo 1 || echo 0)"
rm -f "$MARK"

# 13. Without a session id there is nowhere to record ancestry: fail visibly
#     and leave the marker for a session that has one.
echo "$CP" > "$MARK"
OUT=$(hook "$BOX/main" x '{}')
check "a SessionStart with no session id fails resume setup visibly" 1 "$(has 'RESUME SETUP FAILED' "$OUT")"
check "and the persona precedes the setup diagnostic" "$PERSONA" "$(head -1 <<<"$OUT")"
check "and keeps the marker" 1 "$([ -f "$MARK" ] && echo 1 || echo 0)"
rm -f "$MARK"

# 14. The resumed checklist: a resumed main rebuilt EVERY item, done ones too,
#     one TaskCreate per turn, and then spent a turn per status update.
#     Both binding outcomes carry one rule, and the checkpoint template and
#     main's own rules say the same: only `[ ]` and `[>]` are recreated, all in
#     one reply, and updates ride along with the work. Written out here so
#     weakening the source cannot weaken the expectation.
TODO_RULE='TODO LIST: recreate only the unfinished items, `[ ]` next and `[>]` in progress (status in_progress), every TaskCreate in ONE reply; `[x]` items stay done in this checkpoint and are not recreated. Later updates ride in the same reply as the work they record.'
printf '# Checkpoint todo\n\n## Todo list\n- [x] TODO-DONE merged alpha\n- [>] TODO-DOING review beta\n- [ ] TODO-NEXT deploy gamma\n' > "$CP"
echo "$CP" > "$MARK"
OUT=$(RUNUSE_FAIL=1 hook "$BOX/main" sid14)
check "an unbound resume carries the unfinished-only rebuild rule" 1 "$(has "$TODO_RULE" "$OUT")"
check "and the mixed list it applies to" 1 "$(has '- [>] TODO-DOING review beta' "$OUT")"
OUT=$(hook "$BOX/main" sid14b)
check "a bound resume carries the same rule" 1 "$(has "$TODO_RULE" "$OUT")"
check "the checkpoint template states the rule" 1 "$(has "$TODO_RULE" "$(cat "$ROOT/templates/checkpoint.md")")"
check "main's rules require updates to share the working reply" 1 \
  "$(has 'in the same reply as the work it records' "$(cat "$ROOT/templates/main-session.md")")"
check "main's rules drain the inbox only on a wake" 1 \
  "$(has 'Drain the Orca inbox only on a wake' "$(cat "$ROOT/templates/main-session.md")")"
check "main's rules name the two re-ask exceptions" 1 \
  "$(has '--reask' "$(cat "$ROOT/templates/main-session.md")")"

# Two projects on one machine share ~/.claude/checkpoints. A marker another
# project's main left is not this one's to take: taking it handed that
# checkpoint to the wrong session and left the right one with nothing.
rm -f "$CPD"/resume-pending.*
printf '%s\n' "$CP" > "$CPD/resume-pending.-some-other-repo"; printf '%s\n' "$CP" > "$CPD/resume-pending"
OUT=$(hook "$BOX/main" sidother)
check "another repo's pending resume injects nothing here" "" "$OUT"
check "and both foreign markers are left in place" 2 "$(ls "$CPD/resume-pending.-some-other-repo" "$CPD/resume-pending" 2>/dev/null | wc -l | tr -d ' ')"

# A board that does not finish inside the cap says so. The lines it did
# print are a partial board, and main must not read them as the whole one.
printf '#!/usr/bin/env bash\necho "RUN=run_test01  BOARD-PARTIAL"\nsleep 5\necho BOARD-LATE\n' > "$BOX/board"
echo "CHECKPOINT-MARK" > "$CP"; echo "$CP" > "$MARK"
OUT=$(COMMANDECK_BOARD_TIMEOUT=1 hook "$BOX/main" sidslow)
check "a board cut off at the cap is named as timed out" 1 "$(has 'board.sh timed out after 1 s' "$OUT")"
check "and keeps the lines it printed in time, and none after" "1 0" "$(has BOARD-PARTIAL "$OUT") $(has BOARD-LATE "$OUT")"
check "and still injects the binding and the checkpoint" "1 1" "$(has 'run-use --id run_test01: bound' "$OUT") $(has CHECKPOINT-MARK "$OUT")"

# Two projects on one machine share ~/.claude/checkpoints. A marker another
# project's main left is not this one's to take: taking it handed that
# checkpoint to the wrong session and left the right one with nothing.
rm -f "$CPD"/resume-pending.*
printf '%s\n' "$CP" > "$CPD/resume-pending.-some-other-repo"; printf '%s\n' "$CP" > "$CPD/resume-pending"
OUT=$(hook "$BOX/main" sidother)
check "another repo's pending resume injects nothing here" "" "$OUT"
check "and both foreign markers are left in place" 2 "$(ls "$CPD/resume-pending.-some-other-repo" "$CPD/resume-pending" 2>/dev/null | wc -l | tr -d ' ')"

echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
