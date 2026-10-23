#!/usr/bin/env bash
# dashboard-built-costs.test.sh -- the costs kept for finished builds, and the project registry, are never lost to a
# file that cannot be read or a directory in its place; --register and --import (issue 292); the 7-day cost list
# (issue 270) and the unit ledger's review loop and escapes (issues 271, 272). The fixture is dashboard-built.test.sh's.
set -uo pipefail
. "$(dirname "$0")/fixtures/dashboard-built-setup.sh"
dash

# The costs kept for finished builds are written back whole on every run. A kept file that could not be read
# was taken as empty and overwritten, losing every earlier unit's cost; one that reads but is not an object is reset.
K=$T/out/cache/demo/unit-cost.json
printf '{"old-unit":{"usd":1}}\n' > "$K"; chmod 000 "$K"; dash; chmod 644 "$K"
check "an unreadable kept cost file is left as it was" '{"old-unit":{"usd":1}}' "$(jq -c . "$K" 2>&1)"
echo 'not json{' > "$K"; dash
check "a corrupt kept cost file is reset to an object" '{}' "$(jq -c . "$K" 2>&1)"
rm "$K"; mkdir "$K"; dash
check "a directory where the kept cost file belongs gets nothing put inside it" 0 "$(ls -A "$K" | wc -l | tr -d ' ')"
# Issue 280: the kept costs grow by one unit a build and went on jq's command line: past the argument limit (ARG_MAX)
# every collect failed with "Argument list too long", and the units card was gone for good.
rm -rf "$K"; jq -cn '[range(30000) | {key: "u-\(.)", value: {total: {usd: 1, calls: 3}, stages: []}}] | from_entries' > "$K"
[ "$(wc -c < "$K")" -gt 1048576 ] || echo "FAIL setup: the kept cost file is not over 1 MB"
dash
check "issue 280: a kept cost file over 1 MB: the collect completes and keeps every unit" "0 30000 object" \
  "$(grep -c 'Argument list too long' "$T/out.log") $(jq length "$K" 2>&1) $(jq -r 'first(.[]) | .units | type' "$T/out/run/project.json" 2>&1)"
rm -f "$K"
# The same fault in --unregister: an unreadable registry was rewritten as empty, dropping every registered project.
unreg() { COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" bash "$SOURCE/scripts/dashboard.sh" --unregister "$1" >/dev/null 2>&1; }
R=$T/out/projects; printf '/a\n/b\n' > "$R"; chmod 000 "$R"; unreg /a
check "--unregister with an unreadable registry fails and leaves it as it was" "1 /a /b" "$? $(chmod 644 "$R"; paste -sd' ' "$R")"
unreg /a; check "--unregister drops only that project" "0 /b" "$? $(paste -sd' ' "$R")"
rm "$R"; mkdir "$R"; unreg /b
check "--unregister with a directory where the registry belongs fails, putting nothing inside it" "1 0" "$? $(ls -A "$R" | wc -l | tr -d ' ')"
# Issue 292: the registry that does not list home turns it off, so the first --register, which made it, dropped home.
rmdir "$R"; git init -q -b main "$T/other"; git -C "$T/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" bash "$SOURCE/scripts/dashboard.sh" --register "$T/other" >/dev/null 2>&1
check "issue 292: the first --register of another project keeps home collected, listed first" "0 $MAIN $T/other" "$? $(paste -sd' ' "$R")"
rm -f "$R"

# Issue 292: --import carries over another collector's history, saved layout and cleared builds, never over what is here.
I=$T/imp; mkdir -p "$I/cache" "$I/p/demo" "$T/out/cache"
printf '%s\n' '{"at":"1999-01-01T00:00:00Z","pct":10}' '{"at":"1999-01-02T00:00:00Z","pct":99}' '{"at":"1999-01-03T00:00:00Z","pct":30,"folder":"/elsewhere"}' > "$I/cache/limit-history.jsonl"
# The history here is this account's, as a collect records it (dash's --project run does not).
python3 "$SOURCE/scripts/dashboard_limit.py" account "$T/out/cache" >/dev/null
printf '%s\n' '{"at":"1999-01-02T00:00:00Z","pct":20}' > "$T/out/cache/limit-history.jsonl"
echo 'window.DASH_LAYOUT = {"rev":4,"order":["a"],"cleared":3,"projects":{"other":{"rev":2,"hidden":["b"]}}};' > "$I/layout.js"
echo 'window.DASH_LAYOUT = {"rev":1,"builds":{"u-1":"shut","u-2":"open"}};' > "$I/p/demo/layout.js"
echo 'window.DASH_LAYOUT = {"rev":7,"order":["mine"],"projects":{"other":{"rev":3,"order":["kept"]}}};' > "$T/out/layout.js"
printf '\tu-old\nother\tu-9\n' > "$I/closed.log"; printf '\tu-old\n' > "$T/out/closed.log"
imp() { COMMANDECK_DASHBOARD_DIR="$T/out" COMMANDECK_MAIN="$MAIN" bash "$SOURCE/scripts/dashboard.sh" --import "$I" 2>&1; }
check "issue 292: --import prints what it took" \
  "dashboard: --import from $I took 1 limit-history.jsonl rows; 0 codex-limit-history.jsonl rows; layout slots: demo; 1 cleared builds" "$(imp)"
check "issue 292: a history row held here wins; another account's row is left out" '[[10,"1999-01-01T00:00:00Z"],[20,"1999-01-02T00:00:00Z"]]' \
  "$(jq -sc 'map([.pct, .at])' "$T/out/cache/limit-history.jsonl")"
check "issue 292: a layout held here is kept; a slot not held is taken, its folds as true/false" \
  '[7,["mine"],["kept"],{"builds":{"u-1":true,"u-2":false},"rev":1}]' \
  "$(sed 's/^[^=]*= //; s/;$//' "$T/out/layout.js" | jq -c '[.rev, .order, .projects.other.order, .projects.demo]')"
check "issue 292: a cleared build is added once" "$(printf '\tu-old\nother\tu-9')" "$(cat "$T/out/closed.log")"
check "issue 292: --import run again takes nothing" \
  "dashboard: --import from $I took 0 limit-history.jsonl rows; 0 codex-limit-history.jsonl rows; layout slots: none; 0 cleared builds" "$(imp)"
# A history here that cannot be read is no empty one: import refuses it, and the collector's record() leaves it.
cp "$T/out/cache/limit-history.jsonl" "$T/hist.kept"; echo '{"at":"1999-01-05T00:00:00Z","pct":50}' >> "$I/cache/limit-history.jsonl"
chmod 000 "$T/out/cache/limit-history.jsonl"
imp >/dev/null; RC=$?
(cd "$SOURCE/scripts" && python3 -c 'import sys, dashboard_limit as d; d.record(sys.argv[1], 2000000000, 5, 2000000000)' "$T/out/cache/limit-history.jsonl" 2>/dev/null)
chmod 600 "$T/out/cache/limit-history.jsonl"
check "an unreadable history here is refused by --import and left as it was by the collector" "1 same" \
  "$RC $(cmp -s "$T/hist.kept" "$T/out/cache/limit-history.jsonl" && echo same)"
# A fresh folder had no account record, so the collector's first account check took the imported history for an
# unknown account's and moved it aside: the import was gone from view after one collect.
F=$T/fresh; COMMANDECK_DASHBOARD_DIR="$F" COMMANDECK_MAIN="$MAIN" bash "$SOURCE/scripts/dashboard.sh" --import "$I" >/dev/null 2>&1
python3 "$SOURCE/scripts/dashboard_limit.py" account "$F/cache" >/dev/null
check "--import into a fresh folder: the collector's account check keeps the imported history" "[10,99,50] none" \
  "$(jq -sc 'map(.pct)' "$F/cache/limit-history.jsonl" 2>&1) $(ls "$F/cache" | grep -c 'limit-history\..*\.jsonl' | sed 's/^0$/none/')"
# The collector's history write and the server's layout save land while --import is between its read and its
# replace: the import waits for the lock each one holds, so neither write is lost. The holder stands in for both.
H=$T/race; mkdir -p "$H/cache"; python3 "$SOURCE/scripts/dashboard_limit.py" account "$H/cache" >/dev/null
echo '{"at":"1999-01-04T00:00:00Z","pct":40}' > "$H/cache/limit-history.jsonl"
echo 'window.DASH_LAYOUT = {"order":["old"],"rev":4};' > "$H/layout.js"
python3 - "$H" <<'PY' &
import fcntl, os, sys, time
h = sys.argv[1]
with open(h + '/cache/limit-history.jsonl.lock', 'a') as a, open(h + '/layout.js.lock', 'a') as b:
    fcntl.flock(a, fcntl.LOCK_EX); fcntl.flock(b, fcntl.LOCK_EX)
    open(h + '/held', 'w').close()
    while not os.path.exists(h + '/go'):
        time.sleep(0.05)
    with open(h + '/cache/limit-history.jsonl', 'a') as f:
        f.write('{"at":"1999-01-06T00:00:00Z","pct":60}\n')
    with open(h + '/layout.js', 'w') as f:
        f.write('window.DASH_LAYOUT = {"order":["new"],"rev":5};\n')
PY
HOLDER=$!; until [ -e "$H/held" ]; do sleep 0.05; done
COMMANDECK_DASHBOARD_DIR="$H" COMMANDECK_MAIN="$MAIN" bash "$SOURCE/scripts/dashboard.sh" --import "$I" >/dev/null 2>&1 &
IMPORT=$!; sleep 3; kill -0 "$IMPORT" 2>/dev/null && WAITED=waited || WAITED="did not wait"
touch "$H/go"; wait "$HOLDER" "$IMPORT"
check "--import beside a collector write and a layout save waits for them and keeps both" \
  'waited [10,99,40,50,60] [5,["new"],["demo","other"]]' \
  "$WAITED $(jq -sc 'map(.pct)' "$H/cache/limit-history.jsonl") $(sed 's/^[^=]*= //; s/;$//' "$H/layout.js" | jq -c '[.rev, .order, (.projects | keys?)]')"

# Issue 270: what each unit cost over the last 7 days, from the costs kept for its card: a unit finished 9 days ago
# is out, and each unit in the list carries the figures its own card shows.
cu() { jq -cn --argjson usd "$1" '{total: {usd: $usd, input: 100, cached: 50, output: 10, byAgent: {claude: ($usd - 0.5), codex: 0.5}}, stages: [{stage: "building", usd: $usd}]}'; }
jq -cn --argjson a "$(cu 1.5)" --argjson b "$(cu 2)" --argjson c "$(cu 9)" '{"new-a": $a, "new-b": $b, "old-c": $c}' > "$K"
mkdir -p "$HOME/.commandeck/builds"
for u in new-a:1 new-b:2 old-c:9; do
  jq -cn --arg m "$(cd "$MAIN" && pwd -P)" --arg u "${u%:*}" --argjson d "${u#*:}" '{main: $m, unit: $u, how: "merged", at: (now - $d * 86400 | todate), sha: ("b" * 40)}'
done > "$HOME/.commandeck/builds/demo.jsonl"
dash
check "issue 270: the 7-day cost list holds the units in the window, most costly first, each as its card shows it" \
  '[["new-b",2,1.5,0.5],["new-a",1.5,1,0.5]] true' \
  "$(jq -r 'first(.[]).units | [.costPerUnit[] | select(.unit | test("^(new|old)-"))] as $l
    | [[$l[] | [.unit, .total.usd, .total.byAgent.claude, .total.byAgent.codex]],
      ([$l[] | {(.unit): .total}] | add) == ([.finishedBuilds[] | select(.unit | test("^new-")) | {(.unit): .cost.total}] | add)] | "\(.[0] | tojson) \(.[1])"' "$T/out/run/project.json" 2>&1)"

# Issues 271 and 272: the review loop and its escapes are read from the unit ledger the merge writes, long after
# the unit's worktree and round files are gone. No ledger is not measured, never an empty week.
check "issues 271 and 272: with no unit ledger both parts are null and the source says why" \
  '[null,null,"not-measured"]' "$(jq -c 'first(.[]) | [.reviewLoop, .escapes, .sources["unit-ledger"].status]' "$T/out/run/project.json" 2>&1)"
mkdir -p "$MAIN/.claude/metrics"
{ for u in loopy:5:4:3 quick:1:0:1 old:7:6:9; do IFS=: read -r n r g d <<< "$u"
    jq -cn --arg u "$n" --argjson r "$r" --argjson g "$g" --argjson d "$d" '{unit: $u, mergeSha: ("c" * 40), mergedAt: (now - $d * 86400 | todate),
      rounds: $r, goRounds: 1, noGoRounds: $g, fixRounds: null, verdict: "CONVERGED-GO", findings: null, expensivePasses: null,
      gaps: ["fixRounds", "findings", "expensivePasses"]} + (if $u == "loopy" then {passKinds: {adversarial: {go: 0, noGo: 4}, final: {go: 1, noGo: 0}}, reviewSeconds: 1500} else {} end)'; done
  printf '%s\n' '{"unit":"loopy","escaped":[41],"class":"lost-reply","caught":"production","recordedAt":"1999-01-02T00:00:00Z"}' '{"unit":"gone","escaped":[42],"recordedAt":"1999-01-02T00:00:00Z"}' \
    '{"unit":"loopy","escaped":[43],"class":"race","caught":"main","recordedAt":"1999-01-03T00:00:00Z"}' 'not json'; } > "$MAIN/.claude/metrics/unit-ledger.jsonl"
dash
check "issue 271: the units merged in 7 days, most rounds first; an older unit and the escape rows are left out" \
  '[["loopy",5,4,null,["fixRounds","findings","expensivePasses"]],["quick",1,0,null,["fixRounds","findings","expensivePasses"]]]' \
  "$(jq -c 'first(.[]) | [.reviewLoop[] | [.unit, .rounds, .noGoRounds, .fixRounds, .gaps]]' "$T/out/run/project.json" 2>&1)"
check "issue 271: a unit's GO/NO-GO per pass kind and its seconds in review reach the page, null on a row from before them" \
  '[["loopy",{"adversarial":{"go":0,"noGo":4},"final":{"go":1,"noGo":0}},1500],["quick",null,null]]' \
  "$(jq -c 'first(.[]) | [.reviewLoop[] | [.unit, .passKinds, .reviewSeconds]]' "$T/out/run/project.json" 2>&1)"
check "issue 272: one escape entry per unit and issue with its class and where caught (null on an older row), a unit with no merged row included" \
  '[{"unit":"gone","issue":42,"class":null,"caught":null},{"unit":"loopy","issue":41,"class":"lost-reply","caught":"production"},{"unit":"loopy","issue":43,"class":"race","caught":"main"}]' "$(jq -c 'first(.[]) | .escapes' "$T/out/run/project.json" 2>&1)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
