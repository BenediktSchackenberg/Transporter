class_name Mayor
extends RefCounted
## Buergermeister-Rolle (Auftrag 7, Etappe 3). Die Rolle hat eine eigene Beobachtung (`indicators`), eigene Aktionen (`execute`),
## ein eigenes Gedaechtnis und Entscheidungsprotokoll. Ob ein Sprachmodell (MayorAgent) oder die Regeln (MayorBrain) entscheiden,
## aendert nichts: die Engine prueft Zustaendigkeit, Budget, Flaechenverfuegbarkeit und Ratsbeschluss. Es gibt keinen Welteditor.

const SCHEMA := {
	"wait": {"params": {}, "desc": "Nichts tun."},
	"kommunal_bauen": {"params": {"typ": "string", "reason": "string", "grundstueck": "string?"},
		"desc": "Kommunale Einrichtung neu bauen. Für Wasserwerk WW-01, Hochbehälter WT-01 oder Kläranlage KA-01 kannst du ein geprüftes grundstueck aus obs.versorgungsanlagen_standorte wählen. Ratsbeschluss, Ausschreibung und Baufirma; Kosten und Bedarf siehe obs.kommunale_dienste."},
	"kommunal_fahrzeug": {"params": {"einrichtung": "string", "fahrzeug": "string", "reason": "string"},
		"desc": "Fahrzeug für eine Einrichtung kaufen (einrichtung = ID M<n>, fahrzeug HLF 20|DLK 23|RTW|NEF|Kipper|Streuwagen|Linienbus|Wertstoffwagen)."},
	"infra_ausbau": {"params": {"anlage": "string", "reason": "string"},
		"desc": "Nur bei echtem Kapazitätsengpass eine bestehende Anlage vergrößern: wasserwerk | hochbehaelter | klaeranlage. Kein neuer Standort und keine größere Druckzone; dafür kommunal_bauen beziehungsweise versorgungsleitung_bauen wählen. gleis repariert die Bahnlinie."},
	"stromtrasse_bauen": {"params": {"option": "string", "reason": "string"},
		"desc": "Eine geprüfte Hochspannungstrasse aus obs.stromtrassen wählen. Die KI bestimmt Trasse und Standort des Umspannwerks; Material, Baufirma, Bauzeit und Kosten sind real. Nach Fertigstellung erhält die Stadt Kraftwerksstrom. Ein zweiter Weg schützt vor Ausfällen."},
	"versorgungsleitung_bauen": {"params": {"option": "string", "reason": "string"},
		"desc": "Einen geprüften Frischwasser- oder Abwasserleitungsabschnitt aus obs.versorgungsleitungen wählen. Er folgt verbundenen Straßen, braucht Material und Baufirma und versorgt Gebäude erst nach Fertigstellung."},
	"stromstoerung_priorisieren": {"params": {"trasse": "string", "reason": "string"},
		"desc": "Bei einer unterbrochenen Trasse aus obs.strom.netz.reparaturen zusätzliche Netzkräfte bezahlen; der Trupp fährt weiterhin zur Schadstelle und repariert dort schneller."},
	"kraftwerk_notfall": {"params": {"massnahme": "string", "reason": "string"},
		"desc": "Nach einem Angriff auf das Kernkraftwerk aus obs.strom.kraftwerk.notfall handeln: stabilisieren (45 000 EUR, Reparatur und kürzere Sperre) oder bei Katastrophe evakuieren (20 000 EUR, Wesen verlassen die Sperrzone). Jede Maßnahme nur einmal; Strom und Wasser können ausfallen."},
	"kommunal_schliessen": {"params": {"einrichtung": "string", "reason": "string"}, "desc": "Kommunale Einrichtung schließen (Personal frei, keine Kosten mehr)."},
	"fahrzeug_entwerfen": {"params": {"klasse": "string", "name": "string", "farbe": "string", "akzent": "string?", "form": "string?", "nutzlast": "int?",
		"leistung": "string?", "qualitaet": "string?", "kuehlung": "bool?", "preis": "number?", "reason": "string"},
		"desc": "Neues Modell im städtischen Fahrzeugwerk entwerfen (nur die Stadt mit Werk, obs.fahrzeugwerk). klasse pkw|transporter|lkw|sattelzug; farbe/akzent rot|blau|gruen|gelb|weiss|schwarz|silber|orange|tuerkis|violett|braun|grau|creme oder Hex; form kantig|rund|keil; nutzlast je Klasse (pkw 4-7 Sitze, transporter 8-24, lkw 28-56, sattelzug 60-100); leistung sparsam|ausgewogen|kraftvoll; qualitaet einfach|solide|premium; kuehlung nur transporter/lkw; preis optional (zwischen Selbstkosten und 2,2-fach). Kostet 15 000 EUR Entwicklung; danach baut das Band, Verkäufer bieten es an."},
	"regionalrat_antrag": {"params": {"art": "string", "partner": "int?", "reason": "string"},
		"desc": "Antrag für die nächste Sitzung des Regionalrats: art verbindung (mit partner = Stadt-Nr.)|kh_ausbau|drehleiter|zweckverband|bahn_takt (weiterer Triebwagen, Land 75 %)|zweites_gleis (Abschnitt mit der meisten Wartezeit, Land 75 %; siehe obs.bahn.ausbau). Mehrheit 3 von 4, Eigentumsfragen einstimmig; Kraftwerksanteile bleiben 25/25/25/25."},
	"propose_project": {"params": {"project": "string", "category": "string", "reason": "string", "priority": "int?", "desiredDistrict": "string?",
		"features": "array?", "size": "string?"},
		"desc": "Eigene Bauidee für die Stadt (Auftrag 19): z. B. Spielplatz, Stadtpark, Marktplatz, Bolzplatz, Stadion, Kindergarten, eine Statue von dir. category recreation|familie|gruen|markt|sport|prestige|bildung; size klein|mittel|groß. Die Engine wählt Bauvorlage, Standort und Material (obs.stadtentwicklung.bauvorlagen); entschieden und beschafft wird beim nächsten Besuch im Großlager."},
	"set_vision": {"params": {"vision": "string", "reason": "string"},
		"desc": "Langfristiges Ziel der Stadtentwicklung festlegen (gespeichert, prägt die Auswahl der Bauprojekte)."},
	"remember": {"params": {"inhalt": "string"}, "desc": "Eine Erfahrung oder Notiz im Gedächtnis des Amtes festhalten."},
	"designate_quarter": {"params": {"name": "string?", "parcel_ids": "array", "zone": "string?", "reason": "string"},
		"desc": "Neues Quartier vorschlagen: städtische, freie Grundstücke (siehe entwicklungsvorschlaege) werden einer Zone zugewiesen. Braucht Ratsbeschluss; danach zur Entwicklung vorgesehen."},
	"offer_parcels": {"params": {"parcel_ids": "array", "price_factor": "number?", "reason": "string"},
		"desc": "Städtische Grundstücke aus beschlossenen Quartieren zur Vergabe freigeben (Preisfaktor 0,7–1,3)."},
	"viertel_erschliessen": {"params": {"viertel": "string", "reason": "string"},
		"desc": "Ein Viertel des Stadtplans (V1, V2, … siehe stadtplan.viertel) in einem Abschnitt erschließen: die freien städtischen Grundstücke dort bekommen die Zone des Viertels, Straße und Anschlüsse werden als Projekt beauftragt (Kosten aus dem Haushalt, Material, Baufirma). Danach entstehen dort Häuser, Läden oder städtische Bauten."},
	"stadtteil_planen": {"params": {"mitte": "array", "zone": "string", "name": "string", "reason": "string"},
		"desc": "Einen neuen Stadtteil selbst entwerfen: mitte [x,y] an einem beliebigen geeigneten Standort der eigenen Stadt; stadtplan_erweiterung zeigt nur Vorschläge. zone wohnen|mischgebiet|gewerbe|industrie|gruen, eigener Name und Grund. Die Engine prüft Fläche und Straßenanschluss."},
	"quartier_entwurf_waehlen": {"params": {"viertel": "string", "entwurf": "string", "reason": "string"},
		"desc": "Für ein eigenes Viertel einen der geprüften Entwürfe wählen. Die Wahl bestimmt Straßen, Platz und Quartierscharakter. Alternativ mit quartier_trasse_planen eine eigene Straßenführung zeichnen."},
	"quartier_trasse_planen": {"params": {"viertel": "string", "punkte": "array", "reason": "string"},
		"desc": "Eigene Straßenführung für ein noch ungeplantes Viertel: 2 bis 8 Wegpunkte [x,y] im Viertel wählen. Die Engine verbindet sie nur über freien, bebaubaren Boden mit dem Rathausnetz und meldet Kosten/Blockaden; danach viertel_erschliessen."},
	"grosslager_anschluss_bauen": {"params": {"reason": "string"},
		"desc": "Die eigene Wildnis-Stadt auf Wunsch ans Großlager-Straßennetz anschließen. Die Engine berechnet eine befahrbare Trasse um Wasser, Berge und fremde Grundstücke; Material, Bautrupp und Kosten gelten wie bei jedem Straßenprojekt."},
	"plan_infrastructure": {"params": {"parcel_ids": "array", "parts": "array?", "reason": "string"},
		"desc": "Erschließung (strasse, strom, wasser, abwasser; Standard: alle fehlenden) für städtische Grundstücke planen. Kosten werden aus dem Haushalt reserviert; über 30 000 EUR Ratsbeschluss."},
	"prioritize_road": {"params": {"corridor_id": "string", "priority": "int", "reason": "string"},
		"desc": "Straßenprojekt auf einem Korridor (Grundstück der Zone korridor) mit Priorität 1 (hoch) bis 5 anlegen oder umpriorisieren."},
	"tender": {"params": {"project_id": "string", "reason": "string"}, "desc": "Beschlossenes Projekt öffentlich ausschreiben (Baufirmen bieten)."},
	"approve_procurement": {"params": {"order_id": "string", "reason": "string"},
		"desc": "Beschaffungsvorschlag des Stadtlagers (obs.stadtlager.vorschlaege) genehmigen: Budget wird reserviert, bester Anbieter bestellt, Transportauftrag ausgeschrieben."},
	"expand_depot": {"params": {"kind": "string", "reason": "string"},
		"desc": "Zentrallager ausbauen: kind ramp (Entladerampe, 18 000 EUR), staff (Lagerkraft einstellen) oder forklift (Gabelstapler). Sinnvoll bei wartenden Lkw oder Rückstau im Wareneingang (obs.stadtlager)."},
	"improve_traffic": {"params": {"kind": "string", "x": "int", "y": "int", "reason": "string"},
		"desc": "Verkehrsmaßnahme auf einem wiederkehrenden Engpass (obs.verkehr.engpaesse mit wiederkehrend=true): kind ampel (Kreuzung, 12 000 EUR, 2 Tage), ladezone (Strecke neben einem Gebäude, 8 000 EUR, 3 Tage, Haltebucht für Lieferfahrzeuge, +1 Kapazität) oder ausbau (Straßenabschnitt, 40 000 EUR, 6 Tage, währenddessen eine Spur weniger). Ein einzelner Stau rechtfertigt keinen Ausbau."},
	"reject_procurement": {"params": {"order_id": "string", "reason": "string"}, "desc": "Beschaffungsvorschlag ablehnen (Begründung nötig, z. B. Budget oder kein Bedarf)."},
	"assess_financing": {"params": {"project_id": "string?"}, "desc": "Finanzierungsbedarf und Status eines Projekts bewerten (nur Auskunft); ohne project_id: Kasse und alle offenen Projekte."},
	"request_credit": {"params": {"betrag": "number", "reason": "string"},
		"desc": "Begrenzten Infrastrukturkredit bei fehlendem Budget fuer unbewohnbare Wohnhaeuser aufnehmen. Betrag und Schuldengrenze aus obs.kreditangebot; Zinsen und Tilgung werden monatlich aus Ueberschuessen bezahlt."},
	"set_property_tax": {"params": {"satz_prozent": "number", "reason": "string"},
		"desc": "Grundsteuersatz in Prozent des Immobilienwerts je Jahr festlegen (0,2–3,0; je Beschluss höchstens ±0,5 Punkte). Alle Bürger-Eigentümer zahlen ihn an die Stadtkasse; siehe obs.bevoelkerungsmodell."},
	"hire_staff": {"params": {"abteilung": "string", "anzahl": "int", "reason": "string"},
		"desc": "Im Rathaus Stellen ausschreiben (abteilung verwaltung | bauamt | strassen | pruefdienst; 1-5 je Aktion, höchstens 120 insgesamt). Besetzung zum Monatsende, Gehälter zahlt die Stadtkasse; nur wenn sie sechs Monatsgehälter der neuen Kräfte deckt. Siehe obs.rathaus."},
	"dismiss_staff": {"params": {"abteilung": "string", "anzahl": "int", "reason": "string"},
		"desc": "Im Rathaus Stellen streichen (mindestens eine Kraft je Abteilung bleibt). Wirkt zum Monatsende."},
	"set_city_freight": {"params": {"vergabe": "string", "firma": "int?", "tage": "int?", "preisfaktor": "number?", "eilig": "bool?", "reason": "string"},
		"desc": "Transportaufträge des Stadtlagers steuern: vergabe ausschreibung (offen für alle) | rahmenvertrag (firma erhält für tage 5–60 je Auftrag einen Tag Vorrecht) | direktvergabe (nur der nächste Auftrag). preisfaktor 0,8–1,3 auf die Vergütung, eilig = +15 % und kürzere Frist. Grenzen: Ruf mindestens 40, höchstens 50 % der Vergaben einer Firma in 30 Tagen. Siehe obs.stadtlager.transportpool."},
	"repair_road": {"params": {"abschnitt": "string", "ausfuehrung": "string", "reason": "string"},
		"desc": "Straßenabschnitt instand setzen (abschnitt aus obs.strassen.schlechteste, z. B. A12_7). ausfuehrung eigen = Straßenmeisterei (1 500 EUR, 3 Tage, je 4 Kräfte ein Bautrupp) | firma = Baufirma (8 000 EUR, 2 Tage, höchstens 2 gleichzeitig). Unter 50 % Zustand fahren Fahrzeuge langsamer und haben mehr Pannen; während der Arbeit ist eine Spur gesperrt."},
	"set_public_staff": {"params": {"bereich": "string", "aenderung": "int", "reason": "string"},
		"desc": "Stellen bei bereich polizei (Aufklärung von Diebstählen) oder gesundheit (Ärzte und Pflege, Behandlungskapazität) ändern: aenderung -5..+5, mindestens 2 Stellen, höchstens das Dreifache des Startbestands. Mehr Stellen nur, wenn die verfügbare Stadtkasse sechs Monatsgehälter deckt; besetzt wird zum Monatsende. Siehe obs.sicherheit_gesundheit."},
	"support_training": {"params": {"foerderung_prozent": "int", "reason": "string"},
		"desc": "Weiterbildung Arbeitsloser fördern (0–100 %): erhöht die Zahl der Kursbeginne bis auf das Dreifache; je Kursbeginn zahlt die Stadt 400 EUR × Förderanteil an den Bildungsträger. Siehe obs.bevoelkerungsmodell."},
	"city_marketing": {"params": {"budget": "number", "reason": "string"},
		"desc": "Stadtmarketing (5 000–30 000 EUR, einmalig): mehr Zuzug von Haushalten für 3 Monate (+1 % je 1 000 EUR). Nur sinnvoll bei freiem Wohnraum und offenen Stellen."},
	"decide_yard_permit": {"params": {"antrag": "string", "decision": "string", "reason": "string"},
		"desc": "Hof-Bauantrag einer Firma (obs.hof_bauantraege, Kran und Umschlaghalle) entscheiden: genehmigen | auflagen (+5 % der Baukosten, z. B. Lärmschutz) | ablehnen (nur mit Begründung). Ohne Entscheidung genehmigt das Amt nach 2 Tagen."},
	"order_inspection": {"params": {"firma": "int", "art": "string", "reason": "string"},
		"desc": "Prüfdienst zu einer Firma schicken (art lohnsteuer | arbeitssicherheit | fahrzeuge). Kapazität je Monat = 2 je Prüfer, Sperrfrist 10 Tage je Firma; Befunde kosten die Firma Bußgeld (an die Stadtkasse), eine Prüfung ohne Befund kostet Zustimmung. Siehe obs.pruefungen."},
	"mediate_rivalry": {"params": {"firma_a": "int", "firma_b": "int", "tage": "int?", "reason": "string"},
		"desc": "Zwischen zwei zerstrittenen Firmen schlichten (obs.rivalitaet.paare, ab Spannung 30): Spannung −25 und Stillhalteabkommen für 3–14 Tage (Standard 7). Wer es bricht (Abwerben, Anzeige, Blockade, Sabotage gegen den anderen), zahlt 3000 EUR und verliert 10 Ruf. Unruhe zwischen Firmen kostet Zustimmung."},
	"expand_power": {"params": {"reason": "string"},
		"desc": "Stromnetz der Stadtwerke ausbauen: +500 kW Leistung nach 10 Tagen für 60 000 EUR. Sinnvoll, wenn obs.strom.auslastung über 0,85 liegt oder Betriebe abgeschaltet sind."},
	"expand_harbor": {"params": {"reason": "string"},
		"desc": "Hafen eine Stufe ausbauen (obs.hafen.ausbau: Ziel, Ladung je Schiff, Kosten, Tage): Stadtprojekt, eine Baufirma baut mit Material aus dem Stadtlager. Sinnvoll, wenn obs.hafen.rueckstau_schiffsladungen über 1 liegt (Einfuhren warten auf mehrere Schiffe)."},
	"build_harbor": {"params": {"reason": "string"}, "desc": "Einmalig einen Hafen am echten Meer mit Zufahrt bauen; Standort aus obs.verkehrsstandorte.hafen. Ein See ist kein Hafenstandort."},
	"expand_airport": {"params": {"reason": "string"},
		"desc": "Flughafen eine Stufe ausbauen (obs.flughafen.ausbau: Ziel, Plaetze, Fracht je Flug, Kosten, Tage): Stadtprojekt, eine Baufirma baut mit Material aus dem Stadtlager. Danach mehr Passagiere und mehr Frachtplatz je Flug, hoechere Abfertigungsgebuhr. Sinnvoll, wenn obs.flughafen.rueckstau_fluege ueber 1 liegt (Luftfracht wartet auf mehrere Fluege)."},
	"build_airport": {"params": {"reason": "string"}, "desc": "Einmalig einen Flughafen auf freiem ebenem Land mit Zufahrt bauen; Standort aus obs.verkehrsstandorte.flughafen."},
	"plan_airport": {"params": {"strategie": "string", "reason": "string"}, "desc": "Flughafen am geprueften Standort finanzieren: strategie sparen oder kredit. Der Plan reserviert wachsende freie Mittel; ein Kredit ist nur im Rahmen des Kreditangebots moeglich. Die KI waehlt den Zeitpunkt des Baus selbst."},
	"build_station": {"params": {"reason": "string"}, "desc": "Einmalig einen Bahnhof an der gegruendeten Stadt bauen. Nach dem zweiten Bahnhof verbindet die Regionalbahn die Staedte mit Personen- und Gueterzug."},
	"warn_company": {"params": {"firma": "int", "reason": "string"},
		"desc": "Firma öffentlich verwarnen (nur wenn sie in den letzten 7 Tagen eskaliert hat, siehe obs.rivalitaet.verursacher): Ruf −2, für 10 Tage kostet jede weitere Eskalation zusätzlich Ruf."},
	"build_bridge": {"params": {"grundstueck": "string", "bruecke": "string?", "vergabe": "string?", "firma": "int?", "reason": "string"},
		"desc": "Die Stadt ausbauen: städtisches Grundstück jenseits von Fluss oder See erschließen (obs.erschliessung.vorschlaege), Weg und Brücke ganz aus der Stadtkasse. bruecke holz | stein | stahlbeton (muss Spannweite und Last schaffen, siehe brueckenarten; Standard die günstigste passende). vergabe ausschreibung (Standard; ortsansässige Unternehmer-Baufirmen bevorzugt) | direkt mit firma = Firmen-ID einer Unternehmer-Baufirma (obs.erschliessung.baufirmen), damit die Firma den Auftrag bekommt. Bis zur Abnahme gesperrt."},
	"build_tunnel": {"params": {"von": "array", "nach": "array", "reason": "string"},
		"desc": "Strassentunnel durch einen Berg bauen: von und nach sind [x,y] der beiden Strassenportale (obs.tunnel.vorschlaege). Die Stadt finanziert Material und Baufirma; der Fels bleibt bis zur Abnahme unpassierbar."},
	"decide_tunnel": {"params": {"antrag": "string", "decision": "string", "reason": "string"},
		"desc": "Tunnelantrag einer Firma (obs.tunnel.antraege) genehmigen oder ablehnen. Die Firma zahlt 25 %, die Stadt den Rest; ohne Entscheidung entscheidet das Bauamt nach 3 Tagen."},
	"propose_regional_project": {"params": {"partner": "int", "anteil_prozent": "number?", "reason": "string"},
		"desc": "Gemeinschaftsprojekt mit einer Nachbarstadt vorschlagen (obs.region.nachbarn): neue Schotterstraße zwischen beiden Orten; eine Ausschreibung, Kosten nach Anteilen (anteil_prozent = dein Anteil, Standard 50). Die Partnerstadt muss zustimmen (Frist 5 Tage), sonst scheitert es."},
	"decide_regional_project": {"params": {"projekt": "string", "decision": "string", "reason": "string"},
		"desc": "Über die Beteiligung an einem Gemeinschaftsprojekt entscheiden (obs.region.gemeinschaftsprojekte_offen): decision zustimmen | ablehnen. Zustimmen reserviert deinen Anteil; Ablehnen lässt das Projekt scheitern."},
	"decide_mining": {"params": {"grundstueck": "string", "decision": "string", "abgabe_prozent": "number?", "reason": "string"},
		"desc": "Abbauantrag eines Unternehmers entscheiden (obs.bergbau.abbauantraege): decision genehmigen | ablehnen. abgabe_prozent 3–15 = Förderabgabe vom Rohstoffwert an die Stadtkasse (Standard 8); höher bringt mehr Steuern, zu hoch macht den Abbau unrentabel. Bergwerke schaffen Arbeitsplätze und Exporte über den Hafen. Ohne Entscheidung genehmigt das Bauamt nach 3 Tagen mit 8 %."},
	"decide_access": {"params": {"antrag": "string", "decision": "string", "bruecke": "string?", "vergabe": "string?", "firma": "int?", "reason": "string"},
		"desc": "Erschließungsantrag eines Unternehmers entscheiden (obs.erschliessung.antraege: Zufahrt zu einer Lagerstätte, ggf. mit Brücke). decision genehmigen | ablehnen. Genehmigt zahlt die Firma ihren Beitrag für den Weg, die Stadt trägt die Brücke(n) (anteil_stadt). Du bestimmst, wie gebaut wird: bruecke holz | stein | stahlbeton (muss Spannweite und Last schaffen) und vergabe ausschreibung | direkt (firma = Firmen-ID einer Unternehmer-Baufirma). Ohne Entscheidung entscheidet das Bauamt nach 3 Tagen."},
	"decide_application": {"params": {"application_id": "string", "decision": "string", "reason": "string", "conditions": "array?"},
		"desc": "Bauantrag der Bürgermeisterebene entscheiden: decision genehmigen | bedingungen | ablehnen | rueckfrage. Ablehnung nur wegen benannter fehlender Voraussetzungen; ohne Mängel muss genehmigt werden."},
}
const FIRST_NAMES := ["Katharina", "Thomas", "Ingrid", "Markus", "Sabine", "Jürgen", "Petra", "Stefan", "Monika", "Ralf"]
const LAST_NAMES := ["Brandt", "Winter", "Lindner", "Roth", "Kessler", "Albrecht", "Hahn", "Sommer", "Engel", "Voigt"]
const PERSONS_PER_UNIT := 2.4
const BASE_VACANCY := 0.03
const RESERVE_CASH := 100000.0         # Mindestreserve der Stadtkasse
const MAX_CLUSTER := 12
const MAX_NOTES := 25
const ELECTION_MIN_APPROVAL := 45.0
const MAX_QUERIES := 2                 # Rueckfragen der Buergermeisterebene je Antrag

var sim
var name := ""
var party := "wachstum"
var term_start_day := 0
var approval := 55.0
var stock_units := 0                   # Wohneinheiten im Bestand
var waiting := 0                       # wohnungssuchende Haushalte
var plans := {}                        # "Q<n>" -> Quartiersplan
var projects := {}                     # "P<n>" -> oeffentliches Projekt (Erschliessung, Strasse)
var decisions: Array = []              # Entscheidungsprotokoll mit Begruendung und Ausfuehrung
var notes: Array = []                  # Gedaechtnis des Amtes
var commitments := 0.0                 # aus der Stadtkasse reservierte Mittel
var elections: Array = []              # {day, approval, result, mayor}
var pop_history: Array = []
var growth_history: Array = []          # je Monat {monat, wohnhaeuser, geschaefte, steuern} (Ziele des Buergermeisters)

## Ziele: zufriedene Buerger, Zuwachs an Wohnhaeusern und Geschaeften, Steuern. Dafuer eine ausgewogene Flaechenaufteilung (Richtwerte
## als Anteil der bebaubaren Flaeche; Abweichungen zeigen, wo umgewidmet werden sollte).
const HOME_TYPES := ["house", "semi", "villa", "apartment", "highrise"]
const SHOP_TYPES := ["shop", "pharmacy", "restaurant", "office", "bank", "gas_station"]
const ZONE_TARGET := {"wohnen": 0.45, "mischgebiet": 0.2, "gewerbe": 0.2, "industrie": 0.15}
var marketing_boost := 0.0             # zusaetzlicher Zuzug durch Stadtmarketing (Anteil)
var marketing_until := -1              # bis einschliesslich Monat
var town := 0                          # Ort dieser Verwaltung (Auftrag 17); Konto, Grundeigentum und Lager ueber Towns
var _next_plan := 1
var _next_project := 1
var _next_dec := 1
var _arrival_acc := 0.0                # Bruchteil zugezogener Haushalte (Zuzug wird taeglich verteilt)


func setup(simulation) -> void:
	sim = simulation
	sim.month_changed.connect(on_month)
	sim.day_changed.connect(on_day)


## Anfangszustand nach Erzeugung der Stadt: Wohnungsbestand passt zur Bevoelkerung (3 % Leerstand).
func start() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.city.seed_value) + 31337 + 7919 * town   # je Ort eigener Buergermeister
	name = "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	party = Council.SEATS.keys()[rng.randi() % 3]
	stock_units = int(ceil(float(sim.citizens.population_of(town)) / PERSONS_PER_UNIT * (1.0 + BASE_VACANCY)))
	pop_history = [sim.citizens.population_of(town)]


# ------------------------------------------------------------------ Kennzahlen
func occupied_units() -> int:
	if _region():
		return town_units().filter(func(u): return u.tenant != "").size()
	return mini(stock_units, int(round(float(sim.citizens.population()) / PERSONS_PER_UNIT)))


func vacancy() -> float:
	if _region():
		var all := town_units().size()
		return float(all - occupied_units()) / maxf(1.0, float(all))
	return float(stock_units - occupied_units()) / maxf(1.0, float(stock_units))


const JOB_PULL_MIN := 3.0     # Haushalte je Monat, die bei offenen Stellen mindestens zuziehen (Region)


func _region() -> bool:
	return sim.towns != null and sim.towns.is_region()


## Wohneinheiten im eigenen Verwaltungsgebiet (Region).
func town_units() -> Array:
	return sim.housing.units.values().filter(func(u): return sim.towns.of_building(int(u.building)) == town)


## Region: Zuzug in die eigene Stadt (Einwohner, Beschaeftigung und Glueck dieser Stadt bzw. der Region); Zugezogene ziehen direkt in
## freie Wohnungen des eigenen Gebiets. Wer keine Wohnung findet, wartet (Wohnungssuchende dieser Stadt).
const REGION_ARRIVALS := 10.0  # Region: Zuzug je Monat das Zehnfache der Grundrate (Staedte sollen sichtbar wachsen; Zuzug ist der Taktgeber des Bautraegers)
func _arrivals_town() -> void:
	if sim.wildnis and not sim.town_ready(town):
		return   # Erst nach der Stadtgründung gibt es eine Zielstadt für Zuziehende.
	if sim.neubeginn and not sim.wildnis:
		return   # Neubeginn: Zuzug nur per Siedlerschiff (SeaTraffic)
	var Z: Citizens = sim.citizens
	var month := GameCalendar.month_of(sim.game_min)
	var boost := marketing_boost if month <= marketing_until else 0.0
	var rate := float(Population.cfg().get("zuzug_je_monat", 0.04)) * REGION_ARRIVALS / float(GameCalendar.DAYS_PER_MONTH)
	var fam: float = sim.civic.family_factor(town) if sim.civic != null and sim.civic.enabled() else 1.0   # Spielplaetze, Parks, Kitas ziehen Familien an
	if sim.education != null and sim.education.enabled():
		fam *= sim.education.family_factor(town)   # Auftrag 20: Kitaplaetze
	_arrival_acc += float(Z.population_of(town)) / PERSONS_PER_UNIT * rate * (0.5 + Z.employment_rate_of(town)) * (0.5 + sim.population.mean_need("glueck") / 100.0) * (1.0 + boost) * fam
	# Sog durch Arbeit: kleine Orte wachsen nicht nur proportional zur Einwohnerzahl. Je besser die Beschaeftigung, desto mehr Haushalte
	# kommen zusaetzlich (bei 90 % JOB_PULL_MIN je Monat, mehr bei offenen Stellen); unter 70 % kein zusaetzlicher Zuzug.
	var open_jobs := 0
	for v in Z._vacancies().values():
		open_jobs += maxi(0, int(v))
	open_jobs = open_jobs / maxi(1, sim.towns.count())
	var pull := clampf((Z.employment_rate_of(town) - 0.7) / 0.2, 0.0, 1.0)   # 70 % Beschaeftigung: kein Sog, 90 %: voller Sog
	if pull > 0.0:
		_arrival_acc += maxf(JOB_PULL_MIN, float(open_jobs) / PERSONS_PER_UNIT) * pull / float(GameCalendar.DAYS_PER_MONTH) * (1.0 + boost)
	var new_h := int(_arrival_acc)
	_arrival_acc -= float(new_h)
	waiting += new_h
	# Der Gruender zaehlt bereits als Einwohner, obwohl noch keine Familie dort wohnt.
	# Seine Grundrate liefert erst nach vielen Tagen einen Haushalt. Eine erste
	# Pionierfamilie wartet auf ein tatsaechlich erschlossenes, bewohnbares Haus.
	if sim.wildnis and waiting == 0 and not town_units().any(func(u): return str(u.tenant) != ""):
		waiting = 1
	if waiting <= 0:
		return
	var free: Array = town_units().filter(func(u): return u.tenant == "" and sim.housing.habitable(u))
	free.sort_custom(func(a, b): return a.id < b.id)
	var moving := mini(waiting, free.size())
	for i in moving:
		var u: Dictionary = free[i]
		Z.immigrate(int(round(PERSONS_PER_UNIT)), month, str(u.id))
		u.tenant = "B"
		u.arrears = 0
	waiting -= moving


## Mietniveau relativ (100 = ausgeglichener Markt): steigt bei wartenden Haushalten, sinkt bei Leerstand.
func rent_index() -> float:
	return clampf(100.0 + 400.0 * float(waiting) / maxf(1.0, float(stock_units)) - 300.0 * (vacancy() - BASE_VACANCY), 70.0, 160.0)


## Stadtkasse dieses Orts (Towns.account_of), oeffentliches Grundeigentum, eigenes Zentrallager und eigener Hafen.
func acct() -> String:
	return Towns.account_of(town)


func land_owner() -> String:
	return Towns.owner_of(town)


func cash() -> float:
	return float(sim.economy.accounts.get(acct(), 0.0))


func depot() -> CityDepot:
	return sim.towns.depot(town) if sim.towns != null and sim.towns.depots.size() > 0 else depot()


func harbor() -> Harbor:
	return sim.towns.harbor(town) if sim.towns != null and sim.towns.harbors.size() > 0 else sim.harbor


func airport() -> Airport:
	return sim.towns.airport(town) if sim.towns != null and sim.towns.airports.size() > 0 else sim.airport


func town_label() -> String:
	return sim.towns.name_of(town) if sim.towns != null and sim.towns.list.size() > 0 else (sim.city.town_name if sim.city.town_name != "" else "die Stadt")


func available_budget() -> float:
	return maxf(0.0, airport_budget() - airport_reservation)


func airport_budget() -> float:
	return maxf(0.0, cash() - reserve_cash() - commitments)


var airport_goal := false
var airport_target_cost := 0.0
var airport_reservation := 0.0
var airport_financing_mode := "sparen"


func _refresh_airport_reservation() -> void:
	var basic_services: bool = sim.eko != null and int(sim.eko.city_growth_status(town).get("bewohnbar", 0)) > 0
	if airport_goal and not airport().enabled and basic_services:
		airport_reservation = minf(airport_target_cost, maxf(0.0, airport_budget() - 30000.0))
	else:
		airport_reservation = 0.0


func plan_airport(strategy: String) -> Dictionary:
	if strategy not in ["sparen", "kredit"]:
		return {"ok": false, "msg": "Strategie muss sparen oder kredit sein."}
	if airport().enabled:
		return {"ok": false, "msg": "Der Flughafen steht bereits."}
	for project in projects.values():
		if str(project.kind) == "flughafenbau" and str(project.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
			return {"ok": false, "msg": "Der Flughafen wird bereits gebaut."}
	var site: Dictionary = sim.eko.settle.transport_site(town, "flughafen")
	if site.is_empty():
		return {"ok": false, "msg": "Kein freies ebenes Flugfeld mit Zufahrt gefunden."}
	airport_goal = true
	airport_target_cost = EkoSettle.AIRPORT_BUILD_COST + (site.get("road", []) as Array).size() * 180.0
	airport_financing_mode = strategy
	_refresh_airport_reservation()
	var priority := " Erst bewohnbare Wohnungen und Versorgung schaffen; bis dahin werden keine Mittel gebunden und kein Flughafenkredit angeboten." if airport_reservation <= 0.0 and int(sim.eko.city_growth_status(town).get("bewohnbar", 0)) == 0 else ""
	return {"ok": true, "msg": "Flughafenplan %s gespeichert: %s geschaetzt, %s reserviert, %s fehlen im freien Flughafenbudget. Bauzeitpunkt selbst waehlen.%s" % [strategy, Catalog.money(airport_target_cost), Catalog.money(airport_reservation), Catalog.money(maxf(0.0, airport_target_cost - airport_budget())), priority]}


func airport_plan_committed() -> void:
	airport_goal = false
	airport_target_cost = 0.0
	airport_reservation = 0.0


## Mindestreserve nach Ortsgroesse: 20 000 EUR + 80 EUR je Einwohner, hoechstens RESERVE_CASH (die grosse Stadt bleibt bei 100 000).
func reserve_cash() -> float:
	return minf(RESERVE_CASH, 20000.0 + 80.0 * float(sim.citizens.population_of(town)))


## Landeszuweisung (Strukturfoerderung) fuer kleine Orte: monatlich, faellt mit wachsender Einwohnerzahl weg (ab GRANT_UNTIL).
const GRANT_BASE := 14000.0
const GRANT_UNTIL := 500
var grants_total := 0.0
var grant_last := 0.0
const CREDIT_LIMIT := 750000.0
const CREDIT_MIN := 20000.0
const CREDIT_RATE_MONTH := 0.003
const CREDIT_REPAY_SHARE := 0.2
var credit_debt := 0.0
var credit_total := 0.0
var credit_repaid := 0.0
var credit_last_day := -999


func credit_offer() -> Dictionary:
	var units := 0
	var unserved := 0
	for unit in sim.housing.units.values():
		if sim.towns.of_building(int(unit.building)) == town:
			units += 1
			var parcel: Dictionary = sim.parcels.of_building(int(unit.building))
			var utility: Dictionary = parcel.get("erschliessung", {})
			var gap := not parcel.is_empty() and ["strasse", "strom", "wasser", "abwasser"].any(func(part): return not bool(utility.get(part, false)))
			gap = gap or not sim.grid.net.connected(town) or not sim.water.building_on_net(town, int(unit.building)) or not sim.water.building_on_sewer(town, int(unit.building))
			if gap:
				unserved += 1
	var room := maxf(0.0, CREDIT_LIMIT - credit_debt)
	var gap := maxf(0.0, reserve_cash() + commitments - cash())
	var minimum := maxf(CREDIT_MIN, gap + 20000.0)
	var emergency_topup := credit_debt > 0.0 and available_budget() < 1000.0
	var cooldown_ok: bool = _today() - credit_last_day >= 15 or emergency_topup
	var infrastructure: bool = unserved > 0 and available_budget() < 25000.0
	var airport_gap := maxf(0.0, airport_target_cost - airport_budget())
	var airport_finance: bool = airport_goal and airport_financing_mode == "kredit" and unserved == 0 and airport_gap >= CREDIT_MIN and sim.citizens.population_of(town) > 0 and not sim.eko.settle.transport_site(town, "flughafen").is_empty()
	if airport_finance and not infrastructure:
		minimum = maxf(CREDIT_MIN, airport_gap)
	var allowed: bool = sim.wildnis and sim.town_ready(town) and (infrastructure or airport_finance) \
		and room >= minimum and cooldown_ok
	var suggested := minf(room, ceilf(maxf(minimum, gap + minf(100000.0, 50000.0 + float(units) * 3000.0)) / 1000.0) * 1000.0)
	if airport_finance and not infrastructure:
		suggested = minf(room, ceilf(airport_gap / 1000.0) * 1000.0)
	return {"ok": allowed, "vorschlag": suggested if allowed else 0.0, "minimal": snappedf(minimum, 1.0) if allowed else 0.0, "maximal": room if allowed else 0.0,
		"schuld": snappedf(credit_debt, 1.0), "zins_pro_monat": CREDIT_RATE_MONTH,
		"rueckzahlung": "20 % des freien monatlichen Ueberschusses nach Projektreservierungen und Mindestreserve",
		"zweck": "Flughafen" if airport_finance and not infrastructure else "Wohnungsanschluesse",
		"grund": "Kredit fuer unversorgte Wohnungen oder einen von der KI geplanten Flughafen; fruehestens 15 Tage nach dem letzten Kredit, mit Schuldengrenze und Zins."}


func request_credit(amount: float) -> Dictionary:
	var offer: Dictionary = credit_offer()
	if not bool(offer.ok):
		return {"ok": false, "msg": "Derzeit kein Stadtinvestitionskredit verfuegbar. Pruefe kreditangebot, laufende Projekte und die Stadtkasse."}
	if amount < float(offer.minimal) or amount > float(offer.maximal) or not is_finite(amount):
		return {"ok": false, "msg": "Kreditbetrag muss zwischen %s und %s liegen. Vorgeschlagen sind %s fuer %s." % [Catalog.money(float(offer.minimal)), Catalog.money(float(offer.maximal)), Catalog.money(float(offer.vorschlag)), str(offer.zweck)]}
	amount = snappedf(amount, 1.0)
	sim.economy.transfer("X0", acct(), amount)
	credit_debt += amount
	credit_total += amount
	credit_last_day = _today()
	_refresh_airport_reservation()
	sim.log_event("%s nimmt einen Stadtinvestitionskredit von %s fuer %s auf (Schuld %s); der Buergermeister waehlt das Projekt." % [town_label(), Catalog.money(amount), str(offer.zweck), Catalog.money(credit_debt)], "info")
	return {"ok": true, "msg": "Kredit %s fuer %s ausgezahlt. Frei verfuegbar: %s; Flughafenbudget: %s; Schuld %s." % [Catalog.money(amount), str(offer.zweck), Catalog.money(available_budget()), Catalog.money(airport_budget()), Catalog.money(credit_debt)]}


func _service_credit() -> void:
	if credit_debt <= 0.0:
		return
	credit_debt = snappedf(credit_debt * (1.0 + CREDIT_RATE_MONTH), 0.01)
	var surplus := available_budget()
	var payment := minf(credit_debt, snappedf(surplus * CREDIT_REPAY_SHARE, 0.01))
	if payment > 0.0:
		sim.economy.transfer(acct(), "X0", payment)
		credit_debt = maxf(0.0, credit_debt - payment)
		credit_repaid += payment
func _state_grant() -> void:
	var pop: int = sim.citizens.population_of(town)
	grant_last = 0.0
	if pop >= GRANT_UNTIL:
		return
	grant_last = snappedf(GRANT_BASE * (1.0 - float(pop) / float(GRANT_UNTIL)), 10.0)
	sim.economy.transfer("X0", acct(), grant_last)
	grants_total += grant_last
	sim.log_event("Landeszuweisung für %s: %s (Strukturförderung kleiner Orte, %d Einwohner)." % [town_label(), Catalog.money(grant_last), pop], "info")


func transport_indicators() -> Dictionary:
	var out := {}
	for kind in ["hafen", "flughafen"]:
		var built: bool = harbor().enabled if kind == "hafen" else airport().enabled
		var pending := ""
		for p in projects.values():
			if str(p.kind) == ("hafenbau" if kind == "hafen" else "flughafenbau") and str(p.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
				pending = str(p.id)
				break
		var site: Dictionary = sim.eko.settle.transport_site(town, kind) if not built and pending == "" and sim.wildnis else {}
		out[kind] = {"gebaut": built, "projekt": pending, "standort": site.get("site", []), "strassenfelder": (site.get("road", []) as Array).size(),
			"kosten": (EkoSettle.HARBOR_BUILD_COST if kind == "hafen" else EkoSettle.AIRPORT_BUILD_COST) + (site.get("road", []) as Array).size() * 180 if not site.is_empty() else 0,
			"grund": "kein freier Meereshafen mit Zufahrt" if kind == "hafen" and site.is_empty() and not built else ("kein freies ebenes Flugfeld mit Zufahrt" if site.is_empty() and not built else "")}
		if kind == "flughafen":
			out[kind]["finanzplan"] = {"aktiv": airport_goal, "strategie": airport_financing_mode, "zielkosten": int(airport_target_cost),
				"reserviert": int(airport_reservation), "flughafenbudget": int(airport_budget()),
				"fehlbetrag": int(maxf(0.0, float(out[kind].kosten) - airport_budget()))}
	var st: Dictionary = sim.rail.station_of(town) if sim.rail != null else {}
	var center: Vector2i = sim.towns.get_t(town).center
	var sr: Array = st.get("rect", [])
	var rail_pending := ""
	for p in projects.values():
		if str(p.kind) == "bahnhofbau" and str(p.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
			rail_pending = str(p.id)
			break
	out["bahn"] = {"bahnhof": not st.is_empty(), "gebaut": not st.is_empty(), "projekt": rail_pending, "kosten": RailNet.STATION_BUILD_COST,
		"standort": sr.slice(0, 2) if not st.is_empty() else [center.x, center.y],
		"entfernung_zur_stadt": absi(int(sr[0]) - center.x) + absi(int(sr[1]) - center.y) if sr.size() >= 2 else -1,
		"zuege": sim.trains.trains.size() if sim.trains != null else 0}
	return out


func indicators() -> Dictionary:
	var Z: Citizens = sim.citizens
	var vac_jobs := 0
	var by_vac := {}
	for k in Citizens.EMPLOYERS:
		var v := maxi(0, int(Z.cap.get(k, 0)) - Z.employed_count(k))
		by_vac[k] = v
		vac_jobs += v
	var net_wage := 0.0
	var n := 0
	for p in Z.people:
		if p.employer != "":
			net_wage += float(p.wage) * Citizens.HOURS_PER_MONTH * (1.0 - PublicSector.INCOME_TAX - PublicSector.SOCIAL_RATE)
			n += 1
	net_wage = net_wage / maxf(1.0, float(n))
	var rent := 0.25 * net_wage * rent_index() / 100.0
	var free_by_zone := {}
	var served := 0
	var free_n := 0
	for p in sim.parcels.items.values():
		if p.state == "frei" and sim.parcels.is_buildable(p) and p.owner == land_owner():
			free_n += 1
			var e: Dictionary = free_by_zone.get(p.zone, {"anzahl": 0, "flaeche": 0})
			e.anzahl += 1
			e.flaeche += int(p.area)
			free_by_zone[p.zone] = e
			if sim.parcels.utility_level(p) == "voll":
				served += 1
	var jams: int = sim.traffic_events.filter(func(e): return e.kind == "stau").size()
	var queue_ids: Array = []
	var pending: Array = []
	for a in sim.permits.apps.values():
		if a.status == "zur_entscheidung" and _mine(str(a.parcel)):
			queue_ids.append(a.id)
			var pre := Planning.assess(sim.parcels.parcel(a.parcel), a)
			var design: Dictionary = BuildingDesigns.design(str(a.get("design", "")))
			pending.append({"id": a.id, "antragsteller": a.applicant, "grundstueck": a.parcel, "art": str(design.get("label", Planning.DEFS[a.def].label)), "geschosse": a.floors,
				"entwurf": str(a.get("design", "")), "komfort": int(design.get("comfort", 60)), "ausstattung": design.get("amenities", []),
				"einheiten": pre.units, "kosten_gesamt": pre.costs.get("gesamt", 0.0), "vorpruefung_ok": pre.ok, "ablehnungsgruende": pre.blocking,
				"offene_punkte": pre.questions, "auflagen": pre.conditions.map(func(c): return c.text), "rueckfragen_bisher": int(a.get("mayor_queries", 0))})
	var trend := 0
	if pop_history.size() >= 2:
		trend = int(pop_history[-1]) - int(pop_history[-2])
	return {
		"stadt_id": town,
		"buergermeister": {"name": name, "partei": party, "zustimmung": snappedf(approval, 0.1), "amtszeit_seit_tag": term_start_day, "tag": _today()},
		"bevoelkerung": {"einwohner": Z.population_of(town), "veraenderung_letzter_monat": trend, "monat": GameCalendar.month_of(sim.game_min),
			"stadtmarketing_bis_monat": marketing_until, "stadtmarketing_zuzug_plus": snappedf(marketing_boost, 0.01)},
		"wohnen": {"bestand_einheiten": stock_units, "belegt": occupied_units(), "leerstand": snappedf(vacancy(), 0.001),
			"wohnungssuchende_haushalte": waiting, "mietindex": snappedf(rent_index(), 0.1), "miete_monat": snappedf(rent, 1.0),
			"bezahlbarkeit_miete_anteil_netto": snappedf(rent / maxf(1.0, net_wage), 0.01),
			"zufriedenheit": snappedf(sim.contentment.mean, 0.1), "zufriedenheit_viertel": sim.contentment.by_district.duplicate(),
			"wohnungslos": sim.housing.homeless_count(), "raeumungen": int(sim.housing.stats.evictions), "planung": sim.housing.planning_aids()},
		"stadtentwicklung": sim.civic.mayor_obs(town) if sim.civic != null else {},
		"kommunale_dienste": sim.services.mayor_obs(town) if sim.services != null and sim.municipal.enabled() else {},
		"fahrzeugwerk": sim.vworks.mayor_obs(town) if sim.municipal.enabled() else {},
		"arbeit": {"quote": snappedf(Z.employment_rate_of(town), 0.001), "arbeitslos": Z.unemployed_of(town), "offene_stellen": vac_jobs,
			"offene_stellen_nach_arbeitgeber": by_vac},
		"buergerleben": Z.life_obs(town),
		"gewerbe": {"freie_gewerbeflaeche": free_by_zone.get("gewerbe", {}), "freie_industrieflaeche": free_by_zone.get("industrie", {}),
			"nachfrage_stellen_baufirma_industrie": int(by_vac.get("baufirma", 0)) + int(by_vac.get("industrie", 0))},
		"verkehr": _traffic_indicators(jams),
		"versorgung": {"freie_stadtgrundstuecke": free_n, "davon_voll_erschlossen": served,
			"anteil_voll_erschlossen": snappedf(float(served) / maxf(1.0, float(free_n)), 0.01)},
		"haushalt": {"kasse": snappedf(cash(), 1.0), "reserviert": snappedf(commitments, 1.0), "verfuegbar": snappedf(available_budget(), 1.0),
			"flughafenreserve": snappedf(airport_reservation, 1.0), "flughafenbudget": snappedf(airport_budget(), 1.0),
			"steuern_gesamt": snappedf(sim.public_sector.tax_total + sim.public_sector.social_total + sim.public_sector.corporate_total, 1.0),
			"defizit": cash() < reserve_cash(), "mindestreserve": int(reserve_cash()), "landeszuweisung_monat": int(grant_last),
			"hinweis": "verfuegbar = Kasse - Mindestreserve - reserviert. Ist verfuegbar 0, scheitert jede Ausgabe: dann Grundstücke verkaufen (offer_parcels), Grundsteuer anpassen oder warten."},
		"kreditangebot": credit_offer(),
		"bauantraege": {"warteschlange": sim.permits.queue().size(), "zur_entscheidung": queue_ids, "zur_entscheidung_details": pending, "kapazitaet_je_tag": snappedf(sim.permits.capacity(), 0.1)},
		"plaene": plans.values().map(func(p): return {"id": p.id, "name": p.name, "status": p.status, "grundstuecke": p.parcels.size(), "zone": p.zone, "tag": int(p.get("day", 0)),
			"ratsbegruendung": str(p.get("vote", "")).left(200) if p.status == "abgelehnt" else "",
			"ids_zur_entwicklung": p.parcels.filter(func(id): return sim.parcels.parcel(id).get("state", "") == "zur_entwicklung").slice(0, MAX_CLUSTER),
			"ids_ohne_anschluss": p.parcels.filter(func(id): return sim.parcels.parcel(id).get("state", "") in ["frei", "zur_entwicklung"] and sim.parcels.utility_level(sim.parcels.parcel(id)) != "voll").slice(0, MAX_CLUSTER),
			"naechster_schritt": "plan_infrastructure mit ids_ohne_anschluss (baut Straße und Anschlüsse)" if p.status == "beschlossen" else ""}),
		"projekte": projects.values().map(func(p): return {"id": p.id, "art": p.kind, "status": p.status, "kosten": p.cost, "prioritaet": p.get("priority", 0), "grundstuecke": p.parcels.slice(0, MAX_CLUSTER)}),
		"stadtlager": stadtlager_indicators(),
		"entwicklungsvorschlaege": quarter_candidates(3),
		"stadtplan": sim.town_plan.brief(town) if sim.town_plan != null else {},
		"stadtplan_naechster_abschnitt": sim.town_plan.next_district(town, waiting > 0) if sim.town_plan != null else {},
		"stadtplan_erweiterung": sim.town_plan.expansion_sites(town) if sim.town_plan != null else [],
		"planungsregeln": ["wohnen", "mischgebiet", "gewerbe", "industrie"].map(func(z): return Planning.rules(z)),
		"rathaus": sim.town_hall.summary(),
		"pruefungen": sim.inspections.summary(),
		"ziele": goals(),
		"flaechenplanung": zoning(),
		"strassen": sim.road_care.summary(),
		"hof_bauantraege": sim.estate.open_permits(),
		"bevoelkerungsmodell": sim.population.summary(),
		"sicherheit_gesundheit": sim.safety.summary(),
		"rivalitaet": sim.rivalry.mayor_summary(),
		"strom": sim.grid.summary(),
		"stromtrassen": sim.grid.net.option_brief(town),
		"versorgungsleitungen": sim.water.main_brief(town) if sim.water != null and sim.water.enabled() else [],
		"versorgungsanlagen_standorte": sim.services.utility_sites(town) if sim.services != null and sim.water != null and sim.water.enabled() else [],
		"bahn": sim.trains.summary() if sim.trains != null and not sim.trains.path.is_empty() else {},
		"wasser": sim.water.mayor_view(town) if sim.water != null and sim.water.enabled() else {},
		"polizei": sim.police.summary(town) if sim.police != null and sim.police.enabled() else {},
		"infrastruktur_lage": InfraStatus.compact(sim, town) if sim.towns.is_region() else {},
		"erschliessung": access_indicators(),
		"tunnel": sim.tunnels.summary(town),
		"bergbau": _own_mining(),
		"region": _region_obs(),
		"hafen": harbor().summary() if harbor().enabled else {},
		"flughafen": airport().summary() if airport().enabled else {},
		"verkehrsstandorte": transport_indicators(),
		"gedaechtnis": notes.slice(-6),
		"entscheidungen_zuletzt": decisions.slice(-4).map(func(d): return {"tag": d.day, "aktion": d.action, "ok": d.ok, "ergebnis": d.msg.left(120)}),
		"zuletzt_abgelehnt": decisions.slice(-12).filter(func(d): return not d.ok).map(func(d): return "%s: %s" % [d.action, d.msg.left(100)]),
		"neue_quartiere_ab_tag": _quarter_days(),   # je Zone: ab diesem Tag nimmt der Rat wieder Quartiersantraege an
	}


## Verkehr: Mengen, Zeitverlust, wiederkehrende Engpaesse und laufende bzw. fertige Massnahmen mit Vorher/Nachher.
func _traffic_indicators(jams: int) -> Dictionary:
	var T: TrafficFlow = sim.traffic_flow
	var busy := {}
	for m in T.measures.values():
		busy[m.cell] = m.status
	var spots: Array = []
	for h in T.hotspots(5 if not _region() else 40):
		if _region() and sim.towns.of_cell(h.cell) != town:
			continue   # nur Engpaesse im eigenen Gebiet
		if spots.size() >= 5:
			break
		spots.append({"x": h.cell.x, "y": h.cell.y, "verlorene_fahrzeugsekunden": snappedf(h.lost, 1.0), "tage_mit_stau": h.days, "wiederkehrend": h.recurring,
			"kreuzung": T.is_junction(h.cell), "neben_gebaeude": T.next_to_building(h.cell), "kapazitaet": T.capacity_of(h.cell), "massnahme": busy.get(h.cell, "")})
	var done: Array = []
	for m in T.measures.values():
		var e := T.effect(m)
		done.append({"id": m.id, "art": m.kind, "x": m.cell.x, "y": m.cell.y, "status": m.status, "kosten": m.cost,
			"verlust_je_tag_vorher": snappedf(e.vorher, 0.1), "verlust_je_tag_nachher": snappedf(e.nachher, 0.1) if e.nachher >= 0.0 else null})
	var worst := 0
	var hours: Array = T.delay_by_hour()
	for h in 24:
		if hours[h] > hours[worst]:
			worst = h
	return {"fahrzeuge_unterwegs": sim.traffic.size(), "staus": jams, "strassenzellen": sim.city.road_count, "durchschnittstempo": snappedf(T.avg_speed(), 0.01),
		"stosszeit_stunde": worst, "engpaesse": spots, "massnahmen": done.slice(-6)}


## Stadtlager: offene Beschaffungsvorschlaege (Entscheidung der Buergermeisterebene), kritische Bestaende, laufende Bestellungen.
func stadtlager_indicators() -> Dictionary:
	var D: CityDepot = depot()
	var props: Array = []
	for o in D.orders.values():
		if o.status == "vorschlag":
			var q := D.quote(o.item, int(o.qty), int(o.crit))
			props.append({"id": o.id, "artikel": CityGoods.get_item(o.item).name, "menge": o.qty, "kritikalitaet": o.crit, "grund": o.reason, "geschaetzte_kosten": snappedf(float(q[0].total) + D._freight(o.item, int(o.qty), int(q[0].loc)) if not q.is_empty() else 0.0, 1.0),
				"anbieter": q[0].name if not q.is_empty() else "", "tage_offen": _today() - int(o.day), "entscheidung": o.get("decision", ""),
				"projekt": str(o.get("project", ""))})
	# Material laufender Projekte zuerst: der Buergermeister hat pro Runde nur wenige Aktionen, und jedes offene
	# Projektmaterial muss genehmigt werden, bevor der Bauschritt laeuft (sonst stauen Routineeinkaeufe die Projekte aus).
	props.sort_custom(func(a, b): return (str(a.projekt) != "" and str(b.projekt) == "") or (str(a.projekt) != "" and str(b.projekt) != "" and int(a.kritikalitaet) > int(b.kritikalitaet)))
	var underway: Array = D.open_orders().filter(func(o): return str(o.status) != "vorschlag")
	underway = underway.map(func(o): return {"id": str(o.id), "artikel": str(o.item), "menge": int(o.qty),
		"status": str(o.status), "projekt": str(o.get("project", "")), "lieferung_bis_tag": int(o.get("due", -1))})
	return {"rampen": D.ramps, "rampen_frei": D.ramps_free(), "lkw_wartezeiten_letzte_10_tage": D.recent_waits(), "rueckstau_wareneingang_einheiten": D.backlog_units(),
		"personal_verfuegbar": D.available_staff(), "personal_gesamt": D.roster().size(), "kapazitaet_wareneingang_je_tag": D.dock_capacity(), "gabelstapler": D.forklifts(),
		"laufende_kosten_monat": snappedf(float(D.running_costs().summe), 1.0), "blockaden": D.current_tasks().blockers.slice(0, 4),
		"vorschlaege": props.slice(0, 8), "kritisch": D.critical_items().slice(0, 6).map(func(i): return {"artikel": i.name, "bestand": i.bestand, "mindestbestand": i.mindestbestand}),
		"bestellungen_offen": underway.size(), "laufende_bestellungen": underway.slice(0, 8),
		"einkauf_bisher": snappedf(float(D.stats.purchases), 1.0), "transportpool": D.pool_summary()}


## Gruppen staedtischer, freier Grundstuecke (je 32x32 Felder) als Vorschlaege fuer neue Quartiere.
## Bezugspunkt "Zentrum": Kern des Stadtplans, sonst Rathaus, sonst (alte Einzelstadt) die Kartenmitte.
func _center_ref() -> Vector2:
	if sim.town_plan != null and sim.town_plan.has(town):
		var kp: Array = sim.town_plan.of(town).kern
		return Vector2(int(kp[0]), int(kp[1]))
	var hall := int(sim.towns.get_t(town).get("town_hall", -1)) if sim.towns != null else -1
	if hall >= 0:
		var b: Dictionary = sim.city.building(hall)
		if not b.is_empty():
			return Vector2(int(b.x), int(b.y))
	return Vector2(sim.city.size * 0.45, sim.city.size * 0.5)


func quarter_candidates(limit: int) -> Array:
	var groups := {}
	var planned := _planned_ids()
	for p in sim.parcels.items.values():
		if p.owner != land_owner() or p.state not in ["frei", "zur_entwicklung"] or not sim.parcels.is_buildable(p) or p.zone not in ["wohnen", "mischgebiet", "gewerbe", "industrie"]:
			continue
		if planned.has(p.id):   # Partie 18.11.: Vorschlaege enthielten Grundstuecke beschlossener Quartiere – Regel-Buergermeister schlug sie jede Runde neu vor
			continue
		if sim.parcels.utility_level(p) == "keine":
			continue
		var key := Vector2i(int(p.rect[0]) / 32, int(p.rect[1]) / 32)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(p)
	var out: Array = []
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 4:
			continue
		list.sort_custom(func(a, b): return a.area > b.area)
		var chosen: Array = list.slice(0, MAX_CLUSTER)
		var area := 0
		var zone_count := {}
		var full := 0
		for p in chosen:
			area += int(p.area)
			zone_count[p.zone] = int(zone_count.get(p.zone, 0)) + 1
			if sim.parcels.utility_level(p) == "voll":
				full += 1
		var zone := "wohnen"
		for z in zone_count:
			if zone_count[z] > int(zone_count.get(zone, 0)):
				zone = z
		if open_quarters(zone).size() >= QUARTER_OPEN_MAX:   # Zone hat schon genug unverkaufte Quartiere
			continue
		out.append({"lage_feld": [key.x * 32, key.y * 32], "zone": zone, "flaeche": area, "grundstuecke": chosen.map(func(p): return p.id),
			"davon_voll_erschlossen": full, "entfernung_zentrum": int(Vector2(key.x * 32 + 16, key.y * 32 + 16).distance_to(_center_ref()))})
	out.sort_custom(func(a, b): return a.davon_voll_erschlossen > b.davon_voll_erschlossen or (a.davon_voll_erschlossen == b.davon_voll_erschlossen and a.entfernung_zentrum < b.entfernung_zentrum))
	return out.slice(0, limit)


# ------------------------------------------------------------------ Ziele und Flaechenplanung
func _counts() -> Array:
	var homes := 0
	var shops := 0
	var region: bool = sim.towns != null and sim.towns.is_region()
	for b in sim.city.buildings:
		if region and sim.city.town_of_building(int(b.id)) != town:
			continue   # nur Gebaeude im eigenen Verwaltungsgebiet
		if b.type in HOME_TYPES:
			homes += 1
		elif b.type in SHOP_TYPES:
			shops += 1
	return [homes, shops]


func _taxes() -> float:
	var P: PublicSector = sim.public_sector
	return P.tax_total + P.corporate_total + P.vat_total + P.property_tax_total


## Zielerreichung: Zufriedenheit, Bestand und Zuwachs an Wohnhaeusern und Geschaeften, Steuern (gesamt und im letzten Monat).
func goals() -> Dictionary:
	var c := _counts()
	var last: Dictionary = growth_history[-1] if not growth_history.is_empty() else {"wohnhaeuser": c[0], "geschaefte": c[1], "steuern": 0.0}
	var prev: Dictionary = growth_history[-2] if growth_history.size() >= 2 else last
	return {"zufriedenheit": snappedf(sim.contentment.mean, 0.1), "wohnhaeuser": c[0], "geschaefte": c[1],
		"zuwachs_wohnhaeuser_seit_monatsbeginn": c[0] - int(last.wohnhaeuser), "zuwachs_geschaefte_seit_monatsbeginn": c[1] - int(last.geschaefte),
		"zuwachs_wohnhaeuser_letzter_monat": int(last.wohnhaeuser) - int(prev.wohnhaeuser), "zuwachs_geschaefte_letzter_monat": int(last.geschaefte) - int(prev.geschaefte),
		"steuern_gesamt": snappedf(_taxes(), 1.0), "steuern_letzter_monat": snappedf(float(last.steuern) - float(prev.steuern), 1.0)}


## Flaechenbilanz je Zone (alle bebaubaren Grundstuecke) mit Richtwert und Abweichung, dazu Umwidmungsvorschlaege fuer die Zonen mit dem
## groessten Fehlbestand: Gruppen freier staedtischer Wohngrundstuecke in passender Lage (Mischgebiet nahe dem Zentrum, Industrie weit weg).
func zoning() -> Dictionary:
	var area := {}
	var free := {}
	var road_free := {}
	var total := 0
	for p in sim.parcels.items.values():
		if sim.towns.is_region() and sim.towns.of_parcel(str(p.id)) != town:
			continue
		if not sim.parcels.is_buildable(p) or not ZONE_TARGET.has(p.zone):
			continue
		area[p.zone] = int(area.get(p.zone, 0)) + int(p.area)
		total += int(p.area)
		if p.state == "frei" and p.owner == land_owner():
			free[p.zone] = int(free.get(p.zone, 0)) + int(p.area)
			if bool(sim.parcels.utilities_of(p).strasse):
				road_free[p.zone] = int(road_free.get(p.zone, 0)) + 1
	var zones := {}
	var short: Array = []
	for z in ZONE_TARGET:
		var share := float(area.get(z, 0)) / maxf(1.0, float(total))
		zones[z] = {"flaeche": int(area.get(z, 0)), "frei_staedtisch": int(free.get(z, 0)), "frei_mit_strasse": int(road_free.get(z, 0)), "anteil": snappedf(share, 0.01), "richtwert": ZONE_TARGET[z],
			"abweichung": snappedf(share - float(ZONE_TARGET[z]), 0.01)}
		if z != "wohnen" and share < float(ZONE_TARGET[z]) - 0.05:
			short.append(z)
	short.sort_custom(func(a, b): return float(zones[a].abweichung) < float(zones[b].abweichung))
	var props: Array = []
	var used := _planned_ids()
	for z in short:
		if open_quarters(z).size() >= QUARTER_OPEN_MAX:   # erst die offenen Quartiere dieser Zone vergeben (sonst lehnt _designate_quarter ab)
			continue
		var c := _rezone_cluster(z, used)
		if not c.is_empty():
			props.append(c)
	return {"zonen": zones, "fehlende_zonen": short, "umwidmung_vorschlaege": props,
		"hinweis": "Umwidmen mit designate_quarter (zone = Zielzone, parcel_ids aus dem Vorschlag); danach offer_parcels und plan_infrastructure."}


func _center() -> Vector2:
	if sim.town_hall.building >= 0:
		var b: Dictionary = sim.city.building(sim.town_hall.building)
		return Vector2(float(b.x), float(b.y))
	return Vector2(sim.city.size * 0.5, sim.city.size * 0.5)


func _rezone_cluster(zone: String, used: Dictionary) -> Dictionary:
	var groups := {}
	for p in sim.parcels.items.values():
		if sim.towns.is_region() and sim.towns.of_parcel(str(p.id)) != town:
			continue
		if p.owner != land_owner() or p.state != "frei" or p.zone != "wohnen" or not sim.parcels.is_buildable(p) or used.has(p.id):
			continue
		var key := Vector2i(int(p.rect[0]) / 24, int(p.rect[1]) / 24)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(p)
	var ctr := _center()
	var best := {}
	var best_score := INF
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 4:
			continue
		var dist := Vector2(key.x * 24 + 12, key.y * 24 + 12).distance_to(ctr)
		var full := list.filter(func(p): return sim.parcels.utility_level(p) != "keine").size()
		# Mischgebiet (Geschaefte) nahe den Wohnungen, Gewerbe in mittlerer Lage, Industrie mit Abstand; erschlossene Flaechen zuerst
		var want: float = {"mischgebiet": 20.0, "gewerbe": 60.0, "industrie": 120.0}.get(zone, 60.0)
		var score := absf(dist - want) - 6.0 * full
		if score < best_score:
			best_score = score
			list.sort_custom(func(a, b): return a.area > b.area)
			var chosen: Array = list.slice(0, MAX_CLUSTER)
			best = {"zone": zone, "grundstuecke": chosen.map(func(p): return p.id), "flaeche": chosen.reduce(func(s, p): return s + int(p.area), 0),
				"entfernung_rathaus": int(dist), "davon_erschlossen": full}
	for id in best.get("grundstuecke", []):
		used[id] = true
	return best


# ------------------------------------------------------------------ Monatslauf, Wohnungsmarkt, Wahl
## Zuzug je Spieltag: neue Haushalte suchen eine Wohnung, Wartende ziehen bei freiem Wohnraum ein (Umzugswagen auf der Karte).
## Menge nach Wirtschaftslage (Beschaeftigung) und Lebensqualitaet (mittleres Glueck, 50 = neutral); Grundrate je Monat aus
## config/residents.json "zuzug_je_monat" (Anteil der Haushalte, Standard 0,04).
func on_day(_day: int) -> void:
	if sim.wildnis:
		if not sim.town_ready(town):
			return   # Erst der Unternehmer gruendet die Stadt und baut ihr Buergeramt.
	_refresh_airport_reservation()
	if _region():
		_arrivals_town()
		return
	var Z: Citizens = sim.citizens
	var month := GameCalendar.month_of(sim.game_min)
	var boost := marketing_boost if month <= marketing_until else 0.0
	var rate := float(Population.cfg().get("zuzug_je_monat", 0.04)) / float(GameCalendar.DAYS_PER_MONTH)
	_arrival_acc += float(Z.population()) / PERSONS_PER_UNIT * rate * (0.5 + Z.employment_rate()) * (0.5 + sim.population.mean_need("glueck") / 100.0) * (1.0 + boost)
	var new_h := int(_arrival_acc)
	_arrival_acc -= float(new_h)
	waiting += new_h
	var free_units := stock_units - occupied_units()
	var moving := mini(waiting, maxi(0, free_units))
	if moving > 0:
		waiting -= moving
		Z.immigrate(int(round(moving * PERSONS_PER_UNIT)), month)


func on_month(month: int) -> void:
	var Z: Citizens = sim.citizens
	# lange Wartende wandern ab
	waiting = maxi(0, waiting - int(round(float(waiting) * 0.08)))
	pop_history.append(Z.population_of(town))
	if pop_history.size() > 36:
		pop_history.pop_front()
	_state_grant()
	_refresh_airport_reservation()
	_service_credit()
	var c := _counts()
	growth_history.append({"monat": month, "wohnhaeuser": c[0], "geschaefte": c[1], "steuern": _taxes()})
	if growth_history.size() > 36:
		growth_history.pop_front()
	_update_approval()
	if month > 0 and month % 12 == 0:
		hold_election()


func _update_approval() -> void:
	var Z: Citizens = sim.citizens
	var target := 55.0
	# Beschaeftigung der eigenen Stadt, gedeckelt: vorher drueckte sie bei hoher Arbeitslosigkeit jeden Zielwert auf 0 und
	# alle Staedte lagen bei genau 38,5 % - Wohnungsnot, Kasse, Plaene und Antraege spielten keine Rolle mehr.
	target += clampf(20.0 * (Z.employment_rate_of(town) - Citizens.employment_target()) / 0.1, -30.0, 15.0)
	if sim.civic != null and sim.civic.enabled():
		target += sim.civic.approval_bonus(town)   # Auftrag 19: Anlagen und Denkmaeler (Prunk bei fehlender Grundversorgung kostet)
	if sim.transit != null:
		target += sim.transit.approval_bonus(town)   # Auftrag 20: Busanbindung
	target -= 250.0 * float(waiting) / maxf(1.0, float(stock_units)) * 10.0 / 10.0
	if cash() < reserve_cash():
		target -= 10.0
	target -= 2.0 * maxf(0.0, float(sim.permits.queue().size()) - 3.0)
	target += 1.5 * float(plans.values().filter(func(p): return p.status == "beschlossen").size())
	var complaints := int(sim.citizens.life_last.get(town, {}).get("beschwerde", 0))   # Buerger-KI: Beschwerden im Rathaus (Personenstunden)
	target -= minf(8.0, 0.25 * float(complaints))
	var riv: Dictionary = sim.rivalry.mayor_summary()   # Unruhe zwischen Firmen (Blockaden, Sabotage) kostet Zustimmung
	target -= minf(10.0, 0.2 * float(riv.unruhe) + 2.0 * float(riv.schwere_vorfaelle_7_tage))
	approval = clampf(approval * 0.7 + clampf(target, 0.0, 100.0) * 0.3, 0.0, 100.0)


## Jaehrliche Wahl: bei zu geringer Zustimmung wird ein neues Stadtoberhaupt gewaehlt; Akten, Plaene und Gedaechtnis des Amtes bleiben.
func hold_election() -> Dictionary:
	var re := approval >= ELECTION_MIN_APPROVAL
	var old := name
	var rec := {"day": _today(), "zustimmung": snappedf(approval, 0.1), "ergebnis": "wiedergewählt" if re else "abgewählt", "amtsinhaber": old}
	if not re:
		var h := absi(hash(Vector2i(_today(), elections.size())))
		name = "%s %s" % [FIRST_NAMES[h % FIRST_NAMES.size()], LAST_NAMES[(h / 7) % LAST_NAMES.size()]]
		party = Council.SEATS.keys()[(h / 3) % 3]
		term_start_day = _today()
		approval = 55.0
		rec["nachfolger"] = name
		remember("Wahl: %s abgewählt; neue Amtsführung %s (%s)." % [old, name, party])
	elections.append(rec)
	sim.log_event("Bürgermeisterwahl: %s %s (Zustimmung %.0f %%)%s." % [old, rec.ergebnis, rec.zustimmung, "" if re else ", Nachfolger " + name], "info")
	return rec


# ------------------------------------------------------------------ Aktionen
## Auftrag 22 Phase 8: Ausbau der Versorgung aus eigener Entscheidung (sonst baut der Betreiber erst nach 5 Tagen Engpass aus).
func _infra_ausbau(anlage: String) -> Dictionary:
	if anlage == "gleis":
		if sim.trains == null or sim.trains.stops.is_empty():
			return {"ok": false, "msg": "Keine Bahnlinie."}
		var s: int = sim.trains.stop_of_town(town)
		var worst := -1
		for b in [s - 1, s]:
			if b >= 0 and b < sim.trains.stops.size() - 1 and (worst < 0 or sim.trains.condition_of(b) < sim.trains.condition_of(worst)):
				worst = b
		if s < 0 or worst < 0:
			return {"ok": false, "msg": "Kein Bahnhof in dieser Stadt."}
		return sim.trains.start_repair(worst)
	if anlage not in ["wasserwerk", "hochbehaelter", "klaeranlage"]:
		return {"ok": false, "msg": "anlage: wasserwerk | hochbehaelter | klaeranlage | gleis"}
	return sim.water.mayor_expand(town, anlage)


## Benedikt 19.11.: Wildnis-Stadt ohne Strasse zum Grosslager – erst der Anschluss, dann Projekte mit Stadtlager-Material
## (sonst warten sie auf Material, binden Geld und blockieren Baufirmen; Sonnenufer hatte 14 Projekte, 7 davon ohne Material).
const HUB_FIRST_ACTIONS := ["kommunal_bauen", "infra_ausbau", "stromtrasse_bauen", "versorgungsleitung_bauen", "propose_project",
	"viertel_erschliessen", "stadtteil_planen", "plan_infrastructure", "build_harbor", "build_airport", "build_station", "expand_harbor", "expand_airport", "expand_depot", "expand_power", "build_bridge"]


func hub_blocked() -> String:
	if not sim.wildnis or sim.eko == null or not sim.town_ready(town):
		return ""
	if bool(sim.eko.settle.road_link(town).get("verbunden", true)):
		return ""
	# Jede KI hat einen Materialhubschrauber am Grosslager. Der kann Baustoffe sichtbar
	# zum bereits gegruendeten Stadtlager bringen, auch wenn der Landweg noch fehlt.
	var depot: CityDepot = sim.towns.depot(town)
	if depot.building >= 0 and sim.material_heli != null:
		for c in sim.companies:
			if c.home_town == town and sim.material_heli.has_heli(c.id):
				return ""
	var run: Array = projects.values().filter(func(p): return str(p.get("ref", "")) == "anschluss" and str(p.status) not in ["fertig", "abgelehnt", "abgebrochen"])
	return "Erst der Straßenanschluss ans Großlager: ohne ihn bekommt das Stadtlager kein Material, neue Bauprojekte würden nur warten. %s" % (
		("Er läuft als %s – danach wieder planen." % run[0].id) if not run.is_empty() else "Das Bauamt beschließt ihn selbst.")


func execute(action: Dictionary) -> Dictionary:
	var a := ActionExecutor.normalize(action)
	var act := str(a.get("action", a.get("type", "")))
	if sim.wildnis and not sim.town_ready(town) and act != "wait":
		return {"ok": false, "msg": "Die Stadt %s existiert noch nicht. Zuerst muss ihr KI-Unternehmer den Betriebshof und das Bürgeramt bauen." % town_label()}
	var err := ActionExecutor.validate_against(SCHEMA, act, a)
	if err == "":
		a["action"] = act
		err = foreign_target(a)   # Region: keine Entscheidungen im Gebiet einer anderen Stadt
	if err == "" and act in HUB_FIRST_ACTIONS and not sim.wildnis:
		err = hub_blocked()
	if err == "" and sim.wildnis and act in ["viertel_erschliessen", "plan_infrastructure", "kommunal_bauen", "infra_ausbau", "stromtrasse_bauen", "versorgungsleitung_bauen", "propose_project", "build_harbor", "build_airport", "build_station", "build_bridge", "build_tunnel", "expand_harbor", "expand_airport", "expand_power", "grosslager_anschluss_bauen"]:
		var open_projects := 0
		for project in projects.values():
			if str(project.get("status", "")) not in ["fertig", "abgelehnt", "abgebrochen"]:
				open_projects += 1
		var capacity := maxi(3, int(ceil(float(sim.crews.crews.size()) * 0.6 / float(maxi(1, sim.towns.count())))))
		if open_projects >= capacity:
			err = "%d offene Bauprojekte bei einer Kapazität von %d. Erst Material, Bautrupps und Fertigstellung der laufenden Projekte klären; Verwaltungs- und Planungsentscheidungen bleiben möglich." % [open_projects, capacity]
		elif sim.towns.depot(town).backlog_units() > 0 and sim.towns.depot(town).roster().is_empty():
			err = "Stadtlager: angelieferte Baustoffe koennen ohne Personal nicht eingelagert werden. Entscheide ueber expand_depot mit kind staff oder klaere die Lagerblockade; neue Bauauftraege wuerden nur mehr Material stauen."
	var res: Dictionary
	if err != "":
		res = {"ok": false, "msg": err}
	else:
		match act:
			"wait":
				res = {"ok": true, "msg": "Keine Maßnahme."}
			"remember":
				remember(str(a.inhalt))
				res = {"ok": true, "msg": "Notiz gespeichert."}
			"propose_project":
				res = sim.civic.propose(town, a) if sim.civic != null else {"ok": false, "msg": "Keine Stadtentwicklung."}
			"infra_ausbau":
				res = _infra_ausbau(str(a.anlage))
			"stromtrasse_bauen":
				res = sim.grid.net.request_line(town, str(a.get("option", "")), str(a.get("reason", "Stadtversorgung")))
			"versorgungsleitung_bauen":
				res = sim.water.request_main(town, str(a.get("option", "")), str(a.get("reason", "Neue Stadtteile versorgen"))) if sim.water != null and sim.water.enabled() else {"ok": false, "msg": "Keine kommunalen Leitungen in dieser Welt."}
			"stromstoerung_priorisieren":
				res = sim.grid.net.prioritize_repair(town, str(a.get("trasse", "")))
			"kraftwerk_notfall":
				res = sim.plant.respond(town, str(a.get("massnahme", "")))
			"kommunal_bauen":
				res = sim.services.build(town, str(a.typ), str(a.reason), "Bürgermeister %s" % name, str(a.get("grundstueck", ""))) if sim.services != null and sim.municipal.enabled() else {"ok": false, "msg": "Keine kommunalen Dienste."}
			"kommunal_fahrzeug":
				var mf: Dictionary = sim.municipal.facilities.get(str(a.einrichtung), {})
				res = {"ok": false, "msg": "Einrichtung %s gehört nicht zu dieser Stadt." % str(a.einrichtung)} if mf.is_empty() or int(mf.town) != town \
					else sim.services.buy_vehicle(str(a.einrichtung), str(a.fahrzeug), str(a.reason), "Bürgermeister %s" % name)
			"fahrzeug_entwerfen":
				res = sim.vworks.design(town, a, "Bürgermeister %s" % name)
			"kommunal_schliessen":
				var mc: Dictionary = sim.municipal.facilities.get(str(a.einrichtung), {})
				res = {"ok": false, "msg": "Einrichtung %s gehört nicht zu dieser Stadt." % str(a.einrichtung)} if mc.is_empty() or int(mc.town) != town \
					else sim.services.close(str(a.einrichtung), str(a.reason), "Bürgermeister %s" % name)
			"regionalrat_antrag":
				res = sim.council.queue_proposal(town, str(a.art), int(a.get("partner", -1)) if a.get("partner") != null else -1, str(a.reason)) if sim.council != null and sim.council.enabled() else {"ok": false, "msg": "Kein Regionalrat."}
			"set_vision":
				if sim.civic != null and sim.civic.profiles.has(town):
					sim.civic.profiles[town].vision = str(a.vision).left(200)
					res = {"ok": true, "msg": "Neue Vision: %s" % str(a.vision).left(200)}
				else:
					res = {"ok": false, "msg": "Keine Stadtentwicklung."}
			"designate_quarter":
				res = _designate_quarter(a)
			"offer_parcels":
				res = _offer_parcels(a)
			"viertel_erschliessen":
				res = _develop_district(a)
			"stadtteil_planen":
				res = sim.town_plan.plan_district(town, a) if sim.town_plan != null else {"ok": false, "msg": "Kein Stadtplan."}
			"quartier_entwurf_waehlen":
				res = sim.town_plan.choose_design(town, a) if sim.town_plan != null else {"ok": false, "msg": "Kein Stadtplan."}
			"quartier_trasse_planen":
				res = sim.town_plan.choose_route(town, a) if sim.town_plan != null else {"ok": false, "msg": "Kein Stadtplan."}
			"grosslager_anschluss_bauen":
				res = hub_connection() if sim.wildnis else {"ok": false, "msg": "Kein Wildnis-Anschluss nötig."}
				if res.is_empty():
					res = {"ok": false, "msg": "Die Stadt ist bereits angebunden oder es gibt derzeit keine befahrbare Trasse. Prüfe die Karte und mögliche Tunnel."}
			"plan_infrastructure":
				res = _plan_infrastructure(a)
			"prioritize_road":
				res = _prioritize_road(a)
			"tender":
				res = _tender(a)
			"approve_procurement":
				res = depot().approve(str(a.order_id), "Bürgermeister %s" % name, str(a.get("reason", "")))
			"expand_depot":
				res = depot().expand(str(a.get("kind", "")), "Bürgermeister %s" % name)
			"improve_traffic":
				res = _improve_traffic(a)
			"reject_procurement":
				res = depot().reject(str(a.order_id), "Bürgermeister %s" % name, str(a.get("reason", "")))
			"assess_financing":
				res = _assess_financing(a)
			"request_credit":
				res = request_credit(float(a.betrag))
			"decide_application":
				res = _decide_application(a)
			"set_property_tax":
				res = sim.population.set_tax_rate(float(a.satz_prozent))
			"hire_staff":
				res = sim.town_hall.hire(str(a.abteilung), int(a.anzahl), "Bürgermeister %s" % name)
			"dismiss_staff":
				res = sim.town_hall.dismiss(str(a.abteilung), int(a.anzahl))
			"set_city_freight":
				res = depot().set_pool(str(a.vergabe), int(a.get("firma", -1)), int(a.get("tage", 0)), float(a.get("preisfaktor", depot().pool.price)), bool(a.get("eilig", false)))
			"repair_road":
				res = sim.road_care.order(str(a.abschnitt), str(a.ausfuehrung), str(a.get("reason", "")))
			"set_public_staff":
				res = _set_public_staff(str(a.bereich), int(a.aenderung))
			"support_training":
				res = sim.population.set_training_support(int(a.foerderung_prozent))
			"city_marketing":
				res = _city_marketing(float(a.budget))
			"decide_yard_permit":
				res = sim.estate.decide_permit(str(a.antrag), str(a.decision), str(a.get("reason", "")), "Bürgermeister %s" % name)
			"order_inspection":
				res = sim.inspections.order(int(a.firma), str(a.art), str(a.get("reason", "")))
			"mediate_rivalry":
				res = sim.rivalry.mediate(int(a.firma_a), int(a.firma_b), int(a.get("tage", 7)), "Bürgermeister %s" % name)
			"warn_company":
				res = sim.rivalry.warn(int(a.firma), "Bürgermeister %s" % name)
			"expand_power":
				res = sim.grid.expand("Bürgermeister %s" % name, self)
			"expand_harbor":
				res = harbor().expand("Bürgermeister %s" % name)
			"build_harbor":
				res = sim.eko.settle.request_transport(town, "hafen", str(a.get("reason", "Neuer Meereshafen")))
			"expand_airport":
				res = airport().expand("Bürgermeister %s" % name)
			"build_airport":
				res = sim.eko.settle.request_transport(town, "flughafen", str(a.get("reason", "Neuer Flughafen")))
			"plan_airport":
				res = plan_airport(str(a.get("strategie", "")))
			"build_station":
				res = sim.rail.request_station(town, str(a.get("reason", "Neuer Bahnhof")))
			"build_bridge":
				res = sim.access.order_city(str(a.grundstueck), "Bürgermeister %s" % name, _build_choice(a))
			"build_tunnel":
				if a.von is Array and a.nach is Array and a.von.size() >= 2 and a.nach.size() >= 2:
					res = sim.tunnels.build_city(town, Vector2i(int(a.von[0]), int(a.von[1])), Vector2i(int(a.nach[0]), int(a.nach[1])), str(a.get("reason", "")), "Bürgermeister %s" % name)
				else:
					res = {"ok": false, "msg": "von und nach brauchen jeweils [x,y]."}
			"decide_tunnel":
				var td := str(a.get("decision", "")).to_lower()
				if td in ["genehmigen", "ablehnen"]:
					res = sim.tunnels.decide(town, str(a.antrag), td == "genehmigen", str(a.get("reason", "")), "Bürgermeister %s" % name)
				else:
					res = {"ok": false, "msg": "decision muss genehmigen oder ablehnen sein."}
			"propose_regional_project":
				var mine := clampf(float(a.get("anteil_prozent", 50.0)) / 100.0, 0.0, 1.0)
				var partner := int(a.partner)
				res = sim.regional.propose(town, "verbindung", partner, {town: mine, partner: 1.0 - mine}, str(a.get("reason", "")))
			"decide_regional_project":
				var dr := str(a.get("decision", "")).to_lower()
				if dr not in ["zustimmen", "ablehnen"]:
					res = {"ok": false, "msg": "decision muss zustimmen oder ablehnen sein."}
				else:
					res = sim.regional.decide(str(a.projekt), town, dr == "zustimmen", str(a.get("reason", "")))
			"decide_mining":
				var dm := str(a.get("decision", "")).to_lower()
				if dm not in ["genehmigen", "ablehnen"]:
					res = {"ok": false, "msg": "decision muss genehmigen oder ablehnen sein."}
				else:
					res = sim.mining.decide(str(a.grundstueck), dm == "genehmigen", float(a.get("abgabe_prozent", 8.0)) / 100.0, str(a.get("reason", "")), "Bürgermeister %s" % name)
			"decide_access":
				var dec := str(a.get("decision", "")).to_lower()
				if dec not in ["genehmigen", "ablehnen"]:
					res = {"ok": false, "msg": "decision muss genehmigen oder ablehnen sein."}
				else:
					res = sim.access.decide(str(a.antrag), dec == "genehmigen", str(a.get("reason", "")), "Bürgermeister %s" % name, _build_choice(a))
			_:
				res = {"ok": false, "msg": "Unbekannte Aktion."}
	if act != "wait":
		decisions.append({"id": Towns.prefixed(town, "B", _next_dec), "day": _today(), "action": act, "reason": str(a.get("reason", "")).left(240), "ok": res.ok, "msg": str(res.msg).left(300),
			"ref": res.get("ref", ""), "args": a})
		_next_dec += 1
		if decisions.size() > 120:
			decisions.pop_front()
		sim.log_event("Bürgermeister %s: %s – %s" % [name, act, str(res.msg).left(140)], "info")
		if res.ok and act not in ["remember", "assess_financing"]:
			sim.activity.add("buergermeister", -1, "stadt", "Bürgermeister %s: %s" % [name, act], str(a.get("reason", "")), _action_cell(a))
	return res


## Ort einer Massnahme fuer die Kartenanzeige: erstes betroffenes Grundstueck, Verkehrszelle oder das Rathaus.
func _action_cell(a: Dictionary) -> Vector2i:
	var portal = a.get("von", [])
	if portal is Array and portal.size() >= 2:
		return Vector2i(int(portal[0]), int(portal[1]))
	if a.get("x") != null and a.get("y") != null:
		return Vector2i(int(a.x), int(a.y))
	var ids = a.get("parcel_ids", [])
	if ids is Array and not ids.is_empty():
		var p: Dictionary = sim.parcels.parcel(str(ids[0]))
		if p.has("rect"):
			return Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
	if sim.town_hall.building >= 0:
		return sim.city.building(sim.town_hall.building).walk
	return Vector2i(sim.city.size / 2, sim.city.size / 2)


## Stellen bei Polizei oder Aerzten/Pflege (Arbeitgeber in Citizens, Loehne aus der Stadtkasse). Besetzung zum Monatsende.
const PUBLIC_STAFF := ["polizei", "gesundheit"]
func _set_public_staff(area: String, delta: int) -> Dictionary:
	if area not in PUBLIC_STAFF:
		return {"ok": false, "msg": "bereich muss polizei oder gesundheit sein."}
	if delta == 0 or absi(delta) > 5:
		return {"ok": false, "msg": "aenderung muss zwischen -5 und +5 liegen (nicht 0)."}
	var Z: Citizens = sim.citizens
	var start := int(Z.start_cap.get(area, Z.base_cap[area]))
	var target := int(Z.base_cap[area]) + delta
	if target < 2 or target > maxi(2, start * 3):
		return {"ok": false, "msg": "Stellen bei %s müssen zwischen 2 und %d liegen (jetzt %d)." % [Citizens.EMPLOYERS[area].label, maxi(2, start * 3), int(Z.base_cap[area])]}
	var monthly := float(delta) * float(Citizens.EMPLOYERS[area].wage) * Citizens.HOURS_PER_MONTH
	if delta > 0 and available_budget() < monthly * 6.0:
		return {"ok": false, "msg": "Die verfügbare Stadtkasse (%s) deckt keine sechs Monatsgehälter (%s)." % [Catalog.money(available_budget()), Catalog.money(monthly * 6.0)]}
	Z.base_cap[area] = target
	Z.cap[area] = target
	return {"ok": true, "msg": "%s: Stellen %d -> %d (%s %s je Monat); %s zum Monatsende." % [Citizens.EMPLOYERS[area].label, target - delta, target,
		"Mehrkosten" if delta > 0 else "Einsparung", Catalog.money(absf(monthly)), "Besetzung" if delta > 0 else "Abbau"]}


## Stadtmarketing: einmalige Ausgabe (P0 -> S0), drei Monate mehr Zuzug.
func _city_marketing(budget: float) -> Dictionary:
	if budget < 5000.0 or budget > 30000.0:
		return {"ok": false, "msg": "Budget muss zwischen 5 000 und 30 000 EUR liegen."}
	var month := GameCalendar.month_of(sim.game_min)
	if month <= marketing_until:
		return {"ok": false, "msg": "Eine Kampagne läuft noch bis Monat %d." % marketing_until}
	if available_budget() < budget:
		return {"ok": false, "msg": "Verfügbare Stadtkasse (%s) reicht nicht." % Catalog.money(available_budget())}
	sim.economy.transfer(acct(), "S0", budget)
	marketing_boost = budget / 100000.0
	marketing_until = month + 2
	return {"ok": true, "msg": "Stadtmarketing für %s: +%d %% Zuzug bis Monat %d." % [Catalog.money(budget), roundi(marketing_boost * 100.0), marketing_until]}


func remember(text: String) -> void:
	notes.append({"tag": _today(), "text": text.left(240)})
	if notes.size() > MAX_NOTES:
		notes.pop_front()


func _city_parcels(ids: Array, states: Array) -> Dictionary:
	if ids.is_empty() or ids.size() > 40:
		return {"error": "Es müssen 1 bis 40 Grundstücke angegeben werden."}
	var out: Array = []
	for id in ids:
		var p: Dictionary = sim.parcels.parcel(str(id))
		if p.is_empty():
			return {"error": "Grundstück %s gibt es nicht." % id}
		if p.owner != land_owner() or not p.rights.is_empty():
			return {"error": "Grundstück %s gehört nicht der Stadt oder ist mit Rechten Dritter belastet; die Stadt darf darüber nicht verfügen." % id}
		if p.state not in states:
			return {"error": "Grundstück %s hat den Zustand %s (erforderlich: %s)." % [id, p.state, "/".join(states)]}
		out.append(p)
	return {"parcels": out}


## Kennzahlen fuer den Rat (Council.vote liest nur diese): statt des vollstaendigen Lageberichts (indicators kostet bis 800 ms;
## Ruckler bei der Ankunft eines Buergermeisters im Grosslager, Auftrag 19).
func vote_inputs() -> Dictionary:
	return {"wohnen": {"wohnungssuchende_haushalte": waiting, "leerstand": vacancy(), "mietindex": rent_index()},
		"haushalt": {"verfuegbar": available_budget()}, "arbeit": {"quote": sim.citizens.employment_rate_of(town)}}


## Ratsbeschluss fuer ein Projekt der Stadtentwicklung (Auftrag 19); Denkmaeler und Stadion als "denkmal" (Soziales skeptisch).
func civic_vote(kind: String, cost: float) -> Dictionary:
	return _proposal_vote(kind, cost, 0, 0)


## Projekt der Stadtentwicklung beim Bauamt anlegen (Status "geplant": Ausschreibung erst nach der Rueckkehr des Buergermeisters).
func add_civic_project(ref: String, parcel_ids: Array, cost: float, days: int, material: Dictionary, reason: String) -> Dictionary:
	commitments += cost
	var prj := {"id": Towns.prefixed(town, "P", _next_project), "kind": "anlage", "ref": ref, "parcels": parcel_ids, "parts": [], "cost": snappedf(cost, 1.0),
		"days": days, "material": material, "status": "geplant", "reason": reason.left(240), "day": _today(), "tender": {}}
	_next_project += 1
	projects[prj.id] = prj
	return prj


func _proposal_vote(kind: String, cost: float, units: int, area: int, zone: String = "") -> Dictionary:
	if not Council.needs_vote(kind, cost):
		return {"needed": false, "passed": true, "text": "Kein Ratsbeschluss erforderlich (Kosten %s)." % Catalog.money(cost)}
	var r := Council.vote({"kind": kind, "cost": cost, "units": units, "area": area, "zone": zone}, vote_inputs())
	return {"needed": true, "passed": r.passed, "text": Council.explain(r), "result": r}


const QUARTER_RETRY_DAYS := 10
const QUARTER_OPEN_MAX := 2        # so viele ueberwiegend unverkaufte Quartiere je Zone, bevor neue ausgewiesen werden
## Ab welchem Tag nimmt der Rat wieder Quartiersantraege dieser Zone an (nach einer Ablehnung)? Heute oder frueher = jetzt moeglich.
func quarter_ok_day(zone: String) -> int:
	var d := _today()
	for pl in plans.values():
		if pl.status == "abgelehnt" and str(pl.zone) == zone:
			d = maxi(d, int(pl.get("day", -999)) + QUARTER_RETRY_DAYS)
	return d


func _quarter_days() -> Dictionary:
	var out := {}
	for z in ["wohnen", "mischgebiet", "gewerbe", "industrie"]:
		out[z] = quarter_ok_day(z)
	return out


## Zone aus einer Angabe oder Begruendung: exakter Schluessel, sonst Wortstamm (wohn, misch, gewer/gewerb, indust); "" wenn unklar.
static func _zone_of(text: String) -> String:
	var t := text.to_lower().strip_edges()
	var first := t.split(" ")[0] if t != "" else ""
	if Parcels.ZONES.has(first):
		return first
	for stem in [["misch", "mischgebiet"], ["indust", "industrie"], ["gewer", "gewerbe"], ["wohn", "wohnen"]]:
		if t.contains(stem[0]):
			return stem[1]
	return first


## Grundstuecke, die schon zu einem beschlossenen Quartier gehoeren (ID -> true).
func _planned_ids() -> Dictionary:
	var out := {}
	for pl in plans.values():
		if pl.status == "beschlossen":
			for pid in pl.parcels:
				out[str(pid)] = true
	return out


## Beschlossene Quartiere der Zone, deren Grundstuecke noch ueberwiegend unverkauft sind: [[id, unverkauft], ...].
func open_quarters(zone: String) -> Array:
	var out: Array = []
	for pl in plans.values():
		if pl.status != "beschlossen" or str(pl.zone) != zone:
			continue
		var free_n := 0
		for pid in pl.parcels:
			var pp: Dictionary = sim.parcels.parcel(str(pid))
			if not pp.is_empty() and Towns.is_public(str(pp.owner)):
				free_n += 1
		if free_n * 2 >= int(pl.parcels.size()):
			out.append([str(pl.id), free_n])
	return out


func _designate_quarter(a: Dictionary) -> Dictionary:
	# Modelle liessen name/zone weg oder verschrieben die Zone ("gewerne"; Partie 11.11.: 90 abgelehnte Antraege) - Zone aus Text erkennen
	var zone := _zone_of(str(a.get("zone", "")) + " " + str(a.get("reason", "")))
	if a.get("name") == null or str(a.name).strip_edges() == "":
		a["name"] = "%s %d" % [Parcels.ZONES[zone].label if Parcels.ZONES.has(zone) else "Quartier", plans.size() + 1]
	if not Parcels.ZONES.has(zone) or not Parcels.ZONES[zone].buildable or zone == "oeffentlich":
		return {"ok": false, "msg": "Zone '%s' ist für ein Quartier nicht zulässig (wohnen, mischgebiet, gewerbe, industrie)." % zone}
	var chk := _city_parcels(a.parcel_ids, ["frei", "zur_entwicklung"])
	if chk.has("error"):
		return {"ok": false, "msg": chk.error}
	var covered := ""
	for pl in plans.values():
		if pl.status == "beschlossen" and pl.zone == zone and chk.parcels.all(func(p): return p.id in pl.parcels):
			covered = str(pl.id)
			break
	if covered != "":
		return {"ok": false, "msg": "Diese Grundstücke gehören bereits zum beschlossenen Quartier %s (Zone %s): kein zweites Quartier ausweisen, sondern mit offer_parcels vergeben." % [covered, zone]}
	# Der Rat entscheidet nach der Lage der Stadt, nicht nach Zuschnitt: nach einer Ablehnung ruhen Quartiersantraege einige Tage
	# (ein Modell-Buergermeister legte sonst dieselben Quartiere als "kleine" Varianten immer wieder vor).
	for pl in plans.values():
		if pl.status == "abgelehnt" and str(pl.zone) == zone and _today() - int(pl.get("day", -999)) < QUARTER_RETRY_DAYS:
			return {"ok": false, "msg": "Der Rat hat am Tag %d das Quartier '%s' abgelehnt (%s). Neue Quartiersanträge frühestens ab Tag %d – bis dahin Bestehendes entwickeln (offer_parcels, plan_infrastructure) oder die Gründe der Ablehnung angehen." % [
				int(pl.day), pl.name, str(pl.vote).left(160), int(pl.day) + QUARTER_RETRY_DAYS]}
	# Partie 14.11.: ein Modell-Buergermeister wies 38 Industrie- und 35 Gewerbegebiete aus, die alten blieben leer. Solange beschlossene
	# Quartiere der Zone noch ueberwiegend unverkauft sind, erst diese vergeben.
	var oq := open_quarters(zone)
	var open_q: Array = oq.map(func(e): return e[0])
	var unsold := 0
	for e in oq:
		unsold += int(e[1])
	if open_q.size() >= QUARTER_OPEN_MAX:
		return {"ok": false, "already": true, "msg": "Es gibt schon %d Quartiere der Zone %s mit %d unverkauften Grundstücken (%s): erst diese vergeben (offer_parcels) oder erschließen (plan_infrastructure), dann neue ausweisen." % [
			open_q.size(), zone, unsold, ", ".join(open_q.slice(0, 4))]}
	var area := 0
	for p in chk.parcels:
		area += int(p.area)
	var v := _proposal_vote("quartier", 0.0, 0, area, zone)
	var plan := {"id": Towns.prefixed(town, "Q", _next_plan), "name": str(a.name).left(60), "zone": zone, "parcels": chk.parcels.map(func(p): return p.id), "area": area,
		"status": "beschlossen" if v.passed else "abgelehnt", "reason": str(a.reason).left(240), "vote": v.text, "day": _today()}
	_next_plan += 1
	plans[plan.id] = plan
	if v.passed:
		for p in chk.parcels:
			p.zone = zone
			p.state = "zur_entwicklung"
			p.price = snappedf(float(Parcels.ZONES[zone].price) * float(p.area), 1.0)
			sim.parcels.touch(p.id)
	return {"ok": v.passed, "msg": "Quartier %s '%s' (%d Felder, %d Grundstücke): %s" % [plan.id, plan.name, area, plan.parcels.size(), v.text], "ref": plan.id}


func _offer_parcels(a: Dictionary) -> Dictionary:
	var factor := clampf(float(a.get("price_factor", 1.0)), 0.7, 1.3)
	var chk := _city_parcels(a.parcel_ids, ["frei", "zur_entwicklung"])
	if chk.has("error"):
		return {"ok": false, "msg": chk.error}
	for p in chk.parcels:
		if p.state == "zur_entwicklung" and not _in_decided_plan(p.id):
			return {"ok": false, "msg": "Grundstück %s ist nicht Teil eines beschlossenen Quartiers; erst mit designate_quarter ausweisen." % p.id}
	for p in chk.parcels:
		p.state = "frei"
		p.price = snappedf(float(p.price) * factor, 1.0)
		sim.parcels.touch(p.id)
	return {"ok": true, "msg": "%d Grundstücke zur Vergabe freigegeben (Preisfaktor %.2f)." % [chk.parcels.size(), factor], "ref": str(a.parcel_ids[0])}


func _in_decided_plan(pid: String) -> bool:
	for pl in plans.values():
		if pl.status == "beschlossen" and pid in pl.parcels:
			return true
	return false


## Auftrag 8 Stadtplanung: Viertel des Stadtplans abschnittsweise erschliessen (hoechstens DISTRICT_STEP Grundstuecke, naechste zur
## Viertelmitte zuerst). Die Grundstuecke werden zur Zone des Viertels umgewidmet; Bau und Kosten laufen ueber _plan_infrastructure.
const DISTRICT_STEP := 5


func _develop_district(a: Dictionary) -> Dictionary:
	if sim.town_plan == null or not sim.town_plan.has(town):
		return {"ok": false, "msg": "Für %s gibt es noch keinen Stadtplan." % town_label()}
	var vid := str(a.get("viertel", "")).to_upper()
	var v: Dictionary = {}
	for x in sim.town_plan.of(town).viertel:
		if str(x.id) == vid:
			v = x
	if v.is_empty():
		return {"ok": false, "msg": "Viertel %s gibt es nicht (%s)." % [vid, ", ".join((sim.town_plan.of(town).viertel as Array).map(func(x): return "%s %s" % [x.id, x.rolle]))]}
	if str(v.zone) == "gruen":
		return {"ok": false, "msg": "%s ist Grünfläche (%s) – dort wird nicht gebaut." % [vid, v.text]}
	var ctr := Vector2(int(v.mitte[0]), int(v.mitte[1]))
	var res0 := _district_streets(v, str(a.get("reason", "")))
	if not res0.is_empty():
		return res0
	var cands: Array = []
	for p in sim.parcels.items.values():
		if p.owner != land_owner() or str(p.state) != "frei" or not sim.parcels.is_buildable(p) or int(p.area) < 12:
			continue
		var c := Vector2(int(p.rect[0]) + int(p.rect[2]) / 2.0, int(p.rect[1]) + int(p.rect[3]) / 2.0)
		var d := c.distance_to(ctr)
		if d <= float(v.radius) + 4.0:
			cands.append([d, p])
	if cands.is_empty():
		return {"ok": false, "msg": "Im Viertel %s (%s) gibt es kein freies städtisches Grundstück mehr.%s" % [vid, v.text, _district_options(vid)]}
	cands.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var ids: Array = []
	var todo: Array = []
	for e in cands:
		var p: Dictionary = e[1]
		if not bool(p.erschliessung.get("strasse", false)):
			todo.append(p)
		ids.append(str(p.id))
	for p in cands.map(func(e): return e[1]).slice(0, DISTRICT_STEP * 2):
		var center := Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
		var planned_zone: String = sim.town_plan.zone_at(town, center)
		if str(p.zone) != planned_zone and planned_zone != "gruen" and str(p.zone) in ["wohnen", "mischgebiet", "gewerbe", "industrie", "oeffentlich"]:
			p.zone = planned_zone   # Nutzung der gewaehlten Komposition statt einheitlicher Viertelzone
			sim.parcels.touch(str(p.id))
	if todo.is_empty():
		return {"ok": false, "msg": "Viertel %s ist schon erschlossen (%d freie Grundstücke mit Straße) – dort kann gebaut werden.%s" % [vid, ids.size(), _district_options(vid)]}
	var step: Array = todo.slice(0, DISTRICT_STEP).map(func(p): return str(p.id))
	var res := _plan_infrastructure({"parcel_ids": step, "reason": "Viertel %s (%s): %s" % [vid, v.text, str(a.get("reason", ""))]})
	if bool(res.get("ok", false)):
		v.status = "in_erschliessung"
		sim.town_plan.revise(town, "Viertel %s (%s) wird erschlossen: %s." % [vid, v.text, ", ".join(step)])
		res.msg = "Viertel %s (%s): erster Abschnitt mit %d Grundstücken. %s" % [vid, v.text, step.size(), str(res.msg)]
	return res


## Andere Viertel, die sich noch erschliessen lassen (Hinweis bei einer Absage).
func _district_options(except: String) -> String:
	var opts: Array = []
	for v in sim.town_plan.of(town).get("viertel", []):
		if str(v.id) == except or str(v.zone) == "gruen" or str(v.status) == "erschlossen":
			continue
		opts.append("%s %s (%s, %s)" % [v.id, v.rolle, v.zone, v.status])
	return (" Noch zu erschließen: %s – Amt {aktion: {action: \"viertel_erschliessen\", viertel: \"…\"}}." % "; ".join(opts)) if not opts.is_empty() else ""


## Viertel ohne Strassen: Strassennetz nach Grundform als Erschliessungsprojekt (Kosten je Strassenfeld, Material aus dem Stadtlager,
## Baufirma). Leeres Ergebnis = Viertel hat schon Strassen oder kein Netz moeglich (dann Grundstuecks-Erschliessung wie bisher).
const STREET_CELL_COST := 320.0


func _district_streets(v: Dictionary, reason: String) -> Dictionary:
	for prj in projects.values():
		if str(prj.get("viertel", "")) == str(v.id) and str(prj.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
			var e: Dictionary = sim.construction.public.get(prj.id, {})
			return {"ok": false, "already": true, "msg": "Für Viertel %s läuft schon %s (%s)." % [v.id, prj.id, ("noch %d Tage, %s" % [int(e.days_left), str(e.get("waiting", "")) if str(e.get("waiting", "")) != "" else "es wird gebaut"]) if not e.is_empty() else str(prj.status)]}
	for prj in projects.values():   # Auftrag 8, Abschnitt 6: in Abschnitten wachsen – ein Strassennetz nach dem anderen
		if prj.has("road_plan") and str(prj.get("ref", "")) != "anschluss" and str(prj.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
			return {"ok": false, "msg": "Erst das laufende Straßennetz %s (Viertel %s) fertigstellen – die Stadt erschließt ein Viertel nach dem anderen." % [prj.id, str(prj.get("viertel", "Anschluss"))]}
	var sp: Dictionary = sim.town_plan.street_plan(town, str(v.id))
	var cells: Array = sp.cells
	if cells.is_empty():
		return {}
	var cost := snappedf(float(cells.size()) * STREET_CELL_COST + (6000.0 if sp.platz.x >= 0 else 0.0), 10.0)
	if cost > available_budget():
		return {"ok": false, "msg": "Straßennetz für Viertel %s (%d Felder) kostet %s, verfügbar %s." % [v.id, cells.size(), Catalog.money(cost), Catalog.money(available_budget())]}
	var vote := _proposal_vote("erschliessung", cost, 0, cells.size(), str(v.zone))
	if not vote.passed:
		return {"ok": false, "msg": "Rat lehnt das Straßennetz für %s ab: %s" % [v.id, vote.text]}
	commitments += cost
	var prj := {"id": Towns.prefixed(town, "P", _next_project), "kind": "erschliessung", "ref": "viertel", "parcels": [], "parts": ["strasse"],
		"cost": cost, "days": maxi(3, int(ceil(cells.size() / 8.0))), "status": "ausgeschrieben", "day": _today(), "tender": {"opened_day": _today(), "bids": [], "by": "Bauamt"},
		"material": CityDepot.material_need(["strasse"], maxi(1, int(ceil(cells.size() / 6.0)))),
		"viertel": str(v.id), "road_plan": cells.map(func(q): return [q.x, q.y]), "platz": [sp.platz.x, sp.platz.y],
		"reason": ("Viertel %s (%s): %s. %s" % [v.id, v.text, sp.text, reason]).left(240)}
	_next_project += 1
	projects[prj.id] = prj
	sim.access.invalidate_city_reservations()
	v.status = "in_erschliessung"
	sim.town_plan.revise(town, "Viertel %s (%s): %s beschlossen (%s, %d Felder)." % [v.id, v.text, sp.text, prj.id, cells.size()])
	sim.log_event("%s: Straßennetz für Viertel %s (%s) beschlossen – %s, %d Felder, %s." % [town_label(), v.id, v.text, sp.text, cells.size(), Catalog.money(cost)], "info")
	return {"ok": true, "msg": "Projekt %s: Straßennetz für Viertel %s (%s) – %s, %d Straßenfelder, Kosten %s. %s Danach entstehen an den neuen Straßen Grundstücke der Zone %s." % [
		prj.id, v.id, v.text, sp.text, cells.size(), Catalog.money(cost), vote.text, v.zone], "project": prj.id}


## Benedikt 19.11.: Wildnis-Staedte ohne Strasse zum Grosslager bekamen 60 Tage kein Baumaterial (Stadtlager-Lieferungen
## "wartet_strasse"). Das Bauamt beschliesst den Strassenanschluss selbst: Trasse vom naechsten angebundenen Strassenfeld
## bis zum Buergeramt, Ausschreibung, Baufirma baut mit eigenem Material (nichts aus dem unerreichbaren Stadtlager).
func hub_connection() -> Dictionary:
	if not sim.town_ready(town):
		return {}
	for prj in projects.values():
		if str(prj.get("ref", "")) == "anschluss" and str(prj.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
			return {}
	var link: Dictionary = sim.eko.settle.road_link(town)
	if bool(link.get("verbunden", true)) or not link.has("von"):
		return {}
	var from := Vector2i(int(link.von[0]), int(link.von[1]))
	var to := Vector2i(int(link.bis[0]), int(link.bis[1]))
	var planned := {}   # 19.11. (fe89198): das Kern-Strassennetz reserviert seine Felder – die Anschlusstrasse darf sie kreuzen
	for p in projects.values():
		if p.has("road_plan") and str(p.status) not in ["fertig", "abgelehnt", "abgebrochen"]:
			for c in p.road_plan:
				planned[Vector2i(int(c[0]), int(c[1]))] = true
	var cells: Array = sim.eko.settle._road_between(from, to, planned).filter(func(q): return not sim.city.is_road(q) and not planned.has(q))
	if cells.is_empty():
		return _hub_tunnel(from)   # 19.11.: Bergstadt ohne ebenen Weg (Falkenwiek) – Tunnel aus dem Tunnelsystem
	return _hub_road_project(cells)


## Tunnel zum Grosslager: Vorschlag der Stadt, dessen Bergseite gegenueber an das Grosslager-Netz anschliesst
## (direkt oder ueber einen ebenen Weg zum naechsten angebundenen Strassenfeld). Danach legt hub_connection die Restsrasse.
func _hub_tunnel(linked: Vector2i) -> Dictionary:
	if sim.tunnels == null:
		return {}
	for j in sim.tunnels.items.values():
		if int(j.town) == town and str(j.status) not in ["fertig", "abgelehnt"]:
			return {}
	var hub_b: Dictionary = sim.city.building(int(sim.city.hub.get("buildings", {}).get("hauptlager", -1))) if not sim.city.hub.is_empty() else {}
	var hall: Dictionary = sim.city.building(int(sim.city.towns[town].get("town_hall", -1))) if town < sim.city.towns.size() else {}
	if hub_b.is_empty() or hall.is_empty():
		return {}
	var town_road: Vector2i = hall.road   # Falkenwiek 19.11.: Rathauszufahrt war keine Strasse, die Ortsstrasse lag 2 Felder daneben
	if not sim.city.is_road(town_road):
		for r in range(1, 7):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if not sim.city.is_road(town_road) and sim.city.is_road(hall.road + Vector2i(dx, dy)):
						town_road = hall.road + Vector2i(dx, dy)
	var best := {}
	for pr in sim.tunnels.proposals(town, 12):
		var von := Vector2i(int(pr.von[0]), int(pr.von[1]))
		var nach := Vector2i(int(pr.nach[0]), int(pr.nach[1]))
		if sim.nav.road_path(von, town_road).is_empty():
			continue   # Eingangsportal nicht mit dem eigenen Ortsnetz verbunden
		var pl: Dictionary = sim.tunnels.plan(von, nach)
		var far := nach
		if not (pl.approach as Array).is_empty():
			var last := Vector2i(int(pl.approach[-1][0]), int(pl.approach[-1][1]))
			for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				if sim.city.is_road(last + d) and last + d != von:
					far = last + d
					break
		var ok: bool = not sim.nav.road_path(far, hub_b.road).is_empty() or not sim.eko.settle._road_between(linked, far).is_empty()
		if ok and (best.is_empty() or float(pl.cost) < float(best.cost)):
			best = {"von": von, "nach": nach, "cost": float(pl.cost)}
	if best.is_empty() or float(best.cost) > available_budget():
		return {}
	var r: Dictionary = sim.tunnels.build_city(town, best.von, best.nach, "Straßenanschluss ans Großlager durch den Berg (kein ebener Weg)", "Bauamt %s" % town_label())
	if not bool(r.get("ok", false)):
		return {}
	var tj: Dictionary = sim.tunnels.items.get(str(r.get("ref", "")), {})
	if projects.has(str(tj.get("project", ""))):   # das Stadtlager ist ohne Anschluss unerreichbar: Baufirma bringt das Material mit
		projects[str(tj.project)]["material"] = {}
		projects[str(tj.project)]["ref_anschluss"] = true
	sim.log_event("%s: Bauamt beauftragt einen Tunnel zum Großlager (%s, %s) – kein ebener Straßenweg um den Berg." % [town_label(), str(r.get("ref", r.get("msg", ""))), Catalog.money(float(best.cost))], "info")
	return {"ref": "tunnel", "tunnel": r}


func _hub_road_project(cells: Array) -> Dictionary:
	var cost := snappedf(float(cells.size()) * STREET_CELL_COST, 10.0)
	if cost > available_budget():
		return {}
	commitments += cost
	var prj := {"id": Towns.prefixed(town, "P", _next_project), "kind": "erschliessung", "ref": "anschluss", "parcels": [], "parts": ["strasse"],
		"cost": cost, "days": maxi(3, int(ceil(cells.size() / 12.0))), "status": "ausgeschrieben", "day": _today(), "tender": {"opened_day": _today(), "bids": [], "by": "Bauamt"},
		"material": {}, "viertel": "Anschluss", "road_plan": cells.map(func(q): return [q.x, q.y]),
		"reason": "Straßenanschluss ans Großlager: ohne ihn liefert niemand Baumaterial ins Stadtlager (%d Felder)." % cells.size()}
	_next_project += 1
	projects[prj.id] = prj
	sim.access.invalidate_city_reservations()
	sim.log_event("%s: Bauamt beschließt den Straßenanschluss ans Großlager – %s, %d Felder, %s (Baufirma bringt das Material mit)." % [town_label(), prj.id, cells.size(), Catalog.money(cost)], "info")
	return prj


func _plan_infrastructure(a: Dictionary) -> Dictionary:
	var chk := _city_parcels(a.parcel_ids, ["frei", "zur_entwicklung"])
	if chk.has("error"):
		return {"ok": false, "msg": chk.error}
	# Partie 18.11.: dieselbe Erschliessung wurde viermal beauftragt, weil die laufende nicht in der Liste stand
	var ids: Array = chk.parcels.map(func(p): return str(p.id))
	for prj in projects.values():
		if str(prj.kind) == "erschliessung" and str(prj.status) in ["beschlossen", "ausgeschrieben", "beauftragt", "laufend"] and (prj.parcels as Array).any(func(id): return str(id) in ids):
			var e: Dictionary = sim.construction.public.get(prj.id, {})
			var info := ("noch %d Tage, %s" % [int(e.days_left), str(e.get("waiting", "")) if str(e.get("waiting", "")) != "" else "es wird gebaut"]) if not e.is_empty() else str(prj.status)
			return {"ok": false, "already": true, "msg": "Für diese Grundstücke läuft schon die Erschließung %s (%s). Abwarten – danach kommunal_bauen erneut." % [prj.id, info]}
	var parts: Array = []
	var wanted: Array = a.get("parts", []) if a.get("parts") is Array else []
	var cost := 0.0
	var missing_total := 0
	var per: Array = []   # [Kosten, Grundstueck]
	for p in chk.parcels:
		var pc := 0.0
		for part in Planning.UTILITY_COST_CELL:
			if not p.erschliessung.get(part, false) and (wanted.is_empty() or part in wanted):
				pc += float(Planning.UTILITY_COST_CELL[part]) * float(p.area)
				missing_total += 1
				if part not in parts:
					parts.append(part)
		if pc > 0.0:
			per.append([pc, p])
		cost += pc
	if missing_total == 0:
		return {"ok": false, "msg": "Alle gewünschten Anschlüsse liegen bereits an."}
	var staged := ""
	if cost > available_budget():
		# Partie 14.11.: 11 Mal hintereinander an den Mitteln gescheitert. In Etappen erschliessen: die guenstigsten Grundstuecke,
		# so viele die Mittel tragen.
		per.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var keep: Array = []
		var sum := 0.0
		for e in per:
			if sum + float(e[0]) > available_budget():
				break
			sum += float(e[0])
			keep.append(e[1])
		if keep.is_empty():
			return {"ok": false, "msg": "Kosten %s übersteigen die verfügbaren Mittel %s; schon das günstigste Grundstück kostet %s. Erst Einnahmen abwarten (Grundstücksverkauf mit offer_parcels, Steuern)." % [
				Catalog.money(cost), Catalog.money(available_budget()), Catalog.money(float(per[0][0]) if not per.is_empty() else cost)]}
		staged = " Erste Etappe: %d von %d Grundstücken (Mittel reichen nicht für alle)." % [keep.size(), chk.parcels.size()]
		chk.parcels = keep
		cost = sum
	var v := _proposal_vote("erschliessung", cost, 0, 0)
	if not v.passed:
		return {"ok": false, "msg": "Erschließung (%s) abgelehnt: %s" % [Catalog.money(cost), v.text]}
	if cost > available_budget():
		return {"ok": false, "msg": "Kosten %s übersteigen die verfügbaren Mittel %s." % [Catalog.money(cost), Catalog.money(available_budget())]}
	commitments += cost
	var prj := {"id": Towns.prefixed(town, "P", _next_project), "kind": "erschliessung", "parcels": chk.parcels.map(func(p): return p.id), "parts": parts, "cost": snappedf(cost, 1.0),
		"status": "beschlossen", "vote": v.text, "reason": str(a.reason).left(240), "day": _today(), "tender": {}}
	_next_project += 1
	projects[prj.id] = prj
	for p in chk.parcels:
		sim.parcels.mark(p.id, p.state, p.application)
	return {"ok": true, "msg": "Projekt %s: Erschließung (%s) für %d Grundstücke, %s reserviert. %s%s" % [prj.id, ", ".join(parts), prj.parcels.size(), Catalog.money(cost), v.text, staged], "ref": prj.id}


func _prioritize_road(a: Dictionary) -> Dictionary:
	var p: Dictionary = sim.parcels.parcel(str(a.corridor_id))
	if p.is_empty() or p.zone != "korridor":
		return {"ok": false, "msg": "%s ist kein Korridor für Straßen und Leitungen." % a.corridor_id}
	var prio := clampi(int(a.priority), 1, 5)
	for prj in projects.values():
		if prj.kind == "strasse" and prj.parcels == [p.id]:
			prj.priority = prio
			return {"ok": true, "msg": "Straßenprojekt %s auf Priorität %d gesetzt." % [prj.id, prio], "ref": prj.id}
	var cost := float(Planning.UTILITY_COST_CELL.strasse) * float(p.area)
	var v := _proposal_vote("strasse", cost, 0, 0)
	if not v.passed:
		return {"ok": false, "msg": "Straßenprojekt abgelehnt: %s" % v.text}
	if cost > available_budget():
		return {"ok": false, "msg": "Kosten %s übersteigen die verfügbaren Mittel %s." % [Catalog.money(cost), Catalog.money(available_budget())]}
	commitments += cost
	var prj := {"id": Towns.prefixed(town, "P", _next_project), "kind": "strasse", "parcels": [p.id], "parts": ["strasse"], "cost": snappedf(cost, 1.0), "priority": prio,
		"status": "beschlossen", "vote": v.text, "reason": str(a.reason).left(240), "day": _today(), "tender": {}}
	_next_project += 1
	projects[prj.id] = prj
	return {"ok": true, "msg": "Projekt %s: Straße auf Korridor %s, Priorität %d, %s reserviert. %s" % [prj.id, p.id, prio, Catalog.money(cost), v.text], "ref": prj.id}


func _improve_traffic(a: Dictionary) -> Dictionary:
	var kind := str(a.kind)
	if not TrafficFlow.MEASURES.has(kind):
		return {"ok": false, "msg": "Unbekannte Massnahme %s (ampel, ladezone oder ausbau)." % kind}
	var v := _proposal_vote("verkehr", float(TrafficFlow.MEASURES[kind].cost), 0, 0)
	if not v.passed:
		return {"ok": false, "msg": "Verkehrsmaßnahme abgelehnt: %s" % v.text}
	var r: Dictionary = sim.traffic_flow.propose(kind, Vector2i(int(a.x), int(a.y)), str(a.reason))
	if r.ok:
		r.msg = "%s %s" % [r.msg, v.text]
	return r


## Netzausbau (Auftrag 14, Etappe 4): beschlossenes und sofort ausgeschriebenes Bauprojekt ohne Grundstuecke; Construction fuehrt es aus.
func add_power_project(cost: float, kw: float, by: String) -> Dictionary:
	commitments += cost
	var prj := {"id": Towns.prefixed(town, "P", _next_project), "kind": "netzausbau", "parcels": [], "parts": [], "cost": snappedf(cost, 1.0), "kw": kw,
		"status": "ausgeschrieben", "vote": "Stadtwerke", "reason": "Netzausbau (%s)" % by, "day": _today(), "tender": {"opened_day": _today(), "bids": []}}
	_next_project += 1
	projects[prj.id] = prj
	return prj


## Erschliessungsbauten (Auftrag 15, Etappe D): Wegebau ("zufahrt") oder Bruecke ("bruecke") als ausgeschriebenes Bauprojekt ohne
## Grundstuecke, mit eigener Bauzeit und eigenem Material aus dem Stadtlager. award: Direktvergabe an eine Baufirma (z. B. "C1"), sonst
## Ausschreibung (ortsansaessige Unternehmer-Baufirmen bevorzugt). Construction fuehrt aus und meldet die Fertigstellung.
func add_works_project(kind: String, ref: String, cost: float, days: int, material: Dictionary, by: String, award: String = "") -> Dictionary:
	commitments += cost
	var prj := {"id": Towns.prefixed(town, "P", _next_project), "kind": kind, "ref": ref, "parcels": [], "parts": [], "cost": snappedf(cost, 1.0),
		"days": days, "material": material.duplicate(), "status": "ausgeschrieben", "vote": "Erschließung", "reason": by, "day": _today(),
		"tender": {"opened_day": _today(), "bids": []}, "award": award}
	if kind == "bruecke":
		prj["bridge"] = ref
	_next_project += 1
	projects[prj.id] = prj
	return prj


## Bauweise aus einer Aktion: Brueckenart und Vergabe (Direktvergabe an eine Unternehmer-Baufirma).
func _build_choice(a: Dictionary) -> Dictionary:
	var c := {}
	if str(a.get("bruecke", "")) != "":
		c["variant"] = str(a.bruecke).to_lower()
	if str(a.get("vergabe", "")).to_lower() == "direkt":
		c["award"] = "C%d" % int(a.get("firma", -1))
	return c


## Beobachtung Erschliessung: offene Antraege, laufende Bauten, Brueckenarten, Unternehmer-Baufirmen, eigene Vorschlaege.
func access_indicators() -> Dictionary:
	sim.construction.sync_company_builders()
	var firms: Array = []
	for bid in sim.construction.builders:
		var b: Dictionary = sim.construction.builders[bid]
		if b.has("company"):
			firms.append({"firma": int(b.company), "name": b.name, "status": b.status, "kapazitaet": int(b.capacity), "auslastung": sim.construction.load_of(bid)})
	var kinds := {}
	for v in Bridges.ORDER:
		var d: Dictionary = Bridges.VARIANTS[v]
		kinds[v] = {"max_spannweite": int(d.max_span), "traegt_t": int(d.last_t), "kosten_grund": int(d.base), "kosten_je_feld": int(d.cell)}
	return {"antraege": sim.access.pending().filter(func(x): return _mine(str(x.grundstueck))), "laufend": sim.access.summary().filter(func(j): return j.status == "im_bau"), "bruecken": sim.bridges.summary().bruecken,
		"brueckenarten": kinds, "baufirmen": firms, "vorschlaege": sim.bridges.proposals()}


func _tender(a: Dictionary) -> Dictionary:
	var prj: Dictionary = projects.get(str(a.project_id), {})
	if prj.is_empty():
		return {"ok": false, "msg": "Projekt %s gibt es nicht." % a.project_id}
	if prj.status != "beschlossen":
		return {"ok": false, "msg": "Projekt %s: %s Nur beschlossene Projekte werden ausgeschrieben." % [prj.id, status_hint(prj)]}
	prj.status = "ausgeschrieben"
	prj.tender = {"opened_day": _today(), "bids": []}
	return {"ok": true, "msg": "Projekt %s ausgeschrieben (Budget %s)." % [prj.id, Catalog.money(float(prj.cost))], "ref": prj.id}


func _assess_financing(a: Dictionary) -> Dictionary:
	var prj: Dictionary = projects.get(str(a.get("project_id", "")), {})
	if prj.is_empty():   # ohne (gueltige) project_id: Uebersicht statt Fehler (Partie 16.11.: Buergermeisterin vergass das Feld)
		var open: Array = []
		for p in projects.values():
			if str(p.status) not in ["fertig", "abgelehnt"]:
				open.append("%s %s (%s)" % [p.id, str(p.get("name", p.get("kind", ""))), p.status])
		return {"ok": true, "msg": "Kasse %s, reserviert %s, verfügbar %s. Offene Projekte: %s." % [Catalog.money(cash()), Catalog.money(commitments),
			Catalog.money(available_budget()), ", ".join(open.slice(-8)) if not open.is_empty() else "keine"]}
	return {"ok": true, "msg": "Projekt %s: Kosten %s, %s Reserviert %s, verfügbar %s, Kasse %s." % [prj.id, Catalog.money(float(prj.cost)), status_hint(prj),
		Catalog.money(commitments), Catalog.money(available_budget()), Catalog.money(cash())]}


## Was bedeutet der Projektstatus und ist etwas zu tun? (Partie 16.11.: "beauftragt" wurde als Fehler gelesen, ~20 Schritte vergeudet)
func status_hint(prj: Dictionary) -> String:
	match str(prj.status):
		"geplant":
			return "Status geplant – noch nicht beschlossen."
		"beschlossen":
			return "Status beschlossen – jetzt ausschreiben (tender)."
		"ausgeschrieben":
			return "Status ausgeschrieben – Baufirmen bieten, die Vergabe läuft automatisch. Nichts zu tun."
		"beauftragt", "laufend":
			var run: Dictionary = sim.construction.public.get(str(prj.id), {}) if sim.construction != null else {}
			var firm := str(sim.construction.builders.get(str(prj.get("builder", "")), {}).get("name", "eine Baufirma")) if sim.construction != null else "eine Baufirma"
			var rest := (" Noch etwa %d Tage." % int(run.days_left)) if run.has("days_left") else ""
			return "Status %s – %s baut, alles in Ordnung, kein Handlungsbedarf.%s" % [prj.status, firm, rest]
		"fertig":
			return "Status fertig."
	return "Status %s." % prj.status


## Liegt das Grundstueck im eigenen Verwaltungsgebiet? (Region; Einzelstadt: immer)
func _mine(pid: String) -> bool:
	return sim.towns == null or not sim.towns.is_region() or sim.towns.of_parcel(pid) == town


## Region: Nachbarstaedte (knapp), offene Gemeinschaftsprojekte zur eigenen Entscheidung, eigene laufende.
func _region_obs() -> Dictionary:
	if sim.towns == null or not sim.towns.is_region():
		return {}
	var me: String = sim.towns.name_of(town)
	return {"stadt": me, "nachbarn": sim.towns.summary().filter(func(t): return int(t.id) != town).map(func(t): return {"id": t.id, "name": t.name, "buergermeister": t.buergermeister, "verfuegbar": t.verfuegbar}),
		"gemeinschaftsprojekte_offen": sim.regional.pending_for(town),
		"direkt_verbunden": sim.regional.linked(town).map(func(k): return sim.towns.name_of(k)),
		"ohne_direkte_strasse": range(sim.towns.count()).filter(func(k): return k != town and k not in sim.regional.linked(town)).map(func(k): return {"id": k, "name": sim.towns.name_of(k),
			"entfernung": absi(sim.towns.get_t(k).center.y - sim.towns.get_t(town).center.y) + absi(sim.towns.get_t(k).center.x - sim.towns.get_t(town).center.x)}),
		"gemeinschaftsprojekte": sim.regional.summary().filter(func(r): return me in str(r.verbindung))}


func _own_mining() -> Dictionary:
	var m: Dictionary = sim.mining.summary()
	m.abbauantraege = m.abbauantraege.filter(func(x): return _mine(str(x.grundstueck)))
	return m


## Betriebsgenehmigung des Bauamts fuer einen neuen Betrieb im eigenen Gebiet (Auftrag 17: die Stadt der Lage entscheidet, auch wenn die
## Firma anderswo registriert ist). Regel: kein Betrieb auf Gruen-/Korridorflaechen, keine Industrie im Wohn- oder Mischgebiet.
const INDUSTRY := ["bergwerk", "kokerei", "stahlwerk", "elektrostahlwerk", "schlachthof", "moebelwerk"]
func business_permit(cid: int, parcel: Dictionary, branch: String) -> Dictionary:
	var zone := str(parcel.get("zone", ""))
	var ok := zone not in ["gruen", "korridor"] and not (branch in INDUSTRY and zone in ["wohnen", "mischgebiet"])
	# Bergwerk: das genehmigte Abbaurecht dieser Firma auf genau dieser Lagerstaette ist die Genehmigung (das Bergwerk kann nur dort stehen;
	# vorher lehnte das Bauamt Lagerstaetten im Wohngebiet immer wieder ab und die Kette blieb stehen)
	var pm: Dictionary = sim.mining.permits.get(str(parcel.get("id", "")), {})
	if branch == "bergwerk" and not pm.is_empty() and pm.status == "genehmigt" and int(pm.cid) == cid:
		ok = true
	var who: String = sim.company(cid).company_name if sim.company(cid) != null else "C%d" % cid
	var foreign: bool = sim.company(cid) != null and int(sim.company(cid).home_town) != town
	var msg := "Bauamt %s %s %s für %s auf %s (%s%s)." % [town_label(), "genehmigt" if ok else "lehnt ab:", Businesses.branches().get(branch, {}).get("label", branch), who,
		str(parcel.get("id", "")), Parcels.ZONES.get(zone, {}).get("label", zone), ", auswärtige Firma" if foreign else ""]
	decisions.append({"id": Towns.prefixed(town, "B", _next_dec), "day": _today(), "action": "betriebsgenehmigung", "reason": "Zone %s" % zone, "ok": ok, "msg": msg,
		"ref": str(parcel.get("id", "")), "args": {"firma": cid, "branche": branch}})
	_next_dec += 1
	if decisions.size() > 120:
		decisions.pop_front()
	return {"ok": ok, "msg": msg}


## Zustaendigkeit (Auftrag 17, Abschnitt 13): Entscheidungen ueber Antraege, Grundstuecke, Zufahrten und Verkehrsflaechen nur im eigenen
## Gebiet. Gibt eine Begruendung zurueck, wenn die Aktion ein fremdes Gebiet betrifft, sonst "".
func foreign_target(a: Dictionary) -> String:
	if sim.towns == null or not sim.towns.is_region():
		return ""
	var t := -1
	match str(a.get("action", "")):
		"decide_application":
			t = sim.towns.of_parcel(str(sim.permits.apps.get(str(a.get("application_id", "")), {}).get("parcel", "")))
		"decide_mining", "build_bridge":
			t = sim.towns.of_parcel(str(a.get("grundstueck", "")))
		"decide_access":
			t = sim.towns.of_parcel(str(sim.access.jobs.get(str(a.get("antrag", "")), {}).get("parcel", "")))
		"build_tunnel":
			var portal = a.get("von", [])
			if portal is Array and portal.size() >= 2:
				t = sim.towns.of_cell(Vector2i(int(portal[0]), int(portal[1])))
		"decide_tunnel":
			t = int(sim.tunnels.items.get(str(a.get("antrag", "")), {}).get("town", -1))
		"improve_traffic":
			t = sim.towns.of_cell(Vector2i(int(a.get("x", 0)), int(a.get("y", 0))))
	if t < 0 or t == town:
		return ""
	return "Nicht zuständig: das Ziel liegt im Gebiet von %s; dort entscheidet Bürgermeister %s." % [sim.towns.name_of(t), sim.towns.mayor(t).name]


func _decide_application(a: Dictionary) -> Dictionary:
	var aid := str(a.application_id)
	var site: Dictionary = sim.eko.homes.sites.get(aid, {}) if sim.eko != null else {}
	if not site.is_empty() and str(site.get("app", "")) != "":   # 19.11.: Petra Engel nannte die Baustelle (BS14) statt des Antrags
		aid = str(site.app)
	var app: Dictionary = sim.permits.apps.get(aid, {})
	if app.is_empty():
		return {"ok": false, "msg": "Antrag %s gibt es nicht. Entscheidbare Anträge stehen in bauantraege.zur_entscheidung (IDs wie A12)." % a.application_id}
	if app.status != "zur_entscheidung":
		var stage := {"beantragt": "ist eingereicht und wartet auf das Bauamt", "in_pruefung": "wird vom Bauamt geprüft",
			"rueckfrage": "wartet auf eine Rückfrage beim Antragsteller", "entschieden": "ist bereits entschieden (%s)" % str(app.get("decision", ""))}
		return {"ok": false, "msg": "Antrag %s%s %s – erst wenn das Bauamt ihn vorlegt, steht er in bauantraege.zur_entscheidung." % [
			aid, (" (Baustelle %s)" % a.application_id) if aid != str(a.application_id) else "", stage.get(str(app.status), "hat Status " + str(app.status))]}
	var extra: Array = a.get("conditions", []) if a.get("conditions") is Array else []
	return sim.permits.mayor_decide(aid, str(a.decision), str(a.reason), extra, "Bürgermeister %s" % name)


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	return {"name": name, "party": party, "term_start_day": term_start_day, "approval": approval, "stock_units": stock_units, "waiting": waiting, "plans": plans,
		"projects": projects, "decisions": decisions, "notes": notes, "commitments": commitments, "elections": elections, "pop_history": pop_history, "grants_total": grants_total, "grant_last": grant_last, "growth_history": growth_history,
		"credit_debt": credit_debt, "credit_total": credit_total, "credit_repaid": credit_repaid, "credit_last_day": credit_last_day,
		"airport_goal": airport_goal, "airport_target_cost": airport_target_cost, "airport_reservation": airport_reservation, "airport_financing_mode": airport_financing_mode,
		"town": town, "next": [_next_plan, _next_project, _next_dec], "marketing": [marketing_boost, marketing_until], "arrival_acc": _arrival_acc}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	town = int(d.get("town", town))
	name = str(d.get("name", name))
	party = str(d.get("party", party))
	term_start_day = int(d.get("term_start_day", 0))
	approval = float(d.get("approval", 55.0))
	stock_units = int(d.get("stock_units", stock_units))
	waiting = int(d.get("waiting", 0))
	plans = d.get("plans", {})
	projects = d.get("projects", {})
	for p in projects.values():   # 19.11.: Stadtwerke-Projekte nannten den Anzeigenamen "betonbauteile" statt des Artikels "beton"
		if p.get("material") is Dictionary and p.material.has("betonbauteile"):
			p.material["beton"] = int(p.material.get("beton", 0)) + int(p.material.betonbauteile)
			p.material.erase("betonbauteile")
	decisions = d.get("decisions", [])
	notes = d.get("notes", [])
	commitments = float(d.get("commitments", 0.0))
	elections = d.get("elections", [])
	pop_history = d.get("pop_history", pop_history)
	grants_total = float(d.get("grants_total", 0.0))
	grant_last = float(d.get("grant_last", 0.0))
	credit_debt = float(d.get("credit_debt", 0.0))
	credit_total = float(d.get("credit_total", 0.0))
	credit_repaid = float(d.get("credit_repaid", 0.0))
	credit_last_day = int(d.get("credit_last_day", -999))
	airport_goal = bool(d.get("airport_goal", false))
	airport_target_cost = float(d.get("airport_target_cost", 0.0))
	airport_reservation = float(d.get("airport_reservation", 0.0))
	airport_financing_mode = str(d.get("airport_financing_mode", "sparen"))
	growth_history = d.get("growth_history", [])
	_arrival_acc = float(d.get("arrival_acc", 0.0))
	var mk: Array = d.get("marketing", [0.0, -1])
	marketing_boost = float(mk[0])
	marketing_until = int(mk[1])
	var nx: Array = d.get("next", [1, 1, 1])
	_next_plan = int(nx[0])
	_next_project = int(nx[1])
	_next_dec = int(nx[2])
