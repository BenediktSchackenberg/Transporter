# Auftrag 7 – Stadtentwicklung, Bauunternehmen, Bürgermeister-KI

Auftragstext von Benedikt (26.10.2026), hier festgehalten, damit er nicht erneut verloren geht. Umsetzungsstand steht unten.

**Ziel:** Eine Stadt, die durch Entscheidungen ihrer Bewohner, Unternehmen und gewählten Verwaltung räumlich wächst. Jede neue Straße und jedes neue Gebäude benötigt Grundstück, Planung, Finanzierung, Material, Arbeit und Zeit. Verbunden mit Banken, Haushalten, Materiallieferungen, Lagerarbeit, Beschäftigung, Verkehr, Steuern und jährlichen Wahlen.

## 1. Spielfeld vergrößern
- Vorhandene Kartengröße prüfen, nutzbare Grundfläche im Standard auf mindestens das Vierfache (z. B. Breite und Höhe verdoppeln); technische Umsetzung an die Engine anpassen.
- Ergänzen: unbebaute Grundstücke in bestehenden Vierteln; große Entwicklungsflächen am Stadtrand; neue Wohngebiete; Gewerbe- und Industrieflächen; Flächen für öffentliche Einrichtungen; Grünflächen und Landschaft; reservierte Korridore für Straßen und Versorgungsleitungen.
- Unbebaute Reserve: konfigurierbar, Ausgangswert etwa 25–40 % der grundsätzlich bebaubaren Flächen.
- Abwechslungsreiche Quartiere und Grundstücksgrößen, keine Wiederholung identischer Blöcke.
- Bestehende Grundstücke, Personen, Gebäude behalten ihre Identitäten; alte Spielstände brauchen nachvollziehbare Erweiterung/Migration.

## 2. Grundstücke als Wirtschaftsobjekte
- Eindeutige ID, feste Fläche und Geometrie, Eigentümer und ggf. Nutzungsberechtigte, aktuelle Nutzung, zulässige Bebauung, Kauf-/Pachtbedingungen, Erschließungszustand, Reservierungen, zugehörige Anträge und Bauprojekte.
- Zustände mindestens: frei und verfügbar · reserviert · privat gehalten · zur Entwicklung vorgesehen · genehmigt · in Erschließung · im Bau · bebaut.
- Nie gleichzeitig an mehrere Bauherren vergeben. Eigentum, Pacht und sonstige Nutzungsrechte eindeutig unterscheiden. Die Stadt darf private Rechte nicht per KI-Aktion löschen.

## 3. Bauherren und Bauunternehmen trennen
- Bauherren: einzelner Bewohner, Haushalt, bestehendes Unternehmen, Immobilienunternehmen, Stadtverwaltung. Privatfinanzen eines Arbeitnehmers bleiben vom Arbeitgeber getrennt.
- Baufirma = eigenständiges Unternehmen (Ausführung). Mehrere Baufirmen mit unterschiedlichen Kapazitäten, Qualifikationen, Preisen, Bauzeiten, Qualitätswerten, Zuverlässigkeitsverläufen, Geräten.
- Spielerunternehmen können nach Voraussetzungen eine Bauabteilung eröffnen oder in eine Baufirma investieren. Zusätzliche Baufirmen zählen nicht als weitere Transportspieler.

## 4. Bürgermeister-KI
- Eigene Rolle, Zugriff auf relevante Stadtinformationen, eigenes Gedächtnis, Modell, eigener API-Key (oder globaler Zugang mit getrenntem Kontext), Anfrage- und Tokenbudget.
- Kann selbstständig: Entwicklungsbedarf erkennen; Quartiere vorschlagen; Grundstücke zur Vergabe vorbereiten; Erschließung planen; Bauanträge bearbeiten lassen; Straßenprojekte priorisieren; öffentliche Aufträge ausschreiben; Finanzierungsbedarf bewerten.
- Große Vorhaben beachten Haushalts- und Parlamentsregeln. Die Engine prüft Zuständigkeit, Budget, Flächenverfügbarkeit, zulässige Aktionen. Kein unbegrenzter Welteditor.

## 5. Bedarfsableitung (Daten für die Bürgermeister-KI)
Bevölkerungsentwicklung, Wohnungsauslastung/Leerstand, wohnungssuchende Haushalte, Mietniveau/Bezahlbarkeit, Beschäftigung/Arbeitskräftebedarf, Gewerbeflächennachfrage, Verkehrsbelastung, Versorgungsreichweite, Infrastrukturkapazitäten, Haushaltslage/Verschuldung. Abwägungen: Lücken schließen oder neues Quartier; Einfamilien- oder Mehrfamilienhäuser; Wohnen nahe Arbeitsplätzen; erst Straßenkapazität oder Nachfrage beobachten; öffentliche Einrichtung erweitern. Eine Ausweisung allein baut nichts: Vergabe, Finanzierung, Entwicklung folgen.

## 6. Bauplanungsregelwerk
Je Entwicklungsgebiet: zulässige Nutzungen, Gebäudegrößen/Geschosse, Freiflächen, Straßen- und Lieferzugänge, Versorgungsanforderungen, Einschränkungen, Gebühren und Erschließungsbeiträge. Transparent, in Oberfläche und für die KI zugänglich; Bauherr kann vor dem Antrag die Eignung abschätzen.

## 7. Bauantragsprozess
- Bauherr wählt Grundstück und Gebäudedefinition. Antrag: Antragsteller, Grundstück, Gebäudeart, Grundfläche, Geschosse, Wohneinheiten/Betriebsflächen, Zugänge/Stellflächen, Erschließungsbedarf, Finanzierungskonzept, grobe Kosten/Zeit.
- Ablauf: Entwurf → Antrag → Prüfung → Rückfrage/Überarbeitung → Entscheidung → Genehmigung mit Bedingungen oder Ablehnung.
- Ergebnisse: genehmigt · genehmigt unter Bedingungen · Überarbeitung erforderlich · abgelehnt mit benannten fehlenden Voraussetzungen. Begründung nachvollziehbar.
- Bearbeitung braucht Verwaltungskapazität und Zeit; Warteschlange, Bearbeitungsstand, offene Fragen anzeigen. Sympathie ersetzt keine Prüfung.

## 8. Erschließung
- Mindestens: Straßen-/Fußwegzugang, Strom, Wasser, Entwässerung/Abwasser. Vereinfachtes, kapazitätsbegrenztes Versorgungsmodell.
- Erschließung braucht Planung, Finanzierung, Material, Arbeitskräfte, Geräte, Bauzeit. Material aus kommunalem Lager oder nach vorhandenem Beschaffungsprozess.
- Provisorische Baustellenzufahrt muss tatsächlich hergestellt werden. Genehmigung kann an geplante Erschließung gebunden sein; Nutzung erst nach erfüllten Voraussetzungen.

## 9. Bauunternehmen als Betriebe
Geschäftskonto/Finanzierung, Mitarbeiter und Vorarbeiter, Qualifikationen, Geräte/Maschinen, Fahrzeuge oder beauftragte Transporte, Lager/Materialflächen, laufende Verträge, Löhne/Betriebskosten/Abgaben, verfügbare und belegte Kapazitäten. Rollen: Bauarbeiter, Vorarbeiter, Maschinenführer, Rohbau, Ausbau/Installation. Vorhandene Personen- und Arbeitsvertragssysteme nutzen. Maschinen kaufen oder mieten, mit Bedienpersonal, Betriebsmitteln, Wartung. Nicht beliebig viele Projekte gleichzeitig vollständig besetzen.

## 10. Angebote und Bauverträge
Mehrere Angebote einholen und vergleichen. Angebot: Leistungsumfang, Preis, Materialverantwortung, Beginn, Bauzeit, Zahlungsplan, Voraussetzungen, Verzögerungs-/Änderungsregeln, Nachbesserung. Günstigster ≠ bester (Kapazität, Zuverlässigkeit, Qualität, Terminrisiko). Annahme = verbindlicher Vertrag. Vom Bauherrn gestelltes Material wird nicht nochmals als Beschaffung der Baufirma berechnet.

## 11. Finanzierung
Trennen: Eigenmittel · Kredit · Fördermittel · reserviertes Projektbudget · bezahlte Leistungen · offene Verpflichtungen. Auszahlungen nach überprüfbaren Bauabschnitten. Unverbindliche Kreditanfrage ≠ gesicherte Finanzierung. Gebäudewert ist kein ausgezahltes Geld; Gebäude, Schulden, Liquidität, Ertrag getrennt.

## 12. Bauphasen (sichtbar, kalibrierbar)
Vorbereitung (Vermessung, Markierung, Absperrung, Baustelleneinrichtung) · Erdarbeiten (Maschinen, Boden bewegen/abtransportieren) · Unterbau und Fundament · Tragwerk und Rohbau (schrittweise) · Dach · Gebäudehülle (Fenster, Türen, Fassade) · Installation (Leitungen, Technik) · Innenausbau · Außenanlagen (Wege, Zufahrten, Beleuchtung, Grün) · Prüfung und Übergabe (Mängel erfassen, Nutzung freigeben).
Je Phase definieren: Voraussetzungen, Materialmengen, Qualifikationen, Personalbedarf, Gerätebedarf, Arbeitsaufwand, Kosten, Abschlussbedingungen. Fehlendes Material/Personal/ungeeignete Bedingungen blockieren die Phase; andere zulässige Arbeiten laufen weiter.

## 13. Material- und Transportkreislauf
Artikelgruppen: Sand/Schotter, Betonbauteile, Stahl/Verbindungsmaterial, Ziegel/Holz, Dachmaterial, Glas/Fenster/Türen, Dämmung, Rohre/Kabel, Haustechnik, Ausbau-/Oberflächenmaterial, Pflaster/Außenbeleuchtung.
Ablauf: Bedarf ermitteln → Bestand prüfen → bestellen → reservieren → transportieren → entladen → am Bauplatz lagern → verarbeiten. Baustellen haben begrenzte Lager-/Entladekapazität (zu frühe/große Lieferungen verursachen Probleme). Transportfirmen erhalten echte Lieferaufträge; Rücktransporte (Verpackung, Geräte, verwertbares Material).

## 14. Fertigstellung, Wohnungen, Nutzung
Einfamilienhäuser, Doppelhäuser, Mehrfamilienhäuser, Wohn-/Gewerbemischung, Büros, Lager/Werkstätten, öffentliche Gebäude. Gebäudedefinition legt Grundfläche, Bauphasen, Nutzung fest. Mehrfamilienhaus: Wohnungen mit eigenen IDs, Kapazität, Ausstattung, Mietbedingungen. Nach Übergabe: Einzug, Vermietung, Flächenbezug, Betrieb öffentlicher Leistungen; Einzug erzeugt Umzugs-, Möbel-, Versorgungsaufträge. Bestehende Haushalts-, Miet-, Instandhaltungssimulation übernimmt den Betrieb.

## 15. Verzögerungen, Mängel, Insolvenzen
Materialmangel, Personalausfall, Maschinenprobleme, Finanzierungsengpässe, Änderungswünsche, Wetter (definierte Regeln), Qualitätsmängel, Ausfall einer Baufirma. Ursachen und Verantwortlichkeiten zuordnen. Bei Insolvenz bleibt die Baustelle bestehen; erbrachte Leistungen, offene Forderungen, Materialeigentum korrekt erfassen; anderer Betrieb kann per neuem Vertrag übernehmen; bezahlte Leistungen nicht erneut als unbezahlt behandeln.

## 16. Oberfläche
Kartenebenen: freie Grundstücke, Eigentum/Nutzungsrechte, zulässige Bebauung, Erschließungszustand, Anträge, Bauprojekte, Versorgungs-/Verkehrsengpässe. Baustelle anklicken: Bauherr, Baufirma, Genehmigungsstatus, Finanzierung, Phase, Mitarbeiter, Materialbestand und erwartete Lieferungen, Fortschritt, Blockaden, prognostizierte Fertigstellung. Bürgermeisteransicht: Entwicklungspläne, Antragswarteschlangen, öffentliche Infrastrukturprojekte. Jede wichtige KI-Entscheidung mit kurzer Begründung, verbunden mit der tatsächlichen Ausführung.

## 17. Große Karte technisch
Kartenabschnitte und Detailstufen; nicht sichtbare Gebiete vereinfacht berechnen, Personen/Bestände/Projekte bleiben erhalten; beim Kamerawechsel werden keine Waren, Arbeitsleistungen oder Gebäude neu erzeugt. Miniatur-/Voxeloptik beibehalten; Bauphasen als Entwicklung desselben Gebäudes erkennbar.

## 18. Abnahme (zuerst diesen Ablauf vollständig)
1 Haushalt sucht Baugrundstück · 2 reserviert Fläche · 3 Bank prüft Finanzierung · 4 Bauantrag · 5 Bürgermeister-KI/Verwaltung entscheidet begründet · 6 Erschließung finanziert und hergestellt · 7 Angebote vergleichen, Baufirma beauftragen · 8 Material bestellt und von einem Spieler geliefert · 9 Mitarbeiter und Maschinen führen sichtbare Bauphasen aus · 10 Fortschritt und Zahlungen verbucht · 11 Prüfung und Übergabe · 12 Haushalt zieht ein. Danach: Mehrfamilienhaus mit mehreren Wohnungen und tatsächlicher Vermietung.

---

## Stand der Umsetzung
(wird laufend ergänzt)

- **Etappe 1 (Karte und Grundstücke) – fertig, 4589 Tests grün:**
  - Standardkarte 512×512 (`Catalog.MAP_SIZE`, vierfache Fläche). Kartenerzeugung von 14 s auf rund 3 s beschleunigt (Straßenzusammenhang nur zwischen den Enden eines entfernten Abschnitts prüfen, Fußnetz mit Feldern statt Dictionary).
  - Unbebaute Reserve: Jeder Block außerhalb des Zentrums bleibt mit Wahrscheinlichkeit `Catalog.RESERVE_TARGET` (0,19) frei; ergibt auf 512 etwa 30 % unbebaute, bebaubare Fläche (konfigurierbar 25–40 %). Alte Spielstände ohne `reserve` werden mit ihrer ursprünglichen Karte (ohne Reserve) neu aufgebaut.
  - `Parcels` (`scripts/world/parcels.gd`): Jedes Gebäude steht auf einem Grundstück (Identität bleibt); freie Flächen werden in Grundstücke unterschiedlicher Größe zerlegt, dazu Korridore für Straßen und Leitungen und Grünflächen. Zonen Wohnen, Mischgebiet, Gewerbe, Industrie, öffentlich, Grün, Korridor mit Regeln (Nutzungen, Geschosse, Anteil, Preis). Zustände: frei, reserviert, privat gehalten, zur Entwicklung, genehmigt, in Erschließung, im Bau, bebaut. Erschließungszustand (Straße, Strom, Wasser, Abwasser) aus der Nähe zur Bebauung.
  - Eigentum getrennt von Rechten (`owner`, `rights`); Reservierung (ein Bewerber, läuft nach 14 Tagen ab), Kauf durch Haushalte (Preis an die Stadt, Geld bleibt erhalten); die Stadt kann nur über eigene, freie Flächen verfügen (`city_can_assign`). Gespeichert werden nur Änderungen (`touched`); ältere Spielstände bekommen die Grundstücke aus ihrer Karte. Neue Gebäude zur Laufzeit werden ihrem Grundstück zugeordnet.
  - Oberfläche: Ansicht „Grundstücke“ im Reiter Wirtschaft.
  - Leistung bei 512: Fußgänger ruhen außerhalb des Bildes, Beschriftungen nur im Bild und bei lesbarem Zoom, Kundenliste höchstens alle 0,3 s. Entitäten 25 → 4 ms je Bild. Bei vollständig herausgezoomter Karte bleiben die Draw-Calls hoch (siehe Abschnitt 17, Detailstufen noch offen).
  - Noch offen in Etappe 1: Kartenebenen in der Oberfläche (Abschnitt 16), Unternehmen als Käufer (braucht Grundstückswert in der Bilanz), Quartiere mit eigenem Charakter jenseits von Zone und Größe.
- **Etappe 2 (Planungsregelwerk und Bauantrag) – fertig, 4620 Tests grün:**
  - `Planning` (`scripts/core/planning.gd`): 7 Gebäudedefinitionen (Einfamilienhaus, Doppelhaus, Mehrfamilienhaus, Wohn- und Geschäftshaus, Bürogebäude, Lager/Werkstatt, öffentliches Gebäude) mit Grundfläche, Geschossen, Einheiten, Kosten, Bauzeit, Stellplätzen. Regeln je Zone: zulässige Nutzungen, Geschosse, Bebauungsanteil, Freifläche, benötigte Anschlüsse, Lieferzugang, Gebühren, Erschließungsbeitrag. `Planning.assess` ist die Vorprüfung vor dem Antrag (Ergebnis: Ablehnungsgründe, behebbare Rückfragen, Auflagen, Kosten, Bauzeit, fehlende Anschlüsse); `Planning.explain` macht sie lesbar.
  - `Permits` (`scripts/economy/permits.gd`): Entwurf → Antrag → Prüfung → Rückfrage/Überarbeitung → Entscheidung. Ergebnisse: genehmigt, genehmigt mit Bedingungen, Überarbeitung erforderlich, abgelehnt, jeweils mit Begründung. Bearbeitung kostet Verwaltungskapazität (Rathaus-Beschäftigte ÷ 8 = Punkte je Tag), Warteschlange mit voraussichtlichem Entscheidungstag. Gebühr erst bei Genehmigung (Haushalt oder Unternehmen → Stadt). Unverbindliche Kreditanfrage zählt nicht als Finanzierung. Rechte am Grundstück (Eigentum oder Reservierung) werden bei Antrag und Entscheidung geprüft; Genehmigung gilt 180 Tage. Große Vorhaben (über 6 Einheiten oder 400 000 Gesamtkosten) gehen zur Bürgermeisterebene; ohne angebundene Bürgermeister-KI entscheidet nach 2 Tagen die Verwaltung stellvertretend (`Permits.mayor_attached`).
  - Oberfläche: Ansicht „Bauanträge“ (Warteschlange, Rückfragen, Entscheidungen, Regeln je Zone).
  - Noch offen: Planungsinformationen in der KI-Beobachtung (kommt mit der Bürgermeister-Rolle), Anträge von Unternehmen über KI-Aktionen, Verknüpfung der Auflagen mit der tatsächlichen Erschließung (Etappe 5).
- **Etappe 3 (Bürgermeister als Rolle) – fertig, 4665 Tests grün:**
  - `Mayor` (`scripts/core/mayor.gd`): eigene Rolle mit Name, Partei, Zustimmung, Gedächtnis (Notizen), Entscheidungsprotokoll (Begründung + tatsächliche Ausführung + Verweis), Plänen (Quartiere) und Projekten (Erschließung, Straße). Beobachtung `indicators()` mit Bevölkerung, Wohnungsmarkt (Bestand, Leerstand, wohnungssuchende Haushalte, Mietindex, Bezahlbarkeit), Beschäftigung und offenen Stellen, Gewerbeflächen, Verkehr, Versorgung, Haushaltslage (Kasse, reservierte und verfügbare Mittel), Antragswarteschlange mit Vorprüfung, Entwicklungsvorschläge (Gruppen städtischer Grundstücke mit IDs) und Planungsregeln.
  - Aktionen (`Mayor.SCHEMA`, von der Engine geprüft): designate_quarter, offer_parcels, plan_infrastructure, prioritize_road, tender, assess_financing, decide_application, remember, wait. Zuständigkeit: nur städtische Grundstücke ohne Rechte Dritter. Budget: verfügbar = Kasse − Reserve 100 000 − reservierte Mittel. Bauanträge: Genehmigung nie gegen benannte Mängel, Ablehnung nur wegen benannter fehlender Voraussetzungen, höchstens 2 Rückfragen.
  - `Council` (`scripts/core/council.gd`): Gemeinderat mit drei Fraktionen (Wachstum, Soziales, Haushalt, je 3 Sitze, Mehrheit 5 von 9); Ratsbeschluss für Quartiere und alles über 30 000 EUR, mit begründeter Abstimmung je Fraktion.
  - Wohnungsmarkt: Bestand startet mit 3 % Leerstand; jeden Monat suchen neue Haushalte eine Wohnung (abhängig von der Beschäftigung), Wartende ziehen bei Leerstand ein (Zuzug von Bürgern), lange Wartende wandern ab. Neue Einheiten kommen aus Bauprojekten (Etappe 6).
  - Jährliche Wahl: Zustimmung aus Beschäftigung, Wartenden, Kasse, Antragsstau und beschlossenen Plänen; unter 45 % wird ein Nachfolger mit anderer Partei gewählt, Akten und Gedächtnis bleiben.
  - `MayorAgent` (`scripts/ai/mayor_agent.gd`): eigener Kontext, eigenes Modell/Schlüssel/Anfrage- und Tokenbudget (`mayor` in der Konfiguration; `provider: global` nutzt den Zugang des ersten Spielers mit getrenntem Kontext; Standard `demo` = regelbasiert). Ersatzmodus bei API-Störung oder erschöpftem Budget. `MayorBrain` entscheidet über dieselbe Beobachtung und dieselben Aktionen wie ein Modell.
  - Oberfläche: Ansicht „Bürgermeister“ im Reiter Wirtschaft; Autotest-Zeile „Stadtentwicklung“.
  - Gleichzeitig behoben: In `EntityView` konnte die zwischengespeicherte Kundenliste Figuren enthalten, die inzwischen ruhig waren, und warf jeden Frame einen Fehler (Regression aus Etappe 1).
  - Noch offen: Einstellung des Bürgermeister-Zugangs im Startmenü (bisher Konfigurationsdatei), automatisches Bauherrenverhalten der Haushalte (Grundstückssuche, Antrag), Ausführung der Erschließungs- und Straßenprojekte und Ausschreibungen (Etappen 4 und 5).
- Nächste Etappe: 4 Baufirmen als Betriebe, Angebote und Bauverträge.
- **Etappen 4-6 (Baufirmen, Angebote, Verträge, Erschließung, Bauphasen, Finanzierung, Übergabe, Einzug) – umgesetzt:**
  - `Construction` (`scripts/economy/construction.gd`): drei Baufirmen (Preis, Bauzeit, Qualität, Zuverlässigkeit, Kapazität), Angebote mit Bewertung (günstigster ≠ bester), verbindlicher Vertrag mit zurückgelegten Mitteln, Erschließung vor dem Bau, zehn Bauphasen mit Zahlungsplan (8 % bei Übergabe), Material je Phase vom Bauhof (Lieferauftrag; Spieler können ihn annehmen und erhalten Frachtlohn, sonst liefert der Bauhof nach 2 Tagen), Verzögerungsursachen (Material, Wetter, Personal, Auslastung, Anschluss, Finanzierung), Prüfung mit Mängeln, Übergabe (Gebäude entsteht auf dem Grundstück), Wohneinheiten mit IDs, Einzug des Bauherrn-Haushalts, Vermietung und Mieteinnahmen, Ausfall einer Baufirma mit Ersatzvertrag ohne doppelte Bezahlung.
  - Bauträger `D0` (Immobilienunternehmen, eigenes Kapital 140 000) baut bei Wohnungsnot selbstständig Mehrfamilienhäuser (Grundstück reservieren, Antrag, Vertrag, Bau, Vermietung).
  - Öffentliche Erschließung: Ausgeschriebene Bürgermeister-Projekte werden von Baufirmen ausgeführt, Anschlüsse am Grundstück gesetzt, reservierte Mittel gebucht.
  - Oberfläche: Ansicht „Bauvorhaben“ (Baufirmen, Baustellen mit Phase/Fortschritt/Blockaden/Prognose, offene Lieferaufträge). Konten `K0` (Baufirmen), `D0` (Bauträger).
  - Tests: `test_construction`, `test_developer_autopilot`.
  - Noch offen: sichtbare Bauphasen in der Grafik (Gerüst/Rohbau-Sprites), Baustelle anklicken, Kartenebenen, Maschinen und Mitarbeiter je Baufirma als einzelne Personen, Unternehmen als Bauherren, Kreditfinanzierung über Banken (hängt an Auftrag 6), KI-Aktionen für Spieler (`bau_lieferung`).
- **Etappe 7 (Teil): Baustellen sichtbar** – `SiteView` (`scripts/world/site_view.gd`) zeichnet Absperrung, Baugrube, Fundament, wachsenden Rohbau und Dach nach Bauphase; Klick auf die Baustelle zeigt Bauherr, Baufirma, Genehmigung, Finanzierung, Phase, Material, erwartete Lieferungen, Blockaden und Prognose. Sichtprüfung: `-- --autotest --scenario=site --site-phase=4 --screenshot=...`. 4711 Tests grün.
