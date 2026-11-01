"""Exercise negotiated haulage through the real HTTP adapter, without a model/key.

    python tests/mock_operations_api.py --godot /path/to/godot

The deterministic server is a test double, not an AI. It only uses observations
sent to the two players and never changes the simulation directly.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Scenario:
    def __init__(self):
        self.lock = threading.Lock()
        self.job = None
        self.calls = 0
        self.actions = []
        self.observations = {}
        self.errors = []
        self.delivered = False
        self.paid = False

    def respond(self, obs):
        cid = int(obs["ich"]["id"])
        self.observations[cid] = obs
        self.calls += 1
        ops = obs["betriebsablauf"]
        actions = []
        for agreement in obs.get("vertraege", []):
            if agreement["kind"] == "split_contract" and agreement["status"] == "erfüllt":
                self.delivered = True
                self.paid = self.paid or (cid == 1 and obs["ich"]["umsatz"] == int(float(agreement["price"])))
        incoming = [o for o in obs["angebote_an_dich"] if o.get("hilfe_angebot")]
        if incoming:
            offer = incoming[0]
            if cid == 0 and "counter_offer" not in self.actions:
                actions = [{"action": "counter_offer", "offer_id": offer["id"], "price": round(offer["preis"] * 0.95, 2)}]
            else:
                actions = [{"action": "accept_trade", "offer_id": offer["id"]}]
        elif cid == 1:
            inquiries = [r for r in ops["hilfeanfragen"] if not r["own"] and not r["quote_pending"]]
            if inquiries:
                r = inquiries[0]
                actions = [{"action": "quote_transport_help", "request_id": r["id"], "fee": round(r["max_fee"] * 0.9, 2)}]
        elif self.job is None:
            helper = self.observations.get(1)
            if helper:
                spec = helper["fahrzeugmodelle"][helper["fahrzeuge"][0]["modell"]]
                candidates = [k for k in obs["markt"] if k["menge"] <= spec["kapazitaet"]
                              and not k["kuehlung"] and not k["schwer"]
                              and k["min_reputation"] <= helper["ich"]["reputation"]
                              and k["frist_in_min"] > 200 and k["verguetung"] > 100]
                if candidates:
                    k = max(candidates, key=lambda item: item["frist_in_min"])
                    self.job = k["id"]
                    actions = [{"action": "accept_contract", "contract_id": k["id"]},
                               {"action": "request_transport_help", "contract_id": k["id"], "max_fee": round(k["verguetung"] * 0.4, 2)}]
            if not actions and "collect_contracts" not in self.actions:
                actions = [{"action": "collect_contracts"}]
        if not actions:
            actions = [{"action": "wait"}]
        self.actions.extend(a["action"] for a in actions)
        return {"summary": "HTTP-Test: konkrete Fracht anfragen, Preis verhandeln, Lieferung abwarten.",
                "actions": actions}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--seconds", type=int, default=50)
    args = parser.parse_args()
    scenario = Scenario()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            try:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                obs = json.loads(body["messages"][-1]["content"].rsplit("BEOBACHTUNG:\n", 1)[1])
                with scenario.lock:
                    result = scenario.respond(obs)
                payload = json.dumps({"choices": [{"message": {"content": json.dumps(result)}}],
                                      "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}).encode()
                self.send_response(200)
            except Exception as exc:
                scenario.errors.append(str(exc))
                payload = b'{"error":{"message":"mock scenario failed"}}'
                self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    command = [args.godot, "--headless", "--path", str(Path(__file__).resolve().parents[1]), "--",
               "--autotest", "--players=2", f"--seconds={args.seconds}", "--speed=8", "--map=128", "--seed=21",
               "--weather=sim", "--fault=0", "--interval=1", "--timeout=5", "--provider=openai",
               f"--base-url=http://127.0.0.1:{server.server_port}/v1", "--model=operations-test-double"]
    try:
        env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=args.seconds * 3 + 45)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    print(result.stdout)
    print(result.stderr)
    expected = {"request_transport_help", "quote_transport_help", "counter_offer", "accept_trade"}
    assert result.returncode == 0 and "AUTOTEST OK" in result.stdout, "game did not finish cleanly"
    assert "SCRIPT ERROR" not in result.stderr and "AUTOTEST FEHLER" not in result.stdout, "runtime error"
    assert not scenario.errors, scenario.errors
    assert expected.issubset(set(scenario.actions)), scenario.actions
    assert scenario.delivered and scenario.paid, "negotiated contract was not delivered and settled"
    stats = re.findall(r"Anfragen\s+\d+ ok\s+\d+ fehl\s+(\d+) ungültig\s+(\d+)\s+Aktionen\s+\d+/(\d+)", result.stdout)
    assert len(stats) == 2 and all(tuple(map(int, s)) == (0, 0, 0) for s in stats), stats
    print(f"HTTP OPERATIONS OK: {scenario.calls} responses, {scenario.job} delivered, counteroffer paid once.")


if __name__ == "__main__":
    main()
