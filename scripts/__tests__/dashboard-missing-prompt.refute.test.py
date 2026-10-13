import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import dashboard_limit as d


class MissingPrompt(unittest.TestCase):
    def test_unknown_prompt_size_is_unpriced(self):
        for value in ("missing", None, "150000"):
            with self.subTest(value=value):
                usage = {"output_tokens": 1_000_000}
                if value != "missing":
                    usage["input_tokens"] = value
                row = d.request_row({
                    "type": "assistant",
                    "requestId": "r",
                    "timestamp": "2026-10-10T12:00:00Z",
                    "message": {
                        "model": "claude-haiku-5-5",
                        "usage": usage,
                    },
                })
                self.assertIsNone(d.price(row))


if __name__ == "__main__":
    unittest.main()
