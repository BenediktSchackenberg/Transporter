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
4. **Bürger-KI (`CitizenBrain`):** Jeder Bürger plant seinen Tag selbst: Schichten nach Arbeitgeber (Industrie früh, Handel später und
   samstags, Polizei/Pflege/Kommunales im Früh-, Spät- und Nachtwechsel mit versetzten freien Tagen), Mittagspause im Büro,
   gelegentlich ein Arzttermin, Arbeitslose vormittags zur Arbeitsvermittlung, Weiterbildung in der Schule, Besorgungen nach der
   Arbeit oder am Samstag, abends Gastronomie (freitags und samstags öfter, nur mit Einkommen), Spaziergänge am Markt oder Hafen (nicht
   bei Regen), sonntags Ausflüge. Ziele sind die nächsten offenen Gebäude im eigenen Ort; fehlt dort etwas, zählt der Wunsch als
   unversorgt. Stündliche Zählung je Ort (Personenstunden je Tätigkeit, unversorgte Wünsche) steht dem Bürgermeister als
   `buergerleben` im Lagebild zur Verfügung; die Auswahl eines Bürgers zeigt seinen Tagesplan. Test: `test_citizen_brain`.
5. **Instandhaltung sichtbar (`BuildingCare.works`):** Die monatliche Pflege der Eigentümer erscheint als Handwerkereinsatz (jedes vierte
   gepflegte Gebäude, verteilt über den Monat, 1–3 Tage, werktags 7–16 Uhr): Maler auf einem Gerüstfeld mit frischem Anstrich,
   Dachdecker auf der Traufe mit Leiter und Ziegelstapel, Fensterbauer tragen Scheiben vom Firmenwagen. Test: `test_care_works`.
6. **Animierte KI-Porträts (`PortraitArt`):** Jede Figur oben links wird aus ihrem Namen gezeichnet (Hautton, Frisur, Haarfarbe, Bart,
   Kappe/Bauhelm/Mütze/Hut, Brille, Ohrring, Sommersprossen, Kragen, Krawatte/Schal/Fliege, Jacke in Firmenfarbe, Skyline). Die
   Animation zeigt die Tätigkeit: denkt (Modellanfrage läuft: Hand am Kinn, Gedankenblase), telefoniert (Zuteilen, Anwerben),
   unterschreibt (Aufträge, Kredite, Handel), rechnet (Kauf, Preise), plant (Gründung, Bau), liest (Auftragsbörse), geht, spricht,
   wartet (Finger trommeln, Gähnen); Blinzeln, Atmen, Stimmung aus dem Ergebnis. Das Sprachmodell wählt mit `geste` selbst, wie sich
   seine Figur zeigt (jubeln, fluchen, grübeln, telefonieren, zuversichtlich, nervös, winken, schulterzucken, daumen_hoch, kaffee).
   Sichtprüfung: `tests/probe_portraits.gd`.
7. **Fahrzeiten:** Die Schätzung rechnet mehrere Ladungen (Hin- und Rückfahrten), Fahrer mit geplanter Tour bekommen keine andere
   Aufgabe mehr, jeder Auftrag misst Schätzung, gebrauchte Zeit, Minuten je Zustand und Tempo (`type: "trip"` im Partie-Log,
   `tests/probe_trip_times.gd`).
8. **Gemüt der Bürger:** Jede Figur führt täglich Energie (Schichtstunden, Nachtschicht, Pendelweg, Schlaf, freie Tage), Jobfrust (Lohn
   unter dem Schnitt, Pendelweg, Schichtdienst, Müdigkeit, Unglück) und Ärger (nichts Offenes im Ort, Unglück, Arbeitslosigkeit) mit
   Gründen. Folgen: erschöpft → krankgemeldet, müde → abends kein Ausgehen, frustriert → Jobsuche nach der Arbeit und häufiger Stellen-
   wechsel bzw. Kündigung, verärgert → Beschwerde im Rathaus (kostet Zustimmung). Zeichen über dem Kopf (Zzz, ?, !!), Gemüt mit Gründen
   in der Auswahl, `buergerleben.stimmung` im Lagebild des Bürgermeisters. Test: `test_citizen_mood`.
9. **Bauleitung für Modell-Firmen:** In den Partien vom 14.11. bauten die lokalen Modelle nie (kein `create_stone_work`, `free_build`
   oder `hub_buy`), Naturstein im Großlager blieb liegen. Die Bauleitung (`AgentController._run_build_help`, höchstens alle 6 Spiel-
   stunden) holt fehlendes Material für laufende Bauten beim Großlager und beginnt, wenn die Firma seit 3 Tagen selbst nichts gebaut
   hat und Geld über der Reserve liegt, ein Werk oder freies Bauwerk; Entwurf nach Persönlichkeit (`RuleBrain._free_build/_stone_work`).
   Im Partie-Log mit `source: "Bauleitung"`. Test: `test_build_help`; Ursachensuche: `tests/probe_build_why.gd`.
10. **Zuteilung und Rückgabe:** Die Fahrtmessung der Partie 14.11. 17:54 zeigte: gelieferte Aufträge wurden sofort zugeteilt, gescheiterte
    hatte das Modell ohne Fahrzeug angenommen, sie warteten 10–17 Spielstunden. Jetzt fährt bei einer Modell-Annahme ohne Fahrzeug sofort
    ein bereitstehendes passendes Fahrzeug, wenn es rechtzeitig liefert; angenommene, nicht zugeteilte Aufträge, die kein eigenes Fahrzeug
    mehr schafft, gehen alle 30 Spielminuten gegen 10 % Gebühr (statt 30 % Strafe, Reputation −2 statt −6) an den Markt zurück.
    Test: `test_contract_release`.
