#!/usr/bin/env bash
# The strict tier is OFF unless the project turned it on. A strict hook that
# speaks in a project that never asked for it is the plugin refusing ordinary
# work on install day, so every one of them must be silent and exit 0 there,
# whatever the payload. The switch is "strictHooks": true in the project's
# .claude/commandeck.json, read from the primary checkout so a worktree
# answers as its main does.
set -u
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected '$2', got '$3')"; fi }

STRICT="bash-guardrails batch-independent-looks edit-content-tripwires
file-size-cop git-ignore-warn new-test-file-guard pane-budget-gate read-tracker script-over-reads
staged-index-warn suite-rerun-guard test-skip-only-blocker web-fetch-blocker"

# The list above is the tier: a hook gated by accident, or a strict one that
# lost its gate, changes what a default install refuses.
GATED=$(cd "$HOOKS" && grep -l 'pp_strict' -- *.sh | sed 's/\.sh$//' | sort | tr '\n' ' ')
check "the gated hooks are exactly the strict list" "$(echo $STRICT | tr ' ' '\n' | sort | tr '\n' ' ')" "$GATED"

SKIP=$(jq -cn '{tool_name:"Write", tool_input:{file_path:"/x/src/a.test.ts", content:"it.only(\"x\", () => {});\n"}}')
SEARCH=$(jq -cn '{tool_name:"Bash", tool_input:{command:"grep -r foo /"}}')
FETCH=$(jq -cn '{tool_name:"WebFetch", tool_input:{url:"https://example.com/"}}')
# run <tier|-> <hook> <payload> [cwd]: prints "<rc>|<everything it said>"
run() {
  local out rc
  out=$(cd "${4:-$TMP}" && if [ "$1" = - ]; then env -u COMMANDECK_HOOK_TIER bash "$HOOKS/$2.sh" 2>&1 <<<"$3"
        else COMMANDECK_HOOK_TIER=$1 bash "$HOOKS/$2.sh" 2>&1 <<<"$3"; fi); rc=$?
  echo "$rc|$out"
}
rc() { run "$@" | head -1 | cut -d'|' -f1; }

# The payloads are refusing ones: strict proves it, so the silence below is the
# gate and not a payload nothing would have refused.
check "strict: a focused test is refused"      2 "$(rc strict test-skip-only-blocker "$SKIP")"
check "strict: a search of / is refused"       2 "$(rc strict bash-guardrails "$SEARCH")"
check "strict: a web fetch is advised"         yes "$([ -n "$(run strict web-fetch-blocker "$FETCH" | cut -d'|' -f2-)" ] && echo yes)"

for h in $STRICT; do
  for p in "$SKIP" "$SEARCH" "$FETCH"; do
    check "default: $h is silent on $(jq -r .tool_name <<<"$p")" "0|" "$(run default "$h" "$p")"
  done
done

# Without the gate line the same hook, same tier, refuses: the line is what
# keeps the default install quiet.
mkdir -p "$TMP/ungated"; cp -R "$HOOKS/lib" "$TMP/ungated/"
grep -v 'pp_strict' "$HOOKS/test-skip-only-blocker.sh" > "$TMP/ungated/test-skip-only-blocker.sh"
check "an ungated copy refuses in the default tier" 2 \
  "$(COMMANDECK_HOOK_TIER=default bash "$TMP/ungated/test-skip-only-blocker.sh" >/dev/null 2>&1 <<<"$SKIP"; echo $?)"

# The project file, with no override in the environment.
P="$TMP/proj"; git init -q -b main "$P"
git -C "$P" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m base
git -C "$P" worktree add -q "$TMP/wt" -b wt
check "no project file: off"                    0 "$(rc - test-skip-only-blocker "$SKIP" "$P")"
mkdir -p "$P/.claude"; echo '{"version": 1, "strictHooks": false}' > "$P/.claude/commandeck.json"
check "strictHooks false: off"                  0 "$(rc - test-skip-only-blocker "$SKIP" "$P")"
echo '{"version": 1, "strictHooks": true}' > "$P/.claude/commandeck.json"
check "strictHooks true: on in the main checkout" 2 "$(rc - test-skip-only-blocker "$SKIP" "$P")"
check "and in a worktree of it"                 2 "$(rc - test-skip-only-blocker "$SKIP" "$TMP/wt")"
check "COMMANDECK_HOOK_TIER=default overrides the file" 0 "$(rc default test-skip-only-blocker "$SKIP" "$P")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
