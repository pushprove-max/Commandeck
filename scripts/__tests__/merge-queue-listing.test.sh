#!/usr/bin/env bash
# covers: scripts/merge-queue.sh
# Issue 307's reuse rule against a check that lists its inputs, by directory listing or a path built from
# parts (split from merge-queue-glob.test.sh): a run that tested another tree never stands for the merged tree.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
. "$(dirname "$0")/fixtures/merge-queue-setup.sh"

pattern_cases <<'EOF'
a directory listing|set -- $(ls | grep flag)
readdirSync|set -- $(node -p "require(\\"fs\\").readdirSync(\\".\\").filter(f => f.endsWith(\\".flag\\")).join(\\" \\")")
a path built from parts|n=0; for x in a b; do [ -e "$x.flag" ] && n=$((n + 1)); done; set -- $(seq $n)
EOF
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
