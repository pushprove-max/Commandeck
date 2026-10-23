#!/usr/bin/env bash
# seat-launch-github.test.sh -- issue 316: seat.sh launch reads GitHub once as the seat would (a Codex seat inside its
# sandbox) before the pane opens, and refuses with the reason. What this pins: each pane seat is refused with no pane and
# no record; the reason tells a sandbox with no network from one that hides gh's sign-in from a host that is signed out;
# the probe carries the seat's own token, Codex home, settings env and repo; a first plan launch is probed in main.
# Its own file because seat-launch.test.sh ran past the runner's 120 s cap with these cases in it.
set -uo pipefail
. "$(dirname "$0")/fixtures/seat-setup.sh"
jq '.builder = {effort: "high"}' "$CFG" > "$T/cfg" && mv "$T/cfg" "$CFG"
printf 'Judge the plan.\nEnd on a line of its own.\n' > "$T/judge-spec.md"
cap() { jq -n --argjson o "$1" '{pluginConfigs: {"commandeck@commandeck": {options: $o}}}' > "$HOME/.claude/settings.json"; }
# The codex stand-in: `codex sandbox <words> -- <cmd>` runs <cmd> as the sandboxed seat would (GH_SANDBOXED set), and
# every call is logged with the CODEX_HOME it saw.
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
echo "\$*|CODEX_HOME=\${CODEX_HOME:-}" >> "$T/codex.log"
if [ "\${1:-}" = sandbox ]; then shift; while [ \$# -gt 0 ] && [ "\$1" != -- ]; do shift; done; shift; GH_SANDBOXED=1 exec "\$@"; fi
exit 0
EOF
chmod +x "$BIN/codex"

# Issue 316: a judge that read the brief's copy of an issue because gh had no network. Every pane seat's launch makes
# one gh read as that seat would (a Codex seat inside its sandbox), and refuses with the reason when it fails.
cap '{"planJudgeSolAgent": "codex", "planJudgeAstraAgent": "codex"}'
jq -n '{models: [{slug: "gpt-9.1-sol"}, {slug: "gpt-9.1-astra"}]}' > "$HOME/.codex/models_cache.json"
for u in gu gb; do git -C "$PROJ" worktree add -q "$HOME/orca/workspaces/proj/$u"; done
echo gu > "$(git -C "$HOME/orca/workspaces/proj/gu" rev-parse --absolute-git-dir)/commandeck-plan-of"
gl() { : > "$T/creates"; rm -f "$T/pane-up"; srun launch "$1" "${2:-gu}" "${3:-$T/judge-spec.md}" >"$T/out" 2>&1; echo "$?"; }
echo "error connecting to api.github.com" > "$T/gh-fail"
for r in plan-author plan-judge-sol plan-judge-astra builder; do
  u=gu; [ "$r" != builder ] || u=gb; spec=$T/judge-spec.md; [ "$r" != builder ] || spec=$T/spec.md
  rc=$(gl "$r" "$u" "$spec")
  check "$r with no network for gh is refused at launch with the reason; no pane, no record" "2:1:0:0" \
    "$rc:$(grep -c "^BLOCKED: $r cannot read GitHub from its sandbox: no network in the sandbox" "$T/out"):$(grep -c . "$T/creates"):$(ls "$HOME/.commandeck/scratch/"*/"seat-$u-$r.txt" 2>/dev/null | grep -c .)"
done
echo "To get started with GitHub CLI, please run:  gh auth login" > "$T/gh-fail"
rc=$(gl plan-judge-sol)
check "a sandbox that hides gh's sign-in while the host has it: no credentials visible in the sandbox" "2:1" \
  "$rc:$(grep -c 'cannot read GitHub from its sandbox: no credentials visible in the sandbox' "$T/out")"
touch "$T/gh-host-out"; rc=$(gl plan-judge-sol)
check "gh signed out on the host too: not signed in to gh" "2:1" "$rc:$(grep -c 'cannot read GitHub from its sandbox: not signed in to gh' "$T/out")"
rm -f "$T/gh-fail" "$T/gh-host-out"

# The probe is the seat's: its environment (the Codex shellEnv, its Codex home, a Claude seat's settings env) and its
# target repo. The stub fails the token the seat would carry, and a checkout that is not this project's repo.
RT=$T/rt316.json; ROUTING=$RT
jq '.roles["plan-judge-sol"] += {shellEnv: {GH_TOKEN: "seat-token"}}' "$REAL/config/routing.json" > "$RT"
echo seat-token > "$T/gh-bad-token"; rc=$(gl plan-judge-sol)
check "a Codex judge routed with its own GH_TOKEN is probed with that token, and refused" "2:1" "$rc:$(grep -c 'cannot read GitHub' "$T/out")"
jq '.roles["plan-judge-sol"] += {codexHome: "~/.codex-j"}' "$REAL/config/routing.json" > "$RT"; mkdir -p "$HOME/.codex-j"; cp "$HOME/.codex/models_cache.json" "$HOME/.codex-j/"
: > "$T/codex.log"; rc=$(gl plan-judge-sol)
check "a judge with its own Codex home is probed in that home" "0:1" "$rc:$(grep -c "^sandbox .*|CODEX_HOME=$HOME/.codex-j\$" "$T/codex.log")"
# A routing file deployed before judges had network (COMMANDECK_ROUTING of the owner's) still loads and renders the
# sandbox it always did; where gh then has no network in it, the launch says which key to set.
jq 'del(.roles["plan-judge-sol"].network)' "$REAL/config/routing.json" > "$RT"
rm -f "$T/gh-bad-token"; : > "$T/codex.log"; rc=$(gl plan-judge-sol)
check "a deployed judge row with no network key launches with --sandbox read-only and is probed in -c sandbox_mode" "0:1:1" \
  "$rc:$(sed -n 's/^cmd=//p' "$HOME/.commandeck/scratch/"*/seat-gu-plan-judge-sol.txt | tail -1 | grep -c -- '--sandbox read-only'):$(grep -c '^sandbox -c sandbox_mode="read-only" ' "$T/codex.log")"
echo "error connecting to api.github.com" > "$T/gh-fail-sandbox"; rc=$(gl plan-judge-sol)
check "and where gh has no network in that sandbox the launch is refused naming the key to set" "2:1" \
  "$rc:$(grep -c 'no network in the sandbox: .*Fix: set network: true on the seat' "$T/out")"
rm -f "$T/gh-fail-sandbox"; ROUTING=
mkdir -p "$HOME/orca/workspaces/proj/gu/.claude"; echo '{"env":{"GH_TOKEN":"seat-token"}}' > "$HOME/orca/workspaces/proj/gu/.claude/settings.local.json"
echo seat-token > "$T/gh-bad-token"; rc=$(gl plan-author)
check "a plan author whose checkout settings carry a GH_TOKEN env is probed with it, and refused" "2:1" "$rc:$(grep -c 'cannot read GitHub' "$T/out")"
rm -f "$T/gh-bad-token" "$HOME/orca/workspaces/proj/gu/.claude/settings.local.json"
# Claude Code gives the seat its routed env words, then user, project and local settings env on top, the later one
# winning: the probe must read with the token that wins, or it certifies one the seat never uses. Each step adds a layer.
jq '.roles["plan-author"] += {shellEnv: {GH_TOKEN: "routed"}}' "$REAL/config/routing.json" > "$RT"; ROUTING=$RT
echo "HTTP 401: Bad credentials" > "$T/gh-fail"; seen=
for l in - "$HOME/.claude/settings.json:user" "$HOME/orca/workspaces/proj/gu/.claude/settings.json:project" "$HOME/orca/workspaces/proj/gu/.claude/settings.local.json:local"; do
  [ "$l" = - ] || { f=${l%:*}; [ -e "$f" ] || echo '{}' > "$f"; jq --arg t "${l##*:}" '.env.GH_TOKEN = $t' "$f" > "$T/s" && mv "$T/s" "$f"; }
  : > "$T/gh.log"; gl plan-author >/dev/null; seen+="$(head -1 "$T/gh.log" | cut -d'|' -f2) "
done
check "a Claude seat is probed with the token Claude Code gives it: settings env over routed env words, local over project over user" \
  "routed user project local " "$seen"
rm -f "$T/gh-fail" "$HOME/orca/workspaces/proj/gu/.claude/settings"*.json; jq 'del(.env)' "$HOME/.claude/settings.json" > "$T/s" && mv "$T/s" "$HOME/.claude/settings.json"; ROUTING=
# Another repo's seat is probed in that repo's checkout, though this project reads fine.
OWT=$HOME/orca/workspaces/other/ou; git init -q -b main "$OWT" && git -C "$OWT" remote add origin https://github.com/o/other.git
echo o/proj > "$T/gh-repo"; : > "$T/gh.log"
rc=$(COMMANDECK_SEAT_REPO=other gl builder ou "$T/spec.md")
check "COMMANDECK_SEAT_REPO=other is probed in that repo's checkout, which the stub cannot read: refused" "2:1:$OWT" \
  "$rc:$(grep -c 'cannot read GitHub' "$T/out"):$(cut -d'|' -f1 "$T/gh.log" | tail -1)"
rm -f "$T/gh-repo"
# A plan seat's first launch has no worktree yet: it is probed in main, on main's tracked settings, not the caller's.
printf 'Launch: new unit fresh-plan\nOrder: test\nPlan it.\n' > "$T/fresh-spec.md"
CWT=$HOME/orca/workspaces/proj/caller; git -C "$PROJ" worktree add -q -b caller "$CWT"
mkdir -p "$CWT/.claude" && echo '{"env":{"GH_TOKEN":"invalid"}}' > "$CWT/.claude/settings.json" && git -C "$CWT" add .claude/settings.json && git -C "$CWT" -c user.name=t -c user.email=t@t commit -q -m invalid
echo invalid > "$T/gh-bad-token"; : > "$T/gh.log"; : > "$T/creates"; rm -f "$T/pane-up"
CALLER=$CWT srun launch plan-author fresh-plan "$T/fresh-spec.md" >"$T/out" 2>&1; rc=$?
check "a first plan launch reads main's settings, not the caller's: the worktree is cut and the pane opens" "0:1:$PROJ|:yes" \
  "$rc:$(grep -c . "$T/creates"):$(tail -1 "$T/gh.log" | cut -d'|' -f1,2):$([ -d "$HOME/orca/workspaces/proj/fresh-plan" ] && echo yes || echo no)"
git -C "$PROJ" worktree remove --force "$HOME/orca/workspaces/proj/fresh-plan" && git -C "$PROJ" branch -q -D fresh-plan
mkdir -p "$PROJ/.claude" && echo '{"env":{"GH_TOKEN":"invalid"}}' > "$PROJ/.claude/settings.json" && git -C "$PROJ" add .claude/settings.json && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q -m "main invalid"
git -C "$CWT" reset -q --hard main^; : > "$T/creates"; rm -f "$T/pane-up"
CALLER=$CWT srun launch plan-author fresh-plan "$T/fresh-spec.md" >"$T/out" 2>&1; rc=$?
check "reversed, main's tracked settings carry the bad token: refused, and no worktree is cut" "2:1:0:no" \
  "$rc:$(grep -c 'cannot read GitHub' "$T/out"):$(grep -c . "$T/creates"):$([ -d "$HOME/orca/workspaces/proj/fresh-plan" ] && echo yes || echo no)"
rm -f "$T/gh-bad-token"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
