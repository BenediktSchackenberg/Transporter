# Auftrag 17: Mehrere Städte in einer gemeinsamen Wirtschaftsregion

Eingegangen am 07.11.2026 (Benedikt): „im Anschluss ohne Rückfragen selbständig vollständig machen“. Geprüfte Ausgangsbasis laut
Auftrag: `unternehmer` @ `d2bca42`; tatsächliche Arbeitsbasis: `unternehmer` @ `14a6912` (enthält zusätzlich Bergwerk-Geschichte,
Gebäudestufen und Küstenort Etappe E). Arbeit auf Branch `region` (Worktree `PTR_e`).

## Wortlaut (gekürzt auf die verbindlichen Anforderungen, Abschnittsnummern wie im Auftrag)

1. **Ziel:** Region mit mehreren eigenständigen Städten auf einer Karte. Neue Partie: Städte = Startspieler (2–4), je Stadt genau ein
   ursprünglicher Unternehmer, eigener Bürgermeister, kleine Grundversorgung. Zufällige geeignete Standorte, einfaches zusammenhängendes
   Straßennetz, je Stadt ein kleiner Flughafen mit gemeinsamem Flugnetz. Später neue Unternehmer, Expansion, Umzüge. Iso-Voxel-Optik,
   Windows, Engine und Zuschauerprinzip bleiben; Wirtschaft aus realen Aufträgen, Beständen, Arbeitsverhältnissen, Kosten, Zahlungen.
2. **Bestand prüfen**, parallel laufende Arbeit erhalten, keine destruktiven Git-Befehle, eigener Branch.
3. **Identitäten:** Stadt (`city_id`, Name, Gebiet, Kern), Bürgermeisteramt je Stadt (Politik, Gedächtnis, Amtszeit), Company (Heimatstadt,
   Konto, Rechtsform, Betriebe), Business (Standort in einer Stadt), Bewohner (Wohnort, Arbeitgeber, Reise-/Umzugsstatus), Infrastruktur
   (Lage, Eigentümer, Betreiber, Zuständigkeit). Bürgermeister belegen keine Unternehmerplätze. Startzustand ohne versteckte Zusatzfirmen.
4. **Gemeinsame Welt, getrennte Verwaltungen:** eine Simulation, eine Karte, ein Verkehrsmodell. Gemeinsam: Uhr, Seed, Koordinaten,
   Gebäude-IDs, Geldbuch, Warenbuch, Firmenregister, Märkte, Banken, Zentralbank. Je Stadt: Bürgermeister, Haushalt, Rathaus, Beschaffung,
   Bauhof/Zentrallager, Planung/Genehmigung, öffentliche Projekte, Kennzahlen, Wahlen, Flughafenbetrieb. Verwaltungsgebiet ≠ Eigentum.
   Unzugeordnete Flächen brauchen ausdrückliche Zuständigkeit.
5. **Start:** erst Landschaft, dann geeignete Stadtstandorte (Baufläche, Küste, Flugplatz, Mindestabstand, Erweiterungsfläche, nicht in
   Berg/Wasser/übereinander). Jede Startstadt an der Küste mit kleinem Hafen und Fantasienamen; Namen/Standorte gespeichert, Seed
   reproduzierbar. Alle Städte über Land ohne spätere Brücken verbindbar; kontrollierte Neugenerierung mit Fehlermeldung. Berge
   unbebaut. Je Stadt genau ein Unternehmer-Startgrundstück.
6. **≤ 40 fertige Startgebäude je Stadt** (Maximum, inkl. Grundversorgung und Flughafengebäude, eindeutig einer Stadt zugeordnet).
   Je Stadt genau ein Rathaus, ein Bauhof/Zentrallager, ein kleiner Hafen, ein kleiner Flughafen, ein Unternehmer, passender Wohnraum.
   Bescheidene Bauten. ≥ 60 % der bebaubaren Regionsfläche unerschlossen. Danach Wachstum nur durch Nachfrage, Finanzierung,
   Genehmigung, Material, Bau.
7. **Verbindungsstraßen:** zusammenhängendes, befahrbares Grundnetz aus Schotterstraßen als definierte Startinfrastruktur; je Abschnitt
   Eigentum/Wartung; gemeinsame Projekte als ein regionales Projekt mit Kostenanteilen (keine Vierfachbestellung/-zahlung);
   Verkehrsbelastung/Zustand wirken auf Fahrzeit; Energie/Versorgung nicht ungeprüft vervielfachen.
8. **Getrennte Stadtkassen** (z. B. `PUB:<city_id>`): Bürgermeister verfügt nur über eigene Mittel; alle `P0`-/`Parcels.CITY`-Zugriffe
   fachlich zuordnen (Standort, Grundstück, Auftraggeber, Wohnort). Steuern, Gebühren, Abgaben, Gehälter, Sozialleistungen, Mieten,
   Beschaffung je Zuständigkeit, nie doppelt. Startbudgets konfiguriert und bilanziert (kein verstecktes `Economy.SEED`). Wahlen je Stadt.
9. **Überregionaler Handel/Expansion:** Firma mit Heimatstadt handelt/gründet/baut überall; Warenbuch einzige Bestandswahrheit;
   Binnenhandel ist nicht `X0`; Lieferantenwahl nach Gesamtpreis inkl. Fahrt, Kapazität, Lieferzeit; echte Importe/Exporte getrennt.
10. **Flughäfen:** je Stadt kleiner Flugplatz; regionale Flugnetzverwaltung (Flughäfen, Strecken, Kapazität, Kosten); Flug als echter
    Vorgang (Buchung → Abfertigung → Beladung → Start → Reise → Landung → Entladung → Weitertransport); Fracht erst nach Landung
    verfügbar; Passagiere mit Identität/Gruppe; sichtbare Flugzeuge zwischen den Flughäfen; Betreiber mit Einnahmen/Kosten; Ausbau nur
    über Budget/Bauauftrag/Material.
11. **Bewohner:** eindeutige Wohnung/Wohnstadt, Arbeitsplatz auch anderswo, Pendelzeit/-kosten; Umzug als Vorgang ohne neue Menschen/
    neues Vermögen; Auslandszuzug getrennt.
12. **Zusätzliche Gründer:** neue Companies aus erkennbarer Chance (Nachfrage, Kapazitätslücke, Bauaufträge), Standort/Personal/
    Genehmigung/Finanzierung geprüft, Abklingzeit; höchstens 3 aktive Unternehmer mit Heimat je Stadt (konfigurierbar); Startkapital aus
    Bewohnervermögen, Investorenpool oder Bankkredit (kein Geld aus dem Nichts); eigene Identität/Controller (Regel-KI); append-only
    Firmenregister, keine ID-Wiederverwendung; Insolvenz betrifft nur die Firma.
13. **KI:** Bürgermeister je Stadt mit eigenem Kontext, Gedächtnis, Anfragebudget und Profil; Unternehmer eigene Profile, Gründer Regeln;
    Beobachtung um eigene Stadt, Nachbarn, regionale Angebote, Verbindungen (begrenzt); Berechtigungsprüfung bei fremden Standorten;
    gemeinsamer Modellserver mit Warteschlange/Zeitlimit/Budget; veraltete Antworten verwerfen (Partie, Akteur, Generation, Amtszeit);
    knappe sachliche Begründungen; Regel-KI beherrscht die Abläufe ohne API.
14. **Oberfläche:** Regionsübersicht (Städte, Grenzen, Bürgermeister, Verbindungen), Stadtauswahl springt und filtert; Stadtansicht mit
    Bevölkerung, Wohnraum, Beschäftigung, Versorgung, Haushalt, Zufriedenheit, Unternehmen, Projekten; Flughafen/Hafen/Bauhof mit realen
    Bewegungen; Unternehmeransicht mit Heimatstadt und Betrieben je Standort; Protokoll filterbar; getrennte Auswertungen (Unternehmen,
    Städte, Region), Score-Gewichte offen.
15. **Spielstände:** Version erhöhen, alle neuen Daten speichern; Welt beim Laden nicht neu würfeln (versionierte Generatorparameter bzw.
    Kartendaten); alte Einzelstadt-Stände als Region mit einer Stadt; Kompatibilitätszugriff `sim.mayor` nur vorübergehend, im
    Mehrstädtemodus keine stille Umleitung an Stadt 0. Laden während Flug/Lieferung/Umzug/Gemeinschaftsprojekt ohne Verdopplung.
16. **Etappen:** 1 Bestand/Architektur → 2 Stadtidentitäten/Zuständigkeiten/Konto-Auflösung/Migration → 3 Generierung 2–4 Orte, Startnetz
    → 4 Bürgermeister/Haushalte/Bauhöfe/Genehmigungen/Projekte je Stadt, Gemeinschaftsprojekte → 5 Binnenhandel, dann Flughäfen und
    Flugverkehr → 6 Expansion, Gründer, Pendeln, Umzüge → 7 Oberfläche, Auswertungen, Grafikprüfung, Balance. Nach jeder Etappe
    lauffähig mit Regressionen; Fortschritt hier festhalten.
17. **20 Abnahmeszenarien** (siehe Tabelle unten).
18. **Lieferung:** Code, Konfiguration, Grafiken soweit nötig, Migration, Abnahmeprüfungen; nur tatsächlich gelaufene Tests berichten.

## Bestandsaufnahme (07.11.2026)

- Basis `14a6912`; parallele Sitzung (Flughafen, Auftrag 16) arbeitet im Hauptordner auf `unternehmer` mit uncommitteten Änderungen an
  `airport.gd`/`city_depot.gd` (Luftfracht). Diese Dateien nur über Diff berühren.
- Einzelstadt-Annahmen (Zählung `grep`): `sim.mayor` 56, `sim.city_depot` 40, `sim.harbor` 42, `sim.airport` 4, `"P0"` 69,
  `accounts.P0` 15, `Parcels.CITY` 18, `sim.permits` 32, `sim.town_hall` 14, `companies[` 42, `sim.company(` 406, `town_name` 25.
- `CityData` hat genau einen `town_name`, einen `airport`-Datensatz und `start_depots`; `CoastGenerator._town()` baut einen Ort mit vier
  Startgrundstücken, `validate()` verlangt genau ein Rathaus/einen Bauhof und vier Startgrundstücke.
- Firmen-ID = Arrayindex (`Simulation.company(id)` → `companies[id]`); Insolvenz-`refound()` ersetzt am Platz.
- Fluss mündet bisher 0,22·n neben dem Ort ins Meer – bei mehreren Küstenorten würde er Städte trennen.

## Architekturentscheidung

- **Eine Simulation, eine Karte.** Neue Weltart `region` (Startmenü), `CityData` behält die gesamte Geometrie und erhält `towns`
  (Liste der Stadtdatensätze: id, name, Zentrum, Ortsrechteck, Rathaus, Bauhof, Hafenlager, Flughafen-Geometrie) und `town_of(cell)`
  (Verwaltungsgebiet: nächstes Ortszentrum; damit gibt es keine unzugeordnete Fläche). Gebäude tragen `town`.
- **Stadt-Register `Towns` (`sim.towns`)** mit je Stadt einer eigenen Instanz von `Mayor`, `CityDepot`, `Harbor`, `Airport`. Stadt 0
  behält Konto `P0` und Grundstückseigentümer `Parcels.CITY` (= Migration alter Spielstände ohne Umbuchung); Stadt k > 0 hat Konto
  `P<k>` und Eigentümer `stadt<k>`. `sim.mayor`, `sim.city_depot`, `sim.harbor`, `sim.airport` bleiben als Verweis auf Stadt 0 für die
  Einzelstadt; im Regionsmodus wählen alle fachlichen Aufrufer die zuständige Stadt (`sim.towns.of_building/of_cell/of_parcel`).
- **Startbudgets** weiterer Städte: Landeszuweisung zum Start (`X0 → P<k>`, im Geldbuch als Zuweisung verbucht), Betrag konfiguriert.
- **Firmenregister** bleibt Array mit `id = Index`, aber streng append-only (nie entfernen, geschlossene Firmen bleiben archiviert);
  neue Gründer bekommen die nächste ID; Startspielerprofile bleiben an IDs 0..n-1.
- **Spielstände:** `SAVE_VERSION` erhöhen; alte Stände ohne `towns` laden als Region mit einer Stadt.

## Etappen und Stand

| Etappe | Inhalt | Stand |
|---|---|---|
| 1 | Bestandsaufnahme, Architektur | fertig (07.11.2026, dieses Dokument) |
| 2 | Stadtidentitäten, Konten/Eigentümer je Stadt, Zuständigkeitsauflösung, Migration | fertig (07.11.2026): `Towns` (`sim.towns`, `scripts/core/towns.gd`): je Ort Konto `P<k>` (Ort 0 `P0`), Grundeigentümer `stadt<k>` (Ort 0 `stadt`), Projekt-/Plan-IDs `T<k>P<n>`; Zuständigkeit `of_cell/of_building/of_parcel` (Verwaltungsgebiet = nächstes Ortszentrum, keine unzugeordnete Fläche); `Company.home_town`; Startbudget weiterer Orte 200 000 EUR als Landeszuweisung X0 → P<k> (verbucht). Migration: Spielstände ohne `region` laden als eine Stadt (Test). Spielstand: Abschnitt `region` mit Ortszahl, Generatorparametern, Städten (Ladeprüfung meldet Abweichung) und Zuständen der weiteren Verwaltungen |
| 3 | Regionsgenerator 2–4 Orte, je ein Unternehmer, Startstraßennetz | fertig (07.11.2026): `RegionGenerator` (Weltart `region`, Standard im Startmenü und Autotest): Orte gleichmäßig entlang der Küste, Berge mit Abstand, Fluss mündet jenseits der Orte, je Ort ≤ 40 Gebäude mit Rathaus, Bauhof, Hafen, Flughafen, genau einem Startgrundstück; ein regionales Kraftwerk (Ort 0); Verbindungsstraßen per Wegsuche über Land (`CityData.region_roads`, Eigentum Region, Wartung nach Verwaltungsgebiet); Selbstprüfung mit bis zu 8 Versuchen (Seeds 7, 21, 99, 123, 4242: erster Versuch). Behoben dabei: Kaikante trennte die Hauptstraße, Flussquelle in Bergmulde |
| 4 | Verwaltung je Stadt (Bürgermeister, Haushalt, Bauhof, Genehmigung, Projekte, Wahlen), Gemeinschaftsprojekte | fertig (07.11.2026): je Ort eigene Instanz von `Mayor`, `CityDepot`, `Harbor`, `Airport` und eigener `MayorAgent` (Kontext, Budget, Protokoll `buergermeister_<k>`, zeitversetzt, Antworten nach Amtswechsel verworfen, eine laufende Anfrage je Modellserver, Gesamtbudget `max_requests_total`); Wahlen je Ort; Kennzahlen nur eigenes Gebiet; Zuständigkeitsprüfung `Mayor.foreign_target`; öffentliche Projekte aus Kasse und Lager der beauftragenden Stadt; Zufahrten, Brücken, Straßenwartung, Verkehrsmaßnahmen, Förderabgabe, Grundsteuer, Pacht, Gebühren, Ladenmieten nach Lage; Steuern/Verwaltung/Bußgelder der Firmen an die Heimatstadt (`Ledger.public_acct`); öffentliche Löhne, Lohnsteuer, Grundsicherung, Konsumsteuer, Weiterbildung je Wohnstadt; Zuzug und Wohnungsmarkt je Stadt; Betriebsgenehmigung durch das Bauamt der Stadt der Lage. Gemeinschaftsprojekte `RegionalProjects` (`sim.regional`): Vorschlag mit Anteilen, Beschluss je Stadt mit Frist, eine Ausschreibung, Zahlung je Anteil bei Abnahme. Bewusst regional: ein Stromnetz mit Kraftwerk in Ort 0 (Tarif an P0, Ausbau bezahlt die anordnende Stadt), ein privater Großhandel (Bauhof T0), Rathauspersonal-Modell `TownHall`, Müllabfuhr, Grundsteuersatz |
| 5 | Binnenhandel zwischen Städten, Flughäfen und Flugverkehr | fertig (07.11.2026): Lieferanten aller Städte konkurrieren in `Production.order` nach Preis + Fracht; Import/Ausfuhr nur über den Hafen der eigenen Stadt (`import_point(loc)`); Gründung in einer Zielstadt (`found_business stadt=`). `AirNetwork` (`sim.air`): Strecken zwischen Nachbarstädten, je Strecke ein Flugzeug, Zustände Abfertigung → Rollen → Flug → Landung → Entladen, Abflug gebündelt (ab 3 Reisenden, Fracht oder 100 min Wartezeit, Umsetzflüge), Luftfracht (Reservierung am Abgangsort, Zubringerzeit, 20 LE je Flug, Ware erst nach der Entladung im Frachtterminal der Zielstadt), Reisende mit Grund und Rückflug, Betreiber Regionalflug (Konto A0, Startkapital 60 000 EUR von außen, Ticket 55 EUR, Kerosin an X0, Abfertigung/Landegebühr an die Städte); AirView zeichnet die echten Flüge; Aktion `book_air_cargo` |
| 6 | Expansion, zusätzliche Gründer, Pendeln, Umzüge | fertig (07.11.2026): Filialen in anderen Städten (Heimatstadt bleibt). `Founders` (`sim.founders`): Chancen je Stadt (fehlende Bäckerei/Restaurant, fehlende Vorstufe, Bauvorhaben ohne Bautrupp) über drei Prüfungen; Quote 3 aktive Unternehmen je Heimatstadt (`max_per_town`), Abklingzeit 30 Tage, Standort, Personal, Einlage 60 000 EUR aus dem Kapitalgeberpool I0; neue Company am Ende des Registers (append-only, keine ID-Wiederverwendung) mit Figur, Gedächtnis und eigenem Regel-Controller (auch nach dem Laden); Ablehnungen mit Grund. `Commuting` (`sim.commute`): Personal mit Wohnung in A und Arbeit in B zahlt Fahrtkosten, Motivation sinkt, nach 2 Monaten Umzug in eine bezahlbare freie Wohnung der Arbeitsstadt |
| 7 | Oberfläche, Auswertungen, Grafikprüfung, Balance | fertig (07.11.2026): Taste O wählt Stadt (Kamera springt, Protokoll filtert), Stadt → Ort (Stadtfenster je Stadt), Stadt → Region (Städtevergleich mit offen gelegten Gewichten, Straßen, Gemeinschaftsprojekte, Flugnetz, Gründer, Pendeln, Binnen-/Außenhandel), Firmenansicht mit Heimatstadt und Betrieben je Stadt, Karten und Figuren für spätere Gründer. Grafische Probeläufe (Fenster-Build, Seed 21): Städte, Verbindungsstraße mit Verkehr, Flughafen mit Flugzeug, Bautrupps. Probelauf `tests/probe_region.gd` (4 Städte, 60 Tage, Regel-KI): Identität stets erfüllt, Schritt Ø 1,3–1,7 ms, ein Gründer (Bäckerei), 5 Geschäfte zwischen Städten, 69 Flüge mit 88 Reisenden, Flugbetreiber −6 300 EUR in 60 Tagen (Anlaufverlust), 16 Pendler |

## Abnahmeszenarien

| Nr. | Szenario | Stand |
|---|---|---|
| 1 | 2/3/4 Startspieler → so viele gültige Städte, eindeutige Namen, je ein Unternehmer | erfüllt (`test_region_world`) |
| 2 | ≤ 40 Startgebäude je Stadt; Rathaus, Bauhof, Hafen, Flugplatz erreichbar; keine versteckten Startfirmen | erfüllt (`test_region_world`) |
| 3 | Verschiedene Seeds gültig, gleicher Seed reproduziert; Berge unbebaut | erfüllt (`test_region_world`) |
| 4 | Städte über Straßen verbunden, LKW-Lieferung zwischen Stadtzentren | erfüllt (`test_region_roads`; `test_region_trade`: LKW fährt die Mehllieferung von Stadt 0 nach Stadt 1) |
| 5 | Zahlung aus A ändert B nicht; fremde Verwaltungsaktionen abgelehnt | erfüllt (`test_region_administration`) |
| 6 | Firma aus A kauft Land in B, Antrag in B, Entscheidung von B, Betrieb läuft | erfüllt (`test_region_trade`: Betriebsgenehmigung des Bauamts von B, Kaufpreis an B) |
| 7 | Kommunaler Materialauftrag von der richtigen Stadt bezahlt und ins richtige Lager; Personal einmal entlohnt | erfüllt (`test_region_administration`; `test_region_residents`: öffentliche Löhne genau einmal aus der Kasse der Wohnstadt) |
| 8 | Gemeinsames Projekt einmal vergeben, anteilig finanziert, erst nach Abnahme nutzbar; Folgen bei Ablehnung | erfüllt (`test_region_joint_project`) |
| 9 | Produkt zwischen zwei Städten verkauft/transportiert, X0 unverändert | erfüllt (`test_region_trade`) |
| 10 | Echter Flug A→B, Fracht erst nach Ankunft verfügbar, Kapazität und Kosten | erfüllt (`test_region_flight`) |
| 11 | Flug/Umzug erzeugt keine Personen, Bevölkerung und Vermögen erhalten | erfüllt (`test_region_flight`, `test_region_commute`, `test_region_residents`) |
| 12 | Nachfrage + Finanzierung → neue Company mit eigenem Controller | erfüllt (`test_region_founders`; Controller und Karte im Autotest ohne Fehler) |
| 13 | Gründung scheitert verständlich (Kapital, Standort, Quote); Heimatstadt vs. Filiale | erfüllt (`test_region_founders`: Quote, Kapital, Filiale; Standortgrund im Code, nicht eigens getestet) |
| 14 | Company-ID > Startslots funktioniert überall (Verträge, Personal, Kredite, UI, Speichern) | erfüllt für Personal, Kredit, Betriebe, Speichern (`test_region_founders`) sowie Figur, Karte und Controller (Autotest); Transportverträge einer Gründerfirma nicht eigens getestet |
| 15 | Insolvenz reguliert Forderungen; keine ID-Wiederverwendung | erfüllt (`test_region_founders`: Neugründung nur am eigenen Platz, nächster Gründer neue ID ohne Schulden; Insolvenzregeln unverändert, `test_insolvency`) |
| 16 | Wahl in A ändert B nicht; verspätete Antwort des alten Amtsinhabers verworfen | erfüllt (`test_region_mayors_and_save`) |
| 17 | Speichern/Laden neuer Regionen und alter Einzelstadt-Stände ohne Verlust | erfüllt (`test_region_mayors_and_save`; Laden im Flug `test_region_flight`; Gemeinschaftsprojekt `test_region_joint_project`; Gründer `test_region_founders`) |
| 18 | Bilanzen/Warenbilanz/Geldprüfungen konsistent, keine unbeabsichtigten Mittel | erfüllt (`identity_ok` in allen Regionstests und im 60-Tage-Lauf; Startbudgets, Flugbetreiber und Gründereinlagen mit Gegenkonto X0/I0) |
| 19 | Langer Probelauf mit 4 Städten und Gründern; API-Ausfall blockiert nichts | erfüllt (`tests/probe_region.gd`, 60 Tage; `test_region_model_queue`); Live-API nicht getestet |
| 20 | Grafische Probeläufe der Region | erfüllt (Bildschirmfotos Fenster-Build, Seed 21); Schritt Ø 1,3–1,7 ms bei 4 Städten |


## Spielstand und Migration

- `SAVE_VERSION` bleibt 2: Der Abschnitt `region` (Ortszahl, Generatorparameter, Städte, Zustände der weiteren Verwaltungen) sowie
  `regional`, `air`, `founders` und `commute` sind optional; alte Stände ohne sie laden als eine Stadt (`test_region_mayors_and_save`).
- Die Welt wird beim Laden aus Seed und Parametern neu erzeugt (wie bisher). Die Ladeprüfung vergleicht Namen und Zentren der Städte mit
  dem Spielstand und meldet eine Abweichung (geänderter Generator) im Protokoll und in `Simulation.load_warnings`.
- Neue Konten: `P1`–`P3` (Stadtkassen), `A0` (Regionalflug). Startbudgets und Startkapital kommen per Überweisung von `X0` (im Geldbuch).

## Offene Punkte und Grenzen

- Bürger (Citizens) haben keinen ortsgebundenen Arbeitsplatz; Pendeln und Umzug gelten für das Firmenpersonal.
- Rathauspersonal (`TownHall`) und Müllabfuhr sind ein regionales Modell; das Stromnetz ist regional mit Kraftwerk in Ort 0.
- Die Regel-KI bucht keine Luftfracht von selbst (Modelle können `book_air_cargo` nutzen). Gemeinschaftsprojekte schlagen nur Modell-Bürgermeister
  vor; der Regel-Bürgermeister stimmt zu oder lehnt ab.
- Die Bürgermeisterkarte links zeigt Ort 0; die anderen Bürgermeister stehen im Stadtfenster und in der Regionsübersicht. Die Zoomgrenze
  erlaubt keine Gesamtansicht aller Städte (Minikarte zeigt sie).
- Live-API (Claude/Ollama) mit mehreren Bürgermeistern nicht getestet.
