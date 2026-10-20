#!/usr/bin/env bash
# builder-launch-resume.test.sh -- the second call of a risky launch (the one that opens the Builder once the design
# note exists), on a real worktree and the real worktree-setup.sh, with seat.sh, the pass script and orca-ide stood
# in for. What this pins: a --keep given on the second call reaches the Builder's settings before its pane opens,
# as it does on a first call, so a billing exemption asked for late is not silently dropped. And a unit is planned and
# built in one worktree: a clean planning worktree is adopted and the Builder opens in it, based on local main; a
# dirty one is refused before any pane closes, and an unmarked one (another Builder's) is refused as before.
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
printf '#!/usr/bin/env bash\n[ ! -e "%s/seat-fails" ] || exit 1\necho "$1 $2 $3" >> "%s/seats"\n[ ! -e "%s/seat-opens-fails" ] || { touch "%s/pane-open"; exit 1; }\n[ "$1 $2" != "launch builder" ] || { bash "$(dirname "$0")/worktree-setup.sh" "$COMMANDECK_WORKSPACES/$3" >/dev/null 2>&1; jq -r ".env.COMMANDECK_SKILL_KEEP // \\"none\\"" "$COMMANDECK_WORKSPACES/$3/.claude/settings.local.json" > "%s/keep-at-open"; }\n' "$T" "$T" "$T" "$T" "$T" > "$T/plug/scripts/seat.sh"
printf '#!/usr/bin/env bash\necho "claude-x\\tx"\n' > "$T/plug/scripts/builder-claude-pass.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/plug/scripts/plan-worktree-close.sh"
cat > "$T/bin/orca-ide" <<EOS
#!/usr/bin/env bash
echo "\$*" >> "$T/orca.log"
case "\$*" in
  "worktree create"*) a="\$*"; a=\${a#*--name }; git -C "$P" worktree add -q "$WS/\${a%% *}" ;;
  "terminal list"*) [ ! -e "$T/pane-open" ] || [ ! -e "$T/list-fails" ] || exit 1; [ -e "$T/pane-open" ] && echo '{"ok":true,"result":{"terminals":[{"handle":"term_b8","connected":true}]}}' || echo '{"ok":true,"result":{"terminals":[]}}'; exit ;;
esac
echo '{"ok":true,"result":{}}'
EOS
chmod +x "$T"/bin/orca-ide "$T"/plug/scripts/*.sh
# batchfor <unit> [launch line] -- the batch, its Launch line naming <unit> as a new unit unless one is given (issue 234).
batchfor() { printf '## The issues\n\n1. #1: x\n\n## Launch\n\n%s\nOrder: build issue 1\n\n## Prior art\n\nnone\n\n## Plan\n\n.claude/plans/toy.md\n' "${2-Launch: new unit $1}" > "$T/batch.md"; }
launch() { batchfor u1; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky "$@" u1 "$T/batch.md" </dev/null 2>&1); }
launch >"$T/out"; check "the first call opens the design pane and no Builder" "1:0" "$(grep -c 'design pane open' "$T/out"):$(test -e "$T/keep-at-open" && echo 1 || echo 0)"
mkdir -p "$WS/u1/.claude/briefs"; echo note > "$WS/u1/.claude/briefs/u1-design.md"
launch --keep billing >"$T/out"
check "a second call with --keep billing opens the Builder with Stripe kept" "billing:null" \
  "$(cat "$T/keep-at-open" 2>/dev/null):$(jq -c '.enabledPlugins["stripe@claude-plugins-official"]' "$WS/u1/.claude/settings.local.json")"

# --- a unit planned in its own worktree: the real plan-worktree-close.sh, a launch with no --risky ---
cp "$REAL/scripts/plan-worktree-close.sh" "$T/plug/scripts/"
build() { batchfor "$1"; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
# planned <unit> -- the worktree a plan seat's first launch leaves: cut from main and marked as that unit's.
planned() { git -C "$P" worktree add -q "$WS/$1" && echo "$1" > "$(git -C "$WS/$1" rev-parse --absolute-git-dir)/commandeck-plan-of"; }
mark() { cat "$(git -C "$WS/$1" rev-parse --absolute-git-dir)/commandeck-plan-of" 2>/dev/null; }
planned u2; echo more > "$P/.claude/plans/u2.md"; git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -q -m plan-u2
: > "$T/seats"; : > "$T/orca.log"; build u2
check "a clean planning worktree is adopted: the Builder opens in it, on local main, its brief written, the mark gone" "0:1:0:yes:yes:" \
  "$RC:$(grep -cx 'launch builder u2' "$T/seats"):$(grep -c '^worktree create' "$T/orca.log"):$([ "$(git -C "$WS/u2" rev-parse HEAD)" = "$(git -C "$P" rev-parse main)" ] && echo yes || echo no):$([ -s "$WS/u2/.claude/briefs/u2.md" ] && echo yes || echo no):$(mark u2)"
planned u3; echo x > "$WS/u3/stray"; : > "$T/seats"; : > "$T/orca.log"; build u3
check "a dirty one is refused before any pane closes, its file named, the planner's mark kept" "2:1:0:0:u3" \
  "$RC:$(grep -c "^REFUSED: $WS/u3 already exists.*holds stray (untracked)" "$T/out"):$(grep -c . "$T/seats"):$(grep -c '^terminal close' "$T/orca.log"):$(mark u3)"
# Adoption takes the mark before the reset to main: a reset that failed (a stale index lock) left the worktree
# unmarked, so every later Builder and planner launch refused it.
planned u5; touch "$(git -C "$WS/u5" rev-parse --absolute-git-dir)/index.lock"; : > "$T/seats"; build u5
check "a launch that fails after adoption gives the planner its mark back" "1:0:u5" "$RC:$(grep -c . "$T/seats"):$(mark u5)"
rm "$(git -C "$WS/u5" rev-parse --absolute-git-dir)/index.lock"; build u5
check "so the same launch run again adopts it and opens the Builder" "0:1:" "$RC:$(grep -cx 'launch builder u5' "$T/seats"):$(mark u5)"
# Pass 2: a launch that failed after it wrote the brief and the Builder settings (here, a routing log it cannot
# append to) gave the mark back but left both, so every retry's adoption refused them. The launch's own files go,
# and the planner's settings come back byte for byte.
planned u6; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/worktree-setup.sh" "$WS/u6" >/dev/null 2>&1)
cp "$WS/u6/.claude/settings.local.json" "$T/u6-settings"
skip() { batchfor u6; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS "$@" bash "$T/plug/scripts/builder-launch.sh" --skip-plan --reason retry-test u6 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
: > "$T/seats"; skip COMMANDECK_ROUTING_LOG=.
check "a launch that fails after its brief and Builder settings are written takes both back, and the mark comes back" "1:0:0:same:u6" \
  "$RC:$(grep -c . "$T/seats"):$(ls "$WS/u6/.claude/briefs" 2>/dev/null | grep -c '^u6'):$(cmp -s "$T/u6-settings" "$WS/u6/.claude/settings.local.json" && echo same || echo changed):$(mark u6)"
skip
check "so the same launch run again adopts it and opens the Builder" "0:1:" "$RC:$(grep -cx 'launch builder u6' "$T/seats"):$(mark u6)"
# The same for a risky launch whose design pane did not open: its design spec, left behind, made the retry read
# as the second call and wait for a design note no pane would write.
planned u7; touch "$T/seat-fails"; : > "$T/seats"
batchfor u7; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky u7 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?
check "a risky launch whose design pane fails takes its design spec and brief back, and the mark comes back" "1:0:u7" "$RC:$(ls "$WS/u7/.claude/briefs" 2>/dev/null | grep -c '^u7'):$(mark u7)"
rm "$T/seat-fails"
batchfor u7; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky u7 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?
check "so the retry adopts it and opens the design pane" "0:1:" "$RC:$(grep -cx 'launch design-coauthor u7' "$T/seats"):$(mark u7)"
# Pass 3: seat.sh can fail after its pane opened (its last screen read, after the dispatch). The rollback then took
# the brief and settings from under the running Builder and gave its worktree the planner's mark, so the next launch
# could adopt it under that Builder. A pane open in the worktree keeps the launch's state, and says so.
planned u8; touch "$T/seat-opens-fails"; : > "$T/seats"; build u8
check "a launch whose seat fails after its pane opened keeps the Builder's brief and settings, names the pane, gives no mark back" "1:yes:yes:1:" \
  "$RC:$([ -s "$WS/u8/.claude/briefs/u8.md" ] && echo yes || echo no):$([ -f "$WS/u8/.claude/settings.local.json" ] && echo yes || echo no):$(grep -c 'term_b8' "$T/out"):$(mark u8)"
rm "$T/pane-open"; planned u9
batchfor u9; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky u9 "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?
check "the same for a risky launch's design pane: its spec stays, so the retry waits for the note that pane writes" "1:yes:" \
  "$RC:$([ -s "$WS/u9/.claude/briefs/u9-design-spec.md" ] && echo yes || echo no):$(mark u9)"
rm "$T/pane-open"; planned u10; touch "$T/list-fails"; build u10
check "and when the pane list cannot be read, nothing says no pane opened: the launch's files stay too" "1:yes:1:" \
  "$RC:$([ -s "$WS/u10/.claude/briefs/u10.md" ] && echo yes || echo no):$(grep -c 'pane list could not be read' "$T/out"):$(mark u10)"
rm "$T/seat-opens-fails" "$T/pane-open" "$T/list-fails"
git -C "$P" worktree add -q "$WS/u4"; : > "$T/seats"; build u4
check "an existing unmarked worktree (another Builder's) is refused as before" "2:1:0" \
  "$RC:$(grep -c "^REFUSED: $WS/u4 already exists" "$T/out"):$(grep -c . "$T/seats")"

# Issue 234: a unit opened on an order that never named it. The batch quotes the order, and its Launch line must
# name this unit as new; adding work to a unit is builder-add-work.sh's.
# order <unit> <launch line> -- a launch of <unit> on a batch with that Launch line ('' for none); RC and $T/out as build's.
order() { : > "$T/seats"; : > "$T/orca.log"; batchfor "$1" "$2"; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS \
  bash "$T/plug/scripts/builder-launch.sh" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
order u11 ''
check "a batch with no Launch line is refused before anything opens" "2:1:0:0" "$RC:$(grep -c 'REFUSED: .* has no Launch line' "$T/out"):$(grep -c . "$T/seats"):$(grep -c . "$T/orca.log")"
order u12 'Launch: add to u2'
check "a batch that adds to a unit is refused, pointing to builder-add-work.sh" "2:1:0" "$RC:$(grep -c 'REFUSED: .*adds work to u2: run builder-add-work.sh u2' "$T/out"):$(grep -c . "$T/seats")"
order u13 'Launch: new unit u99'
check "a batch whose order names another unit is refused" "2:1:0" "$RC:$(grep -c "REFUSED: .*names u99, not u13" "$T/out"):$(grep -c . "$T/seats")"
order u14 'Launch: new unit u14'
check "a batch whose Launch line names this unit as new opens its Builder" "0:1" "$RC:$(grep -cx 'launch builder u14' "$T/seats")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
