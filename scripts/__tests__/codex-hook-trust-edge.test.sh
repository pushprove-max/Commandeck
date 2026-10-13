#!/usr/bin/env bash
# codex-hook-trust-edge.test.sh -- Codex will not start on a config.toml it
# cannot parse, and the doctor's "codex trust" line is what the owner goes by.
# What this pins: a config whose last line has no newline keeps one hash per
# hook when the hash is rewritten, and a check with no config.toml at all
# fails, since no hook in it can be trusted.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $1 (expected [$2], got [$3])"; fi; }

H=$T/cx; mkdir -p "$H"
jq -n '{hooks: {PreToolUse: [{hooks: [{type: "command", command: "S=/p/hooks/codex-dispatch.sh; bash \"$S\" pre"}]}]}}' > "$H/hooks.json"
printf '[hooks.state."%s:pre_tool_use:0:0"]\ntrusted_hash = "sha256:old"' "$H/hooks.json" > "$H/config.toml"
python3 "$ROOT/scripts/codex-hook-trust.py" "$H" >"$T/out" 2>&1; check "the hash is rewritten" 0 $?
check "the block holds one hash, the new one" "1 0" "$(grep -c '^trusted_hash' "$H/config.toml") $(grep -c 'sha256:old' "$H/config.toml")"
check "and the file is still TOML" ok "$(python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb")); print("ok")' "$H/config.toml" 2>&1 | tail -1)"
python3 "$ROOT/scripts/codex-hook-trust.py" --check "$H" >/dev/null 2>&1; check "the check then passes" 0 $?
# TOML may indent a table. The owner's, right after the plugin's block, is not part of it.
printf '  [owner.table]\n  keep = true\n' >> "$H/config.toml"
python3 "$ROOT/scripts/codex-hook-trust.py" --forget "$H" >/dev/null 2>&1; check "the trust is forgotten" 0 $?
check "the plugin's block is gone and the owner's indented table is whole" "0 1 1" \
  "$(grep -c 'hooks.state' "$H/config.toml") $(grep -c '\[owner.table\]' "$H/config.toml") $(grep -c 'keep = true' "$H/config.toml")"
# A table header may carry a comment or spaces. It is still the hook's table,
# and a second table of the same name is a file Codex will not start on.
for head in '[hooks.state."%s:pre_tool_use:0:0"]   # reviewed' '[ hooks . state . "%s:pre_tool_use:0:0" ]'; do
  # shellcheck disable=SC2059  # the header is the format
  printf "$head"'\ntrusted_hash = "sha256:old"\n' "$H/hooks.json" > "$H/config.toml"
  python3 "$ROOT/scripts/codex-hook-trust.py" "$H" >/dev/null 2>&1
  check "a header written as ${head%%\"*} keeps one table and one hash, the new one" "1 1 0 ok" \
    "$(grep -c 'state' "$H/config.toml") $(grep -c 'trusted_hash' "$H/config.toml") $(grep -c 'sha256:old' "$H/config.toml") $(python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb")); print("ok")' "$H/config.toml" 2>&1 | tail -1)"
  python3 "$ROOT/scripts/codex-hook-trust.py" --check "$H" >/dev/null 2>&1; check "and the check passes" 0 $?
done
# The hash that counts is the value of trusted_hash. The right one in a
# comment beside a wrong value is not trust.
GOOD=$(grep -o 'sha256:[0-9a-f]\{64\}' "$H/config.toml" | head -1)
printf '[hooks.state."%s:pre_tool_use:0:0"]\n# was %s\ntrusted_hash = "sha256:wrong"\n' "$H/hooks.json" "$GOOD" > "$H/config.toml"
python3 "$ROOT/scripts/codex-hook-trust.py" --check "$H" >/dev/null 2>&1; check "the right hash in a comment only does not pass the check" no "$([ $? = 0 ] && echo yes || echo no)"
python3 "$ROOT/scripts/codex-hook-trust.py" "$H" >/dev/null 2>&1
check "and a plain run writes the value" 1 "$(grep -c "^trusted_hash = \"$GOOD\"" "$H/config.toml")"
# The same table written a way this script does not edit (dotted keys): a
# block added beside it would not parse, so nothing is written and it says so.
printf 'hooks.state."%s:pre_tool_use:0:0".enabled = true\n' "$H/hooks.json" > "$H/config.toml"; cp "$H/config.toml" "$T/keep.toml"
python3 "$ROOT/scripts/codex-hook-trust.py" "$H" >"$T/out" 2>&1; check "a config the change would break is refused" no "$([ $? = 0 ] && echo yes || echo no)"
check "it is left as it was, and the refusal says why" "same 1" "$(cmp -s "$H/config.toml" "$T/keep.toml" && echo same || echo changed) $(grep -c 'would not parse' "$T/out")"
rm "$H/config.toml"
python3 "$ROOT/scripts/codex-hook-trust.py" --check "$H" >/dev/null 2>&1; check "with no config.toml the check fails" no "$([ $? = 0 ] && echo yes || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
