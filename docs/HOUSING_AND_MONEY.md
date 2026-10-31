# Entwurf: Auftrag 6 (Bewohner, Wohnen, private Kredite) und Rest von Auftrag 4 (Zentralbank, Geldschöpfung)

Status: **ENTWURF zur Freigabe** (31.10.2026). Der Wortlaut der beiden Aufträge liegt nicht im Repo; dieser Entwurf stammt aus den
Stichworten der Auftragswarteschlange und dem vorhandenen Code. Nach Freigabe wird er Etappe für Etappe umgesetzt, jede Etappe mit Tests,
Konservierungsprüfung (`Economy.conservation_error() == 0`) und Eintrag im Abschnitt „Stand“ unten.

## Ausgangslage im Code
- `Households` (`households.gd`): ein Haushalt je Mitarbeiter einer Firma, feste Adresse, Lebenshaltungskosten, Defizit, Motivation. Keine Wohnung, keine Miete.
- `Citizens` (`citizens.gd`): 1200 Einwohner mit Arbeitgeber; keine Wohnung, keine Zufriedenheit.
- `Banking` (`banking.gd`): Firmenkredite, Einlagen, Baukredite für Haushalte (`mortgage_*`); Kreditpoolmodell mit Mindestreserve 15 %.
- Gebäude und Mehrfamilienhäuser mit Vermietung entstehen in `Construction`; Mieteinnahmen gehen heute an den Bauherrn, ohne Mieter.

## Teil A – Auftrag 6: Bewohner und Wohnen
**A1 Wohnungsbestand.** Jedes Wohngebäude (`Parcels`/`Construction`) erhält Wohneinheiten (Größe, Zustand, Kaltmiete, Eigentümer-Konto). Startbestand: so viele Einheiten, dass alle 1200 Bürger und alle Firmenhaushalte untergebracht sind (kleiner Leerstand ca. 4 %).
**A2 Mietverhältnis.** Haushalt/Bürger ↔ Wohneinheit: Miete monatlich von H0 an den Eigentümer (Konto), Kündigung, Umzug bei Arbeitsplatzwechsel oder Zahlungsverzug, Räumung nach 3 offenen Monaten (Eintrag in Ereignisse). Mietspiegel je Viertel aus Angebot und Nachfrage; Anpassung höchstens 5 % je Jahr.
**A3 Wohnungsmarkt.** Suchende Haushalte vergleichen Angebote nach Miete im Verhältnis zum Einkommen (Obergrenze 40 %), Weg zur Arbeit, Zustand. Wohnungsmangel hebt Mieten und löst Bauanträge der Bauträger aus (Anschluss an `MayorBrain`/`Developer`).
**A4 Private Kredite.** Konsumkredit und Überziehung für Haushalte über `Banking` (Aufschlag auf Referenzzins, Obergrenze Rate ≤ 40 % Einkommen, Bonität aus Zahlungshistorie); Ausfälle belasten die Bank (`losses`), Privatinsolvenz-Light: Pfändung bis zur Pfändungsfreigrenze. Baukredite (`mortgage_*`) bleiben bestehen; Unternehmen als Bauherren erhalten Bankkredit wie andere Firmenkredite (Anschluss an `quote`/`grant`).
**A5 Zufriedenheit.** Index 0–100 je Haushalt aus Wohnung (Zustand, Miete/Einkommen), Arbeit (Motivation, Arbeitslosigkeit), Versorgung (Läden, Müll), Verkehr (Engpässe), Wetter. Folgen: niedrige Zufriedenheit senkt Konsum und Motivation, erhöht Wegzug; Stadtmittel im Reiter Lage.
**A6 Planungshilfen für die KI.** Beobachtung (`ObservationBuilder`) um Wohnungsmarkt (Leerstand, Mietspiegel, Zufriedenheit je Viertel) erweitern; für Bürgermeister/Bauträger Kennzahlen „Wohnungsbedarf“ und „Zahlungsfähigkeit“. **Berührt `scripts/ai`**: dort arbeitet laut Notiz eine andere KI – nur ergänzende Felder, vorher Dateien neu lesen.
**A7 Oberfläche und Abnahme.** Ansicht „Wohnen“ im Reiter Wirtschaft (Leerstand, Mieten, Zufriedenheit, Zwangsräumungen). Abnahmetest: Neubau → Vermietung → Einzug → Mietzahlung → Zahlungsverzug → Räumung → Konten stimmen.

## Teil B – Rest von Auftrag 4: Zentralbank und Geldschöpfung
**B1 Bankbilanz.** Je Bank Aktiva (Kredite, Reserven, Wertpapiere) und Passiva (Einlagen, Eigenkapital, Zentralbankkredit); Kredit buchen = Einlage schaffen. Heute ist das ein Kreditpool mit Mindestreserve; Umstellung so, dass `Economy.conservation_error()` weiterhin 0 meldet (Geldmenge wird als Summe der Sichtguthaben geführt, Kreditschöpfung als bilanzielle Verlängerung, nicht als Einzahlung von außen).
**B2 Zentralbank.** Konto `Z0`: Leitzins ersetzt `ref_rate`, Refinanzierung der Banken gegen Sicherheiten, Mindestreserve, Notfallliquidität bei Bank-Run. Regel nach Inflation und Geldmengenwachstum (Taylor-artig, Schritt ±0,25 Punkte monatlich).
**B3 Geldmengenkennzahlen.** M1 (Sichtguthaben), Kreditvolumen, Verschuldung der Haushalte/Unternehmen, Preisindex aus Warenkorb (`CityGoods`), Inflationsrate.
**B4 Wirtschaftslabor.** Ansicht/Skript, das Parameter (Reservequote, Zinsregel, Steuersätze, Kreditobergrenzen) variiert und Kennzahlen aus B3 über mehrere Seeds aufzeichnet (Weiterentwicklung von `tests/probe_city_cash.gd`, mit kürzerer Laufzeit).
**B5 Gewerbeaufsicht und Einsätze.** Aufsicht für Betriebe (Auflagen, Prüfung, Bußgeld nach Muster der Steuerprüfung in `public_sector.gd`), Einsätze der Öffentlichen Hand bei Ereignissen (Unfall, Brand, Sturm) aus dem Ressort-Budget.
**B6 Stadtviertel-Entwicklung.** Viertel mit Nachfrage-/Mietwirkung aus Zufriedenheit und Gebäudezustand (verbindet A5 mit `building_care.gd`).

## Reihenfolge und Abhängigkeiten
A1 → A2 → A3 → A7 (Wohnen ohne Kredit lauffähig) · A4 (braucht A2) · A5 (braucht A2/A3) · A6 (braucht A3/A5) · dann B1 → B2 → B3 → B4 · B5 und B6 unabhängig danach.
Offene Entscheidungen (Annahmen, bitte bestätigen oder ändern): Miete 40 % des Einkommens als Obergrenze; Räumung nach 3 Monaten; Leerstand 4 % als Startwert; Zentralbankkonto `Z0` als neuer Sektor.

## Stand
Noch nichts umgesetzt.
