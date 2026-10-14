#!/usr/bin/env bash
# doctor.sh is what an owner runs when something seems off, so its common path
# must be right: a fresh setup reads clean, and each way Codex's one notify
# command can miss the plugin is named with its own line and the fix. Codex
# takes a single notify command, so an owner with another notify tool runs a
# wrapper that calls both; a wrapper that kept an old version's path went on
# calling a stale hook through several updates. The full doctor runs once (its
# common path); each notify case calls the check it prints, so this runs in seconds.
set -uo pipefail
. "$(dirname "$0")/install-fixture.sh"
CFG=$HOME/.codex/config.toml LINK=$HOME/.commandeck/plugin/hooks/codex-notify.sh
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup succeeds" 0 $?
# A message queued for main while it is down is main's to read: the doctor's own startup measure must not take it.
QD=$(cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH bash -c '. "$0" && echo "$PP_SCRATCH/queue"' "$PLUGIN/scripts/paths.sh")
mkdir -p "$QD" && echo '{"at":"x","type":"status","subject":"answer","body":"stop this build"}' > "$QD/main.jsonl"
# An open decision is the owner's to answer: the prompt the doctor's startup measure sends must not close it.
(cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR PATH="$BIN:$PATH" bash "$PLUGIN/scripts/decision.sh" add doctor-test 'May this build ship?' no chat >/dev/null 2>&1)
run "$PROJ" doctor.sh >"$T/doc" 2>&1; check "a fresh setup has no FAIL line" 0 "$(grep -c '^FAIL' "$T/doc")"
check "the doctor leaves the owner's open decision open" null \
  "$(cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR PATH="$BIN:$PATH" bash "$PLUGIN/scripts/decision.sh" list 2>/dev/null | jq '.[] | select(.id == "doctor-test") | .answeredAt')"
check "the doctor leaves main's queued messages where they are" 1 "$(grep -c 'stop this build' "$QD/main.jsonl" 2>/dev/null)"
check "the direct notify line passes, and says which case" 1 "$(grep -c "^ok   codex notify: the line calls this plugin's hook" "$T/doc")"
check "setup keeps a stable link to the plugin" "$PLUGIN" "$(readlink "$HOME/.commandeck/plugin")"

# notify <script body> -- Codex's notify is the owner's wrapper with this body; the doctor's notify line.
notify() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$T/wrap.sh"; chmod +x "$T/wrap.sh"
  { printf 'notify = ["bash", "%s"]\n' "$T/wrap.sh"; grep -v '^notify = ' "$CFG"; } > "$T/cfg" && mv "$T/cfg" "$CFG"
  report
}
# report -- the notify check doctor.sh prints, called by itself ("ok ..." or "warn ...").
report() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux \
  bash -c '. "$0/paths.sh" && . "$0/install-lib.sh" && il_notify_report' "$PLUGIN/scripts" 2>&1); }
check "a wrapper calling the current hook passes" 1 "$(notify "/opt/tracker \"\$@\"; \"$PLUGIN/hooks/codex-notify.sh\" \"\$@\"" | grep -c "^ok codex notify: through the wrapper $T/wrap.sh")"
check "a wrapper calling it by the stable link passes" 1 "$(notify "\"$LINK\" \"\$@\"" | grep -c '^ok codex notify: through the wrapper')"
OUT=$(notify '/opt/tracker "$@"')
check "a wrapper with no hook in it warns so, with the line to add" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh does not call the plugin's hook.*add this line to it: \"$LINK\" \"\$@\"" <<<"$OUT")"
OLD=$HOME/.claude/plugins/cache/commandeck/commandeck/0.1.0/hooks/codex-notify.sh
mkdir -p "${OLD%/*}" && touch "$OLD"
OUT=$(notify "\"$OLD\" \"\$@\"")
check "a wrapper calling an older version warns so, naming it and the fix" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh calls an older plugin's hook ($OLD).*update.sh, which points it at $LINK" <<<"$OUT")"

OUT=$(notify "# \"$LINK\" \"\$@\"
exit 0")
check "a hook named only in a comment is no call: it warns" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh does not call the plugin's hook" <<<"$OUT")"
OUT=$(notify "exit 0 # \"$LINK\" \"\$@\"")
check "a hook named only in an inline comment is no call: it warns" 1 "$(grep -c "^warn codex notify: the wrapper $T/wrap.sh does not call the plugin's hook" <<<"$OUT")"
check "a wrapper that names the hook is reported as read, not run" 1 "$(notify "\"$LINK\" \"\$@\"" | grep -c 'read as text, not run')"
SP="$HOME/My Plugins/0.1.0/hooks/codex-notify.sh"; mkdir -p "${SP%/*}" && touch "$SP"
OUT=$(notify "\"$SP\" \"\$@\"")
check "an older hook at a quoted path with a space is named whole" 1 "$(grep -cF "calls an older plugin's hook ($SP)" <<<"$OUT")"
(cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux \
  bash -c '. "$0/paths.sh" && . "$0/install-lib.sh" && il_notify_repoint "$1" yes' "$PLUGIN/scripts" "$T/repoint-mf.json" >/dev/null 2>&1)
check "and a yes replaces it whole" "\"$LINK\" \"\$@\"" "$(sed -n 2p "$T/wrap.sh")"
notify "\"$OLD\" \"\$@\"" >/dev/null

# --- the wrapper is the owner's file: setup asks before it changes it, and changes it only on yes ---
WAS=$(cat "$T/wrap.sh")
run "$PROJ" setup.sh "${ANSWERS[@]}" >"$T/out" 2>&1; check "setup with no answer about the wrapper succeeds" 0 $?
check "it leaves the wrapper as it was" "$WAS" "$(cat "$T/wrap.sh")"
check "and asks, showing the old line and the new one" 1 "$(grep -cF "codex notify: ASK: the wrapper $T/wrap.sh calls an older plugin's hook. Old line: \"$OLD\" \"\$@\" New line: \"$LINK\" \"\$@\" Change it: --notify-wrapper yes; leave it: --notify-wrapper no" "$T/out")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --notify-wrapper no >"$T/out" 2>&1; check "a no succeeds" 0 $?
check "a no leaves the wrapper as it was" "$WAS" "$(cat "$T/wrap.sh")"
check "and says what the doctor will warn" 1 "$(grep -c "^codex notify: the wrapper $T/wrap.sh was left as it is; the doctor will warn: codex notify: the wrapper .* calls an older plugin's hook" "$T/out")"
run "$PROJ" setup.sh "${ANSWERS[@]}" --notify-wrapper yes >"$T/out" 2>&1; check "a yes succeeds" 0 $?
check "a yes points the wrapper at the stable link, and says so" "1:0:1" "$(grep -c "\"$LINK\" \"\$@\"" "$T/wrap.sh"):$(grep -c '0\.1\.0' "$T/wrap.sh"):$(grep -c "^codex notify: $T/wrap.sh now calls $LINK" "$T/out")"
check "and leaves the owner's notify line as it was" 1 "$(grep -c "^notify = \[\"bash\", \"$T/wrap.sh\"\]$" "$CFG")"
check "the doctor then passes it" 1 "$(report | grep -c '^ok codex notify: through the wrapper')"

# --- uninstall removes the link and says so; the wrapper stays the owner's to edit ---
WAS=$(cat "$T/wrap.sh")
run "$PROJ" uninstall.sh >"$T/out" 2>&1; check "uninstall succeeds" 0 $?
check "the link is gone" no "$([ -e "$HOME/.commandeck/plugin" ] || [ -L "$HOME/.commandeck/plugin" ] && echo yes || echo no)"
check "the wrapper is not edited" "$WAS" "$(cat "$T/wrap.sh")"
check "uninstall names the wrapper and the line to take out" 1 "$(grep -cxF "codex notify: the wrapper $T/wrap.sh still calls $LINK, which uninstall has removed; take this line out of it: \"$LINK\" \"\$@\"" "$T/out")"

grep -v '^notify = ' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"
check "no notify line at all warns so, with the line to add" 1 "$(report | grep -c "^warn codex notify: .* has no notify line.*notify = \[\"$LINK\"\]")"

[ "$FAIL" = 0 ] || { echo "--- doctor"; cat "$T/doc"; }
done_tests
