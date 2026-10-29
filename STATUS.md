# Umsetzungsstand

Stand: 25.10.2026. „Geprüft“ heißt: durch automatische Tests (`tests/run_tests.gd`) und/oder Autotest-Partien belegt.
Ein lokales Qwen-3.5-Modell wurde über Ollamas native API mit vollständigem Spiel-Prompt und gültigem Aktions-JSON getestet (Godot 4.7.2). Der aktuelle vollständige Headless-Lauf bestand 4374 Prüfungen ohne Testfehler.
Externe Sprachmodell-APIs wurden mangels Key nicht live getestet. Die übrigen Adaptertests nutzen den
DEMO-Adapter (regelbasiert, keine KI) oder den echten HTTP-Adapter gegen einen lokalen Mock-Server.

## Auftrag „Stadtleben, Wetter, Kunden, Grafik“ (25.10.2026)

| Bereich | Umsetzung | Geprüft |
|---|---|---|
| Wetteradapter Mainz (Open-Meteo), asynchron, 15-min-Takt, einmalige Standortsuche, Altersstatus, Ersatzwetter, Aufzeichnung/Wiederholung | `weather.gd`, `weather_service.gd` | 45 Unit-Tests, **echter Abruf** erfolgreich |
| Einheiten: Niederschlag je Messintervall → mm/h; Wetterzeit getrennt von Spielzeit und Partiedauer | `Weather.parse_forecast`, HUD-Wetterfeld, `Lage`-Reiter | Unit-Test |
| Wettereffekte (konfigurierbare Schwellen; Glätte nur bei Frost + Feuchtigkeit; Überdachung hilft; Wartung senkt Pannenrisiko) | `Weather.PARAMS`, `Simulation`, `Estate` | Unit-Tests + Screenshots |
| Sichtbares Wetter: Regen, Nässe, Pfützen, Schnee auf Dächern/Boden, Wind (Bäume, Fahnen, Laub), Nebel, Hitzeflimmern, Schirme, Nachtlicht | `city_view.gd`, Shader | Screenshots (Tag, Regen, Schnee, Nebel, Nacht) |
| Automatischer Ereignismanager mit Ursache, Abklingzeit, Schwerelimit, ruhiger Phase | `world_events.gd` | Unit-Tests, Langläufe (kein Spam) |
| Kundenfiguren mit Bedarf, echten Anfragen, Budgetlogik der Beschreibung, Sperrfrist, Eskalation | `residents.gd` | Unit-Test (komplette Kette bis zur Zufriedenheit), Speichern/Laden |
| Transparenz: Aktivitäten-, Lage- und Entscheidungsreiter mit Ursachenketten, erweiterte Unternehmenskarten | `live_text.gd`, `hud.gd` | Unit-Tests, Screenshots |
| Isometrische Voxelgrafik (Dimetrie 2:1, einheitlicher Renderer): 38 Gebäudetypen/-varianten, 20 Einrichtungen, 6 Fahrzeugmodelle × 4 Richtungen, Figuren (7 Posen × 4 Richtungen), Boden mit Straßenmarkierungen | `tools/vox/`, `tools/build_iso.py`, `assets/iso/` | Vollständigkeitstest (143 Prüfungen), Screenshots |
| Neue Gebäude: Schule, Kindergarten, Frachtterminal, Villa, Doppelhaus, Hochhaus | `city_generator.gd`, Lieferketten, Kundenprofile | Tests, Sichtprüfung |
| Tiefensortierung in Streifen, Klick auf das sichtbare Pixel, verdeckte Kunden behalten ihr Symbol | `iso.gd`, `entity_view.gd` | Geometrietests |
| Leistung: Kundentakt in Zeitscheiben, 4 Spieler bei 16× ≈ 17 ms je Bild | `residents.gd` | Messung im laufenden Spiel |
| Windows-Export | `build/PixelTransportRivals.exe` | Autotest mit der exportierten EXE |

**Bewusst nicht umgesetzt / Grenzen dieses Stands**
- Gebäude-Zustandsvarianten und Renovierung (Teil des Auftrags „Stadtviertel“) sowie Winterkleidung der Figuren fehlen.
- Ein- und Aussteigen der Fahrer wird nicht animiert; die Nahaufnahme „arbeitender Betriebshof“ wurde mit einem Testszenario (`--scenario=yard`) geprüft, in dem Bau und Reparatur laufen, aber nur wenige Arbeiter sichtbar sind.
- Die Aufträge „Wirtschaftskreislauf“ (Banken, Kredite, Insolvenz, Großhändler, Produktion), „Kraftstoffpreise, Löhne, Haushalte, Stadtviertel“ und „Öffentliche Hand, Steuern, Geldschöpfung“ sind **noch nicht umgesetzt**. Vorhanden sind nur der Entwurf (`docs/ECONOMY.md`), die Kalenderklasse `GameCalendar` (Spieltag/Monat/Jahr, im HUD angezeigt) und die Partiedauern 4 h/12 h/24 h/Endlos.
- Externe Sprachmodell-APIs wurden weiterhin nicht live getestet; das lokale Ollama-Modell wurde geprüft.

## Fertig

### Basisspiel (v0.1)
Stadt 256×256, 2–4 KI-Spieler, OpenAI-kompatibler Adapter, Demo-/Ersatzmodus, Gewinnwertung mit Bilanzidentität,
Handel, Sabotage (Ruf/Depot), Spielende nach aktiver Echtzeit (max. 240 min), Speichern/Laden, Windows-Export.

### Elemente aus der Version „KingGamer“
| Element | Geprüft |
|---|---|
| Pixel-Porträts der Unternehmer (Firmenkarten) | Screenshot |
| IONOS-Qwen-Profil (Herstellerparameter, kein response_format, `<think>`-Filter) | Unit-Test |
| Anbieterwahl pro Spieler: Ollama lokal ohne Key oder externe API mit eigener URL, Modell und Key | Unit-Test + lokaler Ollama-Smoke-Test |
| 12 konkrete Lieferketten (Brauerei → Restaurant: Bierfässer …), Klinik, Baustellen, Werft | Unit-Test |
| Jobbörse: nur gesammelte Aufträge sind sichtbar/annehmbar | Unit-Test |
| Büros (Zentrale + Filialen), Ausbaustufen, Internet 1/2, Auftragskapazität | Unit-Test |
| Besuchswarteschlange der Figur (bis 4 Besuche) | Unit-Test |
| Öffentliche Ansprache nur bei Begegnung (Funk/Rundruf immer) | Unit-Test |
| KI-Ziel (`goal`), besuchte Orte, Situationssprüche, Routenlinien, Bürofahnen, Stadtansicht [Tab], Lastenrad | Screenshot/Test |

### Arbeiter, Vorarbeiter, Ressourcen, Arbeiter-Sabotage
| Anforderung | Umsetzung | Geprüft |
|---|---|---|
| Arbeiter als sichtbare NPCs mit ID, Name, Arbeitgeber, Fähigkeiten, Lohn, Anwerbegebühr, Erfahrung, Zuverlässigkeit, Loyalität, Erschöpfung, Standort, Aufgabe | `Worker`, `Personnel` | Abnahmetest |
| Aufgaben als Objekte (Auftraggeber, Ausführender, Ziel, Priorität, Status zugewiesen → unterwegs → in Bearbeitung → abgeschlossen / blockiert / fehlgeschlagen / abgebrochen, Rückmeldung) | `WorkerTask` | Abnahmetest |
| Ein Arbeiter tut nur eine Sache; reine Wege sind unterbrechbar; Erschöpfte lehnen ab | `Personnel.can_take` | Abnahmetest |
| Fahrer steigen sichtbar ein; Fahrzeuge fahren nur mit Fahrer | Aufgabe `fahren` | Abnahmetest |
| Reparatur vor Ort (Mechaniker + Ersatzteile + Zeit), sonst Werkstatt/Abschleppen; liegengebliebene Fahrzeuge setzen nach Reparatur fort | `reparieren`, `break_vehicle`, `resume_vehicle` | Abnahmetest |
| Bewachen, Verladen (halbiert Ladezeit), Auskundschaften (Berichte), Unterstützen | Aufgabentypen | Code + Teiltests |
| Vorarbeiter: Kapazität, Standort, Kontrollreichweite, Befugnisse (Fahrer einteilen, Reparatur, Ersatz, Budget), Berichte nur aus eigenen Informationsquellen | `Personnel.foremen_tick` | Abnahmetest |
| Knappe Ressourcen an Orten: Arbeitskräfte (Personalbüro/Hafen/Werkstätten), Fahrzeugangebote (Händlerbestand), Treibstoff (Tankstellen), Ersatzteile (Werkstätten), Waren an Abholorten | `ResourceMarket`, Karte | Abnahmetest |
| Konflikte eindeutig: wer zuerst vor Ort ist, wirbt an/kauft; verkauft = weg; angenommene Aufträge verschwinden | Prüfung bei Ankunft | Abnahmetest |
| Arbeiter-Sabotage an gesichteten, stehenden Fremdfahrzeugen: Erfolg / Fehlschlag / erwischt; erwischt = Arbeiter dauerhaft verloren, Aufgaben beendet, nicht wieder anwerbbar | `attempt_vehicle_sabotage` | Abnahmetest |
| Wachen, Zeugen, Sicherheitsstufe, Erfahrung beeinflussen Entdeckung; Kosten + Abklingzeit + Zielschutz | `Personnel.sabotage_odds` | Abnahmetest |
| Spielanweisung „Du willst diese Partie gewinnen …“ im Systemprompt; Hinweis bei Untätigkeit | `AgentController` | Unit-Test |
| Personal-Reiter, Arbeiter anklickbar (Arbeitgeber, Aufgabe, Fortschritt, Status), Aufgaben-Symbole, Händlerbestand/Waren/Vorräte auf der Karte | HUD, EntityView | Screenshot (teilweise) |

### Strategische Steuerung – Stufe 1 (kombinierbare Aktionen, Pläne)
| Anforderung | Umsetzung | Geprüft |
|---|---|---|
| Teilmengen, Zwischenlager (`lager:<Depot>`, 60 Plätze), Umladen, Sammeltouren, Rückfahrten | `Logistics` (Stopp-Modell), `plan_tour`, `assign_transport` mit menge/von/nach | Unit-Test |
| Kapazität über ganze Tour, Reservierungen gegen Doppelverplanung, Bezahlung erst bei vollständiger Lieferung | `Logistics.validate` | Unit-Test |
| Fahrzeuge versetzen, Touren streichen | `move_vehicle`, `clear_tour` | Unit-Test |
| Strukturierter Plan (Ziel, Schritte, Abhängigkeiten, Mittel, Nutzen, Risiken, Abbruchbedingungen), Neuplanung bei entfallener Voraussetzung | `PlanBook`, `set_plan`/`execute_plan_step`/`update_plan_step`/`cancel_plan`, Antwortfeld `plan` | Unit-Test |
| Übersicht verfügbarer Aktionen mit gültigen IDs, Unbekanntes markiert | `verfuegbare_aktionen`, `unbekannt` | Unit-Test |
| Herkunft jeder Aktion (api/plan/fallback/…) | `ActionExecutor.execute(origin)` | Code |
| Fester Simulationsschritt + Schrittzähler (Grundlage für exakte Wiederholung) | `GameSession`, `Simulation.step_count` | Code |

### Strategische Steuerung – Stufen 2–5
| Anforderung | Umsetzung | Geprüft |
|---|---|---|
| Privates Gedächtnis: Ereignisse und Erfahrungen (Tatsache/Vermutung, Belege, Vertrauen), Relevanzauswahl, gespeichert, optional in die nächste Partie übernommen; Formulierung „erfahrungsbasierte Anpassung durch gespeicherten Kontext“ (keine Gewichtsänderung) | `MemoryBook`, `remember`/`forget`, `carry_memory` | Unit-Test |
| Ereignisregler für Zuschauer (Straßensperrung, Großauftrag, Treibstoffpreis, Arbeitskräftemangel, neues Gewerbegebiet, Nachfrageschub) mit Folgenbericht | `EventDirector`, Ereignis-Panel | Unit-Test |
| Entscheidungsprotokoll mit Herkunft (API/Plan/Vorarbeiter/Automatik/Zuschauer), Prüfergebnis, verknüpften IDs und später gemessenen Folgen | `DecisionLog`, Reiter „Entscheidungen“ | Unit-Test |
| Experimente mit echten Kosten (Vergleich in der laufenden Simulation) | `ExperimentBook` | Unit-Test |
| Verbindliche Verträge: Auftragsübertragung, Kapazitätsvermietung, Lagermitbenutzung, Teilung eines Großauftrags; Gegenangebote, Reservierungen, Vertragsstrafen, begrenzte Verhandlungsrunden | `Social` | Unit-Test |
| Delegation an Vorarbeiter: Ziel, Priorität (fristgerecht/kosten/auslastung), Budget, Befugnis Ersatzteile zu kaufen; Käufe als „Vorarbeiter“-Entscheidung protokolliert; Investitionen/Sabotage bleiben beim Unternehmer | `set_foreman_orders`, `foremen_tick` | Unit-Test |
| Veränderbare Infrastruktur (Ladeplätze, Zwischenlager, Werkstätten …) mit Standort, Geld, Arbeitskräften, Bauzeit und Anbindung | über den Betriebshof (siehe unten) | Abnahmetest |

### Grundstücke und Betriebshof (Auftrag „Grundstücke und Stadt“, Teil 1)
| Anforderung | Umsetzung | Geprüft |
|---|---|---|
| Gleich großes, leeres, kostenloses Startgrundstück (7×6 Tiles, offene Stellfläche für 2 Fahrzeuge, 20 Lagerplätze, 1 offene Ladefläche) statt Depot; angrenzende Erweiterungsfläche (5×6) zum Kaufen oder Pachten | `CityGenerator._place_plot`, `Estate` | Abnahmetest |
| 15 Einrichtungstypen: Unternehmerbüro (4 Stufen), Disposition, Stellplätze, Fahrzeughalle, Werkstatt, Laderampe, Lagerhalle, Kühllager, Betriebstankstelle, Ladepunkte, Pausenräume, Schulungsraum, Sicherheitsanlage, Waschplatz, vermietbare Büroflächen | `Estate.FACILITIES` | Abnahmetest (Büro, Stellplätze, Lager, Werkstatt, Rampe, Mietbüro); übrige: Code |
| Platzierung mit Position und Drehung; Prüfung von Eigentum, Grenzen, Überlappung, freier Einfahrt und Erreichbarkeit aller anfahrbaren Einrichtungen; gültige Bauvorschläge in der Beobachtung | `Estate.validate_place`, `suggestions` | Abnahmetest |
| Bau durch Baufirma (+40 %, Material geliefert) oder Eigenbau (interner Materialtransport ohne Umsatz, eigene Arbeiter, Bauzeit); während des Baus keine Wirkung, Ausbau bleibt nutzbar | `Estate.place`, Aufgabe `bauen` | Abnahmetest |
| Echte Kapazitätswirkung: Flottengröße, Auftragskapazität, Lager-/Kühlplätze, Rampen begrenzen parallele Abfertigung (Wartezustand), Rampe beschleunigt Laden, Werkstattplätze (Wartung doppelt so schnell), Tankgröße, Erholung, Sabotage-Entdeckung | `Estate`, `Simulation._bay_free`, `Personnel` | Abnahmetest (Teile) |
| Buchhaltung: Bau = Investition mit Abschreibung, Grund und Boden ohne Abschreibung, Rückbau schreibt Buchwert ab, Betriebskosten/Pacht/Nebenkosten, Mieteinnahmen; Bilanzidentität bleibt erhalten | `Estate`, `Ledger` | Abnahmetest |
| Vermietung: nur ausdrücklich vermietbare Flächen (Mietbüro, Büro Stufe 4); Interessenten abhängig von Lage und Preis; Mieter verlängern/ziehen aus und erzeugen echte Transportaufträge (Einzug, Bedarf, Auszug) | `offer_office_rental`, `accept_tenant` | Abnahmetest |
| Neue Aktionen: inspect_plot, expand_plot, place_building, upgrade_building, remove_building, assign_parking, assign_loading_bay, schedule_maintenance, purchase_fuel_stock, offer_office_rental, accept_tenant, assign_building_staff, wash_vehicle, train_worker | `EstateActions` | Abnahmetest (Teile) |
| Darstellung: Grundstücksgrenze in Firmenfarbe, Einfahrt, Einrichtungs-Pixelgrafiken (beide Ausrichtungen, Nachtlicht), Baustelle mit Absperrung/Fortschritt, Ausbaustufe | `EstateView`, `tools/gen_assets.py` | Screenshot |
| Demo-KI baut ihren Hof (Büro, Stellplätze, Lager, Werkstatt, Mietbüro) | `RuleBrain` | Wirtschaftscheck 3 Tage: alle 4 Firmen mit Gewinn |

### Behobene Fehler in dieser Runde
- Periodische Prüfungen (Vorarbeiter alle 10 min, Mietinteressenten, Händler-Nachschub …) fielen zufällig aus, weil ein Simulationsschritt mehrere Spielminuten umfasst; jetzt fortlaufender Minutenzähler.
- 158 von 904 Gebäudezugängen lagen in abgeschlossenen Fußwege-Taschen (Arbeiter kamen nie an); Zugänge liegen jetzt im zusammenhängenden Fußnetz (Regressionstest).
- „Partie beenden“ verlangt einen zweiten Klick; Leistenknöpfe reagieren nicht mehr auf Leertaste/Enter.

## Offen
- Strategische Steuerung Stufe 6: Vergleichsmodus (Metrik-Export, rotierende Startpositionen, gleiche Budgets) und exakte Wiederholung ohne API-Aufrufe; Abnahmeszenario mit Straßensperrung.
- Auftrag „Grundstücke und Stadt“, Teil 2: Villen, Schulen, Kitas, Frachtterminal, gebäudetypabhängige Kundenaufträge und die Animationen Tragen/Reparieren/Sprechen sind umgesetzt; offen sind Ein-/Aussteigen und Zustandsvarianten der Gebäude.
- Nicht automatisch getestet: Kühllager-Pflicht für Kühlware am Hof, Tankstelle, Waschplatz, Schulung, Garage/Sicherheit-Bonus (Code vorhanden, kein eigener Test).

## Auftrag 3 (Zwischenstand)
- **Fertig:** reale Kraftstoffpreise (Tankerkönig-Adapter, Referenz/Aufschlag/Ereignisfaktor getrennt, Status, Ersatzpreis), Tankstellen als Betriebe (Zapfsäulen, Wartezeit, Tankwagen, Betreiberkonto), Haushalte je Mitarbeiter (feste Adresse, Lebenshaltung, Defizit), verhandelte Löhne (`negotiate_wage`, Mindestlohn aus Markt und Haushaltsbedarf), aufgelaufene Löhne mit Rückstand und Vorrang in der Insolvenz, Motivation mit Kündigung.
- **Zusätzlich fertig:** Treibstoffplanung (`compare_fuel_options`, `schedule_refueling`, Wetter erhöht Verbrauch), Gebäudezustand (Stadtgebäude und Firmeneinrichtungen, Verfall, Pflege durch Eigentümer, `fund_maintenance`, `commission_renovation`, sichtbare Abnutzung, Viertelmittel im Lage-Reiter).
- **Ebenfalls fertig:** Nachrichten-Adapter in drei Ebenen (gemeldet, Einschätzung der Engine, begrenztes Spielereignis; Duplikatschutz, Schlüssel `NEWS_API_KEY`), Gesundheit und Erholung (`schedule_rest`, Krankheit), `offer_training`, `request_replacement_worker`, Ansicht Haushalte im Reiter Wirtschaft, 24 weitere Gebäudevarianten und vier neue Haustypen.
- **Offen:** Stadtviertel-Entwicklung mit Wirkung auf die Kundennachfrage, öffentliche Haushalte und Straßen (kommen mit Auftrag 4). Steuern und Sozialabgaben folgen mit Auftrag 4 (bis dahin Lohn = Nettolohn).

## Auftrag 4 (Zwischenstand)
- **Fertig:** `PublicSector` (`public_sector.gd`): Lohnsteuer 12 % und Sozialabgaben 10 % vom Bruttolohn auf P0, Sozialleistung deckt 60 % des Haushaltsdefizits, die Hälfte der Mittel über dem Ausgangsstand geht als öffentliche Aufträge an S0. Test `test_public_sector`; 4524 Prüfungen grün.
- **Ebenfalls fertig:** Ertragsteuer 15 % auf den kumulierten Gewinn mit Verlustvortrag (monatlich, nur soweit Bargeld da ist, Kategorie `tax`), Ressortausgaben (Soziales, Verkehr, Bildung, Verwaltung, Gesundheit) in `PublicSector.departments`. 4530 Prüfungen grün.
- **Steuerprüfung:** 15 % Chance je Firma und Monat (deterministisch aus Firma und Monat), fordert offene Ertragsteuer nach, 10 % Zuschlag als Bußgeld, Eintrag im Log und in der Ansicht „Staat“. 4534 Prüfungen grün.
- **Bürger und Arbeitsmarkt (`citizens.gd`):** 1200 Einwohner, 80 % beschäftigt. Jede KI-Firma startet mit 10 Mitarbeitern (`Personnel.MIN_STAFF`), Startkapital deshalb 150 000. Übrige Bürger arbeiten bei Rathaus, Schulen/Klinik, Baufirma, Handel, Industrie (Löhne vom Arbeitgeberkonto, Lohnsteuer und Sozialabgaben an P0), wechseln monatlich die Stelle, werden entlassen oder kündigen; Arbeitslose erhalten Arbeitslosengeld von P0. Ansicht „Bürger“ im Reiter Wirtschaft. Test `test_citizens`; 4564 Prüfungen grün.
- **KI-Antworten:** abgeschnittene JSON-Antworten werden bis zur letzten vollständigen Aktion gerettet; `ActionExecutor.normalize` glättet verschachtelte `parameters`, abweichende Schlüsselnamen und fehlendes `kind`.
- **Offen:** Gewerbeaufsicht, Einsätze, Zentralbank und Geldschöpfungsmodell, Stadtviertel-Entwicklung. HUD: Ansicht „Staat“ im Reiter Wirtschaft (Kasse, Steuern, Ressorts, Ertragsteuer je Firma).

## Fehlerbehebung nach externer Prüfung (25.10.2026)
1. `repay_loan` mit fremder Kredit-ID wird abgelehnt (Eigentumsprüfung vor jeder Buchung).
2. Die Veraltet-Grenze für KI-Antworten wächst mit der Simulationsgeschwindigkeit; bei 16× gelten dieselben realen Sekunden wie bei 1×.
3. Vorzeitige Ablösung zieht überfällige Raten samt Zinsen und Verzugszuschlag zuerst ein; kein Kredit gilt als getilgt, solange Forderungen offen sind.
4. Treibstoff wird gezapft (belegte Zapfsäulen = Wartezeit) und erst bei Ankunft im Depot gutgeschrieben (Tankwagen gegen Gebühr oder eigener Transportauftrag Tankstelle → Depot). Ein leerer Tank lässt das Fahrzeug liegen (kein stiller Notkauf); es fährt weiter, sobald Treibstoff im Depot ist, sonst kommt nach 90 Minuten die teure Notbetankung. Die Demo-KI bestellt früh und nutzt eine feste Nachtank-Regel.
5. Wetter-Speichertest vergleicht den Zeitstempel mit Toleranz.

## Auftrag 7 – Stadtentwicklung (Stand 29.10.2026)
- **Fertig:** Karte 512 mit Grundstücken, Planungsregeln und Bauantrag, Bürgermeister-KI mit Gemeinderat und Wahl, Baufirmen mit Angebot/Vertrag/zehn Bauphasen/Material/Erschließung/Übergabe/Einzug, Bauträger, Unternehmen als Bauherren, Haushalte als Bauherren mit Baukredit der Investitionsbank (Zusage, Auszahlung je Bauabschnitt, Annuität, Ausfall), sichtbare Baustellen mit Mannschaft und Geräten, Einzugsaufträge (Umzug, Möbel), KI-Aktion `bau_lieferung`, Kartenebenen (Taste L, inkl. Engpässe), Detailstufe, Bürgermeister-Zugang im Startmenü.
- **Geprüft:** `test_acceptance_flow` (Abnahme Schritte 1–12 über den Autopiloten, danach Mehrfamilienhaus mit Vermietung), `test_household_builder`, `test_construction`, `test_developer_autopilot`; Autotest 150 s/16× ohne Skriptfehler. Einzelheiten und Grenzen: `docs/URBAN_DEVELOPMENT.md`, Abschnitt „Stand der Umsetzung“.
- **Grenzen:** Haushalte bauen nur, wenn Einkommen und Eigenmittel der Bank genügen – im normalen Spielverlauf (Anfangsguthaben 150) geschieht das selten; die Mannschaft ist ein Besetzungsmodell mit Darstellung, keine Personen im Personalsystem; Unternehmen finanzieren Bauten nur aus der Kasse (Bankkredit für Bauherren-Unternehmen folgt mit Auftrag 6); der Verkehr kennt keine Kapazität (Auftrag 5), die Engpass-Ebene zeigt Ereignisse und Fahrzeugdichte.
