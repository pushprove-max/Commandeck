#!/usr/bin/env bash
set -euo pipefail
REAL=$(git rev-parse --show-toplevel)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
unset COMMANDECK_ALLOW_AGENT_GIT
mkdir -p "$T/home/.claude/plugins/cache/openai-codex/codex/1/scripts" "$T/home/.claude/plugins/cache/openai-codex/codex/1/prompts" "$T/ws"
# The pass has no prompt but the installed plugin's.
printf '{{TARGET_LABEL}} {{USER_FOCUS}}\nPrefer one strong finding over several weak ones.\n<structured_output_contract>\njson\n</structured_output_contract>\n{{REVIEW_COLLECTION_GUIDANCE}}\n{{REVIEW_INPUT}}\n' \
  > "$T/home/.claude/plugins/cache/openai-codex/codex/1/prompts/adversarial-review.md"
cat > "$T/home/.claude/plugins/cache/openai-codex/codex/1/scripts/codex-companion.mjs" <<'JS'
import { writeFileSync } from "node:fs";
writeFileSync(process.env.PROBE_MARKER, "called");
JS
# Each reviewer gets a broker of its own; this one only has to come up.
cat > "$T/home/.claude/plugins/cache/openai-codex/codex/1/scripts/app-server-broker.mjs" <<'JS'
import { writeFileSync } from "node:fs";
writeFileSync(process.argv[process.argv.indexOf("--endpoint") + 1].replace(/^unix:/, ""), "");
setInterval(() => {}, 1000);
JS
printf '{"roles":{"codex-reviewer":{"model":"gpt-9-probe","effort":"high","fast":false}}}\n' > "$T/routing.json"
git init -q -b main "$T/repo"
git -C "$T/repo" config user.name test
git -C "$T/repo" config user.email test@example.com
git -C "$T/repo" config core.hooksPath /dev/null
git -C "$T/repo" commit -qm base --allow-empty
git -C "$T/repo" worktree add -qb builder/u "$T/ws/u"
echo '.claude/settings.local.json' >> "$T/repo/.git/info/exclude"
mkdir -p "$T/ws/u/.claude/briefs" "$T/ws/u/src/__tests__"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$T/ws/u/.claude/settings.local.json"
cat > "$T/ws/u/src/__tests__/example.guard.test.ts" <<'TS'
import { test } from 'node:test';
import assert from 'node:assert/strict';
test('required environment is configured', () => {
  assert.equal(process.env.REQUIRED_SETTING, 'enabled');
});
TS
echo 'Mutation-verified: removed REQUIRED_SETTING; the guard failed.' \
  > "$T/ws/u/.claude/briefs/u-evidence.md"
HOME="$T/home" CODEX_HOME="$T/codex" COMMANDECK_MAIN="$T/repo" \
COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_ROUTING="$T/routing.json" \
PROBE_MARKER="$T/called" \
bash "$REAL/scripts/builder-codex-pass.sh" u 1 adversarial || :
git -C "$T/ws/u" cat-file -e HEAD:src/__tests__/example.guard.test.ts
test -f "$T/called"
