# Auftrag 12: Rivalität – KI-Dialoge, Provokation und Eskalation

Auftrag von Benedikt (04.11.2026): „Bürgermeister und die KI-Spieler agieren nicht miteinander. Sie sollen Dialoge führen, KI-gesteuert; die KI soll schauen, in welche Richtung der Dialog geht. Die KI soll provozieren, und die anderen KIs können darauf reagieren, z. B. ihn anzeigen oder etwas sabotieren, die Straßen mit Waren zulegen, damit er seine Lkw nicht mehr fahren kann. Überlege dir was Cooles.“ Reihenfolge bestätigt: nach Auftrag 11 (Hof-Imperium), vor Auftrag 13 (KI-Regie für Ereignisse).

## Bestand (keine Parallelsysteme)

`Social` (Nachrichten, Vertrauen je Firmenpaar, Bündnisse, Handelsangebote), `Rivalry` (Fahrer/Kunden abwerben, Anzeige beim Bürgermeister, Sabotage mit Entdeckung, Sicherheitsdienst), `Inspections` (Prüfdienst), `PublicSafety` (Streifenwagen sichern Sperrungen), `NavGrid.add_roadwork` (gesperrte Straßenzelle), `ActivityFeed` (Karte und Leiste), `MemoryBook` (Gedächtnis), Claude-Anbindung wie beim Disponenten (nummerierte Kandidaten, Regeln als Ersatz).

## Entwurf

1. **Spannung je Firmenpaar** (0–100) aus echten Ereignissen: Auftrag weggeschnappt, Fahrer/Kunde abgeworben, überboten (Grundstück), Anzeige, Sabotage entdeckt, Blockade; sinkt langsam von selbst und durch Kooperation, Bündnis oder Schlichtung.
2. **Gesprächsregie**: wählt regelmäßig das spannendste Paar und lässt die nächste Zeile sprechen. Mit Claude: Lage des Paares, letzte Zeilen, Persönlichkeiten und **nummerierte gültige Reaktionen** → Antwort `{text, richtung (eskalation|deeskalation|kooperation), wahl}`. Ohne Schlüssel: Regelzeilen je Persönlichkeit und Stufe. Zeilen erscheinen als Sprechblasen auf der Karte und im Funkverkehr.
3. **Eskalationsleiter**: 1 Stichelei (öffentliche Nachricht, etwas Ruf), 2 Provokation (Kunde/Fahrer abwerben, Grundstück überbieten), 3 Anzeige (Prüfdienst), 4 **Straßenblockade** (neu: Paletten auf eine Straße nahe am Hof des Rivalen; dessen Lkw müssen umfahren; verboten – Streifenwagen räumen, Bußgeld, Ruf), 5 Sabotage (wie bisher). Reaktionen: Gegenanzeige, Polizei rufen, Schlichtung beim Bürgermeister, Bündnis mit Dritten, deeskalieren.
4. **Bürgermeister**: sieht Spannungen und Vorfälle, kann öffentlich verwarnen oder schlichten (befristetes Stillhalteabkommen); Unruhe senkt seine Zustimmung.
5. **Lernen**: Folgen jeder Eskalation (Ruf, Kunden, Bußgelder, verlorene Fahrten) werden gemessen und ins Gedächtnis geschrieben.
6. **Grenzen**: höchstens eine Blockade je Firma und Tag, Dauer begrenzt, nie an Krankenhaus, Polizei oder Feuerwehr; Schutzfristen wie bei der Sabotage; alles im Protokoll.

## Etappen

| # | Inhalt | Stand |
|---|---|---|
| 1 | Spannungsmodell, Ereignisquellen, Beobachtung für Firmen und Bürgermeister | fertig (05.11.2026) |
| 2 | Straßenblockade mit Polizei, Bußgeld, Darstellung | fertig (05.11.2026) |
| 3 | Gesprächsregie (Regeln + Claude), Sprechblasen, Reaktionswahl | offen |
| 4 | Bürgermeister: Verwarnung, Schlichtung, Zustimmung; Lernen aus Folgen; Messlauf | offen |

## Stand

**Etappe 1 (05.11.2026):** `Rivalry.tension` je Firmenpaar (`Social.pair_key`), Vorfallsliste `incidents` (Verursacher, Betroffener, Art, Änderung), Werte in `Rivalry.TENSION`: Auftrag beim fremden Stammkunden +4, Abwerbeversuch +5, Fahrer/Kunde abgeworben +15, Grundstück überboten +8, Anzeige +20 (unbegründet +12), entdeckte Sabotage +35, Geschäft −6, Bündnis −15; täglicher Abbau 4. Stufen (`STAGES`): ab 15 Stichelei, 30 Provokation, 50 Anzeige, 70 Blockade, 85 Sabotage; Stufenwechsel landet im Protokoll. Unentdeckte Sabotage erzeugt keine Spannung (das Opfer kennt den Täter nicht). Beobachtung: `konkurrenten[].spannung` und `rivalitaet` für Firmen, `rivalitaet` (Paare, Vorfälle 7 Tage, Unruhe) für den Bürgermeister. Test `test_rivalry_tension`.

**Etappe 2 (05.11.2026):** Aktion `block_road(target)` (`Rivalry.block_road`): erst ab Spannung 70, je Täter und je Opfer höchstens eine am Tag, 600 EUR. Die Zelle liegt 2–7 Straßenschritte vom Hof des Opfers, nur auf geraden Stücken (keine Kreuzung), mindestens 5 Felder von Polizei, Arztpraxen und Klinik entfernt, und nur dort, wo vom Hof aus beide Enden erreichbar bleiben (Umfahrung). Sperre über `NavGrid.add_roadwork`, Verkehrsmeldung `blockade`, Streifenwagen sichern die Stelle (vorhandene Logik in `PublicSafety`). Die Polizei räumt nach 60–150 Spielminuten und ermittelt mit 70 % (+10 % je Sicherheitsstufe des Opfers): 2500 EUR Bußgeld an die Stadtkasse, Ruf −8, Vertrauen −30, Spannung +25. Unbekannter Täter: keine Spannung. Voxelgrafik `blockade` (Paletten mit Kartons, `python tools/build_iso.py props`). Aktive Blockaden werden gespeichert und sperren nach dem Laden weiter. Test `test_road_blockade`.
