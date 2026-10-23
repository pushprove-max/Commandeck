# Sourced by builder-codex-pass.test.sh, builder-codex-pass-fresh-round.test.sh, builder-codex-pass-suite.test.sh,
# builder-codex-pass-closing.test.sh, builder-codex-pass-decisions.test.sh, builder-codex-pass-fresh-session.test.sh and
# builder-codex-pass-github.test.sh:
# a scratch repo with a Builder worktree, stubs of the Codex plugin, the Codex CLI and Orca, and the pass helpers.
# Seven files, not one: one file of every case ran 199 s alone at load ~150, past the runner's 120 s per-file cap, and
# the owner ruled that no file raises it.
REAL=$(cd "$(dirname "$0")/../.." && pwd)
PASS_SH=$REAL/scripts/builder-codex-pass.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
# Issue 301: a fresh-round helper a pass started outlives the file; the exit kills any that still names its folder.
trap 'pkill -f "$TMP/" 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME=$TMP/home CODEX_HOME=$TMP/codex COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
unset COMMANDECK_MAIN COMMANDECK_ROUTING CLAUDE_CONFIG_DIR
REPO=$TMP/proj U=unit
mkdir -p "$HOME" "$TMP/ws" "$TMP/cli" "$TMP/py" "$CODEX_HOME"

# A stub of the Codex plugin that leaves the session record Codex would (as in
# merge-unit-local.test.sh); STUB_THREAD names each pass's threads.
PLUG=$HOME/.claude/plugins/cache/openai-codex/codex/1.0.0
mkdir -p "$PLUG/scripts" "$PLUG/prompts"
printf 'Target: {{TARGET_LABEL}}\nUser focus: {{USER_FOCUS}}\nPrefer one strong finding over several weak ones.\n<structured_output_contract>\nReturn only valid JSON matching the provided schema.\n</structured_output_contract>\n{{REVIEW_COLLECTION_GUIDANCE}}\n{{REVIEW_INPUT}}\n' > "$PLUG/prompts/adversarial-review.md"
cat > "$PLUG/scripts/codex-companion.mjs" <<'JS'
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
const args = process.argv.slice(2);
const cwd = args[args.indexOf("--cwd") + 1], promptFile = args[args.indexOf("--prompt-file") + 1];
const id = `${process.env.STUB_THREAD}-${promptFile.match(/-prompt-(\d+)\.md$/)[1]}`;
const reply = process.env.STUB_REPLY || "Clean.\nVERDICT: GO";
const sha = execFileSync("git", ["-C", cwd, "rev-parse", "HEAD"]).toString().trim();
const dir = `${process.env.CODEX_HOME}/sessions/2026/10/14`;
mkdirSync(dir, { recursive: true });
writeFileSync(`${dir}/rollout-2026-10-14T00-00-00-${id}.jsonl`, [
  { type: "session_meta", timestamp: new Date().toISOString(), payload: { id, cwd, git: { commit_hash: sha } } },
  { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: readFileSync(promptFile, "utf8") }] } },
  { type: "event_msg", timestamp: new Date().toISOString(), payload: { type: "task_complete", last_agent_message: reply } },
].map((r) => JSON.stringify(r)).join("\n") + "\n");
// STUB_NOTIFY: the program Codex's notify setting runs at the turn's end, handed the turn as Codex hands it.
if (process.env.STUB_NOTIFY) execFileSync("bash", [process.env.STUB_NOTIFY,
  JSON.stringify({ type: "agent-turn-complete", "turn-id": id, "last-assistant-message": reply })], { stdio: "ignore" });
process.stdout.write(JSON.stringify({ threadId: id, status: 0, rawOutput: reply }));
JS
printf 'import { writeFileSync } from "node:fs";\nconst a = process.argv.slice(2);\nwriteFileSync(a[a.indexOf("--endpoint") + 1].replace(/^unix:/, ""), "");\nsetInterval(() => {}, 1000);\n' > "$PLUG/scripts/app-server-broker.mjs"
echo 1 > "$PLUG/scripts/commandeck-test-waits"
# The Codex stand-in: signed in by `login status`; a one-word exec request records where it ran and
# fails while $TMP/probe-fail holds a count above 0, the way a revoked sign-in does.
cat > "$TMP/cli/codex" <<EOF
#!/bin/sh
case "\$1" in
  login) [ "\$*" = "login status" ] ;;
  exec) echo "\$PWD" >> "$TMP/probe"; n=\$(cat "$TMP/probe-fail" 2>/dev/null || echo 0)
    [ "\$n" -gt 0 ] || exit 0; echo \$((n - 1)) > "$TMP/probe-fail"; echo 'ERROR: stream disconnected before completion' >&2; exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/cli/codex"
# Issue 316: the pass reads GitHub before any reviewer starts. The gh stand-in answers a read from the files under
# $TMP/gh (issue-<n>.txt, JSON with body and comments; api-<n>.json, the HTML GitHub renders for them; pr.txt) and
# fails with the text of $TMP/gh-fail, if there is one; it logs each call. Off a terminal, as here, a real gh issue view
# --comments prints the comments and no body. gh api serves the comments one a page, so only --paginate reads them all.
mkdir -p "$TMP/gh"
cat > "$TMP/cli/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$TMP/gh.log"
[ ! -e "$TMP/gh-fail" ] || { cat "$TMP/gh-fail" >&2; exit 1; }
case "\$*" in
  "repo view"*) echo '{"nameWithOwner":"o/proj"}' ;;
  "issue view "*) n=\$3; [ -e "$TMP/gh/issue-\$n.txt" ] || { echo "GraphQL: Could not resolve to an issue or pull request with the number of \$n." >&2; exit 1; }
    case "\$*" in *--json*) cat "$TMP/gh/issue-\$n.txt" ;; *) jq -r '.comments[].body' "$TMP/gh/issue-\$n.txt" ;; esac ;;
  "api "*) n=\$(echo "\$*" | sed -nE 's#.*/issues/([0-9]+)(/comments)?\$#\1#p'); f=$TMP/gh/api-\$n.json
    [ -n "\$n" ] && [ -e "\$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    case "\$*" in
      *--paginate*/comments) jq -c '.comments[] | [.]' "\$f" ;;
      */comments) jq -c '.comments[:1]' "\$f" ;;
      *) jq '{html_url, body_html}' "\$f" ;;
    esac ;;
  "pr view "*) [ -e "$TMP/gh/pr.txt" ] || { echo 'no pull requests found for branch "builder/unit"' >&2; exit 1; }; cat "$TMP/gh/pr.txt" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/cli/gh"
# routing.json names the family; the account's model list holds its ids.
printf 'model = "x"\n' > "$CODEX_HOME/config.toml"
printf '{"models":[{"slug":"gpt-5.2-sol"},{"slug":"gpt-6.1-sol"}]}\n' > "$CODEX_HOME/models_cache.json"
jq '.roles["codex-reviewer"].model = "sol"' "$REAL/config/routing.json" > "$TMP/routing.json"
export COMMANDECK_ROUTING=$TMP/routing.json

git init -q -b main "$REPO"
git -C "$REPO" config user.name t; git -C "$REPO" config user.email t@t; git -C "$REPO" config core.hooksPath /dev/null
git -C "$REPO" remote add origin https://github.com/o/proj.git
printf 'echo base\n' > "$REPO/a.sh"; mkdir -p "$REPO/.claude"; echo '{"reviewLoop":{"maxRounds":"5"}}' > "$REPO/.claude/commandeck.json"
git -C "$REPO" add a.sh .claude/commandeck.json; git -C "$REPO" commit -qm base
printf '%s\n' .claude/settings.local.json .claude/builder-events.jsonl >> "$REPO/.git/info/exclude"
git -C "$REPO" worktree add -q "$TMP/ws/$U" -b "builder/$U"
W=$TMP/ws/$U B=$TMP/ws/$U/.claude/briefs MAINBRIEF=$REPO/.claude/briefs/$U-builder-brief.md
mkdir -p "$B" "${MAINBRIEF%/*}"; echo '{"env":{"COMMANDECK_BUILDER":"1"}}' > "$W/.claude/settings.local.json"
# The launcher's brief in main's checkout: a first pass of one reviewer, a small build not launched risky.
printf 'Fix #1.\nbash x/builder-codex-pass.sh %s 1 adversarial\n' "$U" > "$MAINBRIEF"; cp "$MAINBRIEF" "$B/$U.md"
pass() { # <N> <kind>: one pass of the real pass script; what it printed is in $TMP/out
  (cd "$W" && TMPDIR=$TMP PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO STUB_THREAD=thr-$1 \
    bash "$PASS_SH" "$U" "$1" "$2" >"$TMP/out" 2>"$TMP/err") || { echo "FAIL the $2 pass r$1 did not run: $(cat "$TMP/err")"; FAIL=$((FAIL+1)); }
}
input() { sed -n '/^Review input: /,$p' "$B/$U-r$1-prompt-1.md"; } # <N>: what reviewer 1 of round N was handed below the template
SC=$TMP/scratch FB=$TMP/fb; mkdir -p "$SC" "$FB"
PROJ=$HOME/.claude/projects/$(printf '%s' "$W" | tr -c 'A-Za-z0-9' '-')
# Logs every call; a wait answers FRS_IDLE (1 with no answer is a failed wait); the list holds term_frs unless FRS_GONE;
# typing the pointer starts the new session's log.
cat > "$FB/orca-ide" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FRS_CALLS"
case "$*" in
  *"terminal wait"*) exit "${FRS_IDLE:-0}" ;;
  *"terminal list"*) [ -n "${FRS_GONE:-}" ] && echo '{"result":{"terminals":[]}}' || echo '{"result":{"terminals":[{"handle":"term_frs"}]}}' ;;
  *"--text /clear"*) [ -z "${FRS_SEND_FAILS:-}" ] || { echo "orca: PROBE-REFUSAL" >&2; exit 1; } ;;
  # The first new session is new-sid; each later one gets a log of its own, as the record already names new-sid.
  *"Your task spec is the file"*) f=$FRS_PROJ/new-sid.jsonl; [ ! -e "$f" ] || f=$FRS_PROJ/new-sid-$(ls "$FRS_PROJ" | wc -l | tr -d ' ').jsonl
    printf '%s\n' "$*" > "$f"; touch -t 209901010000 "$f" ;;
esac
exit 0
SH
chmod +x "$FB/orca-ide"
fpass() { # <dir> <round> <kind> <reply> [env...]: one pass from <dir> as the Builder's pane; prints its exit code
  local d=$1 n=$2 k=$3 r=$4; shift 4
  (cd "$d" && env TMPDIR=$TMP PATH=$FB:$TMP/cli:$PATH COMMANDECK_MAIN=$REPO ORCA_TERMINAL_HANDLE=term_frs COMMANDECK_FRESH_ROUND_SETTLE_SECONDS=0 \
    FRS_CALLS=$TMP/frs-calls FRS_PROJ=$PROJ STUB_THREAD=thr-$n "STUB_REPLY=$r" "$@" bash "$PASS_SH" "$U" "$n" "$k" >"$TMP/out" 2>"$TMP/err"); echo $?
}
helper_done() { for _ in $(seq 100); do grep -qE '^builder-fresh-round: .*(now names|stays in)' "$SC/$U-fix-r$1.log" 2>/dev/null && return; sleep 0.1; done; }
NOGO=$'- [P1] FINDING-PROBE -- a.sh:1 -- it breaks -- bash a.sh\nVERDICT: NO-GO'
cfg() { jq "$1" "$REPO/.claude/commandeck.json" > "$TMP/cfg" && mv "$TMP/cfg" "$REPO/.claude/commandeck.json"; }
verify() { (cd "$REPO" && PATH=$TMP/cli:$PATH COMMANDECK_MAIN=$REPO bash "$PASS_SH" --verify "$W" "$U" "$(git -C "$W" rev-parse HEAD)" >"$TMP/vout" 2>"$TMP/verr"); echo $?; }
hand() { cat "$B/$U-fix-r$1.md" 2>/dev/null; } # <N>: the fix hand-off after pass N
