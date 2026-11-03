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
    project = box / "claude/-fixture-ws-u"
    project.mkdir(parents=True)
    (project / "one.jsonl").write_text(json.dumps({
        "type": "assistant", "message": {"usage": {"input_tokens": 10}}
    }) + "\n")
    env = dict(os.environ, COMMANDECK_WORKSPACES="/fixture/ws", TOKEN_LEDGER_CLAUDE_ROOT=str(box / "claude"),
               TOKEN_LEDGER_CODEX_ROOTS=str(box / "absent"),
               TOKEN_LEDGER_RATES=str(box / "missing-rates"))
    out = subprocess.check_output(
        ["bash", str(root / "scripts/token-ledger.sh"), "u"],
        env=env, text=True, cwd=box / "main")
    row = next(line for line in out.splitlines()
               if line.startswith("row unit=u source=claude "))
    for field in ("cache_create", "cache_read", "output"):
        assert f'{field}="not recorded"' in row, row
PY
echo "ledger-missing-usage: 1 passed, 0 failed"
