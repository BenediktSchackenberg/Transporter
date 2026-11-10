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
| 4–12 | offen |

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
