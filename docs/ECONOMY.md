# Wirtschaftskreislauf – Entwurf und Spielregeln

Dieses Dokument beschreibt das vereinfachte Wirtschaftsmodell von „Pixel Transport Rivals“. Es ist zugleich die Referenz
für die Implementierung (Abschnitt „Stand“ am Ende) und die dokumentierte Regelgrundlage, die die Aufgabe verlangt.
Alle Zahlen sind Spielparameter (`scripts/core/catalog.gd`, `scripts/economy/*.gd`), keine Aussagen über reale Märkte.

## 1. Zeit
* **Logistikuhr** (`game_min`): unverändert. 1 Sim-Sekunde = 2 Spielminuten. Sie steuert Fahrten, Ladezeiten, Fristen,
  Tageslicht und Öffnungszeiten (Uhrzeit der Stadt).
* **Spielkalender** (`Calendar`): 1 Spieltag = `day_seconds` Sim-Sekunden (Standard 60 = 1 aktive Echtzeitminute bei 1×),
  1 Spielmonat = 30 Tage, 1 Spieljahr = 12 Monate. Er leitet sich aus `game_min` ab und steht bei Pause still (die Simulation
  steht dann ebenfalls). Alle Verträge, Raten, Zinsen, Mieten und Löhne richten sich nach dem Kalender.
* **Wetterzeit**: reale Uhrzeit, getrennt angezeigt (siehe `weather.gd`).
* Partiedauer: 4 h, 12 h, 24 h aktive Echtzeit oder Endlos (`duration_min` = 0).

## 2. Akteure und Konten
Jeder Akteur hat eine eindeutige ID und ein Konto (`Account` mit `Ledger`):
`C<uid>` Unternehmen · `B<n>` Banken · `T0` Großhändler (Bauhof) · `H0` Haushalte · `S0` Stadtwirtschaft (örtliche Betriebe als
Kunden und Lieferanten) · `P0` öffentliche Auftraggeber · `X0` Außenwirtschaft (Importe, Exporte, Zuflüsse) · `I0` Investorenpool ·
`M<uid>` Insolvenzmasse. Banken, Händler und Sektoren zählen nicht zu den max. vier Spielerunternehmen.

**Geldkonservierung:** Jede Zahlung bewegt Geld zwischen zwei Konten. Die Summe aller Kontostände (einschließlich `X0`) ist
konstant; `X0` ist der einzige Ort, an dem Geld in die Stadt hinein- oder aus ihr herausfließt, und führt Buch darüber
(Importe, Exporte, Investorenkapital, öffentliche Zuweisungen). Test: `test_money_conservation`.

**Bilanzidentität** jedes Akteurs (`Ledger.identity_error`):
`Bargeld + Anlagevermögen + Vorräte + Forderungen aus Krediten + Einlagen bei Banken − Schulden − Kundeneinlagen − Verbindlichkeiten
 = Startkapital + Kapitalzuführungen + Gewinn (+ Schuldenerlass)`.

Gewinnrechnung: Kreditaufnahme ist kein Ertrag, Tilgung kein Aufwand, Zinsen sind Aufwand beim Schuldner und Ertrag beim Gläubiger,
Kreditausfälle mindern die Forderung (Aufwand „Kreditverlust“). Ein Schuldenerlass erzeugt **keinen** Gewinn für die Rangliste.

## 3. Banken und Kredit
Drei Banken mit eigener Bilanz (Bargeld, Kredite, Kundeneinlagen, Eigenkapital), begrenztem Kreditangebot und Risikopolitik:

| Bank | Schwerpunkt | Laufzeit | Sicherheiten |
|---|---|---|---|
| Geschäftsbank | Betriebsmittel, kurzfristig | 1–12 Monate | auch ohne, kleine Beträge |
| Investitionsbank | Fahrzeuge, Gebäude, Maschinen | 6–60 Monate | Pflicht (Fahrzeug/Gebäude, ≥ 50 % Deckung) |
| Handelsbank | Warenfinanzierung, Geldanlagen | 1–6 Monate | Warenbestand/Fahrzeug, bessere Anlagezinsen |

**Finanzierungsmodell:** Ein Kredit wird aus dem *verfügbaren Bargeld der Bank* ausgezahlt:
`verfügbar = Bargeld − Mindestreserve (15 % der Kundeneinlagen)`. Geschäftskonten der Kunden (Bargeld der Firmen) sind **nicht**
Teil der Bankbilanz; nur ausdrücklich angelegte Einlagen (Tagesgeld/Festgeld) werden Kundeneinlagen. So bleiben Kundenguthaben,
freie Mittel und Eigenkapital getrennt. Einzelkreditgrenze: 25 % des Bankeigenkapitals. Ausfälle senken das Eigenkapital; fällt die
Quote, verschärft die Bank Margen und vergibt weniger.

**Referenzzinssatz** (`ref_rate`, nominaler Jahreszins): startet bei 3,5 % und passt sich monatlich langsam an Kreditauslastung und
Ausfälle an. Angebot = `Referenz + Bankmarge + Bonitätsaufschlag + Laufzeitaufschlag + Verschuldungsaufschlag + Ausfallhistorie
− Sicherheitenabschlag + Liquiditätsaufschlag`. Festzinsverträge behalten ihren Zins. Anzeige: nominaler Jahreszins und
monatliche Wirkung (Jahreszins/12) sowie Monatsrate.

**Tilgungsplan** (Annuität): feste Monatsrate `R = K·i / (1 − (1+i)^−n)` mit `i = Jahreszins/12`; Nullzins: `K/n`. Bei Vertragsschluss
entsteht der vollständige Plan (Zinsanteil, Tilgung, Restschuld je Rate), auf Cent gerundet; die letzte Rate gleicht Rundungsreste aus.
Fälligkeit am Monatswechsel (erste Rate im Folgemonat); Einzug automatisch, soweit Geld vorhanden. Fehlt Deckung, entsteht ein
dokumentierter Rückstand mit Verzugszuschlag (1 % der Rate); ab 3 offenen Raten gilt der Kredit als ausgefallen (Kündigung,
Sicherheitenverwertung). Vorzeitige Rückzahlung: Bank 1 % Gebühr auf die Restschuld, zwischen Spielern nach Vertrag.

**Spielerkredite:** Unternehmen können einander Geld leihen (`offer_loan` / `accept_loan`, Gegenangebote bis 3 Runden). Der Geber muss
das Geld besitzen; Auszahlung erst nach Annahme; gleicher Tilgungsplan; optional Sicherheit (Fahrzeug).

## 4. Geldanlage
`deposit_money`: **Tagesgeld** (täglich verfügbar, Zins = Referenz − 1,5 %, min. 0) oder **Festgeld** (Laufzeit 3–24 Monate,
Zins = Tagesgeldzins + Laufzeitbonus, aber stets ≤ Referenz − 0,5 %). Kreditzinsen liegen immer ≥ Referenz + 1 %, daher ist
Kreditaufnahme zum Anlegen nie profitabel. Zinsen zahlt die Bank aus ihrem Bargeld (mindert ihr Eigenkapital); reicht ihr Bargeld
nicht, zahlt sie verspätet und verliert Reputation. Festgeld ist bis zur Fälligkeit gebunden (vorzeitige Auflösung: Verlust der
Zinsen der laufenden Periode + 1 % Gebühr).

## 5. Unternehmensformen (Spielregeln)
| | Einzelunternehmen | UG | GmbH |
|---|---|---|---|
| Gründungskosten | 0 | 500 | 2 000 |
| Mindest-Eigenkapital | 0 | 1 | 25 000 |
| Verwaltung je Monat | 0 | 80 | 250 |
| Berichtspflicht | keine | jährlich | vierteljährlich |
| Kreditrahmen-Faktor | 0,8 | 1,0 | 1,2 |
| Externe Investoren | nein | ja | ja |
| Haftung | Gründer haftet mit Privatreserve (Verwertungsmasse + 15 000) | beschränkt | beschränkt |

Die Form garantiert keine Kreditwürdigkeit. Formwechsel: ≥ 3 Monate alt, keine Rückstände, Mindest-Eigenkapital der Zielform,
Kosten und 15 Tage Bearbeitung; Schulden und Verträge bleiben bestehen.

## 6. Insolvenz
`Aktiv → Liquiditätswarnung → Zahlungsverzug → Insolvenz → Verwertung → Geschlossen`
* *Liquiditätswarnung*: flüssige Mittel decken die in 30 Tagen fälligen Pflichten (Raten, Löhne, Mieten) nicht.
* *Zahlungsverzug*: eine fällige Zahlung konnte nicht geleistet werden. **Nachfrist 15 Tage.** Ausweg: Forderungen einziehen, Vermögen
  verkaufen, verbindliche Finanzierung (Auszahlung zählt, Angebote nicht), verbindlicher Zahlungsaufschub der Gläubiger, Investor.
* *Insolvenz*: Ein Insolvenzverwalter übernimmt. Aktionen des Unternehmers sind gesperrt, das Vermögen ist eingefroren; laufende
  Kundenaufträge werden geregelt abgebrochen und neu ausgeschrieben.
* *Verwertung*: Vermögensverzeichnis, **sichtbare Auktionen** (Fahrzeuge, Vorräte, Standort mit Gebäuden). Andere Unternehmen, der
  Händler und der Fahrzeughändler können bieten. Fremdes Gut (Kundenwaren, Mietfahrzeuge) gehört nicht zur Masse.
  Erlösverteilung: 1. Verwertungskosten (max. 10 % des Erlöses, mind. 200) → 2. gesicherte Forderungen aus *ihrer* Sicherheit →
  3. übrige Forderungen anteilig aus dem Rest. Reicht es nicht, tragen Banken/Gläubiger den Verlust (Ausfallquote wird angezeigt).
  Restschulden werden erlassen, **ohne** Gewinnbonus.
* *Geschlossen*: Mitarbeiter werden wieder verfügbar, der Platz (Grundstück) wird neu angeboten. Die Firma bleibt in der Historie.

## 7. Grundstücke, Neugründung
Grundstück: Eigentümer + Nutzer. Nach der Auflösung wird der Standort als Los versteigert (Grundstück + Gebäude). Findet sich ein
Bieter, übernimmt er den Standort mit Gebäuden; sonst wird geräumt (kostenpflichtig, Zeit) und als freies Baufeld angeboten.
Ein freier Platz wird nach Wartezeit von einem neuen KI-Unternehmer mit neuer Identität und Unternehmensform besetzt.
**Gründungskapital** stammt ausschließlich aus dem Investorenpool `I0` (Anfangsbestand begrenzt, monatlicher Zufluss von `X0`
klein und gedeckelt) – eine Insolvenz erzeugt keine unbegrenzte Geldquelle.

## 8. Großhändler und Bauhof
`T0` ist ein eigenständiger Akteur (regelbasiert, optional mit Sprachmodell) mit sichtbarem Bauhof, begrenzter Lagerkapazität,
Bargeld und Warenbestand. Er bestellt Waren aus `X0` (Import, Lieferzeit in Spieltagen, Transportauftrag Hafen → Bauhof wird
ausgeschrieben), kauft lokale Produkte an, verkauft Material (Mengenrabatt, Reservierung, Lieferung gegen Gebühr), exportiert
Überschüsse, betreibt Produktion und kann Kredite aufnehmen/Geld anlegen. Preis = Einkaufspreis × (1 + Marge) × Bestands- und
Nachfragefaktor + Transportaufwand.

## 9. Waren, Eigentum, Standort
Materialgruppen: Holz, Stahl, Ziegel, Betonbauteile, Glas, Installationsmaterial, Werkzeug, Gebäudemodule, Paletten,
Verbindungsmaterial, Rohmaterial, Altmaterial, Sekundärrohstoff. Jeder Bestand hat **Eigentümer** und **Standort**
(`StockBook`): „gekauft, liegt noch am Bauhof“ ist möglich. Jede Bewegung hat Herkunft und Grund (Import, Produktion, Rückbau,
Verwertung, Handel, Verbrauch).

Bauprojekte (Eigenbau) benötigen Material laut Stückliste am Bauplatz; es wird reserviert, transportiert, bereitgestellt und beim
Bau verbraucht. Baufirma (+40 %) liefert das Material selbst.

## 10. Produktion
Anlagen (Palettenwerk, Betonwerk, Modulwerk, Recycling) brauchen Rohstoffe im Standortlager, Personal, Betriebskosten und
Zeit; die Engine verbraucht Eingang und erzeugt Ausgang (kein Material aus dem Nichts).
Rezepte: Holz + Verbindungsmaterial → Paletten · Rohmaterial → Betonbauteile · Stahl + Betonbauteile → Gebäudemodul ·
Altmaterial → Sekundärrohstoff.

## 11. Haushalte, öffentliche Hand, Außenhandel
Löhne gehen an `H0` (monatlich), Haushalte konsumieren (→ `S0`, Importanteil → `X0`), `S0` zahlt Löhne an `H0`, `X0` zahlt
Exporterlöse an `S0` und Zuweisungen an `P0`. Aufträge der Kunden werden aus dem Budget des Zahlers **vorab reserviert**
(Escrow); fehlt das Budget, entsteht der Auftrag nicht. Importe, Exporte und externe Zuflüsse werden gesondert erfasst.

## 12. Ranglisten
Aktueller Führender, historische Etappensieger (bleiben erhalten, auch wenn die Firma später insolvent wird) und endgültiger
Sieger: aktives, zahlungsfähiges Unternehmen mit dem höchsten kumulierten Nettogewinn. Offene Verpflichtungen, Wertberichtigungen
und Insolvenzverluste werden ausgewiesen.

## Stand der Umsetzung
(wird laufend ergänzt)

- **M1 Kalender – fertig:** `GameCalendar`, Signale `day_changed`/`month_changed`, Kalenderlänge wird mit dem Spielstand gespeichert. Tests: `test_calendar`.
- **M2 Konten und Geldkonservierung – fertig:** `Economy` (Konten H0 Haushalte, P0 Öffentliche Hand, X0 Ausland, S0 Dienstleister, B0 Banken, C0 Verrechnung, I0 Kapitalgeber). Jede Barbewegung läuft über `Ledger._move` mit Gegenbuchung; Standardgegenkonto je Kategorie in `Economy.COUNTER`. Sektorkonten dürfen negativ werden (Sektor hat netto mehr gezahlt als erhalten). Der Test `identity_ok` prüft jetzt in allen Tests zusätzlich `Economy.conservation_error() == 0`. Kapital von außen nur über `Ledger.inject`.
- **M3 Banken, Kredit, Einlagen – fertig (Kreditpool-Variante):** `Banking` mit Geschäfts-, Investitions-, Handelsbank (Konten B1–B3), Referenzzins (monatliche Anpassung), Angebotszins aus Aufschlägen (`quote().parts`), Annuitätenplan auf Cent, Einzug am Monatswechsel, Rückstand mit Verzugszuschlag, Ausfall nach 3 offenen Raten, Pfandverwertung (Fahrzeug), vorzeitige Teiltilgung mit 1 % Gebühr und neuem Plan, Tages-/Festgeld. Aktionen `request_loan`, `repay_loan`, `deposit_money`, `withdraw_deposit`, `take_loan` (Kurzform); HUD-Reiter „Banken“; Beobachtung `bank`/`datum`. Verpfändete Fahrzeuge sind nicht verkäuflich. Kreditgrenze je Firma bleibt `Simulation.max_loan`. Tests: `test_banking`, `test_banking_default`.
- Behobener Altfehler: zur Laufzeit gebaute Gebäude (Neueröffnungen, Gewerbegebiet) wurden beim Laden nicht wiederhergestellt (`EventDirector.added_buildings`).
- **M4 Unternehmensformen – fertig:** `CompanyForms` (Einzel/UG/GmbH: Verwaltungskosten, Kreditrahmen-Faktor, Berichte als Logeinträge, Formwechsel ab 3 Monaten mit 15 Tagen Bearbeitung), Auswahl im Startmenü, Aktion `change_company_form`. Externe Investoren als Aktion fehlen noch.
- **M5 Insolvenz, Auktionen, Neugründung – fertig:** `Insolvency` mit Kette Aktiv → Warnung → Verzug (15 Tage Nachfrist) → Insolvenz (Verwalter, Aktionen gesperrt, Kundenaufträge neu ausgeschrieben, Personal frei) → Verwertung (sichtbare Auktionen für Fahrzeuge und Standort, Händler bietet 55 % Buchwert, Aktion `bid_auction`) → Verteilung (Kosten max. 10 %, gesicherte Forderungen aus ihrer Sicherheit, Rest anteilig, Einzelunternehmer haftet mit 15 000 aus `H0`, Restschulden ohne Gewinnbonus erlassen) → Geschlossen (Historie mit Ausfallquote) → Neugründung nach 10 Tagen mit neuer Identität aus dem Investorenpool `I0`. Reiter „Unternehmen“. Tests: `test_company_forms`, `test_insolvency`.
- **M6 Bauhof, Material, Produktion – fertig (Kern):** `StockBook` (Ware mit Eigentümer und Standort, Bilanz „entstanden − verbraucht = vorhanden“ wird in `identity_ok` geprüft), `Trader` (Konto T0: Import aus X0 mit Lieferzeit und Meldebestand, Produktion Paletten/Beton/Module/Recycling nach Rezept, Verkauf mit Bestandsfaktor und Mengenrabatt, Export von Überschuss, Ankauf von Altmaterial, Monatslöhne an H0). Eigenbau und Baufirma beziehen die Stückliste (`Trader.bom`) vom Bauhof: eigenes Material wird zuerst genutzt und nicht doppelt bezahlt, fehlendes geht per Transportauftrag Bauhof → Baustelle, beim Bau wird verbraucht, Rückbau liefert Altmaterial. Aktionen `buy_material`, `sell_material`; Reiter „Bauhof“. Nicht umgesetzt: Sprachmodell für den Bauhof, Bauhof-Kredite.
- **M7 Ranglisten – fertig:** `Standings` (Etappensieger je Spielmonat, Zeitreihen, Endsieger nur zahlungsfähig, Insolvenzverluste), Reiter „Rangliste“, Endauswertung mit Etappensiegern und Insolvenzen.
- Noch offen: Spielerkredite, Abschreibung von Restforderungen in der Insolvenz (`Banking.write_off` vorhanden, noch nicht angebunden), M4–M9.
