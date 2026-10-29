# 🚚 Pixel Transport Rivals

> **Eine Stadt, die von allein lebt. Vier Unternehmer, die nie schlafen. Und du auf dem besten Platz: dem Zuschauerrang.**

Pixel Transport Rivals ist eine **autonome Wirtschaftssimulation in isometrischer Voxel-Pixeloptik**. Du steuerst nichts. Stattdessen übernehmen **2 bis 4 KI-Unternehmer** (pro Spieler ein lokales Ollama-Modell, eine externe Modell-API oder ein regelbasierter Demo-Spieler) je eine kleine Spedition in einer lebendigen Stadt. Sie kaufen Fahrzeuge, heuern Fahrer an, handeln, verhandeln, funken sich an, bauen ihren Betriebshof aus, nehmen Kredite auf, gehen pleite und werden ersetzt. Du schaust zu, warum sie das tun.

**Godot 4.4.1 · typisiertes GDScript · Windows · Deutsch**

---

## ✨ Was hier passiert

### 🏙️ Eine Stadt mit eigenem Leben
- **Echtes Wetter aus Mainz** (Open-Meteo, alle 15 Minuten): Regen, Schnee, Nebel, Sturm und Hitze verändern Straßen, Ladezeiten, Pannenrisiko und Bautempo. Ohne Netz springt ein gekennzeichnetes Ersatzwetter ein.
- **Automatische Ereignisse mit Ursache**: Starkregen, Neueröffnungen, Nachfrageschübe, Frachtterminal-Großaufträge. Jedes Ereignis hat einen Auslöser, eine Abklingzeit und eine ruhige Phase danach.
- **Kundenfiguren mit echten Anliegen**: Bewohner melden Bedarf, veröffentlichen Aufträge, haben Budgets und Geduld. Wer schlecht liefert, wird nicht wieder gerufen.
- **Ein Tag-Nacht-Zyklus pro Spieltag** (1 Spieltag = 1 Echtzeitminute bei 1×).

### 🎨 Voxel-Miniaturwelt
Die gesamte Stadt (Gebäude, Fahrzeuge, Figuren, Straßen) wird aus **Voxeln gerendert und zu isometrischen Pixelbildern** gebacken (Dimetrie 2:1). Schule, Kita, Frachtterminal, Villen, Hochhäuser, Betriebshöfe mit Werkstatt, Rampen und Lager. Baustellen, Regenpfützen, Schnee auf den Dächern, Lichter bei Nacht.

### 🧠 Transparente KI statt Blackbox
- Jede Firma hat ein **anklickbares Unternehmerporträt** mit Detailfenster: Was tut der Unternehmer gerade? Wo steht er? Was ist sein dokumentiertes Ziel und der nächste Schritt?
- Das **Entscheidungsprotokoll** verknüpft Ursache → Entscheidung → Aktion → Folge.
- **Demo, Ersatzmodus und echte API** sind überall klar gekennzeichnet. API-Schlüssel landen nie in Spielständen oder Logs.

### 💶 Ein geschlossener Wirtschaftskreislauf
Kein Geld entsteht aus dem Nichts. Jede Zahlung bewegt Geld zwischen echten Konten, und ein Test prüft nach jeder Aktion, dass die **Gesamtsumme erhalten bleibt**.
- **Drei Banken** mit eigener Bilanz, Referenzzins, Annuitätenkrediten mit Tilgungsplan, Verzug, Ausfall und Pfandverwertung, dazu Tages- und Festgeld.
- **Rechtsformen**: Einzelunternehmen, UG, GmbH mit unterschiedlicher Haftung, Kosten und Kreditrahmen.
- **Insolvenz mit Folgen**: Zahlungsverzug → Nachfrist → Insolvenzverwalter → **sichtbare Auktionen** für Fahrzeuge und Betriebshof → Gläubigerverteilung mit Ausfallquote → Neugründung durch einen neuen Unternehmer mit neuer Identität.
- **Bauhof (Großhandel)**: importiert, produziert (Paletten, Beton, Module, Recycling), verkauft Material und exportiert Überschüsse. Jede Ware hat **Eigentümer und Standort**; Baustellen verbrauchen echtes Material, das vorher geliefert werden muss.
- **Spielkalender** (Tag, Monat, Jahr) mit Partiedauern von 5 Minuten bis 24 Stunden oder Endlos.

### 🔬 Gebaut mit Beweisen
Über **4300 automatische Prüfungen** (Geldkonservierung, Warenbilanz, Bilanzidentität, Speichern und Laden, Insolvenzablauf, Wetter, Ereignisse, Grafik-Vollständigkeit). Der Stand jedes Bereichs steht ehrlich in [`STATUS.md`](STATUS.md), samt dem, was **noch nicht** fertig ist.

---

## 🗺️ Fahrplan

| Stufe | Inhalt | Stand |
|---|---|---|
| 1 | Stadtleben: Wetter, Ereignisse, Kunden, isometrische Voxelgrafik, transparente KI | ✅ fertig |
| 2 | Wirtschaftskreislauf: Konten, Banken, Rechtsformen, Insolvenz, Bauhof, Material, Ranglisten | ✅ weitgehend fertig (Spielerkredite fehlen) |
| 3 | Kraftstoffpreise (real), Tankstellen, Haushalte, Löhne, Gebäudezustand | ✅ fertig (Stadtviertel offen) |
| 4 | Öffentliche Hand: Steuern, Behörden, Geldschöpfung der Banken | 🔧 Steuern, Ressorts, Prüfung, Bürger fertig; Geldschöpfung offen |
| 5 | Versorgungsnetz: Stadtlager, Verkehr mit Kapazität, Restaurants, Läden, Müll und Mehrweg | ⏳ geplant |
| 6 | Bewohner, Haushalte, Wohnungen, Mieten, private Kredite | ⏳ geplant |
| 7 | Größere Karte, Baugrundstücke, Bauunternehmen, Bürgermeister-KI, Bauanträge | ✅ fertig (siehe `docs/URBAN_DEVELOPMENT.md`) |

Die Pläne stehen in [`docs/ECONOMY.md`](docs/ECONOMY.md) und [`STATUS.md`](STATUS.md).

---

## 🚀 Schnellstart

```powershell
# Godot 4.4.1 (Standard, nicht .NET) installieren, dann:
Godot_v4.4.1-stable_win64.exe --path <Projektordner>

# Tests (headless):
Godot_v4.4.1-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

# 100 Sekunden Autotest mit 4 Demo-Spielern, 16-fache Geschwindigkeit:
Godot_v4.4.1-stable_win64_console.exe --headless --path . -- --autotest --players=4 --seconds=100 --speed=16 --seed=21
```

Nach neuen `class_name`-Dateien einmal `--headless --path . --import` ausführen.
Die fertige Windows-EXE wird nicht im Repository abgelegt (Dateigröße); sie entsteht mit dem Godot-Export (`export_presets.cfg`).

---

## 🧱 Aufbau

| Ordner | Inhalt |
|---|---|
| `scripts/core` | Simulation, Kalender, Ereignisse, Kunden, Immobilien, Personal |
| `scripts/economy` | Konten, Banken, Rechtsformen, Insolvenz, Bauhof, Warenbuch, Verträge |
| `scripts/ai` | Beobachtung, Aktionen, Regelspieler, Planung, Gedächtnis, API-Steuerung |
| `scripts/api` | Ollama-Adapter, OpenAI-kompatibler Adapter, Demo-Adapter, Wetterdienst, sicherer Schlüsselspeicher |
| `scripts/world`, `scripts/ui` | Isometrische Stadt, Rendering, HUD, Menüs |
| `tools/vox` | Voxel-Renderer und Modelle (Python), erzeugt `assets/iso` |
| `tests` | Testsuite und Wirtschaftscheck |
| `docs` | Wirtschaftsdesign und Spielregeln |

---

*Gebaut von Benedikt Schackenberg.*

---

# 📖 Handbuch

Retro-Pixel-Wirtschaftssimulation für Windows: Zwei bis vier **autonome KI-Spieler** bauen in einer großen isometrischen Voxel-Pixelstadt (256 × 256 Felder, Dimetrie 2:1, ein Feld = Raute 128 × 64 px) je eine Spedition auf. Die Stadt lebt von selbst: echtes Mainzer Wetter, automatische Ereignisse mit Ursachen und Kundenfiguren mit konkreten Anliegen. Sie handeln, reden, kooperieren und sabotieren sich gegenseitig. Du richtest die Partie ein und schaust zu.

- **Engine:** Godot **4.4.1-stable** (typisiertes GDScript, GL-Compatibility-Renderer)
- **Status:** v0.2.0 – Stadtleben (Wetter, Ereignisse, Kunden), isometrische Voxelgrafik und transparente KI-Aktivität; siehe [Testbericht](#testbericht) und `STATUS.md`

---

## Schnellstart

### A) Fertige Windows-Version
`build\PixelTransportRivals.exe` starten. Die EXE ist eigenständig, die Spieldaten sind eingebettet.

### B) Aus dem Quellcode
1. Godot 4.4.1 (Standard, nicht .NET) installieren: https://godotengine.org/download/archive/4.4.1-stable/
2. Projekt öffnen: `Godot_v4.4.1-stable_win64.exe --path <Projektordner>` oder im Projektmanager `project.godot` importieren.
3. Mit F5 („Projekt starten“) spielen.

### Eine Partie einrichten
Im Startmenü legst du pro Spieler (2–4) fest:
- Name, Firma, Farbe, Avatar und Persönlichkeit
- **Anbieter**, **Basis-URL** und **Modell**; bei externen Anbietern zusätzlich den **API-Key**
- Entscheidungsintervall, Anfrage- und Tokenbudget, Ersatzmodus und einen optionalen Strategie-Zusatz

Global wählst du außerdem Seed, Partiedauer (5/15/30/60/120/240 Minuten, 12 h, 24 h aktive Echtzeit oder **Endlos**), Startgeschwindigkeit und das **Wetter** (Live Mainz, simuliertes Ersatzwetter oder Wiederholung des Wetters der letzten Partie).

| Anbieter | Bedeutung |
|---|---|
| **Ollama lokal** | Lokales Modell über `POST {Basis-URL}/api/chat`, ohne API-Key. Vorbelegt: `http://127.0.0.1:11435` und `qwen3.5:9b-q4_K_M`. Der Denkmodus ist aus; ein 24k-Kontextfenster und ein JSON-Schema halten auch die langen Spiel-Prompts und Aktionsantworten vollständig. |
| **Externe API** | OpenAI-kompatibler Aufruf über `POST {Basis-URL}/chat/completions`. HTTPS-Adresse, Modell und API-Key pro Spieler, etwa für OpenAI oder OpenRouter. Lokale kompatible Server können auch über `localhost` angesprochen werden. |
| **IONOS · Qwen** | Vorbelegtes externes Profil mit IONOS-Adresse und Qwen-Modell; benötigt einen IONOS-Token als API-Key. |
| **DEMO (simuliert)** | **Keine KI.** Regelbasierte Testantworten laufen durch denselben Parser. In der UI überall als „DEMO“ gekennzeichnet. Mit einstellbarer Fehlerquote (ungültiges JSON, Rate Limit, Timeout) |

`config/example_config.json` zeigt eine gemischte Partie mit externen APIs, lokalem Ollama und Demo **ohne** Zugangsdaten (Button „Beispielkonfiguration laden“).

### Ollama und WebUI lokal starten

Der Docker-Stack in `local-ai/compose.yaml` stellt Ollama mit NVIDIA-GPU und Open WebUI bereit. Die WebUI ist unter <http://127.0.0.1:3000> erreichbar, die Ollama-API unter <http://127.0.0.1:11435>. Beide Ports sind nur an den lokalen Rechner gebunden. Wenn dieser Stack bereits läuft, kannst du im Startmenü sofort „Ollama lokal“ wählen.

Für eine neue Installation zuerst einen eigenen `WEBUI_SECRET_KEY` in `local-ai/.env` erzeugen. Diese Datei wird nicht in Git aufgenommen:

```powershell
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
Set-Content local-ai/.env ("WEBUI_SECRET_KEY=" + [Convert]::ToHexString($bytes).ToLowerInvariant())
docker compose -f local-ai/compose.yaml up -d
docker compose -f local-ai/compose.yaml exec ollama ollama pull qwen3.5:9b-q4_K_M
```

Beim ersten WebUI-Aufruf ein lokales Admin-Konto anlegen. Im Spiel wählst du den Anbieter **für jeden Spieler einzeln**. Ollama braucht keinen Key; bei externen Anbietern bleiben URL, Modell und Key ebenfalls je Spieler getrennt.

**Externe API-Keys** liegen nur im Arbeitsspeicher. Sie werden nie in Spielständen, Logs, `setup.json` oder Dialogen gespeichert. Nur wenn du „Key im Win-Tresor“ ankreuzt, landet der Key in der **Windows-Anmeldeinformationsverwaltung** (Generisch, Ziel `PixelTransportRivals/slotN`). Ollama sendet keinen Key. Entfernst du bei einem externen Anbieter den Haken, wird der Eintrag beim nächsten Start gelöscht.

### Bedienung (Zuschauer)
| Eingabe | Wirkung |
|---|---|
| WASD / Pfeiltasten, rechte oder mittlere Maustaste ziehen | Kamera bewegen |
| Mausrad | Zoom (0,25×–4×) |
| Linksklick | Figur, Kundenfigur, Fahrzeug oder Gebäude auswählen (Info unten; bei Gebäuden zählt das sichtbare Pixel) |
| F / Button „Folgen“ | Kamera folgt der Auswahl bzw. der Spielfigur |
| Klick auf ein Unternehmerporträt | Detailfenster für diese Person und ihre Firma öffnen; dort „Folgen“, „Betriebshof“ oder „Verlauf“ wählen |
| Escape / „Schließen“ / Klick außerhalb des Detailfensters | Unternehmerdetails schließen |
| Leertaste / 1–5 | Pause / Simulationsgeschwindigkeit 1×–16× |
| F5 / „Speichern“, „Laden“ | Schnellspeichern / Laden (ohne Keys) |
| Minimap | Klicken oder ziehen springt mit der Kamera |

Links stehen zunächst nur die **Porträts der Unternehmer**. Ein Klick öffnet ein live aktualisiertes Detailfenster: Unternehmenszahlen, aktueller Zustand, Personal und Aufträge stehen neben dem selbst formulierten KI-Ziel, zuletzt berücksichtigten Ereignissen, dokumentierter Begründung, Planfortschritt, nächstem Schritt und KI-Status. Die Schaltflächen *Folgen*, *Betriebshof* und *Verlauf* stehen im Fenster. Das **Wetter** ist kompakt in der Kopfleiste; Niederschlag, Wind, Datenzeit und Abrufstatus zeigt der Tooltip. Rechts gibt es die Reiter **Aktivitäten** (was jede KI gerade tut und warum), **Lage** (Wetter, Zeitachsen, aktive Ereignisse mit Ursache → Wirkung → Aufträge → Entscheidungen, wartende Kunden), **Ereignisse**, **Dialoge**, **Aufträge**, **Fahrzeuge**, **Finanzen**, **KI-Spieler**, **Personal** und **Entscheidungen** (filterbar nach Herkunft und Unternehmen, mit Folgen).

---

## Spielregeln (Kurzfassung)

**Zeit.** Die Partiedauer zählt nur **aktive Echtzeit**; Pausen und Menüs zählen nicht (4 h, 12 h, 24 h oder Endlos). Die Simulationsgeschwindigkeit (1×–16×) beschleunigt nur die Spielwelt und wird oben **getrennt** von der Restzeit angezeigt. Drei Zeitachsen bleiben getrennt: aktive Partiedauer, **Spielkalender** (1 Spieltag = 60 s bei 1×, 1 Monat = 30 Tage, 1 Jahr = 12 Monate; ein Spieltag ist zugleich ein Tag-Nacht-Zyklus; konfigurierbar in `GameCalendar`) und die **reale Wetterzeit**. Logistik (Fahrten, Ladezeiten, Fristen) läuft intern in Spielminuten (1 Sim-Sekunde = 2 Spielminuten). Nach Ablauf stoppt das Spiel geordnet und zeigt die Endauswertung.

**Gewinnwertung = kumulierter Nettogewinn**, also Erlöse minus laufende Kosten, Abschreibungen, Zinsen, Vertragsstrafen und sonstige Aufwendungen.
- Startkapital (50.000 €) und Kredite sind kein Gewinn. Tilgung ist kein Aufwand, Zinsen sind Aufwand.
- Fahrzeugkäufe sind Investitionen. Abschreibung: linear **2 % des Kaufpreises pro Spieltag** bis auf 20 % Restwert. Ein Verkauf bucht *Erlös − Buchwert* (Händler zahlt 85 % des Buchwerts).
- Jede Buchung erfolgt genau einmal. Geprüfte Identität: **Bargeld + Buchwert − Schulden = Startkapital + Gewinn**.
- Bei Spielende gilt: Überfällige Aufträge erhalten eine Vertragsstrafe; laufende, noch fristgerechte Aufträge werden **ohne Vergütung** storniert.
- Gleichstand: zuerst Reputation, dann erledigte Aufträge.
- Gewinn, Bargeld, Schulden und Vermögen werden getrennt angezeigt. Kredite erhöhen den Punktestand nicht, kosten aber Zinsen (1,2 %/Tag; Dispo 3 %/Tag).

**Fahrzeuge**

| Modell | Preis | Kapazität | Tempo | Kosten/Tile | Besonderheit |
|---|---|---|---|---|---|
| Kleintransporter | 12.000 | 8 | 2,8 | 0,60 | Start |
| Lieferwagen | 22.000 | 18 | 2,5 | 0,85 | |
| Kühltransporter | 32.000 | 14 | 2,4 | 1,10 | Kühlware |
| LKW 12t | 46.000 | 40 | 2,1 | 1,50 | Schwerlast |
| Sattelzug | 80.000 | 80 | 1,8 | 2,30 | Schwerlast, Container |

Weitere Kosten: Fahrerlohn 14 €/Spielstunde (plus 400 € Einstellungsgebühr), Verschleiß führt zu Reparaturen (und unter 30 % Zustand zu Pannen samt Abschleppkosten), Depotmiete 180 €/Tag (Zusatzdepots 350 €/Tag, je +4 Stellplätze).

**Aufträge** haben Abhol- und Zielgebäude, Ware, Menge, Vergütung, Frist und Fahrzeugvoraussetzungen (Kapazität, Kühlung, Schwerlast, teils Mindestreputation).
- Je angefangene Verspätungsstunde gibt es −25 % Vergütung. Mehr als 4 h über der Frist gilt der Auftrag als gescheitert: 30 % Vertragsstrafe und −6 Ruf.
- Kleine Paketaufträge kommen aus Innenstadt und Wohnvierteln; große, lukrative und riskante Aufträge aus Hafen, Industrie und Güterbahnhof.
- Gegen endlose Geldquellen helfen: begrenzter Auftragsmarkt (jeder Auftrag nur einmal vergebbar), Sättigung je Viertel und Kosten für jede Fahrt.
- 3 pünktliche Lieferungen machen einen Absender zum **Stammkunden**: Seine Aufträge sind 60 Minuten lang exklusiv und 10 % besser bezahlt.

**Fern- vs. Besuchsaktionen**

| Fern (Disposition/Telefon/Bank) | Besuch (Figur läuft hin, Ausführung und erneute Prüfung bei Ankunft) |
|---|---|
| Aufträge annehmen und zuweisen, reparieren lassen, verkaufen, Fahrer einstellen/entlassen, Kredite, Nachrichten, Angebote annehmen/ablehnen, Abwerben, Sicherheit/Versicherung, Rufschädigung | Fahrzeugkauf (Autohaus), Depotanmietung (Standort), Betriebsstörung (Depot des Ziels), Kooperationsangebot (Treffen mit der Figur des anderen) |

**Geschäfte zwischen Spielern** laufen ausschließlich als verbindliches Angebot (`offer_trade`, `propose_cooperation`) plus Annahme (`accept_trade`). Bei der Annahme prüft die Engine alles erneut und bucht für beide Seiten (Nullsumme). Arten: Fahrzeug verkaufen/kaufen, Auftrag abgeben (mit Ablöse), Zahlung, Kooperationspakt. Eine Nachricht wie „Ich verkaufe dir einen Transporter“ überträgt nichts.

**Konkurrenz und Sabotage**
- **Legal:** Fahrer mit höherem Lohn abwerben (600 €, Opfer behält mindestens einen Fahrer), Stammkunden abwerben (800 €, abhängig vom Ruf), knappe Depotstandorte und Fahrer wegschnappen.
- **Regelwidrig:**
  - *Betriebsstörung* (2.500 €, Besuch nötig): 90 Minuten mit 60 % Tempo und doppelter Ladezeit.
  - *Rufschädigung* (1.500 €): −8 Ruf.
  - Beide haben eine Abklingzeit von 6 h und eine Erfolgs- bzw. Entdeckungschance. Bei Entdeckung folgen Bußgeld, Schadensersatz an das Opfer, Reputationsverlust und bei bestehendem Pakt zusätzlich ein Paktbruch.
- **Gegenmaßnahmen:** Sicherheitsstufe 1/2 (senkt den Erfolg, erhöht die Entdeckung), Versicherung (zahlt bei Schaden), Pakte (Bruch ist teuer), Schutzfrist von 4 h je Opfer. Nichts wirkt dauerhaft, niemand wird handlungsunfähig.

---

## Stadtleben: Wetter, Ereignisse, Kunden

**Wetter Mainz** (`scripts/world/weather.gd`, `scripts/api/weather_service.gd`). Quelle ist Open-Meteo (ohne Schlüssel, **Modelldaten, keine Messung einer Wetterstation**). Der Standort wird einmal über die Geokodierung ermittelt (Mainz, Rheinland-Pfalz, nicht das bayerische Mainz) und in `user://weather_location.json` gespeichert. Beim Start und danach etwa alle 15 realen Minuten wird asynchron abgerufen: Temperatur, Zustand (WMO-Code), Niederschlag, Wind und Böen, Bewölkung, Tag/Nacht und eine 6-Stunden-Vorhersage (`Europe/Berlin`).
- Der aktuelle Niederschlag ist die **Summe über das Messintervall** (900 s) und wird mit `mm · 3600 / Intervall` in mm/h umgerechnet, nicht ungeprüft als Stundenwert behandelt.
- Bei Ausfall bleibt der letzte Stand mit wachsendem Altersstatus (40 min: veraltet, 2 h: offline); ohne Daten gilt **gekennzeichnetes simuliertes Ersatzwetter**. Im Live-Modus wird kein Ersatzwetter erfunden, solange auf die ersten Daten gewartet wird (max. 10 s).
- Die Spielgeschwindigkeit erzeugt **keine** Wetteränderungen; der Wetterstand ändert sich nur durch reale Abrufe.
- Jeder Stand wird mit der Spielminute aufgezeichnet (`user://last_weather.json`) und kann als Wiederholung abgespielt werden.
- Spieleffekte sind begrenzte, konfigurierbare Schwellenwerte (`Weather.PARAMS`): Regen und Starkregen (langsamere Fahrten, längeres Verladen im Freien, überdachte Plätze helfen, Bau langsamer), Wind (Außenarbeit, Bau), Hitze (Getränke-/Kühlbedarf), Kälte, **Glätte nur bei Frost und Feuchtigkeit**, Nebel. Alle Folgen sind **simulierte Spielereignisse**, keine Aussagen über reale Vorfälle.
- Sichtbar: Regen, nasse Straßen, Pfützen, nasse bzw. verschneite Dächer und Böden, schwingende Bäume und Fahnen, Laubflug, Nebel, Hitzeflimmern, Regenschirme.

**Automatischer Ereignismanager** (`scripts/core/world_events.gd`). Ereignisse entstehen **einmal** aus einer nachprüfbaren Ursache und verändern danach echte Zustände. Jedes hat ID, Ursache und Bedingungen, Orte, Beginn und Dauer, Schwere, Wirkung, Informationsquellen und Endebedingung. Ursachen: Wetter (Starkregen, Sturm, Glätte, Hitze, Winter, Nebel), Kundenbedarf und Lagerbestände (Nachfrageschub), Fahrzeugzustand (Ausfall durch Wartungsrückstand), Personalbelastung (Fahrerengpass), Baufortschritt (wetterbedingte Verzögerung), Angebot und Nachfrage (Preisverfall im Viertel), Handel (Frachtlieferung am Terminal, Neueröffnung, Großauftrag), Mieterwechsel und enttäuschte Kunden. Abklingzeiten je Ursache, höchstens zwei gleichzeitige schwere Störungen, danach eine ruhige Phase.

**Kundenfiguren** (`scripts/core/residents.gd`). Jedes Kundengebäude hat eine benannte Figur mit Rolle und Ort. Der Bedarf wächst aus Tageszeit, Öffnungszeiten, Wetter und Ereignissen; bei genug Druck veröffentlicht die Figur eine Anfrage als **echten Auftrag** mit Kontakt, Anliegen und Anlass. Erfüllte Anliegen haben eine lange Sperrfrist, unerfüllte werden höchstens zweimal dringlicher und besser bezahlt. Nur Figuren mit offenem Anliegen oder frischem Ergebnis stehen sichtbar am Eingang (Symbol über dem Kopf, Klick öffnet die Beschreibung). Die Engine berechnet alles; es gibt keinen API-Aufruf pro Figur.

**Transparenz.** Entscheidungen verknüpfen Ereignis, Kunde, Auftrag, Aktion und gemessene Folgen (`Entscheidungen`-Reiter, `Lage`-Reiter). Die Zuschaueransicht darf mehr zeigen als die KI-Spieler; diese erhalten nur öffentlichen Wetterstand, die Ereignislage mit Quellen und die Kunden hinter den Aufträgen, die sie kennen.

---

## KI-Schnittstelle

1. Jeder Spieler hat einen eigenen `AgentController` mit eigener Erinnerung (Notiz plus letzte Entscheidungen) und eigenem Adapter.
2. Anfragen kommen im **Intervall** (z. B. 20 s Echtzeit) und **bei Ereignissen** (Nachricht, Angebot, Lieferung, Panne, Sabotage, Fahrzeug frei, Besuch beendet). Ereignisse werden gebündelt (mindestens 6 s Abstand), es ist höchstens eine Anfrage pro Spieler unterwegs, und das Anfrage- und Tokenbudget wird eingehalten. Die KI wird nie pro Frame aufgerufen; Bewegung, Wegfindung, Verkehr und Wirtschaft laufen in der Engine.
3. Die **Beobachtung** (`ObservationBuilder`) enthält eigene Finanzen, Fahrzeuge mit Positionen, Fahrer, Aufträge, den Markt (lukrativste plus mit eigener Flotte machbare Aufträge), Preise, Verkehr, Wetter, öffentlich Sichtbares über die Konkurrenz, Nachrichten, Angebote, Ergebnisse der letzten Aktionen, Ereignisse und die verbleibende Spielzeit. Fremde Finanzen, Pläne, Notizen und Keys sind nie enthalten.
4. Die **Antwort** ist JSON: `{"summary": "...", "actions": [{"action": "...", ...}], "memory": "..."}` mit höchstens 6 Aktionen. Die `summary` erscheint für Zuschauer als Entscheidungszusammenfassung; interne Gedankengänge werden nicht verlangt.
5. Jede Aktion wird vom `ActionExecutor` gegen das Schema (Pflichtparameter, Typen) **und** gegen den aktuellen Zustand geprüft. Abgelehnte Aktionen erhält die KI in der nächsten Beobachtung mit verständlicher Begründung zurück.

Aktionen: `wait, move_to, accept_contract, assign_vehicle, repair_vehicle, buy_vehicle, sell_vehicle, hire_driver, fire_driver, rent_depot, cancel_depot, take_loan, repay_loan, send_message, offer_trade, accept_trade, reject_trade, propose_cooperation, poach_driver, poach_customer, buy_security, set_insurance, attempt_sabotage`. Das vollständige Schema mit Beschreibungen steht in `scripts/ai/action_executor.gd` (`SCHEMA`) und wird dem Modell im Systemprompt mitgegeben.

**Robustheit**
- HTTP läuft asynchron in einem eigenen Thread, Oberfläche und Simulation laufen weiter.
- Fehlerbehandlung:
  - Timeout und Wachhund, Verbindungsabbruch, HTTP-Fehler und Rate Limit (mit `Retry-After`) führen zu exponentiellem Backoff.
  - Ungültiges JSON wird gemeldet und an die KI zurückgespielt.
  - Lehnt ein Server Parameter wie `response_format`, `temperature` oder `max_tokens` ab, wird die Anfrage einmalig ohne diesen Parameter bzw. mit `max_completion_tokens` wiederholt.
- **Keine Doppelausführung:** Jede Aktion hat einen Idempotenzschlüssel `p<Spieler>:r<Anfrage>:a<Index>`. Doppelt zugestellte oder verspätete Antworten auf abgebrochene Anfragen werden ignoriert. Antworten auf einen mehr als 90 Spielminuten alten Zustand werden verworfen. Schlüssel und Zähler werden mitgespeichert.
- Bei API-Ausfall laufen bestehende Fahrten weiter. Nach 3 Fehlern in Folge übernimmt (falls aktiviert) der **ERSATZMODUS (regelbasiert)**, sichtbar markiert in Firmenkarte, Ereignisprotokoll und Endauswertung. Die API wird alle 60 s erneut versucht.
- **Protokoll:** `%APPDATA%\Godot\app_userdata\Pixel Transport Rivals\logs\match_*.jsonl` enthält Anfragen, Antworten, Fehler und ausgeführte Aktionen ohne Header und Keys. Bekannte Keys werden zusätzlich geschwärzt.

**Weitere Anbieter:** Von `LLMAdapter` (`scripts/api/llm_adapter.gd`) erben, `send()` und `cancel()` implementieren, `completed` emittieren und in `LLMAdapter.create()` registrieren.

---

## Architektur

```
project.godot, export_presets.cfg
scenes/main.tscn            Einstieg
scripts/main.gd             Menü → Partie → Auswertung, Autotest-Modus
scripts/core/
  catalog.gd                alle Spielkonstanten (Wirtschaft, Fahrzeuge, Waren, Sabotage, Zeit)
  simulation.gd             Spielzustand + Simulationsschritt (ohne Rendering/KI), Speichern/Laden
  game_session.gd           Partie: Zeitmodell, Speed/Pause, Kamera, Spielende, Spielstand
scripts/world/
  city_data.gd              Kartendaten
  city_generator.gd         Stadt aus Seed: Straßenraster, 6 Viertel, Küste/Hafen, Sonderbauten (Schule, Kita, Frachtterminal, Villen), faire Startdepots
  nav_grid.gd               A* Straßennetz (Fahrzeuge), A* Fußwege (Figuren), Baustellen/Staus
  iso.gd                    Dimetrie 2:1: Umrechnung Welt <-> Bildschirm, Tiefensortierstreifen
  city_view.gd              isometrischer Boden, Gebäude in Sortierstreifen, Deko, Ampeln, Tag/Nacht, Wetterdarstellung
  entity_view.gd            Fahrzeuge (4 Richtungen, Firmenfarbmaske), Figuren, Kunden, Sprechblasen, Auswahl
  estate_view.gd            Betriebshöfe und Einrichtungen
  weather.gd                öffentlicher Wetterstand, Einordnung, Spieleffekte, Aufzeichnung/Wiederholung
scripts/entities/           mover.gd (Pfad + Rechtsverkehr), fleet_vehicle.gd, avatar.gd
scripts/economy/            ledger.gd (Buchhaltung), company.gd, contract.gd, market.gd
scripts/core/ (weitere)     world_events.gd (Ereignismanager), residents.gd (Kundenfiguren), game_calendar.gd (Spielkalender)
scripts/social/             social.gd (Nachrichten, Angebote, Pakte, Vertrauen), rivalry.gd (Abwerben, Sabotage)
scripts/ai/                 action_executor.gd (Schema + Prüfung + Ausführung), observation_builder.gd,
                            agent_controller.gd (Planung, Budgets, Fehler, Idempotenz), rule_brain.gd (Demo/Ersatz)
scripts/api/                llm_adapter.gd, ollama_adapter.gd, openai_adapter.gd, demo_adapter.gd, credential_store.gd, api_log.gd, weather_service.gd
scripts/ui/                 setup_menu.gd, hud.gd, live_text.gd, minimap.gd, profit_chart.gd, end_screen.gd, ui_theme.gd
assets/iso                  isometrische Voxelgrafik (tools/build_iso.py), assets/shaders (Boden, Wind, Nebel, Hitze)
assets/gfx, assets/sfx      Symbole, Lichtflecken, Sounds (tools/gen_assets.py), assets/fonts (Pixelify Sans, OFL)
tools/vox/                  Voxel-Renderer und Modelle (Gebäude, Fahrzeuge, Figuren, Requisiten, Boden)
tests/run_tests.gd          Headless-Tests; tests/test_credentials.gd (Windows-Tresor)
tools/mock_openai_server.py lokaler OpenAI-kompatibler Mock mit Fehlerinjektion
```

Die Simulation ist vom Rendering getrennt. Deshalb laufen Wirtschaft, Fahrzeuge und Aktionen in den Tests vollständig headless, und Speichern/Laden muss keine Szenenknoten serialisieren.

---

## Tests und Prüfbefehle

```bat
set GODOT=C:\Pfad\Godot_v4.4.1-stable_win64_console.exe
:: Unit-/Integrationstests (headless)
%GODOT% --headless --path . -s res://tests/run_tests.gd
:: Optional: echtes lokales Modell prüfen (Ollama-Stack und Qwen müssen laufen)
%GODOT% --headless --path . -s res://tests/ollama_smoke.gd
:: Verkürzte Partie, 4 Demo-Spieler, endet automatisch und prüft den Gewinner (Exit-Code 0 = OK)
%GODOT% --headless --path . -- --autotest --players=4 --seconds=60 --speed=16
:: Echter HTTP-Adapter gegen lokalen Mock-Server
python tools\mock_openai_server.py 8765
set PTR_TEST_KEY=sk-irgendwas
%GODOT% --headless --path . -- --autotest --players=2 --seconds=75 --speed=8 --provider=openai --base-url=http://127.0.0.1:8765/v1 --model=mock-1 --api-key-env=PTR_TEST_KEY --interval=4 --timeout=10
:: API-Ausfall (nicht erreichbarer Server)
%GODOT% --headless --path . -- --autotest --players=3 --seconds=45 --speed=8 --provider=openai --base-url=http://127.0.0.1:9/v1 --model=x --timeout=5
:: Live-Wetter (echter Abruf bei Open-Meteo) und Sichtprüfung per Screenshot (Fenster nötig)
%GODOT% --path . -- --autotest --players=4 --seconds=60 --speed=8 --weather=live --screenshot=C:\temp\shot.png --shot-at=40 --shot-tile=80,106 --shot-zoom=1 --wx=rain --hour=11
:: Weitere Prüfoptionen: --wx=rain|storm|hot|snow|fog|wind  --hour=22  --shot-follow=plot0|worker|person  --scenario=yard  --no-residents
:: Speichern bei 15 s, danach laden und zu Ende spielen
%GODOT% --headless --path . -- --autotest --players=3 --seconds=30 --speed=8 --save-at=15
%GODOT% --headless --path . -- --autotest --load
```

## Testbericht

Der aktuelle vollständige Headless-Lauf unter Godot 4.7.2 bestand 4374 Prüfungen ohne Testfehler, einschließlich Ranglisten-, Wirtschaftskreislauf-, Mehrjahres-, Kraftstoff- und Anbieterwahltest. Der folgende Bericht hält zusätzlich frühere Prüfungen unter Godot 4.4.1 fest. Externe Modell-APIs wurden mangels Key nicht live getestet. Neu hinzugekommen ist ein erfolgreicher Aufruf des lokalen Qwen-3.5-Modells über Ollamas native API mit Godot 4.7.2; der Antwortparser akzeptierte dessen Aktions-JSON. Der Wetterdienst wurde gegen das echte Open-Meteo getestet. Die Spalte „Adapter“ zeigt, womit jede Prüfung lief.

| Prüfung | Adapter | Ergebnis |
|---|---|---|
| 4142 Headless-Prüfungen (zusätzlich zu den unten genannten: Wetter-Parser und Einheiten, Altersstatus, Aufzeichnung/Wiederholung, Wetterdienst mit Fehlerfällen, Wirkung der Schwellenwerte, Ereigniskette Wetter → Bedarf → Kundenanfrage → Entscheidung → Lieferung → Zufriedenheit, Obergrenze schwerer Störungen und ruhige Phase, Sperrfrist erfüllter Anliegen, Vollständigkeit der Grafikdaten, Iso-Geometrie und Sortierstreifen, Speichern/Laden der Kunden): Stadtgenerator (Zugänge, Viertel, faire Starts, Reproduzierbarkeit), Bilanzidentität über Kauf/Kredit/Tilgung/Abschreibung/Verkauf/Simulation, Doppelausführung, ungültige Aktionen (10 Fälle, kein Geldeffekt), Nachricht ≠ Besitz, Nachrichtenbudget, Handel (Auftrag + Fahrzeug, Nullsumme, keine Doppelannahme), Sabotage (Kosten, Abklingzeit, Schutzfrist, Besuch, Befristung, Sicherheit), echte Lieferung mit Ware, Spielende-Abrechnung, Rangfolge + Tie-Break, Speichern/Laden, JSON-Parser (Codeblock, Begleittext, kaputt, fehlende Felder, Aktionslimit), Controller (doppelt zugestellt, verspätet, veraltet, ungültig) | ohne Adapter / Controller direkt | 0 Fehler |
| 4-Spieler-Partie, automatisches Ende, korrekter Gewinner, Identitätsfehler 0, keine Frames > 100 ms | DEMO (simuliert, 10 % Fehlerquote) | OK |
| Echter OpenAI-HTTP-Adapter: Bearer-Key kommt an, `response_format`-Ablehnung wird erkannt, 429/500/Timeout/ungültiges JSON abgefangen, absichtlich ungültige Aktion abgelehnt | **Mock-Server** (lokal, keine KI) | OK |
| API-Key in keiner Datei unter `app_userdata` (Logs, Ergebnis) | Mock-Server | 0 Treffer |
| Anbieterwahl pro Spieler, getrennte URL/Modell/Key, Ollama ohne Key und mit nativem JSON | Ollama- und Menütests | OK |
| Echtes Aktions-JSON von `qwen3.5:9b-q4_K_M` auf der lokalen GPU | Ollama native API | OK |
| API nicht erreichbar → ERSATZMODUS, Spiel läuft weiter (max. Frame 40 ms) | OpenAI-Adapter gegen geschlossenen Port | OK |
| Windows-Tresor: Speichern, Lesen, Löschen eines Dummy-Keys | – | OK |
| Speichern in laufender Partie, Laden, Weiterspielen bis zum Ende | DEMO | OK |
| **Exportierte EXE** (`build/PixelTransportRivals.exe`) spielt Autotest-Partie, Exit-Code 0, Identitätsfehler 0 | DEMO | OK |
| Sichtprüfung per Screenshot im laufenden Spiel: Tag, Regen, Schnee, Nebel, Nacht, Innenstadt, Flughafen, Nahaufnahmen (Zoom 1–2), Betriebshof im Ausbau, Unternehmenskarten, Kundenfigur mit Auswahltext | DEMO | OK |
| Live-Wetter: Standort Mainz (Rheinland-Pfalz) gefunden und gespeichert, Abruf übernommen, Verlauf aufgezeichnet | Open-Meteo (echt) | OK |
| Leistung 4 Spieler bei 16×: ca. 17 ms je Bild (Simulation 4 ms, Stadtansicht 1,5 ms, Entitäten 2,7 ms) | DEMO | OK |
| Verbindliche Geschäfte in normaler Demo-Partie (Kooperationspakte zwischen Spielern) | DEMO | OK |

## Windows-Export (reproduzierbar)
1. Export-Templates 4.4.1 installieren: im Editor *Editor → Export-Vorlagen verwalten → Herunterladen*, oder `Godot_v4.4.1-stable_export_templates.tpz` (ZIP) nach `%APPDATA%\Godot\export_templates\4.4.1.stable\` entpacken.
2. `Godot_v4.4.1-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/PixelTransportRivals.exe`

Das Preset `Windows Desktop` (x86_64, PCK eingebettet, `*.json` eingeschlossen) liegt in `export_presets.cfg`. Die EXE ist nicht signiert, daher kann Windows SmartScreen beim ersten Start warnen.

## Assets neu erzeugen
`python tools/build_iso.py` (benötigt Pillow und NumPy) rendert Boden, Gebäude (inkl. Nachtlicht- und Dachmasken), Einrichtungen, Fahrzeuge, Figuren und Requisiten aus den Voxelmodellen in `tools/vox/` nach `assets/iso/`. `python tools/gen_assets.py` erzeugt weiterhin Symbole, Lichtflecken und Sounds. Danach `--import` ausführen; die Mipmap-Einstellung der Iso-Texturen (`mipmaps/generate=true` in den `.import`-Dateien) ist für das ruhige Verkleinern bei Zoom < 1 nötig.

## Annahmen und bekannte Grenzen
- **Karte:** Das Straßennetz ist ein unregelmäßiges Raster mit dichterer Innenstadt und größeren Blöcken am Rand. Es gibt keine geschwungenen Straßen und keine Bahnstrecke; der Güterbahnhof ist ein Gebäude. Die Straßen sind einspurige Felder mit Rechtsverkehr-Versatz. Die Stadt hat rund 4.400 Gebäude und ebenso viele Kundenfiguren in den Daten; gezeichnet werden nur die mit offenem Anliegen.
- **Fahrzeuge** fahren einen Auftrag pro Fahrt (Warteschlange bis 3). Es gibt keine Sammeltouren und keine Teilladungen.
- **Grafik:** Zustandsvarianten von Gebäuden (Verfall, Renovierung) gibt es noch nicht. Ein- und Aussteigen der Fahrer wird nicht animiert (Fahrer sind im Fahrzeug unsichtbar). Kundenfiguren hinter hohen Gebäuden sind verdeckt, ihr Symbol bleibt sichtbar.
- **Fußgänger und NPC-Verkehr** sind Statisten. Der NPC-Verkehr erzeugt aber echte Staus an Ampeln und Engstellen. Wer 6 s blockiert ist, fährt weiter, damit kein Dauerstau entsteht.
- Die **KI-Erinnerung** ist bewusst kompakt (Notiz plus letzte 5 Entscheidungen), damit die Tokenkosten begrenzt bleiben.
- **Spielstand:** eine Schnellspeicherdatei (`user://saves/quicksave.json`). Laufende Figurenbesuche werden beim Laden verworfen. Die Keys kommen beim Laden aus dem Windows-Tresor (falls gespeichert); sonst geht der betroffene Spieler in den Ersatzmodus, bis ein Key gesetzt ist.
- **Ausgewogenheit:** In Demo-Partien liegen sparsame Logistiker vorn, und Sabotage lohnt sich selten. Bei sehr hoher Simulationsgeschwindigkeit (16×) reagieren echte Modelle im Verhältnis zur Spielwelt langsam; für echte KIs sind 1×–4× gedacht.
- Die **Sounds** sind einfache generierte Effekte (kein Musiktrack).

## Lizenzen
Schrift: Pixelify Sans (SIL Open Font License, `assets/fonts/OFL.txt`). Alle übrigen Grafiken und Sounds werden von `tools/gen_assets.py` erzeugt und gehören zum Projekt.
