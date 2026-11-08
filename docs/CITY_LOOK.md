# Auftrag 18: Gebäudeplatzierung, lebendige Stadtviertel, Hafen und Küstenatmosphäre

Eingang: 08.11.2026 (Korrekturauftrag von Benedikt; die erwähnten zwei Spielbilder lagen nicht bei). Ergänzt Wirtschaft, Region (Auftrag 17)
und Tourismus. Arbeit auf Branch `region` (Worktree `PTR_e`), Spiel aus `PTR_play`.

## Wortlaut (verbindliche Anforderungen, gekürzt auf die Kernaussagen, Abschnittsnummern wie im Auftrag)

1. **Ziel:** (a) Gebäude stehen geometrisch und optisch korrekt auf ihren Grundstücken; Häuser, Bodenplatten, Gärten verdecken/blockieren
   keine Fahrbahn. (b) Zusammenhängende, gewachsene Stadt: abwechslungsreiche Gebäude, passende Straßenräume, erkennbare Viertel, Plätze,
   genutzte Freiflächen. (c) Hafen mit Anlagen, Kränen, Hafenarbeitern, Umschlaggeräten und sichtbarer Arbeit an echten Warenbewegungen.
   (d) Küste/Strand mit Atmosphäre: Ufer, Promenade, Aufenthaltsorte, Vegetation, Licht, Wasserbewegung, Leben. Ursachen aus Daten, nicht
   aus dem Bild ableiten. Korrekturen im bestehenden Code/Asset-System, Vergleichsansichten aus dem laufenden Spiel.
2. **Ausgangsstand/Prioritäten:** parallele Arbeit erhalten, keine alten Komplettfassungen. Reihenfolge: Platzierung/Erreichbarkeit →
   Stadtgrundriss + tatsächlich genutzte Gebäudegrafiken → Hafenabläufe → Küstengestaltung. Wirtschaft bleibt spielbar. Bestehende
   Vorgaben bleiben: mehrere Städte, 4 Eckregionen bei 4 Spielern, ≤ 40 fertige Startgebäude je Stadt, viel unerschlossenes Land,
   wirtschaftlich begründetes Wachstum; keine kostenlosen Großbauten.
3. **Straßenüberlappungen an der Ursache:** getrennt prüfen: logische Belegung, Asset-Geometrie, Projektion/Anker, Zeichenreihenfolge.
   Schaltbare Diagnoseansicht (belegte Kacheln, Grundstücksgrenzen, Straßen/Gehwege, Fußpunkt, Eingang, Lieferzugang, Auswahlfläche,
   geladener Asset-Schlüssel + Variante). Gemeinsame Bau-/Platzierungsprüfung für alle Entstehungswege (Weltstart, Neubau, Ausbau,
   Hofvergrößerung, öffentliche Gebäude, Straßenprojekte, Stadtentwicklung); endgültiger gedrehter Grundriss inkl. Anbauten; Eingang mit
   Fußweg, Lieferzone mit Zufahrt; Straßenprojekte beachten Eigentum/Bebauung (Blockade oder Alternative, nie Straße unter ein Haus).
4. **Stadtgrundriss:** kompakter Kern (Rathaus/Markt/Hauptstraße), Ladenfronten zum Gehweg, unterschiedliche Block-/Grundstücksgrößen,
   Wohnstraßen, T-Kreuzungen, Stichstraßen, Fußwege, Höfe, Plätze; Straßen nach Funktion (überörtlich, Hauptstraße, Wohnstraße,
   Hafenzufahrt, Promenade); Ampeln/große Markierungen nur an belasteten Stellen. Charaktere: Ortskern, Wohnviertel, Hafen/Gewerbe,
   Strand/Promenade, Ortsrand. ≥ 60 % unerschlossenes bebaubares Land, Reserve vor allem außerhalb des Kerns.
5. **Gebäudevielfalt:** ≥ 8 deutlich unterscheidbare Wohnhausvarianten aus ≥ 4 Bauformen (Baukörper, Geschosse, Dach, Fenster, Eingang,
   Balkon/Anbau), nicht nur Umfärbung; Geschäfte/Restaurants/Büros/Werkstätten/Lager mit lesbarer Nutzung; Material-/Farbpalette je
   Viertel/Stadt; keine identischen Nachbarn; seedstabil; Variante ändert Grundriss nicht heimlich; kein bloßes Spiegeln.
6. **Asset-Kette prüfen:** Modell → Export → Manifest (Maße, Anker) → Variante → geladene Textur → Darstellung/Auswahl. Laden alle
   denselben Schlüssel? Veraltete Importe/Fallbacks/Caches. Build/Import ausführen, Vollständigkeitsprüfungen, Nachweis im laufenden Spiel
   (Ortskern- und Wohnstraßenansicht).
7. **Hafen als Arbeitsort:** Kaikante, Liegeplatz, Hafenlager, Ladefläche, kleiner Kran, Zugänge; Poller, Fender, Markierungen, Paletten/
   Kisten. Grundausstattung zur Ortsgröße, Ausbau bei Bedarf. Schiffe erreichen den Liegeplatz über Wasser; Kran erreicht Schiff und
   Umschlagfläche; Stapel blockieren nichts. Lagerbestand zusammengefasst sichtbar (leer/voll unterscheidbar). Hafen vom Badestrand getrennt.
8. **Hafenarbeiter und Kräne an realen Vorgängen:** Personal mit Arbeitgeber/Ort/Lohn/Aufgaben; Kette Ankunft → Liegeplatz → Anlegen →
   Entladeauftrag → Kran/Arbeiter → Umschlagfläche → Einlagerung → Abholung (Export umgekehrt); Zustände (Anfahrt, Warten, Anschlagen,
   Heben, Schwenken, Absetzen, Lagern, Rückkehr); Personal, Geräte, Lager, Liegeplätze begrenzen den Umschlag; Ware nie doppelt verfügbar;
   Warenbuch/Reservierungen nutzen; keine doppelten Zahlungen/Löhne; Eigentümer passt zur Stadt/Firma; KI kann bei Engpass Personal,
   Geräte, Lager, Liegeplatz finanzieren; ehrlicher Leerlaufgrund; keine künstlichen Aufträge für Animation.
9. **Küstenatmosphäre:** Ufermasken/Übergänge Wasser-Sand-Land, Naturstrand vs. Kaikante; flaches Wasser, Wellen, Schaum, weniger
   Wiederholung; Strandgras, Felsen, Treibholz, Bänke, Wege, Steg, Uferlicht; ausgebauter Strand mit Schirmen, Liegen, Strandbar,
   Promenade nach Entwicklungsstufe; Licht (Abendfenster, Promenade, Schatten); Wetter/Tageszeit respektieren; Gäste gehen zu echten Zielen.
10. **Stadtdetails mit Zusammenhang:** Straßenbäume, Hecken, Vorgärten, Zäune, Blumen, Bänke, Haltestellen, Schilder nach Regeln;
    Übergänge Tür-Gehweg, Gartentor-Weg, Lieferhof-Zufahrt, Platz-Straße, Strandzugang-Promenade; freie Flächen mit Funktion; Deko
    blockiert keine Zufahrten; seedstabil.
11. **Spielstände erhalten:** IDs, Bewohner, Besitz, Mieten, Hypotheken, Betriebe, Bestände, Aufträge; Renderfehler nur in der Darstellung
    korrigieren; echte logische Überschneidung: dokumentierte Standortkorrektur mit Identität; Grundriss-Änderungen nur für neue Welten/
    Wachstum; Migration mit Versionsnummer und Sicherung; Hafenmigration ohne doppelte Einfuhr.
12. **Umsetzung/Leistung/Abnahme:** Sichtbarkeitsbereiche, Kapazität von Spielzeit statt Bildrate. Abnahme:
    - mehrere Seeds + neue Bau-/Ausbauvorgänge: keine unzulässige Überschneidung Grundfläche/Straße/Baukörper/Korridor;
    - Diagnose zeigt Grundstücke, Anker, Eingänge, geladene Varianten; Bodenplatte, Standort, Auswahl passen;
    - Fußgänger/Lieferfahrzeuge erreichen Gebäude über gültige Zugänge; Straßenbau überbaut keine Häuser;
    - ≥ 8 Wohnhausvarianten im laufenden Spiel sichtbar, Wohnstraße nicht nur identische Doppelhäuser;
    - neue Stadt mit kompaktem Kern, Nachbarschaften, abwechslungsreichen Grundstücken; Freiflächen vor allem am Rand;
    - Startgebäudelimit, 4 Eckregionen, Küstenzugang bleiben;
    - Schiff wird abgefertigt, Arbeiter und Kran übernehmen Aufgaben, Ladung/Bestände konsistent;
    - fehlendes Personal/Gerät bremst, finanzierte Erweiterung erhöht Leistung; nichts doppelt gezählt;
    - Küstenabschnitt mit Naturufer/Kaianlage, schönen Übergängen, stimmiger Abendansicht; Wege und Hafen nutzbar;
    - Speichern/Laden erhält Varianten, Eigentum, Bestände, Hafenfortschritt; keine neuen Firmen/Bewohner durch Reparaturen.

## Etappen

| # | Inhalt | Stand |
|---|---|---|
| 1 | Platzierungsdiagnose (Daten + Ansicht), Geometrie-/Ankerkorrektur, gemeinsame Bauprüfung, Straßenprojekte ohne Überbauung | fertig (08.11.2026) |
| 2 | Kompakter Startort, Straßenfunktionen, Viertel; Gebäudevielfalt durch die ganze Asset-Kette | weitgehend (08.11.2026) |
| 3 | Hafenanlagen, Hafenarbeiter, Kran-Arbeitsablauf an Warenbuch und Personal | fertig (08.11.2026) |
| 4 | Küste: Übergänge, Wasser, Strandausstattung, Licht, Stadtdetails | offen |

## Stand

### Etappe 1 (08.11.2026)

Befund aus den Daten (`tests/probe_placement.gd`, Seeds 21/4242/7/99 beim Start, Seed 21 nach 40 Spieltagen Wachstum):
- **Logisch keine Überschneidung**: kein Gebäuderechteck auf Straße/Gehweg/Schiene/Wasser, keine Doppelbelegung, jedes Gebäude mit
  Straßenzugang; Projektion einheitlich (Manifest 128x64 je Feld = Spielumrechnung).
- **Ursache der Darstellung**: `EventDirector._add_building` (alle Neubauten im Spiel) belegte das Baufeld der Planung (Einfamilienhaus
  5x4, Mehrfamilienhaus 6x5, Laden 4-5x3-4), gezeichnet wurde das Bild mit seiner eigenen Grundfläche (2x2 bzw. 3x3) an der hinteren
  Ecke - Sortierung/Streifen rechneten mit 5x4, daher leere Rasenflächen und Häuser, die vor Straßen gezeichnet wurden. Zusätzlich bekam
  jeder Neubau `info[0][0]` (immer dieselbe Variante) und die Zellen wurden schon vor der Straßenprüfung blockiert.
- Straßenbau (`AccessRoads._apply_cells`, `Bridges._open`) prüfte beim Bauen nicht erneut auf Gebäude.

Behoben:
- **Gemeinsame Bauprüfung** `_add_building`: Gebäude belegt die Bildgrundfläche, straßenseitig im Baufeld (`lot` bleibt Garten/Hof);
  keine Zelle auf Straße/Wasser/Schiene/Rollbahn/fremdem Gebäude/geplanter Zufahrt (`AccessRoads.reserved`); Belegung erst nach allen
  Prüfungen; seedstabile Variante, verschieden von den Nachbarn (Schrittweite 3 wechselt auch die Bauform).
- **Spielstände**: Neubauten im Protokoll mit `v: 2`, Grundfläche und Variante → Laden stellt exakt wieder her; alte Einträge (v1) behalten
  ihre gespeicherte Grundfläche, die Darstellung setzt das Bild straßenseitig ins Rechteck (`CityView.sprite_cell`).
- **Straßenbau** legt nie eine Straße unter ein Gebäude (Zelle wird übersprungen und gemeldet).
- **Diagnoseansicht** (F8, `scripts/world/placement_overlay.gd`, Autotest `--shot-placement`): Baufeld, belegte Zellen, Bildgrundfläche,
  Eingang, Lieferzugang, Straßen/Gehwege, Asset-Schlüssel.
- Test `test_building_placement` (17 Prüfungen).

### Etappe 2 (08.11.2026)

Asset-Kette geprüft: 8 Wohnhaus-Bauformen (`tools/vox/residential.py`: Satteldach mit Garage, Bungalow, moderner Kubus, L-Haus, schmales
Stadthaus, Bauernhaus mit Scheune, Cottage mit Erker, …) je 6 Material-/Farbvarianten (`house<n>s<k>`), Manifest-Grundflächen passen
(Diagnose `probe_placement`). Die Monotonie kam aus (a) Neubauten immer Variante 0 (Etappe 1 behoben) und (b) zufälliger Streuung der
Startbebauung über ein großes Rechteck.

Umgesetzt (gilt für neue Welten; bestehende Orte werden beim Laden nicht verschoben):
- Kompakter Kern: Wohnhäuser von der Ortsmitte nach außen (Radius wächst mit jedem Haus), Freiflächen vor allem am Rand.
- Marktplatz vor dem Rathaus (Pflaster, nicht bebaubar, Bänke, Laterne).
- Ortspalette: je Ort 3 der 6 Material-/Farbvarianten, alle 8 Bauformen; nie dasselbe Modell wie ein Nachbar (`CityGenerator._variant`).
- Ampeln nur an Vierwege-Kreuzungen ≤ 12 Felder von einer Ortsmitte (`CityData.signals`); Fahrzeuge halten nur dort.
- Autotest `--shot-town=<k>` (Kamera aufs Rathaus).
- Bilder: `town_vorher.png`/`town_nachher.png`, `core_nachher.png` (app_userdata).

Offen in Etappe 2: Blockinneres (Gärten/Höfe/Wege), Straßen nach Funktion in der Grafik (Breite/Randgestaltung), Zebrastreifen der
Kreuzungsgrafik nur an Ampelkreuzungen.

### Etappe 3 (08.11.2026)

- Abfertigung (`Harbor`): Ankunft → Anfahrt (`APPROACH_MIN` 40, gleich der Schiffsansicht) → Anlegen → Posten für Posten durch Kran und
  Hafenarbeiter (`on_minute`, Leistung = Personal × 0,5 × Kranfaktor 2,5 × Hafenstufe) → Einfuhr erst beim Absetzen ins Warenbuch bzw. an
  Stadtlager/Bauhof, Ausfuhr verlässt das Lager erst beim Verladen → Abfahrt erst nach getaner Arbeit. Ein Liegeplatz: das nächste Schiff
  wartet auf Reede. Ehrlicher Leerlaufgrund (`idle_reason`: Schiff legt an, kein Personal, nächstes Schiff in n Tagen, abgefertigt).
- Personal: Arbeitgeber `hafen` (Bürger der Stadt, Lohn über die normale Lohnabrechnung, genau einmal); Grundbesetzung 2, bei Engpass
  stellt die Hafenverwaltung bis 6 ein; Kran-/Stufenausbau über die vorhandenen Hafenstufen.
- Darstellung (`AmbientView`): Kran auf dem Anleger folgt dem aktuellen Posten (Anschlagen, Heben, Schwenken, Absetzen, leer zurück; Last
  in Farbe der Warengruppe; Ausfuhr umgekehrt), Hafenarbeiter pendeln mit Kisten zwischen Kran und Lager, Lagerplatz mit Kistenstapeln
  nach Bestand (Paletten bei leerem Lager), Leerlaufgrund über dem Kran; Anleger mit Fendern und Festmacherleinen beim Liegen.
- Tests: `test_harbor_handling` (12 Prüfungen); bestehende Logikprüfungen laufen mit `Harbor.default_instant` (Sofortabfertigung) weiter.
- Bild: `hafen_arbeit.png` (app_userdata).

### Etappe 4, Teil 1 (08.11.2026)

- Bodenebene `AmbientView.GroundOverlay` (unter Gebäuden, nur sichtbarer Ausschnitt): Flachwasser und auflaufende Schaumkanten an
  Naturufern (Schaumstärke nach Wind; Kaikanten bleiben gerade ohne Schaum), Hecken oder weiße Lattenzäune um Wohnhäuser mit
  Gartentor zur Straße und Blumen im Vorgarten.
- Strand: Dünengras zur Landseite (wiegt im Wind), Steine, Treibholz an der Wasserlinie, Laterne an Strandabschnitten mit Straße
  (abends warmes Licht).
- Offen: Bänke/Wege am Strand, Steg, Abendstimmung über die Laternen hinaus, Blockinnenbereiche.
