# Auftrag 16: Flughafen im Küstenort – Fluganimation, Luftfracht, Passagiere, Ausbau, Feuerwehr

Eingegangen am 06.11.2026 (Benedikt). Der Küstenort (Auftrag 15) bekommt einen kleinen Flughafen:
sichtbare Flugbewegung über der Karte, wirtschaftlicher Betrieb (Luftfracht, Auslandsreisen),
Wachstum über Stadtprojekte und eine eigene Flughafenfeuerwehr. Die Weltart „Küstenort" ist
Voraussetzung; im Rasterstadtl-Modus und in alten Spielständen ohne Airport baut der Generator
keinen Flughafen und alle Systeme bleiben aus (kein Verhalten, keine Kennzahlen).

## Anforderungen (Zusammenfassung)

1. **Gebäude:** Flughafen westlich des Orts auf flachem Grund (weg vom Meer), Startbahn, Vorfeld,
   Terminal, Tower, Hangar, Frachtterminal, Flughafenfeuerwehr; vier neue Voxel-Gebäude,
   neue Bodenarten (Startbahn, Vorfeld), L-förmiger Straßenanschluss an das Straßennetz;
   deterministisch (gleicher Seed → gleiche Welt), im ≤40-Gebäudelimit.
2. **Fluganimation:** kleines Propellerflugzeug erscheint am Kartenrand, setzt auf der Startbahn
   auf, rollt zum Vorfeld, steht zur Abfertigung und steigt wieder ab; reine Funktion der Spieluhr
   (deterministisch, nahtloses Speichern/Laden ohne Flugzustand); Bodenschatten bleibt unten.
3. **Luftfracht:** Bestellungen des Stadtlagers fliegen per Luftfracht (25 % Aufschlag, nur
   Kritikalität 3); Ware liegt „in der Luft" und kommt bei der nächsten Landung; Wetter-Gate
   (Starkregen, Sturm, Schnee, Glätte, dichter Nebel → Flug fällt aus); Abwicklung wie am Hafen
   (Auftrag 15, Etappe C): X0-Ware im Frachtterminal, Transportauftrag ins Stadtlager,
   Betreiberpauschale.
4. **Passagiere:** Bürger buchen Auslandsreisen (Urlaub, Familie, Arzt, Geschäft); Ticket aus dem
   Bürgerguthaben, Landegebühr an die Stadt; Ab- und Rückflug mit dem Linienverkehr; Reisende
   laufen nicht auf der Karte.
5. **Ausbaustufen:** Flughafen wächst über Stadtprojekte des Bürgermeisters (Baufirma, Material
   aus dem Stadtlager) durch Stufen mit mehr Plätzen, mehr Frachtplatz, höheren Gebühren;
   die Regel-KI baut bei Rückstau aus.
6. **Feuerwehr/Notfälle:** die Flughafenfeuerwehr ist ein echtes Fahrzeug mit Einsatz: bei
   Alarm fährt es zum Frachtbereich, das Feuer kostet Luftfracht, die Versicherung ersetzt
   einen Teil, die Stadt zahlt die Einsatzkosten; Geld- und Warenbilanz bleiben erhalten.
7. **Abnahme:** Tests je Etappe, grafische Probeläufe (`--demo-airport --shot-airport`),
   Sichtbarkeit von Flugzeug, Fracht, Passagieren und Wehrauto in der Karte.

## Entscheidung und Etappen

| Etappe | Inhalt | Stand |
|---|---|---|
| E1 | Flughafen im Küstenort: Platz, Gebäude, Bodenarten, Anschluss | fertig (06.11.2026): `CoastGenerator._airport` sucht westlich des Orts nach einem flachen 16×13-Feld ohne Wasser und Bergen, baut Startbahn (eine Zeile), Betonvorfeld, Parkplatzstreifen und fünf Gebäude (Terminal 4×3, Tower 2×2, Feuerwehr 3×2, Hangar 4×3, Frachtterminal 6×4) und zeichnet die L-Zufahrt zur nächsten Straße; die Freilaufprüfung (`_road_path_exists`) verwirft Standorte ohne sauberen Anschluss, dann wird der nächste Seed-Versuch gebaut. Vier neue Voxel-Gebäude (`tools/vox/airport.py`: Terminal mit Glasfront und Treppen, Tower mit Blinklicht, Hangar, rot-weiße Feuerwehrwache mit blauem Licht) plus Bodenarten `RUNWAY`/`APRON`/`PARKING`. Geometrie (Bahn, Vorfeld, Gebäude-IDs) liegt in `city_data.airport`. Tests `test_airport` (Grafik), `test_coast_world` (Generator) |
| E2 | Fluganimation und Luftfracht | fertig (06.–07.11.2026): `Airport` (`sim.airport`): Flugzeug-Position/Höhe/Grund ist eine reine Funktion der Spieluhr (Zyklus 60 Spielminuten ≈ 30 s; Key-Points Anflug → Touchdown → Rollen → Vorfeld → Abflug, weiche Bewegung); `AirView` zeichnet das Voxel-Flugzeug (vier Richtungen, Positions-/Blinklichter) als Overlay mit weichem Bodenschatten, der auf dem Boden bleibt. Nachschärfungen: Feld-×32→Welt-Koordinaten, Maßstab 0,62, schlankeres Voxel-Flugzeug. **Luftfracht:** `city_depot.quote` bietet neben dem Seeweg die Luftfracht an (25 % Aufschlag, Lieferzeit 1 Tag, nur Kritikalität 3, sonst der günstigere Schifffahrtsweg); genehmigte Bestellungen hängen im Flughafen-`manifest` („in der Luft") und werden bei der nächsten Landung ins Frachtterminal ausgeliefert – nur bei Flugwetter (`flight_ok`: kein Starkregen/Sturm/Schnee/Glätte/Nebel), sonst zahlt der Flug einen Abbruch; nach der Landung Transportauftrag Frachtterminal → Stadtlager wie am Hafen; je Landung mit Fracht zahlt die Stadt die Betreiberpauschale (P0→X0). Tests `test_airport` (23 Prüfungen: Grafik, Flugphasen, Determinismus, Speichern/Laden), `test_air_cargo` (25: Wetter-Gate, Angebot, Bestellung, Landung, Rückstau) |
| E3 | Passagiere (Auslandsreisen) | fertig (07.11.2026): täglich bucht der Flughafen deterministisch (Hash aus Welt-Seed und Spieltag, Chance 0,004 je Bürger) neue Auslandsreisen bis zum freien Platz der Stufe; Voraussetzungen: Guthaben ≥ 150, nicht inhaftiert, nicht schon unterwegs; Ticket 28 € (Hin/Rückflug) aus dem Bürgerguthaben (R0→X0). Abflug und Rückkehr (Aufenthalt 2 Tage) sitzen auf dem Linienverkehr mit Wetter-Gate gemeinsam mit der Fracht; bei jeder Passagierlandung kassiert die Stadt die Landegebühr (X0→P0). Reisende tragen im Personendatensatz `away` (Reisegrund, zugehörig laufender Reise); ihre `travel_plan` ist leer, daher laufen sie nicht auf der Karte, und der Fußgänger-Generator überspringt sie (Cursor statt Index, sonst klemmt das Speichern/Laden). Inhaftierung vor dem Abflug → Erstattung. Test `test_air_passengers` (13) |
| E4 | Flughafenstufen (Ausbau) | fertig (07.11.2026): `STAGES` – Kleinstflughafen (4 Plätze, 8 Frachteinheiten je Flug, Landegebühr 40, Pauschale 180) → Regionalflughafen (8/20, 60, 300; Ausbau 60 000 €, 20 Tage: Betonfertigteile/Schotter/Verbindungen) → Regionalzentrum (12/40, 80, 450; 160 000 €, 40 Tage: Glas/Dämmung/Betonfertigteile/Schotter/Verbindungen). `expand` schreibt ein Stadtprojekt (`kind` flughafenausbau) aus, `finish_expansion` schaltet nach Fertigstellung um; die Stufenfunktionen (`seats`, `cargo_cap`, `landing_fee`, `airfreight_fee`) ersetzen die flachen Konstanten. Der `manifest` wird kapazitätsgrenzt geladen: größere Posten liefern anteilig, der Rest kommt mit dem nächsten Flug (Restfeld `left` pro Posten, alte Spielstände migriert); erst die Komplettlandung übergibt an das Stadtlager. Indikator `flughafen` (mit `rueckstau_fluege`); Regel-Bürgermeister baut aus, wenn Luftfracht für > 1 Flug wartet und die Kasse 1,5× die Kosten trägt. Test `test_airport_expansion` (17) |
| E5 | Feuerwehr/Notfälle | fertig (07.11.2026): die Feuerwehrwache der E1 ist jetzt besetzt: ein Wehrauto (neues Voxel-Modell `firetruck`, rote Lackierung, römische Fünf, Lichtbalken; vier Richtungen, 8 Texturen) mit Basis an der Wache. Alarm: deterministischer Wurf je Tag (Welt-Seed + Spieltag, Chance 0,004 ≈ einmal je 250 Tage); die E5-Funktionen in `Airport` (`fire_vehicle`, `fire_task`, `_fire_dispatch`, `update_fire`) schicken das Wehrauto auf die Straße, das Ziel ist die Straße des Frachtterminals (hin → Schaden → zurück zur Wache, 0,5 Sim-Sekunden je Spielminute im Minuten-Tick). **Schaden:** 50 % der X0-Ware im Frachtterminal (reserviertes Projektmaterial bleibt unangetastet) wird per `stock.consume` vernichtet; die Versicherung ersetzt 40 % des Basispreises je Einheit (S0→P0), die Stadt zahlt 2 000 € Einsatz (P0→S0) – Geld- und Warenbilanz bleiben exakt (Conservation + `balance_error` bleiben 0). Kennzahlen (`einsaetze`, `verloren`, `entschaedigung`, `einsatzkosten`) in `statistik` und im Indikator `flughafen.feuerwehr`. Wehrauto (Position, Weg, Ziel) und laufender Einsatz werden gesichert; nach dem Laden wird der Weg neu geroutet. Sichtbar in `EntityView` (Rotes/blauer Blinklicht nur bei Einsatz). Test `test_air_fire` (18) |
| E6 | Abnahme | fertig (07.11.2026): diese Datei, Autotest `--demo-airport` (Flugzeug steht auf dem Vorfeld, Luftfracht liegt im Frachtterminal) und `--shot-airport` (Kamera auf das Areal). Abnahmekriterien: (1) Startbahn/Vorfeld/Grünflächen in der Küstenwelt sichtbar; (2) Flugzeug fliegt den Zyklus (Anflug → Rollen → Abflug) und ist bei klarem Wetter am Vorfeld; (3) Luftfracht kommt als X0-Ware im Frachtterminal an und transportiert weiter; bei Schlechtwetter fällt der Flug aus (Statistik `abgebrochen`); (4) Passagiere buchen, fliegen los und kommen zurück (Statistik `passagiere`, Landegebühr); (5) der Bürgermeister baut bei Rückstausituation aus (Projekt `flughafenausbau`, danach `stage` 2); (6) bei Alarm kommt das Wehrauto, das Feuer kostet Ware, Versicherung und Einsatzkosten laufen (Geld- und Warenbilanz 0); (7) Speichern/Laden: Flugphase, Manifest, Reisen, Stufe und laufender Einsatz bleiben. Prüfbefehl: `Godot_v4.4.1-stable_win64_console.exe --path . -- --autotest --players=4 --seconds=90 --speed=8 --seed=4242 --demo-airport --shot-airport --shot-at=10 --screenshot=user://shot_airport.png --wx=clear --hour=11` (Fenster nötig; die Weltart ist dann standardmäßig Küstenort). Headless: `--only=test_airport`, `--only=test_air_cargo`, `--only=test_air_passengers`, `--only=test_airport_expansion`, `--only=test_air_fire` |

## Grenzen (Stand 07.11.2026)

- Der Flughafen entsteht nur im Küstenort; der Generator verwirft Weltversuche ohne sauberen
  Straßenanschluss (neuer Seed-Versuch), dadurch kann das Areal je Seed weiter westlich liegen.
- Flugzeug und Wehrauto sind nicht anklickbar (keine Detailkarte); die Gebäude sind es.
- Das Wehrauto läuft als eigenes Fahrzeug neben dem Sicherheitswesen (Polizei/Krankenwagen
  bleiben städtisch); der Alarm ist rein atmosphärisch (ein Brand je ~250 Tage), die Stadt
  kann darauf nicht selbst einwirken.
- Die Ausbaustufen haben noch kein eigenes Aussehen am Gebäude (Name/Stufe in Kennzahlen);
  ein größeres Terminal in Stufe 3 wäre ein eigener Grafiknachtrag.
- Die Versicherungszahlung (40 % des Warenwerts) ist ein fester Wert ohne Vertragsmodell;
  die Einsatzkosten sind pauschal (Personal, Fahrzeug, Material).

## Tests

| Test | Prüfungen | Inhalt |
|---|---|---|
| `test_airport` | 23 | Grafikdaten, Startbahn/Anbindung, Flugphasen, Determinismus, Speichern/Laden |
| `test_air_cargo` | 25 | Wetter-Gate, Luftfracht-Angebot, Bestellung, Landung, Rückstau, Geld erhalten |
| `test_air_passengers` | 13 | Buchung, Ticket, Abflug/Rückkehr, Landegebühr, Geld erhalten |
| `test_airport_expansion` | 17 | Rückstau, Ausschreibung, Teillandung, Fertigstellung, neue Kapazität, Speichern/Laden |
| `test_air_fire` | 18 | Alarm, Wehrauto hin und zurück, Schaden, Versicherung/Einsatzkosten, Saldo, Speichern/Laden |
| `test_money_conservation` | 9 | Geld- und Warenbilanz über längere Läufe (inkl. Flughafenverkehr) |
