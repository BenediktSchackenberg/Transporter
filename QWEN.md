# Übergabe: Weiterentwicklung von Pixel Transport Rivals

Diese Datei ist der Einstieg für jede KI- oder Entwickler-Sitzung, die hier weitermacht (Qwen Code liest `QWEN.md` automatisch).
Sie beschreibt Arbeitsweise, Befehle, Konventionen, den aktuellen Stand und die nächsten Schritte. Stand: 11.11.2026, Commit `08e6bbb`.

## Projekt in Kürze

Godot-4.4.1-Spiel (GDScript, Windows) – Wirtschafts- und Transportsimulation in isometrischer Voxel-Pixelgrafik. Mehrere Städte
(„Region“) auf einer Karte, je Stadt ein Bürgermeister (KI) und Unternehmer-Firmen (KI über Ollama/IONOS/Anthropic oder Regel-KI).
Städte haben kommunale Dienste (Feuerwehr, Rettung, Bauhof, Bus, Schulen, Müll …), echte Warenketten, Bauprojekte mit Baufirmen,
Autobahn, Häfen, Flughäfen. Ausführliches Handbuch: `README.md`; Fachdokumente in `docs/`.

## Arbeitsweise (verbindlich)

- **Einfach und chirurgisch:** nur ändern, was die Aufgabe verlangt; keine spekulativen Abstraktionen; bestehenden Stil übernehmen.
  Annahmen offen nennen, Erfolgskriterien vorher festlegen (Test oder Messprobe), dann prüfen.
- **Jede Änderung mit Test:** neuer Test in `tests/run_tests.gd` (Funktion `test_<name>` + Eintrag in der Liste `test_names` oben).
  Verhalten über längere Zeit mit Messproben (`tests/probe_*.gd`) prüfen, nicht nur raten.
- **Commits auf Deutsch**, aussagekräftig (was + warum, gern mit Messwerten), **ohne** Co-Authored-By-Zeile und ohne Nennung eines
  KI-Assistenten. Nach jedem getesteten Schritt committen und pushen.
- **Branches:** Es wird **nur noch auf `main`** gearbeitet und gepusht: `git push origin main`
  (vorher `git pull --rebase` bzw. `git fetch` und prüfen). Die alten Branches `region`/`unternehmer`
  und die parallelen Worktrees sind am 11.11. in `main` eingemerged und danach entfernt worden.
- **Nicht einchecken:** `build/`, `.godot/`, API-Schlüssel, `tools/vox/__pycache__/`, lokale `setup.json`.
- Antworten an den Projektinhaber auf Deutsch, knapp, mit konkreten Zahlen aus Messungen.

## Befehle

Godot (Konsolenversion): `C:\Users\Benedikt\Tools\godot441\Godot_v4.4.1-stable_win64_console.exe` (unten `G`).

```bash
G --headless --path . -s tests/run_tests.gd                      # alle Tests (~25-30 min, viel RAM)
G --headless --path . -s tests/run_tests.gd -- --only=test_xyz   # ein Test (nur EIN Name je Aufruf)
PTR_VERBOSE=1 G ... --only=test_xyz                              # zeigt auch bestandene Prüfungen
G --headless --path . --import                                   # nach neuen class_name-Dateien oder neuen Bildern
G --path .                                                       # Spiel starten (ohne _console: Fensterversion)
```

**Wichtig:** Läuft parallel eine Partie, Testläufe immer mit eigener Logdatei starten
(`G --headless --log-file <tmp>/t.log --path . ...`), sonst überschreiben sie `godot.log` der laufenden Partie.
Volltest nicht parallel zu einer Partie mit lokalem Ollama-Modell (RAM).

Logs einer Partie: `%APPDATA%\Godot\app_userdata\Pixel Transport Rivals\logs\` – `match_*.jsonl` (alle KI-Anfragen mit
Beobachtung, Antworten, Aktionen mit Ergebnis, Leistungsdaten), `godot.log` (Skriptfehler), `zuletzt.txt`/`haenger.txt` (Hänger).
Auswertung: Anfragen/Antworten je Spieler, Erfolgsquote je Quelle (KI, Disposition, Ersatzmodus), häufigste Ablehnungsgründe,
Finanzen aus `ich` (bargeld, gewinn, umsatz, kosten, reputation) in der Beobachtung der Anfragen, Ereignisse „gescheitert“.

Grafik (Voxel-Baukasten in `tools/vox/`, Ausgabe `assets/iso/` + `manifest.json`): einzelne neue Bilder bauen, ohne alles neu zu rendern:

```bash
cd tools && python -c "
import sys, json; sys.argv=['x','none']
import build_iso as B, public as PB
B.build_buildings(only=[n for n in PB.specs() if n.startswith('pub_aw_')])   # Beispiel: Betriebshof
B.build_vehicles()
json.dump(B.manifest, open(B.MANIFEST_PATH,'w',encoding='utf8'), indent=1)"
```

Neue öffentliche Gebäudetypen brauchen 6 Grundvarianten × 4 Stile (`tools/vox/public.py`), Eintrag in `CityGenerator.TYPES`
und im Test `test_public_buildings`; neue kommunale Fahrzeuge ein Modell in `tools/vox/vehicles.py` (Liste `MUNICIPAL`).

## Architektur (Einstieg)

- `scripts/core/simulation.gd` – Simulationskern; alle Systeme hängen als Felder daran (`sim.waste`, `sim.municipal`, `sim.towns` …),
  Tageswechsel über Signal `day_changed`, Monat `month_changed`; Speichern/Laden über `to_dict`/`from_dict` je System.
- `scripts/core/towns.gd` – Städte der Region: Konto `P<k>` (Ort 0 = `P0`), Eigentümer `stadt<k>`, `of_building/of_cell`.
- `scripts/economy/municipal.gd` – kommunale Einrichtungen (Typen `TYPES`, Berufe `BERUFE`, Fahrzeuge `VEHICLES`, Startausstattung
  `START_KIT`), Personal, Kosten. Nur in der Weltart Region aktiv.
- `scripts/economy/waste.gd` + `scripts/core/city_fleet.gd` – Müll: Tonnen je Gebäude, Touren, Waage an der gemeinsamen Deponie.
- `scripts/ai/` – KI: `agent_controller.gd` (Firmen-KI, Ablauf Anfrage→Antwort→Aktionen), `observation_builder.gd` (was das Modell
  sieht; `compact_for_local` für lokale Modelle), `action_executor.gd` (prüft und führt Aktionen aus), `action_assist.gd`
  (ergänzt/korrigiert typische Modellfehler), `worker_actions.gd`, `mayor_agent.gd` + `scripts/core/mayor.gd` (Bürgermeister),
  `rule_brain.gd`/`mayor_brain.gd` (Regel-KI und Ersatzmodus).
- `scripts/core/regional_projects.gd` – Gemeinschaftsprojekte und Autobahn (Trasse auf Grobraster, `plan_highway`).
- `scripts/world/` – Kartengeneratoren und Darstellung (`entity_view.gd`, `*_view.gd`); `scripts/ui/` – HUD und Texte (`live_text.gd`).

## Fachdokumente (Aufträge mit Stand)

| Datei | Inhalt |
|---|---|
| `docs/INFRASTRUCTURE.md` | **Auftrag 22 (aktuell):** Müll, Strom, Wasser, Polizei, Eisenbahn in 8 Phasen – Stand je Phase |
| `docs/PUBLIC_SERVICES.md` | Auftrag 20: kommunale Dienste; Teil 2 Etappen 15–24 offen |
| `docs/HIGHWAY.md` | Auftrag 21: Autobahn, Fleischkette; Eisenbahn geht in Auftrag 22 Phase 6/7 auf |
| `docs/REGION.md` | Auftrag 17: Region mit mehreren Städten, offene Punkte |
| `docs/MAYOR_PROJECTS.md` | Auftrag 19: Großlager, autonome Bauideen der Bürgermeister |
| `docs/CITY_LOOK.md`, `ART_DIRECTION.md` | Stadtbild und Grafikstil |

## Stand 11.11.2026

Erledigt zuletzt:
- **Auftrag 22 Phase 1 Müll:** Tonnen mit Füllstand je Gebäude, Abfuhr je Stadt mit echter Entleerung beim Halt,
  Waage an der gemeinsamen Deponie, Abrechnung je Stadtkasse, Erweiterung der Deponie. Test `test_waste_bins`, Probe `probe_waste.gd`.
- **Phase 2 Schritt 1 Betriebshof:** Municipal-Typ `AW-01` je Stadt mit Müllwerkern und Müllwagen (Besatzung 3), Touren starten dort,
  Stadt kauft Wagen nach Bedarf. Test `test_waste_depot`. Stellenanzeigen der Dienste werben jetzt für jeden Beruf von außerhalb an
  (Startorte mit 30–55 Bürgern sind voll beschäftigt).
- **Autobahn:** gerade Trasse (Grobraster mit Kurvenstrafe) statt Zickzack; alte unfertige Trassen werden neu geplant.
- **KI-Robustheit (lokales Qwen 9B über Ollama):** keine Token-/Anfragegrenze bei Ollama; lokale Modelle sehen nur annehmbare
  Aufträge; Ersatzfahrer bei falscher Arbeiter-ID; „Tank leer“ statt Panne (kein sinnloses Abschleppen); `accept_contract` auf einen
  eigenen, noch nicht disponierten Auftrag weist ein Fahrzeug zu (war Hauptgrund gescheiterter Lieferungen und der Insolvenzen);
  Bürgermeister-Quartiere verstehen Tippfehler bei der Zone. Test `test_local_model_guards`, `test_empty_tank_no_tow`.
- Wirkung (Partievergleich bis Spieltag 29): gescheiterte Lieferungen 24 → 5, Reputation der Firmen 0–30 → 20–55, Verluste kleiner.
  Profitabel ist noch keine Modell-Firma – nach ein, zwei Spielmonaten erneut auswerten.

Testlage: Volltest zuletzt 6877 Prüfungen; die vier damals roten Tests (veraltete Erwartungen) sind korrigiert. Nach den letzten
Änderungen wurden die betroffenen Tests einzeln geprüft, der Volltest steht aus.

## Nächste Schritte (in dieser Reihenfolge)

1. **Auftrag 22 Phase 2 Schritt 2 – Müllarten (fertig, 11.11.):** drei Tonnen Rest/Bio/Wertstoffe je Gebäude,
   eigene Touren; Wertstoffe fahren per Wertstoffwagen zum Recyclinghof (jetzt in der Startausstattung);
   Waagebuch und Hofbestände im realen Modus. Test `test_waste_streams`, Messproben `probe_waste.gd`/`probe_rc_route.gd`.
2. Schritt 3 – Sauberkeit je Viertel: überquellende Tonnen erzeugen Abfall auf der Straße, Stadtreinigung (Kehrmaschine) räumt;
   Wirkung auf Zufriedenheit.
3. Schritt 4 – Müllverbrennung (gemeinsam): verbrennt Restmüll, liefert Strom ins Netz, Asche auf die Deponie.
4. Schritt 5 – Deponie-Erweiterung und Verbrennungsanlage über Ausschreibung und Baufirmen bauen (heute Kosten an S0).
5. Danach Phase 3 (gemeinsames Kernkraftwerk, Stromnetz als Graph), Phase 4 (Wasser/Kanal/Kläranlage), Phase 5 (Polizei),
   Phase 6/7 (Eisenbahn), Phase 8 (Verflechtung, Dashboard) – Details in `docs/INFRASTRUCTURE.md`.

Bekannte offene Punkte außerhalb der Reihenfolge:
- Stadtkassen schrumpfen schnell (Regel-KI-Lauf: Morgenholm 200 000 → 61 000 € in 60 Tagen, vor allem Bauaufträge) – vor Phase 3 prüfen.
- Firmen-KI (lokal) hat nur 12–35 % erfolgreiche Aktionen (doppelte Besuchsanfragen, erschöpfte/beschäftigte Arbeiter, Antwortzeit
  ~50 Spielminuten).
- Müllwagen werden nicht gespeichert (nach dem Laden werden volle Tonnen neu angefahren).
- FPS bei weit herausgezoomter Karte, wachsender Speicher in langen Partien.
