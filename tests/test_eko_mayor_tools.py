"""Regressionspruefung fuer typisierte Entscheidungen der lokalen Buergermeister-KI."""

import unittest
from types import SimpleNamespace

from tools.eko.eko_ollama import Agent, changed_world, compact_obs, company_choices, mayor_action_key, mayor_choices, mayor_state_signature


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


def agent_with(world, role="buergermeister"):
    agent = Agent.__new__(Agent)
    agent.args = SimpleNamespace(rolle=role)
    agent.world = world
    agent._passive_office = 0
    agent._mayor_failed_key = ""
    agent._mayor_failed_count = 0
    agent._mayor_invalid_streak = 0
    agent._mayor_invalid_state = ""
    agent._passive_streak = 0
    agent._nonworld_streak = 0
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

    def test_district_with_running_project_is_not_offered_again(self):
        office = {"bauprogramm": {"neues_bauprojekt_moeglich": True, "projekte": [{"viertel": "V1"}]},
                  "stadtplan_optionen": [{"viertel": "V1", "zone": "wohnen"}, {"viertel": "V2", "zone": "gewerbe"}]}
        offered = [c["params"]["viertel"] for c in mayor_choices(office) if c["action"] == "viertel_erschliessen"]
        self.assertEqual(offered, ["V2"])

    def test_full_build_board_only_offers_actions_without_new_project(self):
        office = {"bauprogramm": {"neues_bauprojekt_moeglich": False},
                  "stadtlager": {"vorschlaege": [{"id": "ORDER-1"}]},
                  "versorgungsleitungen": [{"id": "wasser:4:5"}],
                  "stromtrassen": [{"id": "strom:1"}],
                  "stadtplan_optionen": [{"viertel": "V3"}]}
        self.assertEqual([c["action"] for c in mayor_choices(office)], ["approve_procurement"])

    def test_running_road_project_hides_other_districts_but_keeps_harbor(self):
        office = {"bauprogramm": {"neues_bauprojekt_moeglich": True, "projekte": [{"art": "erschliessung", "viertel": "V1"}]},
                  "stadtplan_optionen": [{"viertel": "V2"}], "haushalt": {"verfuegbar": 500000},
                  "verkehrsstandorte": {"hafen": {"gebaut": False, "projekt": "", "standort": [10, 20], "kosten": 200000}}}
        offered = [c["action"] for c in mayor_choices(office)]
        self.assertNotIn("viertel_erschliessen", offered)
        self.assertIn("build_harbor", offered)

    def test_transport_sites_remain_visible_among_many_utility_choices(self):
        office = {"bauprogramm": {"neues_bauprojekt_moeglich": True, "projekte": []},
                  "haushalt": {"verfuegbar": 500000},
                  "stadtlager": {"vorschlaege": [{"id": "O1"}, {"id": "O2"}]},
                  "versorgungsleitungen": [{"id": "wasser:1", "kosten": 200}, {"id": "wasser:2", "kosten": 200},
                                             {"id": "abwasser:3", "kosten": 200}],
                  "stromtrassen": [{"id": "strom:1", "kosten": 200}, {"id": "strom:2", "kosten": 200}],
                  "versorgungsanlagen_ausbau": {"wasserwerk": {"ok": True}, "klaeranlage": {"ok": True}},
                  "stadtplan_optionen": [{"viertel": "V1"}, {"viertel": "V2"}],
                  "verkehrsstandorte": {"hafen": {"standort": [10, 20], "kosten": 100000},
                                        "flughafen": {"standort": [20, 20], "kosten": 120000},
                                        "bahn": {"standort": [30, 20], "kosten": 90000}}}
        offered = [c["action"] for c in mayor_choices(office)]
        self.assertIn("build_harbor", offered)
        self.assertIn("build_airport", offered)
        self.assertIn("build_station", offered)

    def test_rejected_infra_expansion_is_prechecked_and_reason_changes_do_not_reset_guard(self):
        class BlockedWorld(FakeWorld):
            def observe(self):
                data = super().observe()
                data["mein_amt"]["bauprogramm"]["neues_bauprojekt_moeglich"] = True
                data["mein_amt"]["versorgungsanlagen_ausbau"] = {"hochbehaelter": {"ok": False, "msg": "Kapazitaet reicht"}}
                return data
        world = BlockedWorld()
        result = agent_with(world).call_tool("mayor_action", {"action": "infra_ausbau", "params": {"anlage": "hochbehaelter"}})
        self.assertFalse(result["ok"])
        self.assertIn("Kapazitaet", result["msg"])
        self.assertEqual(world.actions, [])
        self.assertEqual(mayor_action_key("infra_ausbau", {"anlage": "hochbehaelter", "reason": "A"}),
                         mayor_action_key("infra_ausbau", {"anlage": "hochbehaelter", "reason": "B", "grundstueck": "G133"}))

    def test_failed_mayor_waits_until_relevant_world_state_changes(self):
        class StateWorld:
            open = False
            def observe(self):
                return {"ok": True, "mein_amt": {"bauprogramm": {"neues_bauprojekt_moeglich": self.open, "projekte": []}}}
        world = StateWorld()
        agent = agent_with(world)
        agent._mayor_invalid_streak = 2
        agent._mayor_invalid_state = mayor_state_signature(world.observe()["mein_amt"])
        self.assertEqual([t["name"] for t in agent.available_tools()], ["wait"])
        world.open = True
        self.assertIn("mayor_action", [t["name"] for t in agent.available_tools()])
        self.assertEqual(agent._mayor_invalid_streak, 0)

    def test_company_choice_rechecks_vehicle_offer_and_executes_investment(self):
        class CompanyWorld(FakeWorld):
            def observe(self):
                return {"ok": True, "meine_firma": {"firma": "Test", "bargeld": 300000, "lieferungen": 25,
                        "fahrzeuge": [{"id": 1}], "fahrzeugangebote": [{"id": "F10", "modell": "LKW", "preis": 90000}],
                        "wirtschaftsoptionen": [{"branche": "brauerei", "grundstueck": "G12", "stadt": 0,
                                                  "kosten": 80000, "personal_min": 2}]}}
        world = CompanyWorld()
        agent = agent_with(world, "unternehmer")
        choices = company_choices(world.observe()["meine_firma"])
        self.assertEqual([c["action"] for c in choices], ["buy_vehicle", "found_business"])
        result = agent.call_tool("company_choice", {"candidate": 0})
        self.assertTrue(result["ok"])
        self.assertEqual(world.actions[0][1]["aktion"]["offer_id"], "F10")
        self.assertTrue(changed_world("company_choice", {"candidate": 0}, result))


if __name__ == "__main__":
    unittest.main()
