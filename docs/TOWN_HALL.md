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
| 1 | **Rathaus mit Personal**: sichtbares Gebäude, Abteilungen (Verwaltung, Bauamt, Straßenmeisterei, Prüfdienst), Einstellen/Entlassen durch den Bürgermeister, Kapazität je Abteilung, Gehälter aus der Stadtkasse, Anzeige im HUD | fertig (03.11.2026) |
| 2 | **Prüfungen**: Aktion `order_inspection {Firma, Art}` (Lohnsteuer, Arbeitssicherheit, Gewerbe, Fahrzeuge), Kapazität des Prüfdienstes, Sperrfrist je Firma, Befunde mit Auflagen und Bußgeld, Fehlverdacht kostet Zustimmung | fertig (04.11.2026): `scripts/economy/inspections.gd`, `test_inspections` |
| 3 | **Städtischer Auftragspool**: Freigabe, Priorität, Preisrahmen und Vergabeart (Ausschreibung, Rahmenvertrag, Direktvergabe) für die Transportaufträge des Stadtlagers; Anteilsgrenze je Firma, Protokoll, Beschwerde; die Aufträge erscheinen in den Spielerbeobachtungen | fertig (04.11.2026): Pool im `CityDepot`, Aktion `set_city_freight`, `test_city_freight_pool` |
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

## Etappe 2: Prüfungen (Umsetzung)

- **Aktion** `order_inspection {firma, art, reason}`; Arten `lohnsteuer` (offene Ertragsteuer über die vorhandene Steuerprüfung, dazu nicht gezahlte Löhne mit 10 % Zuschlag), `arbeitssicherheit` (Beschäftigte mit Ermüdung ab 90 oder Gesundheit unter 50: 300 EUR je Person), `fahrzeuge` (Zustand unter 40 %: 400 EUR je Fahrzeug). Eine eigene Art „Gewerbe“ gibt es nicht; Lohnrückstände gehören zur Lohnsteuerprüfung.
- **Grenzen**: 2 Prüfungen je Prüfer und Monat, Sperrfrist 10 Spieltage je Firma, Bußgeld höchstens das Bargeld (Buchung `fines` an die Stadtkasse). Prüfung ohne Befund: −1,5 Punkte Zustimmung.
- **Sichtbarkeit**: Ereignisprotokoll der Firma, Kartenaktivität am Betriebshof, Liste der letzten Prüfungen in `obs.pruefungen`.
- **Beobachtung** des Bürgermeisters: nur öffentlich sichtbare Auffälligkeiten je Firma (mittlerer Fahrzeugzustand, erschöpfte Beschäftigte, Tage seit der letzten Prüfung), keine Akteneinsicht. Die Regel-KI prüft bei Fahrzeugzustand unter 50 % oder mindestens zwei Erschöpften, höchstens eine Prüfung je Runde.
- Die monatliche Zufallsprüfung der Ertragsteuer (15 %) bleibt unverändert.

## Etappe 3: Städtischer Auftragspool (Umsetzung)

- **Aktion** `set_city_freight {vergabe, firma?, tage?, preisfaktor?, eilig?, reason}` für die Transportaufträge des Stadtlagers. Die **Freigabe** der Beschaffung bleibt `approve_procurement`.
- **Vergabearten**: `ausschreibung` (offen für alle, wie bisher), `rahmenvertrag` (für 5–60 Tage erhält die Firma bei jedem neuen Auftrag einen Tag Vorrecht, danach ist er offen), `direktvergabe` (nur der nächste Auftrag). Der Partner kennt den Auftrag sofort; die Bezeichnung nennt Vergabeart und Partner, die Exklusivität ist in den Spielerbeobachtungen sichtbar (`exklusiv_fuer_dich`).
- **Preisrahmen** 0,8–1,3 auf die Vergütung; **eilig** (Priorität) = +15 % und Frist 4 statt 6 Tage.
- **Grenzen**: Ruf mindestens 40; höchstens 50 % der Vergaben der letzten 30 Tage je Firma (ab 4 Vergaben). Wird die Grenze während eines Rahmenvertrags erreicht, geht der Auftrag offen raus und die Beschwerde der Mitbewerber steht im Protokoll. Nutzt der Partner sein Vorrecht zweimal nicht, wird der Rahmenvertrag gekündigt (Protokoll und Gedächtnis des Amtes).
- **Beobachtung** `stadtlager.transportpool`: Vergabeart, Partner, Laufzeit, Preisfaktor, Einsätze des Stadtfuhrparks in 30 Tagen, je Firma Ruf, Pünktlichkeit, erledigte Aufträge und Anteil.
- **Regel-KI**: frühestens 10 Tage nach der letzten Änderung; bei mindestens 4 Einsätzen des Stadtfuhrparks Rahmenvertrag (20 Tage) mit der pünktlichsten Firma (Ruf ≥ 60, mindestens 80 % pünktlich), bei 2 Einsätzen Vergütung +0,1, ohne Einsätze schrittweise zurück auf 1,0.
- **Grenze**: Firmen bieten nicht selbst auf Stadtaufträge (späterer Ausbau laut Annahme 3).
