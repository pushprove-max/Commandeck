# Sourced by main-watch-auto-merge.test.sh and main-watch-merge-gate.test.sh: main-watch-setup.sh, with stubs of
# builder-codex-pass.sh --verify and merge-queue.sh, a decisions ledger and a Builder unit worktree. Two files, not one:
# one file of every case ran 70 s alone, past what the per-file cap leaves under load (issue 218).
. "$(dirname "${BASH_SOURCE[0]}")/main-watch-setup.sh"
# --verify answers from refuse-<unit> (exit 1, the reason on stderr) or rule-<unit> (the proof's rule, after the text
# in pad-<unit>), and counts calls.
cat > "$REPO/scripts/builder-codex-pass.sh" <<EOF
#!/usr/bin/env bash
echo "\$3" >> "$F/verify-calls"
[ ! -e "$F/refuse-\$3" ] || { cat "$F/refuse-\$3" >&2; exit 1; }
n=\$(ls "$T/ws/\$3/.claude/briefs" 2>/dev/null | sed -n "s/^\$3-r\\([0-9][0-9]*\\)-reports.md\$/\\1/p" | sort -n | tail -n 1)
echo "Builder proof: \$3-r\${n:-3}-reports.md: the closing pass\$(cat "$F/pad-\$3" 2>/dev/null); rule: \$(cat "$F/rule-\$3" 2>/dev/null || echo closing GO)"
# mkround-<unit>: a round that finishes while this check runs (it holds the text of the next round file)
[ ! -e "$F/mkround-\$3" ] || { n=\$(( \${n:-3} + 1 )); mv "$F/mkround-\$3" "$T/ws/\$3/.claude/briefs/\$3-r\$n-reports.md"; }
EOF
# merge-queue.sh prints its own line for each unit it merged and removes its worktree, as the real merge does; a unit
# named in mq-fail stops it, one in mq-late merges with a later step failed.
cat > "$REPO/scripts/merge-queue.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$F/mq-calls"
for a; do [ "\$a" != --train ] || continue
  grep -qxF -- "\${a%@*}" "$F/mq-fail" 2>/dev/null && { echo "merge-queue: STOPPED at \${a%@*} (not merged)" >&2; exit 1; }
  rm -rf "$T/ws/\${a%@*}"
  grep -qxF -- "\${a%@*}" "$F/mq-late" 2>/dev/null && { echo "merge-queue: \${a%@*} MERGED, but a step after the merge commit failed or was refused (exit 5)" >&2; continue; }
  echo "merge-queue: \${a%@*} merged; ok"; done
EOF
chmod +x "$REPO/scripts/builder-codex-pass.sh" "$REPO/scripts/merge-queue.sh"
: > "$F/verify-calls"; : > "$F/mq-calls"; : > "$F/mq-fail"; : > "$F/mq-late"
mkdir -p "$REPO/.claude/metrics" "$T/home/.claude/plugins/store" "$T/home/.claude/projects/p"
: > "$REPO/.claude/metrics/decisions.jsonl"
D=$S/main-watch/digest

unit() { # <unit> -- a Builder worktree, clean, with its brief and one commit; its seat is working
  local w=$T/ws/$1; mkdir -p "$w/.claude/briefs"; git -C "$w" init -q; echo '.claude/' > "$w/.gitignore"
  echo "# $1" > "$w/.claude/briefs/$1.md"
  git -C "$w" add -A; git -C "$w" -c user.name=t -c user.email=t@t commit -qm "feat($1): work"
  bseat "$1" "term_$1" "task_$1" $((N - 1000)); state "term_$1" working
}
said_done() { echo "${1^^}-DONE" > "$F/verdict-term_$1"; state "term_$1" "done"; }
tip() { git -C "$T/ws/$1" rev-parse HEAD; }
# The merge job runs detached; its exit file is what the next tick reads.
jobwait() { local i; for i in $(seq 100); do ls "$S"/main-watch/mergejob-*.rc >/dev/null 2>&1 && [ -z "$(running)" ] && return 0; sleep 0.1; done; fail "the merge job for $1 never finished"; }
running() { local j; for j in "$S"/main-watch/mergejob-*.log; do [ -e "$j" ] && [ ! -e "${j%.log}.rc" ] && echo "$j"; done; }
gone() { rm -rf "$T/ws/$1" "$S/seat-$1-builder.txt"; }
mails() { cat "$T/typed" 2>/dev/null | grep -c "items are waiting in your Orca inbox" || true; }
offer() { # <session> <shownAt s> <line> -- the store shows one offer from a session in this checkout
  jq -nc --arg id "sess-$1" --argjson at "$2" --arg l "$3" '{sessions: [{id: $id, view: {kind: "offer", shownAt: ($at * 1000), line: $l, explanation: "why"}}]}' \
    > "$T/home/.claude/plugins/store/cc-plugin-you-should-know_builtin-t.json"
  jq -nc --arg c "$REPO" '{cwd: $c}' > "$T/home/.claude/projects/p/sess-$1.jsonl"; }
