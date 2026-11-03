# Auftrag 9: Rathaus, Verwaltung und städtische Aufgaben des Bürgermeisters

Wortlaut des Auftrags (Benedikt, 03.11.2026): Der Bürgermeister soll ein **Rathaus** haben und **Angestellte**. Er muss die **Straßen warten** (seine Mitarbeiter, dazu Baufirmen beauftragen), man sieht **per Bautrupp**, dass die Menschen arbeiten. Der Bürgermeister **entscheidet, ob eine Prüfung bei einer Firma stattfindet** (Lohnsteuerprüfung, Mitarbeitersicherheit). Er **steuert das Auftragsverhalten aus dem städtischen Pool**.

## Annahmen (Benedikt hat die drei offenen Fragen nicht beantwortet; Standard = meine Empfehlung, änderbar)

1. Die **Zufallsprüfung** (Lohnsteuer, 15 % je Firma und Monat) bleibt als Grundrauschen; der Bürgermeister kann gezielt zusätzlich prüfen.
2. **Straßenzustand wirkt spürbar, aber mild**: schlechte Straßen machen langsamer und erhöhen das Pannenrisiko leicht.
3. Städtische Aufträge teilt der Bürgermeister zunächst **nach Ruf, Zuverlässigkeit und Preis zu** (Ausschreibung/Rahmenvertrag/Direktvergabe); eigenes Bieten der Firmen ist ein späterer Ausbau.

Grundregeln: Alle Eingriffe haben **harte Grenzen** (Budget, Kapazität, Sperrfristen), sind **protokolliert** und für Spieler **sichtbar**. Ein Sprachmodell wählt nur zwischen gültigen Optionen; die Engine prüft jede Aktion.

## Etappen

| # | Inhalt | Stand |
|---|---|---|
| 1 | **Rathaus mit Personal**: sichtbares Gebäude, Abteilungen (Verwaltung, Bauamt, Straßenmeisterei, Prüfdienst), Einstellen/Entlassen durch den Bürgermeister, Kapazität je Abteilung, Gehälter aus der Stadtkasse, Anzeige im HUD | in Arbeit |
| 2 | **Prüfungen**: Aktion `order_inspection {Firma, Art}` (Lohnsteuer, Arbeitssicherheit, Gewerbe, Fahrzeuge), Kapazität des Prüfdienstes, Sperrfrist je Firma, Befunde mit Auflagen und Bußgeld, Fehlverdacht kostet Zustimmung | offen |
| 3 | **Städtischer Auftragspool**: Freigabe, Priorität, Preisrahmen und Vergabeart (Ausschreibung, Rahmenvertrag, Direktvergabe) für die Transportaufträge des Stadtlagers; Anteilsgrenze je Firma, Protokoll, Beschwerde; die Aufträge erscheinen in den Spielerbeobachtungen | offen |
| 4 | **Straßenwartung und Bautrupps**: Zustand je Straßenstück (Verkehr, Frost, Regen), Wirkung auf Tempo und Pannen, Eigenleistung der Straßenmeisterei oder Auftrag an eine Baufirma, sichtbare Bautrupps mit Absperrung | offen |

## Etappe 1: Entwurf

- **Gebäude**: Typ `townhall` (Rolle `town_hall`, Sprite `office1`, 3×3), nach dem Auffüllen der Bauplätze platziert (letzte Gebäude-ID, Zufallszustand danach wiederhergestellt), damit alle übrigen Gebäude, IDs und Namen pro Seed gleich bleiben. Fehlt ein Platz, gibt es kein Rathausgebäude, die Verwaltung arbeitet trotzdem.
- **Personal** sind Bürger mit Arbeitgeber `rathaus` (Lohn aus der Stadtkasse P0 über `Citizens`). Der Bürgermeister legt je Abteilung den **Soll-Bestand** fest. Besetzt wird zum Monatsende aus den Arbeitslosen (wie bei allen Arbeitgebern); Entlassungen ebenfalls zum Monatsende. Die Zufallsschwankung des Rathausbedarfs entfällt: der Bedarf ist der Soll-Bestand.
- **Abteilungen** (Startverteilung): Verwaltung 45 %, Bauamt 20 %, Straßenmeisterei 25 %, Prüfdienst 10 %. Die Zuordnung der Personen zu Abteilungen ist deterministisch (nach Bürger-ID, anteilig auf den tatsächlichen Bestand).
- **Kapazität**: Bauanträge: (Verwaltung + Bauamt) / 5,2 je Tag (bei Startverteilung gleich dem bisherigen Wert „Rathaus-Beschäftigte / 8“). Prüfdienst und Straßenmeisterei liefern die Kapazität für Etappe 2 und 4.
- **Aktionen** `hire_staff {abteilung, anzahl, reason}` und `dismiss_staff {abteilung, anzahl, reason}`. Grenzen: höchstens 5 je Aktion, mindestens 1 je Abteilung, höchstens 120 insgesamt; Einstellen nur, wenn die verfügbare Stadtkasse nach Abzug der Reserve mindestens sechs Monatsgehälter der neuen Kräfte deckt.
- **Beobachtung** `rathaus`: Gebäude, je Abteilung Soll/Ist/Kapazität, Monatskosten, offene Stellen. Die Regel-KI stellt bei langer Antragswarteschlange im Bauamt ein.
- **Anzeige**: Detailfenster des Bürgermeisters zeigt die Abteilungen und namentlich die Belegschaft.

## Grenzen / bewusst offen

- Das Rathaus erhält zunächst kein eigenes Sprite; Mitarbeiterfiguren am Gebäude und der Bautrupp kommen mit Etappe 4.
- Keine Gehaltsverhandlung, keine Krankheit/Erschöpfung der Verwaltungskräfte.
