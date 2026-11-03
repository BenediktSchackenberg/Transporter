# Auftrag 10: Bewohner, Eigentum, Grundsteuer, Bedürfnisse, Sicherheit und Gesundheit

Vorlage von Benedikt (03.11.2026, zweimal eingereicht; die zweite Fassung ergänzt Zu-/Abwanderung, Polizei, Gefängnis, Krankenhaus, Ärzte und Kriminalität und verlangt keine Rückfrage mehr). Grundsatz der Vorlage: **auf den bestehenden Strukturen aufbauen, keine Parallelsysteme**, fehlende Informationen als Annahmen kennzeichnen.

## Technischer Kontext (aus dem Projekt, nicht aus der Vorlage)

Godot 4.4.1, GDScript, isometrische Pixelgrafik. Bestehende Bausteine: `Citizens` (Bürger als schlanke Datensätze, Arbeitsmarkt), `Housing` (Wohneinheiten, Mietverträge, Räumung), `Contentment` (Zufriedenheit je Wohneinheit), `Tiers` (Wohnstufen und Bedürfnisse je Viertel), `PublicSector` (Steuern, Sozialleistungen), `Economy` (Sektorkonten mit Geldkonservierung), `Mayor`/`TownHall` (Bürgermeister, Rathaus mit Personal), `CityGenerator` (Karte), `Citizens.travel_plan` (sichtbare Alltagswege).

## Abgleich der Vorlage mit dem Bestand

| Punkt | Bestand | Neu / geändert |
|---|---|---|
| 1 Startbevölkerung | 1200 Bürger mit ID, Name, Arbeitgeber, Lohn, Wohnsitz | Alter, Bildung, Konto, Bedürfnisse, Eigentümerstatus; Zahl konfigurierbar |
| 2 Karte | Wohnungsbestand mit Leerstand 4 % aus vorhandenen Wohngebäuden (Haus 1, Doppelhaus 2, Villa 1, Wohnblock 6, Hochhaus 24 Einheiten) | Startprüfung der Kapazität; Polizei, Gefängnis, Arztpraxis (Etappe 3) |
| 2 Arbeitsplätze | Arbeitgeber Rathaus, Schule/Klinik, Baufirma, Handel, Industrie, Stadtlager; 80 % beschäftigt | Beschäftigungsquote konfigurierbar; Zuweisung nach Bildung |
| 3 Eigentum/Miete | Miete der Bürgergruppen sektorweise an den Vermietersektor V0 | Eigentümer aus der Bevölkerung (Eigennutzer, Vermieter), Miete von Person zu Person |
| 4 Grundsteuer | feste 10 % der Vermieterflüsse an P0 | Grundsteuer je Eigentümer nach Immobilienwert, Satz vom Bürgermeister |
| 5 Monatszyklus | einzelne Monatsabrechnungen | feste Reihenfolge, Monatsprotokoll |
| 6 Bedürfnisse | Zufriedenheit je Wohneinheit, Bedürfnisdeckung je Viertel | Geld, Arbeit, Bildung, Glück je Person mit Verhaltenswirkung |
| 7 Bewegung | Tagesablauf und sichtbare Wege vorhanden | Schule, Arzt, Polizei, Gefängnis als Ziele; Leistungsmessung vor Optimierung |
| 8 Validierung | keine Startprüfung | Startprüfung mit Logausgabe |
| 8 Zu-/Abwanderung | `immigrate`/`emigrate` vorhanden (Wohnungsmarkt) | an Wirtschaftslage und Glück gekoppelt |
| 8 Sicherheit/Gesundheit | Kliniken als Gebäude, Krankheit nur beim Firmenpersonal | Polizei, Gefängnis, Ärzte, Krankenhausaufenthalte, Kriminalität |
| 9 Konfiguration | Konstanten in den Klassen | zentrale Datei `config/residents.json` |

## Annahmen (deutlich gekennzeichnet)

- **A1 Konten:** neues Sektorkonto **R0 „Bürgerkonten“**. Jede Person hat ein Guthaben; die Summe aller Guthaben ist immer exakt R0 (Teil der Konservierungsprüfung). Bürgerzahlungen laufen über R0 statt über H0; H0 (Firmenhaushalte, Kundenmarkt) bleibt unverändert, damit die Stadtkasse stabil bleibt. Startguthaben kommen als Ersparnisse aus dem Ausland (X0 → R0).
- **A2 Zahlen:** Standard laut Vorlage 1000 Bewohner, 90 % Beschäftigung, 35 % Eigentümer. Zeigt der Wirtschaftslauf, dass die Stadtkasse damit kippt, werden Löhne oder Leistungen angepasst und das hier vermerkt.
- **A3 Arbeitgeber:** die bestehenden Kategorien bleiben (kein Parallelsystem). Abbildung der Vorlage: „Fabrik“ = Industrie und Baufirma, „Büro“ = Handel/Dienstleistung, „Stadtverwaltung“ = Rathaus, Schule/Klinik, Stadtlager, Polizei, Gesundheit.
- **A4 Grundsteuer** ersetzt die feste 10 %-Abzweigung für Wohnungen mit Bürger-Eigentümer; der Vermietersektor V0 zahlt für seine Wohnungen weiter wie bisher.
- **A5 Bildung** 0 Grundbildung, 1 Ausbildung, 2 Fachkraft, 3 Hochschule. Rathaus, Schule/Klinik und Gesundheit verlangen eher höhere Bildung.
- **A6 Kriminalität** ist ein Spielmodell ohne Wertung: Wahrscheinlichkeit aus Geldnot, Arbeitslosigkeit und Unglück; Polizei findet Täter abhängig von ihrer Personalstärke.

## Etappen

| # | Inhalt | Stand |
|---|---|---|
| 1 | Personenmodell (Alter, Bildung, Konto R0, Bedürfnisse), Konfiguration, Eigentümer/Mieter, Miete von Person zu Person, Grundsteuer mit Satz des Bürgermeisters, Monatszyklus in fester Reihenfolge, Startprüfung | fertig (03.11.2026): `scripts/economy/population.gd`, `config/residents.json`, `test_population`; Volltest 5314 Prüfungen (2 angepasste Erwartungen an 90 % Beschäftigung); Stadtkasse über 180 Tage 200 k → 440 k, nie im Minus |
| 2 | Verhalten aus Bedürfnissen: Jobsuche nach Bildung, Schulbesuch, Umzug und Jobwechsel bei Unglück, Zu- und Abwanderung nach Wirtschaftslage | offen |
| 3 | Polizei, Gefängnis, Arztpraxen, Krankenhaus: Gebäude, Personal (wohnt in der Stadt), Krankheit und Einweisung, Kriminalität, Festnahme, Haft mit Verlust von Arbeit und ggf. Wohnung | fertig (03.11.2026): `scripts/economy/public_safety.gd`, `test_public_safety`; Streifen- und Krankenwagen fahren sichtbar, Polizei sichert Sperrungen ab |
| 4 | Darstellung und Leistung: neue Wegziele, Streifen, Messung mit `tests/probe_perf.gd`, Optimierung nur wo gemessen nötig | offen |

## Monatszyklus (Ziel von Etappe 1)

1. Löhne (Arbeitgeber → R0, Rathaus aus P0), Lohnsteuer und Sozialabgaben an P0.
2. Grundsicherung für Arbeitslose (P0 → R0).
3. Miete: Mieter → Eigentümer (innerhalb R0) bzw. → V0/D0 bei Wohnungen ohne Bürger-Eigentümer; Rückstand bei Zahlungsunfähigkeit.
4. Grundsteuer: Eigentümer → P0.
5. Konsum aus dem verfügbaren Einkommen (R0 → S0, X0).
6. Bedürfnisse und Statistik; Monatsprotokoll der Summen.

## Etappe 3: Umsetzung

- **Gebäude** (nach allen anderen, letzte IDs, Zufallszustand wiederhergestellt): Polizeiwache, Justizvollzugsanstalt, zwei Arztpraxen; Krankenhaus ist die vorhandene Stadtklinik.
- **Personal**: Arbeitgeber `polizei` (3 % der Stellen) und `gesundheit` (4 %), Löhne aus der Stadtkasse; der Handel gibt dafür 7 Punkte ab. Das Personal sind Bürger mit Wohnung.
- **Gesundheit** (täglich): Erkrankungsrisiko steigt mit Unglück und Alter; leichte Fälle 1–3 Tage beim Arzt, schwere (25 % oder bei überlasteten Praxen) 3–10 Tage Krankenhaus mit Krankenwagen. Kosten (60 EUR Arzt, 250 EUR je Krankenhaustag) zahlt die Stadtkasse an die Dienstleister.
- **Kriminalität** (täglich): Ladendiebstahl; Wahrscheinlichkeit ×3 bei Geldnot, ×2 arbeitslos, ×2 unglücklich. Beute vom Handel auf das Konto des Täters.
- **Polizei**: Aufklärung je Tag 10 % + 2,5 % je Polizist (höchstens 90 %); Festnahme mit Streifenwagen, Beute erstattet, Haft 30–90 Tage, Arbeit weg; Mieter verlieren ab 60 Tagen Haft die Wohnung, Eigentümer mit Steuerrückstand bei langer Haft ihr Haus (Zwangsversteigerung an den Vermietersektor, 60 % des Werts). Häftlinge werden weder eingestellt noch untergebracht und erhalten keine Grundsicherung.
- **Streifenwagen** sichern freie Sperrungen ab (stehen mit Blaulicht daneben), sonst Streife; Krankenwagen warten am Krankenhaus.
- **Anzeige**: Diebstahl rot, Polizei blau, Krankenwagen weiß auf der Karte und in der Leiste; der Bürgermeister sieht `sicherheit_gesundheit`.
- **Grenzen**: Arbeitsausfall Kranker wirkt nicht auf den Lohn (Lohnfortzahlung); Personalstärke von Polizei und Gesundheit steuert der Bürgermeister noch nicht.
