#!/usr/bin/env bash
# Drift guard: every hook script hooks/hooks.json registers exists. A deleted hook whose entry stays makes the
# launcher fail on every call of its event, and with "onFailure": "block" that refuses the tool itself.
# Run: bash hooks/__tests__/hook-retire-when.guard.test.sh
set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

# The hook is the last ${CLAUDE_PLUGIN_ROOT} path of its command (the launcher is the first).
MISSING=$(jq -r '.hooks[][].hooks[].command | [scan("[$][{]CLAUDE_PLUGIN_ROOT[}]/[^\" ]+")] | last' "$ROOT/hooks/hooks.json" \
  | sort -u | while read -r p; do [ -f "$ROOT/${p#*\}/}" ] || echo "$p"; done)
[ -z "$MISSING" ] && ok "every registered hook file exists" || bad "registered but missing: $MISSING"

# Every hook names when it may be retired, so a kept guard always has an exit condition (issue 513). The line is
# "# Retire when: <condition>" with a condition of 12+ characters; a shorter or empty one is no condition.
RETIRE='^# Retire when: .{12,}'
lacking() { for f in "$1"/hooks/*.sh; do grep -Eq "$RETIRE" "$f" || echo "${f##*/}"; done; }
NONE=$(lacking "$ROOT")
[ -z "$NONE" ] && ok "every hook carries a Retire when condition" || bad "no Retire when line in: $(echo $NONE)"

FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
mkdir "$FX/hooks"
printf '#!/usr/bin/env bash\n# Retire when: the host runs this check itself\n' >"$FX/hooks/has.sh"
printf '#!/usr/bin/env bash\n# A hook with a header and no exit condition.\n' >"$FX/hooks/missing.sh"
printf '#!/usr/bin/env bash\n# Retire when:\n' >"$FX/hooks/empty.sh"
printf '#!/usr/bin/env bash\n# Retire when: soon\n' >"$FX/hooks/short.sh"
GOT=$(lacking "$FX" | sort | tr '\n' ' ')
[ "$GOT" = "empty.sh missing.sh short.sh " ] && ok "fixture: only the hooks with a good Retire when line pass" || bad "fixture lacking: $GOT"
case " $GOT " in *" missing.sh "*) ok "a hook with no Retire when line fails the guard" ;; *) bad "a hook with no Retire when line fails the guard" ;; esac
case " $GOT " in *" empty.sh "*) ok "an empty Retire when condition fails the guard" ;; *) bad "an empty Retire when condition fails the guard" ;; esac

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
