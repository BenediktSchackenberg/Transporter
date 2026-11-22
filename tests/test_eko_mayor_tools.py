"""Regressionspruefung fuer typisierte Entscheidungen der lokalen Buergermeister-KI."""

import unittest
from types import SimpleNamespace
from unittest.mock import patch

from tools.eko.eko_ollama import Agent, changed_world, compact_obs, company_choices, estate_choices, growth_choices, mayor_action_key, mayor_choices, mayor_project_signature, mayor_state_signature, mining_choices


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
    def test_mining_choices_follow_real_deposit_steps(self):
        firm = {"bargeld": 250000, "bergbau": {"kohle": {"schritt": "erkunden", "grundstueck": "G20", "kosten": 6000,
                "rohstoffwert_geschaetzt": 220000, "alternative": {"schritt": "abbauantrag", "grundstueck": "G21"}},
                "uranerz": {"schritt": "gruenden", "grundstueck": "G30", "kaufpreis": 80000,
                             "strombedarf_kw": 50, "kraftwerksanschluss": True}}}
        choices = mining_choices(firm)
        self.assertEqual([(c["action"], c["standort"]) for c in choices],
                         [("explore_deposit", "G20"), ("request_mining", "G21"), ("found_business", "G30")])
        self.assertEqual(choices[2]["params"]["branche"], "uranbergwerk")
        world = FakeWorld()
        world.observe = lambda: {"ok": True, "meine_firma": {"firma": "Test", **firm}}
        agent = agent_with(world, "unternehmer")
        self.assertTrue(agent.call_tool("mining_choice", {"candidate": 2})["ok"])
        self.assertEqual(world.actions[0][1]["aktion"]["rohstoff"], "uranerz")

    def test_growth_requires_demand_and_habitable_homes(self):
        firm = {"bargeld": 300000, "bauentwuerfe": [{"id": "design_w_001", "typ": "einfamilienhaus", "kosten": 85000,
                    "komfort": 70}], "wohnstandorte": {"einfamilienhaus": [{"grundstueck": "G7", "preis": 25000,
                    "bewertung": 0.8, "erschliessung": "Straße liegt am Grundstück"}]}}
        self.assertEqual(growth_choices(firm, {"wohnungen": 4, "bewohnbar": 0, "wohnungssuchende": 3}), [])
        self.assertEqual(growth_choices(firm, {"wohnungen": 4, "bewohnbar": 4, "wohnungssuchende": 0}), [])
        choice = growth_choices(firm, {"wohnungen": 4, "bewohnbar": 4, "wohnungssuchende": 3})[0]
        self.assertEqual(choice["params"], {"typ": "einfamilienhaus", "entwurf": "design_w_001", "grundstueck": "G7"})

    def test_empty_transport_chances_are_removed_from_tool_menu(self):
        world = FakeWorld()
        world.observe = lambda: {"ok": True, "meine_firma": {"firma": "Test", "transportchancen": []}}
        agent = agent_with(world, "unternehmer")
        names = {tool["name"] for tool in agent.available_tools()}
        self.assertNotIn("contract_choice", names)
        self.assertIn("act", names)

    def test_direct_mayor_action_uses_the_same_fresh_id_check(self):
        world = FakeWorld()
        world.observe = lambda: {"ok": True, "mein_amt": {"stadtlager": {"vorschlaege":
                                [{"id": "B7", "projekt": "P1"}]}, "bauprogramm": {"neues_bauprojekt_moeglich": True}}}
        agent = agent_with(world)
        stale = {"type": "Amt", "data": {"aktion": {"action": "approve_procurement", "order_id": "B6"}}}
        self.assertFalse(agent.call_tool("act", stale)["ok"])
        self.assertFalse(world.actions)
        valid = {"type": "Amt", "data": {"aktion": {"action": "approve_procurement", "order_id": "B7"}}}
        self.assertTrue(agent.call_tool("act", valid)["ok"])
        self.assertEqual(len(world.actions), 1)

    def test_project_id_cannot_be_used_as_infrastructure_plant(self):
        world = FakeWorld()
        world.observe = lambda: {"ok": True, "mein_amt": {"versorgungsanlagen_ausbau": {
            "wasserwerk": {"ok": False}, "hochbehaelter": {"ok": False}, "klaeranlage": {"ok": False}}}}
        agent = agent_with(world)
        result = agent.call_tool("act", {"type": "Amt", "data": {"aktion":
                                 {"action": "infra_ausbau", "anlage": "P50", "reason": "Druckzone"}}})
        self.assertFalse(result["ok"])
        self.assertIn("Projekt-IDs", result["msg"])
        self.assertFalse(world.actions)

    def test_unfunded_airport_gets_two_financing_choices(self):
        office = {"haushalt": {"verfuegbar": 30000, "flughafenbudget": 30000}, "verkehrsstandorte": {
            "flughafen": {"standort": [100, 200], "kosten": 150000, "gebaut": False, "projekt": "",
                          "finanzplan": {"aktiv": False, "fehlbetrag": 120000}}}}
        choices = mayor_choices(office)
        self.assertEqual([c["params"]["strategie"] for c in choices if c["action"] == "plan_airport"],
                         ["sparen", "kredit"])
        office["verkehrsstandorte"]["flughafen"]["finanzplan"]["aktiv"] = True
        self.assertFalse(any(c["action"] == "plan_airport" for c in mayor_choices(office)))

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
                  "haushalt": {"verfuegbar": 20000},
                  "stadtplan_optionen": [{"viertel": "V1", "zone": "wohnen"}, {"viertel": "V2", "zone": "gewerbe"}]}
        offered = [c["params"]["viertel"] for c in mayor_choices(office) if c["action"] == "viertel_erschliessen"]
        self.assertEqual(offered, ["V2"])

    def test_full_build_board_only_offers_actions_without_new_project(self):
        office = {"bauprogramm": {"neues_bauprojekt_moeglich": False}, "haushalt": {"verfuegbar": 2000},
                  "stadtlager": {"vorschlaege": [{"id": "ORDER-1", "geschaetzte_kosten": 300}]},
                  "versorgungsleitungen": [{"id": "wasser:4:5"}],
                  "stromtrassen": [{"id": "strom:1"}],
                  "stadtplan_optionen": [{"viertel": "V3"}]}
        self.assertEqual([c["action"] for c in mayor_choices(office)], ["approve_procurement"])

    def test_empty_budget_offers_credit_instead_of_unaffordable_orders(self):
        office = {"bauprogramm": {"neues_bauprojekt_moeglich": True}, "haushalt": {"verfuegbar": 0},
                  "kreditangebot": {"ok": True, "vorschlag": 125000, "schuld": 0, "zins_pro_monat": 0.003},
                  "stadtlager": {"vorschlaege": [{"id": "B18", "geschaetzte_kosten": 333}]},
                  "versorgungsleitungen": [{"id": "wasser:4:5", "kosten": 1040}],
                  "stadtplan_optionen": [{"viertel": "V2"}]}
        offered = mayor_choices(office)
        self.assertEqual([c["action"] for c in offered], ["request_credit"])
        self.assertEqual(offered[0]["params"]["betrag"], 125000)

    def test_single_mayor_option_accepts_missing_candidate(self):
        class CreditWorld(FakeWorld):
            def observe(self):
                return {"ok": True, "mein_amt": {"haushalt": {"verfuegbar": 0},
                        "kreditangebot": {"ok": True, "vorschlag": 125000}}}
        world = CreditWorld()
        result = agent_with(world).call_tool("mayor_choice", {})
        self.assertTrue(result["ok"])
        self.assertEqual(world.actions[0][1]["aktion"]["action"], "request_credit")
        self.assertEqual(world.actions[0][1]["aktion"]["betrag"], 125000)

    def test_full_observation_keeps_checked_choices(self):
        observation = {"ok": True, "mein_amt": {"haushalt": {"verfuegbar": 0},
                       "kreditangebot": {"ok": True, "vorschlag": 620000}},
                       "meine_firma": {"bargeld": 200000, "lieferungen": 24, "fahrzeuge": [{"id": 1}],
                       "fahrzeugangebote": [{"id": "F2", "modell": "truck", "preis": 30000}]}}
        full = compact_obs(observation, full=True)
        self.assertEqual(full["mein_amt"]["entscheidungsoptionen"][0]["action"], "request_credit")
        self.assertEqual(full["meine_firma"]["entscheidungsoptionen"][0]["action"], "buy_vehicle")

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
                  "stadtlager": {"vorschlaege": [{"id": "O1", "geschaetzte_kosten": 100}, {"id": "O2", "geschaetzte_kosten": 100}]},
                  "versorgungsleitungen": [{"id": "wasser:1", "kosten": 200}, {"id": "wasser:2", "kosten": 200},
                                             {"id": "abwasser:3", "kosten": 200}],
                  "stromtrassen": [{"id": "strom:1", "kosten": 200}, {"id": "strom:2", "kosten": 200}],
                  "versorgungsanlagen_ausbau": {"wasserwerk": {"ok": True, "kosten": 1000}, "klaeranlage": {"ok": True, "kosten": 1000}},
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

    def test_unaffordable_line_preflight_counts_toward_repeat_guard(self):
        class BrokeWorld(FakeWorld):
            def observe(self):
                data = super().observe()
                office = data["mein_amt"]
                office["haushalt"] = {"verfuegbar": 0}
                office["kreditangebot"] = {"ok": True, "vorschlag": 620000}
                office["bauprogramm"]["neues_bauprojekt_moeglich"] = True
                office["versorgungsleitungen"][0]["kosten"] = 1040
                return data
        world = BrokeWorld()
        agent = agent_with(world)
        for reason in ("A", "B"):
            result = agent.call_tool("mayor_action", {"action": "versorgungsleitung_bauen",
                                                      "params": {"option": "wasser:4:5", "reason": reason}})
            self.assertFalse(result["ok"])
        self.assertEqual(agent._mayor_failed_count, 2)
        self.assertEqual(world.actions, [])

    def test_failed_mayor_waits_until_relevant_world_state_changes(self):
        class StateWorld:
            open = False
            def observe(self):
                return {"ok": True, "mein_amt": {"bauprogramm": {"neues_bauprojekt_moeglich": self.open,
                        "projekte": [{"id": "P1", "status": "laufend", "wartet_auf": "Material"}]}}}
        world = StateWorld()
        agent = agent_with(world)
        agent._mayor_invalid_streak = 2
        agent._mayor_invalid_state = mayor_state_signature(world.observe()["mein_amt"])
        self.assertEqual([t["name"] for t in agent.available_tools()], ["wait"])
        world.open = True
        self.assertIn("mayor_action", [t["name"] for t in agent.available_tools()])
        self.assertEqual(agent._mayor_invalid_streak, 0)

    def test_repeated_observation_leads_to_project_wait_or_decision(self):
        class BusyWorld:
            threat = False
            def observe(self):
                return {"ok": True, "mein_amt": {"bedrohung": self.threat,
                        "bauprogramm": {"neues_bauprojekt_moeglich": False,
                                        "projekte": [{"id": "P1", "status": "laufend"}]},
                        "stadtlager": {"vorschlaege": []}}}
        world = BusyWorld()
        agent = agent_with(world)
        agent._observe_streak = 2
        self.assertEqual([t["name"] for t in agent.available_tools()], ["wait"])
        agent._observe_streak = 0
        agent._nonworld_streak = 5
        self.assertEqual([t["name"] for t in agent.available_tools()], ["wait"])
        world.threat = True
        self.assertEqual([t["name"] for t in agent.available_tools()], ["mayor_action"])

    def test_completed_utility_effect_reopens_mayor_decisions(self):
        class EffectWorld:
            effect = []
            def observe(self):
                return {"ok": True, "mein_amt": {"bauprogramm": {"neues_bauprojekt_moeglich": True, "projekte": []},
                        "versorgungswirkung": self.effect}}
        world = EffectWorld()
        agent = agent_with(world)
        agent._mayor_invalid_streak = 2
        agent._mayor_invalid_state = mayor_state_signature(world.observe()["mein_amt"])
        self.assertEqual([t["name"] for t in agent.available_tools()], ["mayor_action", "wait"])
        world.effect = [{"projekt": "P50", "wohnungen_mehr": 4, "betriebe_mehr": 1}]
        self.assertIn("mayor_action", [t["name"] for t in agent.available_tools()])
        self.assertEqual(agent._mayor_invalid_streak, 0)

    def test_project_wait_ends_on_material_progress(self):
        class ProjectWorld:
            status = "bestellt"
            def observe(self):
                return {"ok": True, "mein_amt": {"bauprogramm": {"projekte": [{"id": "P1", "status": "laufend",
                        "resttage": 3, "wartet_auf": "Material"}]}, "stadtlager": {
                        "laufende_bestellungen": [{"id": "B1", "status": self.status}]}}}
        world = ProjectWorld()
        agent = agent_with(world)
        agent._mayor_invalid_streak = 2
        before = mayor_project_signature(world.observe()["mein_amt"])
        with patch("tools.eko.eko_ollama.time.sleep", side_effect=lambda _s: setattr(world, "status", "angeliefert")):
            result = agent.call_tool("wait", {})
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"], "abgeschlossen")
        self.assertNotEqual(before, mayor_project_signature(result["lage"]["mein_amt"]))

    def test_busy_mayor_wait_defaults_to_project_change(self):
        class ProjectWorld:
            status = "bestellt"
            def observe(self):
                return {"ok": True, "mein_amt": {"bauprogramm": {
                        "neues_bauprojekt_moeglich": False,
                        "projekte": [{"id": "P1", "status": "laufend"}]},
                        "stadtlager": {"laufende_bestellungen": [{"id": "B1", "status": self.status}]}}}
        world = ProjectWorld()
        agent = agent_with(world)
        with patch("tools.eko.eko_ollama.time.sleep", side_effect=lambda _s: setattr(world, "status", "angeliefert")):
            result = agent.call_tool("wait", {})
        self.assertEqual(result["status"], "abgeschlossen")
        self.assertEqual(result["bestellungen"][0]["status"], "angeliefert")

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

    def test_estate_choice_uses_firm_cash_and_current_design(self):
        class EstateWorld(FakeWorld):
            def __init__(self):
                super().__init__()
                self.cash = 80000
                self.building = False
                self.tower = False

            def observe(self):
                return {"ok": True, "meine_firma": {"firma": "Test", "bargeld": self.cash},
                        "mein_stammsitz": {"bauten": [{"art": "huette", "status": "fertig"}] +
                                                 ([{"art": "turm", "status": "fertig"}] if self.tower else []) +
                                                 ([{"art": "garten", "status": "im_bau"}] if self.building else []),
                                            "ausbauoptionen": [{"art": "garten", "feld": 3, "material": "boden", "hoehe": 2,
                                                                "kosten": 12000, "zweck": "Garten"},
                                                               {"art": "schloss", "feld": 4, "material": "stein", "hoehe": 2,
                                                                "kosten": 90000, "zweck": "Schloss"}]}}

        world = EstateWorld()
        agent = agent_with(world, "unternehmer")
        choices = compact_obs(world.observe())["mein_stammsitz"]["entscheidungsoptionen"]
        self.assertEqual([c["art"] for c in choices], ["garten"])
        result = agent.call_tool("estate_choice", {"candidate": 0})
        self.assertTrue(result["ok"])
        self.assertEqual(world.actions, [("Bauwerk", {"art": "garten", "feld": 3, "material": "boden", "hoehe": 2,
                                                "zahlung": "firma"})])
        self.assertTrue(changed_world("estate_choice", {"candidate": 0}, result))
        world.building = True
        self.assertEqual(estate_choices(world.observe()["mein_stammsitz"], world.observe()["meine_firma"]), [])
        self.assertFalse(agent.call_tool("estate_choice", {"candidate": 0})["ok"])
        world.building = False
        world.tower = True
        agent._nonworld_streak = 5
        self.assertEqual([tool["name"] for tool in agent.available_tools()], ["estate_choice"])


if __name__ == "__main__":
    unittest.main()
