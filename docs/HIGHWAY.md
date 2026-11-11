# Auftrag 21: Autobahn, Fleischkette, Eisenbahn

Eingang 10.11.2026 (Benedikt): „1, 2, 3 – 2 und 3 müssen auch Auswirkung auf den Wirtschaftskreislauf gesamt haben.“
Arbeit im Worktree `PTR_hub`, Veröffentlichung auf `region`, `main`, `unternehmer`.

## Teil 1: Autobahn (fertig 10.11.2026) – Test `test_highway`, Probe `tests/probe_highway.gd`, Sichtprüfung `--demo-highway`

* **Verkehrszählung** (`RegionalProjects.count_traffic`): RoadCare meldet vor dem Tageswechsel die Fahrzeugsekunden je 16×16-Abschnitt;
  Überland = Abschnitt weiter als 40 Felder vom nächsten Ortszentrum. Je Tag Summe und Zuordnung zur nächsten Stadt (30 Tage).
  Messung Seed 4242: frühes Spiel ≈ 1 300 Fahrzeugsekunden/Tag, gewachsene Region (Nachspiel Seed 14939, Tag 274) ≈ 2 700.
* **Antrag**: Regel-Bürgermeister beantragen die Autobahn im Regionalrat, wenn der Überlandverkehr im 14-Tage-Mittel 2 000 übersteigt und
  ihre Stadt die Strecken überdurchschnittlich nutzt; KI-Bürgermeister über `regionalrat_antrag` mit `autobahn`. Abstimmung 3 von 4,
  Nutzen nach eigenem Verkehrsanteil, Verhandlung wie bei anderen Anträgen.
* **Trasse** (`plan_highway`): Städte nacheinander nach Lage um die Kartenmitte; je Abschnitt Landweg (kein Wasser, keine Berge, keine
  Gebäude, vorhandene Straßen nur kreuzen), zweibahnig (Parallelfeld je Schritt), Anschlussstelle am nächsten Ortsstraßenfeld jeder Stadt,
  Kreuzungen dort, wo die Trasse Straßen quert. Typisch ≈ 1 900–2 400 Felder, 4 Anschlussstellen, 2–4 Kreuzungen, 1,3–1,6 Mio. EUR, 48–60 Bautage.
* **Finanzierung**: Bund 95 % (X0 → Baufirma bei der Abnahme), Städte 5 % nach Nutzungsanteilen der Verkehrszählung (mindestens 5 % je Stadt).
* **Bau**: ein Bauauftrag über Ausschreibung und Baufirma (Material beschafft die Baufirma, im Preis); auf der Karte erst abgesteckte
  Trasse (Erdreich, Pflöcke), dann wächst der Asphalt mit dem Baufortschritt (Leitplanken, Fahrstreifen, Baken an der Baustellenspitze),
  blaue Schilder „A Stadt“ an den Anschlussstellen (`scripts/world/highway_view.gd`).
* **Wirkung**: bei der Abnahme befahrbar; Fahrzeuge fahren dort 1,8-mal so schnell, die Wegsuche bevorzugt die Autobahn (Gewicht 0,55).
* **Leitstelle** (Öffentliche Dienste & Regionalpolitik): Verkehrszählung, Nutzungsanteile, Autobahn mit Status, Kosten, Bund, Baufortschritt,
  Sprung zur Trasse. Lagebericht der Bürgermeister: `kommunale_dienste.autobahn`.

## Teil 2: Fleischkette (fertig 10.11.2026) – Test `test_meat_chain2`, Sichtprüfung `--demo-meat=schweinemast|rindermast|schlachthof|metzgerei`

* **Betriebe** (`config/branches.json`): Schweinemast (Maststall, Futtersilos, Güllebehälter, Auslauf; Ferkel + 2 dt Getreide →
  Mastschwein nach 10 Tagen, 60 Plätze), Rindermast (Laufstall bzw. Offenstall, Weide, Fahrsilo, Heuballen; Kalb + 6 dt Getreide →
  Mastrind nach 20 Tagen, 24 Plätze), Schlachthof mit zwei Linien (`rezept_varianten`: Mastschwein → 90 Portionen Fleisch, Mastrind →
  380 Portionen; alte Schlachttiere weiter), Metzgerei (Fleisch → Wurst und Aufschnitt; mit Verkaufskraft öffnet die Theke für Haushalte).
* **Waren** (`config/articles.json`): Ferkel, Kälber (Zukauf von außerhalb), Mastschweine, Mastrinder (neue Ladungsart **Lebendvieh**
  in `Catalog.CARGO`, eigene Ladungskiste), Wurst (gekühlt, 6 Tage haltbar).
* **Gebäude** (`tools/vox/meat.py`): je 4 strukturell verschiedene Varianten für Schweinemast (4×3), Rindermast (4×4), Schlachthof (4×3,
  Kühlhaus mit Kälteaggregaten, Viehrampe, Kühl-Lkw-Rampen, Schornstein) und Metzgerei (2×2, Schaufenster mit Auslage, rot-weiße Markise,
  Schild, teils Wurststand). Tiere stehen im Bild; zusätzlich laufen Rinder auf der Weide und Schweine im Auslauf (Kartenleben), ihre
  Zahl folgt dem tatsächlichen Stallbestand.
* **Kreislauf**: Mastbetriebe kaufen Getreide (Ackerbau der Region oder Import) und Jungtiere, verkaufen per Liefervertrag an den
  Schlachthof (Lebendvieh-Transporte als Aufträge für die Transportfirmen); der Schlachthof wählt täglich die Linie mit Tieren auf Lager und
  liefert gekühlt an Metzgereien, Restaurants (Braten), Großhandel oder Ausfuhr; die Metzgerei verkauft Wurst an die Haushalte (Kundschaft
  wie Bäckereien, geteilt zwischen Metzgereien einer Stadt). Gründer erkennen fehlende Metzgereien ab 80 Einwohnern und fehlende Vorstufen
  (Restaurant wartet auf Fleisch → Schlachthof; Schlachthof wartet auf Mastschweine/-rinder → Mastbetrieb). Einkauf nur unter dem
  Erlöswert (Rind: 380 Portionen ≈ 1 160 EUR gegen 900 EUR je Mastrind).
* **Test**: Gründung aller vier Betriebe, Mastzeiten (Schweine Tag 13, Rinder Tag 23), Verbrauch (37 Ferkel, 24 Kälber, 218 dt Getreide),
  beide Schlachtlinien, Lebendvieh-Aufträge, 2 550 Portionen Wurst, Thekenverkauf ≈ 5 500 EUR, Geld- und Warenbilanz erhalten.
* **Grenze**: Wurst liegt nicht im Sortiment der allgemeinen Lebensmittelläden (das verschob deren Einkauf und Verkauf); sie verkauft
  sich über die Metzgerei-Theke und den Großhandel.

## Teil 3: Eisenbahn (geplant)

Bahnhöfe je Stadt, Güterbahnhof am Großlager, Gleise mit Signalen, Personen- und Güterzüge nach Fahrplan, Strecken als
Regionalratsprojekt. Wirkung auf den Kreislauf: Pendler (Arbeitsmarkt über Stadtgrenzen), Güterverkehr Großlager ↔ Städte (Konkurrenz und
Zubringer für Lkw), Fahrgeldeinnahmen, Betriebskosten, Personal.

## Nachtrag 11.11.2026: gerade Trasse statt Zickzack

Benedikt: „wie er gerade die Autobahn baut … Zickzacks, das macht keinen Sinn“. Ursache: die Trasse kam aus der feinen Wegsuche ohne
Diagonalen; bei schrägen Verbindungen sind alle Treppenwege gleich lang, die Wegsuche wählte Zickzack (Seed 4242: 85 Richtungswechsel),
und die zweite Fahrbahn wechselte bei jedem Schritt die Seite. Jetzt plant `RegionalProjects.plan_highway` die Hauptstrecke auf einem
4×4-Grobraster mit Strafkosten je Richtungswechsel (`HW_TURN`): lange Geraden, rechtwinklige Kurven, beide Fahrbahnen fest in einer
Spur des Blocks; spätere Abschnitte nutzen schon geplante Strecke mit (`HW_REUSE`, keine Parallelautobahn). Nur die kurzen Zubringer
zur Anschlussstelle nutzen die feine Wegsuche. Seed 4242: 6–8 Richtungswechsel. Eine noch nicht fertige Autobahn aus einem älteren
Spielstand wird am nächsten Spieltag einmal neu trassiert (`trasse: 2`; Kosten und Bauzeit bleiben). Bild der Trasse:
`tests/probe_highway_route.gd [-- --seed=… --out=…]`.
