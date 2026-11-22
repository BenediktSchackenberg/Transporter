"""Regressionspruefung fuer typisierte Entscheidungen der lokalen Buergermeister-KI."""

import unittest
from types import SimpleNamespace

from tools.eko.eko_ollama import Agent, changed_world, compact_obs


class FakeWorld:
    def __init__(self, ok=True):
        self.ok = ok
        self.actions = []

    def observe(self):
        return {"ok": True, "mein_amt": {
            "stadtlager": {"rueckstau_wareneingang_einheiten": 4, "personal_gesamt": 0,
                           "vorschlaege": []},
            "versorgungsleitungen": [{"id": "wasser:4:5", "art": "wasser", "gebaeude_nahe": 2, "kosten": 800}],
            "stromtrassen": [], "stadtplan_optionen": [], "bauprogramm": {"neues_bauprojekt_moeglich": False}},
            "stadtwachstum": {"bewohnbar": 0}}

    def act(self, kind, data):
        self.actions.append((kind, data))
        return {"ok": self.ok, "msg": "angenommen" if self.ok else "abgelehnt"}


def agent_with(world):
    agent = Agent.__new__(Agent)
    agent.args = SimpleNamespace(rolle="buergermeister")
    agent.world = world
    agent._passive_office = 0
    agent._mayor_failed_key = ""
    agent._mayor_failed_count = 0
    return agent


class MayorToolTests(unittest.TestCase):
    def test_invalid_infrastructure_does_not_reach_world(self):
        world = FakeWorld()
        result = agent_with(world).call_tool("mayor_action", {"action": "infra_ausbau", "params": {}})
        self.assertFalse(result["ok"])
        self.assertIn("anlage", result["erforderlich"])
        self.assertEqual(world.actions, [])

    def test_choice_uses_live_order_and_real_parameters(self):
        world = FakeWorld()
        agent = agent_with(world)
        choices = compact_obs(world.observe())["mein_amt"]["entscheidungsoptionen"]
        self.assertEqual(choices[0]["action"], "expand_depot")
        result = agent.call_tool("mayor_choice", {"candidate": 0})
        self.assertTrue(result["ok"])
        self.assertEqual(world.actions[0][1]["aktion"]["kind"], "staff")
        self.assertTrue(changed_world("mayor_choice", {"candidate": 0}, result))

    def test_repeated_rejection_is_stopped(self):
        world = FakeWorld(ok=False)
        agent = agent_with(world)
        args = {"action": "expand_depot", "params": {"kind": "staff"}}
        for _ in range(3):
            result = agent.call_tool("mayor_action", args)
        self.assertFalse(result["ok"])
        self.assertEqual(len(world.actions), 2)


if __name__ == "__main__":
    unittest.main()
