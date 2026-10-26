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
- Nächste Etappe: 2 Planungsregelwerk und Bauantrag.
