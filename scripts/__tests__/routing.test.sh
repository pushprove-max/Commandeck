#!/usr/bin/env bash
# config/routing.json ships to other people's machines, so it names model
# families only: a pinned version goes stale the day a newer one ships, and a
# [1m] context bills a plan that may not have it. The five roles are the ones
# the Builder flow launches; a missing one stops a launch or a review pass.
# The resolver in paths.sh accepts versions and contexts (the source project
# uses both), so those two rules are checked here.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
CFG=$REAL/config/routing.json
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
. "$REAL/scripts/paths.sh" || exit 1
RT_READONLY=

# lint <file> -- 0 when the file holds the five roles, families only, no context.
lint() {
  jq -e '
    (["orchestrator", "builder", "codex-reviewer", "claude-reviewer", "design-coauthor"] - (.roles | keys) | length == 0)
    and ([.roles[] | .model, (.advisor // "x") | test("^[a-z]+$")] | all)
    and ([.roles[] | has("context")] | any | not)' "$1" >/dev/null 2>&1
}
valid() { COMMANDECK_ROUTING=$1 pp_routing_valid >/dev/null 2>&1; echo $?; }
mutant() { jq "$1" "$CFG" > "$TMP/m.json"; }

# A Codex family resolves against the account's model list at launch; the
# fixture list stands in for it.
export CODEX_HOME=$TMP/codex; mkdir -p "$CODEX_HOME"
printf '{"models":[{"slug":"gpt-7.2-sol"},{"slug":"gpt-7.10-sol"},{"slug":"gpt-8-luna"}]}\n' > "$CODEX_HOME/models_cache.json"
check "the shipped file validates in the resolver" 0 "$(valid "$CFG")"
check "the shipped file passes the lint" 0 "$(lint "$CFG"; echo $?)"
for r in builder codex-reviewer claude-reviewer orchestrator design-coauthor; do
  RT_AGENT= RT_MODEL= RT_EFFORT=
  COMMANDECK_ROUTING=$CFG pp_route "$r" 2>/dev/null
  check "$r resolves an agent and a model" yes "$([ -n "$RT_AGENT" ] && [ -n "$RT_MODEL" ] && echo yes || echo no)"
done
COMMANDECK_ROUTING=$CFG pp_route codex-reviewer; check "codex-reviewer is a Codex seat" codex "$RT_AGENT"
check "a Codex pane launches on the family's newest model id, never the bare family" "gpt-7.10-sol 1" \
  "$RT_MODEL $(grep -c -- '--model gpt-7.10-sol ' <<<"$RT_CMD ")"
check "a family the account does not list stops the launch" 2 "$(CODEX_HOME=$TMP/none COMMANDECK_ROUTING=$CFG pp_route codex-reviewer >/dev/null 2>&1; echo $?)"
check "an explicit model override is used as written" gpt-1-x "$(COMMANDECK_ROUTING=$CFG pp_route_json codex-reviewer "" gpt-1-x | jq -r .model)"
check "codex-reviewer carries an effort" yes "$([ -n "$RT_EFFORT" ] && echo yes || echo no)"
check "codex-reviewer is read-only" 1 "$RT_READONLY"
COMMANDECK_ROUTING=$CFG pp_route claude-reviewer; check "claude-reviewer is a Claude seat" claude "$RT_AGENT"
check "claude-reviewer runs at high effort" high "$RT_EFFORT"
check "claude-reviewer is read-only" 1 "$RT_READONLY"
REVIEWER_MODEL=$RT_MODEL
check "claude-reviewer is headless" 'claude -p' "$(COMMANDECK_ROUTING=$CFG pp_argv claude-reviewer | paste -sd' ' - | grep -o 'claude -p')"
COMMANDECK_ROUTING=$CFG pp_route builder
check "the Claude reviewer is a different family than the Builder" yes "$([ "$REVIEWER_MODEL" != "$RT_MODEL" ] && echo yes || echo no)"
check "no role is boxed: the pane box is not part of the plugin" 0 "$(jq '[.roles[] | select((.headless or .unboxed) | not)] | length' "$CFG")"

mutant '.roles.builder.model = "claude-opus-5-5"'
check "a version-suffixed Claude model fails" 1 "$(lint "$TMP/m.json"; echo $?)"
mutant '.roles["codex-reviewer"].model = "gpt-6.1-sol"'
check "a version-suffixed Codex model fails" 1 "$(lint "$TMP/m.json"; echo $?)"
mutant '.roles.builder.advisor = "claude-fable-5-1"'
check "a version-suffixed advisor fails" 1 "$(lint "$TMP/m.json"; echo $?)"
for r in orchestrator builder; do
  mutant ".roles[\"$r\"].context = \"1m\""
  check "a 1m context on $r still validates in the resolver" 0 "$(valid "$TMP/m.json")"
  check "a 1m context on $r fails the lint" 1 "$(lint "$TMP/m.json"; echo $?)"
done
for r in orchestrator builder codex-reviewer claude-reviewer design-coauthor; do
  mutant "del(.roles[\"$r\"])"
  check "a file without $r fails" 1 "$(lint "$TMP/m.json"; echo $?)"
done

# A leak word in a note fails the leak test, which reads the word list itself.
mkdir -p "$TMP/tree/config"
cp "$CFG" "$TMP/tree/config/routing.json"
check "the shipped notes are clean" 0 "$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1; echo $?)"
N=0
for w in 'Push''Prove' 'M''ax ruling' 'see #''1481'; do
  N=$((N + 1))
  jq --arg w "$w" '.roles.builder.note += " " + $w' "$CFG" > "$TMP/tree/config/routing.json"
  check "leak word $N in a note fails" 1 "$(bash "$REAL/ci/leak-test.sh" "$TMP/tree" >/dev/null 2>&1; echo $?)"
done

# Codex behind a proxy (#42): its models_cache.json is empty or stale, and the proxy's own list is the
# account's. A GitHub Copilot API proxy runs on this machine and signs in by itself: no key is sent.
# A regular proxy wants the key its provider's env_key names, as a bearer token. The fake curl
# answers both from canned lists, and anything else as no route: no case reaches the network.
mkdir -p "$TMP/bin" "$TMP/proj/.claude"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"; h=; [[ " $* " != *" -H @- "* ]] || h=$(cat)
case "${@: -1}" in
  http://localhost:4141/v1/models) echo '{"object":"list","data":[{"id":"gpt-6-sol"},{"id":"gpt-6.1-sol"},{"id":"claude-sonnet-x"}]}' ;;
  https://llm.example.test/v1/models) [ "$h" = 'Authorization: Bearer k-123' ] || exit 22; echo '{"data":[{"id":"gpt-7-sol"},{"id":"gpt-6.9-sol"}]}' ;;
  *) exit 7 ;;
esac
EOF
chmod +x "$TMP/bin/curl"
export CURL_LOG=$TMP/curl.log
PX=$TMP/px; mkdir -p "$PX"
copilot() { printf 'model = "gpt-6.1-sol"\nmodel_provider = "copilot"\n\n[model_providers.copilot]\nname = "Copilot API"\nbase_url = "http://localhost:4141/v1"\nwire_api = "chat"\n' > "$PX/config.toml"; }
regular() { printf 'model_provider = "corp"\nservice_tier = "fast"\n[model_providers.corp]\nbase_url = "https://llm.example.test/v1"\nenv_key = "CORP_KEY"\n' > "$PX/config.toml"; }
stale() { printf '{"models":[{"slug":"gpt-5-sol"}]}\n' > "$PX/models_cache.json"; }
cm() { : > "$CURL_LOG"; PATH=$TMP/bin:$PATH CODEX_HOME=$PX PP_MAIN=$TMP/proj pp_codex_model "$@" 2>"$TMP/err"; }
copilot; echo '{}' > "$PX/models_cache.json"
check "behind a Copilot API proxy the family is the proxy list's newest" gpt-6.1-sol "$(cm sol)"
check "and the Copilot proxy is asked with no key" "0 1" "$(grep -c Authorization "$CURL_LOG") $(grep -c 'localhost:4141/v1/models' "$CURL_LOG")"
regular; stale
check "behind a regular proxy, with its key, the family is that proxy list's newest" gpt-7-sol "$(CORP_KEY=k-123 cm sol)"
check "and the key is sent on stdin, never on curl's command line" 0 "$(grep -c k-123 "$CURL_LOG")"
check "a proxy that refuses (no key) falls back to models_cache.json" gpt-5-sol "$(cm sol)"
# Every TOML form a provider is written in reads the same: literal strings, comments, quoted names,
# dotted keys, an inline table. One that went unread would fall back to the stale cache in silence.
form() { printf "$1" > "$PX/config.toml"; CORP_KEY=k-123 cm sol; }
check "single-quoted (literal) strings" gpt-7-sol "$(form "model_provider = 'corp'\n[model_providers.corp]\nbase_url = 'https://llm.example.test/v1'\nenv_key = 'CORP_KEY'\n")"
check "a comment after a header and after a value" gpt-7-sol "$(form 'model_provider = "corp" # mine\n[model_providers.corp] # the proxy\nbase_url = "https://llm.example.test/v1" # here\nenv_key = "CORP_KEY"\n')"
check "a quoted provider name" gpt-7-sol "$(form 'model_provider = "corp"\n[model_providers."corp"]\nbase_url = "https://llm.example.test/v1"\nenv_key = "CORP_KEY"\n')"
check "dotted keys at the top level" gpt-7-sol "$(form 'model_provider = "corp"\nmodel_providers.corp.base_url = "https://llm.example.test/v1"\nmodel_providers.corp.env_key = "CORP_KEY"\n')"
check "dotted keys under [model_providers]" gpt-7-sol "$(form 'model_provider = "corp"\n[model_providers]\ncorp.base_url = "https://llm.example.test/v1"\ncorp.env_key = "CORP_KEY"\n')"
check "an inline table" gpt-7-sol "$(form 'model_provider = "corp"\nmodel_providers.corp = { name = "Corp", base_url = "https://llm.example.test/v1", env_key = "CORP_KEY" }\n')"
check "a model_provider inside another table is not the top-level one" gpt-5-sol "$(form '[profiles.x]\nmodel_provider = "corp"\n[model_providers.corp]\nbase_url = "https://llm.example.test/v1"\nenv_key = "CORP_KEY"\n')"
check "a quoted provider name holding a dot" gpt-7-sol "$(form "model_provider = 'corp.proxy'\n[model_providers.'corp.proxy']\nbase_url = 'https://llm.example.test/v1'\nenv_key = 'CORP_KEY'\n")"
check "\"base_url =\" inside another value is text, not the URL" gpt-7-sol \
  "$(form "model_provider = 'corp'\nmodel_providers.corp = { name = 'base_url = \"https://wrong.example/v1\"', base_url = 'https://llm.example.test/v1', env_key = 'CORP_KEY' }\n")"
check "and no request went to the URL in that text" 0 "$(grep -c wrong.example "$CURL_LOG")"
check "a config.toml that does not parse is no proxy" gpt-5-sol "$(form 'model_provider = "corp\n[model_providers.corp]\nbase_url = "https://llm.example.test/v1"\n')"
# No tomllib (Python older than 3.11): no guessing at the file. It says so, and reads as no proxy.
mkdir -p "$TMP/nopy"; printf '#!/usr/bin/env bash\necho "ModuleNotFoundError: No module named tomllib" >&2\nexit 1\n' > "$TMP/nopy/python3"; chmod +x "$TMP/nopy/python3"
copilot; stale; : > "$CURL_LOG"
check "with no tomllib the proxy is not read: the cache is used, no proxy asked" "gpt-5-sol 0" \
  "$(PATH=$TMP/nopy:$TMP/bin:$PATH CODEX_HOME=$PX PP_MAIN=$TMP/proj pp_codex_model sol 2>"$TMP/err") $(wc -l < "$CURL_LOG" | tr -d ' ')"
check "and it says plainly that proxy discovery needs Python 3.11 or newer" 1 "$(grep -c 'proxy model discovery needs Python 3.11 or newer' "$TMP/err")"
check "and doctor's and setup's route line says the same" "Codex's proxy setting was not read: proxy model discovery needs Python 3.11 or newer" \
  "$(PATH=$TMP/nopy:$PATH CODEX_HOME=$PX pp_codex_route)"
check "a commented-out provider is none" gpt-5-sol "$(form '# model_provider = "corp"\n[model_providers.corp]\nbase_url = "https://llm.example.test/v1"\n')"
printf 'model_provider = "gone"\n[model_providers.gone]\nbase_url = "http://127.0.0.1:9/v1"\n' > "$PX/config.toml"
check "a proxy that does not answer falls back to models_cache.json" gpt-5-sol "$(cm sol)"
rm "$PX/models_cache.json"
check "with neither list, the family fails" 2 "$(cm sol >/dev/null; echo $?)"
check "and the refusal names the proxy and the setup answer that fixes it" "1 1" \
  "$(grep -c 'through the proxy http://127.0.0.1:9/v1' "$TMP/err") $(grep -c 'setup.sh --codex-model codex-reviewer=<model id>' "$TMP/err")"
printf 'service_tier = "fast"\n' > "$PX/config.toml"
check "with no proxy, the refusal says Codex goes direct and names the same answer" 2 "$(cm sol >/dev/null; echo $?)"
check "and no proxy is asked" "1 0" "$(grep -c 'Codex goes direct to its provider' "$TMP/err") $(wc -l < "$CURL_LOG" | tr -d ' ')"
# The setup answer is the project's own, so a plugin update keeps it, and it wins over everything.
echo '{"codexModels":{"codex-reviewer":"gpt-6.1-sol"}}' > "$TMP/proj/.claude/commandeck.json"
check "the project's saved model id for the role is used, with no list at all" gpt-6.1-sol "$(cm sol codex-reviewer)"
check "and asks no proxy" 0 "$(wc -l < "$CURL_LOG" | tr -d ' ')"
check "another role is not given it" 2 "$(cm sol other-role >/dev/null; echo $?)"
# A hand edit of the installed routing.json (a stopgap the next update may replace) names an id.
jq '.roles["codex-reviewer"].model = "gpt-5.5-sol"' "$CFG" > "$TMP/hand.json"
check "the saved answer wins over a hand-edited model id in routing.json" gpt-6.1-sol \
  "$(PATH=$TMP/bin:$PATH CODEX_HOME=$PX PP_MAIN=$TMP/proj COMMANDECK_ROUTING=$TMP/hand.json pp_route_json codex-reviewer | jq -r .model)"
rm "$TMP/proj/.claude/commandeck.json"
check "with no saved answer the hand-edited id is used as written" gpt-5.5-sol \
  "$(PATH=$TMP/bin:$PATH CODEX_HOME=$PX PP_MAIN=$TMP/proj COMMANDECK_ROUTING=$TMP/hand.json pp_route_json codex-reviewer | jq -r .model)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
