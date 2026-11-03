#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
python3 - "$ROOT" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
os.environ.pop("CLAUDE_PROJECT_DIR", None)
root = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    box = pathlib.Path(tmp)
    (box / "main").mkdir()
    subprocess.run(["git", "init", "-q"], cwd=box / "main", check=True)
    logs = box / "codex"
    logs.mkdir()
    records = [{"type": "session_meta", "payload": {
        "cwd": "/fixture/ws/u"}}]
    for turn, amount in (("a", 100), ("b", 200)):
        records.append({"type": "token_usage_record", "payload": {
            "turn_id": turn, "turn_token_usage": {
                "input_tokens": amount, "cached_input_tokens": 0,
                "output_tokens": 10}}})
    (logs / "one.jsonl").write_text(
        "".join(json.dumps(record) + "\n" for record in records))
    env = dict(os.environ, COMMANDECK_WORKSPACES="/fixture/ws", TOKEN_LEDGER_CLAUDE_ROOT=str(box / "absent"),
               TOKEN_LEDGER_CODEX_ROOTS=str(logs),
               TOKEN_LEDGER_RATES=str(box / "missing-rates"))
    out = subprocess.check_output(
        ["bash", str(root / "scripts/token-ledger.sh"), "u"],
        env=env, text=True, cwd=box / "main")
    row = next(line for line in out.splitlines()
               if line.startswith("row unit=u source=codex "))
    assert "uncached=300 " in row and "output=20 " in row, row
PY
echo "ledger-codex-turn-usage: 1 passed, 0 failed"
