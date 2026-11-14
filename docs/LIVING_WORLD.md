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
2. **Jede Karte anders:** Lage der Orte, Küstenlinie, Fluss (Seite, Lauf), Zahl und Größe von Bergen und Seen nach Seed; Ortsbild
   nach Charakter mit zufälligem Straßenraster, Ortskern an wechselnder Stelle, Wahrzeichen und Details (Brunnen, Bänke, Gärten,
   Alleen, Kirche, Kneipe, Pension).
3. **Baustellen im Detail:** Bauphasen mit Gerüst, Kran, Materialstapeln, Lieferwagen; Arbeiter mit sichtbarer Tätigkeit je Phase.
   Straßenbau und -wartung: Absperrung, Fräse, Walze, Asphaltkocher, Arbeiter mit Schaufel und Rüttelplatte.
4. **Bürger-KI:** Tagespläne für alle Bürger, sichtbar als Fußgänger und Pendler mit Ziel; Auswirkungen auf Umsatz, Verkehr und Stimmung.
