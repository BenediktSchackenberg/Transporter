"""Eko-Modus mit lokalem Modell (Ollama): freies Wesen ohne Ziel, Gedaechtnis als Dateien (Idee nach Clawblox, MIT).

Wie start_eko.ps1, aber statt Claude Code steuert ein lokales Modell ueber Werkzeugaufrufe (Ollama /api/chat, tools):
observe, act, wait, list_files, read_file, write_file, append_memory. Das Wesen wird vom Skript angemeldet; das Modell
handelt nur ueber diese Werkzeuge und darf nur Dateien in seinem Arbeitsordner lesen und schreiben.

    python tools/eko/eko_ollama.py                      # Lumo, der kleine Roboter vom Smaragdstern
    python tools/eko/eko_ollama.py --name Mia --art mensch --seele "" --model qwen3.5:9b-q4_K_M

Nur Standardbibliothek. Abbruch mit Strg+C; das Gedaechtnis bleibt im Arbeitsordner.
"""
import argparse
import json
import os
import shutil
import sys
import time
import traceback
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTINUE = "Bitte nicht aufhören. Mach einfach weiter mit dem, was du tun möchtest."
REFLECT = ("Nimm dir kurz Zeit: Wie fühlst du dich gerade (observe → gefuehle)? Halte Wichtiges in EPISODIC_MEMORY.jsonl "
           "(append_memory) und geprüftes Wissen in SEMANTIC_MEMORY.md fest. Danach mach weiter, womit du willst.")
MAX_MESSAGES = 60          # Gespraechslaenge, danach werden die aeltesten Schritte verworfen (das Gedaechtnis liegt in Dateien)
KEEP_MESSAGES = 36
MAX_CHARS = 30000          # Textlaenge des Verlaufs (~10.000 Token): darueber lief das 16k-Kontextfenster ueber (Ollama HTTP 500, 15.11.)
REFLECT_EVERY = 40         # Werkzeugschritte zwischen zwei Erinnerungen an das Gedaechtnis

TOOLS = [
    {"name": "observe", "description": "Sieh dich um: wo du bist, was du trägst, Karte der Umgebung (21x21 Felder), Blöcke, "
     "Gebäude, Bauhöfe, andere Wesen, deine letzten Ereignisse.", "parameters": {"type": "object", "properties": {}}},
    {"name": "act", "description": "Eine Handlung in der Welt. type: MoveTo {tile:[x,y]}, Stop {}, Pickup {material, count} am "
     "Bauhof oder Pickup {block:[x,y,z]} oder Pickup {job} (Kisten eines Botengangs abholen), Place {block:[x,y,z], material?}, "
     "Say {text}, Talk {to, text} (mit einer Figur oder einem Wesen in der Nähe reden, höchstens 3 Felder; Unternehmer antworten), "
     "AcceptJob {job} (Arbeit einer Firma aus jobangebote annehmen), Deliver {job} (Auftrag abliefern, Lohn bekommen), "
     "BuyPlot {plot} (Wohngrundstück kaufen, höchstens 6 Felder entfernt), OrderHouse {wand?: ziegel|holz|stein|beton} "
     "(Baufirma baut dir ein Haus), Rest {} (ausruhen und Akku laden: draußen langsam, zu Hause in der Ladestation schnell), FoundCompany {name?, behalten?} (eigene "
     "Transportfirma gründen, ab 1.500 EUR Ersparnissen, Kapitalgeber legt 20.000 EUR dazu), Firma {aktion: {action, ...}} (deine Firma "
     "führen, siehe meine_firma.aktionen), MoveIn {} (in das selbst gebaute Haus auf deinem Grundstück einziehen), "
     "Amt {aktion: {action, ...}} (nur Bürgermeister: Amtshandlung, siehe mein_amt.aktionen). Material und "
     "Einrichtung (bett, ladestation, tisch, lampe, ...) kaufst du mit Pickup am Bauhof, Preise in material_preise. "
     "Blockraster: 4x4 Blöcke je Feld, z = Schicht ab 0.",
     "parameters": {"type": "object", "properties": {
         "type": {"type": "string", "enum": ["MoveTo", "Stop", "Pickup", "Place", "Say", "Talk", "AcceptJob", "Deliver", "BuyPlot", "OrderHouse", "Rest", "FoundCompany", "Firma", "MoveIn", "Amt"]},
         "data": {"type": "object", "description": "Parameter der Handlung, z. B. {\"tile\": [30, 12]}"}},
         "required": ["type", "data"]}},
    {"name": "wait", "description": "Warte einige Sekunden (z. B. während du gehst).",
     "parameters": {"type": "object", "properties": {"seconds": {"type": "number"}}, "required": ["seconds"]}},
    {"name": "list_files", "description": "Dateien in deinem Arbeitsordner.", "parameters": {"type": "object", "properties": {}}},
    {"name": "read_file", "description": "Datei aus deinem Arbeitsordner lesen.",
     "parameters": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}},
    {"name": "write_file", "description": "Datei in deinem Arbeitsordner schreiben (überschreibt). Nicht für EPISODIC_MEMORY.jsonl.",
     "parameters": {"type": "object", "properties": {"name": {"type": "string"}, "content": {"type": "string"}},
                    "required": ["name", "content"]}},
    {"name": "append_memory", "description": "Ein Erlebnis an EPISODIC_MEMORY.jsonl anhängen (zeit, wo, was, warum?, gefuehl?).",
     "parameters": {"type": "object", "properties": {"entry": {"type": "object"}}, "required": ["entry"]}},
]


class World:
    def __init__(self, base, name):
        self.base = base
        self.name = name
        self.token = ""
        self.art = "mensch"

    def _req(self, method, path, body=None, retry=True):
        r = self._send(method, path, body)
        # Welt neu gestartet: alter Token ungueltig (401) -> automatisch neu anmelden und einmal wiederholen
        if retry and isinstance(r, dict) and "X-Session" in str(r.get("msg", "")) and not path.startswith("/join"):
            try:
                self.join(self.art)
            except Exception:
                return r
            return self._send(method, path, body)
        return r

    def _send(self, method, path, body=None):
        data = json.dumps(body).encode("utf-8") if body is not None else (b"" if method == "POST" else None)
        req = urllib.request.Request(self.base + path, data=data, method=method)
        if self.token:
            req.add_header("X-Session", self.token)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                raw = r.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8")
        except (urllib.error.URLError, OSError) as e:   # Welt kurz nicht erreichbar: als Ergebnis zurueckgeben, nicht abstuerzen
            return {"ok": False, "msg": "Welt nicht erreichbar (%s). Später erneut versuchen." % e}
        return json.loads(raw) if raw.startswith(("{", "[")) else raw

    def join(self, art="mensch"):
        self.art = art
        r = self._send("POST", "/join?name=" + urllib.request.quote(self.name) + "&art=" + art)
        self.token = r["session"]

    def api_md(self):
        req = urllib.request.Request(self.base + "/api.md")
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.read().decode("utf-8")

    def observe(self):
        return self._req("GET", "/observe")

    def act(self, typ, data):
        return self._req("POST", "/input", {"type": typ, "data": data or {}})


def compact_obs(o):
    """Beobachtung fuer kleine Kontexte: Karte als Zeilen, Bloecke gekuerzt."""
    if not isinstance(o, dict) or not o.get("ok", False):
        return o
    o = dict(o)
    blocks = o.get("bloecke_in_der_naehe", [])
    if len(blocks) > 60:
        o["bloecke_in_der_naehe"] = blocks[:60]
        o["bloecke_hinweis"] = "%d Blöcke in der Nähe, die ersten 60 gezeigt" % len(blocks)
    return o


class Agent:
    def __init__(self, args):
        self.args = args
        self._repeat = 0
        self._last_fail = ""
        self.dir = Path(args.root) / args.name
        self.ws = self.dir / "workspace"
        self.logs = self.dir / "logs"
        self.ws.mkdir(parents=True, exist_ok=True)
        self.logs.mkdir(parents=True, exist_ok=True)
        for f in (HERE / "vorlage").iterdir():
            if not (self.ws / f.name).exists():
                shutil.copy(f, self.ws / f.name)
                if f.name == "SOUL.md" and args.seele:   # eigene Seele nur beim ersten Start, danach gehoert die Datei dem Wesen
                    soul = (HERE / "seelen" / (args.seele + ".md")).read_text(encoding="utf-8")
                    soul = soul.replace("{NAME}", args.name).replace("{FIRMA}", getattr(args, "firma", "") or "meine Firma") \
                        .replace("{STADT}", getattr(args, "stadt", "") or "meiner Stadt")
                    (self.ws / "SOUL.md").write_text(soul, encoding="utf-8")
        (self.ws / "EPISODIC_MEMORY.jsonl").touch()
        self.world = World("http://127.0.0.1:%d" % args.port, args.name)
        self.log = open(self.logs / "sitzung.log", "a", encoding="utf-8")

    def _path(self, name):
        p = (self.ws / str(name)).resolve()
        if self.ws.resolve() not in p.parents and p != self.ws.resolve():
            raise ValueError("Nur Dateien in deinem Arbeitsordner.")
        return p

    def system_prompt(self):
        base = (HERE / "systemprompt.md").read_text(encoding="utf-8")
        base = base.replace("${NAME}", self.args.name).replace("${WORKSPACE}", "deinem Arbeitsordner").replace("${BASE}", self.world.base)
        # Der Zugang laeuft hier ueber Werkzeuge statt curl: die letzten beiden Zeilen ersetzen
        lines = [ln for ln in base.splitlines() if "HTTP" not in ln and "api.md" not in ln and "curl" not in ln]
        lines.append("Du bist bereits in der Welt angemeldet. Andere Figuren und Wesen kannst du mit act Talk ansprechen; "
                     "was in deiner Nähe gesagt wird, steht in observe unter gehoert. Du handelst nur über deine Werkzeuge: observe, act, wait, "
                     "list_files, read_file, write_file, append_memory. Antworte kurz; denke in Taten.")
        lines.append("\nBeschreibung deiner Welt:\n" + self.world.api_md().split("## Endpunkte")[0])
        return "\n".join(lines)

    def call_tool(self, name, a):
        try:
            if name == "observe":
                return compact_obs(self.world.observe())
            if name == "act":
                data = a.get("data", {})
                if isinstance(data, str):
                    data = json.loads(data) if data.strip().startswith("{") else {}
                r = self.world.act(str(a.get("type", "")), data)
                if str(a.get("type", "")) == "Rest" and isinstance(r, dict) and r.get("ok"):
                    time.sleep(20)   # die Pause wirklich abwarten (das Modell schickte sonst alle 2 s erneut Rest)
                    r["msg"] = str(r.get("msg", "")) + " Die Pause ist vorbei."
                obs = r.pop("beobachtung", {}) if isinstance(r, dict) else {}
                if isinstance(obs, dict) and obs.get("ok"):
                    r["du"] = obs.get("du")
                return r
            if name == "wait":
                s = max(0.5, min(20.0, float(a.get("seconds", 3))))
                time.sleep(s)
                return {"ok": True, "gewartet_s": s}
            if name == "list_files":
                return sorted(p.name for p in self.ws.iterdir())
            if name == "read_file":
                return self._path(a["name"]).read_text(encoding="utf-8")[:6000]
            if name == "write_file":
                if str(a["name"]).endswith("EPISODIC_MEMORY.jsonl"):
                    return {"ok": False, "msg": "EPISODIC_MEMORY.jsonl nur mit append_memory erweitern."}
                self._path(a["name"]).write_text(str(a["content"]), encoding="utf-8")
                return {"ok": True}
            if name == "append_memory":
                with open(self.ws / "EPISODIC_MEMORY.jsonl", "a", encoding="utf-8") as f:
                    f.write(json.dumps(a.get("entry", {}), ensure_ascii=False) + "\n")
                return {"ok": True}
            return {"ok": False, "msg": "Unbekanntes Werkzeug %s" % name}
        except Exception as e:   # Fehler gehen als Ergebnis an das Modell zurueck
            return {"ok": False, "msg": "%s: %s" % (type(e).__name__, e)}

    def chat(self, messages):
        body = {"model": self.args.model, "messages": messages, "stream": False, "think": self.args.think,
                "tools": [{"type": "function", "function": t} for t in TOOLS],
                "options": {"num_ctx": self.args.ctx, "temperature": 0.8}}
        req = urllib.request.Request(self.args.ollama + "/api/chat", data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            return json.loads(r.read().decode("utf-8"))["message"]

    def say(self, text):
        line = time.strftime("%H:%M:%S ") + text
        print("%s [%s] %s" % (line[:9], self.args.name, text), flush=True)   # im Schwarm-Fenster: wer spricht
        self.log.write(line + "\n")
        self.log.flush()

    def trim(self, messages, hard=False):
        """Aelteste Schritte verwerfen (nach Anzahl und Textlaenge), ohne ein Werkzeugergebnis von seinem Aufruf zu trennen."""
        size = lambda ms: sum(len(json.dumps(m, ensure_ascii=False)) for m in ms)
        if not hard and len(messages) <= MAX_MESSAGES and size(messages) <= MAX_CHARS:
            return messages
        keep = 8 if hard else KEEP_MESSAGES
        out = messages[-keep:]
        while len(out) > 4 and size(out) > MAX_CHARS * 0.6:
            out = out[2:]
        while out and out[0]["role"] == "tool":   # Werkzeugergebnis ohne seinen Aufruf verwerfen
            out.pop(0)
        out.insert(0, {"role": "user", "content": "(Ältere Schritte sind ausgeblendet; dein Gedächtnis steht in deinen Dateien.) " + CONTINUE})
        return out

    def run(self):
        self.world.join(self.args.art)
        system = {"role": "system", "content": self.system_prompt()}
        messages = [{"role": "user", "content": "Beginne. Lies zuerst deine Dateien (list_files, read_file)."}]
        steps = 0
        while self.args.max_steps == 0 or steps < self.args.max_steps:
            messages = self.trim(messages)
            try:
                msg = self.chat([system] + messages)
            except Exception as e:   # Ollama ueberlastet oder Kontext voll: protokollieren, Verlauf kuerzen, kurz warten, weitermachen
                self.say("⚠ Modellaufruf fehlgeschlagen: %s – Verlauf gekürzt, neuer Versuch in 10 s" % e)
                messages = self.trim(messages, hard=True)
                self.log.write(traceback.format_exc())
                time.sleep(10)
                continue
            calls = msg.get("tool_calls") or []
            messages.append({"role": "assistant", "content": msg.get("content", ""), "tool_calls": calls} if calls
                            else {"role": "assistant", "content": msg.get("content", "")})
            if msg.get("content", "").strip():
                self.say("💭 " + msg["content"].strip().replace("\n", " ")[:300])
            if not calls:
                messages.append({"role": "user", "content": CONTINUE})
                continue
            for c in calls:
                fn = c["function"]
                a = fn.get("arguments") or {}
                if isinstance(a, str):
                    try:
                        a = json.loads(a)
                    except ValueError:
                        a = {}
                res = self.call_tool(fn["name"], a)
                steps += 1
                short = json.dumps(a, ensure_ascii=False)[:120]
                verdict = (res.get("msg", "") if isinstance(res, dict) else "")[:100]
                self.say("→ %s %s %s" % (fn["name"], short, ("· " + verdict) if verdict else ""))
                messages.append({"role": "tool", "tool_name": fn["name"], "content": json.dumps(res, ensure_ascii=False)[:14000]})
                # Schleifenbremse: dieselbe fehlgeschlagene Handlung dreimal hintereinander -> deutlicher Hinweis (Ralf fragte Greta 20-mal)
                failed = isinstance(res, dict) and res.get("ok") is False
                key = fn["name"] + json.dumps(a, sort_keys=True, ensure_ascii=False) if failed else ""
                self._repeat = self._repeat + 1 if key and key == getattr(self, "_last_fail", "") else (1 if key else 0)
                self._last_fail = key
                if self._repeat >= 3:
                    messages.append({"role": "user", "content": "Du wiederholst dich: Dieselbe Handlung ist jetzt %d-mal hintereinander gescheitert (%s). "
                                     "So klappt es nicht – lies die Rückmeldung genau und versuche etwas anderes." % (self._repeat, verdict)})
                    self.say("↺ Schleifenbremse nach %d gleichen Fehlschlägen" % self._repeat)
                    self._repeat = 0
            if steps % REFLECT_EVERY < len(calls):
                messages.append({"role": "user", "content": REFLECT})


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", default="Lumo")
    ap.add_argument("--art", default="roboter", choices=["roboter", "mensch"], help="Gestalt in der Welt")
    ap.add_argument("--seele", default="lumo", help="Persoenlichkeit aus tools/eko/seelen/<name>.md fuer den ersten Start (\"\" = neutrale Vorlage)")
    ap.add_argument("--port", type=int, default=8790)
    ap.add_argument("--model", default="hf.co/6block/Qwen3.8-27B-GGUF:IQ3_M")
    ap.add_argument("--ollama", default="http://127.0.0.1:11435")
    ap.add_argument("--root", default=os.path.join(os.path.expanduser("~"), "PixelTransportRivals-Eko"))
    ap.add_argument("--ctx", type=int, default=16384)
    ap.add_argument("--think", action="store_true", help="Denkmodus des Modells einschalten (langsamer)")
    ap.add_argument("--max-steps", type=int, default=0, help="0 = endlos")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    agent = Agent(args)
    while True:
        try:
            agent.run()
            break
        except KeyboardInterrupt:
            print("\nBeendet. Gedächtnis liegt in", Path(args.root) / args.name / "workspace")
            break
        except Exception as e:   # nichts darf das Wesen dauerhaft beenden: Fehler ins Protokoll, nach 10 s neu anmelden
            agent.say("⚠ Fehler: %s – Neustart in 10 s" % e)
            agent.log.write(traceback.format_exc())
            agent.log.flush()
            time.sleep(10)


if __name__ == "__main__":
    main()
