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
    def test_invalid_native_tool_call_uses_structured_json_and_stays_there(self):
        agent = object.__new__(eko_ollama.Agent)
        agent.args = SimpleNamespace(rolle="unternehmer", anbieter="ollama", model="local-test",
                                     ollama="http://127.0.0.1:11435", ctx=16384, think=False, name="Greta")
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
        agent.urgency = 0
        with patch.object(eko_ollama.urllib.request, "urlopen", return_value=Response(
                {"message": {"content": '{"tool":"observe","arguments":{"felder":["voll"]}}'}})):
            result = agent.chat_json_tool([{"role": "user", "content": "Beobachte"}])
        self.assertEqual(result["tool_calls"][0]["function"]["arguments"], {})


if __name__ == "__main__":
    unittest.main()
