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

## Teil 2: Fleischkette (geplant)

Schweinemast und Rindermast als eigene Betriebe (Ställe, Weide, sichtbare Tiere, Futter aus Getreide), Viehtransport zum Schlachthof,
Metzgerei als Laden; Fleisch und Wurst gehen an Restaurants, Bürger (Einkauf) und Großlager. Wirkung auf den Kreislauf: Getreidenachfrage
der Bauern, Arbeitsplätze, Kühltransporte für die Transportfirmen, Preise und Versorgung der Bürger, Gründungsanreize.

## Teil 3: Eisenbahn (geplant)

Bahnhöfe je Stadt, Güterbahnhof am Großlager, Gleise mit Signalen, Personen- und Güterzüge nach Fahrplan, Strecken als
Regionalratsprojekt. Wirkung auf den Kreislauf: Pendler (Arbeitsmarkt über Stadtgrenzen), Güterverkehr Großlager ↔ Städte (Konkurrenz und
Zubringer für Lkw), Fahrgeldeinnahmen, Betriebskosten, Personal.
