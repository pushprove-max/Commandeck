#!/usr/bin/env bash
# cos-tell.test.sh -- Orca answers `terminal list` in two shapes: `.result` is
# the list itself, or an object holding it in `.terminals`. A script that reads
# one shape only finds no pane under the other, and dictation to the Chief of
# Staff then fails with the pane open. Every reader takes both.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
mkdir -p "$T/bin" "$T/main" "$T/ws"; git -C "$T/main" init -q
cat > "$T/bin/orca-ide" <<ORCA
#!/usr/bin/env bash
case "\$1 \$2" in
  "terminal list") cat "$T/list.json" ;;
  "terminal send") echo "\$*" >> "$T/sent" ;;
esac
ORCA
chmod +x "$T/bin/orca-ide"
tell() { ( cd "$T/main" && PATH="$T/bin:$PATH" COMMANDECK_MAIN="$T/main" COMMANDECK_WORKSPACES="$T/ws" bash "$ROOT/scripts/cos-tell.sh" "$@" 2>&1 ); }
PANES=$(jq -cn --arg wt "$T/ws/Chief-of-Staff" '[{handle: "term_other", worktreePath: "/x", agentIdentity: "claude"}, {handle: "term_cos", worktreePath: $wt, agentIdentity: "claude"}]')

jq -cn --argjson p "$PANES" '{result: {terminals: $p}}' > "$T/list.json"
check "the pane is found in an object-shaped list" term_cos "$(tell --handle)"
jq -cn --argjson p "$PANES" '{result: $p}' > "$T/list.json"
check "and in an array-shaped list" term_cos "$(tell --handle)"
tell hello there >/dev/null
check "text is sent to it" 1 "$(grep -c -- '--terminal term_cos --text \[dictated\] hello there' "$T/sent" 2>/dev/null)"
echo '{"result": []}' > "$T/list.json"
tell --handle >/dev/null; check "no pane is exit 1" 1 $?

# The same read in every script: none takes the object shape alone.
check "no script reads .result.terminals without the array shape" "" \
  "$(grep -rn '[.]result[.]terminals\[' "$ROOT/scripts" "$ROOT/hooks" --exclude-dir=__tests__ | cut -d: -f1 | sort -u | sed "s|$ROOT/||" | paste -sd' ' -)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
