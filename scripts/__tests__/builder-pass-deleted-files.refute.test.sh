#!/usr/bin/env bash
# Codex refuses an input over 1048576 characters, and a branch that deletes a
# folder of files passed it: the pass committed, sent nothing and no reviewer
# read a line. Past the hard limit a deleted file is named and its old text
# left out; what the branch adds or changes still goes whole.
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
echo base > "$T/repo/a"
echo OLD-TEXT-OF-A-DELETED-FILE > "$T/repo/gone"
git -C "$T/repo" add a gone
git -C "$T/repo" commit -qm base
git -C "$T/repo" worktree add -qb builder/u "$T/ws/u"
mkdir -p "$T/ws/u/.claude/briefs"
echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$T/ws/u/.claude/settings.local.json"
echo '.claude/settings.local.json' >> "$T/repo/.git/info/exclude"
echo built > "$T/ws/u/a"
rm "$T/ws/u/gone"
HOME="$T/home" CODEX_HOME="$T/codex" COMMANDECK_MAIN="$T/repo" \
COMMANDECK_WORKSPACES="$T/ws" COMMANDECK_ROUTING="$T/routing.json" \
PROBE_MARKER="$T/called" COMMANDECK_PASS_DIFF_MAX=1 COMMANDECK_PASS_DIFF_HARD=1 \
bash "$REAL/scripts/builder-codex-pass.sh" u 1 adversarial || :
P=$T/ws/u/.claude/briefs/u-r1-prompt-1.md
grep -q '^deleted file mode' "$P" || { echo "FAIL: the prompt does not name the deleted file" >&2; exit 1; }
! grep -q OLD-TEXT-OF-A-DELETED-FILE "$P" || { echo "FAIL: past the hard limit the prompt still carries a deleted file's text" >&2; exit 1; }
grep -qx -- '+built' "$P" || { echo "FAIL: the prompt lost a changed line" >&2; exit 1; }
echo "PASS: past the hard limit a deleted file is named in the prompt and its text left out"
