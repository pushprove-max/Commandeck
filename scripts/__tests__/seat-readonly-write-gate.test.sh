#!/usr/bin/env bash
# Self-test for seat.sh's read-only write gate (orchestrator invariant 3:
# delegate by contract -- the allowed changes a spec asks for must match the
# sandbox the seat runs in). Run directly.
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SEAT=$ROOT/scripts/seat.sh
PASS=0 FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2, got $3)"; fi }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fake-unit"
export COMMANDECK_WORKSPACES=$TMP

# Anchor on the gate's own BLOCKED line, not on exit 2: seat.sh also exits 2
# when run-bound.sh finds no Orca run, which is always true in a chain lane, so
# an exit-code test read every allowed spec as blocked there.
# The stub keeps the launch off the network in both environments.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/orca-ide"; chmod +x "$TMP/bin/orca-ide"
export PATH=$TMP/bin:$PATH
# routing.json names codex-reviewer's model by family; seat.sh resolves it from
# the Codex model list and refuses the launch, before the gate, on a machine
# that has none (the CI runner). A refusal has no BLOCKED line either.
export CODEX_HOME=$TMP/codex; mkdir -p "$CODEX_HOME"
printf '{"models":[{"slug":"gpt-7.2-sol"}]}\n' > "$CODEX_HOME/models_cache.json"
# A grep that cannot run the gate's write pattern; every other grep is the real one.
mkdir -p "$TMP/badgrep"
printf '#!/bin/sh\ncase "$*" in *"write|save"*) exit 2 ;; esac\nexec %s "$@"\n' "$(command -v grep)" > "$TMP/badgrep/grep"
chmod +x "$TMP/badgrep/grep"
# "allowed" is a launch that got past the gate to the step after it: the stub
# Orca binds no run, so run-bound.sh stops it there. A run that died any other
# way has no BLOCKED line either, and calling it allowed would pass a broken gate.
export COMMANDECK_RUN=run_test
launch() {
  local out rc
  printf '%s\n' "$2" > "$TMP/spec.md"
  out=$(timeout 20 bash "$SEAT" launch "$1" fake-unit "$TMP/spec.md" 2>&1); rc=$?
  if grep -q '^BLOCKED:' <<<"$out"; then echo blocked
  elif grep -q '^NO RUN BOUND: run-use --id run_test failed' <<<"$out"; then echo allowed
  else echo "died rc=$rc: $(tail -1 <<<"$out")"; fi
}

# codex-reviewer is the read-only pane seat; builder is a writing seat.
for role in codex-reviewer; do
  check "$role told to write a report blocks" blocked \
    "$(launch "$role" 'Review the diff. Write your findings to .claude/briefs/unit-r1-report.md, then stop.')"
done
check "read-only seat told to append to a log blocks" blocked \
  "$(launch codex-reviewer 'Append each finding to .claude/briefs/unit-evidence.md as you go.')"
check "read-only seat told to create a json file blocks" blocked \
  "$(launch codex-reviewer 'Create .claude/metrics/unit-findings.json with one row per finding.')"

# The real templates print to the chat and say "do not edit anything"; a spec
# that only NAMES a file to read, or negates the write, must still launch.
check "read-only seat told to read a brief is allowed" allowed \
  "$(launch codex-reviewer 'Read .claude/briefs/unit.md and its map .claude/briefs/unit-map.md. Print findings in the chat. Do not edit anything.')"
# A verb inside a filename is not an ask (u1224, 2026-09-17: `dbg-xqhcxw-save-hang.md`).
check "read-only seat told to read a file whose name holds a verb is allowed" allowed \
  "$(launch codex-reviewer 'Research: read-only dbg-capture.md and dbg-save-hang.md. Print findings in the chat.')"
check "read-only seat told it writes a report file blocks" blocked \
  "$(launch codex-reviewer 'It writes the report to .claude/briefs/unit-r1.md.')"
check "read-only seat with an explicit never-write line is allowed" allowed \
  "$(launch codex-reviewer 'Your sandbox is read-only, so never write .claude/briefs/unit-r1.md; print the report instead.')"
check "writing seat told to write a report is allowed" allowed \
  "$(launch builder 'Write the brief to .claude/briefs/unit.md and its map to .claude/briefs/unit-map.md.')"

# The gate fails closed: a check that cannot run blocks a spec it would allow.
check "read-only seat whose write check cannot run blocks" blocked \
  "$(PATH=$TMP/badgrep:$PATH launch codex-reviewer 'Read .claude/briefs/unit.md. Print findings in the chat.')"
# The second stage too: it drops the negated lines, and a stage that cannot run
# must not read as "every line was negated".
printf '#!/bin/sh\ncase "$*" in *"do not|does not"*) exit 2 ;; esac\nexec %s "$@"\n' "$(command -v grep)" > "$TMP/badgrep/grep"
check "read-only seat whose negation check cannot run blocks" blocked \
  "$(PATH=$TMP/badgrep:$PATH launch codex-reviewer 'Write your findings to .claude/briefs/unit-r1-report.md, then stop.')"
# No model list: the launch is refused before the gate, so nothing is allowed.
check "read-only seat with no Codex model list is refused" refused \
  "$(printf 'Print findings in the chat.\n' > "$TMP/spec.md"
     CODEX_HOME=$TMP/none timeout 20 bash "$SEAT" launch codex-reviewer fake-unit "$TMP/spec.md" 2>&1 \
       | grep -q '^no usable roles.codex-reviewer' && echo refused || echo launched)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
