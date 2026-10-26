#!/usr/bin/env bash
# update.test.sh -- update.sh shows what setup's rerun says needs the owner. Setup puts a failed add-on install or
# update under "Needs you"; an update that dropped setup's output hid that failure and still said done (main ruling 2026-10-16).
# setup.sh and doctor.sh are stubs here, in a plugin folder of links to the real scripts (no setup run).
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home
PL=$T/plugin PROJ=$T/proj
mkdir -p "$PL/scripts" "$HOME" && ln -s "$REAL/.claude-plugin" "$REAL/CHANGELOG.md" "$PL/"
for f in "$REAL"/scripts/*; do case ${f##*/} in setup.sh|doctor.sh) ;; *) ln -s "$f" "$PL/scripts/"; esac; done
cat > "$PL/scripts/setup.sh" <<'EOF'
#!/usr/bin/env bash
echo "codex: updated 0.40.0 -> 0.41.0 (codex update)"
# Seen by another pane's repair or revoke, which opens the folder anew: the update holds it, and hands setup the fd.
( exec 8<"$HOME/.commandeck/install"; flock -n 8 ) && echo "lock: free" > "$HOME/lock-seen" || echo "lock: held, fd ${IL_PROFILE_LOCK_FD:+handed}" > "$HOME/lock-seen"
echo "Done:"
echo "add-on serena: installed at its latest"
echo
echo "Needs you:"
echo "  add-on ui-themes: the install FAILED (network down); to try again, run in the project: x"
echo
echo "Optional. Add-ons not installed; each line is the command and what it costs:"
EOF
echo 'echo "doctor: ok"' > "$PL/scripts/doctor.sh"
git init -q -b main "$PROJ" && mkdir -p "$PROJ/.claude" && echo '{"version": 1}' > "$PROJ/.claude/commandeck.json"
SLUG=$(cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR bash -c '. "$0" && echo "$PP_MAIN_SLUG"' "$REAL/scripts/paths.sh")
mkdir -p "$HOME/.commandeck/install" && echo '{"root": "/old", "entries": {}}' > "$HOME/.commandeck/install/$SLUG.json"
upd() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH -u CODEX_HOME bash "$PL/scripts/update.sh" 2>&1); }

OUT=$(upd)
check "it shows setup's Needs-you block, the failed install's line whole" "Needs you:
  add-on ui-themes: the install FAILED (network down); to try again, run in the project: x" "$(grep -A1 '^Needs you:$' <<<"$OUT")"
check "and not the rest of setup's report" 0 "$(grep -c '^Optional\.\|^add-on serena' <<<"$OUT")"
# Issue 314: setup updates Codex when a newer one is out; the owner is told, not only on failure.
check "it says setup's codex line" "codex: updated 0.40.0 -> 0.41.0 (codex update)" "$(grep '^codex: ' <<<"$OUT")"
# Pass 4's class: the way back copies the manifests and the profile file from before setup ran, so a revoke in
# another pane meanwhile was lost; it now waits for the update's lock.
check "setup runs under the update's lock, handed to it" "lock: held, fd handed" "$(cat "$HOME/lock-seen")"
check "then the doctor runs and the update says done" '1:1' "$(grep -c '^doctor: ok$' <<<"$OUT"):$(grep -c '^update: done$' <<<"$OUT")"

# --- pass 5: the relay's pane opens only after the update lets go of the lock ---
# Setup's own let-go does not free a lock the update still holds, and the update holds it to its way back. A pane
# opened inside that window starts its launch repair under the lock, which gives up after 30 s and leaves the copied
# profile without setup's settings. orca-ide is a stub that notes, at `terminal create`, whether the lock is free.
mkdir -p "$T/bin"; export PATH=$T/bin:$PATH
cat > "$T/bin/orca-ide" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "terminal list") echo '{"result": []}' ;;
  "terminal create") { ( exec 8<"$HOME/.commandeck/install"; flock -n 8 ) && echo "create: lock free" || echo "create: lock held"; } >> "$HOME/log"
    echo '{"result": {"handle": "term_relay"}}' ;;
  "worktree create") mkdir -p "$PP_WORKSPACES/Chief-of-Staff"; echo '{}' ;;
esac
EOF
chmod +x "$T/bin/orca-ide"
# Setup's side, its relay block run alone: a fresh relay worktree under the update is left to it, not opened.
SR=$T/setup-relay; mkdir -p "$SR/scripts"; echo 'exit 0' > "$SR/scripts/worktree-setup.sh"; ln -s "$REAL/scripts/codex-helpers.sh" "$REAL/scripts/paths.sh" "$SR/scripts/"
git -C "$PROJ" commit -q --allow-empty -m init
RELAY=$(sed -n '/^# --- the relay: /,/^# --- the project files/p' "$REAL/scripts/setup.sh")
srelay() { (cd "$PROJ" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH "$@" bash -c '. "$0/paths.sh" && PP_WORKSPACES=$1 && export PP_WORKSPACES && pp_worktree_new() { orca-ide worktree create; }; HERE=$2 NAME=Kit NEED=(); eval "$3"; printf "need: %s\n" "${NEED[@]}"' "$REAL/scripts" "$SR/ws" "$SR/scripts" "$RELAY" 2>&1); }
: > "$HOME/log"; OUT=$(srelay IL_RELAY_PANE="$SR/relay-pane")
check "setup under the update: the new relay's pane is left to the update, with its place, name and command" \
  "0:$SR/ws/Chief-of-Staff	Kit	orca-ide terminal create --worktree path:$SR/ws/Chief-of-Staff --title Kit --command claude:need: " \
  "$(grep -c create "$HOME/log"):$(cat "$SR/relay-pane" 2>/dev/null):$(grep '^need:' <<<"$OUT")"
rm -rf "$SR/ws"; : > "$HOME/log"; OUT=$(srelay)
check "setup on its own still opens the new relay's pane" "create: lock free:1" "$(cat "$HOME/log"):$(grep -c "opened its pane (term_relay)" <<<"$OUT")"
# The update's side: setup (a stub) leaves the pane to it; it opens it after the doctor, with the lock let go.
sed -i.bak '1a\
[ -z "${IL_RELAY_PANE:-}" ] || printf "%s\\t%s\\t%s\\n" "$HOME/ws/Chief-of-Staff" Kit "orca-ide terminal create x" > "$IL_RELAY_PANE"' "$PL/scripts/setup.sh"
echo 'echo "doctor: ok" | tee -a "$HOME/log"' > "$PL/scripts/doctor.sh"
: > "$HOME/log"; OUT=$(upd)
check "the update opens the relay's pane after the doctor, with the lock free" "doctor: ok
create: lock free" "$(cat "$HOME/log")"
check "and says so, then done" '1:1' "$(grep -c "^Relay: opened Kit's pane (term_relay)\.$" <<<"$OUT"):$(grep -c '^update: done$' <<<"$OUT")"
echo 'echo "doctor: broken"; exit 1' > "$PL/scripts/doctor.sh"
: > "$HOME/log"; OUT=$(upd)
check "an update that goes back opens no pane" 0 "$(grep -c create "$HOME/log")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
