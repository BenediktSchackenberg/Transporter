"""Eko-Schwarm: alle freien Wesen einer Partie mit lokalem Ollama oder IONOS laufen lassen.

Fragt die Welt (mit dem Betreiberschluessel aus user://eko_betreiber.txt), welche Wesen es gibt (Unternehmer, Buergermeister,
Lumo, ...), und startet fuer jedes einen Agenten aus eko_ollama.py in einem eigenen Faden – mit passender Seele
(tools/eko/seelen/<seele>.md), eigenem Arbeitsordner und Protokoll. Neue Wesen (z. B. nach einer Gruendung) kommen
automatisch dazu. Lokales Ollama arbeitet Anfragen nacheinander ab; IONOS laesst mehrere gleichzeitig zu.

    python tools/eko/eko_schwarm.py                     # Spiel vorher mit -- --eko-spieler starten
    python tools/eko/eko_schwarm.py --model qwen3.5:9b-q4_K_M

Abbruch mit Strg+C; jedes Gedaechtnis bleibt im Arbeitsordner seines Wesens.
"""
import argparse
import json
import os
import socket
import sys
import threading
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eko_ollama  # noqa: E402

TOKEN_FILE = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "Pixel Transport Rivals" / "eko_betreiber.txt"
STATUS_FILE = TOKEN_FILE.with_name("eko_schwarm_status.json")   # entspricht Godot user://eko_schwarm_status.json


def beings(base):
    req = urllib.request.Request(base + "/betreiber/wesen", headers={"X-Betreiber": TOKEN_FILE.read_text().strip()})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def run_agent(info, args, publish):
    a = argparse.Namespace(**vars(args))
    a.name = info["name"]
    a.art = info.get("art", "mensch")
    a.seele = info.get("seele", "") or ""
    a.firma = info.get("firma", "")
    a.stadt = info.get("stadt", "")
    a.rolle = info.get("rolle", "")   # Gewicht in der Warteschlange am Modell (Buergermeister seltener)
    a.status_callback = publish
    agent = None
    while True:   # wie eko_ollama.main: nichts beendet ein Wesen dauerhaft
        try:
            if agent is None:
                agent = eko_ollama.Agent(a)
            agent.run()
            publish(a.name, "beendet", waiting_on="")
            return
        except Exception as e:
            publish(a.name, "fehler", last_error=str(e)[:220], waiting_on="Neustart in 10 s")
            if agent is not None:
                agent.say("⚠ Fehler: %s – Neustart in 10 s" % e)
            else:
                print("⚠ %s: Startfehler: %s – Neustart in 10 s" % (a.name, e), flush=True)
            time.sleep(10)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8790)
    ap.add_argument("--model", default=eko_ollama.DEFAULT_MODEL)
    ap.add_argument("--ollama", default="http://127.0.0.1:11435")
    ap.add_argument("--root", default=os.path.join(os.path.expanduser("~"), "PixelTransportRivals-Eko"))
    ap.add_argument("--ctx", type=int, default=32768)
    ap.add_argument("--think", action="store_true")
    ap.add_argument("--max-steps", type=int, default=0)
    ap.add_argument("--kein-internet", action="store_true", help="Werkzeug nachschlagen (Wikipedia) fuer alle Wesen abschalten")
    ap.add_argument("--anbieter", default="ollama", choices=["ollama", "ionos"], help="Modellanbieter fuer alle Wesen")
    ap.add_argument("--base-url", default=eko_ollama.IONOS_BASE_URL)
    ap.add_argument("--key-env", default="IONOS_API_TOKEN", help="Umgebungsvariable mit dem API-Schluessel (IONOS)")
    ap.add_argument("--max-output-tokens", type=int, default=eko_ollama.IONOS_MIN_OUTPUT_TOKENS,
                    help="Antwortbudget je IONOS-Aufruf (mindestens 8000 fuer Qwen)")
    ap.add_argument("--ohne", default="", help="Komma-Liste von Wesen, die hier nicht gestartet werden (z. B. schon laufende)")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    # Nur ein Schwarm je Welt: das Spiel startet ihn selbst (Startmenue "Freie Wesen"), der Welt-Waechter oder man von Hand.
    # Ein zweiter wuerde jedes Wesen doppelt steuern; die Sperre ist ein lokaler Port, den das Betriebssystem beim Ende freigibt.
    lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock.bind(("127.0.0.1", args.port + 1000))
    except OSError:
        print("Eko-Schwarm läuft schon für diese Welt – dieser Start wird beendet.", flush=True)
        time.sleep(3)
        return
    base = "http://127.0.0.1:%d" % args.port
    skip = {x.strip() for x in args.ohne.split(",") if x.strip()}
    running = {}
    statuses = {}
    status_lock = threading.Lock()
    stop_status = threading.Event()

    def publish(name, state, **fields):
        with status_lock:
            entry = statuses.setdefault(name, {"calls": 0})
            entry.update(fields)
            entry["state"] = state
            entry["updated_at"] = time.time()
            if state == "antwortet":
                entry["calls"] += 1

    def write_status():
        with status_lock:
            agents = {name: dict(entry, alive=bool(not stop_status.is_set() and running.get(name) and running[name].is_alive()))
                      for name, entry in statuses.items()}
        model = eko_ollama.IONOS_MODEL if args.anbieter == "ionos" and (args.model.startswith("hf.co/") or args.model.startswith("gpt-oss")) else args.model
        snapshot = {"updated_at": time.time(), "provider": args.anbieter, "model": model, "pid": os.getpid(),
                    "configuration_error": ("Umgebungsvariable %s fehlt" % args.key_env) if args.anbieter == "ionos" and not os.environ.get(args.key_env) else "",
                    "agents": agents}
        STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
        temporary = STATUS_FILE.with_name("eko_schwarm_status.%d.tmp" % os.getpid())
        temporary.write_text(json.dumps(snapshot, ensure_ascii=False), encoding="utf-8")
        os.replace(temporary, STATUS_FILE)

    def status_writer():
        while not stop_status.is_set():
            try:
                write_status()
            except OSError as e:
                print("⚠ Schwarmstatus konnte nicht geschrieben werden: %s" % e, flush=True)
            stop_status.wait(2)

    writer = threading.Thread(target=status_writer, daemon=True, name="Schwarmstatus")
    writer.start()
    print("Eko-Schwarm: Welt %s, Modell %s" % (base, args.model), flush=True)
    try:
        while True:
            try:
                for info in beings(base):
                    name = info["name"]
                    if name in skip:
                        continue
                    with status_lock:
                        old = running.get(name)
                    if old is not None and old.is_alive():
                        continue
                    if old is not None and args.max_steps:
                        continue   # begrenzte manuelle Sitzung nicht automatisch wiederholen
                    if old is not None:
                        publish(name, "neustart", last_error="Agentenfaden endete unerwartet")
                    t = threading.Thread(target=run_agent, args=(info, args, publish), daemon=True, name=name)
                    with status_lock:
                        running[name] = t
                    publish(name, "startet", waiting_on="Anmeldung an der Welt")
                    t.start()
                    print("▶ %s (%s, Seele %s%s) startet" % (name, info["rolle"], info.get("seele") or "neutral",
                                                           ", " + info["firma"] if info.get("firma") else ""), flush=True)
                    time.sleep(3)   # zeitversetzt, damit nicht alle gleichzeitig das Modell anfragen
            except Exception as e:
                print("⚠ Welt nicht erreichbar: %s" % e, flush=True)
            time.sleep(30)   # neue Wesen (Gruendungen, Wahlen) regelmaessig aufnehmen
    except KeyboardInterrupt:
        print("\nSchwarm beendet. Gedächtnisse liegen in", args.root)
    finally:
        stop_status.set()
        writer.join(timeout=3)
        with status_lock:
            for entry in statuses.values():
                entry["state"] = "beendet"
        try:
            write_status()
        except OSError:
            pass


if __name__ == "__main__":
    main()
