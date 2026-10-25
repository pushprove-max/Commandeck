# Sourced by builder-launch-resume.test.sh, builder-launch-resume-rollback.test.sh,
# builder-launch-resume-launch-line.test.sh and builder-launch-resume-from-plan.test.sh: a real worktree and the real
# worktree-setup.sh, with seat.sh, the pass script and orca-ide stood in for, and the launch helpers. Four files, not
# one: one file of every case ran 162 s alone at load ~150, past the runner's 120 s per-file cap; the owner ruled
# that no file raises it.
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
export HOME=$T/home; mkdir -p "$HOME" "$T/bin"
P=$T/proj WS=$T/ws
mkdir -p "$P/.claude/plans" "$WS" "$T/plug"
git init -q -b main "$P"; echo '{"version": 1, "profile": "claude"}' > "$P/.claude/commandeck.json"; PSZ="- Planned size: 1 file, 10 changed lines"; printf "plan\n%s\n" "$PSZ" > "$P/.claude/plans/toy.md"
git -C "$P" add -A && git -C "$P" -c user.name=t -c user.email=t@t commit -q -m base
# A copy of the plugin whose seat.sh only reruns the settings script (as the real launch does) and records the keep
# the Builder would open with; the pass script has nothing to check, and the planning worktree has nothing to close.
cp -R "$REAL/scripts" "$REAL/hooks" "$REAL/templates" "$REAL/config" "$T/plug/"
printf '#!/usr/bin/env bash\n[ ! -e "%s/seat-fails" ] || exit 1\necho "$1 $2 $3" >> "%s/seats"\n[ ! -e "%s/seat-opens-fails" ] || { touch "%s/pane-open"; exit 1; }\n[ "$1 $2" != "launch builder" ] || { bash "$(dirname "$0")/worktree-setup.sh" "$COMMANDECK_WORKSPACES/$3" >/dev/null 2>&1; jq -r ".env.COMMANDECK_SKILL_KEEP // \\"none\\"" "$COMMANDECK_WORKSPACES/$3/.claude/settings.local.json" > "%s/keep-at-open"; }\n' "$T" "$T" "$T" "$T" "$T" > "$T/plug/scripts/seat.sh"
printf '#!/usr/bin/env bash\necho "claude-x\\tx"\n' > "$T/plug/scripts/builder-codex-pass.sh"
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
batchfor() { printf '## The issues\n\n1. #1: x\n\n## Launch\n\n%s\nOrder: build issue 1\n\n## Prior art\n\nnone\n\n## Data design\n\nnone: no state is added or changed\n\n## What can go wrong\n\nan empty batch: one named test\n\n## Plan\n\n.claude/plans/toy.md\n' "${2-Launch: new unit $1}" > "$T/batch.md"; }
launch() { batchfor u1; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" --risky "$@" u1 "$T/batch.md" </dev/null 2>&1); }
# build <unit> -- a launch with no --risky; RC and $T/out hold its exit and output.
build() { batchfor "$1"; (cd "$P" && env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS bash "$T/plug/scripts/builder-launch.sh" "$1" "$T/batch.md" </dev/null >"$T/out" 2>&1); RC=$?; }
# planned <unit> -- the worktree a plan seat's first launch leaves: cut from main and marked as that unit's.
planned() { git -C "$P" worktree add -q "$WS/$1" && echo "$1" > "$(git -C "$WS/$1" rev-parse --absolute-git-dir)/commandeck-plan-of"; }
mark() { cat "$(git -C "$WS/$1" rev-parse --absolute-git-dir)/commandeck-plan-of" 2>/dev/null; }
# Issue 256 (--from-plan) helpers.
git -C "$P" config user.name t; git -C "$P" config user.email t@t
E=(env -u COMMANDECK_MAIN -u CLAUDE_PROJECT_DIR -u COMMANDECK_SCRATCH -u CLAUDE_CONFIG_DIR PATH="$T/bin:$PATH" COMMANDECK_WORKSPACES=$WS)
SCR=$(cd "$P" && "${E[@]}" bash -c '. "$0/paths.sh" && mkdir -p "$PP_SCRATCH" && echo "$PP_SCRATCH"' "$T/plug/scripts")
fp() { : > "$T/seats"; (cd "$P" && "${E[@]}" bash "$T/plug/scripts/builder-launch.sh" --from-plan "$@" </dev/null >"$T/out" 2>&1); RC=$?; }
hash() { sha256sum < "$WS/$1/.claude/plans/$1.md" | cut -d' ' -f1; }
# fpunit <unit> -- a planning worktree holding its plan and the batch beside it, as the plan seats and main leave them.
fpunit() { planned "$1"; mkdir -p "$WS/$1/.claude/plans" "$WS/$1/.claude/briefs"; printf "plan of %s\n%s\n" "$1" "$PSZ" > "$WS/$1/.claude/plans/$1.md"
  batchfor "$1"; sed "s#\.claude/plans/toy\.md#.claude/plans/$1.md#" "$T/batch.md" > "$WS/$1/.claude/briefs/$1-batch.md"; }
# judged <unit> <GO|NO-GO> <collected> -- the judge's record as seat.sh leaves it: the plan hashed at launch, then the verdict.
judged() { printf 'role=plan-judge-%s\nlaunched=100\nplan=%s\nplanhash=%s\nverdict=VERDICT: %s\ncollected=%s\n' \
  "${4:-claude}" "$WS/$1/.claude/plans/$1.md" "$(hash "$1")" "$2" "$3" > "$SCR/seat-$1-plan-judge-${4:-claude}.txt"; }
onmain() { git -C "$P" show "main:.claude/plans/$1.md" 2>/dev/null | head -1 | grep . || echo none; } # the plan's first line
