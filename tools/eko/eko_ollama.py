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
import threading
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
DAY_STEPS = 150            # Schlaf-Zyklus wie bei Eko: nach so vielen Schritten endet der "Tag" (Sitzung)
NIGHT_STEPS = 8            # so viele Schritte bleiben, um das Gedaechtnis zu schreiben
EVENING = ("Dein Tag geht zu Ende. Schreib jetzt das Wichtigste auf: Erlebnisse mit append_memory, geprüftes Wissen und gute "
           "Abläufe in SEMANTIC_MEMORY.md, deine Pläne für morgen. Gleich schläfst du, danach weißt du nur noch, was in deinen Dateien steht.")
MORNING = "Ein neuer Tag beginnt. Lies zuerst deine Dateien (list_files, read_file), dann schau dich um (observe)."
# Wissen in SEMANTIC_MEMORY.md, getrennt nach Art (Werkzeug learn); Fehlschlaege und Bewaehrtes kommen in jede neue Sitzung
SECTIONS = {"tatsache": "## Beobachtete Tatsachen", "vermutung": "## Vermutungen (noch nicht geprüft)",
            "technik": "## Erprobte Techniken", "fehlschlag": "## Fehlgeschlagene Ansätze",
            "strategie": "## Wiederholbar erfolgreiche Strategien", "korrektur": "## Korrekturen (widerlegte Annahmen)"}
DIGEST = ("fehlschlag", "strategie", "korrektur")
ARRIVAL_MAX_S = 90          # wait bis=ankunft: so lange hoechstens auf die Ankunft warten (ohne Modellaufruf)


class FairGate:
    """Faire Reihenfolge am lokalen Modellserver: Wesen im Schwarm (Threads) kommen der Reihe nach dran (Wartemarken)."""
    def __init__(self):
        self.cv = threading.Condition()
        self.next_ticket = 0
        self.serving = 0

    def __enter__(self):
        with self.cv:
            me = self.next_ticket
            self.next_ticket += 1
            while me != self.serving:
                self.cv.wait()

    def __exit__(self, *exc):
        with self.cv:
            self.serving += 1
            self.cv.notify_all()


MODEL_GATE = FairGate()

TOOLS = [
    {"name": "observe", "description": "Sieh dich um: wo du bist, was du trägst, Karte der Umgebung (21x21 Felder), Blöcke, "
     "Gebäude, Bauhöfe, andere Wesen, deine letzten Ereignisse.", "parameters": {"type": "object", "properties": {}}},
    {"name": "act", "description": "Eine Handlung in der Welt. type: MoveTo {tile:[x,y]}, Stop {}, Pickup {material, count} am "
     "Bauhof oder Pickup {block:[x,y,z]} oder Pickup {job} (Kisten eines Botengangs abholen), Place {block:[x,y,z], material?}, "
     "Say {text}, Talk {to, text} (mit einer Figur oder einem Wesen in der Nähe reden, höchstens 3 Felder; Unternehmer antworten), "
     "Inspect {target_id} (sichtbares Gebäude, Wesen, Unternehmer oder Grundstück G… genauer ansehen; ändert nichts), "
     "Attack {ziel, waffe} (Ziel: ein Wesen, ein Gebäude per Name oder building_<id>, ein Fahrzeug fahrzeug_<id>) oder Attack {waffe, feld} "
     "(Sprengsatz auf ein Feld, z. B. eine Straße; Bombe ablegen). Alles Gebaute kann beschädigt und zerstört werden. Gewalt ist verboten, "
     "die Polizei steht auf der Seite der Bürger und bestraft oft. "
     "Give {to, waffe} (getragene Waffe einem Wesen in der Nähe geben), Pickup {waffe} (fertige Waffe an deiner eigenen Waffenschmiede holen), "
     "Bauwerk {art: mauer|zaun|burg|festung|schloss|turm|garten, feld 0-8, material?, hoehe?, zahlung?: firma} (auf deinem Stammsitz bauen lassen, "
     "siehe mein_stammsitz), Tor {offen: true|false} (Tor deines Stammsitzes), "
     "Ziel {ziel, warum, teilziele?, nutzen?, ressourcen?, erwartung?, abbruch?, ersetzen?} (dein Hauptziel; ein aktives Ziel ersetzt du nur bewusst), "
     "ZielStand {fortschritt 0-100?, teilziel_erledigt?, status?: aktiv|erreicht|aufgegeben, notiz?}, "
     "AcceptJob {job} (Arbeit einer Firma aus jobangebote annehmen), Deliver {job} (Auftrag abliefern, Lohn bekommen), "
     "BuyPlot {plot} (Wohngrundstück kaufen, höchstens 6 Felder entfernt), OrderHouse {wand?: ziegel|holz|stein|beton} "
     "(Baufirma baut dir ein Haus), Rest {} (ausruhen und Akku laden: draußen langsam, zu Hause in der Ladestation schnell), FoundCompany {name?, behalten?} (eigene "
     "Transportfirma gründen, ab 1.500 EUR Ersparnissen, Kapitalgeber legt 20.000 EUR dazu), Firma {aktion: {action, ...}} (deine Firma "
     "führen, siehe meine_firma.aktionen), MoveIn {} (in das selbst gebaute Haus auf deinem Grundstück einziehen), "
     "Amt {aktion: {action, ...}} (nur Bürgermeister: Amtshandlung, siehe mein_amt.aktionen), "
     "Ablauf {schritte: [{type, data}, ...]} (bis zu 30 Handlungen nacheinander; die Welt wartet nach MoveTo auf die Ankunft "
     "und bricht beim ersten Fehler ab – spart dir viele Einzelschritte, z. B. Material holen, hingehen, mehrere Blöcke setzen). Material und "
     "Einrichtung (bett, ladestation, tisch, lampe, ...) kaufst du mit Pickup am Bauhof, Preise in material_preise. "
     "Blockraster: 4x4 Blöcke je Feld, z = Schicht ab 0.",
     "parameters": {"type": "object", "properties": {
         "type": {"type": "string", "enum": ["MoveTo", "Stop", "Pickup", "Place", "Say", "Talk", "Inspect", "Attack", "Give", "Bauwerk", "Tor", "Ziel", "ZielStand", "AcceptJob", "Deliver", "BuyPlot", "OrderHouse", "Rest", "FoundCompany", "Firma", "MoveIn", "Amt", "Ablauf"]},
         "data": {"type": "object", "description": "Parameter der Handlung, z. B. {\"tile\": [30, 12], \"warum\": \"Hafen erkunden\"}. "
                  "warum (kurz) ist bei jeder Handlung erlaubt und wird im Spiel angezeigt. Die Antwort hat status: laeuft, abgeschlossen, gescheitert oder doppelt."}},
         "required": ["type", "data"]}},
    {"name": "wait", "description": "Warte einige Sekunden – oder mit bis: \"ankunft\", bis du am Ziel deines MoveTo bist "
     "(höchstens 90 s, ohne dass du dazwischen nachdenken musst). Danach bekommst du deine Lage.",
     "parameters": {"type": "object", "properties": {"seconds": {"type": "number"}, "bis": {"type": "string", "enum": ["ankunft"]}}}},
    {"name": "learn", "description": "Eine Erkenntnis in SEMANTIC_MEMORY.md festhalten, getrennt nach Art: tatsache (beobachtet), "
     "vermutung (noch ungeprüft), technik (erprobt), fehlschlag (hat nicht geklappt – warum), strategie (wiederholbar erfolgreich), "
     "korrektur (eine frühere Annahme ist widerlegt; ersetzt = alter Text). Fehlschläge, Strategien und Korrekturen bekommst du jeden Morgen wieder vorgelegt.",
     "parameters": {"type": "object", "properties": {"art": {"type": "string", "enum": list(SECTIONS.keys())}, "text": {"type": "string"},
                                                    "ersetzt": {"type": "string"}}, "required": ["art", "text"]}},
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
    def __init__(self, base, name, keyfile=None):
        self.base = base
        self.name = name
        self.token = ""
        self.art = "mensch"
        self.keyfile = keyfile   # geheimer Schluessel des Wesens (ausserhalb des Arbeitsordners: das Modell sieht ihn nie)

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

    def _send(self, method, path, body=None, headers=None):
        data = json.dumps(body).encode("utf-8") if body is not None else (b"" if method == "POST" else None)
        req = urllib.request.Request(self.base + path, data=data, method=method)
        if self.token:
            req.add_header("X-Session", self.token)
        for k, v in (headers or {}).items():
            req.add_header(k, v)
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
        key = self.keyfile.read_text(encoding="utf-8").strip() if self.keyfile and self.keyfile.exists() else ""
        r = self._send("POST", "/join?name=" + urllib.request.quote(self.name) + "&art=" + art, headers={"X-Schluessel": key} if key else None)
        if not isinstance(r, dict) or "session" not in r:
            raise RuntimeError("Anmeldung abgelehnt: %s" % (r.get("msg", r) if isinstance(r, dict) else r))
        if r.get("schluessel") and self.keyfile:
            self.keyfile.write_text(r["schluessel"], encoding="utf-8")
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
        self.world = World("http://127.0.0.1:%d" % args.port, args.name, self.dir / "schluessel.txt")
        self._arrival_failed = set()
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
                if a.get("bis") == "ankunft":   # deterministisch warten, kein Modellaufruf je Schritt
                    t0 = time.time()
                    while time.time() - t0 < ARRIVAL_MAX_S:
                        o = self.world.observe()
                        if not isinstance(o, dict) or not o.get("ok") or not o.get("du", {}).get("unterwegs"):
                            break
                        time.sleep(1.5)
                    o = compact_obs(self.world.observe())
                    arrived = isinstance(o, dict) and not o.get("du", {}).get("unterwegs", False)
                    return {"ok": arrived, "status": "abgeschlossen" if arrived else "laeuft", "gewartet_s": round(time.time() - t0),
                            "msg": "angekommen" if arrived else "noch unterwegs", "lage": o}
                s = max(0.5, min(20.0, float(a.get("seconds", 3))))
                time.sleep(s)
                return {"ok": True, "gewartet_s": s}
            if name == "learn":
                return self.learn(str(a.get("art", "")), str(a.get("text", "")), str(a.get("ersetzt", "")))
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

    def learn(self, art, text, ersetzt=""):
        """Erkenntnis unter ihrer Art in SEMANTIC_MEMORY.md einordnen; korrektur streicht die widerlegte Annahme durch."""
        if art not in SECTIONS or not text.strip():
            return {"ok": False, "msg": "art muss eine von %s sein, text darf nicht leer sein." % ", ".join(SECTIONS)}
        p = self.ws / "SEMANTIC_MEMORY.md"
        doc = p.read_text(encoding="utf-8") if p.exists() else "# Wissen\n"
        if art == "korrektur" and ersetzt.strip() and ersetzt.strip() in doc:
            doc = doc.replace(ersetzt.strip(), "~~%s~~ (widerlegt)" % ersetzt.strip(), 1)
        head = SECTIONS[art]
        line = "- %s %s" % (time.strftime("%d.%m. %H:%M"), text.strip().replace("\n", " "))
        if head in doc:
            i = doc.index(head) + len(head)
            j = doc.find("\n## ", i)
            j = len(doc) if j < 0 else j
            doc = doc[:j].rstrip("\n") + "\n" + line + "\n" + ("\n" + doc[j:].lstrip("\n") if j < len(doc) else "")
        else:
            doc = doc.rstrip("\n") + "\n\n" + head + "\n" + line + "\n"
        p.write_text(doc, encoding="utf-8")
        self.world.act("Merke", {"art": art, "text": text[:160]})   # nur Anzeige im Spiel; das Wissen liegt in der Datei
        return {"ok": True, "msg": "unter „%s“ festgehalten" % head[3:]}

    def digest(self):
        """Gezielt in den Kontext: Fehlschlaege, bewaehrte Strategien, Korrekturen und das aktuelle Ziel."""
        p = self.ws / "SEMANTIC_MEMORY.md"
        doc = p.read_text(encoding="utf-8") if p.exists() else ""
        parts = []
        for k in DIGEST:
            head = SECTIONS[k]
            if head in doc:
                i = doc.index(head)
                j = doc.find("\n## ", i + len(head))
                parts.append(doc[i:j if j > 0 else len(doc)].strip()[-1200:])
        o = self.world.observe()
        goal = o.get("mein_ziel", {}) if isinstance(o, dict) else {}
        if goal:
            parts.append("## Dein aktuelles Ziel\n%s (%s, %s %%) – warum: %s" % (goal.get("ziel"), goal.get("status"), goal.get("fortschritt"), goal.get("warum")))
        return ("Erinnerung aus deinem Gedächtnis:\n" + "\n\n".join(parts)) if parts else ""

    def chat(self, messages):
        body = {"model": self.args.model, "messages": messages, "stream": False, "think": self.args.think,
                "tools": [{"type": "function", "function": t} for t in TOOLS],
                "options": {"num_ctx": self.args.ctx, "temperature": 0.8}}
        req = urllib.request.Request(self.args.ollama + "/api/chat", data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        with MODEL_GATE, urllib.request.urlopen(req, timeout=600) as r:   # der Reihe nach, fair fuer alle Wesen
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
        messages = [{"role": "user", "content": "Beginne. Lies zuerst deine Dateien (list_files, read_file). " + self.digest()}]
        steps = 0
        day_start = 0
        evening = False
        while self.args.max_steps == 0 or steps < self.args.max_steps:
            if not evening and steps - day_start >= DAY_STEPS:   # Abend: Gedaechtnis schreiben lassen
                evening = True
                messages.append({"role": "user", "content": EVENING})
                self.say("🌙 Abend – das Wesen schreibt sein Gedächtnis")
            elif evening and steps - day_start >= DAY_STEPS + NIGHT_STEPS:   # Schlaf: neue Sitzung, nur die Dateien bleiben
                evening = False
                day_start = steps
                messages = [{"role": "user", "content": MORNING + " " + self.digest()}]
                self.say("☀ Neuer Tag – frische Sitzung, Gedächtnis aus den Dateien")
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
                if failed and self._repeat == 1 and fn["name"] == "act":
                    with open(self.ws / "EPISODIC_MEMORY.jsonl", "a", encoding="utf-8") as f:
                        f.write(json.dumps({"zeit": time.strftime("%Y-%m-%d %H:%M"), "art": "fehlschlag", "was": "%s %s" % (a.get("type"), json.dumps(a.get("data", {}), ensure_ascii=False)[:120]),
                                            "ergebnis": verdict, "automatisch": True}, ensure_ascii=False) + "\n")
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
