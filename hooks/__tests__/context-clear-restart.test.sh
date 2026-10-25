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
  "terminal create") panes term_old term_new; echo '{"ok":true,"result":{"terminal":{"handle":"term_new"}}}' ;;
  "terminal close") echo "close \$4 while main=\$(tail -1 "$T/scratch/handles/main")" >> "$T/calls.log"; [ "\$4" != term_old ] || panes term_new; echo '{"ok":true}' ;;
  "terminal send") [ ! -e "$T/refuse-send" ] || { echo '{"ok":false,"error":"refused"}'; exit 0; }; echo '{"ok":true}' ;;
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
touch "$T/refuse-send"; echo term_old > "$T/scratch/handles/main"; echo "checkpoint two" > "$T/cp2.md"
jq -n --arg p "$T/p" '{result: {terminals: [{handle: "term_old", worktreePath: $p, agentIdentity: "claude"}]}}' > "$T/list.json"
(cd "$T/p" && "${E[@]}" bash "$REAL/hooks/lib/context-clear-restart.sh" term_old "$T/cp2.md" true "$T/restart2.log" >/dev/null 2>&1)
check "the unprompted replacement's close writes one too" "term_new|restart: unprompted new|ok" \
  "$(awk -F'\t' '$4 == "restart: unprompted new" {print $2 "|" $4 "|" $5}' "$T/scratch/pane-closes.log")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
