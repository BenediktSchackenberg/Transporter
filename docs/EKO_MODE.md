# Eko-Modus: freie Wesen ohne Ziel

Stand 15.11.2026. Idee nach „Is this machine playing?“ (MIT, machineplaying.org) und der Engine Clawblox (MIT, github.com/nacloos/clawblox).
Übernommen wurden die Ideen, nicht der Code (Clawblox ist eine eigene Rust/Luau-Engine):

1. **Wenige Grundhandlungen** statt eines Aktionskatalogs: gehen, Material aufnehmen, Block setzen, Block wieder aufnehmen, sprechen.
2. **Gedächtnis als Dateien**, die der Agent selbst pflegt: `SOUL.md` (Persönlichkeit), `EPISODIC_MEMORY.jsonl` (Erlebnisse, nur anhängen), `SEMANTIC_MEMORY.md` (geprüftes Wissen).
3. **Dauerlauf**: Der Agent bekommt kein Ziel. Endet seine Antwort, kommt „Bitte nicht aufhören. Mach einfach weiter mit dem, was du tun möchtest.“
4. **Protokoll** `join` / `observe` / `input` über HTTP mit einer kurzen `API.md` (`docs/EKO_API.md`).

## Starten

```powershell
# 1. Spiel mit Weltschnittstelle starten (lauscht nur auf 127.0.0.1:8790)
Godot_v4.4.1-stable_win64.exe --path . -- --eko            # oder --eko-port=8791

# 2. In einer zweiten Konsole ein Wesen starten (Claude Code muss installiert und angemeldet sein)
powershell -ExecutionPolicy Bypass -File tools\eko\start_eko.ps1 -Name Eko
#    weitere Wesen: anderer -Name; Modell wählen mit -Model; Abbruch mit Strg+C
```

**Mit lokalem Modell (Ollama) statt Claude Code:**

```powershell
Godot_v4.4.1-stable_win64.exe --path . -- --eko-folgen          # Kamera folgt dem Wesen, KI-Zentrale eingeklappt
python tools\eko\eko_ollama.py --name Eko                         # Standard: Qwen3.8-27B (IQ3_M) über Ollama auf 127.0.0.1:11435
python tools\eko\eko_ollama.py --name Mia --model qwen3.5:9b-q4_K_M
```

`eko_ollama.py` (nur Python-Standardbibliothek) ist eine eigene Agentenschleife mit Werkzeugaufrufen: `observe`, `act`, `wait`,
`list_files`, `read_file`, `write_file`, `append_memory`. Gleiche Gedächtnisdateien und gleicher System-Prompt wie bei Claude Code;
ohne Werkzeugaufruf kommt automatisch „mach weiter“, alle 40 Schritte eine Erinnerung an das Gedächtnis, ältere Schritte werden
ausgeblendet (das Gedächtnis liegt in den Dateien). Erster Lauf (15.11.2026, Qwen 27B, RTX 5080): 2–3 s je Schritt; Eko baute
einen Steinplatz am Bauhof, erkundete Morgenholm und kommentierte den Hafen im (echten Mainzer) Regen.

Arbeitsordner und Protokolle liegen unter `%USERPROFILE%\PixelTransportRivals-Eko\<Name>\` (`workspace\` = Gedächtnis, `logs\sitzung.log`).
Ein erneuter Start mit demselben Namen setzt die letzte Unterhaltung fort (`claude -c`), das Gedächtnis bleibt erhalten.

Der Agent darf nur `curl` ausführen und Dateien in seinem Arbeitsordner lesen und schreiben (`--allowedTools`).

## Aufbau

| Datei | Aufgabe |
|---|---|
| `scripts/core/eko_world.gd` | Weltmodell: Wesen (Fußweg über `NavGrid.walk_path`), Blockraster 4 × 4 je Feld, Regeln für Halt, Reichweite, Tragen; Beobachtung mit Kartenausschnitt 21 × 21; Speichern/Laden im Spielstand (`eko`) |
| `scripts/api/world_server.gd` | HTTP-Server (TCPServer, nur 127.0.0.1), Sitzungstoken, `handle()` ohne Netzwerk testbar |
| `scripts/world/eko_view.gd` | Blöcke als Iso-Würfel (Farben wie Freibau), Wesen mit getragenem Material und Sprechblase |
| `tools/eko/start_eko.ps1`, `systemprompt.md`, `vorlage/` | Agent-Start, System-Prompt, Gedächtnisvorlagen |
| `tests/run_tests.gd: test_eko_world` | Regeln, Protokoll, Speichern/Laden |

## Regeln (Phase 1)

- Material gibt es kostenlos an jedem Bauhof (höchstens 2 Felder entfernt), getragen werden höchstens 4 Blöcke.
- Blöcke nur auf freiem Boden (keine Straße, kein Gebäude), mit Halt durch Boden, Block darunter oder daneben; über Wasser nur oberhalb des Bodens (Brücken).
- Aufnehmen nur, wenn nichts darauf liegt und kein Nachbar danach schwebt.
- Wesen laufen in Echtzeit (3 Felder/s), unabhängig von der Spielgeschwindigkeit; bei Pause stehen sie.

## Erster Probelauf (15.11.2026, Claude Code, eine Runde, ca. 4 Minuten)

Eko testete die Bauregeln und notierte sie, baute einen Torbogen (Säulen aus Stein und Ziegel, freitragender Holzsturz), wanderte nach
Westen, entdeckte das Meer, versuchte eine Brücke und begann stattdessen einen Leuchtturm an der Küste. Dabei fand Eko drei Schwächen,
die behoben sind: Abbauen ließ Blöcke schweben, Gehen war bei langsamen Bildern zu langsam, Brücken über Wasser waren unmöglich.

## Grenzen und nächste Schritte

- Blöcke versperren keine Wege (Wesen und Fahrzeuge gehen hindurch).
- Keine Verbindung zur Wirtschaft: Material kostet nichts, Wesen haben kein Geld und keine Bedürfnisse.
- Kein Bild aus der Sicht des Wesens (`/observe/image` wie bei Clawblox fehlt).
- Kosten: Ein Dauerlauf verbraucht laufend Kontingent des Claude-Kontos.
