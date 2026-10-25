"""Lokaler OpenAI-kompatibler Mock-Server zum Testen des echten HTTP-Adapters (keine echte KI).

Aufruf:  python tools/mock_openai_server.py [port]   (Standard 8765)
Endpunkt: POST http://127.0.0.1:<port>/v1/chat/completions

Antwortet reihum mit: gueltigen Entscheidungen (aus der Beobachtung abgeleitet), HTTP 429 mit Retry-After,
ungueltigem JSON, verspaeteter Antwort (Timeout-Test) und HTTP 500. Prueft, dass ein Bearer-Key ankommt,
und gibt den Key selbst nie aus.
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = {"n": 0, "auth_ok": 0, "auth_missing": 0, "rejected_response_format": False}
PLAN = ["ok", "ok", "429", "ok", "invalid", "ok", "ok", "slow", "ok", "500", "ok", "ok"]


def decide(user_text):
    obs = json.loads(user_text.split("BEOBACHTUNG:\n", 1)[1])
    actions = []
    free = [v for v in obs["fahrzeuge"] if v["status"] in ("bereit", "fährt zum Depot") and not v["warteschlange"] and v["fahrer"]]
    models = obs["fahrzeugmodelle"]
    for v in free:
        cap = models[v["modell"]]
        for k in obs["markt"]:
            if k["menge"] <= cap["kapazitaet"] and (not k["kuehlung"] or cap["kuehlung"]) and (not k["schwer"] or cap["schwer"]) \
                    and obs["ich"]["reputation"] >= k["min_reputation"]:
                actions.append({"action": "accept_contract", "contract_id": k["id"], "vehicle_id": v["id"]})
                obs["markt"].remove(k)
                break
    for o in obs["angebote_an_dich"]:
        actions.append({"action": "accept_trade", "offer_id": o["id"]})
    if obs["konkurrenten"] and STATE["n"] % 3 == 0:
        r = obs["konkurrenten"][0]
        actions.append({"action": "send_message", "to": str(r["id"]), "private": False,
                        "text": "Hallo %s, ich bin ein Mock-Modell und teste die Schnittstelle." % r["name"]})
    actions.append({"action": "fly_to_moon"})  # absichtlich ungueltig: muss abgelehnt werden
    return {"summary": "Ich (Mock-Modell) disponiere freie Fahrzeuge auf passende Aufträge.", "actions": actions,
            "memory": "Mock-Test Runde %d" % STATE["n"]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        if not self.path.endswith("/chat/completions"):
            self.send_error(404)
            return
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        auth = self.headers.get("Authorization", "")
        STATE["auth_ok" if auth.startswith("Bearer ") and len(auth) > 12 else "auth_missing"] += 1
        # Kompatibilitaetstest: erste Anfrage mit response_format wird abgelehnt
        if "response_format" in body and not STATE["rejected_response_format"]:
            STATE["rejected_response_format"] = True
            return self._json(400, {"error": {"message": "Unsupported parameter: response_format"}})
        mode = PLAN[STATE["n"] % len(PLAN)]
        STATE["n"] += 1
        print("Anfrage %d (%s) Modell=%s Auth=%s" % (STATE["n"], mode, body.get("model"), "ja" if auth else "nein"), flush=True)
        if mode == "429":
            return self._json(429, {"error": {"message": "Rate limit"}}, {"Retry-After": "2"})
        if mode == "500":
            return self._json(500, {"error": {"message": "Interner Fehler (simuliert)"}})
        if mode == "slow":
            time.sleep(30)
        content = "Das ist kein JSON {kaputt" if mode == "invalid" else json.dumps(decide(body["messages"][-1]["content"]), ensure_ascii=False)
        self._json(200, {"id": "mock", "object": "chat.completion", "model": body.get("model"),
                         "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
                         "usage": {"prompt_tokens": 1500, "completion_tokens": 120, "total_tokens": 1620}})

    def _json(self, code, data, headers=None):
        raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            print("Client hat die Verbindung geschlossen (Timeout auf Spielseite).", flush=True)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("Mock-Server auf http://127.0.0.1:%d/v1" % port, flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Statistik: Anfragen=%d Auth_ok=%d Auth_fehlt=%d" % (STATE["n"], STATE["auth_ok"], STATE["auth_missing"]))
