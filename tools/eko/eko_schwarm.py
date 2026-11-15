"""Eko-Schwarm: alle freien Wesen einer Partie gleichzeitig mit dem lokalen Modell (Ollama) laufen lassen.

Fragt die Welt (mit dem Betreiberschluessel aus user://eko_betreiber.txt), welche Wesen es gibt (Unternehmer, Buergermeister,
Lumo, ...), und startet fuer jedes einen Agenten aus eko_ollama.py in einem eigenen Faden – mit passender Seele
(tools/eko/seelen/<seele>.md), eigenem Arbeitsordner und Protokoll. Neue Wesen (z. B. nach einer Gruendung) kommen
automatisch dazu. Ollama arbeitet die Anfragen der Reihe nach ab.

    python tools/eko/eko_schwarm.py                     # Spiel vorher mit -- --eko-spieler starten
    python tools/eko/eko_schwarm.py --model qwen3.5:9b-q4_K_M

Abbruch mit Strg+C; jedes Gedaechtnis bleibt im Arbeitsordner seines Wesens.
"""
import argparse
import json
import os
import sys
import threading
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eko_ollama  # noqa: E402

TOKEN_FILE = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "Pixel Transport Rivals" / "eko_betreiber.txt"


def beings(base):
    req = urllib.request.Request(base + "/betreiber/wesen", headers={"X-Betreiber": TOKEN_FILE.read_text().strip()})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def run_agent(info, args):
    a = argparse.Namespace(**vars(args))
    a.name = info["name"]
    a.art = info.get("art", "mensch")
    a.seele = info.get("seele", "") or ""
    a.firma = info.get("firma", "")
    a.stadt = info.get("stadt", "")
    agent = eko_ollama.Agent(a)
    while True:   # wie eko_ollama.main: nichts beendet ein Wesen dauerhaft
        try:
            agent.run()
            return
        except Exception as e:
            agent.say("⚠ Fehler: %s – Neustart in 10 s" % e)
            time.sleep(10)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8790)
    ap.add_argument("--model", default="hf.co/6block/Qwen3.8-27B-GGUF:IQ3_M")
    ap.add_argument("--ollama", default="http://127.0.0.1:11435")
    ap.add_argument("--root", default=os.path.join(os.path.expanduser("~"), "PixelTransportRivals-Eko"))
    ap.add_argument("--ctx", type=int, default=16384)
    ap.add_argument("--think", action="store_true")
    ap.add_argument("--max-steps", type=int, default=0)
    ap.add_argument("--kein-internet", action="store_true", help="Werkzeug nachschlagen (Wikipedia) fuer alle Wesen abschalten")
    ap.add_argument("--anbieter", default="ollama", choices=["ollama", "ionos"], help="Modellanbieter fuer alle Wesen")
    ap.add_argument("--base-url", default=eko_ollama.IONOS_BASE_URL)
    ap.add_argument("--key-env", default="IONOS_API_TOKEN", help="Umgebungsvariable mit dem API-Schluessel (IONOS)")
    ap.add_argument("--ohne", default="", help="Komma-Liste von Wesen, die hier nicht gestartet werden (z. B. schon laufende)")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    base = "http://127.0.0.1:%d" % args.port
    skip = {x.strip() for x in args.ohne.split(",") if x.strip()}
    running = {}
    print("Eko-Schwarm: Welt %s, Modell %s" % (base, args.model), flush=True)
    try:
        while True:
            try:
                for info in beings(base):
                    if info["name"] in running or info["name"] in skip:
                        continue
                    t = threading.Thread(target=run_agent, args=(info, args), daemon=True, name=info["name"])
                    t.start()
                    running[info["name"]] = t
                    print("▶ %s (%s, Seele %s%s) startet" % (info["name"], info["rolle"], info.get("seele") or "neutral",
                                                           ", " + info["firma"] if info.get("firma") else ""), flush=True)
                    time.sleep(3)   # zeitversetzt, damit nicht alle gleichzeitig das Modell anfragen
            except Exception as e:
                print("⚠ Welt nicht erreichbar: %s" % e, flush=True)
            time.sleep(30)   # neue Wesen (Gruendungen, Wahlen) regelmaessig aufnehmen
    except KeyboardInterrupt:
        print("\nSchwarm beendet. Gedächtnisse liegen in", args.root)


if __name__ == "__main__":
    main()
