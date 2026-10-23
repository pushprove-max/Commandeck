#!/usr/bin/env bash
# codex-parity.guard.test.sh -- Codex and Claude must run the same guards. The
# plugin's hooks.json is the one list; Codex reaches it through five entries in
# its own hooks.json, each pointing at codex-dispatch.sh. This guard fails when
# the two drift: an entry the template lacks, an event the dispatcher dropped,
# an event hooks.json gained that Codex would silently never see, a skip
# marker on a hook nothing registers, or a template Codex would refuse to
# trust.
set -uo pipefail
SOURCE=$(cd "$(dirname "$0")/../.." && pwd)
TPL=$SOURCE/templates/codex-hooks.json DISP=$SOURCE/hooks/codex-dispatch.sh REG=$SOURCE/hooks/hooks.json
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }
EVENTS=(SessionStart UserPromptSubmit PreToolUse PostToolUse Stop)
# Events Claude Code sends that Codex has no counterpart for. Adding one here is a decision, not a fix.
CLAUDE_ONLY='["PostToolUseFailure"]'

for e in "${EVENTS[@]}"; do
  check "the template sends $e to the dispatcher" 1 \
    "$(jq --arg e "$e" '[.hooks[$e][]?.hooks[]? | select(.type == "command" and (.command | contains("__PLUGIN_ROOT__/hooks/codex-dispatch.sh")))] | length' "$TPL" 2>/dev/null)"
  check "the dispatcher handles $e" true "$(grep -v '^[[:space:]]*#' "$DISP" 2>/dev/null | grep -qE "^[[:space:]]*([A-Za-z|]*\|)?$e(\|[A-Za-z|]*)?\)" && echo true || echo false)"
done
check "the template sends nothing else" "$(printf '%s\n' "${EVENTS[@]}" | sort | tr '\n' ' ')" "$(jq -r '.hooks | keys[]' "$TPL" 2>/dev/null | sort | tr '\n' ' ')"
check "every event the plugin registers reaches Codex or is listed as Claude-only" '[]' \
  "$(jq -c --argjson c "$CLAUDE_ONLY" --argjson e "$(printf '%s\n' "${EVENTS[@]}" | jq -R . | jq -cs .)" '(.hooks | keys) - $e - $c' "$REG")"
check "every registered hook file exists" '' \
  "$(jq -r '.hooks[][].hooks[].command' "$REG" | grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' | sed 's/^\${CLAUDE_PLUGIN_ROOT}\///' | sort -u | while read -r f; do [ -x "$SOURCE/$f" ] || echo "$f"; done)"
check "every codex: skip marker is on a registered hook" '' \
  "$(grep -l '^# codex: skip' "$SOURCE"/hooks/*.sh | while read -r f; do grep -qF "/hooks/${f##*/}\\\"" "$REG" || echo "${f##*/}"; done)"

# Codex runs a hook only once its hash is in config.toml: the template, installed, must be one the trust script accepts.
mkdir -p "$T/codex"
sed "s|__PLUGIN_ROOT__|$SOURCE|g" "$TPL" > "$T/codex/hooks.json" 2>/dev/null
: > "$T/codex/config.toml"
python3 "$SOURCE/scripts/codex-hook-trust.py" "$T/codex" >"$T/trust.out" 2>&1; check "the trust script accepts the installed template" 0 $?
check "and records one trusted hash per event" 5 "$(grep -c '^trusted_hash = "sha256:' "$T/codex/config.toml")"
# Another tool's hook in the same file is the owner's to review: the plugin never vouches for it.
jq '.hooks.PreToolUse += [{"matcher": "*", "hooks": [{"type": "command", "command": "/opt/other/hook.sh"}]}]' "$T/codex/hooks.json" > "$T/h.json" && cp "$T/h.json" "$T/codex/hooks.json"
python3 "$SOURCE/scripts/codex-hook-trust.py" "$T/codex" > "$T/trust2.out" 2>&1
check "a hook that is not the plugin's gets no trust entry" 5 "$(grep -c '^trusted_hash = "sha256:' "$T/codex/config.toml")"

# Issue 315: another tool's update rewrites its hook, and a modified hook drops out of trust and opens every Codex
# pane on the review menu. --all trusts every hook in the home, so a launch can re-trust before it starts the pane.
TR="python3 $SOURCE/scripts/codex-hook-trust.py"
sha() { shasum "$T/codex/config.toml" | cut -d' ' -f1; }
BEFORE=$(sha); $TR --list --all "$T/codex" > "$T/list.out" 2>&1
check "--list names the other tool's hook, and writes nothing" "1:$BEFORE" "$(grep -c '/opt/other/hook.sh' "$T/list.out"):$(sha)"
$TR --all "$T/codex" > "$T/all.out" 2>&1; check "--all trusts the other tool's hook too" "0:6" "$?:$(grep -c '^trusted_hash = "sha256:' "$T/codex/config.toml")"
jq '.hooks.PreToolUse[-1].hooks[0].command = "/opt/other/hook-v2.sh"' "$T/codex/hooks.json" > "$T/h.json" && cp "$T/h.json" "$T/codex/hooks.json"
$TR --check "$T/codex" > "$T/c1.out" 2>&1; check "the plugin-only check ignores a modified hook that is not the plugin's" 0 $?
$TR --check --all "$T/codex" > "$T/c2.out" 2>&1; RC=$?
check "--check --all fails on it, saying modified and naming the hook" "1:1" "$RC:$(grep -c 'hook-v2.sh.* is modified' "$T/c2.out")"
$TR --all "$T/codex" > "$T/all2.out" 2>&1
$TR --check --all "$T/codex" > "$T/c3.out" 2>&1
check "a launch's --all re-trusts the modified hook in place, adding no entry" "0:6" "$?:$(grep -c '^trusted_hash = "sha256:' "$T/codex/config.toml")"
jq '.hooks.Stop[0].hooks += [{"type": "agent", "prompt": "x"}]' "$T/codex/hooks.json" > "$T/h.json" && cp "$T/h.json" "$T/codex/hooks.json"
$TR --all "$T/codex" > "$T/all3.out" 2>&1; check "--all reports a hook of a shape it cannot hash instead of guessing" "1:1" "$?:$(grep -c 'Stop\[0\].hooks\[1\] (type agent)' "$T/all3.out")"
jq 'del(.hooks.Stop[0].hooks[1])' "$T/codex/hooks.json" > "$T/h.json" && cp "$T/h.json" "$T/codex/hooks.json"
$TR --forget --all "$T/codex" > "$T/forget.out" 2>&1
check "--forget takes out the plugin's entries only, even with --all" "1" "$(grep -c '^trusted_hash = "sha256:' "$T/codex/config.toml")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
