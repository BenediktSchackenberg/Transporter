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
