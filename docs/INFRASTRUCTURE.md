# Auftrag 22: Lebendige Stadtinfrastruktur – Müll, Energie, Wasser, Polizei, Eisenbahn

Eingang 10.11.2026 (Benedikt, eingefügt während Auftrag 21 Teil 2). Vollständiger Text in der Sitzung; hier die verbindlichen Punkte
und der Abgleich mit dem Bestand. Reihenfolge laut Auftrag: Phasen 1–8, jede Phase integriert und getestet, dann die nächste.

## Kern (gekürzt)

Jeder Einwohner erzeugt Müll, verbraucht Strom und Wasser, erzeugt Abwasser. Vierzehn verbundene Systeme: Müllentsorgung und
Stadtreinigung, zentrale Deponie, Müllverbrennung, kommunale Entsorger, gemeinsames Kernkraftwerk (25/25/25/25, Verbrauch je Stadt
getrennt abgerechnet), Stromnetz als Graph mit Ausfällen und Reparatur, Trinkwasser (Wasserwerk, Pumpen, Hochbehälter, Leitungen,
getrennt von der Kläranlage), Kanalisation je Stadt, zentrale Kläranlage (Kosten nach Abwassermenge), Polizei je Stadt (Unfälle,
Kontrollen, Diebstahl, illegale Müllablagerung, Baustellenabsicherung), Eisenbahnnetz zwischen allen Städten (Bahnhof je Stadt ab
Start, Personen- und Güterzüge, Fahrpläne, Blockabschnitte/Signale/Weichen, Güterbahnhof am Großlager, Gleisbau und -wartung,
regionale Bahngesellschaft, private Güterverkehrsfirmen), neue Berufe im Arbeitsmarkt, Gebühren (Müll, Wasser, Abwasser, Strom,
Fahrgeld), Kettenreaktionen aus echten Zuständen (Stromausfall → Pumpen/Fabriken/Signale; Müllkrise; Bahnstörung → Lkw),
Dashboard-Bereich „Infrastruktur & Versorgung“ mit anklickbaren Ereignissen, Pixel-Animationen. Grundregeln: keine Ware/Energie/kein
Abfall ohne Quelle und Senke, echte räumliche Netze, Gebäude ohne Anschluss nicht versorgt, Anlagen brauchen Personal und
Betriebsmittel, Bau durch Baufirmen, alles gebucht, alles speicherbar. Abnahmetests 1–12.

## Bestand (wird erweitert, nicht ersetzt)

| Bereich | vorhanden | Lücke laut Auftrag 22 |
|---|---|---|
| Müll | `Waste`: Abfall je Haushalt/Betrieb (Tonnen pauschal), Recyclingquote, Gebühr (H0 → Stadt), Deponie je Stadt am Stadtrand, sichtbare Müllwagen-Touren; `Recycling` (Auftrag 20): Wertstoffhof, Sekundärrohstoffe | Müllarten, Tonnen je Gebäude mit Füllstand, Abholung entleert erst beim Halt, Littering/illegale Ablagerung mit Sauberkeit je Viertel, Betriebshof mit Personal/Fahrzeugen je Stadt, **gemeinsame** Deponie mit Waage und Kapazitätsausbau, Müllverbrennung mit Strom und Asche |
| Strom | `PowerGrid` (Leistung, Abschaltung nach Anschlussreihenfolge, Abrechnung), `PowerPlant` (Kernkraftwerk mit Brennelementen, Wartung, Notstrom); Regionalrat: Anteile fest 25/25/25/25 | KKW gemeinsam für vier Städte mit Gewinn-/Kostenteilung, Hochspannungstrassen und Umspannwerke als Graph, Leitungsschäden und Reparaturtrupps, Verbrauch je Stadt |
| Wasser/Abwasser | nur Erschließungsteil „Wasser“ der Grundstücke | Wasserwerk, Pumpen, Hochbehälter, Leitungsnetz, Kanalisation je Stadt, Kläranlage, Rohrbrüche, Gebühren |
| Polizei | `PublicSafety`: Personal, Streifenwagen, Ladendiebstahl, Festnahmen, Absicherung von Sperrungen; Feuerwehr-Verkehrsunfälle (Auftrag 21) | Dienststelle als Gebäude je Stadt mit Ausbau, Verkehrsunfälle mit Sperrung/Umleitung/Abschleppen, Kontrollen, Ruhestörung, illegale Müllentsorgung |
| Eisenbahn | nichts (nur Gebäudename „Güterbahnhof“) | alles |
| Haushalte | Stadtkassen, Landeszuweisung, Steuern, Grundsicherung (70 % Bund), Krankenkassen | Gebühren je Leistung, Infrastrukturbudget, Prioritäten |

## Plan

Phase 1 Müll (Tonnen, Abfuhr mit echter Entleerung, gemeinsame Deponie) · Phase 2 Verbrennung/Recycling/Entsorgungswirtschaft ·
Phase 3 KKW gemeinsam und Stromtrassen · Phase 4 Wasser, Kanal, Kläranlage · Phase 5 Polizei · Phase 6 Bahnhöfe, Schienen,
Personenverkehr · Phase 7 Güterbahn und Gleiswartung · Phase 8 Verflechtung, Bürgermeister-KI, Dashboard. Vorher wird Auftrag 21
Teil 2 (Fleischkette) abgeschlossen; Auftrag 21 Teil 3 (Eisenbahn) geht in Phase 6/7 auf.

## Stand Phase 1 – Müll (11.11.2026)

Umgesetzt in `scripts/economy/waste.gd` und `scripts/core/city_fleet.gd`:

- **Tonnen je Gebäude** (`Waste.bins`, kg): täglich kommt der Abfall der Einwohner jeder Stadt (Einwohner × 0,9 kg, verteilt nach
  bewohnten Wohnungen; ohne bewohnte Wohnung in die Tonne am Rathaus) und die Verpackung der Kassenverkäufe (auf die geöffneten Läden)
  hinein. Fassungsvermögen = 7 Tage Abfall des Gebäudes (mind. 20 kg). Beim ersten Tag sind die Tonnen unterschiedlich voll (wie die
  vorhandene Deponie).
- **Abfuhr je Stadt mit echter Entleerung**: die Müllwagen jeder Stadt starten am eigenen Rathaus; erster Halt ist die vollste Tonne,
  danach jeweils die nächstgelegene Tonne ab 60 % Füllstand, bis 2 t geladen sind. Erst beim Halt wird die Tonne geleert
  (`Waste.empty_bin`); ein voller Wagen fährt sofort zur Deponie. Eine Tour startet erst ab 30 % Ladung oder wenn eine Tonne 95 %
  erreicht (kleine Orte: etwa wöchentlich). Wagenzahl je Stadt nach Abfallmenge und Tourdauer (`Waste.trucks_for`, 1–8).
- **Gemeinsame Deponie mit Waage** (`Waste.weigh_in`): Menge je Stadt im Waagebuch, Wertstoffe (Recyclingquote) verkauft, Rest
  abgelagert. Kosten trägt die Kasse der liefernden Stadt (vorher alles P0), die Gebühr am Monatsende die Haushalte an ihre Stadt.
- **Überquellende Tonnen** senken die Versorgungszufriedenheit (`Contentment.supply_score`).
- **Erweiterung**: ab 80 % Füllstand um 600 t, Kosten 90 000 € nach den gewogenen Mengen je Stadt, fertig nach 20 Tagen.
- Anzeige: Deponie (Waage je Stadt, letzte Wägungen, Erweiterung), Müllwagen (Füllstand der Tonne am Halt, Stadt).
- Tests `test_waste_bins`, `test_garbage_collection`, `test_waste`; Messprobe `tests/probe_waste.gd [-- --days=31 --region]`.

Messung (Seed 4242, 31 Tage): Einzelstadt 1,3 t/Tag erzeugt, nach Anlauf gleich viel gewogen, überquellende Tonnen 227 → 24 von 258;
Region (2 Orte) Touren mit 8–14 Halten, keine dauerhaft überquellenden Tonnen.

Offen in Phase 1/2: Erweiterung wird noch nicht durch eine Baufirma gebaut (Kosten an den Entsorger S0); Betriebshof mit eigenem
Personal und Fahrzeugen je Stadt, Müllarten, Littering/Sauberkeit je Viertel, Müllverbrennung → Phase 2. Müllwagen werden nicht
gespeichert: nach dem Laden bleiben die Tonnen voll und werden neu angefahren (die Ladung eines fahrenden Wagens entfällt).

## Phase 2 – Müll ausbauen (ab 11.11.2026)

Reihenfolge: 1 Betriebshof · 2 Müllarten (Rest, Bio, Wertstoffe) · 3 Sauberkeit je Viertel mit Stadtreinigung · 4 Müllverbrennung
(Strom, Asche) · 5 Erweiterung von Deponie und Verbrennung durch Baufirmen.

**Schritt 1 Betriebshof (fertig 11.11.):** Municipal-Typ `AW-01` „Betriebshof Abfallwirtschaft“ (Gebäude `waste_depot`, 6 Grundvarianten ×
4 Stile in `tools/vox/public.py`), Beruf Müllwerker (13,50 €/h), Fahrzeug „Müllwagen“ (Hecklader, Besatzung 3, Bild `aw_muell` in 4
Richtungen). Gehört zur Startausstattung jeder Stadt (alte Spielstände bekommen ihn über `ensure_kit`). Die Touren starten am Betriebshof;
es fahren höchstens so viele Wagen, wie Fahrzeuge mit Fahrer und volle Besatzungen (3 Müllwerker je Wagen) da sind (`Waste.crews_of`).
Reicht der Fuhrpark nicht und ist Personal für einen weiteren Wagen da, kauft die Stadt einen Müllwagen (260 000 €, ab doppeltem
Kassenbestand). Mit eigenem Betriebshof entfällt die Abholgebühr an den Entsorger; die Stadt trägt Löhne, Fahrzeug- und Sachkosten über
Municipal. Ohne Betriebshof (Einzelstadt, kein Bauplatz) holt weiter der Entsorger S0 gegen Gebühr ab.

Nebenbefunde beim Einbau: Die Startorte (30–55 Bürger) sind voll beschäftigt – neue Dienste fanden kein Personal. Die Stellenanzeige einer
Einrichtung wirbt jetzt für jeden Beruf alle 7 Tage eine Kraft von außerhalb an, wenn im Ort eine Wohnung frei ist (vorher nur Ärzte und
Rettungsdienst). Grundvarianten öffentlicher Gebäude werden über alle Stile verteilt (vorher wiederholten sich Formen bei mehreren Stilen).
Test `test_waste_depot`; Probe `tests/probe_staff_pool.gd` (Arbeitsmarkt der Dienste je Stadt).
