"""Prüft, dass ergebnisloses Warten die KI nicht endlos blockiert."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "eko"))
from eko_ollama import Agent, passive_wait_result  # noqa: E402


class IdleToolTests(unittest.TestCase):
    def test_idle_agent_must_choose_action(self):
        agent = Agent.__new__(Agent)
        agent.args = SimpleNamespace(rolle="unternehmer")
        agent._observe_streak = 0
        agent._passive_streak = 3
        names = {tool["name"] for tool in agent.available_tools()}
        self.assertIn("act", names)
        self.assertNotIn("wait", names)
        self.assertNotIn("observe", names)

    def test_wait_available_during_normal_work(self):
        agent = Agent.__new__(Agent)
        agent.args = SimpleNamespace(rolle="unternehmer")
        agent._observe_streak = 0
        agent._passive_streak = 0
        self.assertIn("wait", {tool["name"] for tool in agent.available_tools()})

    def test_wait_without_answer_counts_as_idle_even_after_long_delay(self):
        self.assertTrue(passive_wait_result({"gewartet_s": 20, "msg": "noch keine Antwort – tu etwas anderes"}))
        self.assertFalse(passive_wait_result({"gewartet_s": 20, "msg": "Nachricht erhalten"}))


if __name__ == "__main__":
    unittest.main()
