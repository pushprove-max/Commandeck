#!/usr/bin/env bash
# doctor.sh is what an owner runs when something seems off: each way Codex's one notify command can miss the plugin
# is named with its own line and the fix, and its startup measure takes nothing of the owner's or main's. Codex
# takes a single notify command, so an owner with another notify tool runs a wrapper that calls both; a wrapper
# that kept an old version's path went on calling a stale hook through several updates. The wrapper is the owner's
# file: it changes only on a yes. Each case calls the check the doctor prints, or the repoint setup runs, on a
# hand-written config.toml (no setup or uninstall run), so this runs in seconds.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd -P)   # -P: as install-lib.sh's IL_ROOT, or a checkout under a link fails the first check
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PROJ=$T/proj BIN=$T/bin CFG=$T/home/.codex/config.toml LINK=$T/home/.commandeck/plugin/hooks/codex-notify.sh
mkdir -p "$HOME/.codex" "$HOME/.commandeck" "$BIN" && ln -s "$REAL" "$HOME/.commandeck/plugin"
git init -q -b main "$PROJ" && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
mkdir -p "$PROJ/.claude" && echo '{"version": 1, "profile": "claude-openai"}' > "$PROJ/.claude/commandeck.json"
printf '#!/usr/bin/env bash\necho "{\\"ok\\":true,\\"result\\":{}}"\n' > "$BIN/orca-ide"; chmod +x "$BIN/orca-ide"
printf 'notify = ["%s/hooks/codex-notify.sh"]\nmodel = "other"\n' "$REAL" > "$CFG"
in_proj() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH -u CODEX_HOME PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux "$@"); }
# lib <shell> [args] -- the shell runs with install-lib.sh loaded and the args as "$1"...
lib() { in_proj bash -c '. "$0/paths.sh" && . "$0/install-lib.sh" && c=$1 && shift && eval "$c"' "$REAL/scripts" "$@" 2>&1; }
# report -- the notify check doctor.sh prints, called by itself ("ok ..." or "warn ...").
report() { lib il_notify_report; }
check "the direct notify line passes, and says which case" 1 "$(report | grep -c "^ok codex notify: the line calls this plugin's hook$")"

# --- the doctor's startup measure takes nothing of the owner's or main's ---
# A message queued for main while it is down is main's to read; an open decision is the owner's to answer.
QD=$(in_proj bash -c '. "$0" && echo "$PP_SCRATCH/queue"' "$REAL/scripts/paths.sh")
mkdir -p "$QD" && echo '{"at":"x","type":"status","subject":"answer","body":"stop this build"}' > "$QD/main.jsonl"
in_proj bash "$REAL/scripts/decision.sh" add doctor-test 'May this build ship?' no chat >/dev/null 2>&1
in_proj bash "$REAL/scripts/startup-size.sh" >/dev/null 2>&1; in_proj bash "$REAL/scripts/startup-size.sh" --per-prompt >/dev/null 2>&1
check "the doctor's startup measure leaves the owner's open decision open" null \
  "$(in_proj bash "$REAL/scripts/decision.sh" list 2>/dev/null | jq '.[] | select(.id == "doctor-test") | .answeredAt')"
check "and main's queued messages where they are" 1 "$(grep -c 'stop this build' "$QD/main.jsonl" 2>/dev/null)"

# notify <script body> -- Codex's notify is the owner's wrapper with this body; the doctor's notify line.
notify() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$T/wrap.sh"; chmod +x "$T/wrap.sh"
  { printf 'notify = ["bash", "%s"]\n' "$T/wrap.sh"; grep -v '^notify = ' "$CFG"; } > "$T/cfg" && mv "$T/cfg" "$CFG"
  report
}
check "a wrapper calling the current hook passes" 1 "$(notify "/opt/tracker \"\$@\"; \"$REAL/hooks/codex-notify.sh\" \"\$@\"" | grep -c "^ok codex notify: through the wrapper $T/wrap.sh")"
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
lib 'il_notify_repoint "$1" yes' "$T/repoint-mf.json" >/dev/null
check "and a yes replaces it whole" "\"$LINK\" \"\$@\"" "$(sed -n 2p "$T/wrap.sh")"

# --- the wrapper is the owner's file: setup asks before it changes it, and changes it only on yes ---
notify "\"$OLD\" \"\$@\"" >/dev/null; WAS=$(cat "$T/wrap.sh")
OUT=$(lib 'il_notify_repoint "$1"' "$T/mf.json")
check "with no answer about the wrapper it is left as it was" "$WAS" "$(cat "$T/wrap.sh")"
check "and the question shows the old line and the new one" 1 "$(grep -cF "codex notify: ASK: the wrapper $T/wrap.sh calls an older plugin's hook. Old line: \"$OLD\" \"\$@\" New line: \"$LINK\" \"\$@\" Change it: --notify-wrapper yes; leave it: --notify-wrapper no" <<<"$OUT")"
OUT=$(lib 'il_notify_repoint "$1" no' "$T/mf.json")
check "a no leaves the wrapper as it was" "$WAS" "$(cat "$T/wrap.sh")"
check "and says what the doctor will warn" 1 "$(grep -c "^codex notify: the wrapper $T/wrap.sh was left as it is; the doctor will warn: codex notify: the wrapper .* calls an older plugin's hook" <<<"$OUT")"
OUT=$(lib 'il_notify_repoint "$1" yes' "$T/mf.json")
check "a yes points the wrapper at the stable link, and says so" "1:0:1" "$(grep -c "\"$LINK\" \"\$@\"" "$T/wrap.sh"):$(grep -c '0\.1\.0' "$T/wrap.sh"):$(grep -c "^codex notify: $T/wrap.sh now calls $LINK" <<<"$OUT")"
check "and leaves the owner's notify line as it was" 1 "$(grep -c "^notify = \[\"bash\", \"$T/wrap.sh\"\]$" "$CFG")"
check "the doctor then passes it" 1 "$(report | grep -c '^ok codex notify: through the wrapper')"
# Uninstall leaves the wrapper to its owner (uninstall.sh says which line to take out); the manifest keeps what it was.
check "the yes recorded the wrapper as it was, in the manifest it was given, its bytes kept" "$WAS" \
  "$(cat "$HOME/.commandeck/install/blobs/$(jq -r --arg w "$T/wrap.sh" '.entries[$w].prior | ltrimstr("sha256:")' "$T/mf.json" 2>/dev/null)" 2>/dev/null)"

grep -v '^notify = ' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"
check "no notify line at all warns so, with the line to add" 1 "$(report | grep -c "^warn codex notify: .* has no notify line.*notify = \[\"$LINK\"\]")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
