#!/usr/bin/env bash
# builder-launch-resume.test.sh -- the second call of a risky launch (the one that opens the Builder once the design
# note exists), on a real worktree and the real worktree-setup.sh, with seat.sh, the pass script and orca-ide stood
# in for. What this pins: a --keep given on the second call reaches the Builder's settings before its pane opens,
# as it does on a first call, so a billing exemption asked for late is not silently dropped.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME" "$T/bin"
P=$T/proj WS=$T/ws
mkdir -p "$P/.claude/plans" "$WS" "$T/plug"
git init -q -b main "$P"; echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"; echo plan > "$P/.claude/plans/toy.md"
git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -q -m base
# A copy of the plugin whose seat.sh only reruns the settings script (as the real launch does) and records the keep
# the Builder would open with; the pass script has nothing to check, and the planning worktree has nothing to close.
cp -R "$REAL/scripts" "$REAL/hooks" "$REAL/templates" "$REAL/config" "$T/plug/"
printf '#!/usr/bin/env bash\n[ "$1 $2" != "launch builder" ] || { bash "$(dirname "$0")/worktree-setup.sh" "$COMMANDECK_WORKSPACES/$3" >/dev/null 2>&1; jq -r ".env.COMMANDECK_SKILL_KEEP // \\"none\\"" "$COMMANDECK_WORKSPACES/$3/.claude/settings.local.json" > "%s/keep-at-open"; }\n' "$T" > "$T/plug/scripts/seat.sh"
printf '#!/usr/bin/env bash\necho "claude-x\\tx"\n' > "$T/plug/scripts/builder-claude-pass.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/plug/scripts/plan-worktree-close.sh"
cat > "$T/bin/orca-ide" <<EOS
#!/usr/bin/env bash
case "\$*" in
  "worktree create"*) git -C "$P" worktree add -q "$WS/u1" ;;
  "terminal list"*) echo '{"ok":true,"result":{"terminals":[]}}' ;;
esac
echo '{"ok":true,"result":{}}'
EOS
chmod +x "$T"/bin/orca-ide "$T"/plug/scripts/*.sh
printf '## The issues\n\n1. #1: x\n\n## Prior art\n\nnone\n\n## Plan\n\n.claude/plans/toy.md\n' > "$T/batch.md"
launch() { (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky "$@" u1 "$T/batch.md" </dev/null 2>&1); }
launch >"$T/out"; check "the first call opens the design pane and no Builder" "1:0" "$(grep -c 'design pane open' "$T/out"):$(test -e "$T/keep-at-open" && echo 1 || echo 0)"
mkdir -p "$WS/u1/.claude/briefs"; echo note > "$WS/u1/.claude/briefs/u1-design.md"
launch --keep billing >"$T/out"
check "a second call with --keep billing opens the Builder with Stripe kept" "billing:null" \
  "$(cat "$T/keep-at-open" 2>/dev/null):$(jq -c '.enabledPlugins["stripe@claude-plugins-official"]' "$WS/u1/.claude/settings.local.json")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
