#!/usr/bin/env bash
# `seat.sh collect --report <path>` writes an absolute path exactly where it
# says and a relative one under the unit worktree. Prefixing the
# worktree onto the absolute path the script's own --help shows failed with
# ".../knip-bwip-import//tmp/commandeck/..." on 2026-09-23.
set -uo pipefail
REAL=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# seat.sh takes its root from `git rev-parse`, so the stubs only get picked up
# from inside a real repo.
git init -q "$TMP/repo"
WT=$TMP/ws/fake-unit
mkdir -p "$TMP/repo/scripts" "$TMP/repo/config" "$WT/.claude/briefs" "$TMP/bin" "$TMP/scratch" "$TMP/out"
cp "$REAL/scripts/seat.sh" "$REAL/scripts/paths.sh" "$REAL/scripts/project-main.sh" "$REAL/scripts/requirements.sh" "$REAL/scripts/read-verdict.sh" "$TMP/repo/scripts/"
jq -f "$REAL/scripts/__tests__/fixtures/routing-seats.jq" "$REAL/config/routing.json" > "$TMP/repo/config/routing.json"
for s in run-bound.sh worktree-setup.sh; do
  printf '#!/bin/sh\nexit 0\n' > "$TMP/repo/scripts/$s"; chmod +x "$TMP/repo/scripts/$s"
done
# collect passes no worktree, so the reader asks Orca's terminal list for it.
cat > "$TMP/bin/orca-ide" <<'STUB'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "terminal list") printf '{"result":[{"handle":"term_c","worktreePath":"%s","agentIdentity":"claude"}]}\n' "$WT" ;;
  "terminal read") jq -n --arg s "${FAKE_SCREEN:-}" '{result: {terminal: {tail: ($s | split("\n"))}}}' ;;
  *) echo '{"ok":true}' ;;
esac
STUB
chmod +x "$TMP/bin/orca-ide"

# The seat's own session log: it starts after the recorded launch and ends in a report.
T=1789353845
PROJ=$TMP/home/.claude/projects/$(printf '%s' "$WT" | tr -c 'A-Za-z0-9' '-')
mkdir -p "$PROJ"
printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"text","text":"# Review\\n- [P2] a finding\\nVERDICT: GO"}]}}\n' \
  "$(date -u -d "@$((T + 2))" +%Y-%m-%dT%H:%M:%S.000Z)" > "$PROJ/seat.jsonl"
REC=$TMP/scratch/seat-fake-unit-certifier.txt

export WT PATH=$TMP/bin:$PATH HOME=$TMP/home COMMANDECK_WORKSPACES=$TMP/ws COMMANDECK_SCRATCH=$TMP/scratch
collect() {
  printf 'handle=term_c\ntask=task_c\nrole=certifier\nunit=fake-unit\nlaunched=%s\n' "$T" > "$REC"
  ( cd "$TMP/repo" && timeout 60 bash scripts/seat.sh collect certifier fake-unit --report "$1" ) 2>&1
}

OUT=$(collect "$TMP/out/abs-r1.md")
[ -s "$TMP/out/abs-r1.md" ] || fail "an absolute --report did not land at its own path: $OUT"
grep -q '^# Review' "$TMP/out/abs-r1.md" || fail "the absolute report is not the pane's report"
[ -e "$WT/$TMP/out/abs-r1.md" ] && fail "the absolute --report was also written under the worktree"

OUT=$(collect .claude/briefs/rel-r1.md)
[ -s "$WT/.claude/briefs/rel-r1.md" ] || fail "a relative --report did not land under the worktree: $OUT"
[ -e "$TMP/repo/.claude/briefs/rel-r1.md" ] && fail "a relative --report resolved against the repo, not the worktree"

# The verdict collect acts on is the reader's one canonical line. A report
# that quotes a GO in a fence and ends on a bold NO-GO is a NO-GO: taking the
# last bare line ran --on-go for a review that refused.
printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"text","text":"# Review\\nThe brief asks for:\\n```\\nVERDICT: GO\\n```\\n- [P1] a blocker\\n**VERDICT: NO-GO**"}]}}\n' \
  "$(date -u -d "@$((T + 2))" +%Y-%m-%dT%H:%M:%S.000Z)" > "$PROJ/seat.jsonl"
printf 'handle=term_c\ntask=task_c\nrole=certifier\nunit=fake-unit\nlaunched=%s\n' "$T" > "$REC"
( cd "$TMP/repo" && timeout 60 bash scripts/seat.sh collect certifier fake-unit --on-go "touch $TMP/went-go" --on-nogo "touch $TMP/went-nogo" ) >/dev/null 2>&1
[ ! -e "$TMP/went-go" ] || fail "a fenced GO ahead of a bold NO-GO ran --on-go"
[ -e "$TMP/went-nogo" ] || fail "a bold final NO-GO did not run --on-nogo"

echo "PASS seat-collect-report-path: absolute path as given, relative under the worktree"
