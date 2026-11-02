#!/usr/bin/env bash
# Issue 573: a closing GO merges by itself (the gate, issue 254), so main is no longer told to merge by hand, and the
# owner's one push question (decision.sh push-ask, which only writes the question) appears by itself once a batch has
# landed: when a tick collects a landed merge it marks push-pending; a tick on which no unit passed the gate and no merge
# job lives asks once and clears the mark. A refused question never stops the tick, and nothing is ever pushed.
# Each check prints `ok <label>` or `FAIL <label> (why)` and the run goes on, so one break names its own check.
set -euo pipefail
. "$(dirname "$0")/fixtures/main-watch-merge-setup.sh"
M=$S/main-watch/push-pending; RC=0
verdict() { if [ -z "$2" ]; then echo "ok $1"; else echo "FAIL $1 ($2)" >&2; RC=1; fi; }
# push-ask is a stub that counts its calls; ask-refuse makes it refuse, as the real one does with nothing to push.
cat > "$REPO/scripts/decision.sh" <<EOS
#!/usr/bin/env bash
echo "\$*" >> "$F/ask-calls"
[ ! -e "$F/ask-refuse" ] || { echo "decision: nothing to push" >&2; exit 1; }
EOS
chmod +x "$REPO/scripts/decision.sh"; : > "$F/ask-calls"
asks() { grep -c . "$F/ask-calls" || true; }
rnd() { printf '## Sol\nReviewed: x\nPass: final\nTiming: a b\n\nVERDICT: GO\n' > "$T/ws/$1/.claude/briefs/$1-r3-reports.md"; }
N=5000; tick $N

# A closing GO is merged by main-watch: no decision row yet, and its report no longer tells main to merge by hand.
N=$((N + 1000)); unit one; rnd one; tick $N; tick $((N + 60)); said_done one; tick $((N + 120)); jobwait one
r=; grep -q 'one@' "$F/mq-calls" || r="not merged: $(cat "$F/mq-calls")"
[ ! -s "$REPO/.claude/metrics/decisions.jsonl" ] || r="a decision row was written before the landing was collected"
verdict "a closing GO is merged by main-watch with no decision row and no message asking main to merge" "$r"
r=; [ "$(posts 'main-watch: one pass 3: GO (final)')" = 1 ] || r="the final GO report was not posted once"
! grep 'main-watch: one pass 3' "$T/sends" | grep -q 'merge-unit-local.sh' || r="it told main to merge by hand: $(grep 'one pass 3' "$T/sends")"
verdict "a final GO report does not tell main to merge by hand" "$r"

# A landing with nothing else queued raises one push question, once.
r=; [ "$(asks)" = 0 ] || r="asked before any merge was collected"
tick $((N + 180)); [ "$(cat "$F/ask-calls")" = push-ask ] || r="${r:+$r; }did not ask once: [$(cat "$F/ask-calls")]"
[ ! -e "$M" ] || r="${r:+$r; }the mark outlived its question"
tick $((N + 240)); tick $((N + 300)); [ "$(asks)" = 1 ] || r="${r:+$r; }asked again ($(asks) asks)"
verdict "a landing with nothing else queued raises one push question" "$r"
gone one; : > "$F/ask-calls"

# A landing while another unit passed the gate this tick asks nothing; the question waits for that batch.
N=$((N + 1000)); unit x1; unit y1; tick $N; said_done x1; tick $((N + 60)); jobwait x1; said_done y1; tick $((N + 120))
r=; grep -q 'x1 merged into local main' "$D" || r="x1's landing was not collected"
[ "$(asks)" = 0 ] || r="${r:+$r; }asked ($(asks) asks)"
[ -e "$M" ] || r="${r:+$r; }the mark was dropped while another unit was queued"
verdict "a landing while another unit passed the gate this tick asks nothing" "$r"
sleep 0.5; jobwait y1; tick $((N + 180)); gone x1; gone y1; : > "$F/ask-calls"

# A landing while a merge job still runs asks nothing; the question comes once that job ends, landed or not.
N=$((N + 1000)); unit z1; tick $N; sleep 300 & LV=$!; echo "$LV" > "$S/main-watch/mergejob-live.pid"
said_done z1; tick $((N + 60)); jobwait z1; tick $((N + 120))
r=; grep -q 'z1 merged into local main' "$D" || r="z1's landing was not collected"
[ "$(asks)" = 0 ] || r="${r:+$r; }asked while the job ran ($(asks) asks)"
[ -e "$M" ] || r="${r:+$r; }the mark was dropped while a merge job still ran"
verdict "a landing while a merge job still runs asks nothing" "$r"
kill "$LV"; wait "$LV" 2>/dev/null || true; echo 1 > "$S/main-watch/mergejob-live.rc"
tick $((N + 180)); r=; [ "$(asks)" = 1 ] || r="asked $(asks) times, not once, by the time that merge ended"
[ ! -e "$M" ] || r="${r:+$r; }the mark outlived its question"
verdict "a landing held behind a live merge raises the push question once that merge ends, landed or not" "$r"
gone z1; : > "$F/ask-calls"

# A merge that did not land raises no push question and leaves no mark.
N=$((N + 1000)); unit bad; echo bad > "$F/mq-fail"; tick $N; said_done bad; tick $((N + 60)); jobwait bad; tick $((N + 120)); tick $((N + 180))
r=; [ "$(posts 'merge of bad did not land cleanly')" = 1 ] || r="the failed merge was not told to main"
[ "$(asks)" = 0 ] && [ ! -e "$M" ] || r="${r:+$r; }a question or a mark was raised ($(asks) asks)"
verdict "a merge that did not land raises no push question" "$r"
: > "$F/mq-fail"; gone bad

# A refused push question does not stop the tick: the landing is still told to main, and the mark is cleared.
N=$((N + 1000)); unit rf; touch "$F/ask-refuse"; tick $N; said_done rf; tick $((N + 60)); jobwait rf; tick $((N + 120))
r=; [ "$(asks)" = 1 ] || r="the refusing push-ask ran $(asks) times"
[ "$(posts 'main-watch: rf merged into local main')" = 1 ] || r="${r:+$r; }the landing was not posted"
[ ! -e "$M" ] || r="${r:+$r; }the mark stayed, so it would be asked every tick"
verdict "a refused push question does not stop the tick" "$r"
rm -f "$F/ask-refuse"; gone rf

# The push question never pushes: with the real decision.sh and a remote, a landing leaves one open push row and the
# remote untouched.
mkdir -p "$REPO/hooks/lib"; cp "$SOURCE/scripts/decision.sh" "$REPO/scripts/"; cp "$SOURCE/hooks/lib/project.sh" "$REPO/hooks/lib/"
git init -q --bare "$T/origin.git"; git -C "$REPO" checkout -q -b main 2>/dev/null || git -C "$REPO" checkout -q main
git -C "$REPO" remote add origin "$T/origin.git"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base; git -C "$REPO" push -q origin main
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m 'feat(np): landed'
R0=$(git -C "$T/origin.git" rev-parse main)
N=$((N + 1000)); unit np; tick $N; said_done np; tick $((N + 60)); jobwait np; tick $((N + 120))
r=; [ "$(jq -s '[.[] | select(.source == "decision.sh push-ask" and .answeredAt == null)] | length' "$REPO/.claude/metrics/decisions.jsonl")" = 1 ] \
  || r="no single open push row: $(cat "$REPO/.claude/metrics/decisions.jsonl")"
[ "$(git -C "$T/origin.git" rev-parse main)" = "$R0" ] || r="${r:+$r; }the remote moved"
verdict "the push question never pushes" "$r"
exit $RC
