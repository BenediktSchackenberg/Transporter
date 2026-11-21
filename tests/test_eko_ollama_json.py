"""Ollama-500 bei kaputtem Tool-JSON darf die KI nicht in eine Fehlerschleife schicken."""
import io
import json
import sys
import unittest
import urllib.error
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools" / "eko"))
import eko_ollama


class Response:
    def __init__(self, payload):
        self.payload = json.dumps(payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self):
        return self.payload


class JsonToolFallbackTest(unittest.TestCase):
    def test_contract_choice_uses_fresh_visible_ids(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="unternehmer")
        agent._opening_foundation = agent._opening_hall = agent._opening_home = agent._opening_freight = False
        agent._passive_streak = 0
        sent = []
        agent.world = SimpleNamespace(
            observe=lambda: {"meine_firma": {"transportchancen": [{"contract_id": "A581", "vehicle_id": 2,
                                                                    "deckungsbeitrag_geschaetzt": 927}]}},
            act=lambda typ, data: sent.append((typ, data)) or {"ok": True, "msg": "angenommen"})
        result = agent.call_tool("contract_choice", {"candidate": 0})
        self.assertTrue(result["ok"])
        self.assertEqual(result["gewaehlt"]["contract_id"], "A581")
        self.assertEqual(sent, [("Firma", {"aktion": {"action": "accept_contract", "contract_id": "A581", "vehicle_id": 2}})])
        self.assertFalse(agent.call_tool("contract_choice", {"candidate": 2})["ok"])
        self.assertEqual(len(sent), 1)

    def test_founding_does_not_force_first_freight_or_hide_company_planning(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="unternehmer")
        sent = []
        agent.world = SimpleNamespace(act=lambda typ, data: sent.append((typ, data)) or {"ok": True})
        agent.observation_status({"ok": True, "meine_firma": {
            "siedlung": {"betriebshof": True, "buergeramt": True, "fertige_wohnhaeuser": 1},
            "lieferungen": 0, "meine_auftraege": [], "transportchancen": [{"contract_id": "A42", "vehicle_id": 1}],
            "dispositionsvorgaben": {"von_dir_gesetzt": False}}})
        self.assertIn("company_plan", [tool["name"] for tool in agent.model_tools()])
        self.assertTrue(agent.call_tool("company_plan", {"ziel": "Stadtbaustoffe liefern", "schritte": ["Auftrag wählen"]})["ok"])
        self.assertEqual(sent[0][1]["aktion"]["action"], "set_plan")
        agent.observation_status({"ok": True, "meine_firma": {
            "siedlung": {"betriebshof": True, "buergeramt": True, "fertige_wohnhaeuser": 1},
            "lieferungen": 1, "meine_auftraege": [], "transportchancen": [],
            "dispositionsvorgaben": {"von_dir_gesetzt": True}}})
        self.assertIn("company_plan", [tool["name"] for tool in agent.model_tools()])

    def test_invalid_native_tool_call_uses_structured_json_and_stays_there(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="unternehmer", anbieter="ollama", model="local-test",
                                     ollama="http://127.0.0.1:11435", ctx=16384, think=False, name="Greta")
        agent._opening_foundation = agent._opening_hall = agent._opening_home = agent._opening_freight = False
        agent._passive_streak = 0
        agent.urgency = 0
        agent.log = io.StringIO()
        requests = []

        def urlopen(request, timeout):
            body = json.loads(request.data)
            requests.append(body)
            if "tools" in body:
                raise urllib.error.HTTPError(request.full_url, 500, "error", {}, io.BytesIO(
                    b'{"error":"llama-server returned invalid tool call arguments for \\"act\\": unexpected end of JSON input"}'))
            return Response({"message": {"content": '{"tool":"act","arguments":{"type":"LKW","data":{"ziel":[202,269]}}}'}})

        messages = [{"role": "system", "content": "System"}, {"role": "user", "content": "Fahre zum Bauplatz"}]
        with patch.object(eko_ollama.urllib.request, "urlopen", side_effect=urlopen):
            first = agent.chat(messages)
            second = agent.chat(messages)
        self.assertEqual(first["tool_calls"][0]["function"]["arguments"]["data"]["ziel"], [202, 269])
        self.assertEqual(second["tool_calls"][0]["function"]["name"], "act")
        self.assertEqual(len(requests), 3)
        self.assertNotIn("tools", requests[1])
        self.assertIn("format", requests[1])
        self.assertNotIn("tools", requests[2])

    def test_menu_fields_are_not_passed_as_tool_arguments(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="unternehmer", model="local-test", ollama="http://127.0.0.1:11435",
                                     ctx=16384, name="Viktor")
        agent._opening_foundation = agent._opening_hall = agent._opening_home = agent._opening_freight = False
        agent._passive_streak = 0
        agent.urgency = 0
        with patch.object(eko_ollama.urllib.request, "urlopen", return_value=Response(
                {"message": {"content": '{"tool":"observe","arguments":{"felder":["voll"]}}'}})):
            result = agent.chat_json_tool([{"role": "user", "content": "Beobachte"}])
        self.assertEqual(result["tool_calls"][0]["function"]["arguments"], {})

    def test_mayor_action_accepts_flat_model_parameters(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="buergermeister", model="local-test", ollama="http://127.0.0.1:11435",
                                     ctx=16384, name="Ingrid")
        agent._passive_streak = 0
        agent.urgency = 2
        agent.log = io.StringIO()
        with patch.object(eko_ollama.urllib.request, "urlopen", return_value=Response(
                {"message": {"content": '{"tool":"mayor_action","arguments":{"action":"stromtrasse_bauen",'
                                        '"option":"ST1","reason":"Wohnungen anschliessen"}}'}})):
            result = agent.chat_json_tool([{"role": "user", "content": "Versorge die Stadt"}])
        self.assertEqual(result["tool_calls"][0]["function"]["arguments"],
                         {"action": "stromtrasse_bauen", "params": {"option": "ST1", "reason": "Wohnungen anschliessen"}})

    def test_json_mode_survives_invalid_model_response(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="buergermeister", anbieter="ollama", model="local-test",
                                     ollama="http://127.0.0.1:11435", ctx=16384, think=False, name="Ingrid")
        agent._passive_streak = 0
        agent.urgency = 2
        agent.log = io.StringIO()
        agent._ollama_json_mode = True
        responses = iter([Response({"message": {"content": '{"tool":"mayor_action","arguments":{}}'}}),
                          Response({"message": {"content": '{"tool":"mayor_action","arguments":'
                                                           '{"action":"stromtrasse_bauen","option":"ST1"}}'}})])
        with patch.object(eko_ollama.urllib.request, "urlopen", side_effect=lambda *_args, **_kwargs: next(responses)):
            with self.assertRaises(eko_ollama.ModelGlitch):
                agent.chat([{"role": "user", "content": "Verbinde die Stadt"}])
            result = agent.chat([{"role": "user", "content": "Versuche es erneut"}])
        self.assertTrue(agent._ollama_json_mode)
        self.assertEqual(result["tool_calls"][0]["function"]["arguments"]["params"]["option"], "ST1")

    def test_repeated_observation_requires_next_step(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="unternehmer", model="local-test", ollama="http://127.0.0.1:11435",
                                     ctx=16384, name="Viktor")
        agent._opening_foundation = agent._opening_hall = agent._opening_home = agent._opening_freight = False
        agent._passive_streak = 0
        agent.urgency = 0
        agent._observe_streak = 2
        requests = []

        def urlopen(request, timeout):
            requests.append(json.loads(request.data))
            return Response({"message": {"content": '{"tool":"wait","arguments":{"seconds":10}}'}})

        with patch.object(eko_ollama.urllib.request, "urlopen", side_effect=urlopen):
            result = agent.chat_json_tool([{"role": "user", "content": "Lage ist bekannt"}])
        self.assertNotIn("observe", requests[0]["format"]["properties"]["tool"]["enum"])
        self.assertEqual(result["tool_calls"][0]["function"]["name"], "wait")


if __name__ == "__main__":
    unittest.main()
