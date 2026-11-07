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
| 2 | Stadtidentitäten, Konten/Eigentümer je Stadt, Zuständigkeitsauflösung, Migration | offen |
| 3 | Regionsgenerator 2–4 Orte, je ein Unternehmer, Startstraßennetz | offen |
| 4 | Verwaltung je Stadt (Bürgermeister, Haushalt, Bauhof, Genehmigung, Projekte, Wahlen), Gemeinschaftsprojekte | offen |
| 5 | Binnenhandel zwischen Städten, Flughäfen und Flugverkehr | offen |
| 6 | Expansion, zusätzliche Gründer, Pendeln, Umzüge | offen |
| 7 | Oberfläche, Auswertungen, Grafikprüfung, Balance | offen |

## Abnahmeszenarien

| Nr. | Szenario | Stand |
|---|---|---|
| 1 | 2/3/4 Startspieler → so viele gültige Städte, eindeutige Namen, je ein Unternehmer | offen |
| 2 | ≤ 40 Startgebäude je Stadt; Rathaus, Bauhof, Hafen, Flugplatz erreichbar; keine versteckten Startfirmen | offen |
| 3 | Verschiedene Seeds gültig, gleicher Seed reproduziert; Berge unbebaut | offen |
| 4 | Städte über Straßen verbunden, LKW-Lieferung zwischen Stadtzentren | offen |
| 5 | Zahlung aus A ändert B nicht; fremde Verwaltungsaktionen abgelehnt | offen |
| 6 | Firma aus A kauft Land in B, Antrag in B, Entscheidung von B, Betrieb läuft | offen |
| 7 | Kommunaler Materialauftrag von der richtigen Stadt bezahlt und ins richtige Lager; Personal einmal entlohnt | offen |
| 8 | Gemeinsames Projekt einmal vergeben, anteilig finanziert, erst nach Abnahme nutzbar; Folgen bei Ablehnung | offen |
| 9 | Produkt zwischen zwei Städten verkauft/transportiert, X0 unverändert | offen |
| 10 | Echter Flug A→B, Fracht erst nach Ankunft verfügbar, Kapazität und Kosten | offen |
| 11 | Flug/Umzug erzeugt keine Personen, Bevölkerung und Vermögen erhalten | offen |
| 12 | Nachfrage + Finanzierung → neue Company mit eigenem Controller | offen |
| 13 | Gründung scheitert verständlich (Kapital, Standort, Quote); Heimatstadt vs. Filiale | offen |
| 14 | Company-ID > Startslots funktioniert überall (Verträge, Personal, Kredite, UI, Speichern) | offen |
| 15 | Insolvenz reguliert Forderungen; keine ID-Wiederverwendung | offen |
| 16 | Wahl in A ändert B nicht; verspätete Antwort des alten Amtsinhabers verworfen | offen |
| 17 | Speichern/Laden neuer Regionen und alter Einzelstadt-Stände ohne Verlust | offen |
| 18 | Bilanzen/Warenbilanz/Geldprüfungen konsistent, keine unbeabsichtigten Mittel | offen |
| 19 | Langer Probelauf mit 4 Städten und Gründern; API-Ausfall blockiert nichts | offen |
| 20 | Grafische Probeläufe der Region | offen |
