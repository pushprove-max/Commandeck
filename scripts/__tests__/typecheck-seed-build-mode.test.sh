#!/usr/bin/env bash
# typecheck-seed-build-mode.test.sh -- Issue 386, pass-1 finding: a buildinfo seeded from a sibling worktree must never
# let `tsc -b` call a changed worktree up to date. A copy dated newer than every input is trusted without reading the
# sources, so a type error the sibling never had passed the closing-pass typecheck green. Pinned with the real compiler:
# the seeded run reports the worktree's TS2322 as a cold run does, and a worktree that matches the sibling stays green.
# Needs TypeScript, which the plugin does not ship: `tsc` on PATH, or COMMANDECK_TEST_NODE_MODULES holding
# `typescript`. Without one the file is skipped and says so, never counted as a pass in silence.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
TSC=$(command -v tsc || true)
[ -n "$TSC" ] || [ ! -f "${COMMANDECK_TEST_NODE_MODULES:-}/typescript/bin/tsc" ] || TSC="node $COMMANDECK_TEST_NODE_MODULES/typescript/bin/tsc"
if [ -z "$TSC" ]; then
  echo "SKIPPED typecheck-seed-build-mode.test.sh: no TypeScript; put tsc on PATH or set COMMANDECK_TEST_NODE_MODULES to a node_modules folder that has typescript"
  exit 0
fi
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
eval "$(sed -n '/^seed_typecheck_cache() {$/,/^}$/p' "$REAL/scripts/builder-codex-pass.sh")"

SIB=$T/sib WT=$T/wt
mkdir -p "$SIB" "$WT"; git -C "$WT" init -q; printf '.cache/\n' > "$WT/.gitignore"
printf '%s\n' '{"compilerOptions":{"composite":true,"noEmit":true,"strict":true,"types":[],"tsBuildInfoFile":".cache/tc.tsbuildinfo"},"files":["x.ts"]}' \
  > "$SIB/tsconfig.json"
cp "$SIB/tsconfig.json" "$WT/tsconfig.json"
printf 'export const x: number = 1;\n' > "$SIB/x.ts"
(cd "$SIB" && $TSC -b) >/dev/null 2>&1
tc() { (cd "$WT" && $TSC -b --pretty false) >"$T/out" 2>&1; echo "$? $(grep -c 'error TS2322' "$T/out")"; }
# Worktree sources older than the sibling's cache: the case where a fresh-dated copy looked current.
plant() { printf '%s\n' "$1" > "$WT/x.ts"; touch -t 202001010000 "$WT/x.ts" "$WT/tsconfig.json"; rm -rf "$WT/.cache"; }

plant 'export const x: number = "bad";'
check "a cold build-mode typecheck reports the planted error" "1 1" "$(tc)"
plant 'export const x: number = "bad";'
seeded() { seed_typecheck_cache | grep -c '^typecheck cache: seeded 1 file'; }
check "a seeded build-mode typecheck still reports the worktree's type error" "1 1 1" "$(seeded) $(tc)"
plant 'export const x: number = 1;'
check "a seeded build-mode typecheck of a worktree that matches the sibling is green" "1 0 0" "$(seeded) $(tc)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
