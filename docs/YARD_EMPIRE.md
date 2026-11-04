# Auftrag 11: Hof-Imperium – lernende KI-Unternehmer bauen ihren Betriebshof selbst aus

Auftrag von Benedikt (04.11.2026): „Wie bekommen wir mehr Dynamik und Lernfähigkeit in die KI? Mega wäre, wenn die KI selbständig kreativ den Betriebshof baut, bearbeitet und erweitert: Waren mit dem Lkw vom Bürgermeisterhof abholen und damit ihr Imperium aufbauen. Die KI entscheidet, was sie auf dem Hof baut, und kann den Hof erweitern.“ Auf die Vorschläge hin: „alles umsetzen 1234“.

Grundsatz wie bisher: auf dem Bestand aufbauen (Betriebshof `Estate` mit 15 Gebäudetypen, Eigenbau mit Material vom Bauhof per eigenem Transport, Erweiterung auf Nachbargrundstücke, Gedächtnis `sim.memory`, Strategielernen), keine Parallelsysteme. Ein Modell wählt nur zwischen gültigen Optionen oder schlägt mit Begründung vor; die Engine prüft jede Aktion.

## Etappen

| # | Inhalt | Stand |
|---|---|---|
| 1 | **Fehler der Modellspieler** aus der Partie vom 04.11.: Auftragsaktionen bei aktivem Disponenten übergehen statt doppelt planen, bereits eingeplante Besuche nicht als Fehler werten, Arbeiter ohne passende Aufgabe in Bereitschaft lassen, `task` als `kind` lesen, Disponent ohne Angebote mit zu kurzer Restlaufzeit (unter 120 Spielminuten) und mit Ersatzwahl | fertig (04.11.2026): `test_model_error_fixes` |
| 2 | **Kern**: (a) Baustoffe vom Bürgermeisterhof (Stadtlager) – Restposten aus Stadtprojekten und Straßenwartung, billiger als der Bauhof, nur Selbstabholung; (b) **Bauberater** mit gemessenen Engpässen und Nutzenrechnung (Nutzen je Monat, Amortisation), fertige Aktion je Vorschlag; (c) **Investitionsakte**: Erwartung beim Bau, Messung nach 10 Tagen, Ergebnis ins Gedächtnis | fertig (04.11.2026): `scripts/core/yard_advisor.gd`, `test_yard_empire_core` |
| 3 | **Spezialisierungen und Layout**: Ausbaupfade (Kühllogistik, Schwerlast, Umschlag, Tankhof) mit neuen Gebäuden und Boni; Nachbarschaftsboni auf dem Hof (z. B. Rampe neben Lager) | fertig (04.11.2026): `test_yard_specializations` |
| 4 | **Bauanträge und Grundstückskonkurrenz**: große Hallen brauchen eine Genehmigung des Bauamts (Kapazität aus dem Rathaus, Bürgermeister kann ablehnen/Auflagen); Nachbargrundstücke per Gebot, Mitbewerber können überbieten | offen |

## Etappe 2: Umsetzung

- **Baustoffe vom Bürgermeisterhof** (`CityDepot`): Restposten (Start: Ziegel, Holz, Beton, Verbindungsmaterial, Stahl, Rohmaterial, Glas, Installation; monatlich Nachschub aus Stadtprojekten; jede Straßeninstandsetzung liefert Aufbruch). Preis 60 % des Bauhofpreises, Erlös an die Stadtkasse. Nur im **Eigenbau** und nur mit Selbstabholung: Die Firma bekommt einen internen Transportauftrag vom Stadtlager zum Hof (zusätzlich ggf. einen vom Bauhof für den Rest); der Bau beginnt erst, wenn alle Lieferungen da sind. `place_building` mit `quelle=bauhof` schließt das Stadtlager aus.
- **Bauberater** (`YardAdvisor`, Beobachtung `betriebshof.bauberater`): tägliche Momentaufnahmen des Hauptbuchs je Firma; Engpässe der letzten 30 Tage (Stellplätze voll bei offenen Aufträgen, Reparaturkosten, Treibstoff, Auftragskapazität, Erschöpfung, Fahrkönnen, Kühlaufträge, Linien über den Hof). Bis zu 5 nummerierte Vorschläge mit Nutzen je Monat, Unterhalt, Kosten, Amortisation, Restposten-Angebot und fertiger Aktion (Eigenbau, wenn ein Arbeiter frei ist).
- **Investitionsakte**: Jeder Bau hält die Erwartung fest (`erwartung_eur_monat` des Modells oder Beraterschätzung). 10 Tage nach Fertigstellung misst das Spiel dieselbe Kennzahl (zusätzliche Fahrzeuge, gesunkene Reparatur-/Treibstoffkosten, mehr erledigte Aufträge, Erschöpfung, Mieten, sonst Gewinn) und schreibt „erwartet … / gemessen …“ ins Gedächtnis der Firma. Der **Prognosefaktor** je Gebäudetyp (Mittel gemessen/geschätzt mit Vorannahme 1,0 im Gewicht von zwei Messungen, 0,2–2,0) korrigiert alle weiteren Schätzungen. Im Spiel bleiben die Faktoren über Partien erhalten (`user://yard_learning.json`), in Tests nicht.
- **Regel-KI**: baut den besten Vorschlag mit Amortisation bis 8 Monate (höchstens eine Baustelle zugleich), teilt freie Arbeiter dem Eigenbau zu, sobald das Material da ist; eigene Materialtransporte disponiert die Regel-Disposition auch bei aktivem Claude-Disponenten.

## Etappe 3: Umsetzung

- **Neue Gebäude** (Voxelgrafik in `tools/vox/facilities.py`, erzeugt mit `python tools/build_iso.py facilities`): **Schwerlastkran** (2×2, 12 000 EUR, schwere Fahrzeuge laden am Hof ×0,6) und **Umschlaghalle (Cross-Dock)** (3×3, 14 000 EUR, überdachter Umschlag am Hof ×0,7).
- **Spezialisierungen** (`Estate.SPECIALIZATIONS`, ergeben sich von selbst aus Gebäuden und Flotte, Übersicht mit Voraussetzungen in `betriebshof.spezialisierungen`):
  - Kühllogistik-Hub (Kühllager + 2 Kühltransporter): +10 % auf Kühlfracht.
  - Schwerlasthof (Kran + schweres Fahrzeug): +10 % auf schwere Fracht.
  - Umschlagzentrum (Umschlaghalle + Laderampe): Laden/Entladen am Hof zusätzlich ×0,8.
  - Tankhof (Betriebstankstelle + 5 Fahrzeuge): übernimmt die Notbetankungen der Konkurrenz; Treibstoff zum Grundpreis geht an den Markt, Aufpreis und Pauschale sind Erlös des Tankhofs (Verrechnung über C0).
  - Werkstatthof (Werkstatt Stufe 2 + Mechaniker mit Reparieren ≥ 2): Pannendienst, die Abschleppgebühr der Konkurrenz ist Erlös.
- **Layout-Boni** (`Estate.LAYOUT`, Gebäude berühren sich auf demselben Grundstück): Laderampe an Lager/Kühllager/Umschlaghalle → Laden am Hof ×0,85; Pausenraum an Werkstatt/Büro → Erholung ×2,5 statt ×2. Aktive Boni und Regeln stehen in der Beobachtung.
- **Bauberater** kennt Kran (bei schweren Fahrzeugen) und Umschlaghalle (Linien über den Hof oder ab 4 Fahrzeugen).
- **Grenze**: Gibt es mehrere Tank- oder Werkstatthöfe, bedient der mit der kleinsten Firmennummer; die Platzwahl für Layout-Boni überlässt die Regel-KI noch den Bauvorschlägen (erster freier Platz), ein Modell kann gezielt daneben bauen.
