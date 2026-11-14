# Auftrag 23: Lebendige Welt

Wunsch (14.11.2026): Die Städte sollen bei jedem Start anders aussehen, schön und mit viel Liebe zum Detail. Autobahnen und
Landstraßen sollen nicht im Zickzack verlaufen. Bauen und Warten von Gebäuden und Straßen soll detailliert zu sehen sein, mit
Arbeitern, die aktiv etwas tun. Die KI steuert die Arbeiter einzeln, am besten alle Bürger, und alle tun im Spielzusammenhang
sinnvolle Dinge.

## Entscheidung: wer steuert die Bürger?

Ein Sprachmodell je Bürger ist nicht machbar: Ein lokales Modell (qwen3.5:9b) braucht 5 bis 60 s je Antwort, die Region hat
mehrere hundert Bürger. Deshalb:

- **Bürger-KI (regelbasiert, jeder Bürger einzeln):** Jeder Bürger hat einen Tagesplan aus seinem echten Zustand (Wohnung, Arbeitgeber,
  Arbeitszeit, Bedarf, Wetter, Wochentag): schlafen, zur Arbeit gehen, arbeiten, einkaufen, Arzt, Freizeit, nach Hause. Jede Tätigkeit
  hängt an einem Spielsystem (Lohn, Umsatz der Läden, Stimmung, Verkehr).
- **Arbeiter:** Bau- und Wartungstrupps bestehen aus einzelnen Arbeitern mit eigener Aufgabe (anliefern, ausheben, mauern, Dach decken,
  asphaltieren, ausbessern). Die Firmen-KI (Sprachmodell oder Regel-KI) teilt ihre Arbeiter weiterhin einzeln ein (`assign_worker_task`).
- **Sprachmodelle** entscheiden dort, wo es zählt: Firmen, Bürgermeister, Disposition; dazu einzelne Sprecherfiguren.

## Phasen

1. **Straßen ohne Zickzack:** Landstraßen, Zufahrten zum Großlager, neue Verbindungen und Autobahnzubringer werden nach der Wegsuche
   begradigt (`PathStraighten`): lange Geraden, rechtwinklige Kurven, höchstens 48 Wegpunkte je L, damit der Weg nahe an der gesuchten
   Trasse bleibt. Messung (`tests/probe_roads_shape.gd`, Seed 97089): Kurvenfelder der Landstraßen 19,0 % → 1,9 %.
2. **Jede Karte anders (Generator 4):** Orte liegen mal weit außen, mal näher an der Mitte; der Fluss mündet im Osten oder Westen
   mit eigenem Lauf; 3–5 Gebirge und 2–4 Seen in wechselnder Größe; Straßenraster und Ortskern mit Zufallsversatz, Gewerbezeile
   mal im Süden, mal im Norden; vier von sechs Ortstypen je Partie (neu: Kurort mit Promenade, Villen, Kurhaus und Kurbrunnen;
   Hafenstadt mit engem Raster, Mietshäusern, Kran, Containerlager und Hafenkneipe). Spielstände mit Generator 2/3 behalten ihre
   Karte. Prüfung: `test_world_variety`, Bilder: `tests/probe_world_variety.gd`.
3. **Baustellen im Detail (`SiteView.SiteNode`):** Bauzaun mit Betonfüßen, offenem Tor und Bauschild in Firmenfarbe; Baucontainer, WC
   und Materiallager je Phase (Schotter, Bewehrungsstahl, Steinpaletten, Holz, Ziegel, Fensterscheiben); Schnurgerüst, Baugrube
   mit Böschung, Bodenplatte mit Bewehrungskorb, Mauerwerk mit Fugen und Fensteröffnungen, Fassadengerüst mit Bohlen, Geländer und
   Netz, Dachstuhl mit Sparren über der Geschossdecke, Ziegel, fertige Hülle mit Glas. Geräte aus `CrewArt` (Kettenbagger, Kipper
   mit Mulde, Fahrmischer mit Schütte, Turmdrehkran mit Gittermast, Laufkatze und Last). Polier-Regeln geben jedem Arbeiter eine
   eigene Aufgabe: graben in der Grube, betonieren, mauern auf dem Gerüst, Dach decken, Material vom Lager tragen und abladen,
   nachmessen; bei Baustopp steht der Trupp am Container. Straßenbaustellen: Baken und Leitkegel, abgefräste Decke, frischer
   dampfender Asphalt, Walze, Rüttelplatte, Sicherungsposten; Leitungsbau mit Graben, Rohr und Bagger.
   Sichtprüfung: `tests/probe_site_art.gd` (ohne Partie) und `--shot-site=bau|road|fleet|works` im Autotest.
4. **Bürger-KI:** Tagespläne für alle Bürger, sichtbar als Fußgänger und Pendler mit Ziel; Auswirkungen auf Umsatz, Verkehr und Stimmung.
