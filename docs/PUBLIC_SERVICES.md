# Auftrag 20: Kommunale Dienste, individuelle Gebäude und Fahrzeuge, regionale KI-Politik

Eingang 09.11.2026 (Benedikt). Arbeit im Worktree `PTR_hub`, Veröffentlichung auf `region`, `main`, `unternehmer`.

## Kern des Auftrags (gekürzt)

Zehn neue Systeme: Feuerwehr, Rettungsdienst/Krankenhäuser, Bauhöfe/Straßenreinigung/Winterdienst, ÖPNV mit Buslinien, Schulen/Kitas/Bildung,
Recyclingindustrie, regionale Infrastrukturverwaltung, Bürgermeisterkonferenzen mit Abstimmungen, individuelle Gebäude- und
Fahrzeuggenerierung, wirtschaftliche Integration. Verbindlich: **jedes Gebäude sieht individuell aus** (≥ 6 strukturell verschiedene
Grundvarianten je Typ, gespeicherter Seed, Stadtstile), **Fahrzeuge passen zum Einsatzzweck**, jede Einrichtung hat **Personal, Kosten,
Aufgaben und Wirkung**, die **Bürgermeister-KI entscheidet** über Bau/Ausbau/Schließung, regionale Projekte brauchen **echte
Verhandlungen und Abstimmungen** (3 von 4 Stimmen, Einstimmigkeit für Eigentumsfragen, Kernkraftwerk bleibt 25/25/25/25), alles sichtbar
gebaut und im Dashboard erklärt. Keine funktionslosen Gebäude, keine erfundenen Wirtschaftsergebnisse. Abnahmetests A–J.

## Bestand (wird erweitert, nicht ersetzt)

| Bereich | vorhanden | Lücke |
|---|---|---|
| Gesundheit | `PublicSafety`: Erkrankung, Arztpraxis, Krankenwagen, Krankenhaus, Kosten an Stadtkasse | ein Krankenhaus, keine Kapazität/Wachen je Stadt, kein Notarzt |
| Feuerwehr | nur Flughafenfeuerwehr (`Airport`, Brand im Frachtterminal) | Wachen je Stadt, Brände, Disposition, Schaden → Reparatur |
| Straßen | `RoadCare`: Zustand je 16×16-Abschnitt, Verschleiß durch Verkehr/Frost/Regen, Instandsetzung, Bautrupps sichtbar | Bauhof als Gebäude mit Personal/Fahrzeugen, Schlaglöcher sichtbar, Winterdienst/Schnee |
| Müll | `Waste` + Müllwagen, Deponie | Wertstoffströme, Recyclinganlagen, Sekundärrohstoffe als Ware |
| Bildung | Schule/Kita als Liefer-Kundengebäude, Arbeitgeber „Schulen und Klinik“ | Plätze, Kinder, Qualifikation über Zeit |
| ÖPNV | – | alles |
| Region | `RegionalProjects` (Verbindungsstraße mit Kostenanteilen und Beschlüssen), `CivicWorks` (Bauplaner, Validator, Großlager-Besuch) | Regionalrat, Konferenz alle 30 Tage, Anträge/Verhandlung/Abstimmung, weitere Projektarten |
| Grafik | Voxel-Pipeline `tools/vox` → `assets/iso`, Seed-Varianten für Wohnhäuser | Baukasten für öffentliche Gebäude, Stadtstile, Einsatzfahrzeuge |

## Architektur

* **`Municipal` (scripts/economy/municipal.gd)** – einheitliches Modell aller kommunalen Einrichtungen: Typcode (FW-01 …), Name aus
  Stadt/Stadtteil/Lage, Stil und visueller Seed, Sprite-Variante, Größe, Baukosten, Unterhalt, Kapazität, Personalbedarf je Beruf,
  Strom/Wasser, Zustand, Inventar, Eigentümer (Stadt), Status. Personal sind echte Bürger (Citizens, Arbeitgeber je Stadt und Dienst),
  Löhne und Unterhalt aus der Stadtkasse. Fahrzeuge mit Typ, Betreiber, Kennung („HLF 20 – Feuerwache Nord – Fahrzeug 1“), Fahrer,
  Status, Zustand, Kosten. Aufgaben (Einsätze) mit ID, Einrichtung, benötigten Leuten/Fahrzeugen, Ziel, Priorität, Fortschritt, Ergebnis.
* Fachsysteme nutzen dieses Modell: `FireService`, Rettung (Erweiterung `PublicSafety`), Bauhof/Winterdienst (Erweiterung `RoadCare`),
  `Transit`, `Education`, `Recycling`, `RegionalCouncil`.
* Bau neuer Einrichtungen über die vorhandene Bürgermeister-Pipeline (Validator, Rat, Ausschreibung, Baufirma, Material) – sichtbar.
* Grafik: `tools/vox/public.py` – Baukasten mit Fassaden (8), Dächern (7), Grundrissen, Grundstücksmodulen; je Typ ≥ 6 strukturell
  verschiedene Grundvarianten; Stadtstile (Backstein-traditionell, modern Glas/Beton, grün/Holz, Industrie) wählen passende Varianten.
  Einsatzfahrzeuge als eigene Voxelmodelle (Fahrgestell, Achsen, Aufbauten, Blaulicht).

## Etappen

1. **Fundament:** `Municipal`-Modell, Namen, Stile, Personal/Kosten/Fahrzeuge/Aufgaben, Speichern/Laden, Startausstattung je Stadt.
2. **Gebäude-Baukasten:** `public.py`, Varianten aller Typen, Stadtstile, Manifest; Test A (10 Feuerwachen).
3. **Fahrzeuge:** Sprites aller Einsatz-, Bauhof-, Bus- und Recyclingfahrzeuge.
4. **Feuerwehr:** Wachen, Personal, Brandursachen, Disposition, Löschen sichtbar, Schaden → Reparaturauftrag, Nachbarschaftshilfe; Test B.
5. **Rettungsdienst/Krankenhäuser:** Wachen und Kliniken je Stadt, Kapazität, medizinische Güter; Test C.
6. **Bauhof, Straßen, Winterdienst:** Bauhof-Gebäude, Schlaglöcher, Schnee und Räumung mit Prioritäten; Test D.
7. **ÖPNV:** Verkehrsbetriebe, Haltestellen, Linien, Fahrplan, Fahrgäste, Wirtschaftlichkeit; Test E.
8. **Bildung:** Kinder, Plätze, Lehrkräfte, Qualifikation über Zeit, Engpass → Neubau; Test F.
9. **Recycling:** Wertstoffströme, Anlagen, Sekundärrohstoffe, private Recyclingfirmen; Test G.
10. **Regionalrat:** Gebäude in der Kartenmitte, Konferenz alle 30 Tage mit Anreise, Anträge, Verhandlung, Abstimmung, Finanzierung,
    sichtbarer Bau; Test H.
11. **Bürgermeister-Entscheidungen und Dashboard:** Bau/Ausbau/Schließung durch die KI, Bereich „Öffentliche Dienste & Regionalpolitik“.
12. **Leistung, Abnahme A–J, Doku.**

## Stand

| Etappe | Stand |
|---|---|
| 1 Fundament | **fertig** (10.11.2026) – `scripts/economy/municipal.gd`, `sim.municipal`, Test `test_municipal`, Probe `tests/probe_municipal.gd` |
| 2 Gebäude-Baukasten | **fertig** (10.11.2026) – `tools/vox/public.py`, Test `test_public_buildings` (Abnahme A) |
| 3 Fahrzeuge | **fertig** (10.11.2026) – `tools/vox/vehicles.py` (`MUNICIPAL`), Prüfung in `test_public_buildings` |
| 4 Feuerwehr | **fertig** (10.11.2026) – `scripts/economy/fire_service.gd` (`sim.fire`), `scripts/world/fire_fx.gd`, Test `test_fire_service` (Abnahme B) |
| 5 Rettungsdienst/Krankenhäuser | **fertig** (10.11.2026) – `scripts/economy/rescue_service.gd` (`sim.rescue`), Test `test_rescue_service` (Abnahme C) |
| 6 Bauhof/Straßen/Winterdienst | **fertig** (10.11.2026) – `scripts/economy/winter_service.gd` (`sim.winter`), `scripts/world/road_state_view.gd`, Test `test_winter_service` (Abnahme D) |
| 7 ÖPNV | **fertig** (10.11.2026) – `transit_service.gd`, Test `test_transit` (Abnahme E) |
| 8 Bildung | **fertig** (10.11.2026) – `education.gd`, Test `test_education` (Abnahme F) |
| 9 Recycling | **fertig** (10.11.2026) – `recycling.gd`, Test `test_recycling` (Abnahme G) |
| 10 Regionalrat | **fertig** (10.11.2026) – `regional_council.gd`, Test `test_regional_council` (Abnahme H) |
| 11 Entscheidungen und Leitstelle | **fertig** (10.11.2026) – `service_planner.gd`, Leitstelle „Öffentliche Dienste & Regionalpolitik“, Test `test_service_planner` (Abnahme I) |
| 12 Leistung, Abnahme | **fertig** (10.11.2026) – Probe `tests/probe_services.gd` (Abnahme J) |

**Etappe 1 im Detail**

* Einrichtungstypen mit Typcode (`FW-01` Feuerwache, `RW-01` Rettungswache, `KH-01` Krankenhaus, `BH-01` Bauhof, `VB-01` Busbetriebshof,
  `SC-01` Grundschule, `KI-01` Kita, `RC-01` Recyclinghof), Berufe mit Lohn und Mindestbildung, Fahrzeugtypen (HLF 20, DLK 23, RTW, NEF,
  Kipper, Streuwagen, Linienbus, Wertstoffwagen) mit Besatzung, Tageskosten und Kaufpreis.
* Einrichtung: ID `M<n>`, Name aus Typ und Lage zur Stadtmitte („Feuerwache Nord“, je Stadt eindeutig), Stadtstil aus dem Ortscharakter
  (Marktflecken → Backstein, Handwerkerort → Industrie, Fischer-/Bauerndorf → Grün/Holz, sonst modern), gespeicherter visueller Seed und
  Variante 0–5 (für Etappe 2), Größe, Bau- und Unterhaltskosten, Kapazität, Strom/Wasser, Zustand, Inventar, Eigentümer `stadt<k>`, Status.
* Personal sind echte Bürger (Arbeitgeber `kommunal`, Lohn je Beruf über den Monatsabschluss aus der Stadtkasse der Wohnstadt). Der Bedarf
  wächst mit der Einwohnerzahl (Werte gelten für 1000 Einwohner, Mindestbesetzung je Typ); bei Schrumpfung wird nicht entlassen, nur nicht
  nachbesetzt. Eingestellt werden zuerst Arbeitslose der Stadt mit passender Bildung, danach wechseln schlechter bezahlte Beschäftigte privater
  Arbeitgeber (sichtbar im Aktivitätsprotokoll). Höchstens 3 Einstellungen je Einrichtung und Tag. Der verwaltete Arbeitgeber wird im
  Monatsabschluss nicht von der Zufallsschwankung entlassen (`Citizens.EMPLOYERS[...].managed`).
* Freiwillige Feuerwehr: kleine Orte haben 1 hauptamtlichen Gerätewart und bis zu 8 Ehrenamtliche (Bürger mit eigenem Beruf, 18–60 Jahre,
  Aufwandsentschädigung 4 €/Tag), die bei Einsätzen mitzählen.
* Fahrzeuge `MV<n>` mit Kennung „HLF 20 – Feuerwache Mitte – Fahrzeug 1“, Fahrer aus dem Personal, Status bereit/im Einsatz/Werkstatt/außer
  Dienst, Zustand, Tageskosten. DLK und NEF gehören erst ab 500 Einwohnern zur Erstausstattung.
* Aufgaben/Einsätze `E<n>`: `open_task` (Art, Ort, Priorität, Personal, Fahrzeugtypen), `dispatch` (teilt freie Fahrzeuge und Personal zu
  oder bleibt offen mit Begründung), `finish`. Abgeschlossene werden auf 200 begrenzt.
* Kosten: Sachkosten (skaliert mit der Ortsgröße, 30–100 %) plus Fahrzeugkosten täglich von der Stadtkasse an S0, gebucht im Ressort des Typs
  (Sicherheit, Gesundheit, Verkehr, Bildung, Umwelt).
* Startausstattung: am ersten Spieltag je Stadt Feuerwache und Rettungswache auf freiem städtischem Bauland nahe dem Rathaus (Bauplatzsuche
  der Stadtentwicklung), als Laufzeitgebäude – alte Spielstände bekommen sie beim nächsten Tageswechsel, neue legen sie beim Laden genau wieder an.
* Nur in der Weltart Region aktiv (wie die Stadtentwicklung).

**Etappe 2 im Detail**

* `tools/vox/public.py`: Bausteine Halle (Sektionaltore in Kennfarbe, Traufband), Mehrgeschosser (auch als Aufbau), Turm
  (Schlauch-/Übungsturm, Silo), Unterstand, Salzkuppel, Schüttguthaufen, Wertstoffcontainer, Hubschrauberlandeplatz, Rotkreuzschild,
  Blaulicht, Spielfeld/Spielgeräte. Stile: Backstein (Klinker, Satteldach, Sprossenfenster, Hecken), modern (Putz, Flachdach mit Technik,
  Fensterbänder), grün (Lärchenholz, Gründach mit Solar, hohe Fenster, Bäume), Industrie (Blechverkleidung, Sheddach, dunkles Glas, Asphalt).
* Je Typ sechs strukturell verschiedene Grundvarianten, z. B. Feuerwache: Hallenzeile mit Turm, L-Form, Zentralturm zwischen zwei Hallen,
  Tore unten/Büros oben, Halle mit freistehendem Übungsturm, lange Halle mit Kopfbau. Größen: Feuerwache 4×3, Rettungswache 3×2,
  Krankenhaus 5×4, Bauhof 4×3, Busbetriebshof 5×3, Schule 6×4, Kita 4×3, Recyclinghof 4×3.
* 8 Typen × 6 Varianten × 4 Stile = 192 Gebäudebilder (`assets/iso/b_pub_<typ>_<v>_<stil>.png`, Bau: `python tools/build_iso.py public`).
* `Municipal.pick_variant`: Grundvariante aus dem gespeicherten Seed, schon vergebene Kombinationen aus Typ und Stil werden übersprungen,
  solange eine freie existiert – zehn Feuerwachen in der Region sehen verschieden aus. Das Bild wird im Laufzeitgebäude gespeichert.
* Kamera für Sichtprüfung: `--shot-dienst=<n>` (n-te Einrichtung).

**Etappe 3 im Detail**

* Eigene Voxelmodelle in vier Fahrtrichtungen (`assets/iso/v_<name>_<0-3>.png`, Bau: `python tools/build_iso.py vehicles`), feste
  Farben ohne Firmenmaske: `fw_hlf` (HLF 20: Mannschaftskabine, Geräteräume mit Rollläden, Dachkasten mit Steckleiter), `fw_dlk`
  (Drehleiter mit Drehkranz und Rettungskorb, drei Achsen), `rd_rtw` (Rettungswagen), `rd_nef` (Notarzt-Kombi), `bh_kipper` (Kipper mit
  Schotter), `bh_streu` (Streuwagen mit Salztrichter, Räumschild, Streuteller), `bus` (Linienbus mit Fensterband, drei Türen,
  Zielanzeige), `rc_wagen` (Wertstoffsammler mit Pressaufbau). Zuordnung über `Municipal.VEHICLES[typ].sprite`.

**Etappe 4 im Detail**

* Brandentstehung täglich je Kundengebäude, deterministisch (Gebäude-ID, Tag): Grundrisiko 0,12 %/Tag, erhöht für Küchen
  (Restaurant, Kneipe, Disco, Hotel), Maschinen (Fabrik, Werkstatt), Lager, Höfe, Tankstellen; doppelt bei Gebäudezustand < 40
  (marode Elektrik), ×1,5 bei Hitze ohne Regen. Ursache passend zum Gebäude (Küchenbrand, Maschinenbrand, Funkenflug, Selbstentzündung
  von Heu, defekte Elektrik, …).
* Alarm an die Wache mit der kürzesten Ankunftszeit (Ausrücken + Fahrt über die Straße mit Sonderrechten), die ein freies HLF und
  mindestens 2 Einsatzkräfte hat (Hauptamtliche + Ehrenamtliche). Ausrückzeit: Berufsfeuerwehr 2, Freiwillige 8 Spielminuten.
  Ohne verfügbare Wache wird alle 10 Spielminuten erneut alarmiert.
* Brandverlauf: Stärke wächst um 2 je Spielminute bis zum Löschangriff; Schaden wächst mit der Stärke. Löschleistung: HLF 3 + 1 je
  Einsatzkraft und Minute. Ohne Feuerwehr brennt ein Gebäude nach 150 Minuten aus (Schaden 90 %).
* Großbrand: große Gebäude (Fabrik, Lager, Frachthalle, Hof, Hotel, Hafenamt, Luftfracht, Werft) brennen bis zu 8 Stunden und verlieren
  je Minute anteilig weniger. **Nachbarschaftshilfe** nur, wenn die Wache einer anderen Stadt vor dem Ausbrennen ankommt – bei
  Wohnhäusern liegen die Städte (330–480 Felder, ≈ 3 Spielstunden) zu weit auseinander, bei Großbränden nicht. Die anfordernde Stadt
  erstattet 1500 € + 20 € je Einsatzminute an die helfende Stadt.
* Folgen: Gebäudezustand (BuildingCare) sinkt um 0,8 × Schaden; Reparaturauftrag an das Handwerk (S0) mit 350 € je Schadenspunkt,
  Dauer 1 + Schaden/15 Tage, bezahlt vom Eigentümer (Stadtgebäude: Stadtkasse, sonst Hausbesitzer H0); danach ist der Zustand wieder
  hergestellt. Während der Reparatur kein neuer Brand im selben Gebäude.
* Darstellung: HLF mit Blaulicht fährt zum Brand und zurück (in der Wache = in der Halle, unsichtbar); `FireFx` zeichnet flackernde
  Flammen und Rauch nach Brandstärke, beim Löschangriff einen Wasserbogen vom Fahrzeug; nach dem Löschen 30 Minuten Restrauch.
  Einträge im Ereignisprotokoll und auf der Karte (Brand, Ausrücken, Löschangriff, Reparaturauftrag).
* Laden während eines Einsatzes: Fahrzeuge stehen wieder in der Wache, der Brand wird neu alarmiert.
* Sichtprüfung: `--demo-fire` (Brand 25–45 Felder von der ersten Wache, Kamera dorthin), z. B.
  `--autotest --speed=2 --seed=21 --demo-fire --screenshot=user://f.png --shot-at=37`. Probe `tests/probe_fire.gd` (Fahrzeiten zwischen den Wachen, Brandstatistik).

**Etappe 5 im Detail**

* `scripts/economy/rescue_service.gd` (`sim.rescue`): Schwere Erkrankungen (PublicSafety, 25 % der Erkrankungen bzw. wenn die
  Arztpraxen ausgelastet sind) lösen in der Region einen Notruf aus. Alarm an die Rettungswache mit der kürzesten Ankunftszeit und
  freiem RTW; lebensbedrohliche Fälle (25 %) bekommen zusätzlich das NEF, wenn die Wache eines und einen Notarzt hat.
* Hilfsfrist (Notruf bis Eintreffen) wird je Einsatz und je Stadt erfasst, Ziel 15 Spielminuten; Übersicht `RescueService.summary(k)`
  mit mittlerer Hilfsfrist und Anteil eingehalten.
* Versorgung vor Ort 10 Minuten; sie verbraucht 1 Pack Sanitätsverbrauchsmaterial aus dem Stadtlager (fehlt es: +5 Minuten, Statistik).
* Transport in das nächste Krankenhaus mit freiem Bett, Übergabe 5 Minuten, Rückfahrt. Ohne freies Bett: Notversorgung in der
  Arztpraxis der Stadt (Meldung).
* **Kreiskrankenhaus** (`KH-01`, regional): einmal je Region in der einwohnerstärksten Stadt mit Bauplatz; Betten und Personal nach der
  Einwohnerzahl der ganzen Region (40 Betten je 1000 Einwohner, mindestens 6), Personal aus allen Städten (Pendler). Betriebsbereite
  Betten = min(Plätze, 4 je Pflegekraft) und nur mit mindestens einem Arzt (Bildung 3) – fehlt er, nimmt das Haus niemanden auf.
* Kosten: Behandlung wie bisher über PublicSafety (Stadtkasse → Dienstleister, Ressort Gesundheit), Betrieb über Municipal.
* Darstellung: RTW/NEF mit Blaulicht auf Anfahrt und Transport, ohne auf der Rückfahrt (gemeinsam mit der Feuerwehr über
  `EntityView._place_muni`).
* Laden während eines Einsatzes: der Einsatz wird abgeschlossen, die Fahrzeuge stehen in der Wache.
* Prüfanpassung: `test_region_flight` prüft die Landegebühr jetzt am Geldfluss Flugbetrieb → Stadt, weil die Stadtkasse im Testzeitraum
  zugleich ihre Wachen bezahlt.
* Messung (Probe `tests/probe_municipal.gd -- --days=30`, Seed 4242): Kreiskrankenhaus ab Tag 14 betriebsbereit (Ärzte mit Bildung 3
  sind selten; bis dahin Notversorgung in der Arztpraxis), danach Aufnahme im Krankenhaus; 4 Notfälle in 30 Tagen, mittlere Hilfsfrist
  11 Minuten, 50 % innerhalb von 15 Minuten.

**Etappe 6 im Detail**

* Bauhof (`BH-01`) gehört jetzt zur Startausstattung jeder Stadt (Mindestbesetzung 2, Streuwagen und Kipper); ältere Spielstände
  bekommen fehlende Typen der Startausstattung einmal nachgebaut (`Municipal.ensure_kit`).
* Schnee je Straßenabschnitt (16 × 16, wie RoadCare): wächst bei Schneefall um 0,5 je Spielminute (auf gestreuten Abschnitten ein Fünftel),
  taut über 2 °C ohne Schneefall. Ab Schneehöhe 30 gilt dort das Schnee-Tempo; geräumte Abschnitte fahren sich bei Schneefall/Glätte
  wie bei Regen (`Simulation._speed_factor` → `WinterService.drive_factor`).
* Räumplan je Stadt: Priorität 1 Rettungswege (Abschnitte an Feuerwache, Rettungswache, Krankenhaus, Rathaus), 2 Hauptachsen
  (≥ 20 Straßenfelder im Abschnitt), 3 übrige Straßen im Ortsgebiet; innerhalb der Stufe nach Entfernung. Verbindungsstraßen
  außerhalb der Orte räumt niemand. Der Streuwagen fährt sichtbar von Abschnitt zu Abschnitt (15 Minuten je Abschnitt), verbraucht
  1 t Streusalz aus dem Stadtlager (ohne Salz hält die Wirkung halb so lange) und kehrt erst zurück, wenn nichts mehr verschneit ist.
  Reihenfolge im `order_log`.
* Schlaglöcher: Abschnitte unter 35 % Zustand. Der Kipper flickt den schlechtesten Abschnitt der Stadt (60 Minuten, +25 Zustand,
  1 t Asphaltmischung aus dem Stadtlager, 400 € aus der Stadtkasse, Ressort Verkehr). Grundsanierung bleibt `RoadCare.order` des Bürgermeisters.
* Darstellung (`RoadStateView`, Bodenebene): Schneedecke auf ungeräumten Straßen, geräumte Straßen dunkel mit Salzkörnern,
  Schlaglöcher als dunkle Flecken; Streuwagen mit Rundumleuchte, Kipper zu den Flickstellen. Sichtprüfung `--demo-snow` (Kamera auf
  den Bauhof) bzw. `--demo-snow=wache` (Kamera auf die Feuerwache, deren Abschnitt zuerst geräumt wird).

**Etappe 7 im Detail (ÖPNV)**

* `scripts/economy/transit_service.gd` (`sim.transit`): ein Busbetriebshof (VB-01) betreibt eine Linie in seiner Stadt. Haltestellen aus
  den Daten: bis zu 3 Wohnschwerpunkte (Wohneinheiten je 8 × 8 Felder), 2 Arbeitsschwerpunkte (Geschäfte, Betriebe), Rathaus; Rundkurs
  ab dem Betriebshof (nächster Nachbar). Betrieb 6–22 Uhr, 2 Minuten Halt; Takt = gemessene Umlaufzeit.
* Fahrgäste: je Betriebsstunde 0,03 Fahrtwünsche je bewohnter Einheit im Umkreis 8 einer Haltestelle; Einsteigen bis 40 Plätze, die
  Hälfte steigt an jeder Haltestelle aus. Jeder Fahrgast zahlt 2 € von seinem eigenen Guthaben (R0 → Stadtkasse); ohne Guthaben fährt
  niemand umsonst (Statistik „nicht bezahlt“).
* Kennzahlen je Linie: Fahrgäste, Erlöse, Kostendeckung (Erlöse / Sachkosten + Bus + Löhne des Fahrpersonals), Anbindung (Anteil der
  Wohneinheiten im Einzugsbereich). Wirkung: bis zu +3 Punkte Zustimmung nach Anbindung.
* Darstellung: Bus fährt sichtbar, Haltestellen als gelbe H-Schilder (`RoadStateView`). Test `test_transit` (Abnahme E).

**Etappe 8 im Detail (Bildung)**

* `scripts/economy/education.gd` (`sim.education`): Erwachsene von 22–45 Jahren haben 0/1/2 Kinder (55/30/15 %), einmal bestimmt und
  am Bürger gespeichert; Kinder altern mit dem Kalender (360 Tage/Jahr). Kita 1–5, Schule 6–17 Jahre.
* Plätze aus Kitas (KI-01) und Schulen (SC-01) der Wohnstadt (60 bzw. 240 je 1000 Einwohner, mindestens 10/20). Unterrichtsqualität =
  Lehrkräfte / Bedarf; Lehrkräfte brauchen Bildungsstufe 2 (Stufe 3 ist selten und geht an die Kliniken).
* Lernstand je Kind: jeden Monat Schulquote × Qualität (ohne Schulplatz Heimunterricht 0,2). Mit 18 wird das Kind ein neuer Bürger der
  Stadt (wohnt bei den Eltern): Bildung 2 ab 90 % des Lernstands, 1 ab 50 %, sonst 0 – Schulen wirken so über Jahre auf den Arbeitsmarkt.
* Kitas fördern den Familienzuzug (+15 % × Betreuungsquote auf den Zuzugsfaktor des Bürgermeisters). Engpässe in der Übersicht.
  Test `test_education` (Abnahme F).

**Etappe 9 im Detail (Recycling)**

* `scripts/economy/recycling.gd` (`sim.recycling`): ein Recyclinghof (RC-01) sortiert die Wertstoffe seiner Stadt (Müll der Einwohner ×
  Recyclingquote + 15 % zusätzlich getrennter Abfall, der sonst auf die Deponie ginge), bis 1 t je Mitarbeiter und Tag.
* Ströme: Papier 35 %, Glas 20 %, Kunststoff 20 %, Metall 10 %, Bio 15 % → echte Waren im Warenbuch (Altpapier, Altglas,
  Kunststoffgranulat, Stahlschrott, Kompost; neue Artikel in `config/articles.json`).
* Wöchentlich fährt der Wertstoffwagen sichtbar zum Großlager: Stahlschrott geht in den Großlagerbestand (L0 zahlt den Ankaufspreis;
  Stahlwerke können ihn dort kaufen; kein Nachschub per Import), die übrigen Stoffe übernimmt ein Verwerter außerhalb (Ausfuhrpreis).
* Hinweis: Die Orte sind klein (≈ 40 Einwohner, ≈ 18 kg Wertstoffe am Tag); eine volle 100-kg-Einheit entsteht erst nach einigen Tagen.
  Private Recyclingfirmen sind noch nicht umgesetzt (Firmen können den Schrott im Großlager kaufen). Test `test_recycling` (Abnahme G).

**Etappe 10 im Detail (Regionalrat)**

* `scripts/core/regional_council.gd` (`sim.council`): Ratsgebäude nahe dem Großlager (Bild vorerst wie die Bank). Sitzung alle 30 Tage
  (ab Tag 15): die Bürgermeister reisen im Dienstwagen an; Beginn, wenn alle da sind (spätestens nach 3 Stunden), danach Rückfahrt.
* Anträge (je Stadt höchstens einer): verbindung (Straße zwischen zwei Orten, gebaut über RegionalProjects), kh_ausbau (+50 % Betten und
  Personal des Kreiskrankenhauses), drehleiter (DLK 23 für eine Wache), zweckverband (Kreiskrankenhaus in gemeinsamer Trägerschaft,
  Unterhalt nach Einwohneranteilen), kkw_anteile (unzulässig: bleibt 25/25/25/25).
* Abstimmung: 3 von 4 (bei n Städten aufgerundet 75 %), Eigentumsfragen einstimmig. Stimmverhalten nach Nutzen und Kostenanteil
  (höchstens die Hälfte der verfügbaren Mittel). Verhandlung: bis zu zwei Runden, in denen der Antragsteller 15 Prozentpunkte mehr trägt.
  Beschlüsse werden sofort finanziert und umgesetzt; Protokoll mit Stimmen und Anteilen.
* KI-Bürgermeister: Aktion `regionalrat_antrag`; Regel-Bürgermeister nach Lage. Test `test_regional_council` (Abnahme H).

**Etappe 11 im Detail (Entscheidungen und Leitstelle)**

* `scripts/core/service_planner.gd` (`sim.services`): Bedarfsanalyse je Stadt (Kinder ohne Schul-/Kitaplatz, Hilfsfrist, ausgebrannte
  Gebäude, fehlende Busanbindung ab 60 Einwohnern, Deponie ab 50 %, Einrichtungen 30 Tage ohne Personal). Maßnahmen: Neubau über Bauplatz
  der Stadtentwicklung, Ratsbeschluss, Ausschreibung, Baufirma und Bautrupp (Projektart „dienst“; bei der Abnahme entsteht die Einrichtung
  mit eigenem Bild, ein Busbetriebshof plant gleich seine Linie), Fahrzeugkauf, Schließung. Baukosten skaliert mit der Ortsgröße (12 % des Stadtpreises plus Anteil nach Einwohnern: Dorfschule statt Stadtschule).
* Alle 5 Tage entscheidet das Bauamt nach Regeln (höchstens eine Maßnahme je Stadt); KI-Bürgermeister zusätzlich über `kommunal_bauen`,
  `kommunal_fahrzeug`, `kommunal_schliessen`, `regionalrat_antrag`. Lagebericht `kommunale_dienste` mit Einrichtungen, Kennzahlen,
  Bedarf, Baukosten und Regionalrat.
* Leitstelle: neuer Bereich **„Öffentliche Dienste & Regionalpolitik“** (✚) – Region (Kreiskrankenhaus, Regionalrat mit letzten
  Beschlüssen und Stimmen) und je Stadt Einrichtungen (Personal, Ehrenamtliche, Fahrzeuge, Kartensprung), Kennzahlen aller Dienste,
  Bedarf mit nächstem Schritt, Neubauten im Bau und letzte Entscheidungen mit Begründung. Test `test_service_planner` (Abnahme I).

**Etappe 12: Leistung und Abnahme**

| Abnahme | Inhalt | Nachweis |
|---|---|---|
| A | 10 Feuerwachen sehen verschieden aus (6 Grundvarianten × 4 Stile) | `test_public_buildings` |
| B | Brand → Alarm → Löschen → Schaden → Reparatur; Nachbarschaftshilfe; Ausbrennen ohne Feuerwehr | `test_fire_service` |
| C | Notfall → Hilfsfrist → Versorgung → Krankenhausbett / Arztpraxis | `test_rescue_service` |
| D | Schnee → Räumung nach Priorität mit Streusalz; Schlaglöcher geflickt | `test_winter_service` |
| E | Buslinie, Fahrgäste zahlen von eigenen Konten, Takt, Kostendeckung | `test_transit` |
| F | Kinder, Plätze, Lehrkräfte, Lernstand, Abschluss als neuer Bürger | `test_education` |
| G | Recyclinghof, Sekundärrohstoffe als Ware, Schrott ins Großlager | `test_recycling` |
| H | Regionalrat: 3 von 4, Eigentum einstimmig, KKW fest, Verhandlung | `test_regional_council` |
| I | Bedarf → Neubau über Rat/Ausschreibung/Baufirma; KI-Aktionen; Leitstelle | `test_service_planner` |
| J | 60-Tage-Langlauf aller Dienste: Invarianten, Kassen, Leistung | `tests/probe_services.gd -- --days=60` |

Langlauf (Seed 4242, 60 Tage, Regelbetrieb): 17 Einrichtungen, 16 Fahrzeuge, 32 Beschäftigte; 10 Brände, alle gelöscht (8 Reparaturen,
38 400 €); 17 Notfälle, Hilfsfrist Ø 7,2 min, 76 % ≤ 15 min; Kreiskrankenhaus 13 Betten; zwei Regionalratssitzungen (Verbindungsstraßen
beschlossen und abgelehnt); Kitas und Grundschulen über Rat, Ausschreibung und Baufirma gebaut bzw. angespart. Geldkonservierung,
Bürgerkonten und Warenbilanz exakt 0. Rechenzeit: Dienst-Updates < 0,01 ms je Simulationsschritt, Bedarfsanalyse aller Städte
≈ 9 ms (alle 5 Tage), Ø ≈ 0,6 s Rechenzeit je Spieltag (ganze Simulation, headless). Der langsamste Einzelschritt (≈ 0,5 s) liegt an
Tageswechseln der übrigen Simulation; die einmalige Zählung der Straßenfelder für den Räumplan (95 ms) läuft jetzt im Aufbau der
Straßenpflege mit.

Nach den Langläufen nachgeschärft:
* Kreiskrankenhaus: Träger ist von Anfang an der Landkreis, Unterhalt nach Einwohneranteilen (vorher trug die Standortstadt alles und
  rutschte ins Minus). Der Zweckverband-Antrag bleibt für eine aufgehobene Teilung.
* Bürgermeister bauen nur mit Rücklage für 60 Tage laufender Dienstkosten (`Municipal.daily_cost`) und sparen für den dringendsten
  Bedarf, statt Geld für Nachrangiges auszugeben (Protokoll „spart für …“). Baukosten kleiner Orte: 8 % des Stadtpreises plus Anteil
  nach Einwohnern (Grundschule für ~45 Einwohner ≈ 145 000 €).

**Grenzen / offen**

* Private Recyclingfirmen gibt es nicht (Firmen können den Schrott im Großlager kaufen).
* Ausbau des Krankenhauses und die gemeinsame Drehleiter wirken sofort (ohne Baustelle); Neubauten laufen sichtbar über Baufirma und Bautrupp.
* Das Ratsgebäude nutzt vorerst das Bild der Bank.
* Kommunale Dienste nur in der Weltart Region.

## Teil 2: Ausbau auf den vollständigen Auftragstext (Eingang 10.11.2026)

Der vollständige Auftragstext kam am 10.11. erneut. Etappen 1–12 setzen je Dienst **einen** Gebäudetyp und zwei bis drei Fahrzeuge um
(FW-01, RW-01, KH-01, BH-01, VB-01, SC-01, KI-01, RC-01). Abgleich mit dem vollen Text – Lücken und Reihenfolge:

| Etappe | Inhalt | Abnahme |
|---|---|---|
| 13 Feuerwehr-Ausbau **(fertig 10.11.)** | FW-02 Feuerwache, FW-03 Hauptfeuerwache, FW-04 BF-Zentrale, FW-05 Flughafenfeuerwehr (übernimmt den Flughafenbrand), FW-06 Ausbildungszentrum (Lehrgänge heben die Qualifikation); Fahrzeuge KdoW, ELW 1, KLF, LF 10, TLF 3000, GW-L, RW, FLF; Einsatzarten (Wohnung, Küche, Fahrzeug, Industrie, Lagerhalle, Verkehrsunfall, technische Hilfe, Unwetter, Wasserschaden, Gefahrstoff, Flughafen) mit Alarm- und Ausrückeordnung (passendes Fahrzeug je Einsatzart); Funktionen im Personal (Maschinist, Gruppenführer, Zugführer, Wachleiter, Gerätewart) mit Arbeitszeit und Erschöpfung | A, B |
| 14 Rettung/Kliniken | RD-02 zentrale Rettungswache, KH-01 Stadtklinik je Stadt, KH-02/KH-03 als Ausbaustufen, KH-04 MVZ; KTW, ELW RD, ITW; Betten je Klinik, Verlegung bei Überlastung, medizinische Güter aus dem Großlager verbraucht | C |
| 15 Bauhof/Straßen | BH-02 bis BH-05; Fahrzeuge Pritsche, Transporter, Kehrmaschine, Asphaltfertiger, Walze, Bagger, Radlader, Mobilkran, Hubsteiger, Schneepflug, Salz-Lkw, Inspektionsfahrzeug; Reparatur mit Sperrung des Abschnitts und Material aus dem Lager, Tempo-Abschlag an Schlaglöchern, Straßenreinigung | D |
| 16 ÖPNV-Ausbau | ÖPNV-02/03 (Betriebshof, Busbahnhof), Haltestellen als sichtbare Bauten (ÖPNV-04/05), Umsteigepunkt am Bahnhof (06); mehrere Linien je Stadt, Linien zum Bahnhof/Flughafen/zur Nachbarstadt, Busgrößen (Klein-, Midi-, Standard-, Gelenk-, E-, Überlandbus), Fahrplan mit Verspätungen, Verstärker bei Nachfrage, Subvention statt Streichung | E |
| 17 Bildung-Ausbau | BILD-02 Kindergarten, BILD-04 weiterführende Schule, BILD-05 Berufsschule, BILD-06 Gymnasium, BILD-07 Hochschule, BILD-08 Bibliothek; Abschlüsse führen zu Berufen (Techniker, Ingenieur, Arzt, Lokführer, Verwaltung, Facharbeiter) | F |
| 18 Recyclingindustrie | REC-02 Sortierzentrum, REC-03…08 Werke (Papier, Glas, Metall, Kunststoff, Kompost, Baustoff) mit Verlusten, Energie und Kapazität; private KI-Firmen gründen Recyclingbetriebe (Grundstück, Bau, Maschinen, Personal, Einkauf, Verkauf) – berührt `scripts/ai`, nur mit Abstimmung | G |
| 19 Regionalverwaltung | REG-01/02/03 mit eigenem repräsentativem Bild in der Kartenmitte; Ankunftsszene mit Porträts und Dialogfenster | H |
| 20 Regionalpolitik | Anträge Energie, Bahn, Wasser, Abfall, Verkehr, Sicherheit als echte Bauprojekte (Bauauftrag, Grundstück, Baufirma, sichtbare Baustelle, Abnahme); Finanzierung gleich, nach Einwohnern, nach Nutzung, Mehranteil, Regionalkredit; Gegenangebot, Kompromiss, Vertagung; Bürgermeister-Persönlichkeit (8 Merkmale) gewichtet nach Lage; KI-Bürgermeister verhandeln mit eigenem Text | H |
| 21 Identität | individuelle Namen aus Stadtteil/Lage/Merkmal (Am Stadtpark, Industriehafen …), Fahrzeugkennungen je Wache, Fahrzeugwahl nach Aufgabe und Kapazität; Stadtstile vom Bürgermeister beeinflussbar | – |
| 22 Dashboard | alle Ereignisse anklickbar (Einsatzstelle, Baustelle mit Baufirma, Begründung jeder Stimme), Kennzahlen je Bereich laut Abschnitt 19 | – |
| 23 Speichern/Laden | Varianten, Kennungen, laufende Einsätze, Beschlüsse, Bauprojekte nach dem Laden identisch | J |
| 24 Leistung, Langlauf, Doku | | A–J |

Jeder neue Gebäudetyp bekommt ≥ 6 Grundvarianten × 4 Stile im Baukasten (`tools/vox/public.py`) **und** eine Funktion; keine Typen
ohne Aufgabe.

**Etappe 13 im Detail (Feuerwehr-Ausbau)** – Test `test_fire_stages`, Probe `tests/probe_fire13.gd`

* Typen: FW-01 heißt jetzt „Freiwillige Feuerwehr“; neu FW-02 Feuerwache (5×3), FW-03 Hauptfeuerwache mit Leitstelle (6×4), FW-04
  Berufsfeuerwehr-Zentrale mit Leitstelle und Werkstatt (7×5), FW-05 Flughafenfeuerwehr (3×2, in der vorhandenen Flughafenwache),
  FW-06 Feuerwehrausbildungszentrum (5×4, regional, Kosten nach Einwohneranteilen). Je Typ 6 Grundvarianten × 4 Stile
  (`tools/vox/public.py`: Hallenkämme, Winkel- und Hofanlagen, Glaskanzel, Funkmast, Übungsturm, Brandhaus, Wrack- und Containerplatz).
* Fahrzeuge (`tools/vox/vehicles.py`): KdoW (Pkw), ELW 1 (Hochdach, Antennenmast), KLF, LF 10 (Saugschlauch), TLF 3000 (Tank, Werfer),
  GW-L (Ladebordwand), RW (Kran, Lichtmast, Seilwinde), FLF (drei Achsen, Panoramakabine, Dach- und Frontwerfer). Jedes Fahrzeug hat
  Rollen (`Municipal.VEHICLES.roles`) und Löschleistung.
* Einsatzarten mit Alarm- und Ausrückeordnung (`FireService.KINDS`): Wohnungs-, Küchen-, Gebäude-, Industrie-, Lagerhallen-, Fahrzeug- und
  Flughafenbrand; Verkehrsunfall (alarmiert parallel den Rettungsdienst für einen verletzten Bürger), technische Hilfeleistung,
  Unwetterschaden (schadet der Straße, bis geräumt ist), Wasserschaden (schadet dem Gebäude → Reparatur), Gefahrstoffeinsatz. Pflichtrollen
  müssen frei sein, Ergänzungen fahren mit, wenn frei (Drehleiter beim hohen Wohnhaus: weniger Schaden; Tank: ×1,5 Löschleistung;
  Einsatzleitung: ×1,2). Technische Einsätze je Stadt und Tag, Wetter verstärkt (Sturm/Starkregen, Schnee/Nebel).
* Personal: drei Wachabteilungen im 24-Stunden-Dienst ab 6 Hauptamtlichen, sonst Tagdienst 7–17 Uhr (außerhalb wie Freiwillige
  alarmierbar, 8 Minuten Ausrückzeit); Leitstelle in der Stadt −1 Minute. Funktionen Wachleiter, Zugführer, Gruppenführer, Maschinist,
  Gerätewart, Disponent, Feuerwehrtechniker. Erschöpfung 0,4 je Einsatzminute, ab 80 nicht einsetzbar, −50 je Tag. Lehrgänge im
  Ausbildungszentrum (10 Tage, Plätze = Kapazität): ausgebildete Kräfte löschen mit 1,5 statt 1,0.
* Flughafenbrand: mit FW-05 rückt die Flughafenfeuerwehr mit FLF aus; Warenschaden und Versicherung rechnet weiter der Flughafen ab.
* Bauamt: Ausbau FW-01 → FW-02 → FW-03 → FW-04 ab 10/25/45 Einsätzen in 30 Tagen oder 1 500/4 000/10 000 Einwohnern; fehlt für eine
  Einsatzart, auf die gewartet werden musste, die Fahrzeugrolle in der ganzen Stadt, kauft es das günstigste passende Fahrzeug.
* Leitstelle: je Wache im Dienst/einsatzbereit/Lehrgang/erschöpft und Funktionen; laufende Einsätze mit Fahrzeugkennungen, anklickbar.
* 30-Tage-Probe (Seed 4242): 6 Brände (alle gelöscht), 13 technische Einsätze, 24 Lehrgänge, Invarianten exakt 0, Feuerwehr-Update 0,006 ms je Schritt.

