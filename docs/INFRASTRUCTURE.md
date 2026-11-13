# Auftrag 22: Lebendige Stadtinfrastruktur – Müll, Energie, Wasser, Polizei, Eisenbahn

Eingang 10.11.2026 (Benedikt, eingefügt während Auftrag 21 Teil 2). Vollständiger Text in der Sitzung; hier die verbindlichen Punkte
und der Abgleich mit dem Bestand. Reihenfolge laut Auftrag: Phasen 1–8, jede Phase integriert und getestet, dann die nächste.

## Kern (gekürzt)

Jeder Einwohner erzeugt Müll, verbraucht Strom und Wasser, erzeugt Abwasser. Vierzehn verbundene Systeme: Müllentsorgung und
Stadtreinigung, zentrale Deponie, Müllverbrennung, kommunale Entsorger, gemeinsames Kernkraftwerk (25/25/25/25, Verbrauch je Stadt
getrennt abgerechnet), Stromnetz als Graph mit Ausfällen und Reparatur, Trinkwasser (Wasserwerk, Pumpen, Hochbehälter, Leitungen,
getrennt von der Kläranlage), Kanalisation je Stadt, zentrale Kläranlage (Kosten nach Abwassermenge), Polizei je Stadt (Unfälle,
Kontrollen, Diebstahl, illegale Müllablagerung, Baustellenabsicherung), Eisenbahnnetz zwischen allen Städten (Bahnhof je Stadt ab
Start, Personen- und Güterzüge, Fahrpläne, Blockabschnitte/Signale/Weichen, Güterbahnhof am Großlager, Gleisbau und -wartung,
regionale Bahngesellschaft, private Güterverkehrsfirmen), neue Berufe im Arbeitsmarkt, Gebühren (Müll, Wasser, Abwasser, Strom,
Fahrgeld), Kettenreaktionen aus echten Zuständen (Stromausfall → Pumpen/Fabriken/Signale; Müllkrise; Bahnstörung → Lkw),
Dashboard-Bereich „Infrastruktur & Versorgung“ mit anklickbaren Ereignissen, Pixel-Animationen. Grundregeln: keine Ware/Energie/kein
Abfall ohne Quelle und Senke, echte räumliche Netze, Gebäude ohne Anschluss nicht versorgt, Anlagen brauchen Personal und
Betriebsmittel, Bau durch Baufirmen, alles gebucht, alles speicherbar. Abnahmetests 1–12.

## Bestand (wird erweitert, nicht ersetzt)

| Bereich | vorhanden | Lücke laut Auftrag 22 |
|---|---|---|
| Müll | `Waste`: Abfall je Haushalt/Betrieb (Tonnen pauschal), Recyclingquote, Gebühr (H0 → Stadt), Deponie je Stadt am Stadtrand, sichtbare Müllwagen-Touren; `Recycling` (Auftrag 20): Wertstoffhof, Sekundärrohstoffe | Müllarten, Tonnen je Gebäude mit Füllstand, Abholung entleert erst beim Halt, Littering/illegale Ablagerung mit Sauberkeit je Viertel, Betriebshof mit Personal/Fahrzeugen je Stadt, **gemeinsame** Deponie mit Waage und Kapazitätsausbau, Müllverbrennung mit Strom und Asche |
| Strom | `PowerGrid` (Leistung, Abschaltung nach Anschlussreihenfolge, Abrechnung), `PowerPlant` (Kernkraftwerk mit Brennelementen, Wartung, Notstrom); Regionalrat: Anteile fest 25/25/25/25 | KKW gemeinsam für vier Städte mit Gewinn-/Kostenteilung, Hochspannungstrassen und Umspannwerke als Graph, Leitungsschäden und Reparaturtrupps, Verbrauch je Stadt |
| Wasser/Abwasser | nur Erschließungsteil „Wasser“ der Grundstücke | Wasserwerk, Pumpen, Hochbehälter, Leitungsnetz, Kanalisation je Stadt, Kläranlage, Rohrbrüche, Gebühren |
| Polizei | `PublicSafety`: Personal, Streifenwagen, Ladendiebstahl, Festnahmen, Absicherung von Sperrungen; Feuerwehr-Verkehrsunfälle (Auftrag 21) | Dienststelle als Gebäude je Stadt mit Ausbau, Verkehrsunfälle mit Sperrung/Umleitung/Abschleppen, Kontrollen, Ruhestörung, illegale Müllentsorgung |
| Eisenbahn | nichts (nur Gebäudename „Güterbahnhof“) | alles |
| Haushalte | Stadtkassen, Landeszuweisung, Steuern, Grundsicherung (70 % Bund), Krankenkassen | Gebühren je Leistung, Infrastrukturbudget, Prioritäten |

## Plan

Phase 1 Müll (Tonnen, Abfuhr mit echter Entleerung, gemeinsame Deponie) · Phase 2 Verbrennung/Recycling/Entsorgungswirtschaft ·
Phase 3 KKW gemeinsam und Stromtrassen · Phase 4 Wasser, Kanal, Kläranlage · Phase 5 Polizei · Phase 6 Bahnhöfe, Schienen,
Personenverkehr · Phase 7 Güterbahn und Gleiswartung · Phase 8 Verflechtung, Bürgermeister-KI, Dashboard. Vorher wird Auftrag 21
Teil 2 (Fleischkette) abgeschlossen; Auftrag 21 Teil 3 (Eisenbahn) geht in Phase 6/7 auf.

## Stand Phase 1 – Müll (11.11.2026)

Umgesetzt in `scripts/economy/waste.gd` und `scripts/core/city_fleet.gd`:

- **Tonnen je Gebäude** (`Waste.bins`, kg): täglich kommt der Abfall der Einwohner jeder Stadt (Einwohner × 0,9 kg, verteilt nach
  bewohnten Wohnungen; ohne bewohnte Wohnung in die Tonne am Rathaus) und die Verpackung der Kassenverkäufe (auf die geöffneten Läden)
  hinein. Fassungsvermögen = 7 Tage Abfall des Gebäudes (mind. 20 kg). Beim ersten Tag sind die Tonnen unterschiedlich voll (wie die
  vorhandene Deponie).
- **Abfuhr je Stadt mit echter Entleerung**: die Müllwagen jeder Stadt starten am eigenen Rathaus; erster Halt ist die vollste Tonne,
  danach jeweils die nächstgelegene Tonne ab 60 % Füllstand, bis 2 t geladen sind. Erst beim Halt wird die Tonne geleert
  (`Waste.empty_bin`); ein voller Wagen fährt sofort zur Deponie. Eine Tour startet erst ab 30 % Ladung oder wenn eine Tonne 95 %
  erreicht (kleine Orte: etwa wöchentlich). Wagenzahl je Stadt nach Abfallmenge und Tourdauer (`Waste.trucks_for`, 1–8).
- **Gemeinsame Deponie mit Waage** (`Waste.weigh_in`): Menge je Stadt im Waagebuch, Wertstoffe (Recyclingquote) verkauft, Rest
  abgelagert. Kosten trägt die Kasse der liefernden Stadt (vorher alles P0), die Gebühr am Monatsende die Haushalte an ihre Stadt.
- **Überquellende Tonnen** senken die Versorgungszufriedenheit (`Contentment.supply_score`).
- **Erweiterung**: ab 80 % Füllstand um 600 t, Kosten 90 000 € nach den gewogenen Mengen je Stadt, fertig nach 20 Tagen.
- Anzeige: Deponie (Waage je Stadt, letzte Wägungen, Erweiterung), Müllwagen (Füllstand der Tonne am Halt, Stadt).
- Tests `test_waste_bins`, `test_garbage_collection`, `test_waste`; Messprobe `tests/probe_waste.gd [-- --days=31 --region]`.

Messung (Seed 4242, 31 Tage): Einzelstadt 1,3 t/Tag erzeugt, nach Anlauf gleich viel gewogen, überquellende Tonnen 227 → 24 von 258;
Region (2 Orte) Touren mit 8–14 Halten, keine dauerhaft überquellenden Tonnen.

Offen in Phase 1/2: Erweiterung wird noch nicht durch eine Baufirma gebaut (Kosten an den Entsorger S0); Betriebshof mit eigenem
Personal und Fahrzeugen je Stadt, Müllarten, Littering/Sauberkeit je Viertel, Müllverbrennung → Phase 2. Müllwagen werden nicht
gespeichert: nach dem Laden bleiben die Tonnen voll und werden neu angefahren (die Ladung eines fahrenden Wagens entfällt).

## Phase 2 – Müll ausbauen (ab 11.11.2026)

Reihenfolge: 1 Betriebshof · 2 Müllarten (Rest, Bio, Wertstoffe) · 3 Sauberkeit je Viertel mit Stadtreinigung · 4 Müllverbrennung
(Strom, Asche) · 5 Erweiterung von Deponie und Verbrennung durch Baufirmen.

**Schritt 1 Betriebshof (fertig 11.11.):** Municipal-Typ `AW-01` „Betriebshof Abfallwirtschaft“ (Gebäude `waste_depot`, 6 Grundvarianten ×
4 Stile in `tools/vox/public.py`), Beruf Müllwerker (13,50 €/h), Fahrzeug „Müllwagen“ (Hecklader, Besatzung 3, Bild `aw_muell` in 4
Richtungen). Gehört zur Startausstattung jeder Stadt (alte Spielstände bekommen ihn über `ensure_kit`). Die Touren starten am Betriebshof;
es fahren höchstens so viele Wagen, wie Fahrzeuge mit Fahrer und volle Besatzungen (3 Müllwerker je Wagen) da sind (`Waste.crews_of`).
Reicht der Fuhrpark nicht und ist Personal für einen weiteren Wagen da, kauft die Stadt einen Müllwagen (260 000 €, ab doppeltem
Kassenbestand). Mit eigenem Betriebshof entfällt die Abholgebühr an den Entsorger; die Stadt trägt Löhne, Fahrzeug- und Sachkosten über
Municipal. Ohne Betriebshof (Einzelstadt, kein Bauplatz) holt weiter der Entsorger S0 gegen Gebühr ab.

Nebenbefunde beim Einbau: Die Startorte (30–55 Bürger) sind voll beschäftigt – neue Dienste fanden kein Personal. Die Stellenanzeige einer
Einrichtung wirbt jetzt für jeden Beruf alle 7 Tage eine Kraft von außerhalb an, wenn im Ort eine Wohnung frei ist (vorher nur Ärzte und
Rettungsdienst). Grundvarianten öffentlicher Gebäude werden über alle Stile verteilt (vorher wiederholten sich Formen bei mehreren Stilen).
Test `test_waste_depot`; Probe `tests/probe_staff_pool.gd` (Arbeitsmarkt der Dienste je Stadt).

**Schritt 2 Müllarten (fertig 11.11.):** In der Region (eigene Abfallwirtschaft) hat jedes bewohnte Gebäude und jeder Laden drei
eigene Tonnen mit eigenem Füllstand – Restmüll (grau), Bio (grün) und Wertstoffe (blau) – statt einer pauschalen Tonne. Der Abfall des
Tages wird nach der effektiven Recyclingquote aufgeteilt: Rest (1 − Quote), davon 40 % des Recyclierbaren als Bio, der Rest Wertstoffe
(`Waste._put`, Quote `BASE_RECYCLING` + Mehrweg-Bonus). Restmüll fährt weiter mit dem Müllwagen (Hecklader) zur gemeinsamen Deponie; die
Waage wiegt jetzt reine Reststoffe und verbucht nur noch die Deponiegebühr – die Wertstofferlöse laufen real über den Hof. Bio und
Wertstoffe holt ein **Wertstoffwagen** (Fahrzeugtyp des Recyclinghofs RC-01, Bild `rc_wagen`, Ladekapazität 1 t, eigener Strom
`Waste.tours_wert`) als zweite Tour ab: ein Wagen je Stadt, er leert am Halt beide Tonnen proportional zum Füllstand
(`Waste.empty_wert`), liefert zum Recyclinghof der Stadt und wird dort `Recycling.deliver` sortiert (Bio-Anteil → Kompost, Rest →
Papier/Glas/Kunststoff/Schrott, Kapazität nach Personal, Sekundärrohstoffe als echte Ware im Hofbestand). Ist die Hof-Kapazität des Tages
ausgefahren, wird die angelieferte Menge begrenzt; die wöchentliche Abfahrt des Wertstoffwagens zum Großlager/Verwerter bleibt der
Erlöskanal. Damit die Abfuhr ab dem ersten Tag fährt, ist der Recyclinghof (RC-01) jetzt Teil der Startausstattung jeder Stadt
(`START_KIT`); alte Spielstände bekommen ihn über `ensure_kit`. Fahren die Müllarten nicht (Hof geschlossen), bleiben Bio- und
Wertstofftonnen voll und zählen als überquellende Tonnen (die senken die Versorgungszufriedenheit). Die Einzelstadt und der Küstenort
(keine kommunale Abfallwirtschaft) bleiben unverändert im Pauschal-Modell: eine Tonne, die Waage berechnet Rest aus der Recyclingquote.
Sichtbar: drei getönte Tonnen je Haus, grüne Wertstoffwerker an den Bio-/Wertstofftonnen, anklickbarer Wertstoffwagen mit eigener
Detailansicht (Status, Halte, Ladung, Bio/Wertstoffe des nächsten Halts); die Deponie-Anzeige nennt je Stadt die Tonnenzahlen nach Art.
Tonnen, Raten und Touren werden in `Waste.to_dict`/`from_dict` gespeichert. Tests `test_waste_streams` (drei Ströme, Halt, Hoflieferung,
Konservation, kein Hof → keine Tour, Laden), Anpassungen `test_waste_bins`/`test_waste_depot`/`test_recycling` an die modusabhängigen
Erwartungen; Messprobe `tests/probe_waste.gd --region`: 31 Tage, 7 Wertstofftouren, überquellende Tonnen 55 → 0, Deponie bleibt bei
~201/800 t (vorher ohne Hof: 55 überquellend).

**Schritt 3 Sauberkeit je Viertel (fertig 12.11.):** Überquellende Tonnen (Waste.overflowing) lassen ab 3 kg Straßenmüll pro
Tonne am Gebäude (building.road) zurück; Viertel-Dreck 0..1 = Summe der Straßenmüll-Zellen / DIRTY_REF 40 kg, die
Versorgungszufriedenheit sinkt um den Dreck im eigenen Viertel. Die Kehrmaschine (Voxel aw_kehr, Betriebshof AW-01) räumt
täglich die schmutzigste Zelle je Stadt (Viertel mit dem meisten Dreck zuerst, dann die Entfernung); die Stadtkasse zahlt
60 €/Zelle. Sichtbar: Flecken in RoadStateView, Zeile in der Deponie-Ansicht und im Service-Planner. Test
test_street_cleaning (16); Messprobe probe_waste --days=31 --region: 23 Zellen geräumt, am Ende 5 Stellen / 5 kg Straßenmüll,
Zufriedenheit stabil.

**Schritt 4 Müllverbrennung (fertig 12.11.):** Die Region beschließt eine Müllverbrennungsanlage neben der gemeinsamen
Deponie, sobald IV_BUILD_T 5 t neuer Restmüll (seit Spielbeginn, ohne die 25 % Startfüllung) angeliefert sind (gemessen
~0,1 t/Tag real angeliefert → Auslösung nach 3–4 Wochen). 25 Tage Bau, 1,5 Mio. €, geteilt nach den gewogenen Müllmengen
der Städte (Waste._iv_shares wie bei der Deponie-Erweiterung). Die Anlage (Municipal-Typ MV-01, Gebäude incineration_plant,
6 Grundvarianten × 4 Stile, der Schornstein raucht über der Stadtansicht) steht auf einem freien öffentlichen Bauplatz (5×4)
mit Straße im Umkreis der Deponie (Waste._iv_find_site); fehlt der Platz, wird es alle 7 Tage erneut versucht. Ab der
Inbetriebnahme fahren die Müllwagen weiterhin zur Deponie, aber 90 % des angelieferten Restmülls werden verbrannt
(Waste._iv_burn): pro Tonne 500 kWh Strom ohne Brennstoff; die Leistung zählt über Waste.iv_available_kw in den Bestand des
Stromnetzes (PowerGrid._allocate wie Kraftwerkseigenproduktion und drückt den Tarif). Der Stromerlös (500 kWh × Tarif)
gleicht den laufenden Betrieb (400 €/Tag) aus; der Aschenrest (10 %) wird abgelagert. Die Städte zahlen die Deponiegebühr
ab dem Bautag nur noch auf die Asche plus eine Verarbeitungspauschale von 25 €/t auf die verbrannten Tonnen
(Waste.weigh_in); die Abholgebühr entfiel bereits mit Schritt 1. Sichtbar: Zeile in der Deponie-Ansicht (LiveText.landfill:
verbrannt / Asche / Netz-Strom / Kosten) und Feld muelle.verbrennung im Bürgermeister-Bericht (keine / im Bau / in
Betrieb). Bau- und Betriebszustand werden gespeichert (iv_building, iv_fertig, iv_fac, iv_new_t, iv_stats, iv_last,
Platzkandidat). Test test_incineration (22: Auslösung, Platzzuweisung, Bau, 90/10-Teilung, Strom im Netz, Kosten,
Anzeige, Speicherung); Messprobe probe_waste --days=100 --region --cities=4: Auslösung an Tag 51 (5 t neuer Restmüll),
in Betrieb seit Tag 77; Ende: 5,8 t verbrannt → 0,6 t Asche, Strom 3 MWh / Ertrag 928 €, Netz bis 251 kW; Deponie wächst
nach Inbetriebnahme nur noch um die Asche (Tag 50–75: 205 → 210 t, dann 210/800 t bis Tag 99).

**Schritt 5 Ausbau über Baufirmen (fertig 12.11.):** Die beiden regionalen Großbauwerke laufen nicht mehr sofort über die
Entsorgungskasse (S0), sondern durch das Bausystem: Die Region (Trägerstadt = größte Stadt) schreibt das Projekt über
Mayor.add_works_project aus; die Kostenanteile der Städte folgen den Anteilen nach gewogenen Müllmengen (Deponie) bzw.
_Müllverbrennung nach IV-Schritt (Waste._iv_tender), und der Tageslauf von Construction vergibt es an das günstigste
Baufirmen-Angebot (maximal 120 % des Budgets, sonst neue Ausschreibung am nächsten Tag). Der Bau ist sichtbar (Baufirma,
Resttage, Budget in der Deponie-Ansicht und im Service-Planner); bei Abnahme (Construction._finish_public) erhöht
Waste.on_landfill_done die Deponiekapazität um 600 t (EXPAND_T) bzw. Waste.on_iv_done nimmt die Verbrennung in Betrieb
(Parzelle bebaut, Gebäude incineration_plant, MV-01). Abnahmefähig wird das Projekt erst ab dem Tag nach Angebotseingang,
wenn eine Bau-Mannschaft vor Ort ist. Gespeichert: Waste.iv_project (Projekt-Id der Ausschreibung) und der Bauplatz; der
Ausschreibungs- und Bauprozess selbst gehört zum Bauprojekt der Trägerstadt (Bürgermeister-Projekte sind Teil des Speichers).
Tests: test_incineration (24: Ausschreibung mit Kostenanteilen, Baufirmen-Bau und Abnahme bis „fertig“, danach Anlage in
Betrieb), Deponie-Block in test_waste_bins (Erweiterung wird ausgeschrieben, Baufirma baut ab, Kapazität wächst, Geld erhalten).

## Phase 3 – Gemeinsames Kraftwerk und Stromnetz (ab 12.11.2026)

Geplante Schritte: (1) Kraftwerk gemeinsam, Verbrauch und Abrechnung je Stadt · (2) Stromnetz als Graph: Umspannwerk je Stadt,
Hochspannungstrassen Kraftwerk → Umspannwerke, Versorgung nur über verbundene Trassen · (3) Leitungsschäden (Sturm/Alter) mit
Ausfall der betroffenen Stadt und Reparaturtrupps der Stadtwerke · (4) Ausbau der Trassen/Umspannwerke über Baufirmen, Anzeige.

**Schritt 1 Kraftwerk gemeinsam, Verbrauch je Stadt (fertig 12.11.):** Neues Konto `E0` „Kraftwerksgesellschaft (gemeinsam)“
trägt alle Kraftwerkskosten (Personal, Wartung, Notstrom, Entsorgung; Brennelemente bestellt weiter Ort 0 über sein Lager, E0
erstattet sofort). `PowerGrid` erfasst je Stadt Grundlast (Einwohner × 1,2 kW) und Betriebe nach Standort (`town_of_biz`,
versorgt/abgeschaltet). Täglich kauft jede Stadt ihren Verbrauch zum Erzeugungspreis (0,17 €/kWh) bei E0; die Betriebe zahlen ihren
Tarif an die Stadtwerke ihrer eigenen Stadt (vorher immer P0). Am Monatsende (`PowerGrid.settle`) wird das Ergebnis von E0 nach
festen gleichen Anteilen ausgeschüttet bzw. von den Städten ausgeglichen (E0 danach 0; Einzelstadt: 100 % an P0). Strom-Ansicht
mit Zeile je Stadt (Last, Bezug, Tarife, Ausgleich), Bürgermeister-Beobachtung mit `staedte`/`anteile`/`letzter_ausgleich`,
gespeichert (`by_town`, `last_settle`). Test `test_shared_plant` (13), `test_power_grid` angepasst (P0 + E0), Messprobe
`tests/probe_power.gd [-- --days=35 --cities=4]`: 4 Städte, Monat 1 Bezug 434–756 € je Stadt, Kraftwerk 10 200 € Personal bei
kleiner Last → Ergebnis −6 630 €, je Stadt −1 658 € ausgeglichen; Geldfehler 0,00.

**Schritt 2 Stromnetz als Graph (fertig 12.11.):** `PowerNet` (`scripts/economy/power_net.gd`, gehört zu `PowerGrid.net`): Knoten
Kraftwerk `KW` und je Stadt ein Umspannwerk `U<k>` (Feld rechts unten am Rathaus); Kanten = Hochspannungstrassen als gerade
Zellenfolge (Freileitung, Bresenham), Startnetz = minimaler Spannbaum ab dem Kraftwerk (Prim). `PowerGrid._allocate` teilt in zwei
Töpfe: Kraftwerk + Müllverbrennung nur für Städte, deren Umspannwerk über intakte Trassen erreichbar ist (`connected`, BFS); der
Notstrom von außen (800 kW) deckt die Lücke aller Städte, abgehängte Städte haben nur ihn (Sperrgrund „Hochspannungstrasse
unterbrochen“, `unversorgt_kw` für Grundlast über dem Notstrom). Kartenansicht `PowerNetView` (über der Bebauung): Gittermasten
alle 4 Felder, Leiterseile mit Durchhang, Umspannwerk mit Zaun, Trafos, Portal und grüner/roter Lampe; unterbrochene Trassen rot
gestrichelt mit Warnzeichen. Gespeichert (`grid.net`), alte Spielstände bekommen das Netz beim ersten Tageslauf. Test
`test_power_net` (13): 5 Knoten/4 Trassen, lückenlose Trassen (Region Seed 4242: 1 020 Felder), genau die Städte hinter der
getrennten Trasse verlieren das Kraftwerk, Notstrom deckt ihre Grundlast, Laden, Wiederverbindung, Einzelstadt 1 Trasse.

**Schritt 3 Leitungsschäden und Netztrupps (fertig 12.11.):** `PowerNet.on_day` würfelt je intakter Trasse einen Schaden
(Sturmtag laut `Weather.is_strong_wind`: 12 %, sonst 0,2 % Alterung). Die Schadstelle liegt an einer Trassenzelle mit Straße im
Umkreis von 6 Feldern; der Netztrupp der nächsten **versorgten** Stadt fährt als echtes Fahrzeug (`CityFleet`, Art `netztrupp`,
Bautrupp-Grafik mit Rundumleuchte) vom Rathaus hin, arbeitet erst ab Ankunft 40 Spielminuten und meldet `PowerNet.repaired`;
die Kraftwerksgesellschaft E0 zahlt 2 500 € an S0. Ereignismeldungen bei Schaden (betroffene Städte) und Reparatur (Ausfalldauer).
Strom-Ansicht: unterbrochene Trassen, Netztrupps, Schadensstatistik. Nach dem Laden fährt für offene Schäden ein neuer Trupp los.
Test `test_power_repair` (12): Anfahrt 94 Spielminuten, 40 Minuten Arbeit, Kosten, Laden mitten in der Reparatur, Sturm.
Messprobe `probe_power --days=60`: 1 Schaden, 2,5 Spieltage Ausfall, Notstrom 495 €, Geldfehler 0,00.

**Schritt 4 Ringschluss über Baufirmen (fertig 12.11.):** Hat ein Schaden Städte getrennt (`repairs[id].getrennt`), beschließt
die Region nach der Reparatur (`PowerNet.plan_ring`) eine zweite Trasse: kürzeste Verbindung eines Knotens hinter der Trasse mit dem
übrigen Netz (BFS ohne die Trasse), 400 €/Feld, Bauzeit Felder/15 (mind. 10 Tage). Ausschreibung als regionales Projekt `trasse`
(Träger die größte Stadt, Anteile gleich je Stadt wie das Kraftwerk), Bautrupp fährt zur Trassenmitte (`BuildCrews._site_of`), die
Abnahme (`Construction._finish_public` → `PowerNet.on_line_done`) fügt die Kante hinzu. Nur ein Ringschluss zugleich; ist die Seite
schon redundant, wird nichts geplant. Karte: abgesteckte Trasse (Pflöcke) während des Baus; Strom-Ansicht „Ringschluss im Bau“.
Test `test_power_ring` (11): Region Seed 4242 Ringschluss U1–U2, 348 Felder, 139 200 € (34 800 € je Stadt), 24 Tage; danach trennt
derselbe Schaden keine Stadt mehr ab.

Offen nach Phase 3: Folgen eines längeren Ausfalls für Haushalte (Zufriedenheit) und für Pumpen/Kläranlage (ab Phase 4),
zusätzliche Umspannwerke für große Städte.

## Phase 4 – Trinkwasser, Kanal und Kläranlage (ab 13.11.2026)

Geplante Schritte: (1) Wasserwerk je Stadt, Verbrauch von Haushalten/Einrichtungen/Betrieben, Gebühr, Engpass bei Stromausfall ·
(2) Leitungsnetz je Stadt entlang der Straßen mit Hochbehälter (Vorrat überbrückt Stromausfälle) und Druckzonen, Gebäude ohne
Anschluss unversorgt · (3) Rohrbrüche mit Ausfall eines Netzabschnitts und Wassertrupp der Stadtwerke (echtes Fahrzeug) ·
(4) Kanalisation je Stadt und gemeinsame Kläranlage der Region (Kosten je Stadt nach Abwassermenge, Abwassergebühr, Überlauf
bei Ausfall) · (5) Ausbau von Wasserwerk, Hochbehälter und Kläranlage über Baufirmen, Anzeige und Bürgermeister-Beobachtung.

**Schritt 1 Wasserwerk und Verbrauch je Stadt (13.11.):** `WaterSupply` (`scripts/economy/water_supply.gd`, `sim.water`, nur
Region). Neuer Municipal-Typ `WW-01` „Wasserwerk“ (Gebäude `waterworks` 4×3, Baukasten `tools/vox/public.py` 6 Grundformen × 4
Stile: Filterhalle, Becken, Rundbehälter, Grashügel-Hochbehälter, Wasserturm; Kennfarbe Blau), gehört zur Startausstattung
(`START_KIT`, alte Spielstände bekommen es beim nächsten Tageslauf), Beruf `wasserwerker`. Verbrauch je Spieltag: 0,12 m³ je
Einwohner, Einrichtungen die Hälfte von `TYPES.water` anteilig zur Ortsgröße (Bezug 1 000 EW, mind. 5 %), Betriebe 0,4 m³ + 0,01 m³ je kW. Förderung = Leistung (m³/Tag, wächst
mit den Einwohnern) × Besetzungsgrad; ohne Strom (Stadt vom Kraftwerk getrennt und Notstrom erschöpft) steht das Werk. Verteilung:
Haushalte, dann Einrichtungen, dann Betriebe nach Anschlussreihenfolge; Betriebe ohne Wasser oder ohne Wasseranschluss des
Grundstücks sind mit Grund blockiert (`wasser`). Gebühr je m³ (Start 2,20 €, monatlich kostendeckend aus Werkskosten / verkauften
m³, 1,50–6,00 €): Haushalte (H0) und Betriebe (Buchung `water`) zahlen an ihre Stadt. Stadt ohne Werk: Fernwasser 1,80 €/m³ an S0.
Abwasser (90 %) wird erfasst. Anzeige im Strom-Tab („Trinkwasser“), gespeichert. Test `test_water_supply`.

## Phase 6 – Eisenbahn: Bahnhöfe, Strecken, Personenverkehr (vorgezogen 13.11.2026)

Benedikt hat die Bahn am 13.11. vor die restlichen Wasserschritte und die Polizei gezogen. Geplante Schritte: (1) Bahnhof je Stadt
und Gleisnetz zwischen allen Bahnhöfen · (2) Regionalbahn mit Fahrplan: Triebwagen fahren sichtbar auf den Gleisen, halten an den
Bahnsteigen, eingleisige Abschnitte mit Blocksicherung (Kreuzen nur in Bahnhöfen), Signale zeigen die Belegung · (3) Fahrgäste:
Einwohner pendeln und reisen per Bahn (statt Auto), Fahrgeld, regionale Bahngesellschaft als Konto, Personal (Triebfahrzeugführer,
Zugbegleiter) · (4) Bahnübergänge schließen vor dem Zug (Straßenverkehr wartet), Störungen (Signal-/Weichenstörung, Sturm) und
Rückfall auf Lkw/Auto · (5) Anzeige, Bürgermeister-Beobachtung, Ausbau (Taktverdichtung, zweites Gleis) über Baufirmen.
Phase 7 (Güterbahn, Güterbahnhof am Großlager, Gleisbau/-wartung, private Güterverkehrsfirmen) folgt danach.

**Schritt 1 Bahnhöfe und Gleisnetz (13.11.):** `RailNet` (`scripts/economy/rail_net.gd`, `sim.rail`, nur Region mit ≥ 2 Städten).
Beim ersten Tageslauf bekommt jede Stadt einen Bahnhof: freies Rechteck 10×4 möglichst nah an der Ortsmitte (Ringsuche 8–90
Felder), Gleis außen, Bahnsteig, Empfangsgebäude 4×2 bzw. 2×4 (`train_station`/`train_station_v`, Baukasten `tools/vox/public.py`
6 Grundformen × 4 Stile: klassisch mit Uhr, Flachbau mit Vordach, Uhrturm, Glaskubus, Holz mit Güterschuppen, Haltepunkt) zur
Ortsmitte hin an einer Straße; mindestens ein Gleisende muss das offene Land erreichen (Flutfüllung des Grobrasters ab Kartenmitte –
Seed 4242 hatte sonst Gleisenden in einer von Kai und Bebauung eingeschlossenen Tasche). Strecken verbinden die Bahnhöfe in der
Reihenfolge um die Kartenmitte (wie die Autobahn): Grobraster 4×4 mit Kurvenstrafe (`RegionalProjects._hw_route`, eigenes Raster
`RailNet._blocks`: Straße 3, Wasser 10 = Brücke, Berg 14 = Tunnel, vorhandenes Gleis 0,3), kurze Zuführungen fein; alle
Endenpaare werden der Nähe nach versucht. Boden der Gleisfelder wird `RAIL` (Bäume gerodet, kein Bau darauf); Straßen bleiben
(Bahnübergang), Wasser/Berg bleiben (Brücke/Tunnel). Darstellung `RailView`: Holzschwellen und Schienen mit Bögen, erhöhte
Bahnsteige mit Sicherheitslinie, Andreaskreuze, Ausfahrsignale, Prellböcke, Brückentrog mit Pfeilern, Tunnelportale; Bodenkachel
Schotter. Gespeichert (`rail`), beim Laden wird der Gleisboden neu gelegt. Kamera `--shot-bahn=<n|bruecke|uebergang|kurve|tunnel>`,
Probe `tests/probe_rail.gd [-- --seed=… --cities=…]` (Seeds 4242/77/9/123: je 4 Bahnhöfe, 3 Abschnitte, 335–501 Felder,
0–5 Bahnübergänge, bis 12 Brückenfelder). Test `test_rail_net` (23).

**Schritt 2 Regionalbahn mit Fahrplan und Blocksicherung (13.11.):** Bahnhöfe haben jetzt 5 Reihen: Ausweichgleis (8 Felder, an
beiden Enden per Weiche am Hauptgleis), Hauptgleis, Bahnsteig, Empfangsgebäude. `RailTraffic` (`scripts/economy/rail_traffic.gd`,
`sim.trains`, Takt in `Simulation.step`): eine Linie über alle Bahnhöfe in Streckenreihenfolge, Fahrweg = lückenlose Zellfolge
(Bahnhofsgleise + Strecken; Ein-/Ausfahrt am selben Ende = Kopfbahnhof mit Wenden). Zwei Triebwagen (RB1 ab erstem, RB2 ab letztem
Bahnhof), 3 Felder je Spielminute (doppelte Lkw-Geschwindigkeit), 4 min Halt, 12 min Wendezeit (Verspätung wird bis auf 4 min
aufgeholt). Blocksicherung: Abschnitt zwischen zwei Halten = Block, höchstens ein Zug; Abfahrt nur bei freiem Block und freiem
Gleis im Zielbahnhof (Haupt + Ausweiche = 2), sonst „wartet am Signal“ mit Grund. Fahrplan: RB2 startet so versetzt, dass sich die
Züge planmäßig im mittleren Bahnhof treffen (gleichzeitiger Start ließ sie sich mitten im Block begegnen: 150 min Wartezeit je
Umlauf); gemessen über 16 Tage Verspätung 0–1 min, Kreuzungen in Bahnhöfen. Darstellung: Triebwagen aus zwei Wagen (Voxel
`rb_triebwagen`, hellgrau mit türkisem Band, gelbe Türen, Steuerwagen blickt nach hinten) entlang des Fahrwegs (`EntityView`), im
Bahnhof weich auf das Ausweichgleis versetzt; Ausfahrsignale grün/rot nach Blockbelegung; Weichen; Anzeige im Strom-Tab
„Eisenbahn (Regionalbahn)“ mit Zügen, Ort, Status, Verspätung, Kreuzungen. Gespeichert (`trains`), Fahrweg wird neu abgeleitet.
Kamera `--shot-bahn=zug|zug2` (folgt dem Zug bis zur Aufnahme). Test `test_rail_traffic` (15): Blocksicherung über einen Umlauf,
Bahnhofskapazität, Fahrten, Kreuzung, Verspätung, Speichern/Laden während der Fahrt.

**Schritt 3 Fahrgäste, Fahrgeld, Bahngesellschaft, Personal (13.11.):** Täglich entstehen Reisewünsche je Haltepaar und Richtung:
0,0002 × Einwohner A × Einwohner B (Ausflug/Einkauf) plus 0,3 Fahrten je Bahnpendler (`Commuting`: wer zwischen zwei
Bahnstädten pendelt, fährt Bahn statt Auto – keine Straßenfahrtkosten, Motivation −1 statt −2; `stats.bahn_paare`). Sie warten am
Bahnsteig (Bruchteile sammeln sich), steigen bei der Abfahrt nur in Züge Richtung Ziel (160 Plätze) und am Ziel aus. Fahrgeld
1,50 € + 0,004 €/Feld (Ende zu Ende 6,42 €) von den Haushalten (H0) an das neue Konto `N0` „Regionalbahngesellschaft
(gemeinsam)“; ohne Zugbegleiter fahren 25 % schwarz. N0 zahlt 0,50 €/Feld Betriebskosten (S0) und erhält 0,45 €/Feld
Landeszuschuss (Regionalisierungsmittel, X0); Monatsausgleich nach Einwohneranteilen (N0 danach 0). Personal: Municipal `BG-01`
„Regionalbahn“ (regional, Sitz im Bahnhof der größten Stadt, Bild bleibt), Berufe `lokfuehrer` (Triebfahrzeugführer) und
`zugbegleiter`, 3 + 2 Stellen, Personal- und Sachkosten erstattet das Land (`refinanziert`). Zug n fährt nur mit mindestens n+1
Triebfahrzeugführern (sonst „wartet: kein Triebfahrzeugführer“, keine Bahnpendler). Messung vor der Erstattung (Probe 40 Tage,
Seed 4242): 288 Fahrgäste, 1 281 € Fahrgeld, 12 800 € Betrieb, 8 960 € Zuschuss, dazu ~5 700 €/Monat Löhne – für vier Orte mit je
~50 Einwohnern zu teuer, daher Erstattung und Zuschuss 0,45 €. Darstellung: wartende Figuren auf dem Bahnsteig (bis 14),
Beschriftung „RB1 · n Fahrgäste“ über dem Zug, Anzeige mit Fahrgästen, Wartenden je Bahnhof, Fahrgeld/Zuschuss/Kosten, Saldo,
Personal, Monatsausgleich. Gespeichert (`waiting`, Ladung je Zug, `facility`). Test `test_rail_passengers` (17);
`test_municipal` nimmt regionale Dienste von der Wohnort-Prüfung aus (stellen regionsweit ein).

**Schritt 4 Bahnübergänge, Störungen, Rückfall auf die Straße (13.11.):** Bahnübergänge der Linie (`RailTraffic.crossings`)
schließen, solange ein fahrender Zug zwischen 6 Feldern vor der Spitze und 3,6 Feldern hinter dem Zugende ist
(`NavGrid.barriers`, zählt in `is_blocked_road`); Firmenfahrzeuge (`Simulation._drive`) und Stadtfahrzeuge (`CityFleet`) warten
davor, statt umzuplanen. Darstellung: Schrankenbäume rot-weiß quer über die Fahrbahn mit blinkender roter Lampe, offen
hochgeklappt. Störungen je Block und Tag: Sturm (`Weather.is_strong_wind`) 15 % „Baum auf dem Gleis“ (60 min Arbeit, 1 200 €),
sonst 0,8 % Signalstörung (Ausfahrsignal, 30 min, 800 €) und 0,4 % Weichenstörung (45 min, 1 500 €). Gestörter Block: keine
Abfahrt („Störung: …“, Signal rot), ein Zug im Block hält vor der Stelle. Bahntrupp (`CityFleet` Art `bahntrupp`, Bautrupp-Grafik
mit Rundumleuchte) fährt vom nächsten Bahnhof zur nächsten Straße, arbeitet ab Ankunft, meldet `RailTraffic.repaired` (Kosten N0 →
S0); nach dem Laden fährt für offene Störungen ein neuer Trupp. Wartende, deren Weg über einen gestörten Block führt, fahren Auto
(0,01 €/Feld H0 → S0, Statistik `strasse`). Karte: Warndreieck, beim Baum ein umgestürzter Baum quer über dem Gleis. Anzeige:
offene Störungen, geschlossene Schranken, Schließungen, Sperrzeit, Ausweichende. Probe 60 Tage: Seed 4242 164 Schließungen,
2 Störungen (81 min), 33 Fahrgäste auf der Straße; Seed 77 262 / 4 (184 min) / 83. Kamera `--shot-bahn=schranke` (wartet, bis
eine Schranke zu ist). Test `test_rail_disruptions` (17). Hinweis: Eine Strecke kann das Endfeld einer Stichstraße schneiden
(Übergang ohne Durchgangsverkehr, harmlos).

**Schritt 5 Bürgermeister-Beobachtung und Ausbau (13.11.):** Beobachtung der Bürgermeister `bahn` (`RailTraffic.summary`: Züge,
Fahrgäste, Wartende, Finanzen, Personal, Störungen, `ausbau` mit Optionen und Kosten). Regionalrat mit zwei neuen Antragsarten
(Aktion `regionalrat_antrag` art `bahn_takt` | `zweites_gleis`; Regel-Bürgermeister nach Lage): **weiterer Triebwagen**
(1,6 Mio. €, Land 75 %, Städte 25 % nach Einwohnern; höchstens 3 Züge; Lieferung nach 20 Tagen am freien Endbahnhof; Bedarf
Triebfahrzeugführer = Züge + 1, Zugbegleiter = Züge) – Regel: ≥ 120 Wartende am eigenen Bahnsteig; **zweites Gleis** auf dem
Abschnitt mit der meisten Wartezeit am Signal (`stats.block_wartezeit`, sonst dem längsten): 700 €/Feld, Bauzeit Felder/12
(mind. 15 Tage), Land 75 % (`federal`), Städte nach Einwohnern; Bauprojekt `gleis` über Ausschreibung und Baufirma (Bautrupp zur
Abschnittsmitte, Baustelle abgesteckt), Abnahme `RailTraffic.on_track_done` – Regel: ≥ 120 Minuten Wartezeit vor dem Abschnitt.
Zweigleisig: Belegung je Richtung (`_bkey`), Züge beider Richtungen gleichzeitig im Abschnitt, je Richtung ein eigenes Gleis
(Rechtsverkehr, 8 Weltpunkte Versatz), RailView zeichnet zwei Gleise. Gespeichert (`double_blocks`, `planned_tracks`, `ordered`).
Kamera-Demo `--demo-zweigleis`. Test `test_rail_expansion` (17). Damit ist Phase 6 (Personenbahn) abgeschlossen; offen für später:
Gleisenden-Zuführungen glätten (Treppen), Übergänge am Ende von Stichstraßen vermeiden. Nächste Phase 7: Güterbahn.

## Phase 7 – Güterbahn (ab 13.11.2026)

Geplante Schritte: (1) Güterbahnhof am Großlager, Anschlussgleis, Güterzug mit Blocksicherung und Vorrang der Regionalbahn ·
(2) Ladung: Stadtlager-Bestellungen aus dem Großlager fahren per Bahn (Beladen am Güterbahnhof, Entladen am Stadtbahnhof, letzte
Meile Stadt-Lkw), günstigere Fracht, Ziel der Tour nach Ladung · (3) Gleiswartung: Gleiszustand je Abschnitt sinkt mit Belastung,
Langsamfahrstellen, Instandsetzung über Baufirmen · (4) private Güterverkehrsfirmen (Unternehmer buchen Trassen/Wagen).

**Schritt 1 Güterbahnhof und Güterzug (13.11.):** `RailNet.ensure_freight` (beim Tageslauf, auch für alte Stände): Güterbahnhof
nahe der Großlager-Mitte (Ringsuche um das Großlager, Layout wie ein Bahnhof: Ausweich- und Ladegleis, Laderampe, Güterhalle
`freight_depot`/`_v` 4×2 bzw. 2×4, Baukasten `tools/vox/public.py` 6 Grundformen, Stil Industrie). Anschlussgleis von einem Gleisende
zu einer Weiche auf einem geraden Stück der Hauptstrecke: Grobraster wie die Strecken, Blöcke mit vorhandenem Gleis gesperrt (keine
Mitbenutzung, nirgends direkt neben der Hauptstrecke außer an der Weiche), letztes Stück fein. Seeds 4242/77/9/123: 116–256 Felder.
`RailTraffic`: Güterzug GZ1 (Voxel `gz_lok` Mittelführerhaus-Diesellok, `gz_wagen` Containertragwagen; Lok + 4 Wagen) – Beladen
20 min, Anschlussgleis (eigener Block `BRANCH`), Einfahrsignal an der Weiche, Einfahrt bei freiem Block und Zielgleis, Fahrt zum Ziel
der Tour (reihum alle Bahnhöfe), Entladen 10 min, zurück, an der Weiche ins Anschlussgleis. Höchstens 3 Züge auf der Linie
(Güterzug zählt mit): mit zwei Gleisen je Bahnhof können sich drei Züge auf einer eingleisigen Linie nicht gegenseitig festfahren.
Vorrang der Regionalbahn: der Güterzug fährt nicht in einen Abschnitt, in den eine Regionalbahn demnächst (30 min) ab- oder
gerade zufährt; nach 240 min Wartezeit nimmt er die nächste freie Lücke (Messungen 30–40 Tage: ohne Vorrang bis 750 min
Verspätung der Regionalbahn, mit striktem Vorrang 0 Güterfahrten). Regionalbahn mit > 60 min Verspätung am Endbahnhof fährt den
nächsten Takt (`takt_neu`). Wartezeit an der Weiche zählt für den Abschnitt (Regel-Bürgermeister beantragen dort das zweite
Gleis). Darstellung: Rampe, Weichen, Signal am Anschluss, Prellbock; Beschriftung „GZ1 · beladen/leer“; Kamera
`--shot-bahn=gueter` und `--shot-bahn=zug3`. Test `test_freight_train` (17); die Personenbahn-Tests laufen ohne Güterzug.

## Nachbesserung Auftrag 23 Steinwerke (13.11.)

Partie 13.11. (vier Ollama-Firmen, qwen3.5 9B): in gut drei Spielmonaten kein einziges Steinwerk. Ursachen: Die Beobachtung
`steinbauten` sagte nur „create_stone_work …“, aber nicht, ob Material, Geld und Platz reichen (das Großlager hat ab Start 80
Aufbereiteten Stein), und das Regel-Gehirn (Ersatzmodus, Demo) hatte gar keine Regel dafür. Jetzt: `jetzt_moeglich`, `grund`,
`eigener_stein`, `grosslager_stein`, `kosten_eur` in der Beobachtung; `RuleBrain._stone_work` baut aus Überschuss (Puffer +
25 000 €) mit 25 % je Entscheidung ein Wahrzeichen, höchstens eins zugleich im Bau, Obergrenze je Persönlichkeit (Wachstum und
Risiko 3, Netzwerker 2, Kostenoptimierer 1), Motiv seriös oder verspielt nach Persönlichkeit, zwei Palettenfarben, Name aus Motiv
und Firma. Test `test_stone_rule_brain` (6).
Benedikt (13.11.): „Die KI sollte selbständig mit den Baumaterialien, unter anderem den Steinen, random sich was Cooles als
Statue bauen.“ Daher zusätzlich: Werke aus **Stein** (12 Aufbereiteter Stein), **Bronze** (4 t), **Holz** (20 m³), **Stahl** (8 t)
oder **Beton** (15 Bauteile) – `StoneWorks.MATERIALS`, Aktion `create_stone_work` mit `material`; unbemalt zeigt das Werk die
Naturfarbe des Materials (Tönung, `StoneView`). Beobachtung kompakt (Token-Budget der lokalen Modelle): `jetzt_moeglich`,
`material_kosten` (nur machbare Materialien) und eine täglich wechselnde Anregung `idee` (Motiv/Material/Grundton/Akzent), die das
Modell nehmen, abwandeln oder ignorieren kann; die Aktionsbeschreibung betont, dass die Firma jederzeit aus eigenem Antrieb baut.
Das Regel-Gehirn wählt Motiv, Material und Farben zufällig. Sichtprüfung `--demo-werke`.

## Freies Bauen und KI für Gründer (13.11.2026)

Benedikt: „Was ich mir vorstelle: dass die KI Sachen vom Bauhof abholt und einfach darauf losbaut, Stein auf Stein oder Dach bauen
– das andere kann ja bleiben. Die neuen Spieler, die entstehen, werden nicht von der KI gesteuert.“

**Freies Bauen** (`FreeBuild`, `scripts/core/free_build.gd`, `sim.freebuild`; Aktion `free_build`): Die Firma entwirft ein Bauwerk –
Form `turm|haus|pyramide|mauer|bogen` mit Breite/Tiefe (2–8 Blöcke, 4 Blöcke = 1 Feld), Höhe (1–12 Schichten), Wandmaterial
(`stein|ziegel|holz|beton|glas|stahl`), Dach `sattel|zelt|flach|kein` mit Dachmaterial, Fenster aus Glas; oder frei als Bauplan
Schicht für Schicht (`"XXXX/X..X/X..X/XXXX"`, Zeichen X/S/Z/H/B/G/T/D/.). Höchstens 420 Blöcke, ein Bau zugleich, 4 fertige je
Firma; Platz auf dem eigenen Grundstück (gemeinsame Belegung mit den Steinwerken). Material je Block: Naturstein 1 t, Ziegel 10,
Holz 1 m³, Beton 1, Glas 2 m², Stahl 1 t – verbaut wird nur, was in den eigenen Lagern liegt (die Firma holt es mit `hub_buy` beim
Baustoffhandel des Großlagers mit eigenem Fahrzeug ab); fehlt etwas, wartet die Baustelle und die Beobachtung `freibau.bau.fehlt`
nennt die Menge. Gebaut wird mit 8 Blöcken je Spielstunde, Schicht für Schicht von unten, das Dach zuletzt. `FreeBuildView`
zeichnet die Blöcke als Iso-Würfel in Materialfarbe (verdeckte Flächen weggelassen, Glas durchscheinend, Ziegelfugen), auf der
Baustelle den nächsten Block als Umriss und Bauzaun-Ecken. Regel-Gehirn: fehlt Material → `hub_buy`; sonst selten (15 %) aus
Überschuss ein zufälliger Entwurf. Demo `--demo-freibau[=1]` (Ziegelhaus mit Fenstern und Holzdach, frei gezeichneter Glasturm).
Test `test_free_build` (18). Beobachtung insgesamt ~5 944 Token (Grenze 5 950).

**Gründer mit KI** (`GameSession.founder_profile_for`): Neu gegründete Firmen übernehmen reihum das KI-Profil der Startspieler
(Anbieter, Modell, Server, Takt, Budget, Schlüssel) mit eigenem Namen, eigener Persönlichkeit, ohne fremdes Gedächtnis und ohne
fremde Strategie; Demo-Startspieler oder `founders_ai: false` → Regel-Controller wie bisher. Test `test_founder_ai_profile` (5).

**Phase 7 Schritt 2 Ladung (13.11.):** Stadtlager-Bestellungen beim Großlager (`supplier L0`) fahren in Städten an der Linie mit dem
Güterzug (`CityDepot._to_rail`): die Stadt zahlt 60 % der Lkw-Fracht als Bahnfracht an N0, die Ware bleibt beim Großlager
reserviert, Status `bahn_wartet` → `bahn` (verladen) → am Bahnhof entladen (`rail_arrived`) → Stadt-Lkw vom Bahnhof ins
Stadtlager → wie bisher Wareneingang und Bezahlung. `RailTraffic.freight_queue`: der Güterzug lädt am Güterbahnhof die Sendungen
der Stadt mit der meisten wartenden Ware (bis 160 Einheiten; eine größere Sendung allein geht immer), Ziel = deren Bahnhof; ohne
Ladung wartet er („wartet auf Ladung“, schont die eingleisige Strecke). Kommt binnen 10 Tagen kein Zug, fährt die Bestellung doch
per Lkw. Anzeige „Güterbahn: wartend/befördert/Touren“. Test `test_rail_cargo` (14): 30 Ziegel, Bahnfracht 315 € statt 525 € Lkw,
Ankunft am Bahnhof nach ~1 100 Spielminuten, Stadt-Lkw liefert an.

**Prompt der lokalen Modelle (13.11.):** Log der Partie 22:04 – die Modelle sahen `steinbauten.jetzt_moeglich: true`, aber
`free_build` fehlte in der Aktionsliste der lokalen Modelle und der Steinwerke-Absatz verlangte noch Bergwerk + Steinmetz. Jetzt:
`free_build` in der Liste, gemeinsamer Absatz „Bauen aus eigenem Antrieb“ (Statue/Figur aus mehreren Materialien mit Idee; freies
Bauwerk Stein auf Stein mit Form oder Bauplan, Material per hub_buy).
