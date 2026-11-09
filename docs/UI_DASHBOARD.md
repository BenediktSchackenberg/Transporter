# Leitstelle – neue Spieloberfläche

Die verschachtelten Menüs rechts sind durch die **Leitstelle** ersetzt: ein einklappbares Seitenfenster über der Karte mit sechs Hauptbereichen.
Die Karte bleibt zentral: **F1** oder „⟩ Karte“ klappt die Leitstelle auf eine schmale Navigationsleiste zusammen, **Tab** blendet alle Seitenleisten aus.

## Menüstruktur

| Bereich | Inhalt |
|---|---|
| ◆ **KI-Zentrale** (Start) | KPI-Karten mit Trend: aktive KI-Unternehmen (API / Ersatzmodus), Mitarbeiter, Fahrzeuge im Einsatz, Transportaufträge (unterwegs / warten / ⚠ gefährdet), offene Bauprojekte, bedeutende Ereignisse heute, Ergebnis aller Firmen (7 Tage), KI-Aktivität. Links „Was passiert gerade?“ (Ereigniskarten), rechts die KI-Spieler-Karten (Status, Ziel, aktuelle Tätigkeit, letzte Entscheidung, Finanzen, Problem, „Details“, „Warum?“). |
| ✦ **Welt & Ereignisse** | Ereigniszentrale mit Filtern (Kategorie, Priorität, Stadt, Unternehmen, Zeitraum), Volltextsuche, „Ältere laden“. Unterseite **Gespräche der KI**: je Firmenpaar eine Karte mit Thema, Anzahl, Angebotsstatus; Angebote gelb hervorgehoben, Wiederholungen zusammengefasst. |
| ▣ **Unternehmen** | Karten aller Firmen. Detailfenster mit Reitern: Überblick, Finanzen (Diagramme), Aufträge, Fahrzeuge (Klick → Kamera folgt dem Fahrzeug), Mitarbeiter, KI-Strategie, Entscheidungen (Zeitleiste, Klick → Erklärung). |
| ▲ **Städte** | Je Stadt Einwohner, Zustimmung, Arbeitslose, Kasse, Leitbild und laufende Anlagen. Detail: KPIs, Haushalt (7 Tage), Kasse/Investitionen als Diagramm, Pläne des Bürgermeisters mit Begründung, Status, nächstem Schritt, Material geliefert/benötigt, Kosten, Baufirma, Restbautage, „Bauplatz auf der Karte“. |
| € **Wirtschaft & Finanzen** | Zeitraum Heute / 7 / 30 Tage / Gesamt. Firmenvergleich (Umsatz, Kosten, Ergebnis, Bargeld, Schulden, Vermögen, Personal, Fahrzeuge), Gesamtwirtschaft der Region, Städtevergleich. |
| ⚙ **Einstellungen & Technik** | Oberflächengröße 100/125/150 %, Ereignismarker auf der Karte, **Expertenmodus** (alte Protokollansichten mit IDs und Rohdaten), Speichern, Status der KI-Anbindung (Anbieter, Modell, Anfragen, Fehler, letzte Störung). |

Globale **Suche** (oben rechts): Unternehmen, Personen, Städte/Bürgermeister, Auftrags-IDs, Fahrzeuge (#Nr. oder Modell), Gebäude, Bauprojekte und Ereignisse.

## Datenmodell (keine zweite Simulation)

* `scripts/core/event_center.gd` – **EventCenter**: liest Ereignisprotokoll, Kartenaktivitäten, Entscheidungsprotokoll und Stadtentwicklung. Kategorien *kritisch, Wirtschaft, KI-Entscheidung, Stadtentwicklung, Aktivität*, Schweregrad 0–3, Verweise, Ort (Kartenzelle zum Zeitpunkt des Ereignisses). Gleichartige Meldungen innerhalb eines Spieltags werden zu einem Ereignis mit Zähler zusammengefasst. Wird gespeichert.
* `scripts/core/decision_text.gd` – **DecisionText**: verständliche Erklärung einer KI-Entscheidung nur aus gespeicherten Fakten: Ziel und Begründung wörtlich vom Modell (fehlt sie: „Gründe nicht bekannt“), Lage zum Entscheidungszeitpunkt (Momentaufnahme im Entscheidungsprotokoll: Bargeld, Schulden, Fahrzeuge, freie Fahrzeuge, Aufträge/Kapazität, Personal, Ruf), Ablauf in fünf Stufen (vorgeschlagen → geprüft → angenommen → ausgeführt → Ergebnis), gemessene Folgen, typische Risiken der Aktion, freundliche Ablehnungstexte mit Ursache und Verbesserung, Quelle (KI-Modell/API, Planschritt, regelbasierter Ersatzmodus). „Technische Details“ zeigt die Rohdaten.
* `scripts/core/finance_history.gd` – **FinanceHistory**: Momentaufnahme je Spieltag (Buchungssummen je Kategorie, Bargeld, Schulden, Vermögen, Flotte, Personal, Auftragsstatistik; je Stadt Kasse, Einnahmen/Ausgaben, Einwohner, Zustimmung, Investitionen). Zeitraumwerte sind Differenzen der Buchhaltung; Ergebnis gesamt = Gewinn laut Ledger. Kredite sind weder Umsatz noch Kosten. Wird gespeichert (letzte 120 Tage).
* `scripts/ui/control_center.gd` – **ControlCenter** (Oberfläche, Diagramme `LineChart`/`BarChart`).
* `scripts/world/map_markers.gd` – **MapMarkers**: wichtige Ereignisse der letzten 12 Spielstunden als verblassende Symbole; Hervorhebungsring beim Kamerasprung.

## Kartensprung

„Auf Karte zeigen“ fährt die Kamera weich zum **gespeicherten Ereignisort** und markiert ihn (Ring, 4 s). Ist ein beteiligtes Fahrzeug inzwischen weitergefahren, wird der damalige Ort gezeigt und ein Hinweis eingeblendet; „Fahrzeug auf der Karte“ (Unternehmen → Fahrzeuge) folgt dem Fahrzeug an seiner aktuellen Position. Existiert ein Objekt nicht mehr, bleibt der gespeicherte Ort.

## Gestaltung

Dunkles Thema; Überschriften in Pixelschrift (22–26 px, Abschnitte 18–20 px), Fließtext in gut lesbarer Systemschrift (15–16 px, Nebentexte 13–14 px). Farben immer mit Symbol oder Statuswort: grün ✔/▲ gut, gelb ⚠ Warnung, rot ✖/▼ kritisch, blau Info, violett ◆ KI. Getestet bei 1920×1080 und 2560×1440, Skalierung 100/125/150 %.

## Leistung

Die Leitstelle baut eine Ansicht nur neu, wenn sich ihre Datenlage ändert (Prüfung alle 1,5 s; KI-Zentrale höchstens alle 20 Spielminuten oder bei neuen Ereignissen/Entscheidungen). Die Ereigniszentrale gleicht sich alle 5 Spielminuten mit den Quellen ab, hält höchstens 2500 Ereignisse und zeigt Listen seitenweise (40 je Seite). Finanzreihen entstehen einmal je Spieltag.

## Prüfung

* Tests: `test_event_center`, `test_decision_text`, `test_finance_history`.
* Sichtprüfung aller Ansichten in einem Lauf:
  `Godot --path . --resolution 1920x1080 -- --autotest --seconds=200 --screenshot=user://v.png --shot-at=70 --shot-ui=ki,welt,gespraeche,firmen,firma:0:finanzen,warum,staedte,stadt:1,finanzen,technik,suche:Greta,sprung,zu`
  (je Angabe ein Bild `v_<Angabe>.png`; `skala:1.5` setzt die Oberflächengröße und speichert sie in `user://ui.cfg`).
