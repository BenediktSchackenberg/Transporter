"""Interaktive, rein lesende Konsole fuer den Eko-Schwarm.

Die Stimmen beschreiben den gemeldeten Agentenstatus. Sie sind keine
zusaetzlichen Modellantworten und loesen keine Spielaktion aus.
"""

import os
import sys
import threading
import time
from pathlib import Path


def clip(value, width=112):
    text = " ".join(str(value or "").split())
    return text if len(text) <= width else text[: width - 3] + "..."


def log_entries(root, limit=1500):
    """Liest nur Sitzungsprotokolle der aktuellen Agentenwurzel."""
    entries = []
    for path in Path(root).glob("*/logs/sitzung.log"):
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[-limit:]
        except OSError:
            continue
        for index, line in enumerate(lines):
            if len(line) < 9 or line[2:3] != ":":
                continue
            entries.append((line[:8], index, path.parent.parent.name, line[9:].strip()))
    return sorted(entries, key=lambda row: (row[0], row[1], row[2]))


def top_events(root, count=10):
    ranked = []
    for stamp, index, name, message in log_entries(root):
        if not message.startswith("→ "):
            continue
        if any(message.startswith("→ " + passive) for passive in
               ("observe ", "wait ", "list_files ", "read_file ", "write_file ", "learn ")):
            continue
        lower = message.lower()
        score = 1
        for word, points in (("founding_choice", 9), ("haus_bauen", 7), ("buergeramt_bauen", 7),
                             ("mayor_action", 7), ("angriff", 8), ("verteidigung", 7),
                             ("hub_buy", 4), ("helicopter", 4), ("kaufen", 3),
                             ("gebaut", 4), ("fertig", 4), ("gegründet", 8),
                             ("zerstört", 9), ("bewohner", 5), ("firma", 2)):
            if word in lower:
                score += points
        if any(word in lower for word in ("ungültig", "ungueltig", "nicht verfügbar", "fehler", "ist nicht")):
            score -= 5
        ranked.append((score, stamp, index, name, message))
    ranked.sort(key=lambda row: (row[0], row[1], row[2]), reverse=True)
    return [(stamp, name, message) for _, stamp, _, name, message in ranked[:count]]


class ConsoleUI:
    """Statusbilder und Tastenkürzel ohne Eingriff in die KI-Steuerung."""

    def __init__(self, root, status_snapshot):
        self.root = root
        self.status_snapshot = status_snapshot
        self.output_lock = threading.Lock()
        self.last_chatter = 0.0
        self.turn = 0
        self.keyboard = None
        self.view = "start"
        self.interactive = False

    def _write(self, value):
        with self.output_lock:
            print(value, flush=True)

    def show_home(self):
        self.view = "start"
        self._write(
            "\x1b[2J\x1b[H\n+==================================================================+\n"
            "|  .---.   E K O  -  S C H W A R M   .---.                      |\n"
            "|  |o_o|   KI-Wesen erkunden, planen und bauen   |o_o|          |\n"
            "|  |___|   [1] Ereignisse  [2] Log  [3] Status  [H] Hilfe     |\n"
            "+==================================================================+\n"
            "  ASCII-Stimmen = Live-Status; echte KI-Aussagen stehen im Log.\n"
            "  [B] Zurueck zur Startanzeige  |  [Esc] und [Backspace] ebenso\n"
        )

    def start(self):
        self.show_home()
        self.interactive = os.name == "nt" and sys.stdin.isatty()
        if self.interactive:
            self.keyboard = threading.Thread(target=self._keys, daemon=True, name="Schwarmtasten")
            self.keyboard.start()
        else:
            self._write("  Tastenkürzel sind nur in einem interaktiven Konsolenfenster verfügbar.")

    def event(self, name, message):
        self._write("%s [%-16s] %s" % (time.strftime("%H:%M:%S"), clip(name, 16), clip(message, 180)))

    def chatter(self):
        now = time.monotonic()
        if now - self.last_chatter < 15:
            return
        self.last_chatter = now
        statuses = self.status_snapshot()
        if not statuses:
            return
        names = sorted(statuses)
        name = names[self.turn % len(names)]
        self.turn += 1
        state = statuses[name]
        situation = state.get("next_step") or state.get("waiting_on") or state.get("goal") or "Ich erkunde die Lage."
        if state.get("state") == "fehler":
            situation = "Ich prüfe einen Fehler: " + (state.get("last_error") or situation)
        elif state.get("state") == "denkt":
            situation = "Ich überlege: " + situation
        elif state.get("state") == "handelt":
            situation = "Ich handle: " + (state.get("tool") or situation)
        else:
            situation = "Ich bin dran: " + situation
        self._write("\n  .---.  %s  |  %s Modellantworten\n  |o_o|  %s\n  '---'\n" %
                    (clip(name, 24), state.get("calls", 0), clip(situation, 125)))

    def _panel(self, title, rows):
        self.view = title
        body = "\n".join("  " + clip(row, 172) for row in rows) if rows else "  Noch keine Einträge."
        self._write("\x1b[2J\x1b[H\n+--- %s %s\n%s\n+%s\n  +------------------------+\n  | [B/Enter] ZURUECK      |  [1] Ereignisse [2] Log [3] Status\n  +------------------------+\n" %
                    (title, "-" * max(0, 58 - len(title)), body, "-" * 64))

    def show_top(self):
        rows = ["%2d  %s  %-16s  %s" % (index, stamp, clip(name, 16), message)
                for index, (stamp, name, message) in enumerate(top_events(self.root), 1)]
        self._panel("TOP 10 KI-EREIGNISSE", rows)

    def show_log(self):
        rows = ["%s  %-16s  %s" % (stamp, clip(name, 16), message)
                for stamp, _, name, message in log_entries(self.root)[-18:]]
        self._panel("LETZTE 18 LOGZEILEN", rows)

    def show_status(self):
        rows = []
        for name, state in sorted(self.status_snapshot().items()):
            rows.append("%-18s %-11s %3s Antworten  %s" %
                        (clip(name, 18), state.get("state", "?"), state.get("calls", 0),
                         clip(state.get("last_error") or state.get("next_step") or state.get("waiting_on"), 100)))
        self._panel("AGENTENSTATUS", rows)

    def _keys(self):
        import msvcrt
        while True:
            try:
                key = msvcrt.getwch().lower()
                if key == "1":
                    self.show_top()
                elif key == "2":
                    self.show_log()
                elif key == "3":
                    self.show_status()
                elif key in ("h", "?"):
                    self._panel("TASTEN", ["1  Zehn wichtigste KI-Ereignisse der laufenden Partie",
                                           "2  Letzte 18 Logzeilen aller KI-Wesen",
                                           "3  Status, Modellantworten und nächste Schritte",
                                           "B, Enter, Esc, Backspace  Zurück zur Startanzeige",
                                           "H  Diese Hilfe; Strg+C beendet den Schwarm"])
                elif key in ("b", "\x1b", "\b", "\r"):
                    self.show_home()
            except (OSError, EOFError):
                return
