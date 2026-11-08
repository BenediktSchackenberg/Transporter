# Auftrag 17: Mehrere Städte in einer gemeinsamen Wirtschaftsregion

Eingegangen am 07.11.2026 (Benedikt): „im Anschluss ohne Rückfragen selbständig vollständig machen“. Geprüfte Ausgangsbasis laut
Auftrag: `unternehmer` @ `d2bca42`; tatsächliche Arbeitsbasis: `unternehmer` @ `14a6912` (enthält zusätzlich Bergwerk-Geschichte,
Gebäudestufen und Küstenort Etappe E). Arbeit auf Branch `region` (Worktree `PTR_e`).

## Eckregionen für neue Partien (Generator 3)

Die Minikarte ist geografisch nordausgerichtet: `x` wächst nach Osten (rechts), `y` nach Süden (unten). Die isometrische Spielansicht
ändert diese Zuordnung nicht. Vier Startspieler erhalten je einen Ort in Nordwest, Nordost, Südwest und Südost. Bei zwei Spielern werden
seedabhängig NW/SO oder NO/SW gewählt; bei drei bleibt seedabhängig eine Ecke frei. Innerhalb jeder Ecke variieren die Küstenlage und
Nord-/Südposition mit dem Seed. Die gemeinsame Landmasse liegt zwischen einer West- und einer Ostküste. Die Orte behalten Hafen,
Flughafen, Rathaus, Bauhof und je ein Startgrundstück; einfache Straßen verbinden sie über Land. Der Start enthält keine Autobahn.

`CornerRegionGenerator` schreibt `gen_params.generator = 3`. `Simulation.from_dict` verwendet für alte Regionsspielstände mit
Generatorversion 2 weiterhin `RegionGenerator`. Damit werden die alten Orte beim Laden nicht an die neuen Eckpositionen verschoben.
Die bisherige `region`-Dokumentation beschreibt im Folgenden auch den historischen Generator 2.

## Tourismus und Freizeitbetriebe (Ausbaustand)

Unternehmer können in Küstenstädten eine Strandpension auf einem erschlossenen Grundstück gründen. Wie andere Betriebe wird sie bei
normaler Spielkonfiguration von einem Bautrupp mit Bauauftrag errichtet, benötigt zugeordnetes Personal und trägt Ausstattung,
Abschreibung, Pacht und Stromkosten in der Firmenbilanz. Drei ausbaubare Gebäudestufen (10/32/80 Zimmer) besitzen eigene
Voxelmodelle. Der Ausbau wird erst nach fertigem Bauauftrag wirksam. Die KI kann `found_business branche=hotel`,
`assign_staff`, `set_hotel_price` und `upgrade_business` benutzen; die Beobachtung enthält belegte und morgen gebuchte Zimmer.

`Tourism` führt Reisegruppen mit begrenztem Budget als eigene Gegenkonten. Externe Gäste finanzieren sich über `X0`, inländische
Gäste über das Guthaben eines Bewohners (`R0`). Ankunft benötigt Flugplätze beziehungsweise eine befahrbare Straßenroute;
Zimmer und Flugplätze sind für den Zeitraum reserviert. Übernachtungen, Ortstaxe und optionales Frühstück werden tatsächlich
bezahlt, Frühstück verbraucht angeliefertes Brot und Fassgetränke. Nicht genutztes Geld fließt bei Stornierung/Abreise an die
Herkunft zurück. Die Gruppen werden auf der Karte am Flughafen, entlang der Straßenroute, im Hotel und tagsüber am Strand
gezeichnet. Ankünfte, Übernachtungen, Ausgaben und aktive Gäste stehen im Stadt- und Regionsfenster.

Hafenkneipe, Strandbar und Diskothek sind eigene gründbare Betriebe mit Voxelmodellen, Personal, Strom und Getränkelieferungen.
Touristen und Einheimische besuchen sie, bezahlen Eintritt/Getränk und verbrauchen vorhandene Ware. Die KI kann
`set_venue_price` ausführen; Besucher und Bestand sind in der Betriebsbeobachtung sichtbar. Touristen erscheinen zur
Öffnungszeit am besuchten Betrieb. `test_tourism_hotel` und `test_tourism_venues` prüfen Buchungen, Zahlungen,
Warenverbrauch, Ansichten und Spielstand.

Noch ausstehend aus dem ergänzenden Auftrag: öffentliches Strand-/Promenadenprojekt mit Bau und Material, vertiefte
Besucherzufriedenheit sowie Verkehrszählung und genehmigte Autobahnprojekte mit Fahrspuren, Anschlussstellen und Kreuzungen.

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

## Zusammenführung 08.11.2026

Alle Branches sind in `region` zusammengeführt; `unternehmer` und `main` zeigen auf denselben Stand. Aus `codex/fix-ai-finance-refueling`
(25.10.) wurden die Robustheits-Fixes übernommen: Sondertilgung nur für eigene Kredite mit positiven, endlichen Beträgen und Einzug
fälliger Zinsen; Einlagen nur mit gültiger Bank/Anlageart; Auszahlung prüft Kapital plus Zinsen; Tankregel/Bestellung prüfen Mengen,
Station und Lieferart; Tankwagen und Abholungen einer früheren Firmengeneration verfallen; KI-Antworten nach Partieende oder an eine
neu gegründete Firma werden ignoriert; Partiedauer zählt volle Echtzeit; JSON-Fehler der Preis-/Nachrichtendienste ohne Parserfehler.
**Nicht übernommen:** das Tankmodell je Fahrzeug (`VehicleFuel`). Es ersetzt den Betriebsvorrat mit Notbetankung/Tankhof, den
Annahmeprüfung, Regel-KI und ActionAssist voraussetzen; ein Wechsel wäre ein eigener Auftrag mit neuer Balance. Test: `test_merged_codex_fixes`.

## Wachstumsbremsen behoben (08.11.2026)

Diagnose mit `tests/probe_town_growth.gd` (Seed 21, 60 Tage): Morgenholm und Kieselstrand bauten kein einziges Wohnhaus.
- Der Regel-Bürgermeister legte alle 2 Tage dieselbe Gewerbe-Umwidmung vor; der Rat lehnte ab, und die abgelehnten Pläne zählten zur
  Obergrenze (8 bzw. 12 Pläne) - danach war kein Wohnquartier mehr möglich. Jetzt zählen nur nicht abgelehnte Pläne, und eine
  abgelehnte Umwidmung derselben Zone ruht 30 Tage.
- Der Bauträger suchte nur in der Zone Wohnen; Städte mit erschlossenem Mischgebiet bekamen nichts. Jetzt Mischgebiet als Ausweichzone.
- Stadtprojekte warteten wochenlang auf Material: Schüttgut (750 t Schotter) ging per Luftfracht (8 Einheiten je Flug), jedes Projekt
  bestellte nur für sich, und Ausschuss (2 %) löste für Restmengen einen ganzen Importzyklus aus. Jetzt Luftfracht nur bis zwei
  Flugladungen, Bestellung über den Bedarf aller offenen Projekte plus 3 % Reserve, offene Vorschläge werden aufgestockt.
Ergebnis: alle vier Städte bauen Wohnhäuser; Morgenholm schließt bis Tag 60 drei Stadtprojekte ab (vorher keines). Test `test_region_town_growth`.

## Firmenschließungen und Stadtkassen (08.11.2026)

Diagnose `tests/probe_closures.gd` (Seed 21, 120 Tage):
- Drei Gründerfirmen gingen an Reparaturkosten von 18–38 T EUR pleite: Abgeschleppte Fahrzeuge fuhren im Modell selbst zur Werkstatt,
  verschlissen weiter und blieben erneut liegen (Schleife mit je 400 EUR Abschleppgebühr). Behoben: Werkstattfahrt ohne Verschleiß,
  Panne und Treibstoff. Danach schließt im selben Lauf nur noch eine Firma (Bäckerei nicht tragfähig).
- Die Bergbau-Gründerin fand nie einen Schritt: Eigentümerprüfungen nutzten `Parcels.CITY` (nur Ort 0). Jetzt `Towns.is_public`.
- Stadtkassen sinken, weil Lohn-/Gewerbesteuern nur an Ort 0 gehen, Ort 0 dafür das regionale Personal/Dienste allein trägt; die
  übrigen Städte finanzieren Erschließung und Verbindungsstraßen aus Grundsteuer und Landeszuweisung. Offen: Steuern und Personal je Stadt.

## Schiffe und Seeverkehr (08.11.2026)

- Neue Schiffsgrafik (`scripts/world/ship_view.gd`): Rumpf mit Bug, Wasserlinie und Aufbauten, gedreht in Fahrtrichtung; vier Bauarten
  (Containerschiff, Schüttgutfrachter, Kreuzfahrtschiff, Autotransporter), Fenster nachts beleuchtet. Jeder Hafen der Region hat
  Anleger und Linienschiff (vorher nur Ort 0).
- `SeaTraffic` (`sim.sea`): Kreuzfahrtschiff „MS Aurora“ (alle 3 Tage eine Etappe) und „Autocarrier Hansa“ (alle 4 Tage) fahren reihum
  zwischen den Hafenstädten. Ankunft: Kreuzfahrtgäste buchen Hotels im Zielort (Tourism), der Autotransporter bringt dem Fahrzeughandel
  zwei Neufahrzeuge. Route: A* über Wasserfelder; liegen die Häfen an verschiedenen Meeren, außerhalb der Karte um das Festland.
- Autotest: `--demo-ship` (alle Häfen), `--demo-sea=0.3 --shot-sea=KS1|AT1`; Diagnose `tests/probe_sea_route.gd`; Test `test_sea_traffic`.

## Kartenleben (08.11.2026)

`scripts/world/ambient_view.gd` (AmbientView, in der Kartenansicht): jede Bewegung haengt an einem echten Zustand.
- Kueste: Badegaeste mit Handtuch und Sonnenschirm, Schwimmer, Kind mit Ball (nur bei Waerme, trocken, 9-19.30 Uhr), Brandung,
  Segelboote auf Kreisbahnen ueber offenem Wasser (nachts Positionslicht), Moewen ueber Straenden.
- Industrie: Bergwerk mit schwenkendem Bagger, pendelnden Muldenkippern, Staub, Halde nach Foerdermenge und Scheinwerfern nachts;
  Stahlwerk/Kokerei mit Schloten, Hochofenglut und Funken; Muehle, Brauerei, Moebelwerk, Schlachthof mit Schlot; Traktor auf Feldern,
  Weidetiere; Hafenkran schwenkt, solange ein Schiff am Kai liegt. Alles nur, wenn der Betrieb laeuft.
- Stadtleben: Passanten an Strassen in bebauten Vierteln (Pendelzeiten mehr, nachts kaum, bei Regen mit Schirm), Cafe- und
  Restaurantterrassen mit Gaesten, Laternenlicht nachts.
- Autotest: `--demo-ambient --shot-ambient=strand|boot|bergwerk|huette|traktor|passanten|kran|terrasse`; Diagnose `tests/probe_ambient.gd`.
- Offen: Autobahn (Verkehrszaehlung, genehmigte Projekte mit Fahrspuren, Anschlussstellen und Kreuzungen) ist noch nicht umgesetzt.
