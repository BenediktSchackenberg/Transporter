# Auftrag 19: Zentrales Großlager, Handelsplatz und autonome KI-Bürgermeister mit eigenen Bauideen

Eingang: 09.11.2026 (Benedikt). Baut auf Region (Auftrag 17, Generator 3 = Eckregionen), Stadtbild (Auftrag 18), Bauwesen,
Stadtlager (CityDepot) und den LLM-Bürgermeistern (MayorAgent) auf. Arbeit auf Branch `region` (Worktree `PTR_e`), Spiel aus `PTR_play`.

## Wortlaut (verbindliche Anforderungen, gekürzt auf die Kernaussagen, Abschnittsnummern wie im Auftrag)

1. **Grundidee:** großes, lebendiges Logistik- und Handelszentrum in der Kartenmitte, nutzbar von allen vier Städten, Bürgermeistern und
   KI-Unternehmen (anbieten, kaufen, verkaufen, abholen, transportieren). Kern: Jeder KI-Bürgermeister fährt alle 10 Spieltage persönlich
   zum Großlager, beschafft Baumaterial und entscheidet selbst und kreativ, welche Gebäude, öffentlichen Einrichtungen oder
   Sehenswürdigkeiten seine Stadt bekommt – keine bloß vorprogrammierten Entscheidungen. Zuerst Codebasis, KI, Straßennetz,
   Warenwirtschaft, Bauverwaltung und Pixelgrafiken analysieren.
2. **Großlager:** neutral, geografische Mitte, von allen vier Städten gut erreichbar. Hauptlager, mehrere Warenhallen, Hochregallager,
   überdachte Verladerampen, Baumaterialhandel, Großhandelsmarkt, Fahrzeug-/Maschinenhandel, Verwaltung, kleiner Händler-Marktplatz,
   große Lkw-Parkplätze, Stellplätze für Bürgermeisterfahrzeuge, Gabelstapler, animierte Lagerarbeiter, Warenannahme, Warenausgang,
   Zufahrten aus allen vier Himmelsrichtungen. Existiert ab Spielbeginn, am Straßennetz, detailreich im Pixel-Art-Stil. Waren und
   Fahrzeuge bewegen sich sichtbar; nichts wird teleportiert.
3. **Handelsplatz:** alle KI-Unternehmen kaufen/verkaufen dort. Waren: Baumaterial (Holz, Beton, Zement, Stahl, Glas, Ziegel, Sand, Kies,
   Asphalt, Rohre, Kabel, Maschinenbauteile), Handelsgüter (Lebensmittel, Möbel, Kleidung, Elektronik, Medizinprodukte, Haushaltswaren,
   Werkzeuge, Ersatzteile), weitere (Fahrzeuge, Bau-/Industriemaschinen, Dekoration, Kunstwerke, Pflanzen/Bäume, Spielplatzgeräte,
   Sportausrüstung). Jeder Händler kann anbieten; Preise nach Angebot, Nachfrage, Transportkosten; Zwischenhandel möglich. Echte
   Bestände, begrenzte Kapazität, nachvollziehbare Buchungen. Abholung nur mit Fahrzeugen. Zufluss vom Flughafen und lokalen Produzenten:
   Flughafenimport, Lager und Handel bilden einen zusammenhängenden Kreislauf.
4. **Bürgermeisterbesuche:** eigenes Dienstfahrzeug je Bürgermeister. Alle 10 Spieltage: Bedarfsanalyse im Rathaus → Überlegung →
   Projektentscheidung → Materialbedarf → Fahrt planen → persönlich fahren → parken → Beschaffung veranlassen → ggf. kommunaler Lkw →
   zurückfahren → Projekte beauftragen. Zeitversetzt. Material fahren Lkw, nicht die Limousine. Bisherige Regeln bleiben: öffentliche
   Standardmaterialien aus dem kommunalen Bestand kostenlos (sofern vorhanden), Sonderwaren/Zusätzliches regulär kaufen; jede Entnahme
   senkt den echten Bestand; fehlt Material: warten, Alternative oder verschieben.
5. **Herzstück:** keine Zufallsauswahl. Jeder Bürgermeister hat eine eigene Entwicklungsstrategie, beobachtet die Stadt, versteht
   Bedürfnisse und entwickelt eigene Projekte. Beispiele: Freizeit (Spielplatz, Park, Fußball-/Basketball-/Tennisplatz, Schwimmbad,
   Skatepark, Grünanlage, Picknick, Garten), Stadtgestaltung (Marktplatz, Brunnen, Rathausplatz, Fußgängerzone, Promenade, Stadtmauer,
   Denkmal, Statue, Aussichtsturm, Kunst), Infrastruktur (Kindergarten, Schule, Feuerwehr, Polizei, Krankenhaus, Bibliothek,
   Bushaltestelle, Parkhaus, Toiletten), Wirtschaft (Wochenmarkt, Gewerbepark, Logistikfläche, Handwerkerhof, Markthalle, Messe,
   Touristeninfo), Prestige (Bürgermeisterstatue, Triumphbogen, Riesenspringbrunnen, Rathausvorplatz, Veranstaltungshalle, Stadttor,
   Gründungsdenkmal, Wahrzeichen). Die KI darf weitere sinnvolle Projekte vorschlagen.
6. **KI-generierte Bauideen:** erweiterbarer Ideengenerator auf der vorhandenen LLM-Agentenarchitektur. Eingaben: Einwohner,
   Altersstruktur, Kinder, Arbeitsplätze, freie Grundstücke, Gebäude, fehlende Einrichtungen, Wirtschaftskraft, Baustellen,
   Zufriedenheit, Verkehr, Rohstoffe, Finanzen, Persönlichkeit. Danach Systemprüfung: Grundstück, Material, Arbeiter, Baufirma, Kosten,
   Dauer; dann Umsetzung (Beispiele Spielplatz, Marktplatz mit Händlern, eitle Statue auf dem Rathausplatz, auf die andere reagieren).
7. **Persönlichkeiten:** z. B. familienfreundlich, wirtschaftsorientiert, prestigeorientiert, sportbegeistert – nicht starr (dringender
   Bedarf geht vor), Persönlichkeit beeinflusst nur Vorlieben; Lernen aus Erfolg/Misserfolg der Projekte.
8. **Technik:** (A) KI-Bauplaner mit strukturierter Beschreibung, maschinenlesbare Antwort (project, category, reason, priority,
   desiredDistrict, features, materials, requiresConstructionCompany); Materialmengen berechnet das Bau-/Materialsystem. (B) Validator:
   Bauvorlage? darstellbar? Bauplatz? Straßenanbindung? Material? finanzierbar? Baufirma? Kollision? Maßstab? Unbekanntes aus vorhandenen
   Bauteilen zusammensetzen; nichts erfinden und als fertig darstellen; viele optisch verschiedene Kombinationen.
9. **Baukasten:** Spielplatz (Sand, Gras, Wege, Schaukeln, Rutschen, Klettergerüste, Bänke, Zäune, Bäume, Laternen), Marktplatz (Pflaster,
   Brunnen, Stände, Bäume, Bänke, Beete, Laternen, Denkmäler, Cafés), Sportplatz (Feld, Laufbahn, Tribüne, Umkleide, Flutlicht, Parkplatz,
   Zaun, Vereinsheim, später erweiterbar). Größe/Gestaltung/Anordnung entscheidet die KI. Anlagen existieren als zusammenhängende
   Gebäude-/Objektgruppen auf der Karte.
10. **Denkmäler:** Büste, Bronzestatue, Reiterstandbild, Steinstatue, Denkmal mit Brunnen, Obelisk, Ehrenplatz, Triumphbogen,
    Bürgermeisterdenkmal mit Grünanlage; Standort/Größe/Material/Gestaltung entscheidet die KI; jede Statue passt optisch zu ihrem
    Bürgermeister; nur vorhandene oder im Asset-System neu erstellte Grafik. Echtes Bauprojekt (Material, Bauzeit, Arbeiter). Wirkung:
    Touristen; überteuertes Prestige bei fehlender Grundversorgung senkt Zufriedenheit; Lernen daraus.
11. **Bauausführung:** Grundstück → Standort → Material → Fahrt zum Lager → Lieferung → Lkw zur Baustelle → Baufirma → Bauarbeiter →
    Bagger → weitere Lieferungen → sichtbar wachsender Bau → Eröffnung → Nutzung. Echter Nutzen (Freizeit, Zufriedenheit, Besucher,
    Handel, Familienattraktivität).
12. **Bewertung:** Punktesystem (Bedarf, wirtschaftlicher Nutzen, Zufriedenheit, Kosten, Material, Grundstück, Persönlichkeit,
    Stadtentwicklung, Vielfalt); mehrere Ideen bewerten, eigenständig wählen; begrenzte Kreativität gegen gleiche Reihenfolgen; dringende
    Infrastruktur vor Prestige.
13. **Langfristige Vision** je Bürgermeister, gespeichert, regelmäßig überprüft, änderbar; Städte entwickeln sich deutlich verschieden.
14. **Konkurrenz/Zusammenarbeit:** auf andere Städte reagieren (größerer Marktplatz, Stadion, Freizeitpark), Spezialisierung (Industrie,
    Tourismus, Wohnen) mit Transportaufträgen über das Großlager; Engpässe (Stahlknappheit) mit Reaktion (Flughafen, lokale Firmen).
15. **Sichtbare Bürgermeister:** Figur, Fahrzeug, Rathaus als Arbeitsplatz, Persönlichkeit, Strategie, Projekte, Entscheidungsverlauf;
    Fahrt Rathaus → Fahrzeug → Handelszentrum → sichtbare Abwicklung → zurück; optional Aufgabensymbol; Besuch der eigenen Denkmalbaustelle.
16. **Bürgermeisterfenster:** Ziel, zuletzt beschlossene Projekte, Baustellen, geplante Projekte, Materialbestellungen, Begründung,
    Zufriedenheit, Finanzen.
17. **Performance/Technik:** getrennt: Strategie-KI, Wirtschaft, Transport, Baustellen, Animation, Oberfläche. Nicht jede Entscheidung per
    LLM; Regeln für Einfaches, LLM für strategische/kreative Entscheidungen; alle KI-Ausgaben validiert; ohne LLM regelbasierter Bauplaner;
    Speichern/Laden korrekt.
18. **Abnahme:** neue Welt, vier kleine Städte, Großlager in der Mitte. Nach 10 Spieltagen fahren alle vier planmäßig zum Lager; vielfältige
    Entscheidungen (z. B. Spielplatz, Marktplatz, Denkmal, Fußballplatz – Beispiel, keine Vorgabe); Waren reserviert und per Fahrzeug
    transportiert; Baufirmen bauen. Danach erneute Analyse, Erfolgskontrolle, neue Entscheidungen; Städte werden optisch und wirtschaftlich
    völlig verschieden.
19. **Reihenfolge:** Analyse → Großlager → Handel/Bestände → Fahrzeuge + 10-Tage-Besuche → Bauplaner → validierter Ideengenerator →
    modulare Bauwerke → Denkmäler → Materialtransport + Bauausführung → Persönlichkeiten → Wettbewerb → Test von Spielstand/Leistung.
    Keine rein dekorative Simulation, keine fest geskripteten Standardentscheidungen; auch ungewöhnliche, lustige Entscheidungen.

**Ergänzungen (Benedikt, 09.11.):** Die KI entscheidet kreativ, *was* gebaut wird; die Engine entscheidet, *wie* es technisch und grafisch
umgesetzt wird (keine unbrauchbaren Gebäude auf Straßen). Bürgermeister kommentieren ihre Denkmäler gegenseitig und versuchen sich zu
übertreffen (kleine Statue → gigantisches Monument), humorvoll.

## Bestandsaufnahme (09.11.2026)

| Bereich | Vorhanden | Lücke für Auftrag 19 |
|---|---|---|
| Karte | `CornerRegionGenerator` (Generator 3): 4 Orte in den Ecken, Mitte mit Bergen (x 36–64 %), 2 Seen, Flussmündung ab x 58 % bei y 50 %; Landstraßen `_connect_towns` (A*, nur Ort k → k+1) | freie Mitte reservieren, Großlager-Gelände, Straßen aus vier Richtungen |
| Bürgermeister | `Mayor` (Regeln, `execute` mit ~20 Aktionen, Rat mit 3 Fraktionen, Projekte: Erschließung, Verbindung, Hafen/Flughafen/Netz, Brücke, Zufahrt), `MayorAgent` (LLM, Ollama/IONOS), `MayorBrain` (Regeln), Partei je Ort | Persönlichkeit, Vision, Bauideen, Besuchsfahrten, eigene Figur/Fahrzeug |
| Bauwesen | `Construction`: Bauvorhaben (Planning.DEFS: Wohnhäuser, Schule, Klinik, Läden, öffentliches Gebäude), öffentliche Projekte über Ausschreibung → Baufirma → `public` (Tage, Bautrupp), `BuildCrews` (Trupp-Lkw holt Material) | Projektart „Anlage“ aus Bauteilen, sichtbar wachsend, Nutzen |
| Material | `CityDepot` (CityGoods, Bestellvorschläge, Lieferanten Bauhof T0 / Import X0 / Firmen), `Trader` (Bauhof, MATERIALS), `StockBook` (Posten mit Eigentümer/Ort, Index) | Großlager als Lagerort mit Kapazität, Handel aller Beteiligten |
| Transport | Verträge (`Contract`), `Logistics`, Stadtfracht, Flughafen/Hafen-Import | Lieferungen Großlager ↔ Städte/Baustellen |
| Grafik | Voxel-Pipeline `tools/build_iso.py` + `tools/vox/*.py` → `assets/iso` + Manifest; vorhanden: Brunnen, Bank, Baum, Busch, Laterne, Kindergarten, Schule, Lager, Hallen, Kran, Laderampe, Stellplatz, Pflaster (PLAZA) | Schaukel, Rutsche, Klettergerüst, Sandkasten, Marktstand, Statuen, Obelisk, Bogen, Spielfeld, Tribüne, Flutlicht, Hochregal, Gabelstapler, Dienstwagen |
| Leben | `AmbientView` (Spots: Terrassen, Höfe, Hafenkran, Passanten), `EntityView` (Fahrzeuge/Figuren), `CityFleet` (kommunale Fahrzeuge) | Gabelstapler/Lagerarbeiter, Dienstwagen, Nutzer der Anlagen |

## Etappen

| # | Inhalt | Stand |
|---|---|---|
| 1 | Großlager im Generator 3: freie Mitte, Gelände mit Hauptlager, Hallen, Hochregal, Rampen, Baustoff-/Großhandel, Fahrzeughandel, Verwaltung, Marktplatz, Lkw- und Dienstwagenparkplätze, Zufahrten N/O/S/W, Landstraßen zu allen Städten; Register `city.hub` | **fertig** (Gelände 44×30 nach Bergen/Seen gewählt → Zufallsfolge und Städte unverändert, 15 Gebäude, Zufahrt je Stadt aus eigener Himmelsrichtung, kein Bauland im Gelände, Test `test_central_hub`, Kamera `--shot-hub`); Optik dünn bis Etappe 6 (große Hallen, Hochregal, Rampen, Stapler) |
| 2 | Handel: Lagerbestände mit Kapazität (StockBook-Ort), Angebote/Preise nach Angebot und Nachfrage, Kauf/Verkauf für Firmen und Städte, Abholung nur per Fahrzeug (Verträge), Zufluss Flughafen/Produzenten | offen |
| 3 | Dienstwagen je Bürgermeister, Figur, 10-Tage-Fahrt (zeitversetzt) Rathaus → Lager → zurück, sichtbar; Material per kommunalem Lkw | offen |
| 4 | Bauplaner: Stadtanalyse (Bedarfe), Ideen per LLM (JSON wie §8A) und Regel-Ersatz, Punktesystem §12, Persönlichkeit, Vision, Kreativität | offen |
| 5 | Validator + Baukasten: Vorlagen aus Bauteilen (Spielplatz, Marktplatz, Sport, Park, Platz, Denkmal …), Größen/Anordnungen, Platz-/Straßen-/Kosten-/Materialprüfung | offen |
| 6 | Neue Voxel-Bauteile (Spielgeräte, Stände, Statuen je Bürgermeister, Obelisk, Bogen, Spielfeld, Tribüne, Flutlicht, Hochregal, Stapler, Dienstwagen) | offen |
| 7 | Bauausführung: Projektart Anlage über Baufirma/Bautrupp/Materiallieferung, sichtbarer Baufortschritt, Eröffnung, Nutzen (Zufriedenheit, Besucher, Markt) | offen |
| 8 | Denkmäler, gegenseitige Kommentare, Überbieten; Wirkung auf Tourismus/Zufriedenheit; Lernen | offen |
| 9 | Persönlichkeiten + Lernen aus Erfolg/Misserfolg; Wettbewerb und Spezialisierung; Engpässe | offen |
| 10 | Bürgermeisterfenster (§16) | offen |
| 11 | Speichern/Laden, Leistung, Abnahmelauf §18 | offen |

## Entscheidungen

- **Was** gebaut wird, entscheidet die KI (LLM oder Regel-Bauplaner); **wie**, entscheidet die Engine: Vorlagen aus vorhandenen bzw. neu
  modellierten Bauteilen, Platzierung über die gemeinsame Bauprüfung (`EventDirector._add_building`), Material über das Bausystem.
- Großlager im Generator 3 (`corner_region_generator.gd`), damit der fremd bearbeitete `region_generator.gd` unberührt bleibt;
  ältere Spielstände (Generator 2) bleiben ohne Großlager.

## Stand

- 09.11.2026: Etappe 1 fertig. Hinweis: Im Worktree `PTR_e` liegen fremde ungesicherte Generatoränderungen (Palette/Marktplatz), die
  Ortsgrundrisse verändern und Straßenstummel erzeugen (Bauhof unerreichbar → Neuversuch). Auftrag 19 wird daher im sauberen Worktree
  `PTR_hub` entwickelt.
