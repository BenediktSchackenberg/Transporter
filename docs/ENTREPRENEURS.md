# Auftrag 14: Vier KI-Unternehmer in einer zusammenhängenden Stadtwirtschaft

Auftrag von Benedikt (05.11.2026), eingereicht als vollständiger Arbeitsauftrag. Branch: `unternehmer`. Der Wortlaut steht unten unverändert; Bestandsbericht, Migrationsentscheidung und Stand folgen am Ende.

---

## Wortlaut

Repository: https://github.com/BenediktSchackenberg/Transporter
Erstellt: 05.11.2026
Eingesehene Ausgangsbasis: main, Commit 65819263f8d76b6fe7099319080f7b17a6c6d7e1.
Der folgende Text ist ein vollständiger Arbeitsauftrag für die umsetzende Entwicklungs-KI. Prüfe zu Arbeitsbeginn erneut den dann aktuellen Repository-Stand.

### 1. Auftrag und Ziel

Baue das bestehende Spiel von einer Konkurrenz zwischen Speditionen zu einer branchenübergreifenden Wirtschaftssimulation um.

Die vier KI-Spieler sind allgemein Unternehmer. Jeder darf innerhalb der Spielregeln Grundstücke erwerben, Betriebe gründen oder übernehmen, Waren produzieren, handeln, transportieren, Gebäude errichten und Immobilien vermieten. Ein Unternehmer darf mehrere Branchen gleichzeitig betreiben und seine Lieferketten zunehmend selbst kontrollieren. Er kann mit einer Bäckerei, Landwirtschaft, Immobilien oder IT erfolgreich sein, ohne zwingend ein Transportunternehmen aufzubauen.

Die normale Partie startet mit vier Unternehmern. Die vorhandene Unterstützung für zwei bis vier Spieler bleibt bestehen. Betriebe, Filialen und Tochterbereiche belegen keine zusätzlichen Spielerplätze. Bürgermeister, Behörden, Banken, öffentliche Betriebe und NPC-Händler bleiben eigenständige Akteure außerhalb dieser vier Wettbewerbsplätze.

Ziel der Unternehmer: höchstmöglicher tatsächlich erwirtschafteter Nettogewinn, ausreichende Liquidität und langfristig eine dominante Marktposition. Expansion ist ein Mittel dazu: Die KI darf Grundstücke, Lieferanten, Verarbeiter, Verkaufsstellen, Lager und Immobilien kombinieren, Marktanteile gewinnen und Konkurrenten wirtschaftlich unter Druck setzen.

Es soll eine spielbare Simulation entstehen: Die Entscheidungen der KI verändern Eigentum, Bestände, Arbeitsplätze, Produktion, Verkehr, Preise und die Stadt. Behalte Windows als Zielplattform, Godot und die vorhandene isometrische Voxel-Pixeloptik bei.

### 2. Den bestehenden Code weiterentwickeln

Beginne mit einem Bestandsbericht anhand des Codes. Lies mindestens README.md, STATUS.md sowie die vorhandenen Wirtschafts-, Versorgungs-, Wohnungs-, Stadtentwicklungs- und Strategiedokumente. Unterscheide tatsächlich implementierte Funktionen von älteren Planungsabschnitten und offenen Grenzen.

Wichtige vorhandene Anknüpfungspunkte:

| Bereich | Vorhandene Grundlage | Konsequenz für den Umbau |
|---|---|---|
| Unternehmer | scripts/economy/company.gd, ledger.gd, company_forms.gd | Company ist noch auf Transport ausgerichtet; zu einem allgemeinen Unternehmensinhaber erweitern. |
| Geld und Finanzierung | economy.gd, banking.gd, central_bank.gd, player_loans.gd, insolvency.gd | Konten, Kredite, Rückzahlung, Haftung und Insolvenz weiterverwenden. |
| Waren | stock_book.gd, Trader.MATERIALS, Retail.GOODS, CityGoods.GROUPS, Catalog.CARGO | Artikelidentitäten, Einheiten, Eigentum und Bestände verbindlich miteinander verbinden. |
| Handel und Gastronomie | retail.gd, tiers.gd, citizens.gd, households.gd | Bestehende NPC-Betriebe für Unternehmereigentum öffnen; Haushaltsnachfrage weiterverwenden. |
| Produktion | trader.gd mit vorhandenen Produktionsrezepten | Zu einer allgemeinen Produktionslogik für verschiedene Besitzer und Standorte erweitern. |
| Transport und Lager | logistics.gd, company_operations.gd, Fahrzeug- und Personalsystem | Für eigene und fremde Waren nutzen; Transport bleibt eine von mehreren Geschäftsmöglichkeiten. |
| Bauen und Eigentum | parcels.gd, permits.gd, construction.gd, housing.gd | Grundstücke, Genehmigungen, Bauphasen, Wohnungen und Mietverträge integrieren. |
| Stadt und Versorgung | mayor.gd, mayor_agent.gd, town_hall.gd, city_depot.gd, road_care.gd, city_fleet.gd | Öffentliche Beschaffung und sichtbare Einsätze erhalten und um Energieversorgung erweitern. |
| Gelände und Grafik | city_data.gd, city_generator.gd, vorhandener Renderer, tools/vox | Höhen, Berge und neue Betriebsmodelle ergänzen. |
| KI und Nachvollziehbarkeit | agent_controller.gd, observation_builder.gd, action_executor.gd, rule_brain.gd, action_assist.gd, activity_feed.gd, activity_layer.gd | Neue Wirtschaftsaktionen prüfen und sichtbar ausführen. |
| Strategien | strategy_evaluator.gd, strategy_learner.gd, strategy_memory.gd, config/strategies.json | Ergebnisse aller Branchen bewerten, nicht nur Flottenkennzahlen. |

Konkrete Grenzen der eingesehenen Ausgangsbasis:

- Die Bäckerei im Retail-System kauft derzeit fertiges Brot ein. Eine vollständige Getreide-Mehl-Backkette muss ergänzt werden.
- Stahl ist beim Großhändler derzeit ein Importartikel. Eigener Bergbau und eigene Stahlproduktion müssen ergänzt werden.
- Strom, Wasser und Abwasser werden bei Grundstücken bisher vereinfacht über die Nähe zur Bebauung beurteilt. Das ersetzt kein Kraftwerk mit begrenzter Leistung und Verbrauchsabrechnung.
- Bauunternehmen und viele Wirtschaftsakteure sind bereits vorhanden, aber noch nicht durchgängig als frei gründbare Betriebe der vier Spieler organisiert.
- CityData enthält noch kein eigenständiges Höhenmodell für wirtschaftlich relevante Berge.
- RuleBrain besitzt inzwischen eine Investitionskreditprüfung für Fahrzeugkäufe. Verallgemeinere sie für andere Betriebsarten und passende Sicherheiten.
- Die aktuelle Dokumentation beschreibt schlechte Ergebnisse bei unnötigen Hofumwegen und dem Anlegen einer Linie für fast jeden Einzelauftrag. Reaktiviere dieses Verhalten nicht als allgemeine Standardstrategie.

Nutze die bestehende Architektur. Vermeide parallele Warenbücher, doppelte Mietsysteme, zusätzliche Geldquellen und eine zweite unabhängige Personalsimulation.

### 3. Gemeinsamer Unternehmenskern

Trenne logisch:

1. Unternehmer/KI-Spieler: Strategie, Persönlichkeit, API-Konfiguration, Gedächtnis und Wettbewerbsidentität.
2. Bestehende Company: Eigentümer, Rechtsform, Finanzierung, zentrale Buchhaltung und Insolvenzverantwortung.
3. Betrieb/Business: eine wirtschaftliche Einheit an einem Standort, etwa Bäckerei, Feldbetrieb, Restaurant, Bergwerk, Lager oder IT-Büro.
4. Gebäude, Grundstück, Maschine und Wohnung: eigenständige Vermögens- und Nutzungsobjekte.

Für den ersten Umbau bleibt die vorhandene Company die rechtliche und finanzielle Klammer eines Unternehmers. Mehrere Betriebe sind Betriebsbereiche derselben Company. Füge nicht für jede Bäckerei einen neuen Eintrag in die Liste der KI-Spieler ein.

Jeder Betrieb erhält mindestens:

- stabile ID, Eigentümer, Branche, Name und Standort;
- Grundstücks- und Gebäuderechte;
- Status: geplant, genehmigt, im Bau, eingerichtet, betriebsbereit, aktiv, blockiert, geschlossen oder in Verwertung;
- zugeordnete Mitarbeiter, Qualifikationen, Maschinen und verfügbare Arbeitskapazität;
- Eingangs- und Ausgangslager mit Kapazitäten;
- Rezepte oder Dienstleistungsprozesse;
- Strom-, Wasser-, Wartungs- und Entsorgungsbedarf;
- Preise, Lieferanten, Kunden, Bestellungen und Verträge;
- Investitionsbedarf, reserviertes Betriebsbudget und Kostenstelle;
- Umsatz, Kosten, Ergebnis, Auslastung und belegte Blockadegründe.

Die Company-Buchhaltung bleibt die finanzielle Wahrheit. Betriebsergebnisse werden über Kostenstellen ausgewertet. Eine weitere Betriebsansicht darf dieselbe Zahlung nicht erneut buchen. Werden eigene Betriebskonten eingeführt, müssen sie in der Unternehmenssumme korrekt konsolidiert werden.

Trenne Hauptsitz, Betriebsstandorte und Transportdepots. Beseitige Annahmen, nach denen jeder Unternehmer zwingend Fahrzeuge oder einen Transportdepot-Eintrag an Position null besitzen muss.

Neue Partien starten mit vergleichbaren Mitteln, einem kleinen Hauptsitz und freiem Startgrundstück. Startpersonal und Fahrzeuge müssen zum allgemeinen Unternehmertum passen; keine teure Zwangsspedition für jeden Bäcker oder Vermieter.

Alte Spielstände werden migriert: Eine vorhandene Spedition wird zum Transportbetrieb ihres bisherigen Unternehmers. Geld, Kredite, Fahrzeuge, Grundstücke, Aufträge, Mitarbeiter und API-Konfiguration bleiben erhalten.

### 4. Waren, Produktion und Transport als gemeinsamer Kern

Führe einen verbindlichen Artikelkatalog ein. Vorhandene Kataloge werden darin registriert beziehungsweise eindeutig darauf abgebildet.

Jeder Artikel braucht ID, Anzeigename, Basiseinheit, Transportklasse, Gewicht/Volumen, Lagerbedingungen, Haltbarkeit und zulässige Verwendungen. Konkrete Artikel wie Mehl, Brot, Eisenerz und Stahl sind von Transportkategorien wie Lebensmittel oder Baustoffe zu unterscheiden.

Die vorhandenen Bestände werden weiterverwendet. Jede Warenmenge hat Eigentümer und tatsächlichen Standort. Das System muss Gebäude, Fahrzeuge und relevante Produktionsorte eindeutig abbilden. Bestehende ganzzahlige Gebäude-IDs dürfen durch neue Standorttypen nicht stillschweigend falsch interpretiert werden.

Jedes Produktionsrezept definiert:

- benötigte Eingangswaren und Mengen;
- Ausgangswaren, Nebenprodukte und Abfälle;
- Produktionsdauer, Maschinenkapazität und Personalbedarf;
- Strom- und Wasserbedarf;
- Lagerbedingungen und notwendige Betriebsvoraussetzungen.

Produktionsablauf:

Bedarf feststellen → Einkauf vereinbaren → Bestand und Budget reservieren → Transport beauftragen → am richtigen Standort entladen → Voraussetzungen prüfen → Produktionsauftrag ausführen → Eingangswaren verbrauchen → Ausgangswaren einlagern → verkaufen und ausliefern.

Fehlen Material, Personal, Energie, Maschinen oder Lagerkapazität, zeigt der Betrieb den konkreten Grund. Reservierungen verhindern Doppelverkauf und gleichzeitige Mehrfachverarbeitung. Beim Abbruch werden Reservierungen nachvollziehbar freigegeben; bereits verbrauchte Ressourcen bleiben verbraucht.

Produktion verwandelt Waren. Deshalb ist eine konstante Gesamtzahl aller Warenstücke keine sinnvolle Prüfmethode. Prüfe je Artikel die dokumentierten Quellen, Rezeptausgänge, Verbräuche und verbleibenden Bestände. Recyclingkreisläufe dürfen weder Material noch Geld beliebig vermehren.

Bei jeder umgestellten Ware müssen die bisherigen pauschalen Nachschubquellen geprüft werden, insbesondere die Produzenten-/Großhandelslogik F0/W0 im Retail-System und die Bauhofrezepte. Eine Ware stammt nach der Umstellung aus einem nachverfolgten lokalen Produktionsbetrieb oder einem definierten Import. Sie darf nicht zusätzlich weiterhin durch den alten vereinfachten Erzeugungsweg entstehen. Erhalte bestehende Bestände beim Übergang.

Eigene Rohstoffe entstehen aus dokumentiertem Abbau, Landwirtschaft oder anderen definierten Prozessen. Importe und Exporte erscheinen an einem Kartenrand, Hafen oder Terminal mit Lieferzeit, Bestand und Zahlung. Der Großhändler bleibt eine mögliche Bezugsquelle; er soll die lokale Wirtschaft ergänzen und keine unbegrenzte Garantieabnahme zu festen Gewinnpreisen bieten.

Warenpreise reagieren auf Angebot, Nachfrage, Qualität, Lieferzeit und Kosten. Jede Nachfrage braucht einen tatsächlichen Abnehmer mit Budget. Überproduktion kann Lager füllen, Preise drücken, verderben und Verlust verursachen.

### 5. Berge, Landschaft und Rohstoffrechte

Erweitere die große Karte um Ebenen, Hügel, erkennbare Berge, Wälder, Flüsse, fruchtbare Felder und Rohstoffvorkommen. Berge müssen in der isometrischen Ansicht räumlich erkennbar sein und Standortentscheidungen beeinflussen.

Speichere Höhe, Steigung und relevante Boden-/Lagerstätteneigenschaften. Passe Darstellung, Verdeckung und Wegfindung zusammen an. Fahrzeuge dürfen nicht durch Felsen fahren oder Steilhänge wie ebene Straßen überqueren.

Auf einem Seed müssen Hauptsitze, Grundversorgung und wirtschaftlich nutzbare Gebiete erreichbar sein. Sichere sinnvolle Straßenverbindungen zu Bergbauregionen. Die räumliche Verteilung darf verschiedene Strategien ermöglichen, aber keinen Spieler ohne praktikablen Zugang zum Markt starten lassen.

Grundstückskauf und Abbaurecht sind eindeutig zuzuordnen. Ein Bergwerk darf nicht auf dem Nachbargrundstück fördern. Vorkommen haben erkundbare Menge, Qualität, Förderkosten und Förderkapazität. Abbau verringert den Vorrat; erschöpfte Lagerstätten schließen oder werden umgenutzt.

Forst und Landwirtschaft besitzen eigene Wachstums- und Regenerationsregeln. Die Fläche selbst, ihre Nutzung und ihr wirtschaftlicher Zustand sollen auf der Karte sichtbar sein.

### 6. Pflichtbranchen und ihre Lieferketten

Diese Branchen müssen im fertigen Umbau gründbar beziehungsweise erwerbbar sein:

| Branche/Betrieb | Wichtige Eingänge und Voraussetzungen | Ergebnis und Abnehmer |
|---|---|---|
| Landwirtschaft | gekaufte oder gepachtete Felder, Saatgut, Wasser, Arbeitskräfte, Maschinen und Betriebsmittel | Getreide, Gemüse, Kartoffeln oder andere konfigurierte Ernten |
| Mühle | angeliefertes Getreide, Energie, Personal, Mühlentechnik | Mehl für Bäckereien und weitere Verarbeitung |
| Bäckerei | Mehl, Wasser, Hefe oder Sauerteig, Salz, Energie; je Sortiment weitere Zutaten | Brot und Brötchen für Bürger, Geschäfte, Restaurants und Einrichtungen |
| Konditorei/erweitertes Backangebot | zusätzlich Zucker, Eier, Butter/Milchprodukte, gegebenenfalls Obst | Kuchen und höherwertige Backwaren mit zusätzlichem Aufwand |
| Futtermittelbetrieb | Getreide und geeignete weitere Agrarprodukte | Tierfutter für landwirtschaftliche Tierhaltung |
| Tierhaltung | Tiere, Futter, Wasser, Stall, Personal und Zeit | Nutztiere; bei passenden Betriebsarten zusätzlich Milch oder Eier |
| Schlachthof | Nutztiere, Personal, Energie, Wasser, Kühlung und Entsorgung | freigegebenes Fleisch für Fleischereien und Großhandel |
| Metzgerei/Fleischerei | angeliefertes Fleisch, Salz, Gewürze, je Rezept Hüllen, Verpackung, Kühlung, Wasser und Energie | Fleischwaren und Wurst für Bürger, Gastronomie und Geschäfte |
| Molkerei | Milch, Kühlung, Energie, Personal und Verpackung | konfigurierte Milchprodukte für Läden, Bäckereien und Restaurants |
| Restaurant | passende Zutaten, Getränke, Personal, Küche, Wasser und Energie | tatsächlich verkaufte Gerichte und Bewirtungsleistungen |
| Einzelhandel | Sortiment, Nachschub, Verkaufsfläche und Personal | Verkauf an zahlungsfähige Haushalte |
| Transportbetrieb | Fahrzeuge, Fahrer, Treibstoff, Wartung und Transportaufträge | vergütete Transporte für beliebige Branchen |
| Lager/Logistikzentrum | Fläche, Lagertechnik, Personal, Energie und reale Lagerkunden | Lager-, Kühl-, Umschlag- und Kommissionierleistungen |
| Bauunternehmen | Personal, Maschinen, Genehmigungen, Material, Zeit und Bauverträge | erbrachte Bauleistungen und übergebene Gebäude |
| Immobilienbetrieb | erworbene Grundstücke, Häuser, Wohnungen oder Gewerbeflächen; Finanzierung und Instandhaltung | Mieteinnahmen, projektbezogene Entwicklung oder Verkauf |
| Bergbau/Steinbruch | passendes Vorkommen, Rechte, Maschinen, Energie, Arbeitskräfte und Zufahrt | Eisenerz, Kohle, Kalkstein, Sand, Kies oder andere definierte Rohstoffe |
| Kokerei | geeignete Kohle, Energie, Personal und Anlagen | Koks für die Erzroute der Stahlproduktion |
| Stahlwerk | definierte Rohstoffroute, Energie, Wasser, Personal und Anlagen | Stahl für Bau, Maschinen und weitere Industrie |
| Recyclingbetrieb | angelieferte Altmaterialien, Sortierung, Energie und Personal | aufbereiteter Schrott und Sekundärrohstoffe |
| IT-Unternehmen | Büro, qualifizierte Mitarbeiter, Computer/Server, Strom und Internet | Software-, Support-, Wartungs- und Digitalisierungsleistungen |

Alle Mengen, Zeiten und Preise sind Spielparameter. Dokumentiere sie als kalibrierbare Spielrezepte, nicht als verbindliche Angaben zur realen Betriebsführung.

#### Landwirtschaft und Backwaren im Detail

Ein Unternehmer muss ein Feld erwerben oder pachten und die Bewirtschaftung organisieren können. Sichtbare Phasen: Vorbereitung, Aussaat, Wachstum, Pflege, Ernte und Abtransport. Wetter, Wasser, Bodenqualität, verfügbare Arbeit und Maschinen beeinflussen die Ernte. Erntegut liegt zunächst am Feld oder im zugehörigen Lager und muss weitertransportiert werden. Je Kultur können Dünger, Kompost und weitere Betriebsmittel als eigene Waren nötig sein; ihre Herkunft und Kosten müssen ebenfalls definiert sein.

Die Mühle verarbeitet Getreide zu Mehl. Die Bäckerei produziert selbst aus Zutaten; sie darf nicht lediglich unbemerkt fertiges Brot aus einer pauschalen Quelle beziehen. Ein Backwarenhandel darf dagegen bewusst fertige Ware weiterverkaufen und muss als solcher erkennbar sein.

Grundsortiment und erweitertes Sortiment besitzen unterschiedliche Zutaten. Für ein einfaches Brot sind Eier und Butter keine allgemeine Pflichtzutat; bei passenden Kuchen- oder Feingebäckrezepten dürfen sie erforderlich sein.

Samen und Tierfutter werden als Waren geführt. Wachstum und Vermehrung benötigen definierte Zeit und Ressourcen. Traktoren, Erntetechnik und Maschinen können gekauft oder gemietet werden; eine kleine Firma muss auch mit einer wirtschaftlich sinnvollen Einstiegsausstattung starten können.

#### Fleisch, Kühlung und Gastronomie

Verbinde Landwirtschaft, Futtermittel, Tierhaltung, Schlachthof und Fleischerei. Eine kleine Fleischerei kann Fleisch einkaufen, ohne selbst Tierhaltung oder einen Schlachthof zu besitzen.

Verderbliche Waren haben Alter und Lagerbedingungen. Geeignete Fahrzeuge und Kühlräume beeinflussen die Nutzbarkeit. Unterbrochene Kühlung, verspätete Lieferung oder fehlende Zutaten verursachen belegbare Ausfälle und Verluste.

Restaurants kochen konkrete Rezepte aus ihrem tatsächlichen Lager. Bürger besuchen sie aufgrund von Einkommen, Bedarf, Erreichbarkeit, Preis und Zufriedenheit. Es wird nur verkauft, was vorhanden beziehungsweise herstellbar ist und bezahlt werden kann.

#### Woher kommt Stahl?

Stahl ist kein fertig abbaubarer Rohstoff. Unterscheide eine Erzroute und eine Recyclingroute:

- Erzroute: Eisenerz aus dem Bergwerk sowie Koks und Kalkstein werden im integrierten Werk zunächst zu Roheisen und anschließend zu Stahl verarbeitet.
- Recyclingroute: aufbereiteter Stahlschrott wird im Elektrostahlwerk mit entsprechendem Strombedarf verarbeitet.

Das sind vereinfachte Spielrouten. Konfiguriere Erträge, Energiebedarf und Verluste. Integriere Nebenprodukte und Abfälle mindestens als dokumentierte Bestands- beziehungsweise Entsorgungsströme.

Das Stahlwerk erzeugt Nachfrage nach Rohstoffen und Transporten; seine Produkte werden von Baufirmen, Maschinenherstellern, Metallverarbeitern und öffentlichen Projekten benötigt. Unterscheide gegebenenfalls Baustahl, Bleche und allgemeine Stahlprodukte, sobald die Abnehmer diese Differenzierung tatsächlich nutzen.

#### IT als echte Dienstleistungsbranche

IT-Unternehmen verdienen durch Verträge mit anderen Betrieben und der Stadt: Kassensysteme, Lagerverwaltung, Büro-IT, Softwareentwicklung, Wartung, Support und Automatisierung.

Computer, Server und Ersatzteile werden physisch geliefert. Software und Support sind Dienstleistungen und werden nicht als Kisten mit LKW transportiert.

Dienstleistungsaufträge brauchen Umfang, qualifizierte Arbeitszeit, Kapazität, Termin, Preis und Abnahme. Ein IT-Betrieb kann nicht beliebig viele Kunden ohne zusätzliches Personal bedienen.

Digitalisierung darf messbare, begrenzte Vorteile erzeugen, beispielsweise weniger Verwaltungsaufwand oder bessere Lagerplanung. Sie darf keinen pauschalen, unbegrenzten Geldbonus geben.

### 7. Weitere sinnvolle Betriebe

Lege diese Erweiterungen im selben datengetriebenen System an. Priorisiere sie so, dass jede neue Ware einen nachvollziehbaren Abnehmer besitzt:

| Betrieb | Beispiel einer verbundenen Kette |
|---|---|
| Forstbetrieb und Sägewerk | Waldpflege und Holzernte → Bretter → Möbel, Bau und Paletten |
| Möbelhersteller | Bretter + Beschläge + Arbeit → Möbel → Haushalte, Büros und Hotels |
| Beton-/Fertigteilwerk | Sand/Kies + Zement + Wasser → Betonprodukte → Baustellen |
| Zementwerk | passende mineralische Rohstoffe + Energie → Zement → Betonwerk |
| Ziegelei | Ton + Energie → Ziegel → Baufirmen |
| Glaswerk | konfigurierte mineralische Eingänge + Energie → Glas → Fenster und Gebäude |
| Metallverarbeitung | Stahl → Träger, Beschläge und Komponenten → Bau und Maschinen |
| Maschinenbau | Metallkomponenten + Technik → Maschinen → Landwirtschaft, Bergbau und Produktion |
| Brauerei/Getränkebetrieb | Agrarprodukte + Wasser + Energie + Gebinde → Getränke → Handel und Gastronomie |
| Verpackungsbetrieb | geeignete Rohstoffe → Kartons, Behälter oder Verpackung → Produzenten und Geschäfte |
| Werkstatt | Ersatzteile + qualifizierte Arbeit → gewartete Fahrzeuge und Maschinen |
| Entsorgungsunternehmen | Abfälle und Rückbau → Sortierung/Recycling/Entsorgung gegen Vergütung |
| Gebäudedienstleister | Personal + Material → Reinigung, Instandhaltung und Gartenpflege |
| Hotel | Gebäude + Personal + Lebensmittel + Wäsche + Energie → Übernachtungen und Bewirtung |
| Großhandel | Einkauf und Lagerung verschiedener Produzenten → gebündelte Versorgung kleiner Betriebe |
| Bau- und Maschinenvermietung | erworbene Geräte + Wartung → zeitlich begrenzte Vermietung |

Diese Erweiterungsliste darf nicht dazu führen, dass die Pflichtketten nur als leere Gebäudehüllen fertiggestellt werden. Schließe zuerst vollständige Kreisläufe.

### 8. Kommunales Atomkraftwerk und Energieversorgung

Auf der Karte steht ein Atomkraftwerk. Eigentümer und politisch verantwortlicher Chef ist die Stadt, vertreten durch den Bürgermeister. Es ist kein fünfter privater Wettbewerbsunternehmer.

Der Bürgermeister entscheidet über Betriebsbudget, Beschaffung, Wartung, Ausbau, Stromtarife und Netzausbau im Rahmen der städtischen Ziele und Zuständigkeiten. Das Kraftwerk besitzt eine qualifizierte Betriebsleitung und Personal. Der Bürgermeister muss nicht selbst jede technische Tätigkeit ausführen.

Erforderliche Spielströme:

- Brennelemente als abstrakte, spezialisierte Beschaffungsware mit Lieferzeit, Preis und geeigneter Transportabwicklung;
- Ersatzteile, Werkzeuge, Filter und weitere konfigurierte Wartungsmaterialien;
- Wasser-/Versorgungsanbindung sowie Arbeits- und Wartungsleistungen;
- dokumentierte Reststoff- und Abfallströme mit begrenzter Lagerung und Entsorgung.

Unverarbeitetes Uranerz darf nicht unmittelbar als verwendbares Brennelement gelten. Für den ersten vollständigen Spielstand können Brennelemente von einem spezialisierten externen Anbieter importiert werden. Eine vorgelagerte Brennstoffindustrie ist keine Voraussetzung für den Einstieg.

Modelliere den Kraftwerksbetrieb wirtschaftlich und auf abstrakter Spielebene: Leistung, Betriebsbereitschaft, Brennstoffvorrat beziehungsweise verbleibendes Energiepotenzial, Wartungsbedarf, Personal, Kosten und Ausfallzeiten. Keine realen kerntechnischen Betriebsanleitungen.

Strom wird über Netze geliefert, nicht per LKW. Leitungen, Umspann-/Verteilerpunkte, Anschlusszustand und Kapazität begrenzen die Versorgung. Jeder angeschlossene Verbraucher hat einen messbaren Bedarf und zahlt Stromkosten an den kommunalen Versorger. Erzeugung, Verbrauch, Verluste und gegebenenfalls Speicherung werden konsistent bilanziert. Vorhandene pauschale Energiezahlungen eines umgestellten Betriebs werden durch diese Abrechnung ersetzt oder darin aufgeführt, nicht zusätzlich ein zweites Mal erhoben.

Folgen von Engpässen: Produktion wird gedrosselt oder gestoppt, Kühlketten geraten unter Druck, IT-Dienste fallen aus, Zufriedenheit und Steuereinnahmen können sinken. Die UI zeigt Ort, Ursache und betroffene Betriebe. Die Stadt kann priorisieren und ausbauen; ihre Maßnahmen brauchen Geld, Material, Arbeit und Zeit.

Ein Ausbau des Kraftwerks oder Netzes erzeugt reale Bau-, Industrie- und Transportaufträge. Private Unternehmer können diese Aufträge übernehmen.

Verhindere einen Startstillstand: Die Stadt beginnt mit funktionsfähiger Grundversorgung und nachvollziehbar finanzierten Anfangsbeständen. Ersatzteile benötigen Stahl und Strom; das erste Stahlwerk darf daher nicht an einem bereits ausgefallenen Kraftwerk ohne Anlaufreserve scheitern. Definiere diese Startvorräte und begrenzte Notimportmöglichkeiten ausdrücklich.

### 9. Grundstücke, Wohnimmobilien und Stadtentwicklung

Jeder Unternehmer kann verfügbare Felder, Gewerbe- und Industrieflächen sowie angebotene Häuser, Wohnungen und Büroflächen erwerben. Pacht und Miete bleiben zusätzliche Einstiegsmöglichkeiten.

Kauf ist ein verbindlicher Vorgang mit Verkäufer, Preis, Finanzierung, Rechten und Eigentumsübergang. Gegebenenfalls sind Genehmigungen, Erschließung und Nutzungsänderung nötig. Ein Klick auf die Karte schenkt kein Grundstück.

Ein erworbenes Gebäude wird nicht automatisch zu einer beliebigen Fabrik. Eignung, Nutzung, Größe, Anschlüsse, Arbeitsplätze und erforderlicher Umbau müssen passen.

Wohnungen werden über die bestehenden Wohnungs- und Haushaltsmodelle vermietet. Mieter haben Einkommen, Bedarf und Zahlungsfähigkeit. Leerstand, Mietrückstände, Instandhaltung und Kreditraten beeinflussen das Ergebnis. Einzug und Umzug erzeugen die vorhandenen Transport- und Versorgungsbedarfe.

Ein Unternehmer darf zugleich Bauherr, Baufirma und später Vermieter sein. Aufträge zwischen eigenen Betriebsbereichen sind konsolidiert interne Leistungen. Bei beauftragten Mitspielern entstehen echte externe Zahlungen.

Das Bauunternehmen benötigt Material, Mitarbeiter, Geräte und Baukapazität. Grundstücke und Aufträge allein machen noch keinen Baufortschritt. Nutze die vorhandenen Genehmigungs-, Bauphasen- und Übergaberegeln.

Öffentliche Straßen, das Rathaus und kritische kommunale Infrastruktur bleiben als öffentliche Nutzungen erhalten. Privatunternehmen können die Stadt nicht durch einen normalen Grundstückskauf ihrer einzigen Zufahrt oder gesamten Grundversorgung berauben.

### 10. Dominanz, Expansion und Konkurrenz

Die KI soll selbstständig Chancen erkennen:

- bei Mehlmangel eine Mühle eröffnen;
- nach erfolgreicher Bäckerei eigene Felder kaufen;
- bei teuren Fremdtransporten Lager oder eigene Fahrzeuge wirtschaftlich prüfen;
- einem Konkurrenten Stahl liefern und später selbst weiterverarbeiten;
- günstige Immobilien entwickeln oder vermieten;
- im Insolvenzverfahren Grundstücke, Maschinen, Bestände oder komplette angebotene Betriebe erwerben;
- unrentable Bereiche schließen, verpachten, verkaufen oder umstellen.

Ermögliche Spezialisierung und vertikale Integration. Verträge, Verhandlungen, Gegenangebote, Zahlungsziele, Lieferfristen und berechtigte Vertragsfolgen gelten über Branchengrenzen hinweg.

Dominanz zeigen: Marktanteile je Branche, versorgte Kunden, Beschäftigte, kontrollierte Produktionskapazität, erworbene Fläche, Vermögen, Schulden und Gewinn. Eigentum, Pacht und nur reservierte Fläche getrennt ausweisen.

Grundstückshortung muss Kosten und Risiken haben: Grundsteuer, Finanzierung, Leerstand, gebundenes Kapital und gegebenenfalls beschlossene Regeln für ungenutzte Flächen. Dominanz darf eine reale Strategie sein; sie darf nicht durch kostenloses Reservieren unbegrenzter Flächen entstehen.

Bestehende Sabotage-, Abwerbe-, Anzeigen- und Kontrollmechaniken bleiben im Regelrahmen nutzbar und werden für neue Betriebsarten sinnvoll geprüft. Eingriffe brauchen Kosten, Risiko, Abklingzeit und sichtbare Folgen.

Die Stadt-KI verfolgt Gemeinwohl, Versorgung, Zufriedenheit, Beschäftigung und tragfähige öffentliche Finanzen. Sie ist kein Komplize eines Spielers und soll Wettbewerb auch dann ermöglichen, wenn ein Unternehmer sehr stark wird.

### 11. Geld, Kredite, Gewinn und Insolvenz

Alle Branchen verwenden die vorhandene Buchhaltung, Banklogik und Spielzeit.

- Kredite schaffen finanzielle Verpflichtungen und sind kein Gewinn.
- Grundstücks- und Maschinenkäufe sind Investitionen; sie verbrauchen Liquidität.
- Produktion schafft Bestand beziehungsweise wirtschaftlichen Wert, aber noch keinen Verkaufserlös.
- Bezahlt wird entsprechend dem verbindlichen Vertragsmodell mit tatsächlicher Gegenpartei.
- Eigene Warenbewegungen zwischen Betriebsstätten erzeugen keinen externen Konzernumsatz.
- Löhne, Sozialabgaben, Steuern, Zinsen, Energie, Miete, Instandhaltung und Abschreibungen werden genau einmal verbucht.
- Bestehende Privat-, Bank-, Staats- und Unternehmensbuchungen dürfen durch neue Betriebskonten nicht überschrieben oder doppelt angerechnet werden.
- Neue Geldschöpfung darf ausschließlich aus dem vorhandenen expliziten Bank-/Zentralbankmodell stammen; Zinszahlungen allein erzeugen keine zusätzliche Geldquelle.

Vor einer Investition kalkuliert die KI Nachfrage, realistische Auslastung, Materialversorgung, Personal, Energie, Transport, laufende Verpflichtungen und eine Reserve. Sie darf Kredite aufnehmen, muss aber Raten und Zinsen bedienen können. Eine Neugründung außerhalb der Transportbranche darf nicht allein deshalb ausgeschlossen sein, weil noch kein Transportumsatz oder Fahrzeugpfand vorhanden ist. Prüfe dafür Eigenmittel, Projekt und Sachwerte, Nachfrage, Anlaufreserve und tragfähige Rückzahlung; eine Kreditzusage ist weiterhin eine geprüfte Entscheidung der Bank.

Beziehe alle Betriebsbereiche, Vermögenswerte, Verpflichtungen, offenen Aufträge und Warenrechte in die Insolvenz ein. Lohnrückstände und Kundenwaren müssen korrekt behandelt werden. Versteigerungen dürfen Betriebe oder Vermögenspakete erhalten und neue Eigentümer ermöglichen; ein Verkauf löscht bestehende Rechte nicht willkürlich.

Die Rangliste verwendet konsolidierten Nettogewinn und Zahlungsfähigkeit. Umsatz, Kreditauszahlungen, selbst angesetzte Grundstückswerte und interne Verrechnung dürfen keinen künstlichen Sieg erzeugen.

Behalte die vorhandenen Partiedauern, Etappenstatistiken und den Endlosbetrieb bei. In langen Partien kann ein zeitweise führender Unternehmer später verlieren oder insolvent werden. Im Endlosbetrieb darf eine vorübergehende Konzentration auf einen zahlungsfähigen Unternehmer nicht unbeabsichtigt die Simulation beenden; Siegbedingungen und Nachfolgeunternehmer sind dafür ausdrücklich zu konfigurieren.

### 12. Bevölkerung und Nachfrage

Jede relevante Branche muss mit einer Nachfrage verbunden sein:

Beschäftigung → Lohn → Haushaltsbudget → Einkäufe, Wohnen und Dienstleistungen → Betriebseinnahmen → Investitionen und neue Arbeitsplätze.

Nutze bestehende Bürger, Haushalte, Wohnungen, Wohnstufen, Bedürfnisse, Zufriedenheit, Zuzug, Krankheit und Arbeitsmarktmechaniken. Ein Besuch einer Figur darf nicht eine zusätzliche zweite Konsumbuchung auslösen.

Geschäfte und Restaurants konkurrieren um begrenzte Kaufkraft. Standort, Preis, Sortiment, Erreichbarkeit, Qualität und Versorgung beeinflussen die Kundschaft. Eine zusätzliche Bäckerei erzeugt nicht automatisch zusätzliche hungrige Einwohner mit unbegrenztem Geld.

Jobs unterschiedlicher Branchen brauchen passende Qualifikationen. Bäcker, Landarbeiter, Fahrer, Lagerkräfte, Bauarbeiter, IT-Fachkräfte und Maschinenbediener können unterschiedliche Löhne und Schulungsbedarfe haben. Beschäftigte bleiben konkrete Personen mit Arbeitgeber, Arbeitsplatz und Haushalt. Erweitere das vorhandene Qualifikationsmodell um die benötigten Fachrollen. Überführe vorhandene Personalpauschalen kontrolliert in dieses System; dieselbe Person und dieselbe Lohnzahlung dürfen durch sichtbares Personal nicht ein zweites Mal entstehen.

Verwaltung, Schulen, Kindergärten, Kliniken, Stadtlager und öffentliche Unternehmen treten als nachvollziehbar finanzierte Abnehmer auf. Stadtwachstum und wirtschaftliche Krisen sollen Bedarfe, Auslastung und das sichtbare Stadtbild verändern.

### 13. Sichtbarer Betrieb und verständliche Ursachen

Die Karte darf keine Ansammlung leerer Gebäude sein.

Ein Betrieb zeigt, soweit relevant: Mitarbeiter beim Arbeitsbeginn, Materialannahme, Einlagerung, Produktion, Kommissionierung, Verladung, Verkauf, Instandhaltung und Rückmeldung.

Jede Tätigkeit besitzt Ziel, Voraussetzungen, Dauer und Ergebnis. Arbeitsphasen laufen weiter, solange ein Auftrag besteht; Figuren werden nach dem Anlaufen eines festen Punktes nicht dauerhaft abgestellt. Pausen und echter Leerlauf werden verständlich angezeigt.

Transportfahrzeuge fahren nachvollziehbar vom Abholort zum tatsächlichen Ziel, warten bei Engpässen, laden die richtige Ware und kehren sinnvoll zurück. Eigene Fahrzeuge und Fremdvergaben sind beide möglich. Hofumschlag ist eine bewusste logistische Entscheidung und kein Pflichtumweg jeder Fracht.

Nutze die aktuellen Personal-, Idle-, ActivityFeed- und ActivityLayer-Systeme. Verwende keine veraltete Routine aus einem älteren Branch, ohne sie mit dem aktuellen Code abzugleichen.

Anklickbare Betriebsansicht:

- Eigentümer, Branche und Betriebsstatus;
- aktuelle Mitarbeiteraufgaben;
- Bestände, reservierte Mengen, unterwegs befindliche Lieferungen;
- laufende Produktion und nächster Fertigstellungstermin;
- konkrete Blockade, beispielsweise „Wartet auf Mehl", „Kühlraum ohne Strom" oder „Maschine ohne Bediener";
- Aufträge, Lieferanten, Kunden, Kapazität und Ergebnis;
- letzte Entscheidung mit kurzer ausdrücklicher Begründung und später gemessener Folge.

Zeige Entscheidungen und Betriebsrückmeldungen mit ihrer tatsächlichen Herkunft. Deterministische Ausführung ist keine zusätzliche Sprachmodellentscheidung. Fordere keine versteckten Gedankengänge an; kurze explizite Begründungen reichen.

Neue grafische Assets gehören zur vorhandenen Gestaltung: bewirtschaftete Felder, Wachstumsstufen, Stollen/Steinbruch, Halden, Mühle, Backstube, Fleischerei, Restaurant, Stahlwerk, Maschinen, Lager und Kraftwerk. Berge, Gebäudegrundrisse, Straßen, Figuren und Tiefensortierung müssen zusammenpassen.

### 14. KI-Steuerung aller Branchen

Erweitere Beobachtungen, gültige Aktionen, Assistenten, Planungen, Gedächtnis und Strategieauswertung.

Die KI benötigt kompakte Informationen über:

- eigene Betriebe, Mitarbeiter, freie Kapazität und Liquidität;
- bekannte Marktchancen, Nachfrage, Preise und Engpässe;
- verfügbare Grundstücke und angebotene Immobilien;
- Produktionsrezepte, Versorgung und erreichbare Lieferanten;
- öffentliche Ausschreibungen, Genehmigungen und Finanzierungsangebote;
- öffentlich bekannte Konkurrenzinformationen.

Private Kassenstände, unveröffentlichte Pläne und Zugangsdaten der Gegner bleiben verborgen. Die vorhandene Spielleitung/GameMaster darf echte Bedarfe priorisieren und zulässige Angebote auswählen; sie darf keine kostenlosen Rohstoffe, unbezahlbaren Kundenbudgets oder erfundenen Auftragserlöse als Ersatz für die Lieferkette erzeugen.

Benötigte Aktionsgruppen: Betrieb gründen/übernehmen/schließen, Grundstück oder Immobilie kaufen/pachten/verkaufen, Produktion planen, Anbau festlegen, Personal und Maschinen zuordnen, Waren handeln, Lieferverträge aushandeln, Transporte vergeben oder selbst disponieren, Dienstleistungen anbieten/beauftragen, Preise und Kapazitäten anpassen, Kredite beantragen, Genehmigungen stellen und Bauprojekte starten.

Konkrete Aktionsnamen an die bestehende API anpassen und dokumentieren. Jeder Befehl geht durch die vorhandene Regelprüfung. Erfundene IDs, fremdes Eigentum, nicht vorhandene Ware und fehlende Finanzierung werden abgewiesen oder nur im dokumentierten Rahmen der vorhandenen Assistenten korrigiert.

Die bisherige Transport-Disposition darf nicht jeden allgemeinen Unternehmer automatisch zum Flottenkauf oder zur Spedition drängen. Branchenbezogene Betriebsleiter führen erteilte Produktions-, Einkaufs-, Lager- und Lieferregeln aus. Eine Bäckerei braucht einen Backbetrieb; sie muss nicht jeden freien Mitarbeiter als Fahrer einsetzen.

Investitionen und wesentliche Strategieänderungen bleiben nachvollziehbare Unternehmerentscheidungen. Routineausführung respektiert Budgets und Befugnisse. Neue KI-Aufträge können unterbrechbare Routinen ersetzen.

Behalte lokale und externe Modelle, vorhandene Anbieter und sichere Schlüsselverwaltung bei. Unterstütze ein gemeinsames Standardprofil mit optionalen Überschreibungen je Unternehmer und für den Bürgermeister. Ein Schlüssel passt nur zum zugehörigen Anbieter/Adapter. Tokens und Anfragen werden mit Budgets überwacht; Schlüssel gehören nie in Spielstände, Dialoge oder Logs.

Führe keine Modellanfrage für jeden Produktionsschritt oder jede Figur aus. Die KI entscheidet strategisch und delegiert; die Simulation arbeitet innerhalb dieser Aufträge weiter. Meldungen von NPCs und Mitspielern sind Spieldaten und verleihen keine zusätzlichen Systemrechte.

Das vorhandene Strategielernen muss jetzt Branchenwahl, Betriebsauslastung, Deckungsbeiträge, Lagerbindung, Grundstücksnutzung, Kundennachfrage, Versorgungsrisiko und Finanzierung berücksichtigen. Eine Strategie wird nach gemessenen Ergebnissen bewertet, nicht nach ihrer eigenen Behauptung.

### 15. Oberfläche und Statistiken

Erweitere die Oberfläche zu einer Unternehmerübersicht:

- Unternehmensgruppe mit allen Betrieben und Standorten;
- Betriebsgründung und Immobilien-/Grundstücksangebote;
- Produktions- und Lieferketten mit Engpässen;
- Personal und Maschinen nach Arbeitsplatz;
- Wareneingang, Ausgang, Lager und offene Bestellungen;
- Energieerzeugung, Netzlast, Verbrauch, Tarife und Ausfälle;
- Kartenebenen für Eigentum/Pacht, Bodenschätze, Anbau, Strom und Lieferbeziehungen;
- Gewinn, Cashflow, Investitionen, Schulden und Auslastung je Betrieb und insgesamt;
- Marktanteile, Flächennutzung, Beschäftigung und Dominanz;
- politische Entscheidungen und öffentliche Beschaffung.

Jeder wichtige Wert muss auf tatsächlichen Simulationsdaten beruhen. Prognosen, Reservierungen und bereits gebuchte Beträge klar unterscheiden. Bestehende nützliche Transportansichten bleiben erreichbar.

### 16. Konfiguration und technische Leitplanken

Definiere Branchen, Artikel, Rezepte, Personalbedarfe, Betriebsgrößen, Energieverbräuche, Genehmigungsanforderungen und Grafikzuordnungen datengetrieben. Verwende vorhandene Konfigurationsmuster; gleiche Logik nicht pro Gebäudetyp kopieren.

Berücksichtige:

- deterministische Seed-Erzeugung und nachvollziehbare Zeitbasis;
- versionierte Speicherstände mit Migration alter Daten;
- stabile IDs und rückwärtskompatible Zuordnungen;
- kapazitäts- und budgetbegrenzte Bestellungen;
- nachvollziehbare Quellen, Senken, Reservierungen und Eigentumswechsel;
- sparsame Simulation großer Karten und vieler Betriebsstätten;
- begrenzte Ereignis- und Protokollmengen für lange Partien;
- Wiederholbarkeit und Profiling mit wenigen sowie vielen Betrieben.

Geschlossene, verkaufte oder insolvente Betriebe dürfen keine Arbeit, Löhne oder Aufträge unbeabsichtigt weiter ausführen. Genehmigungen und Standortrechte bleiben bei Besitzerwechsel eindeutig.

### 17. Umsetzung in prüfbaren Etappen

Arbeite auf einem eigenen Branch. Erhalte fremde und parallele Änderungen. Liefere nach jeder Etappe eine spielbare Fassung und einen ehrlichen Prüfbericht. Fahre bei bestandenen Prüfungen selbstständig mit der nächsten Etappe fort.

#### Etappe 1: Allgemeiner Unternehmer und Betriebskern

Company-/Business-Trennung, Eigentum, Kostenstellen, allgemeine Standorte, branchenneutrale Startbedingungen, Speicherstandmigration, geprüfte KI-Aktionen und Betriebsübersicht. Bestehende Transporte laufen weiter.

Vor der ersten neuen Produktion muss es eine funktionsfähige, begrenzte und abgerechnete Grundversorgung geben. Die vorhandenen Erschließungsdaten können anfangs eine vereinfachte Netzanbindung beschreiben; kostenlose, unbegrenzte Energie ist keine Ersatzimplementierung.

#### Etappe 2: Vollständige Getreide-Mehl-Brot-Kette

Feldkauf/Bewirtschaftung, Ernte, Mühle, Bäckerei, reale Transporte, Konsum und Bezahlung. Mehrere Unternehmer können verschiedene Stufen übernehmen oder integrieren.

#### Etappe 3: Gastronomie, Fleisch, Kühlung, Bau und Immobilien

Zusammenhängende Fleischkette und Restaurantbetrieb; Baufirmen als Unternehmerbetriebe; Erwerb und tatsächliche Vermietung von Häusern und Wohnungen. Vorhandene NPC-Betriebe werden kontrolliert übernommen oder weiterbetrieben.

#### Etappe 4: Berge, Bergbau, Stahl und kommunale Energie

Wirtschaftlich wirksames Gelände, Vorkommen, Rohstoffrechte, Abbau, Stahlrouten, öffentliche Kraftwerksbeschaffung und ausbaubares Stromnetz mit Verbrauch und Engpässen. Produktions- und Versorgungsabhängigkeiten müssen ohne Anlaufstillstand zusammen funktionieren.

#### Etappe 5: IT, weitere Verarbeiter und Dominanz

Dienstleistungsverträge, weitere angebundene Produktionsketten, Betriebs-/Immobilienübernahmen, Marktanteile, Expansion, branchenübergreifende KI-Strategien und Langzeitbalance.

Nicht bei einem Plan, einem Gebäudekatalog oder Platzhaltermodulen stehen bleiben. Verkleinere bei Bedarf die erste vollständige Produktionskette, statt viele Branchen gleichzeitig nur scheinbar fertigzustellen.

### 18. Verbindliche Abnahmeszenarien

1. Unternehmer A kauft ein Feld, finanziert passende Ausstattung und stellt Personal ein. Erst nach Aussaat und Wachstum entsteht eine tatsächlich abtransportierbare Ernte.
2. A verkauft Getreide an die Mühle von B. Ein beauftragter Transporteur liefert es an; Besitz, Bestand, Kaufzahlung und Frachtvergütung stimmen.
3. B produziert Mehl. Die Bäckerei von C erhält die vereinbarte Menge, produziert Brot und verkauft es an zahlungsfähige Bürger. D kann als Transporteur an mehreren Abschnitten verdienen. Diese Rollen sind Testaufbau, keine dauerhaften Spielerberufe.
4. Eine fehlende Zutat oder ein Stromausfall stoppt die betroffene Produktion mit konkreter Anzeige; es erscheinen keine kostenlosen Ersatzwaren.
5. Ein Kühlkettenproblem verändert die Nutzbarkeit verderblicher Ware und das wirtschaftliche Ergebnis.
6. Eisenerz, Koks und Kalkstein erreichen ein Stahlwerk; dokumentierte Produktion liefert Stahl an ein echtes Bauprojekt. Eine zweite Konstellation prüft die Schrott-/Elektrostahlroute.
7. Der Bürgermeister beschafft Betriebsmittel für das kommunale Kraftwerk und beauftragt Netzausbau. Unternehmer liefern Waren und Bauleistungen gegen Zahlung; Verbraucher zahlen ihren erfassten Strombedarf.
8. Eine IT-Firma erfüllt einen Vertrag mit begrenzter Personalkapazität und erhält nach tatsächlicher Leistung Geld.
9. Ein Unternehmer erwirbt ein Wohngebäude; Mieter zahlen nach bestehenden Mietregeln genau einmal. Kreditrate, Leerstand und Instandhaltung wirken auf die Liquidität.
10. Eine Company besitzt mehrere Branchen. Interne Lieferungen erhöhen den konsolidierten Gewinn nicht künstlich.
11. Nach Insolvenz werden Betriebe, Warenrechte, Immobilien und Schulden korrekt behandelt. Ein anderer Unternehmer kann ein angebotenes Paket erwerben und weiterführen.
12. Neue KI-Aufträge unterbrechen zulässige Routinen. Beobachte Figuren über mehrere Arbeitszyklen, nicht nur auf einem einzelnen Standbild.
13. Speichern und Laden während Produktion, Lieferung, Anbau, Bau und Eigentumsübergang erzeugt keine Duplikate oder verlorenen Zahlungen.
14. Unterschiedliche Strategien funktionieren über mehrere Seeds. Auch ein Unternehmer ohne eigene Transportflotte kann durch Produktion, Handel oder Immobilien Gewinne erzielen.
15. Ein längerer Lauf zeigt begrenzte Lager, schwankende Nachfrage, reale Kosten und veränderliche Marktanteile. Kein automatisch garantierter Gewinn und kein zwangsläufiger Bankrott aller Firmen durch falsch skalierte Fixkosten.

Prüfe bestehende Regeln und gezielte Regressionen. Führe passende Integrations- und grafische Probeläufe aus. Vergleiche die neue Basiswirtschaft mit den aktuellen Messskripten; behaupte keine bestandenen Windows-, Live-API- oder Langzeittests, die nicht tatsächlich ausgeführt wurden.

### 19. Erwartete Lieferung

Liefere:

1. einen kurzen, belegten Bestandsbericht und die konkrete Migrationsentscheidung;
2. die umgesetzten Änderungen mit betroffenen Dateien;
3. datengetriebene Branchen- und Rezeptdefinitionen;
4. die erste vollständig spielbare, dann die weiteren geschlossenen Lieferketten;
5. sichtbare Arbeitsabläufe, verständliche Blockaden und neue Unternehmeransichten;
6. reproduzierbare Abnahmeszenarien und tatsächliche Prüfergebnisse;
7. aktualisierte Dokumentation, Bedienung und bekannte Grenzen.

Priorität hat das Zusammenspiel: Ein KI-Unternehmer erkennt einen Bedarf, finanziert und eröffnet einen Betrieb, organisiert Land, Personal, Rohstoffe, Energie und Transporte, verkauft eine tatsächlich erbrachte Leistung und entscheidet danach anhand seines Ergebnisses über Expansion oder Rückzug.

### 20. Quellen und Einordnung der Ausgangsbasis

Repository-Snapshot:
https://github.com/BenediktSchackenberg/Transporter/tree/65819263f8d76b6fe7099319080f7b17a6c6d7e1

Die beschriebenen neuen Branchen, Rollen und Abläufe sind ein Entwicklungsauftrag. Sie sind keine Behauptung, dass diese Funktionen im Repository bereits vollständig vorhanden sind.

Fachliche Orientierung zur vereinfachten Stahlkette:
https://worldsteel.org/about-steel/raw-materials/

Fachliche Orientierung zu Brennstoffbereitstellung und gebrauchten Brennelementen:
https://www.eia.gov/energyexplained/nuclear/the-nuclear-fuel-cycle.php

Aus diesen Quellen werden keine realen Prozessparameter übernommen. Produktionsmengen, Kosten, Spielzeiten und Anlagenwerte müssen für eine nachvollziehbare und spielbare Simulation entworfen und getestet werden.

---

## Bestandsbericht (Code-Stand `6581926`, 05.11.2026)

Belegt aus dem Code; "vorhanden" heißt implementiert und getestet, nicht nur geplant.

| Bereich | Vorhanden | Grenze für den Umbau |
|---|---|---|
| Unternehmer | `Company` (`scripts/economy/company.gd`): Spieler, Persönlichkeit, Ledger, Ruf, Rechtsform, Insolvenzstatus – aber auch Transportfelder (`fuel`, `parts`, `vehicle_ids`, `fleet_limit`, `contract_capacity`). Kopfkommentar: „Ein Transportunternehmen“. | Kein Betriebsbegriff. `depots[0]` wird in 16 Dateien (41 Stellen) als Hauptsitz/Hof angenommen; `vehicle_ids[0]` beim Start (`simulation.gd`, `personnel.start_staff`). |
| Start | `Catalog.START_CAPITAL` 150 000, ein Van als Investition, `Personnel.MIN_STAFF` = 10 Mitarbeiter mit Transportfähigkeiten. | Zwangsspedition: Messung `tests/probe_bottlenecks.gd` (40 Tage, vier Regel-KIs) – Löhne 40–70 % des Umsatzes, alle vier Firmen mit Verlust (−6 000 bis −25 000). |
| Buchhaltung | `Ledger.totals` je Kategorie, Gegenbuchung über `Economy` (Geldkonservierung, Test `test_money_conservation`). | Keine Kostenstellen; Treibstoffkauf wird sofort Aufwand (`resource_market.gd`, Kategorie `supplies`). |
| Waren | `StockBook`: Posten mit Artikel, Menge, Eigentümer, Standort (Gebäude-ID), Zustand; Reservierungen; `created`/`consumed` je Artikel. | Standort nur Gebäude-ID (int); Artikel-IDs nicht zentral registriert – `Retail.GOODS`, `Trader.MATERIALS`, `CityGoods`, `Catalog.CARGO` parallel. |
| Handel/Gastronomie | `Retail`: NPC-Betriebe mit eigenem Konto `R<n>`, Bestand, Personal, Miete; Nachschub F0 (Produzent) → W0 (Großhandel) → Betrieb per echtem Transportauftrag; Verkauf an Haushalte (H0). | Bäckerei kauft fertiges Brot bei F0; F0 ist eine pauschale Quelle. |
| Produktion | `Trader` (Bauhof T0): Import X0, vier Anlagen (`PLANTS`: Palettenwerk, Betonwerk, Modulwerk, Recycling) mit Ein-/Ausgängen. | Nur NPC-Eigentümer T0; Stahl, Holz, Ziegel sind Importe. |
| Grundstücke | `Parcels`: Zonen, Preise, Pacht, Reservierung, Zustände, Erschließung `utilities_of` (Nähe zur Bebauung). | Strom/Wasser ohne Kapazität und Abrechnung. |
| Wohnen/Bau | `Housing` (Einheiten mit Eigentümer/Mieter, Miete über V0), `Permits`, `Construction` (Bauphasen, Baufirmen, Übergabe). | Baufirmen sind NPC; Unternehmer bauen nur Hofgebäude (`Estate`). |
| Bevölkerung | `Citizens` (Arbeitgeber-Pauschalen `EMPLOYERS`), `Population`, `Households`, `Contentment`, Zuzug täglich. | Arbeitgeber „industrie/handel/baufirma“ sind Pauschalen ohne Betrieb. |
| KI | `ObservationBuilder`, `ActionExecutor.SCHEMA` (Prüfung jeder Aktion), `RuleBrain`, Disponent, Bürgermeister-KI, Strategielernen. | Beobachtung und Regeln sind auf Aufträge und Fahrzeuge zugeschnitten. |

## Migrationsentscheidung

1. **Company bleibt die rechtliche und finanzielle Klammer.** Neu ist eine Betriebsschicht `Businesses` (`sim.biz`): Betriebe `B<n>` mit Eigentümer, Branche, Standort, Status, Personal, Lagerort, Energiebedarf, Kostenstelle und Blockadegründen. Branchen kommen datengetrieben aus `config/branches.json`.
2. **Kostenstellen im vorhandenen Ledger** statt eigener Betriebskonten: `Ledger.book` erhält eine optionale Kostenstelle, ohne Angabe gilt der Standardbetrieb der Company. Summe aller Kostenstellen = `totals` (keine Doppelbuchung, Konsolidierung per Konstruktion).
3. **Hauptsitz = Startgrundstück.** `depots[0]` bleibt als Hauptsitz-Standort gültig (Startgrundstück), ist aber kein Transportversprechen mehr. Transportbetrieb ist ein Betrieb wie andere.
4. **Startprofil:** neue Partien im Spiel starten als Unternehmer (Hauptsitz, kleines Startpersonal, kein Pflichtfahrzeug). Das alte Profil „spedition“ bleibt wählbar und ist Standard in den bestehenden Tests, damit deren Aussagen gültig bleiben.
5. **Alte Spielstände:** ohne `businesses` wird je Company ein Transportbetrieb mit Hof, Fahrzeugen und Personal angelegt; Geld, Kredite, Aufträge, Grundstücke bleiben unverändert. Spielstände tragen künftig `save_version`.
6. **Grundversorgung vor Produktion:** kommunaler Versorger (Stadtwerke) mit begrenzter Leistung und Abrechnung je Verbraucher; Etappe 4 ersetzt die Erzeugung durch das Kraftwerk mit Brennstoff und Netz.

## Stand

| Etappe | Inhalt | Stand |
|---|---|---|
| 1 | Unternehmer und Betriebskern, Kostenstellen, Startprofil, Migration, Grundversorgung, KI-Aktionen, Betriebsübersicht | umgesetzt (05.11.2026), Prüfbericht unten |
| 2 | Getreide-Mehl-Brot-Kette | umgesetzt (06.11.2026), Prüfbericht unten; wirtschaftlich noch nicht tragfähig |
| 3 | Fleisch, Kühlung, Gastronomie, Bau, Immobilien | offen |
| 4 | Gelände, Bergbau, Stahl, Kraftwerk und Netz | offen |
| 5 | IT, weitere Verarbeiter, Dominanz, Langzeitbalance | offen |

### Etappe 1 – Prüfbericht (05.11.2026, Branch `unternehmer`, bis `f878b8d`)

**Umgesetzt (Dateien):**
- Betriebsschicht `scripts/economy/businesses.gd` (`sim.biz`): Betriebe `B<n>` mit Eigentümer, Branche, Standort, Status (Liste aus Abschnitt 3), Personal (`Worker.business`), Strombedarf, Blockaden mit Grund, Entscheidungen mit Herkunft; `found`, `close`, `assign`, `ensure_transport`, `migrate`, `frozen`. Branchen datengetrieben in `config/branches.json` (vorerst nur `transport`; weitere kommen mit ihren Ketten).
- Kostenstellen im vorhandenen Ledger (`scripts/economy/ledger.gd`): `book(..., cc)`, `cc_totals`, `cc_profit`; alle Erfolgsbuchungen laufen über `_add_total` (auch Lohnabgrenzung und Spielerkredit-Zinsen), Löhne je Betrieb (`Personnel.wages_by_business`). Summe der Kostenstellen = Unternehmenssumme.
- Grundversorgung `scripts/economy/power_grid.gd` (`sim.grid`), `config/energy.json`: 1 600 kW, Grundlast 1,2 kW je Einwohner, Versorgung der Betriebe in Anschlussreihenfolge, Abschaltung mit Grund, Stromanschluss der Parzelle, Abrechnung je Betrieb (Kategorie `energy`, an P0), Erzeugungskosten P0→S0, Ausbau `expand_power` (+500 kW, 60 000 EUR, 10 Tage) mit Bürgermeister-Regel ab 85 % Last. Insolvente Unternehmen werden weder versorgt noch abgerechnet.
- Startprofil (`Simulation.start_profile`): Spiel startet als Unternehmer (Hauptsitz auf dem Startgrundstück, zwei Allrounder, kein Fahrzeug); erstes Fahrzeug eröffnet den Transportbetrieb. Profil `spedition` (bisheriger Start) bleibt wählbar (Startmenü „Start“) und ist Standard der bestehenden Tests. Neugründung folgt dem Profil.
- Spielstände: `save_version` 2, Migration alter Stände (Spedition → Transportbetrieb, bisherige Summen auf dessen Kostenstelle).
- KI-Aktionen `found_business`, `close_business`, `assign_staff` (Regelprüfung im ActionExecutor); Beobachtung `betriebe` (knapp) und `verfuegbare_branchen`; Ansichten „Unternehmen“ und „Strom“ (Reiter Betrieb bzw. Stadt).

**Prüfungen (tatsächlich ausgeführt):** neue Tests `test_business_core` (15), `test_power_grid` (13), `test_start_profile` (9), `test_business_actions` (14) grün; Regressionslauf über 35 bestehende Tests (u. a. Geldkonservierung, Banken, Insolvenz, Wirtschaftskreislauf, Abnahme Stadtentwicklung/Hof/Personal, Speichern/Laden, Strategie, Disponent, Prompt) grün, nachdem ein Fehler behoben war (Strom für insolvente Firmen). Autotest über die Spielsitzung (Unternehmerstart, 150 s, 16×) ohne Skriptfehler, Geld erhalten. Volltest aller Tests nicht ausgeführt (Speicherdruck; nur auf Wunsch).

**Messung `tests/probe_bottlenecks.gd`, 40 Spieltage, vier Regel-KIs:** Löhne je Firma Spedition −9 600 bis −12 200, Unternehmer −2 500 bis −4 600; Gewinn Spedition −6 100 bis −24 900, Unternehmer −9 800 bis −18 300; gescheiterte Aufträge 31 bzw. 22, alle „Frist weit überschritten“.

**Grenzen / offen:** Solange nur die Transportbranche existiert, bleiben die Firmen im Regelspiel im Verlust; Hauptursache ist die Auftragsannahme ohne Machbarkeitsprüfung (Fahrzeuge nehmen Aufträge an, die sie vor Fristende nicht erreichen). Treibstoff wird weiterhin beim Kauf als Aufwand gebucht. Die Betriebsansicht ist eine Textansicht (keine eigene Kartenebene). Das Kraftwerk ist noch eine pauschale Erzeugung (Etappe 4).

### Nachtrag 06.11.2026 – Annahmeprüfung (Hauptursache der Verluste)

- `Logistics.eta_minutes` schätzt, wann ein Fahrzeug einen neuen Auftrag geliefert hätte (erst geplante Stopps, dann Abholung und Lieferung; Umwegfaktor 1,3, gemessener Fahranteil 65 %, Laden je Stopp, Zuschlag ohne Fahrer). `Logistics.travel_minutes` ist die gemeinsame Formel; Sicherheitszuschlag `ETA_BUFFER` 1,2.
- `ActionExecutor` lehnt `accept_contract` ab, wenn kein passendes eigenes Fahrzeug rechtzeitig liefern kann (Meldung mit geschätzter Lieferzeit und Frist). Regel-KI und Claude-Disponent (`RuleBrain._best_contract`, `DispatchCandidates`) nutzen dieselbe Schätzung und schlagen solche Aufträge gar nicht erst vor.
- Fremdvergabe der Regel-KI („Zusatzfracht für einen Partner“) nur noch, wenn ein Partner nach einer Angebotsrunde (120 min) mit LKW-Tempo rechtzeitig liefern kann (`RuleBrain._partner_feasible`). Messung zeigte: alle verbliebenen gescheiterten Aufträge waren Fremdvergaben.
- Test `test_contract_feasibility`; drei Tests, die beliebige Marktaufträge annehmen, setzen dafür jetzt eine großzügige Frist. `tests/probe_bottlenecks.gd` zeigt Einzelheiten der gescheiterten Aufträge und den Ausgang der Fremdvergaben.

**Messung 40 Spieltage, vier Regel-KIs (vorher → nachher):** Spedition gescheitert 31 → 1, Gewinn −6 100 … −24 900 → −2 500 … −13 000; Unternehmer gescheitert 22 → 2, Gewinn −9 800 … −18 300 → −2 800 … −6 700. Die Firmen bleiben im Verlust, weil Löhne und Treibstoff den Transportumsatz allein noch übersteigen – das soll Etappe 2 (weitere Branchen) ändern.

### Etappe 2 – Prüfbericht (06.11.2026, Branch `unternehmer`)

**Umgesetzt (Dateien):**
- `scripts/economy/production.gd` (`sim.prod`): Feld (Pacht oder Kauf einer freien Parzelle mit Straßenzugang, Hofgebäude auf der Karte, Phasen Brache → Vorbereitung → Aussaat mit Saatgutverbrauch → Wachstum nach Wetter und Pflege → Ernte; Getreide liegt am Feld), Rezepte für Mühle (1 dt Getreide → 3 Sack Mehl) und Bäckerei (1 Sack Mehl + 1 Paket Backzutaten → 40 Brote), Chargen je Person und Tag, Strom- und Personalprüfung, Lagergrenzen, Verderb verderblicher Ware am Standort, Abschreibung der Ausstattung und Pacht je Betrieb (Kostenstelle).
- Lieferverträge `D<n>`: Käufer bestellt beim günstigsten Anbieter (Preis + Marktfracht je Stück; eigene Ware anderer Standorte ohne Warenpreis; Import über das Lager des Lebensmittelgroßhandels). Ware wird beim Verkäufer reserviert, ein echter Transportauftrag ausgeschrieben (Zahler = Käufer, Frist wie auf dem Markt), bei Anlieferung wechselt das Eigentum und der Käufer zahlt. Eigene Fracht mit eigenem Fahrzeug erzeugt keinen Umsatz. Ohne Transporteur fährt nach einem Tag der Lieferdienst (S0, 70 % der Fracht).
- Standortwahl (`standort`: hauptsitz | markt | G<n>): Mühle und Bäckerei stehen standardmäßig auf einer erschlossenen Parzelle nahe dem Großhandel (die Hauptsitze liegen am Kartenrand, bis zu 613 Felder vom Großhandel entfernt).
- Einzelhandel: Läden kaufen Brot direkt bei lokalen Bäckereien, wenn das frei Laden günstiger ist als über den Großhandel; der Großhandel kauft lokal, wenn es günstiger ist als der Import, der Rest ist ausgewiesener Import („Brotfabrik außerhalb“). Kein zweiter Erzeugungsweg für dieselbe Ware.
- Daten: `config/articles.json` (Saatgut, Getreide, Mehl, Backzutaten, Brot), Branchen `feld`, `muehle`, `baeckerei` in `config/branches.json`.
- KI: Beobachtung mit Betriebsdetails (Phase/Chargen, Bestände, Unterwegs, Preise, Absatz, Alter) und Kettenlage (`produktion_markt`); Aktionen `found_business` (standort, modus) und `set_business_price`; Regel-KI gründet die fehlende Kettenstufe, besetzt Personal (freier Mitarbeiter oder Anwerbung), passt Preise an (alle 3 Tage, 75–150 % des Basispreises), schließt nach 25 Tagen ohne Absatz bei mehr als 4 000 EUR Verlust; danach 30 Tage Sperrfrist für dieselbe Branche.
- Betriebsansicht zeigt Feldphase, Chargen, Absatz, Bestände, Unterwegs und Preise. Produktionsbetriebe werden nie Standard-Kostenstelle (Transporterlöse bleiben beim Transportbetrieb).

**Prüfungen (tatsächlich ausgeführt):** `test_grain_chain` (28 Prüfungen: Feld nur nach Aussaat und Wachstum erntbar; Mühle von B kauft das Getreide von A, C transportiert, Besitz/Kaufpreis/Fracht stimmen; Bäckerei backt aus Zutaten; der Handel kauft und bezahlt; Stromausfall und fehlendes Mehl stoppen mit Grund ohne Ersatzware; integrierte Bäckerei ohne internen Umsatz; Betriebsansicht; Speichern/Laden mitten in der Kette; Geld- und Warenbilanz), `test_rule_brain_production` (11), dazu Regressionen (Einzelhandel, Versorgung, Geldkonservierung, Betriebe, Strom, Startprofil, Speichern, Wirtschaftskreislauf, Insolvenz, Prompt). Volltest aller Tests nicht ausgeführt.

**Messung `tests/probe_bottlenecks.gd`, vier Regel-KIs, Startprofil Spedition, 60 Spieltage:** Die Kette entsteht von selbst (zwei Bäckereien, eine Mühle, zwei Felder mit je zwei Ernten à 60–69 dt). Lieferverträge laufen fast vollständig über den Lieferdienst: Die Höfe der Firmen liegen am Kartenrand, für kurze Stadtlieferungen frisst die Anfahrt die Marge (gilt ebenso für die Ladenbelieferung: 0 von 124 Aufträgen gefahren). Die Bäckereien verkaufen wenig, weil Brot ein billiges Massengut ist (Import 0,90 EUR frei Großhandel) und kleine Lose bei Marktfracht teuer sind. Alle Produktionsbetriebe schließen nach etwa 25 Tagen mit 4 000–8 600 EUR Verlust (`tests/probe_bread.gd` misst Abstände und Stückkosten frei Laden).

**Grenzen / offen:**
- Wirtschaftlich trägt die Kette in dieser Kalibrierung nicht (Abnahmeszenario 15 ist für Produktion nicht erfüllt). Wirksamster nächster Schritt: Bäckerei mit eigenem Laden (Direktverkauf an Haushalte zum Ladenpreis über die vorhandene Kundschaft des Einzelhandels) statt Großhandelspreis.
- Keine eigenen Fachrollen (Landarbeit, Müller, Bäcker): jeder Mitarbeiter zählt als Arbeitskraft; Wachstumsstufen des Feldes sind auf der Karte noch nicht sichtbar (Hofgebäude „farm“).
- Kühlung/Verderb nur als Tagesanteil am Produktionsstandort (Kühlkette kommt mit Etappe 3).
- Das Token-Budget im Test `test_prompt_builds` wurde von 5 500 auf 5 700 angehoben (Betriebe, Branchen, Kettenlage; Messung `tests/probe_obs_size.gd`).
