#!/usr/bin/env bash
# dashboard-registry.test.sh -- one dashboard per machine. Two repos at five
# Builder slots each must not mean two collectors and two pages, so the
# collector reads a registry of main checkouts and the snapshot keeps each
# under its own name. What this pins: two registered repos are two projects;
# a unit name both use is read by path, so neither shows the other's panes;
# the machine's own readings (limit, host, alerts) are there once, outside
# every project; a registered checkout that is gone is named, not dropped; a
# registered project is listed only with a GitHub origin; and the home project,
# the one the collector runs for, is always listed and is the page's default.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
DASH=$SOURCE/scripts/dashboard.sh
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home
OUT=$T/out BIN=$T/bin
mkdir -p "$HOME" "$BIN" "$T/elsewhere"
repo() { # name [parent]
  local d=${2:-$T}/$1
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1 first" \
    && git -C "$d" config remote.origin.url "${3:-https://github.com/acme/$1.git}" \
    && git -C "$d" worktree add -q "$HOME/orca/workspaces/$1/u1" -b "$1-u1" 2>/dev/null
}
repo alpha; repo beta
git -C "$T/alpha" config --unset remote.origin.url  # the home project needs none
git init -q -b main "$T/elsewhere/alpha"
# alpha's u1 is a Builder with a working pane; beta's u1 is a plain worktree whose pane finished.
mkdir -p "$HOME/orca/workspaces/alpha/u1/.claude"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$HOME/orca/workspaces/alpha/u1/.claude/settings.local.json"
jq -cn --arg a "$HOME/orca/workspaces/alpha/u1" --arg b "$HOME/orca/workspaces/beta/u1" '{result: {worktrees: [
  {path: $a, agents: [{agentType: "claude", state: "working"}]},
  {path: $b, agents: [{agentType: "codex", state: "done"}]}]}}' > "$T/orca.json"
cat > "$BIN/orca-ide" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "worktree ps --json") cat "$T/orca.json" ;;
  "terminal list --json") echo '{"result":{"terminals":[]}}' ;;
  *) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/pgrep"
# gh is never the real one: here it has no answer, so the P1 count is not measured.
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/gh"
chmod +x "$BIN"/*

# COMMANDECK_MAIN names alpha throughout: without it the collector would read the project the test is run from.
dash() { env -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME \
  PATH="$BIN:$PATH" COMMANDECK_HOST_OS=Linux COMMANDECK_DASHBOARD_DIR="$OUT" COMMANDECK_MAIN="$T/alpha" bash "$DASH" "$@"; }
reg() { dash "$@" 2>&1; }
j() { sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$OUT/data.js" | jq -c "$1" 2>&1; }

# --- the registry holds each main checkout once ---
reg --register "$T/alpha" >/dev/null; reg --register "$T/alpha" >/dev/null
check "registering twice keeps one line" 1 "$(grep -c . "$OUT/projects" 2>/dev/null)"
reg --register "$HOME/orca/workspaces/beta/u1" >/dev/null
check "a worktree registers its main checkout" "$T/beta" "$(sed -n 2p "$OUT/projects" 2>/dev/null)"
reg --register "$T/elsewhere/alpha" >/dev/null; check "a second checkout of one name is refused" 1 $?
reg --register "$T/bin" >/dev/null; check "a folder that is no checkout is refused" 1 $?
check "a refused path is not written" 2 "$(grep -c . "$OUT/projects" 2>/dev/null)"
# Every log and cache is keyed by the folder name with its odd characters
# turned to dashes, so two names that differ only there are one key.
for n in "a b" a-b; do git init -q -b main "$T/$n" && git -C "$T/$n" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first; done
reg --register "$T/a b" >/dev/null; check "a name with a space registers" 0 $?
reg --register "$T/a-b" >/dev/null; check "a name that is the same once cleaned is refused" 1 $?
reg --unregister "$T/a b" >/dev/null
check "and the registry is back to two" 2 "$(grep -c . "$OUT/projects" 2>/dev/null)"

# --- two registered repos are two projects; the machine's readings are there once ---
mkdir -p "$OUT/cache/beta"
echo '{"u1":{"stage":"waiting-main","round":null,"since":1000,"exact":true}}' > "$OUT/cache/beta/unit-stages.json"
dash >"$T/collect.out" 2>&1; check "a collect over two projects succeeds" 0 $?
check "two projects, by name" '["alpha","beta"]' "$(j '.projects | keys')"
check "alpha's u1 shows alpha's pane" '"claude:working"' "$(j '.projects.alpha.units.inFlight[0].agents')"
check "beta's u1 shows beta's pane" '"codex:done"' "$(j '.projects.beta.units.inFlight[0].agents')"
check "alpha's u1 is its Builder" '"building"' "$(j '.projects.alpha.units.inFlight[0] | select(.builder != null) | .stage')"
check "beta's u1 is no Builder and waits on main" '[null,"waiting-main"]' "$(j '.projects.beta.units.inFlight[0] | [.builder, .stage]')"
check "each project has its own main commits" '["alpha first","beta first"]' "$(j '[.projects[].mainChain.commits[0].subject]')"
check "each project names its checkout" "[\"$T/alpha\",\"$T/beta\"]" "$(j '[.projects[].path]')"
check "the machine's readings are at the top, once" 'true' "$(j '[has("limit"), has("host"), has("alerts")] | all')"
check "no project repeats a machine reading" 'false' "$(j '[.projects[] | has("limit") or has("host") or has("alerts")] | any')"
check "no project's reading sits at the top" 'false' "$(j 'has("units") or has("needsOwner") or has("mainChain")')"
check "a project's alert carries its project, for the watcher to filter on" '["beta"]' "$(j '[.alerts[] | select(.id | startswith("stage-")) | .project]')"
check "an alert names its project" '["stage-beta/u1"]' "$(j '[.alerts[].id | select(startswith("stage-")) | sub("-[0-9]+$"; "")]')"
check "each project keeps its own source records" 'true' "$(j '[.projects[].sources.worktrees.status == "fresh"] | all')"

# --- listed: the home project always, a registered one only with a GitHub origin ---
check "the snapshot names the home project, the page's default" '"alpha"' "$(j .home)"
repo gamma "" "$T/elsewhere"; repo delta "" https://github.com.example.net/acme/delta.git; repo eps "" git@github.com:acme/eps.git
git init -q -b main "$T/zeta" && git -C "$T/zeta" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
for n in gamma delta eps zeta; do reg --register "$T/$n" >/dev/null; done
dash >"$T/collect.out" 2>&1; check "a collect with projects that are not listed succeeds" 0 $?
check "an origin on another host, one that only starts like GitHub's, or none is not listed; an ssh GitHub origin is" '["alpha","beta","eps"]' "$(j '.projects | keys')"
check "each project left out is named with the reason, not dropped in silence" '[true,true,true,false]' \
  "$(j '.sources.projects.error as $e | ["/gamma", "/delta", "/zeta", "/eps"] | map(. as $n | $e | test("no GitHub origin.*" + $n + "\\b"))')"
check "the day's cost is kept for the listed projects only" '["alpha","beta","eps"]' "$(j '.limit.today | keys')"
for n in gamma delta eps zeta; do reg --unregister "$T/$n" >/dev/null; done
reg --unregister "$T/alpha" >/dev/null
dash >"$T/collect.out" 2>&1
check "the home project is listed without a registry line" '["alpha","beta"]' "$(j '.projects | keys')"
reg --unregister "$T/beta" >/dev/null; reg --register "$T/alpha" >/dev/null; reg --register "$T/beta" >/dev/null

# A workspace folder that is there and cannot be listed: the units are unknown,
# not none. An empty list would drop every unit from the page and from the
# record of when each entered its stage.
dash >"$T/collect.out" 2>&1; BEFORE_STAGES=$(jq -c 'keys' "$OUT/cache/beta/unit-stages.json")
chmod 000 "$HOME/orca/workspaces/beta"
dash >"$T/collect.out" 2>&1
chmod 755 "$HOME/orca/workspaces/beta"
check "units in a workspace folder that cannot be listed are unknown, not none" 'null' "$(j '.projects.beta.units.inFlight')"
check "the source says so" 'true' "$(j '.projects.beta.sources.worktrees.status != "fresh"')"
check "and the record of their stages is kept" "$BEFORE_STAGES" "$(jq -c 'keys' "$OUT/cache/beta/unit-stages.json")"

# --- unregistering drops the project; a registered checkout that is gone is named ---
reg --unregister "$T/beta" >/dev/null
dash >>"$T/collect.out" 2>&1
check "an unregistered project is gone" '["alpha"]' "$(j '.projects | keys')"
reg --register "$T/beta" >/dev/null; rm -rf "$T/beta"
dash >>"$T/collect.out" 2>&1; check "a collect with a missing checkout still publishes" 0 $?
check "the project that is still there is kept" '["alpha"]' "$(j '.projects | keys')"
check "the missing checkout is named, not dropped in silence" '["not-measured",true]' "$(j '.sources.projects | [.status, (.error | test("/beta$"))]')"

# --- with no registry, the checkout the collector runs for is the one project ---
rm -f "$OUT/projects"
dash >>"$T/collect.out" 2>&1
check "no registry: the current checkout is the one project" '["alpha"]' "$(j '.projects | keys')"

# The snapshot is a script. Written as a plain key, a project named __proto__
# would become the object's prototype and vanish from the page.
repo __proto__; reg --register "$T/__proto__" >/dev/null
dash >"$T/collect.out" 2>&1; check "a collection with a project named __proto__ succeeds" 0 $?
check "the page's script still lists that project" yes \
  "$(node -e 'global.window = {}; require(process.argv[1]); console.log(Object.keys(window.DASH.projects).includes("__proto__") ? "yes" : "no")' "$OUT/data.js" 2>&1)"
[ "$FAIL" = 0 ] || sed 's/^/  collect: /' "$T/collect.out" | tail -20
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
