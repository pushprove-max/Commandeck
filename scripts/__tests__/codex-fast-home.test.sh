#!/usr/bin/env bash
# Codex fast mode is offered, and a fast-mode project's passes are let run, only when the Codex home's config.toml
# runs Codex on the fast tier. A wrong yes runs every review pass on the slow tier unannounced; a wrong no refuses a
# home that is set up. So the setting is read as TOML, the way Codex reads it: any spelling of the key, and the
# default profile's own setting over the top-level one; a key in a profile Codex does not use says nothing.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export CODEX_HOME=$T
# fast <config.toml text> -> yes or no
fast() { printf '%s\n' "$1" > "$T/config.toml"; (source "$ROOT/scripts/paths.sh" && pp_codex_fast_home) 2>/dev/null && echo yes || echo no; }
check "the plain top-level line" yes "$(fast 'service_tier = "fast"')"
check "a quoted key" yes "$(fast '"service_tier" = "fast"')"
check "a literal string" yes "$(fast "service_tier = 'fast'")"
check "another tier" no "$(fast 'service_tier = "flex"')"
check "the line only in a profile Codex does not use" no "$(fast $'model = "x"\n[profiles.work]\nservice_tier = "fast"')"
check "the line in the default profile" yes "$(fast $'profile = "work"\n[profiles.work]\nservice_tier = "fast"')"
check "the default profile sets another tier over the top-level fast" no "$(fast $'profile = "work"\nservice_tier = "fast"\n[profiles.work]\nservice_tier = "flex"')"
check "the line inside a multi-line string" no "$(fast $'notes = """\nservice_tier = "fast"\n"""')"
check "a config.toml that does not parse" no "$(fast $'service_tier = "fast"\n[')"
rm "$T/config.toml"
check "no config.toml" no "$( (source "$ROOT/scripts/paths.sh" && pp_codex_fast_home) 2>/dev/null && echo yes || echo no)"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
