# Auftrag 11: Hof-Imperium – lernende KI-Unternehmer bauen ihren Betriebshof selbst aus

Auftrag von Benedikt (04.11.2026): „Wie bekommen wir mehr Dynamik und Lernfähigkeit in die KI? Mega wäre, wenn die KI selbständig kreativ den Betriebshof baut, bearbeitet und erweitert: Waren mit dem Lkw vom Bürgermeisterhof abholen und damit ihr Imperium aufbauen. Die KI entscheidet, was sie auf dem Hof baut, und kann den Hof erweitern.“ Auf die Vorschläge hin: „alles umsetzen 1234“.

Grundsatz wie bisher: auf dem Bestand aufbauen (Betriebshof `Estate` mit 15 Gebäudetypen, Eigenbau mit Material vom Bauhof per eigenem Transport, Erweiterung auf Nachbargrundstücke, Gedächtnis `sim.memory`, Strategielernen), keine Parallelsysteme. Ein Modell wählt nur zwischen gültigen Optionen oder schlägt mit Begründung vor; die Engine prüft jede Aktion.

## Etappen

| # | Inhalt | Stand |
|---|---|---|
| 1 | **Fehler der Modellspieler** aus der Partie vom 04.11.: Auftragsaktionen bei aktivem Disponenten übergehen statt doppelt planen, bereits eingeplante Besuche nicht als Fehler werten, Arbeiter ohne passende Aufgabe in Bereitschaft lassen, `task` als `kind` lesen, Disponent ohne Angebote mit zu kurzer Restlaufzeit (unter 120 Spielminuten) und mit Ersatzwahl | fertig (04.11.2026): `test_model_error_fixes` |
| 2 | **Kern**: (a) Baustoffe vom Bürgermeisterhof (Stadtlager) – Restposten aus Stadtprojekten und Straßenwartung, billiger als der Bauhof, nur Selbstabholung; (b) **Bauberater** mit gemessenen Engpässen und Nutzenrechnung (Nutzen je Monat, Amortisation), fertige Aktion je Vorschlag; (c) **Investitionsakte**: Erwartung beim Bau, Messung nach 10 Tagen, Ergebnis ins Gedächtnis | offen |
| 3 | **Spezialisierungen und Layout**: Ausbaupfade (Kühllogistik, Schwerlast, Umschlag, Tankhof) mit neuen Gebäuden und Boni; Nachbarschaftsboni auf dem Hof (z. B. Rampe neben Lager) | offen |
| 4 | **Bauanträge und Grundstückskonkurrenz**: große Hallen brauchen eine Genehmigung des Bauamts (Kapazität aus dem Rathaus, Bürgermeister kann ablehnen/Auflagen); Nachbargrundstücke per Gebot, Mitbewerber können überbieten | offen |
