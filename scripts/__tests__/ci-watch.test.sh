#!/usr/bin/env bash
# ci-watch.test.sh -- ci-watch.sh <sha> with a stubbed gh (issue 259). A flaky CI run cost main a manual rerun and a
# wait; a deploy rerun by a script could ship twice. What this pins: a failed run's failed jobs are rerun once and the
# run then reads green; a run that fails again is not rerun a second time, not by this call and not by a later one;
# a deploy workflow (by its name or its file) is watched and never rerun; the one result line names each job.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
mkdir -p "$T/bin" "$T/home" "$T/gh"
git init -q -b main "$T/p"
# The gh stand-in: $T/gh/runs is "<id>\t<workflow name>\t<file>" lines; <id>.rc holds one exit code per attempt
# (line 1 the first run, line 2 after one rerun); <id>.att counts reruns. Like the real gh, a listing returns one page
# of 20 runs unless it is asked to paginate. Its total_count is $T/gh/total when that file is there, else every run;
# GitHub stops a head_sha listing at 1,000 runs but still counts them all. When $T/gh/runs.2 is there, a paged listing
# also returns it as a second page whose total_count is $T/gh/total.2: a run added or removed between pages shifts them.
cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/gh.log"
G=$T/gh
att() { echo \$(( \$(cat "\$G/\$1.att" 2>/dev/null || echo 0) + 1 )); }
rc() { sed -n "\$(att "\$1")p" "\$G/\$1.rc"; }
pg() { jq -Rn --argjson n "\$2" '{total_count: \$n, workflow_runs: [inputs | split("\t") | {id: (.[0] | tonumber), name: .[1], path: .[2]}]}' < "\$1"; }
page() { case " \$* " in *" --paginate "*) cat "\$G/runs" ;; *) head -20 "\$G/runs" ;; esac; }
case "\$*" in
  "run list"*) page "\$@" | jq -Rn '[inputs | split("\t") | {databaseId: (.[0] | tonumber), workflowName: .[1]}]' | jq -r "\${@: -1}" ;;
  "api --paginate "*"actions/runs?"*) { pg "\$G/runs" "\$(cat "\$G/total" 2>/dev/null || wc -l < "\$G/runs")"
    [ ! -f "\$G/runs.2" ] || pg "\$G/runs.2" "\$(cat "\$G/total.2")"; } | jq -r "\${@: -1}" ;;
  "run watch"*) exit "\$(rc "\$3")" ;;
  "run rerun"*) echo \$(( \$(att "\$3") )) > "\$G/\$3.att" ;;
  "run view"*) r=\$(rc "\$3"); [ "\$r" = 0 ] && c=success || c=failure; echo "test \$c" ;;
  "api "*) id=\${2##*/}; [ ! -f "\$G/slow-path" ] || sleep 1; awk -F'\t' -v id="\$id" '\$1 == id { print \$3 }' "\$G/runs" ;;
esac
EOF
chmod +x "$T/bin/gh"
W() { (cd "$T/p" && env -u CLAUDE_PROJECT_DIR HOME="$T/home" PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/p" COMMANDECK_SCRATCH="$T/scratch" \
  COMMANDECK_FOREGROUND=1 bash "$REAL/scripts/ci-watch.sh" "$@" 2>&1); }
reruns() { grep -c "^run rerun $1 --failed" "$T/gh.log"; }

printf '11\tci\t.github/workflows/ci.yml\n' > "$T/gh/runs"; printf '1\n0\n' > "$T/gh/11.rc"
OUT=$(W abc1234); RC=$?
check "a flaky run: failed, rerun once, then green; exit 0 and one line naming the job" "0:1:1" \
  "$RC:$(reruns 11):$(grep -c 'ci: test success (rerun once)' <<<"$OUT")"

rm -f "$T/gh"/*.att "$T/scratch/ci-watch-reruns"; : > "$T/gh.log"
printf '12\tci\t.github/workflows/ci.yml\n' > "$T/gh/runs"; printf '1\n1\n1\n' > "$T/gh/12.rc"
OUT=$(W abc1234); RC=$?
check "a run that fails again after its one rerun is not rerun twice, and reads failed" "1:1:1" \
  "$RC:$(reruns 12):$(grep -c 'ci: test failure' <<<"$OUT")"
W abc1234 >/dev/null
check "and a later call on the same sha does not rerun it either" 1 "$(reruns 12)"

# Two watchers of one sha at once: the run-file lookup is slowed so both are past the first record check together.
rm -f "$T/gh"/*.att "$T/scratch/ci-watch-reruns"; : > "$T/gh.log"; touch "$T/gh/slow-path"
W abc1234 >/dev/null & W abc1234 >/dev/null & wait
rm -f "$T/gh/slow-path"
check "two watchers of one sha at once rerun a failed run once between them" 1 "$(reruns 12)"

: > "$T/gh.log"
printf '13\tDeploy site\t.github/workflows/site.yml\n14\tpages\t.github/workflows/deploy-pages.yml\n' > "$T/gh/runs"
printf '1\n0\n' > "$T/gh/13.rc"; printf '1\n0\n' > "$T/gh/14.rc"
OUT=$(W abc1234); RC=$?
check "a deploy workflow, by its name or its file, is watched and never rerun" "1:0:0:2" \
  "$RC:$(reruns 13):$(reruns 14):$(grep -c '^run watch 1[34] --exit-status' "$T/gh.log")"

: > "$T/gh.log"; rm -f "$T/gh"/*.rc
for i in $(seq 101 121); do printf '%s\tci%s\t.github/workflows/ci.yml\n' "$i" "$i"; echo 0 > "$T/gh/$i.rc"; done > "$T/gh/runs"
printf '1\n1\n' > "$T/gh/121.rc"
OUT=$(W abc1234); RC=$?
check "a commit with more runs than one listing page: the 21st run is watched, rerun once, and its failure reads NOT green" "1:2:1" \
  "$RC:$(grep -c '^run watch 121 --exit-status' "$T/gh.log"):$(grep -c 'NOT green' <<<"$OUT")"

: > "$T/gh.log"; rm -f "$T/gh"/*.att "$T/scratch/ci-watch-reruns"; echo 22 > "$T/gh/total"; for i in $(seq 101 121); do echo 0 > "$T/gh/$i.rc"; done
OUT=$(W abc1234); RC=$?
check "a listing GitHub cut short (21 of 22 runs, all green) reads NOT green before any watch: the missing run may have failed" "1:0:1" \
  "$RC:$(grep -c '^run watch' "$T/gh.log"):$(grep -c 'NOT green.*21 of 22' <<<"$OUT")"
rm -f "$T/gh/total"

# Scaled down from GitHub: page 1 is read, then a run is added, so page 2 repeats one id and counts one more run.
: > "$T/gh.log"; rm -f "$T/gh"/*.rc; for i in 1 2 3; do echo 0 > "$T/gh/$i.rc"; done
printf '3\tci3\t.github/workflows/ci.yml\n2\tci2\t.github/workflows/ci.yml\n' > "$T/gh/runs"; echo 3 > "$T/gh/total"
printf '1\tci1\t.github/workflows/ci.yml\n' > "$T/gh/runs.2"; echo 4 > "$T/gh/total.2"
OUT=$(W abc1234); RC=$?
check "pages whose total_count differ (3, then 4) read NOT green before any watch: the added run went unread" "1:0:1" \
  "$RC:$(grep -c '^run watch' "$T/gh.log"):$(grep -c 'NOT green.*changed while' <<<"$OUT")"
: > "$T/gh.log"; printf '2\tci2\t.github/workflows/ci.yml\n' > "$T/gh/runs.2"; echo 3 > "$T/gh/total.2"
OUT=$(W abc1234); RC=$?
check "a page that repeats an id (3 rows, 2 runs, total 3) reads NOT green before any watch: the run it pushed out went unread" "1:0:1" \
  "$RC:$(grep -c '^run watch' "$T/gh.log"):$(grep -c 'NOT green.*2 of 3' <<<"$OUT")"
rm -f "$T/gh/total" "$T/gh/runs.2" "$T/gh/total.2"

: > "$T/gh.log"
check "a bad sha is refused before any gh call" "2:0" "$(W 'not a sha' >/dev/null; echo $?):$(wc -l < "$T/gh.log" | tr -d ' ')"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
