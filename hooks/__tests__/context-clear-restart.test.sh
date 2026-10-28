#!/usr/bin/env bash
# After a main handoff the name `main` must follow the new pane at once: the helper opens the new pane, types
# the resume prompt, and closes the old one. Until the new session's own start recorded its handle, a send
# (a Builder's question) went to the closed pane and was lost. Pinned: handles/main ends with the new handle
# before the old pane's close call, and a send right after the close reaches the new pane.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ws" "$T/scratch/handles"
git init -q -b main "$T/p" && git -C "$T/p" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
git -C "$T/p" remote add origin https://example.invalid/o/r.git
printf '#!/bin/sh\necho ok\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
# Orca: create opens term_new beside term_old in main's checkout; a close of term_old logs what handles/main held
# at that moment, then removes the pane.
cat > "$T/bin/orca-ide" <<EOF
#!/usr/bin/env bash
panes() { jq -n --arg p "$T/p" '{result: {terminals: [\$ARGS.positional[] | {handle: ., worktreePath: \$p, agentIdentity: "claude"}]}}' --args "\$@" > "$T/list.json"; }
case "\$1 \$2" in
  "terminal list") cat "$T/list.json" ;;
  "terminal create") n=\$(( \$(cat "$T/creates.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$T/creates.n"
    h=term_new; [ "\$n" = 1 ] || h=term_new\$n
    while [ \$# -gt 0 ]; do [ "\$1" != --command ] || printf '%s\n' "\$2" >> "$T/create-commands"; shift; done
    [ ! -e "$T/no-relaunch" ] || [ "\$n" = 1 ] || { echo '{"ok":false}'; exit 0; }
    # The relaunched pane's SessionStart (resume-context.sh) writes the receipt; deliver holds the token it names.
    [ "\$n" = 1 ] || [ ! -e "$T/deliver" ] || printf '%s\nsid2\n' "\$(cat "$T/deliver")" > "\$(cat "$T/cur-cp").delivered"
    panes term_old \$h; echo "{\"ok\":true,\"result\":{\"terminal\":{\"handle\":\"\$h\"}}}" ;;
  "terminal close") echo "close \$4 while main=\$(tail -1 "$T/scratch/handles/main")" >> "$T/calls.log"
    # refuse-close: Orca refuses to close any replacement pane (the old main still closes).
    [ ! -e "$T/refuse-close" ] || [ "\$4" = term_old ] || { echo '{"ok":false}'; exit 0; }
    [ "\$4" != term_old ] || panes term_new; echo '{"ok":true}' ;;
  "terminal send") [ ! -e "$T/refuse-send" ] || { echo '{"ok":false,"error":"refused"}'; exit 0; }
    # A paired phone holding a pane: Orca answers ok:true, accepted:false, and types nothing.
    [ ! -e "$T/phone" ] || { echo '{"ok":true,"result":{"accepted":false,"bytesWritten":0}}'; exit 0; }; echo '{"ok":true}' ;;
  "orchestration send") while [ \$# -gt 0 ]; do [ "\$1" != --to ] || echo "\$2" >> "$T/sent-to"; shift; done; echo '{"ok":true}' ;;
  *) echo '{"ok":true}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
E=(env -u CLAUDE_PROJECT_DIR COMMANDECK_MAIN="$T/p" COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_SCRATCH="$T/scratch" COMMANDECK_RESTART_SETTLE_S=0 COMMANDECK_RESTART_TUI_FALLBACK_S=0 PATH="$T/bin:$PATH")
echo term_old > "$T/scratch/handles/main"
jq -n --arg p "$T/p" '{result: {terminals: [{handle: "term_old", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
echo "checkpoint" > "$T/cp.md"
(cd "$T/p" && "${E[@]}" bash "$REAL/hooks/lib/context-clear-restart.sh" term_old "$T/cp.md" true "$T/restart.log" >/dev/null 2>&1)
check "send after handoff reaches the new pane: handles/main ends with term_new before the close call on the old pane" "close term_old while main=term_new" "$(grep '^close term_old' "$T/calls.log")"
(cd "$T/p" && "${E[@]}" bash "$REAL/scripts/to-main.sh" question q body >/dev/null 2>&1)
check "a to-main.sh send right after the close goes to term_new" "term_new" "$(cat "$T/sent-to" 2>/dev/null)"
check "the older handle is kept in the record, the new one last" "term_old term_new" "$(paste -sd' ' "$T/scratch/handles/main")"

# Every close goes through pp_pane_close, so each one is logged with its cause (host issue 3009): the old main after
# a restart, and a replacement that refused the resume prompt.
check "the old main's close writes a pane-closes.log line with its cause" "term_old|restart: old main|ok" \
  "$(awk -F'\t' '$2 == "term_old" {print $2 "|" $4 "|" $5}' "$T/scratch/pane-closes.log")"
touch "$T/refuse-send"; rm -f "$T/creates.n"; echo term_old > "$T/scratch/handles/main"; echo "checkpoint two" > "$T/cp2.md"
jq -n --arg p "$T/p" '{result: {terminals: [{handle: "term_old", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
(cd "$T/p" && "${E[@]}" bash "$REAL/hooks/lib/context-clear-restart.sh" term_old "$T/cp2.md" true "$T/restart2.log" >/dev/null 2>&1)
check "the unprompted replacement's close writes one too" "term_new|restart: unprompted new|ok" \
  "$(awk -F'\t' '$4 == "restart: unprompted new" {print $2 "|" $4 "|" $5}' "$T/scratch/pane-closes.log")"
rm -f "$T/refuse-send"

# Host fix 3a7cc613: while a paired phone holds a pane, Orca takes every typed send with ok:true, accepted:false and
# types nothing. The helper read that as resumed and closed the OLD main, leaving a new one that never got its prompt.
# Now the unprompted pane closes, a second pane opens with the prompt in its launch command, and the old main closes
# only once that pane's SessionStart wrote the receipt naming the marker's token; else the helper gives up for good.
MARK=$T/resume-pending.$(printf '%s' "$T/p" | tr -c 'A-Za-z0-9' '-')
relaunch() { # <case> -- one restart of term_old under the phone refusal; the marker carries token tok1
  rm -f "$T/creates.n" "$T/create-commands" "$T/calls.log" "$T/scratch/pane-closes.log"
  echo term_old > "$T/scratch/handles/main"; echo "checkpoint $1" > "$T/$1.md"; echo "$T/$1.md" > "$T/cur-cp"
  printf '%s\ntok1\n' "$T/$1.md" > "$MARK"
  jq -n --arg p "$T/p" '{result: {terminals: [{handle: "term_old", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
  (cd "$T/p" && timeout 20 "${E[@]}" COMMANDECK_RESTART_ADOPT_EVERY_S=0 bash "$REAL/hooks/lib/context-clear-restart.sh" term_old "$T/$1.md" "COMMANDECK_RESUME_TOKEN=tok1 claude" "$T/$1.log" >/dev/null 2>&1)
}
closes() { awk -F'\t' '{print $2 "=" $4}' "$T/scratch/pane-closes.log" 2>/dev/null | paste -sd, -; }
touch "$T/phone"; echo tok1 > "$T/deliver"
relaunch ok
check "accepted:false: the unprompted pane closes, then the old main once the relaunch delivered" \
  "term_new=restart: unprompted new,term_old=restart: old main" "$(closes)"
check "the relaunch's command carries the resume prompt, single-quoted, after the token" 1 \
  "$(sed -n 2p "$T/create-commands" | grep -c "^COMMANDECK_RESUME_TOKEN=tok1 claude 'resume from the checkpoint $T/ok.md ")"
check "the helper put the marker back whole for the relaunched pane, and main names that pane" "tok1 term_new2" \
  "$(sed -n 2p "$MARK") $(tail -1 "$T/scratch/handles/main")"
check "a delivered relaunch is no give-up" "no 0" "$([ -e "$T/ok.restart-failed" ] && echo yes || echo no) $(grep -c 'AUTO RESTART FAILED' "$T/ok.log")"
rm -f "$T/deliver"
relaunch none
check "no receipt: the relaunched pane closes and the old main stays" "term_new=restart: unprompted new,term_new2=restart: unprompted new" "$(closes)"
check "no receipt: the helper gives up once, with the mark and the one log line the dashboard reads" "yes 1" \
  "$([ -e "$T/none.restart-failed" ] && echo yes || echo no) $(grep -c "restart: AUTO RESTART FAILED for $T/none.md: " "$T/none.log")"
echo tok-other > "$T/deliver"
relaunch stale
check "a receipt naming another token is no proof: the old main stays and the helper gives up" "no yes" \
  "$(closes | grep -q 'term_old=' && echo yes || echo no) $([ -e "$T/stale.restart-failed" ] && echo yes || echo no)"
echo tok1 > "$T/deliver"; touch "$T/no-relaunch"
relaunch nopane
check "a relaunch that opens no pane gives up and leaves the old main" "no yes no" \
  "$(closes | grep -q 'term_old=' && echo yes || echo no) $([ -e "$T/nopane.restart-failed" ] && echo yes || echo no) $([ -e "$T/nopane.md.restarted" ] && echo yes || echo no)"
rm -f "$T/no-relaunch" "$T/phone"
# A plain refusal (ok:false) is not the phone's: it keeps the old retry path, no relaunch and no give-up.
touch "$T/refuse-send"
relaunch plain
check "an ok:false refusal opens no second pane and does not give up" "1 no" \
  "$(cat "$T/creates.n") $([ -e "$T/plain.restart-failed" ] && echo yes || echo no)"
# A replacement that got no prompt and whose close Orca refuses stays up as a second main, so no stop may retry (its
# .restarted stands, and the next stop says "already restarted"): the helper gives up, raising the owner's alert, and
# the old main stays. Both refusals: the plain one and the phone's (where the relaunch never runs).
touch "$T/refuse-close"
relaunch plainstuck
check "ok:false and the replacement's close refused: the helper gives up, the old main stays" "yes 1 no" \
  "$([ -e "$T/plainstuck.restart-failed" ] && echo yes || echo no) $(grep -c "AUTO RESTART FAILED for $T/plainstuck.md: " "$T/plainstuck.log") $(closes | grep -q 'term_old=' && echo yes || echo no)"
rm -f "$T/refuse-send"; touch "$T/phone"
relaunch phonestuck
check "accepted:false and both closes refused: the helper gives up, opens no second pane, the old main stays" "yes 1 1 no" \
  "$([ -e "$T/phonestuck.restart-failed" ] && echo yes || echo no) $(grep -c "AUTO RESTART FAILED for $T/phonestuck.md: " "$T/phonestuck.log") $(cat "$T/creates.n") $(closes | grep -q 'term_old=' && echo yes || echo no)"
rm -f "$T/refuse-close" "$T/phone"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
