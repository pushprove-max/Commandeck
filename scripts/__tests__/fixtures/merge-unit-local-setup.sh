# The fixture merge-unit-local.test.sh and the merge-queue tests (through merge-queue-setup.sh) share: a scratch project, stub orca-ide and gh,
# and the real pass script run under a stub Codex. Sourced, with REAL, PASS, FAIL and check set by the caller.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
# An empty HOME: no Codex plugin, no model list, no signed-in CLI.
export HOME=$TMP/home CODEX_HOME=$TMP/codex COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
# Run by hand from a Claude session the merge would detach itself (issue 230); the case for that unsets this.
export COMMANDECK_FOREGROUND=1
# Run as a real merge's check, the file inherits that merge's lock flag, which would skip its own merges' detach
# and lock. Claude's folder is the empty HOME's: the caller's own profile is never read.
unset COMMANDECK_MAIN COMMANDECK_ROUTING MERGE_UNIT_LOCAL_LOCK CLAUDE_CONFIG_DIR "${!UNIT_LEDGER_@}"
REPO=$TMP/proj
mkdir -p "$HOME" "$TMP/ws" "$TMP/bin"; : > "$TMP/orca-calls"
git init -q -b main "$REPO"
MERGE=$REAL/scripts/merge-unit-local.sh PASS_SH=$REAL/scripts/builder-codex-pass.sh
git -C "$REPO" config user.name t; git -C "$REPO" config user.email t@t; git -C "$REPO" config core.hooksPath /dev/null
echo base > "$REPO/a.txt"; git -C "$REPO" add a.txt; git -C "$REPO" commit -qm base
printf '%s\n' .claude/settings.local.json .claude/builder-events.jsonl >> "$REPO/.git/info/exclude"
cat > "$TMP/bin/orca-ide" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$TMP/orca-calls"
case "\$1 \$2" in
  "terminal list") echo '{"result":{"terminals":[{"handle":"t_'"\$(cat "$TMP/unit")"'","worktreePath":"$TMP/ws/'"\$(cat "$TMP/unit")"'"}]}}' ;;
  "worktree remove") [ ! -e "$TMP/remove-fails" ] || { echo "orca: the worktree is busy" >&2; exit 1; }
    git -C "\$(git -C "\${4#path:}" rev-parse --path-format=absolute --git-common-dir)" worktree remove --force "\${4#path:}" ;;
  *) echo '{"ok":true}' ;;
esac
STUB
# gh is never the real one: it records its calls and answers only `issue close`, and that fails once gh-fails exists.
printf '#!/usr/bin/env bash\necho "$*" >> "%s/gh-calls"\n[ "$1 $2" = "issue close" ] && [ ! -e "%s/gh-fails" ]\n' "$TMP" "$TMP" > "$TMP/bin/gh"
chmod +x "$TMP/bin/orca-ide" "$TMP/bin/gh"
PATH=$TMP/bin:$PATH

# A proven unit is one the pass script itself ran a first pass on: three
# reviewers ending GO. The pass runs under a home of its own, with a stub of the
# Codex plugin that leaves the session record Codex would; the merge then runs
# under the empty home above. STUB_REPLY is what each reviewer answers.
PH=$TMP/passhome PLUG=$TMP/passhome/.claude/plugins/cache/openai-codex/codex/1.0.0
mkdir -p "$PLUG/scripts" "$PLUG/prompts" "$CODEX_HOME" "$TMP/cli"
printf 'Target: {{TARGET_LABEL}}\nUser focus: {{USER_FOCUS}}\nPrefer one strong finding over several weak ones.\n<structured_output_contract>\nReturn only valid JSON matching the provided schema.\n</structured_output_contract>\n{{REVIEW_COLLECTION_GUIDANCE}}\n{{REVIEW_INPUT}}\n' > "$PLUG/prompts/adversarial-review.md"
cat > "$PLUG/scripts/codex-companion.mjs" <<'JS'
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
const args = process.argv.slice(2);
const cwd = args[args.indexOf("--cwd") + 1], promptFile = args[args.indexOf("--prompt-file") + 1];
const id = `${process.env.STUB_THREAD}-${promptFile.match(/-prompt-(\d+)\.md$/)[1]}`;
const reply = process.env.STUB_REPLY || "Clean.\nVERDICT: GO";
const sha = execFileSync("git", ["-C", cwd, "rev-parse", "HEAD"]).toString().trim();
const dir = `${process.env.CODEX_HOME}/sessions/2026/10/11`;
mkdirSync(dir, { recursive: true });
writeFileSync(`${dir}/rollout-2026-10-11T00-00-00-${id}.jsonl`, [
  { type: "session_meta", timestamp: new Date().toISOString(), payload: { id, cwd, git: { commit_hash: sha } } },
  { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: readFileSync(promptFile, "utf8") }] } },
  { type: "event_msg", timestamp: new Date().toISOString(), payload: { type: "task_complete", last_agent_message: reply } },
].map((r) => JSON.stringify(r)).join("\n") + "\n");
process.stdout.write(JSON.stringify({ threadId: id, status: 0, rawOutput: reply }));
JS
printf 'import { writeFileSync } from "node:fs";\nconst a = process.argv.slice(2);\nwriteFileSync(a[a.indexOf("--endpoint") + 1].replace(/^unix:/, ""), "");\nsetInterval(() => {}, 1000);\n' > "$PLUG/scripts/app-server-broker.mjs"
echo 1 > "$PLUG/scripts/commandeck-test-waits"
printf 'model = "x"\nservice_tier = "fast"\n' > "$CODEX_HOME/config.toml"
jq '.roles["codex-reviewer"].model = "gpt-9.9-probe"' "$REAL/config/routing.json" > "$TMP/routing.json"
# Signed in, and answers the pass's one-word sign-in probe (codex exec).
printf '#!/bin/sh\n[ "$*" = "login status" ] || [ "$1" = exec ]\n' > "$TMP/cli/codex"; chmod +x "$TMP/cli/codex"
mk() { # <unit> [subject]: a Builder worktree with one commit, its brief and its evidence
  local w=$COMMANDECK_WORKSPACES/$1
  git -C "$REPO" worktree add -q "$w" -b "builder/$1"
  mkdir -p "$w/.claude/briefs"; echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$w/.claude/settings.local.json"
  echo "brief for $1" > "$w/.claude/briefs/$1.md"; echo "evidence for $1" > "$w/.claude/briefs/$1-evidence.md"
  echo built > "$w/$1.txt"; git -C "$w" add "$1.txt"; git -C "$w" commit -qm "${2:-feat($1): the unit}"
}
pass() { # <unit> <N> <kind>: one pass of the real pass script on the unit's worktree
  (cd "$COMMANDECK_WORKSPACES/$1" && HOME=$PH TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO COMMANDECK_ROUTING=$TMP/routing.json STUB_THREAD=thr-$1-$2 \
    bash "$PASS_SH" "$1" "$2" "$3" >/dev/null 2>"$TMP/pass.err") || { echo "FAIL the $3 pass on $1 did not run: $(cat "$TMP/pass.err")"; FAIL=$((FAIL+1)); }
}
go() { pass "$1" 1 adversarial; } # <unit>: a first pass that ends GO at the unit's tip
merge() { echo "$1" > "$TMP/unit"; (cd "$REPO" && bash "$MERGE" "$@") > "$TMP/out" 2>&1; echo $?; }
