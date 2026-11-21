"""Konsolenansicht ohne laufendes Spiel prüfen."""

import contextlib
import io
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "eko"))
from eko_console import ConsoleUI, top_events  # noqa: E402


class ConsoleTests(unittest.TestCase):
    def test_top_events_prefers_meaningful_actions(self):
        with tempfile.TemporaryDirectory() as root:
            log = Path(root) / "Greta" / "logs" / "sitzung.log"
            log.parent.mkdir(parents=True)
            log.write_text(
                "12:00:00 → observe {}\n"
                "12:01:00 → founding_choice {\"candidate\": 0} · Basis eröffnet\n"
                "12:02:00 → act {\"action\": \"haus_bauen\"} · Baustelle BS1\n",
                encoding="utf-8",
            )
            events = top_events(root)
            self.assertEqual(len(events), 2)
            self.assertIn("founding_choice", events[0][2])

    def test_shortcuts_and_back_return_to_start(self):
        with tempfile.TemporaryDirectory() as root:
            ui = ConsoleUI(root, lambda: {"Greta": {"state": "denkt", "calls": 3}})
            keys = iter(("1", "2", "3", "b", "h", "\x1b", "\b", "\r"))
            def get_key():
                try:
                    return next(keys)
                except StopIteration as error:
                    raise EOFError from error
            fake = types.SimpleNamespace(getwch=get_key)
            output = io.StringIO()
            with patch.dict(sys.modules, {"msvcrt": fake}), contextlib.redirect_stdout(output):
                ui._keys()
            self.assertEqual(ui.view, "start")
            self.assertIn("TOP 10 KI-EREIGNISSE", output.getvalue())
            self.assertIn("LETZTE 18 LOGZEILEN", output.getvalue())
            self.assertIn("AGENTENSTATUS", output.getvalue())
            self.assertIn("E K O  -  S C H W A R M", output.getvalue())


if __name__ == "__main__":
    unittest.main()
