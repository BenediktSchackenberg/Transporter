# Auftrag 8 – Individuelle, schöne und nachvollziehbare KI-Stadtplanung

Datum: 18.11.2026 · Projekt: Pixel Transport Rivals / Transporter

## 1. Auftrag

Erweitere die bestehende Stadtentwicklungs-KI so, dass sie attraktive, funktionierende und eigenständige Städte plant und während des Spiels gezielt weiterbaut.

Jede Stadt soll einen erkennbaren Charakter besitzen. Ihre Lage, Straßen, Viertel, Gebäude, Grünräume und wirtschaftlichen Schwerpunkte sollen zusammenpassen. Wenn mehrere Städte in derselben Partie wachsen, müssen sie deutlich unterschiedlich wirken. Das gilt für Startstädte, neu entwickelte Viertel und gegebenenfalls während einer laufenden Partie gegründete weitere Siedlungen.

Die KI soll für jede größere Bauentscheidung erklären können: Warum wird dieses Gebäude benötigt, warum an diesem Standort, wie passt es in die Umgebung und wie wird es erschlossen und finanziert?

Implementiere diese Regeln im laufenden Spiel. Eine Beschreibung schöner Städte oder ein zusätzlicher Planungsdatensatz ohne Einfluss auf tatsächliche Bauentscheidungen erfüllt den Auftrag nicht.

Prüfe zuerst aktuellen Branch, lokale Änderungen, Projektanweisungen und vorhandene Stadtplanungsfunktionen. Am Projekt wird parallel gearbeitet. Erhalte vorhandene Weiterentwicklungen und integriere diese Erweiterung in die aktuellen Systeme.

## 2. Bestehende Spielregeln bewahren

Behalte Engine, Windows-Unterstützung, die vorhandene isometrische Voxel-/Pixeloptik und den Wirtschaftskreislauf bei.

Die bisherigen Rahmenbedingungen gelten weiter: Bei vier Startspielern liegt jeweils eine Startstadt in einer der vier Eckregionen der Karte. Jede beginnt als kleiner Küstenort mit den notwendigen Einrichtungen und höchstens 40 fertig errichteten Gebäuden. Große Teile der Region bleiben unerschlossen. Die bereits vereinbarten Regeln zu Unternehmern, Bürgermeistern, Flughäfen, Häfen, Bergen, Verkehr, Tourismus und Bauunternehmen bleiben bestehen.

Erhalte mindestens 60 Prozent zunächst unerschlossene grundsätzlich bebaubare Landfläche nach den bestehenden Weltregeln. Diese Reserve soll überwiegend außerhalb der kompakten bewohnten Kerne liegen. Städte müssen dafür nicht aus riesigen leeren Rasenblöcken bestehen.

Ein schöner Plan erzeugt kein kostenloses Gebäude. Neubauten und Ausbauten benötigen Eigentum oder Nutzungsrecht, Nachfrage, Genehmigung, Finanzierung, Material, Personal, Erschließung und die vorgesehene Bauzeit.

## 3. Jede Stadt erhält ein dauerhaftes Gestaltungsprofil

Lege bei Gründung beziehungsweise kontrollierter Übernahme einer bestehenden Stadt ein gespeichertes Gestaltungsprofil an. Verwende vorhandene Datenstrukturen, wenn sie dafür geeignet sind.

| Bestandteil | Inhalt und tatsächliche Wirkung |
|---|---|
| Landschaft | Küstenform, Fluss, Hänge, Seen, Wald und Rohstofflagen beeinflussen Straßen und Entwicklungsschwerpunkte. |
| Grundstruktur | beispielsweise Ortskern mit Hauptstraße, Hafenort mit Uferachse, Siedlung um einen Platz oder mehrere durch Grünräume verbundene Nachbarschaften |
| Architektur | zusammenpassende Bauformen, Materialien, Dachtypen, Farbpalette und Übergänge zwischen Entwicklungsstufen |
| Dichte und Höhen | geringe Dichte am Ortsrand, kompaktere Bereiche am Zentrum und begründete Standorte für größere Gebäude |
| Freiräume | Art und Lage von Plätzen, Gärten, Grünverbindungen, Uferwegen und späteren Parks |
| Wirtschaft | vorhandene Vorteile und Nachfrage schaffen räumliche Schwerpunkte, ohne andere Branchen grundsätzlich zu verbieten. |
| Öffentlicher Raum | passende Straßenbäume, Beleuchtung, Bodenbeläge und Gestaltung der wichtigen Zugänge |
| Entwicklungsgeschichte | bestehende Bauten und frühere Entscheidungen prägen spätere Erweiterungen. |

Das Profil bleibt beim Laden erhalten. Ein Bürgermeisterwechsel verändert politische Prioritäten, aber würfelt nicht die Identität der ganzen Stadt neu aus. Stil und Planung dürfen sich begründet weiterentwickeln; ältere Teile bleiben dabei erkennbar.

## 4. Stadtplan vor Einzelplatzierung

Verwende eine gemeinsame Planungshierarchie:

Stadtprofil → räumlicher Entwicklungsplan → Viertelplan → Straßen und Grundstücke → bewerteter Bauplatz → genehmigtes und finanziertes Bauprojekt.

Der Entwicklungsplan beschreibt Ortskern, wichtige Straßenachsen, Hafen-/Gewerbebereiche, Wohnschwerpunkte, touristische Uferabschnitte, Grünverbindungen und mögliche spätere Erweiterungsrichtungen. Er reserviert Platz für notwendige Verbindungen und legt geeignete Nutzungen nahe.

Ein Plan ist noch kein bebautes Gebiet. Unterscheide unverbindliche Entwicklungsabsichten von rechtlich oder projektbezogen reservierten Flächen. Sperre nicht die gesamte Karte dauerhaft für hypothetische spätere Großprojekte. Harte Reservierungen brauchen Anlass, Zuständigkeit, Status und gegebenenfalls Ablaufdatum.

Jedes Viertel besitzt eine Rolle, passende Grundstücksgrößen, angestrebte Dichte, Bauhöhen, Straßenanschlüsse und einen gestalterischen Zusammenhang. Ein kleines Viertel kann zunächst aus wenigen Gebäuden bestehen. Ein vollständiger Großstadtplan muss nicht schon am ersten Tag erschlossen werden.

## 5. Individualität entsteht auch im Grundriss

Die Städte sollen sich in ihrer räumlichen Struktur unterscheiden, etwa in der Lage ihres Zentrums zur Küste, in Straßenverbindungen, Blockgrößen, Platzfolgen, Bebauungsdichte und Verteilung der öffentlichen Räume. Andere Hausfarben oder eine gedrehte Kopie desselben Grundrisses reichen dafür nicht aus.

Mögliche, kombinierbare Charaktere sind:

- **Hafenort:** kompakter Kern nahe dem alten Hafen, kurze Geschäftsstraße, Lager- und Gewerbehöfe an einer eigenen Güterzufahrt.
- **Buchtenstadt:** Bebauung folgt einer geschützten Bucht; Promenade und kleine Plätze verbinden Hotels, Gastronomie und Wohnbereiche.
- **Gartenstadt:** kleinere Nachbarschaften mit verbundenen Grünräumen, Gärten und örtlichen Versorgungspunkten.
- **Hangstadt:** Baugruppen und Straßen orientieren sich an geeigneten Höhenlagen und Aussichtspunkten; größere Erschließungen bleiben echte Projekte.
- **Flussstadt:** unterschiedliche Uferquartiere, verständliche Brückenstandorte und sichtbare Zugänge zum Wasser.

Diese Beispiele sind Gestaltungsrichtungen, keine starren Schablonen. Die konkrete Landschaft und der Spielverlauf müssen den Grundriss verändern. Nicht jede Stadt erhält automatisch dieselbe Reihenfolge aus Marktplatz, Ringstraße und vier identischen Vierteln.

Vergleiche die Profile und Strukturmerkmale innerhalb einer Region. Vermeide offensichtlich gleiche Kombinationen, wenn sinnvolle Alternativen vorhanden sind. Unterschiede sollen auch ohne Stadtname und Firmenfarben erkennbar sein. Bewahre dabei eine gemeinsame visuelle Qualität des gesamten Spiels.

## 6. Während der Partie geordnet wachsen

Löse Planung durch tatsächliche Entwicklung aus: Wohnraumbedarf, offene Arbeitsplätze, unterversorgte Viertel, Lieferengpässe, Tourismusnachfrage, Unternehmensanträge oder überlastete Verkehrswege.

Prüfe zuerst geeignete Baulücken, vorhandene erschlossene Grundstücke und sinnvolle Nachverdichtung. Wenn ein neues Viertel erforderlich ist, erweitere an einer nachvollziehbaren Entwicklungsfront mit den nötigen Anschlüssen. Vermeide verstreute einzelne Häuser weit außerhalb der bestehenden Siedlung, deren Straßen und Versorgung nur scheinbar funktionieren.

Standortgebundene Ausnahmen sind ausdrücklich möglich: Bergwerk am Vorkommen, Hafen am geeigneten Ufer, Flughafen auf einer passenden großen Fläche oder Industrie an einer Güterachse. Solche Vorhaben brauchen eine begründete Lage und tatsächlich geplante Erschließung.

Entwickle neue Viertel in überschaubaren Abschnitten. Die KI soll nicht gleichzeitig überall Straßen und Gebäude beginnen, obwohl Geld, Baumaterial und Nachfrage nur für einen Teil reichen. Abgeschlossene Abschnitte werden nutzbar, bevor weitere Vorhaben unnötig Ressourcen binden.

Die Planung bleibt im Spiel aktiv. Bei einer neuen Stadt wird das Profil vor den ersten regulären Bauplatzentscheidungen festgelegt. Bei jeder späteren Erweiterung werden Nachbarschaft, Kapazitäten und Entwicklungsplan erneut berücksichtigt. Die zulässige Zahl neuer Städte und Unternehmer richtet sich weiterhin nach den bestehenden Spielregeln.

## 7. Bauplätze vergleichen statt beliebige freie Koordinaten wählen

Führe jede Platzierung durch dieselbe verbindliche Standortbewertung. Erzeuge eine begrenzte Auswahl geeigneter Kandidaten und vergleiche sie vor der Entscheidung. Kandidaten dürfen seedbasiert entstehen; die abschließende Standortwahl folgt den Regeln und den wirtschaftlichen Zielen.

Prüfe zuerst harte Bedingungen:

- gültiges Grundstück, Eigentum beziehungsweise Nutzungsrecht und zuständige Verwaltung;
- zulässige Nutzung und Genehmigung;
- passende endgültige Grundfläche einschließlich Ausrichtung und Anbauten;
- keine unzulässige Überlappung mit Straße, Gehweg, Gebäude, geschütztem Ufer oder verbindlich reserviertem Korridor;
- gültige Eingänge und Lieferzugänge sowie vorhandene oder verbindlich finanzierte Erschließung;
- tragfähige Finanzierung, Versorgung und notwendige Bauvoraussetzungen.

Bewerte danach die Qualität der gültigen Standorte:

| Kriterium | Beispiele |
|---|---|
| Bedarf und Nutzen | Erreicht der Betrieb Kunden? Entsteht Wohnraum bei Arbeit und Versorgung? |
| Nachbarschaft | Passen Nutzung, Höhe, Lärm, Lieferverkehr und Freiräume zusammen? |
| Stadtstruktur | Schließt das Vorhaben eine Lücke oder stärkt es eine geplante Entwicklungsachse? |
| Erreichbarkeit | Fußwege, Güterzufahrt, ÖPNV soweit vorhanden und Belastung der Straßen |
| Kosten und Betrieb | Grundstück, Anschlüsse, Bau, Transportwege, Unterhalt und erwartete wirtschaftliche Tragfähigkeit |
| Gestaltungsprofil | Bauform, Ausrichtung, Straßenfront, Materialpalette und Viertelcharakter |
| Landschaft | Wasserzugang, Hanglage, Aussicht, Grünverbindung und Schonung geeigneter Naturflächen |

Gewichtungen sind konfigurierbar und können je Stadtprofil und Gebäudenutzung variieren. Normiere die Kriterien nachvollziehbar. Viele Dekorationsobjekte oder eine große freie Fläche dürfen nicht allein einen guten Planungswert erzeugen.

Wenn kein Kandidat gültig ist, löse eine konkrete Folgemaßnahme aus: andere Bauform prüfen, Anschlüsse planen, Grundstück verhandeln oder Vorhaben begründet verschieben. Entferne einen bisherigen beliebigen Zufalls-Fallback, falls er ungültige oder städtebaulich widersprüchliche Platzierungen erzeugt.

Bei dauerhaftem Bedarf ohne guten Standort darf die KI den Entwicklungsplan kontrolliert überarbeiten. Sie darf harte Flächen- und Budgetregeln nicht mit einer bloßen Begründung umgehen.

## 8. Gestaltungsregeln am einzelnen Gebäude

Richte Hauseingänge, Ladenfronten und öffentliche Zugänge auf geeignete Straßen, Plätze oder Wege aus. Platziere Gärten und Höfe passend zur Nutzung. Lieferhöfe bekommen eine funktionierende rückwärtige oder seitliche Zufahrt.

Definiere passende Baufluchten, Abstände, Gebäudehöhen und Übergänge je Viertel. Größere Gebäude brauchen einen geeigneten Standort und eine Entwicklungsstufe, die Nutzung und Versorgung trägt. Vermeide unvermittelte Hochhäuser zwischen einzelnen Anfangshütten.

Verwende tatsächliche architektonische Varianten. Variiere Silhouette, Dach, Fensterteilung, Eingang, Balkon und Anbau innerhalb einer gemeinsamen Gestaltungsfamilie. Verhindere auffällige direkte Wiederholungen, soweit passende Varianten verfügbar sind. Eine bewusst zusammenhängende Reihenhauszeile darf einen ruhigen Rhythmus besitzen, ohne dass die gesamte Stadt daraus besteht.

Prüfe logische Grundfläche, Bildanker, Projektion und Verdeckung gemeinsam. Eine optisch größere Variante darf nicht heimlich Fahrbahn oder Nachbargrundstück belegen. Die ausgewählten Varianten müssen durch die komplette Asset-Kette bis zur geladenen Grafik im Spiel ankommen und dauerhaft gespeichert beziehungsweise stabil abgeleitet sein.

## 9. Bürgermeister und Unternehmer planen gemeinsam mit getrennten Rollen

Der Bürgermeister verantwortet öffentliche Planung, Flächenfreigabe, Genehmigungen, öffentliche Räume und Infrastruktur seiner Stadt. Private Unternehmer entscheiden über ihre Investitionen und beantragen passende Vorhaben. Ein Stadtplan ist keine Erlaubnis, fremdes Eigentum oder die Firmenkasse zu verändern.

Unternehmer erhalten geeignete Standortangebote mit Preisen, Vorteilen, Auflagen und Erschließungsbedarf. Eine profitable Bäckerei darf beispielsweise einen Platz am Wohnviertel oder Markt wählen; ein lärmintensiver Betrieb bekommt passende Gewerbestandorte vorgeschlagen.

Prüfe auch Anträge auswärtiger Firmen nach den Regeln der Standortstadt. Erhalte die eindeutige Stadtzuordnung von Grundstücken, Gebäuden, Konten und Projekten.

Jedes neue Gebäude, jede Straße und jede kostenpflichtige Gestaltung braucht den richtigen Auftraggeber und eine Finanzierung. Private Gärten und gewerbliche Terrassen gehören zum jeweiligen Projekt; öffentliche Promenaden und Plätze werden aus dem zuständigen Haushalt bezahlt. Anfangsausstattung wird ausdrücklich im Startbudget berücksichtigt.

## 10. Straßen, Plätze und Landschaft als zusammenhängender Raum

Baue eine erkennbare Straßenhierarchie: regionale Verbindung, örtliche Hauptstraße, Wohnstraße, Hafenzufahrt und Fußweg. Vermeide gleich breite Straßen und identisch große Blöcke überall. Bestehende Rastertechnik darf verwendet werden, wenn unterschiedliche Blockgrößen, T-Kreuzungen, Platzbildungen und Wege eine abwechslungsreiche Struktur schaffen.

Schütze wichtige Fußwege, Strandzugänge und Grünverbindungen. Trenne schweren Güterverkehr soweit sinnvoll von ruhigen Wohn- und Erholungsbereichen. Hotels sollen Aussicht und Zugang zum Wasser besitzen; ihre Lieferzufahrt darf trotzdem funktionieren. Hafenarbeiter und Lieferfahrzeuge brauchen tatsächliche Arbeitswege.

Setze Plätze, Straßenbäume, kleine Grünflächen, Beleuchtung, Sitzbereiche und Bodenbeläge gezielt ein. Gib Freiflächen eine lesbare Rolle: Garten, Hof, Platz, geplantes Grundstück, Park oder natürlicher Ortsrand. Vermeide das flächendeckende Auffüllen mit beliebiger Dekoration.

Folge Landschaft und Wasserlage. Erhalte sinnvolle Aussichtspunkte und Uferwege, schaffe Übergänge zwischen Bebauung und Natur und plane Bergbau oder größere Verkehrsprojekte mit tatsächlichen Zufahrten. Eine attraktive Stadt muss nicht überall dieselbe symmetrische Parkanlage besitzen.

## 11. Entscheidungen für den Zuschauer verständlich machen

Zeige ein zuschaltbares Planungsbild mit Vierteln, Nutzungen, wichtigen Verbindungen und tatsächlich reservierten Flächen. Unterscheide Entwurf, beschlossenes Vorhaben, Finanzierung, Bau und fertige Nutzung.

Ein Bauvorhaben zeigt gewählten Standort, Begründung, wichtigste Alternativen, voraussichtliche Kosten, nächsten Schritt und mögliche Blockade. Verlange keine internen Gedankengänge des Sprachmodells; eine kurze sachliche Entscheidungsbegründung reicht aus.

Beispiel: „Die Bäckerei entsteht an der Marktstraße: viele erreichbare Haushalte, kurze Warenzufahrt und passende Ladenfront. Der Standort am Ortsrand wurde wegen längerer Wege zurückgestellt.“

Beispiel: „Das Hotel wird auf dem zweiten Ufergrundstück geplant. Es bietet Strandzugang, liegt außerhalb des Güterhafens und lässt den öffentlichen Promenadenweg frei. Der Ausbau wartet auf die finanzierte Zufahrt.“

Wenn eine Stadt bewusst anders wächst als eine andere, soll ihre Entwicklungsgeschichte im Plan und im Stadtbild erkennbar bleiben.

## 12. Technische Integration und begrenzter KI-Einsatz

Nutze vorhandene Planungs-, Bürgermeister-, Grundstücks-, Bau- und KI-Systeme. Suche deren aktuelle Klassen und Erweiterungspunkte im Code, bevor du neue Strukturen anlegst. In älteren Ständen waren insbesondere mayor.gd, mayor_brain.gd, mayor_agent.gd, parcels.gd, permits.gd, construction.gd, city_generator.gd, coast_generator.gd, city_data.gd, observation_builder.gd und action_executor.gd relevant. Ihre aktuelle Form ist maßgeblich.

Die Regelprüfung und Kandidatenbewertung gehören in die Spielsimulation. Ein Sprachmodell kann Ziele setzen, Alternativen auswählen und Planrevisionen vorschlagen. Seine Aktionen werden anhand gültiger Stadt-, Viertel-, Grundstücks- und Projektidentitäten geprüft; es darf keine beliebigen Koordinaten ohne Validierung bebauen.

Wende dieselben Regeln auf Weltgenerierung, dynamischen Neubau, NPC-Gründungen, Gebäudeausbau, öffentliche Projekte, Tourismusbetriebe und alle vorhandenen automatischen Entwicklungswege an. Verhindere, dass ein alter Nebenpfad nach kurzer Spielzeit wieder beliebige Häuser setzt.

Reserviere gewählte Standorte atomar und prüfe ihre Gültigkeit beim tatsächlichen Auftrag erneut. Zwischen Planung und Ausführung können Geld, Eigentum oder Belegung geändert worden sein. Veraltete KI-Antworten dürfen einen inzwischen vergebenen Bauplatz nicht überschreiben.

Plane ereignisbezogen oder in begrenzten Intervallen. Vermeide einen Modellaufruf pro Kachel, Gebäude oder Bild. Nutze begrenzte Kandidatenmengen, geeignete räumliche Abfragen und aktualisiere nur betroffene Planbereiche. Eine funktionierende regelbasierte Stadtplanung muss auch ohne Live-API möglich sein.

## 13. Dauerhafte Pläne und sichere Weiterentwicklung

Speichere mindestens Stadtprofil, Viertelzuordnung, beschlossene Entwicklungsziele, aktive Reservierungen, Planrevisionen, gewählte Varianten und laufende Bauvorhaben. Speichern/Laden darf die Stadt nicht neu entwerfen.

Die seedbasierte Grundplanung soll reproduzierbar sein. Für identischen Seed und dieselbe aufgezeichnete Folge akzeptierter Aktionen muss die Entwicklung wiederholbar sein. Live-Modellentscheidungen können unterschiedlich ausfallen; speichere deshalb die tatsächlich beschlossenen Entscheidungen und Pläne.

Änderungen erfolgen als begründete Revision: etwa neue Nachfrage, fehlende Flächen, Kostenanstieg, Verkehrsengpass oder veränderte kommunale Priorität. Hebe veraltete Reservierungen kontrolliert auf und behandle bereits beauftragte oder begonnene Bauten nach ihren Verträgen. Ein neuer Beschluss darf nicht kommentarlos Häuser oder Straßen verschwinden lassen.

## 14. Bestehende Städte übernehmen

Leite für bestehende Spielstände ein passendes Profil aus ihrer tatsächlichen Bebauung, Landschaft und Nutzung ab. Erfasse vorhandene Viertel und sinnvolle Weiterentwicklungsmöglichkeiten. Erhalte Gebäude, Eigentum, Bewohner, Firmen, Bestände und Finanzierungen.

Verbessere das weitere Wachstum und geeignete Gestaltung schrittweise. Reiße eine vorhandene Stadt nicht kostenlos ab und platziere sie beim Laden neu. Echte frühere Überlappungsfehler brauchen weiterhin die bereits beauftragte kontrollierte Korrektur mit erhaltener wirtschaftlicher Identität.

Migration und Planungsdaten erhalten eine zum aktuellen Projekt passende Version. Bewahre die ursprüngliche Save-Datei vor dem Schreiben einer migrierten Fassung auf. Ein veraltetes Feld darf nicht dazu führen, dass im Mehrstädtemodus alle Projekte an dieselbe Stadt gehen.

## 15. Umsetzung in spielbaren Etappen

1. Prüfe alle bisherigen automatischen Bauwege und dokumentiere kurz, wo Standortentscheidungen fallen und Regeln umgangen werden können.
2. Integriere gespeicherte Stadtprofile und Viertelpläne in die bestehenden Strukturen. Bewahre die bisherige Spielbarkeit und Migration.
3. Führe gemeinsame Standortprüfung, Kandidatenvergleich und gültige Übergabe an das Bau-/Genehmigungssystem ein.
4. Übertrage alle dynamischen Baupfade und die Regel-KI auf diese Planung. Zeige Entscheidungen und Blockaden.
5. Verbinde die tatsächlich geladenen Gebäudevarianten, Straßenräume und öffentlichen Details mit den Profilen. Prüfe sichtbare Unterschiede und langfristiges Wachstum.

Setze den Auftrag bis zur integrierten Funktion fort. Ein gut aussehender Startgenerator reicht nicht aus, wenn während der laufenden Partie anschließend wieder ungeplant gebaut wird.

## 16. Verbindliche Abnahme

- Vier Städte derselben Partie sind an Grundriss, Bebauungsstruktur, Architektur und Freiräumen unterscheidbar. Es sind keine bloß umgefärbten oder gedrehten Kopien.
- Jede Startstadt besitzt einen plausiblen kompakten Kern, passende Pflichtgebäude, funktionsfähige Zugänge und höchstens 40 Startgebäude. Die Eckregionen und übrigen Weltbedingungen bleiben erfüllt.
- Im laufenden Spiel führen Wohnraumbedarf, ein privater Betrieb und ein öffentliches Projekt jeweils zu nachvollziehbar gewählten Standorten innerhalb einer passenden Planung.
- Eine neu gegründete Siedlung, sofern im aktuellen Spiel unterstützt, verwendet vor ihrem weiteren Wachstum dieselben Identitäts- und Planungsregeln.
- Ungültige oder inzwischen vergebene Bauplätze werden abgelehnt. Die KI benennt einen nächsten sinnvollen Schritt, statt irgendwo anders ungeprüft zu bauen.
- Kein automatischer Baupfad erzeugt unzulässige Überlappungen mit Straßen, Gebäuden oder verbindlichen Korridoren. Liefer- und Fußwege bleiben tatsächlich nutzbar.
- Verschiedene gültige Seeds erzeugen unterschiedliche, funktionierende Orte. Prüfe auch ungünstige Küsten-, Hang- und Engpasslagen sowie anhaltendes Wachstum über längere Spielabschnitte.
- Gebäudevarianten, Nachtbeleuchtung und öffentliche Räume sind im laufenden Spiel tatsächlich passend eingebunden. Unterschiedliche Asset-Dateien allein gelten nicht als Nachweis.
- Speichern/Laden erhält Identität und Planung. Bestehende Städte und ihr Vermögen werden nicht neu erzeugt oder verschoben.
- Geld, Waren, Personal, Bauzeiten und Zuständigkeiten bleiben nach den vorhandenen Wirtschaftsregeln konsistent. Geplante Schönheit erzeugt keine kostenlosen Leistungen.

Automatische Kennzahlen können Wiederholungen, Belegung, Wege und Planregelverletzungen prüfen. Die gestalterische Qualität benötigt zusätzlich eine Sichtprüfung aus dem laufenden Spiel. Zeige pro Stadt mindestens eine Übersicht und eine Nahansicht sowie bei einer Stadt die Entwicklung über mehrere Zeitpunkte bei vergleichbarem Zoom.

---

## Stand

### Etappe 1 (18.11.2026): Bestand – wo heute Standorte entschieden werden

Alle Gebäude entstehen über `EventDirector._add_building` (prüft nur: Felder frei, keine Straße/Wasser/Gleis, keine reservierte
Zufahrt; Straßenanschluss in der Wildnis nicht nötig). Die Standortwahl davor ist je Baupfad verschieden und kennt keinen Stadtplan:

| Baupfad | Datei | Standortwahl heute | Problem gegenüber Auftrag 8 |
|---|---|---|---|
| Startstädte (Region) | `region_generator.gd` `_town_core`, `_streets(t, ch)` | feste Versätze um Hafen/Rathaus/Marktplatz; Ortscharakter (Fischerdorf, Marktflecken, Bauerndorf, Handwerkerort, Kurort, Hafenstadt) ändert nur Straßen und Hausmix | Grundriss weitgehend gleich; Charakter wirkt nach dem Start nicht mehr |
| Wildnis-Gründung | `eko_settle.gd` `best_near`/`found`, `open_town` | Wesen wählt das Feld; Rathaus+Bauhof am Grundstück, Hafen am nächsten Meer | kein Profil, kein Kern/Achsenplan |
| Wildnis-Bauland | `eko_settle.gd` `carve_plots`, `carve_area` | feste 6er-Grundstücke entlang jeder neuen Straße, alle Zone `wohnen`; `carve_area`: Ring 18–32 Felder um den Betriebshof | keine Viertel/Nutzungen; Ring erzeugt verstreute Grundstücke ohne Straße |
| Wildnis-Häuser/Betriebe | `eko_homes.gd` `_finish` | Grundstück, das das Wesen nennt | keine Bewertung/Begründung |
| Bauträger Wohnen/Läden | `construction.gd` `_developer_try` | **billigstes** freies Grundstück (`parcels.search` sortiert nach Preis; Rand ist billiger) | baut bevorzugt am Ortsrand, verstreut; keine Begründung |
| Versorgung/Gewerbe | `construction.gd` `_supply_project`, `_commerce_project` | `parcels.search` je Zone, erstes passendes | wie oben |
| Kommunale Bauten (Bürgermeister, Dienste) | `civic_works.gd` `_find_site` (auch `municipal._place`, `service_planner`) | nächstes freies städtisches Grundstück zum Rathaus (≤ 70 Felder), „Rand“ = am weitesten weg | nur Entfernung; keine Nachbarschaft/Lärm/Profil |
| Quartiere (Bürgermeister) | `mayor.gd` `quarter_candidates`, `zoning` | 32er-Raster, Entfernung zur **Kartenmitte** (`size*0.45`) | in Region/Wildnis falscher Bezug (nicht die eigene Stadt) |
| Produktion/Felder | `production.gd` `_parcel_candidates`, `_market_candidates` | nächstes Grundstück mit Straße zum Abnehmer, nicht in Wohn-/Mischgebiet | standortgebunden sinnvoll; nur Begründung fehlt |
| Ladeneröffnung (Ereignis) | `world_events.gd` `_openings` | **zufällige Koordinate** (400 Versuche), ohne Grundstück, Genehmigung und Kosten | umgeht alle Regeln – entfernen bzw. über die Planung |
| Müllverbrennung | `waste.gd` `_iv_find_site` | städtisches Grundstück ≤ 16 Felder von der Deponie | standortgebunden; ok |
| Regionalrat | `regional_council.gd` | erstes freies 3×3 mit Straße nahe Mitte | einmalig; ok |
| Bahnhöfe | `rail_net.gd` | Gleislage | standortgebunden; ok |
| Gebäudevariante | `event_director.gd` `_pick_variant` | Hash der Position, keine direkte Wiederholung in 6 Feldern | Ortspalette (`coast_generator._pick_palette`) gilt nur beim Kartenbau |

Vorhandene Bausteine, auf denen Auftrag 8 aufsetzt: Grundstücke mit Zone/Eigentum/Reservierung (`parcels.gd`), Bauvorprüfung
(`Planning.assess`), Bauanträge (`permits.gd`), Stadtprojekte (`mayor.gd`/`construction.gd`), Ortscharakter (`towns.list[k].charakter`),
Stil kommunaler Bauten je Charakter (`municipal.STYLE_OF_CHARACTER`), Siedlungsdaten der Wildnis (`sim.settlements`).

Plan für Etappe 2–3: neue Klasse `TownPlan` (Profil, Kern, Achsen, Viertel, Reservierungen, Revisionen; gespeichert, beim Laden aus
der Bebauung abgeleitet) und `SiteSelector` (harte Prüfungen → bewertete Kandidaten → Begründung mit Alternativen → atomare
Reservierung). Danach (Etappe 4) laufen alle Pfade der Tabelle über `SiteSelector`; `world_events._openings` entfällt.

### Etappe 2 (18.11.2026): Gestaltungsprofil und Viertelplan je Stadt

- Neue Klasse `TownPlan` (`scripts/core/town_plan.gd`, `sim.town_plan`, gespeichert als `town_plans`). Profil je Stadt: Grundform
  (Hafenort, Buchtenstadt, Gartenstadt, Hangstadt, Flussstadt, Marktort) mit Leitbild, Kern, Wasserrichtung, Hauptachse,
  Landschaftsanteile (Meer, Fluss/See, Hang, Acker, Bucht), Grundstücksgröße, Höhen je Ring, Freiraumart, Wirtschaftsschwerpunkte,
  Stil kommunaler Bauten, Material-/Farbpalette (3 von 6), Hausbauformen (5 von 8), Viertel und Entwicklungsgeschichte.
- Grundform aus der Landschaft um den Kern; eine schon vergebene Grundform kostet 3 Punkte (Region mit 4 Küstenorten, Seed 4242:
  Buchtenstadt, Marktort, Hafenort, Gartenstadt). Palette je Stadt verschieden. Gleicher Seed → gleiche Profile.
- Viertel je Grundform mit Rolle, Zone, Mitte, Radius, Geschosszahl, Zweck; Status `entwurf` (unverbindlich, sperrt nichts). Mitten
  liegen auf freiem Land (gedreht statt in Wasser/Berg) und nie näher an einer anderen Stadt als am eigenen Kern.
- Entstehung: Kartenstart (`ensure_all("start")`), Wildnis-Gründung (`open_town`, vor dem ersten Bauland), Laden alter Spielstände
  (`ensure_all("bestand")`, aus Rathauslage und Landschaft; Gebäude bleiben unverändert). Vor dem ersten Speichern mit Stadtplan wird
  die alte Datei als `quicksave_vor_stadtplan.json` aufbewahrt.
- Wirkung im Spiel: neues Bauland der Wildnis (`carve_plots`) bekommt Grundstücksgröße und Zone des Viertels, im Grünzug/Aussicht/
  Uferweg entsteht keins; neue Gebäude wählen ihre Variante aus Palette und Bauformen der Stadt (`EventDirector._pick_variant`);
  kommunale Bauten den Stil des Profils (`Municipal.style_of`); der Bürgermeister sieht `stadtplan` (Leitbild, Viertel) in seiner Beobachtung.
- Live-Partie: Birkenklippe = Hangstadt (31 % Hang), Liorufer = Gartenstadt.
- Test `test_town_plan` (17 Prüfungen), Probe `tests/probe_town_plan.gd <Spielstand>`.
