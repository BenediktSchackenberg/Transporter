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
python tools\eko\eko_ollama.py                                    # Lumo, der kleine Roboter vom Smaragdstern (Qwen3.8-27B über Ollama, 127.0.0.1:11435)
python tools\eko\eko_ollama.py --name Mia --art mensch --seele "" --model qwen3.5:9b-q4_K_M   # zweites Wesen, kleines Modell
```

`eko_ollama.py` (nur Python-Standardbibliothek) ist eine eigene Agentenschleife mit Werkzeugaufrufen: `observe`, `act`, `wait`,
`list_files`, `read_file`, `write_file`, `append_memory`. Gleiche Gedächtnisdateien und gleicher System-Prompt wie bei Claude Code;
ohne Werkzeugaufruf kommt automatisch „mach weiter“, alle 40 Schritte eine Erinnerung an das Gedächtnis, ältere Schritte werden
ausgeblendet (das Gedächtnis liegt in den Dateien). Erster Lauf (15.11.2026, Qwen 27B, RTX 5080): 2–3 s je Schritt; Eko baute
einen Steinplatz am Bauhof, erkundete Morgenholm und kommentierte den Hafen im (echten Mainzer) Regen.

Arbeitsordner und Protokolle liegen unter `%USERPROFILE%\PixelTransportRivals-Eko\<Name>\` (`workspace\` = Gedächtnis, `logs\sitzung.log`).
Ein erneuter Start mit demselben Namen setzt die letzte Unterhaltung fort (`claude -c`), das Gedächtnis bleibt erhalten.

Der Agent darf nur `curl` ausführen und Dateien in seinem Arbeitsordner lesen und schreiben (`--allowedTools`).

## Lumo und andere Wesen

- **Gestalt** beim Beitreten: `art=mensch` (Pixelfigur) oder `art=roboter` (kleiner Roboter auf Ketten mit großem leuchtendem Auge und
  blinkender Antenne, eigener Entwurf). Standard der Startskripte ist **Lumo**, ein Roboter vom Smaragdstern.
- **Seelen** liegen in `tools/eko/seelen/<name>.md` und werden beim ersten Start als `SOUL.md` übernommen (`--seele` / `-Seele`); danach gehört
  die Datei dem Wesen. Eigene Figuren: einfach eine weitere Datei anlegen.

## Lumos Leben: Arbeit, Grundstück, Haus

- **Arbeit für die KI-Firmen:** Aktive Firmen mit mehr als 3.000 € Kasse bieten Wesen Aufträge an (`jobangebote`, höchstens 5 offen,
  10 Minuten gültig): *Botengang* (1–3 Kisten vom Betriebshof zu einem Gebäude im Ort, `Pickup {job}`, `Deliver {job}`) oder *Mauer*
  (4–8 Blöcke eines Materials im markierten Bereich neben dem Hof). Firmenfiguren in Sichtweite rufen das Wesen an. Beim Abliefern
  zahlt die Firma den Lohn aus ihrer Kasse (Kategorie Löhne, Gegenkonto **Y0 „Freie Wesen“**); die Firma bekommt Annahme und
  Erledigung als Meldung.
- **Grundstück:** `lebensziel.grundstuecke_zu_kaufen` zeigt freie Wohngrundstücke (mind. 2 × 2 Felder) im Ort. `BuyPlot` zahlt den
  Grundstückspreis an die Stadtkasse; Eigentümer wird Y0, das Grundstück gilt als privat gehalten.
- **Haus:** `OrderHouse` (2.400 € an K0 „Baufirmen“) – die Baufirma eines Bautrupps baut ein 8 × 8-Block-Haus Block für Block:
  Holzboden mit Teppich, Wände mit Fenstern und Tür nach Süden, Bett mit Decke, Tisch mit Lampe, Regal mit Buch, Pflanze, Ladestation,
  Flachdach. Gezeichnet wird es als **Schnitt** (ohne Dach, Vorder- und Ostwand nur eine Schicht hoch), damit man das Wesen drinnen sieht.
  Ist es fertig, wird das Grundstück bebaut; `Rest` lässt das Wesen in der Ladestation ausruhen.
- **Vorführung:** `-- --eko-demo-haus` gibt Lumo sofort ein fertiges Haus am nächsten Wohngrundstück (Geld aus X0, Bilanz bleibt gleich).

## Lumo-Unternehmer

- `FoundCompany {name?, behalten?}` ab 1.500 € Ersparnissen: Der Kapitalgeberpool I0 legt 20.000 € dazu, die Ersparnisse gehen als
  Einlage in die Firma (`behalten` bleibt privat). Sitz vorerst im Rathaus, zwei Allrounder wie beim Startunternehmer (`Founders.create_for_being`).
- Das Wesen führt die Firma selbst mit `Firma {aktion}` (accept_contract, assign_transport, collect_contracts, buy_vehicle, sell_vehicle,
  recruit_worker, dismiss_worker, assign_worker_task, rent_depot, take_loan, repay_loan, install_internet, send_message) und sieht eine
  kompakte Lage in `meine_firma`. Den Tagesbetrieb (Aufträge zuweisen, Fahrer setzen, tanken, reparieren, Hof aufbauen) erledigt die
  Disposition der Regel-KI über einen Controller mit Anbieter `eko`, der selbst keine Modellanfragen stellt.
- Die Firmenfigur ist ausgeblendet; sichtbar ist das Wesen selbst. Die Firma erscheint wie jede Gründung in HUD und KI-Zentrale.

## Alle KI-Spieler und Bürgermeister als Wesen (`--eko-spieler`)

```powershell
Godot_v4.4.1-stable_win64.exe --path . -- --eko-spieler --eko-folgen      # neue Partie oder mit --autotest --load ein Spielstand
python tools\eko\eko_schwarm.py                                          # alle Wesen gleichzeitig über Ollama
```

- Jede Startfirma bekommt ein Wesen mit dem Namen des Spielers und einer Seele nach seiner Persönlichkeit
  (`tools/eko/seelen/kostenoptimierer|wachstum|netzwerker|risikospieler.md`). Es entscheidet über `Firma {aktion}`; der Firmen-Controller
  macht nur noch den Tagesbetrieb (Anbieter `eko`). Start wie bisher mit kleiner Firma (Hof, zwei Allrounder, Startkapital).
- Jeder Bürgermeister bekommt ein Wesen (Seele `buergermeister.md`) mit `Amt {aktion}` (alle Amtshandlungen aus `Mayor.SCHEMA`)
  und einer kompakten Amtslage `mein_amt`. Der Bürgermeister-Agent erledigt nur noch Routinefälle nach Regeln (`eko_managed`, alle 120 s).
- `eko_schwarm.py` fragt `GET /betreiber/wesen` (Betreiberschlüssel aus `user://eko_betreiber.txt`) und startet je Wesen einen Agenten
  in einem eigenen Faden; neue Wesen (Gründungen) kommen automatisch dazu. Konsolenzeilen tragen den Namen des Wesens.
- Spielstand sichern ohne Tastendruck: `POST /betreiber/speichern` mit Kopf `X-Betreiber`.
- Grenzen: Alle Wesen teilen sich ein Modell auf einer Grafikkarte; mit 7 Wesen kommt jedes etwa alle 20 Sekunden an die Reihe.
  Nach einer Bürgermeisterwahl behält das Wesen sein Amt (Name des Wesens bleibt).

## Gespräche mit anderen KIs

- `Talk {to, text}` (höchstens 3 Felder Abstand) spricht eine Figur an:
  - **Unternehmer** (KI-Firmen): antworten sofort aus ihrem echten Zustand – was ihre Figur gerade tut, das Ziel und die Begründung ihrer
    letzten KI-Entscheidung. Die Firma bekommt die Worte des Wesens als Meldung in ihre Beobachtung (`sim.notify`); Firmen mit Sprachmodell
    können darauf eingehen.
  - **andere Wesen**: hören es als Ereignis und in `gehoert`, ihr eigenes Modell antwortet mit `Talk`/`Say`.
- `/observe` zeigt `figuren_in_der_naehe` (alle Unternehmer mit Feld und Entfernung, nächste zuerst) und `gehoert` (was im Umkreis von
  12 Feldern gesagt wurde).

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
- Kosten: Ein Dauerlauf mit Claude Code verbraucht laufend Kontingent des Claude-Kontos (mit Ollama nicht).
- Bürgermeister und Bürger lassen sich noch nicht ansprechen; Unternehmer antworten mit festem Satzbau aus ihrem Zustand, nicht frei.
- Aufträge an Wesen erzeugt die Engine im Namen der Firmen; Firmen mit Sprachmodell können noch keine eigenen Aufträge an Wesen formulieren.
- Ein Wesen mit Firma geht nicht selbst zum Händler: Besuche (Fahrzeugkauf, Depot) erledigt die ausgeblendete Firmenfigur.
- Haus und Einrichtung sind fest vorgegeben (eine Bauform, Wandmaterial wählbar).
