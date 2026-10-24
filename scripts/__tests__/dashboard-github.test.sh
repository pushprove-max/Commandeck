#!/usr/bin/env bash
# dashboard-github.test.sh -- the GitHub panes (Merge line, Who holds what, Next push) are read by the collector
# from gh and git. The owner acts on them: a check shown green that failed, or an issue number that links to
# another repository, would send him the wrong way. What this pins: each pull request's checks keep gh's order
# and read as pass, fail or run; an issue takes its priority label and milestone; the next push lists exactly
# the commits the upstream lacks with the issues each names; the page gets the repository's address from the
# origin remote; every gh call is a read; and with gh not signed in, or no GitHub origin, each pane is null
# with the reason while the rest of the project is still collected. And the project's workspace folder is the
# one its sessions record, or its Builders' and worktrees' costs would match none of them.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

export HOME=$T/home
MAIN=$T/demo BIN=$T/bin
mkdir -p "$HOME" "$BIN"
g() { git -C "$MAIN" -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main "$MAIN" && g commit -q --allow-empty -m "first"
git init -q --bare "$T/origin.git" && g remote add origin "$T/origin.git" && g push -q -u origin main 2>/dev/null
printf 'a\nb\n' > "$MAIN/f" && g add f && g commit -q -m "Stream the export" -m "Closes #12"
printf 'a\n' > "$MAIN/f" && g commit -q -am "Bump the lint config"
# The address the page links to comes from the remote's URL; the upstream branch stays the one pushed above.
g remote set-url origin git@github.com:example/demo.git

# gh is never the real one: it answers each read from a fixture in gh's own shape, or exits as $T/gh-exit says.
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/gh.calls"; printf '%s\n' "\${GH_REPO:-none}" >> "$T/gh.repos"
[ ! -e "$T/gh-exit" ] || exit "\$(cat "$T/gh-exit")"
case "\$1 \$2" in
  "pr list") echo '[{"number":7,"title":"Stream the export","url":"https://github.com/example/demo/pull/7","isDraft":false,"headRefName":"work/u1",
    "reviewDecision":"APPROVED","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","additions":3,"deletions":1,"closingIssuesReferences":[{"number":12}],
    "statusCheckRollup":[{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS"},
      {"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"},
      {"__typename":"CheckRun","name":"e2e","status":"IN_PROGRESS","conclusion":""},
      {"__typename":"StatusContext","context":"deploy","state":"PENDING"}]}]' ;;
  "issue list") case "\$*" in *created:*) cat "$T/gh-created.json"; exit ;; *closed:*) cat "$T/gh-closed.json"; exit ;;
      *"--label P1 "*) cat "$T/gh-p1.json"; exit ;; *"--label proposed-decision "*) cat "$T/gh-pd.json"; exit ;; esac
    cat "$T/gh-issues.json" ;;
  "api repos/{owner}/{repo}/milestones?state=open&per_page=100") echo '[{"title":"2.4 Exports","due_on":"2026-10-17T07:00:00Z","open_issues":5,"closed_issues":7}]' ;;
  "run list") echo '[{"conclusion":"success","status":"completed","createdAt":"2026-10-14T10:00:00Z","workflowName":"ci"}]' ;;
  *) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/orca-ide"
chmod +x "$BIN"/*
echo '[{"number":12,"title":"Export times out","url":"https://github.com/example/demo/issues/12","createdAt":"2026-10-01T00:00:00Z",
  "labels":[{"name":"bug"},{"name":"P2"},{"name":"P1"}],"milestone":{"title":"2.4 Exports"}}]' > "$T/gh-issues.json"
# Seven open issues of a label, numbers out of order: the dashboard lists the five lowest and keeps all seven.
seven() { jq -cn --arg l "$1" '[44, 41, 47, 42, 45, 43, 46] | map({number: ., title: "Issue \(.)", url: "https://github.com/example/demo/issues/\(.)", labels: [{name: $l}]})'; }
seven P1 > "$T/gh-p1.json"; seven proposed-decision > "$T/gh-pd.json"
# Issue 273's reads: issues opened 2 h, 30 h and 3 days ago, one closed an hour ago.
jq -cn '[2, 30, 72] | map({number: ., createdAt: (now - . * 3600 | todate), closedAt: null})' > "$T/gh-created.json"
jq -cn '[{number: 9, createdAt: "1999-01-01T00:00:00Z", closedAt: (now - 3600 | todate)}]' > "$T/gh-closed.json"

# collect <out dir> -- one project's collect, as dashboard.sh --project runs it; prints its exit code. $WS, when
# set, is the project's workspace folder.
collect() {
  env -u COMMANDECK_WORKSPACES -u COMMANDECK_SCRATCH -u COMMANDECK_HOOK_FIRE_LOG -u CODEX_HOME PATH="$BIN:$PATH" ${WS:+COMMANDECK_WORKSPACES=$WS} \
    COMMANDECK_DASHBOARD_DIR="$1" COMMANDECK_MAIN="$MAIN" DASH_NOW="${DNOW:-$(date +%s)}" bash "$SOURCE/scripts/dashboard.sh" --project "$1/run" >"$1.log" 2>&1
  echo $?
}
j() { jq -c "first(.[]) | $2" "$1/run/project.json" 2>&1; }

check "a collect with gh answering succeeds" 0 "$(collect "$T/one")"
check "the repository's address comes from the origin remote" '"https://github.com/example/demo"' "$(j "$T/one" .github.repo)"
check "a pull request's checks keep gh's order: success, failure, in progress, pending" '["pass","fail","run","run"]' "$(j "$T/one" '[.github.prs[0].checks[].state]')"
check "a pull request names the issues it closes, its branch, review and merge state" '[[12],"work/u1","APPROVED","MERGEABLE","BLOCKED",false]' \
  "$(j "$T/one" '.github.prs[0] | [.closes, .branch, .review, .mergeable, .mergeState, .draft]')"
# gh's own default repository may be another remote (an upstream): every read names the origin's, the one the page links to.
check "every gh read is made in the origin's repository" "example/demo" "$(sort -u "$T/gh.repos")"
check "an issue's priority is its lowest P label, and its milestone is named" '["P1","2.4 Exports"]' "$(j "$T/one" '.github.issues[0] | [.priority, .milestone]')"
check "a milestone keeps its due date and counts" '[{"title":"2.4 Exports","due":"2026-10-17T07:00:00Z","open":5,"closed":7}]' "$(j "$T/one" .github.milestones)"
check "the last CI run is read for the branch main pushes to" 1 "$(grep -c -- '^run list --branch main ' "$T/gh.calls")"
check "the next push is the two commits the upstream lacks, newest first, with the issues each names" \
  '{"upstream":"origin/main","behind":0,"ahead":2,"subjects":["Bump the lint config","Stream the export"],"refs":[[],[12]],"lines":[[0,1],[2,0]]}' \
  "$(j "$T/one" '.nextPush | {upstream, behind, ahead, subjects: [.commits[].subject], refs: [.commits[].refs], lines: [.commits[] | [.added, .deleted]]}')"
# Issue 273: the Issues card's 24-hour line and 7-day sparkline, from issues created and closed in the last 7 days.
# Issue 292: the P1 and proposed-decision lists, as counted previews: the five lowest numbers, then all of them.
check "seven P1 issues give count 7, the five lowest numbers in top, all seven in all" '[7,[41,42,43,44,45],7,"Issue 41"]' \
  "$(j "$T/one" '.githubP1 | [.count, [.top[].number], (.all | length), .top[0].title]')"
check "seven open proposed-decision issues give count 7, the five lowest numbers in top, all seven in all" '[7,[41,42,43,44,45],7,"https://github.com/example/demo/issues/41"]' \
  "$(j "$T/one" '.githubProposed | [.count, [.top[].number], (.all | length), .top[0].url]')"
check "the issue read asks for 1000" 1 "$(grep -c '^issue list --state open --limit 1000 --json number,title,url,labels,milestone,createdAt$' "$T/gh.calls")"
check "issue 273: opened and closed in 24 h, and per local day over 7 days" '[1,1,7,3,1,false]' \
  "$(j "$T/one" '.github.flow | [.opened24h, .closed24h, (.daily | length), (.daily | map(.opened) | add), (.daily | map(.closed) | add), .incomplete]')"
check "issue 273: each read asks for 7 days, at most 1000" 2 "$(grep -cE '^issue list --state (all|closed) --search (created|closed):>=[0-9-]{10} --json number,createdAt,closedAt --limit 1000$' "$T/gh.calls")"
cp "$T/gh-created.json" "$T/gh-created.bak"; jq -cn '[range(1000) | {number: ., createdAt: (now | todate), closedAt: null}]' > "$T/gh-created.json"
check "issue 273: a read that hits the limit is marked incomplete" true "$(collect "$T/many" >/dev/null; j "$T/many" .github.flow.incomplete)"
mv "$T/gh-created.bak" "$T/gh-created.json"
# A 7-day span over the autumn DST change (New York, 2026-11-01 23:30) is still seven calendar days, one bucket each.
check "issue 273: the 7 local days run on across a DST change, one bucket a day" \
  '["2026-10-26","2026-10-27","2026-10-28","2026-10-29","2026-10-30","2026-10-31","2026-11-01"]' \
  "$(DNOW=1793593800 TZ=America/New_York collect "$T/dst" >/dev/null; j "$T/dst" '[.github.flow.daily[].day]')"
echo '[{"number":1,"title":"a","url":"u","createdAt":"2026-10-01T00:00:00Z","labels":[{"name":"P1"}]},{"number":2,"title":"b","url":"u","createdAt":"2026-10-01T00:00:00Z","labels":[{"name":"P1"},{"name":"P2"}]},
  {"number":3,"title":"c","url":"u","createdAt":"2026-10-01T00:00:00Z","labels":[{"name":"P2"}]},{"number":4,"title":"d","url":"u","createdAt":"2026-10-01T00:00:00Z","labels":[{"name":"bug"}]}]' > "$T/gh-issues.json"
check "issues P1, P1, P2 and one unlabelled give byPriority P1 2, P2 1, none 1" '{"P1":2,"P2":1,"none":1}' "$(collect "$T/prio" >/dev/null; j "$T/prio" .github.byPriority)"
check "every gh call is a read" "" "$(grep -vE '^(pr list|issue list|run list|api repos/\{owner\}/\{repo\}/milestones\?state=open&per_page=100)( |$)' "$T/gh.calls")"

# gh not signed in exits 4. No copy was cached in this dashboard folder, so each pane is null with the reason.
echo 4 > "$T/gh-exit"
check "with gh not signed in the project is still collected" 0 "$(collect "$T/two")"
check "each GitHub pane is null" '[null,null,null,null]' "$(j "$T/two" '.github | [.prs, .issues, .milestones, .runs]')"
check "and its source says gh is not signed in" '"not-measured gh is not signed in: run gh auth login; nothing was cached"' \
  "$(j "$T/two" '.sources["github-prs"] | "\(.status) \(.error)"')"
check "the rest of the project is there" '[2,"https://github.com/example/demo"]' "$(j "$T/two" '[.nextPush.ahead, .github.repo]')"

# A checkout with no GitHub origin asks gh nothing.
rm -f "$T/gh-exit" "$T/gh.calls"
g remote set-url origin "$T/origin.git"
check "with no GitHub origin the project is still collected" 0 "$(collect "$T/three")"
check "the panes say there is no GitHub origin" '[null,"no GitHub origin"]' "$(j "$T/three" '[.github.repo, .sources["github-issues"].error]')"
check "and gh was asked only for the P1 and proposed-decision lists" 0 "$(grep -cvE '^issue list --state open --label (P1|proposed-decision) ' "$T/gh.calls")"

# A session records its folder as the OS gives it, a link resolved (and on a Mac, its letter case): the workspace
# folder a link names is recorded as the folder itself, so the costs read from those sessions match it.
mkdir -p "$T/ws/u1" && ln -s "$T/ws" "$T/wslink"
check "a workspace folder named through a link is collected as the folder it names" "\"$T/ws\"" "$(WS=$T/wslink collect "$T/four" >/dev/null; j "$T/four" .workspaces)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
