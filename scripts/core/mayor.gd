class_name Mayor
extends RefCounted
## Buergermeister-Rolle (Auftrag 7, Etappe 3). Die Rolle hat eine eigene Beobachtung (`indicators`), eigene Aktionen (`execute`),
## ein eigenes Gedaechtnis und Entscheidungsprotokoll. Ob ein Sprachmodell (MayorAgent) oder die Regeln (MayorBrain) entscheiden,
## aendert nichts: die Engine prueft Zustaendigkeit, Budget, Flaechenverfuegbarkeit und Ratsbeschluss. Es gibt keinen Welteditor.

const SCHEMA := {
	"wait": {"params": {}, "desc": "Nichts tun."},
	"kommunal_bauen": {"params": {"typ": "string", "reason": "string"},
		"desc": "Kommunale Einrichtung neu bauen (Auftrag 20): typ FW-01 Feuerwache|RW-01 Rettungswache|KH-01 Krankenhaus|BH-01 Bauhof|VB-01 Busbetriebshof|SC-01 Schule|KI-01 Kita|RC-01 Recyclinghof. Ratsbeschluss, Ausschreibung, Baufirma; Kosten und Bedarf siehe obs.kommunale_dienste."},
	"kommunal_fahrzeug": {"params": {"einrichtung": "string", "fahrzeug": "string", "reason": "string"},
		"desc": "Fahrzeug für eine Einrichtung kaufen (einrichtung = ID M<n>, fahrzeug HLF 20|DLK 23|RTW|NEF|Kipper|Streuwagen|Linienbus|Wertstoffwagen)."},
	"kommunal_schliessen": {"params": {"einrichtung": "string", "reason": "string"}, "desc": "Kommunale Einrichtung schließen (Personal frei, keine Kosten mehr)."},
	"regionalrat_antrag": {"params": {"art": "string", "partner": "int?", "reason": "string"},
		"desc": "Antrag für die nächste Sitzung des Regionalrats: art verbindung (mit partner = Stadt-Nr.)|kh_ausbau|drehleiter|zweckverband. Mehrheit 3 von 4, Eigentumsfragen einstimmig; Kraftwerksanteile bleiben 25/25/25/25."},
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
	"assess_financing": {"params": {"project_id": "string"}, "desc": "Finanzierungsbedarf eines Projekts oder Plans bewerten (nur Auskunft)."},
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
	"expand_airport": {"params": {"reason": "string"},
		"desc": "Flughafen eine Stufe ausbauen (obs.flughafen.ausbau: Ziel, Plaetze, Fracht je Flug, Kosten, Tage): Stadtprojekt, eine Baufirma baut mit Material aus dem Stadtlager. Danach mehr Passagiere und mehr Frachtplatz je Flug, hoechere Abfertigungsgebuhr. Sinnvoll, wenn obs.flughafen.rueckstau_fluege ueber 1 liegt (Luftfracht wartet auf mehrere Fluege)."},
	"warn_company": {"params": {"firma": "int", "reason": "string"},
		"desc": "Firma öffentlich verwarnen (nur wenn sie in den letzten 7 Tagen eskaliert hat, siehe obs.rivalitaet.verursacher): Ruf −2, für 10 Tage kostet jede weitere Eskalation zusätzlich Ruf."},
	"build_bridge": {"params": {"grundstueck": "string", "bruecke": "string?", "vergabe": "string?", "firma": "int?", "reason": "string"},
		"desc": "Die Stadt ausbauen: städtisches Grundstück jenseits von Fluss oder See erschließen (obs.erschliessung.vorschlaege), Weg und Brücke ganz aus der Stadtkasse. bruecke holz | stein | stahlbeton (muss Spannweite und Last schaffen, siehe brueckenarten; Standard die günstigste passende). vergabe ausschreibung (Standard; ortsansässige Unternehmer-Baufirmen bevorzugt) | direkt mit firma = Firmen-ID einer Unternehmer-Baufirma (obs.erschliessung.baufirmen), damit die Firma den Auftrag bekommt. Bis zur Abnahme gesperrt."},
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
	if waiting <= 0:
		return
	var free: Array = town_units().filter(func(u): return u.tenant == "")
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
	return maxf(0.0, cash() - reserve_cash() - commitments)


## Mindestreserve nach Ortsgroesse: 20 000 EUR + 80 EUR je Einwohner, hoechstens RESERVE_CASH (die grosse Stadt bleibt bei 100 000).
func reserve_cash() -> float:
	return minf(RESERVE_CASH, 20000.0 + 80.0 * float(sim.citizens.population_of(town)))


## Landeszuweisung (Strukturfoerderung) fuer kleine Orte: monatlich, faellt mit wachsender Einwohnerzahl weg (ab GRANT_UNTIL).
const GRANT_BASE := 14000.0
const GRANT_UNTIL := 500
var grants_total := 0.0
var grant_last := 0.0
func _state_grant() -> void:
	var pop: int = sim.citizens.population_of(town)
	grant_last = 0.0
	if pop >= GRANT_UNTIL:
		return
	grant_last = snappedf(GRANT_BASE * (1.0 - float(pop) / float(GRANT_UNTIL)), 10.0)
	sim.economy.transfer("X0", acct(), grant_last)
	grants_total += grant_last
	sim.log_event("Landeszuweisung für %s: %s (Strukturförderung kleiner Orte, %d Einwohner)." % [town_label(), Catalog.money(grant_last), pop], "info")


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
			pending.append({"id": a.id, "antragsteller": a.applicant, "grundstueck": a.parcel, "art": Planning.DEFS[a.def].label, "geschosse": a.floors,
				"einheiten": pre.units, "kosten_gesamt": pre.costs.get("gesamt", 0.0), "vorpruefung_ok": pre.ok, "ablehnungsgruende": pre.blocking,
				"offene_punkte": pre.questions, "auflagen": pre.conditions.map(func(c): return c.text), "rueckfragen_bisher": int(a.get("mayor_queries", 0))})
	var trend := 0
	if pop_history.size() >= 2:
		trend = int(pop_history[-1]) - int(pop_history[-2])
	return {
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
		"arbeit": {"quote": snappedf(Z.employment_rate_of(town), 0.001), "arbeitslos": Z.unemployed_of(town), "offene_stellen": vac_jobs,
			"offene_stellen_nach_arbeitgeber": by_vac},
		"gewerbe": {"freie_gewerbeflaeche": free_by_zone.get("gewerbe", {}), "freie_industrieflaeche": free_by_zone.get("industrie", {}),
			"nachfrage_stellen_baufirma_industrie": int(by_vac.get("baufirma", 0)) + int(by_vac.get("industrie", 0))},
		"verkehr": _traffic_indicators(jams),
		"versorgung": {"freie_stadtgrundstuecke": free_n, "davon_voll_erschlossen": served,
			"anteil_voll_erschlossen": snappedf(float(served) / maxf(1.0, float(free_n)), 0.01)},
		"haushalt": {"kasse": snappedf(cash(), 1.0), "reserviert": snappedf(commitments, 1.0), "verfuegbar": snappedf(available_budget(), 1.0),
			"steuern_gesamt": snappedf(sim.public_sector.tax_total + sim.public_sector.social_total + sim.public_sector.corporate_total, 1.0),
			"defizit": cash() < reserve_cash(), "mindestreserve": int(reserve_cash()), "landeszuweisung_monat": int(grant_last),
			"hinweis": "verfuegbar = Kasse - Mindestreserve - reserviert. Ist verfuegbar 0, scheitert jede Ausgabe: dann Grundstücke verkaufen (offer_parcels), Grundsteuer anpassen oder warten."},
		"bauantraege": {"warteschlange": sim.permits.queue().size(), "zur_entscheidung": queue_ids, "zur_entscheidung_details": pending, "kapazitaet_je_tag": snappedf(sim.permits.capacity(), 0.1)},
		"plaene": plans.values().map(func(p): return {"id": p.id, "name": p.name, "status": p.status, "grundstuecke": p.parcels.size(), "zone": p.zone, "tag": int(p.get("day", 0)),
			"ratsbegruendung": str(p.get("vote", "")).left(200) if p.status == "abgelehnt" else "",
			"ids_zur_entwicklung": p.parcels.filter(func(id): return sim.parcels.parcel(id).get("state", "") == "zur_entwicklung").slice(0, MAX_CLUSTER),
			"ids_ohne_anschluss": p.parcels.filter(func(id): return sim.parcels.parcel(id).get("state", "") in ["frei", "zur_entwicklung"] and sim.parcels.utility_level(sim.parcels.parcel(id)) != "voll").slice(0, MAX_CLUSTER),
			"naechster_schritt": "plan_infrastructure mit ids_ohne_anschluss (baut Straße und Anschlüsse)" if p.status == "beschlossen" else ""}),
		"projekte": projects.values().map(func(p): return {"id": p.id, "art": p.kind, "status": p.status, "kosten": p.cost, "prioritaet": p.get("priority", 0), "grundstuecke": p.parcels.slice(0, MAX_CLUSTER)}),
		"stadtlager": stadtlager_indicators(),
		"entwicklungsvorschlaege": quarter_candidates(3),
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
		"erschliessung": access_indicators(),
		"bergbau": _own_mining(),
		"region": _region_obs(),
		"hafen": harbor().summary() if harbor().enabled else {},
		"flughafen": airport().summary() if airport().enabled else {},
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
			props.append({"id": o.id, "artikel": CityGoods.get_item(o.item).name, "menge": o.qty, "kritikalitaet": o.crit, "grund": o.reason, "geschaetzte_kosten": snappedf(float(q[0].total) if not q.is_empty() else 0.0, 1.0),
				"anbieter": q[0].name if not q.is_empty() else "", "tage_offen": _today() - int(o.day), "entscheidung": o.get("decision", ""),
				"projekt": str(o.get("project", ""))})
	# Material laufender Projekte zuerst: der Buergermeister hat pro Runde nur wenige Aktionen, und jedes offene
	# Projektmaterial muss genehmigt werden, bevor der Bauschritt laeuft (sonst stauen Routineeinkaeufe die Projekte aus).
	props.sort_custom(func(a, b): return (str(a.projekt) != "" and str(b.projekt) == "") or (str(a.projekt) != "" and str(b.projekt) != "" and int(a.kritikalitaet) > int(b.kritikalitaet)))
	return {"rampen": D.ramps, "rampen_frei": D.ramps_free(), "lkw_wartezeiten_letzte_10_tage": D.recent_waits(), "rueckstau_wareneingang_einheiten": D.backlog_units(),
		"personal_verfuegbar": D.available_staff(), "personal_gesamt": D.roster().size(), "kapazitaet_wareneingang_je_tag": D.dock_capacity(), "gabelstapler": D.forklifts(),
		"laufende_kosten_monat": snappedf(float(D.running_costs().summe), 1.0), "blockaden": D.current_tasks().blockers.slice(0, 4),
		"vorschlaege": props.slice(0, 8), "kritisch": D.critical_items().slice(0, 6).map(func(i): return {"artikel": i.name, "bestand": i.bestand, "mindestbestand": i.mindestbestand}),
		"bestellungen_offen": D.open_orders().size() - props.size(), "einkauf_bisher": snappedf(float(D.stats.purchases), 1.0), "transportpool": D.pool_summary()}


## Gruppen staedtischer, freier Grundstuecke (je 32x32 Felder) als Vorschlaege fuer neue Quartiere.
func quarter_candidates(limit: int) -> Array:
	var groups := {}
	for p in sim.parcels.items.values():
		if p.owner != land_owner() or p.state not in ["frei", "zur_entwicklung"] or not sim.parcels.is_buildable(p) or p.zone not in ["wohnen", "mischgebiet", "gewerbe", "industrie"]:
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
		out.append({"lage_feld": [key.x * 32, key.y * 32], "zone": zone, "flaeche": area, "grundstuecke": chosen.map(func(p): return p.id),
			"davon_voll_erschlossen": full, "entfernung_zentrum": int(Vector2(key.x * 32, key.y * 32).distance_to(Vector2(sim.city.size * 0.45, sim.city.size * 0.5)))})
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
	var total := 0
	for p in sim.parcels.items.values():
		if not sim.parcels.is_buildable(p) or not ZONE_TARGET.has(p.zone):
			continue
		area[p.zone] = int(area.get(p.zone, 0)) + int(p.area)
		total += int(p.area)
		if p.state == "frei" and p.owner == land_owner():
			free[p.zone] = int(free.get(p.zone, 0)) + int(p.area)
	var zones := {}
	var short: Array = []
	for z in ZONE_TARGET:
		var share := float(area.get(z, 0)) / maxf(1.0, float(total))
		zones[z] = {"flaeche": int(area.get(z, 0)), "frei_staedtisch": int(free.get(z, 0)), "anteil": snappedf(share, 0.01), "richtwert": ZONE_TARGET[z],
			"abweichung": snappedf(share - float(ZONE_TARGET[z]), 0.01)}
		if z != "wohnen" and share < float(ZONE_TARGET[z]) - 0.05:
			short.append(z)
	short.sort_custom(func(a, b): return float(zones[a].abweichung) < float(zones[b].abweichung))
	var props: Array = []
	var used := {}
	for z in short:
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
func execute(action: Dictionary) -> Dictionary:
	var a := ActionExecutor.normalize(action)
	var act := str(a.get("action", a.get("type", "")))
	var err := ActionExecutor.validate_against(SCHEMA, act, a)
	if err == "":
		a["action"] = act
		err = foreign_target(a)   # Region: keine Entscheidungen im Gebiet einer anderen Stadt
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
			"kommunal_bauen":
				res = sim.services.build(town, str(a.typ), str(a.reason), "Bürgermeister %s" % name) if sim.services != null and sim.municipal.enabled() else {"ok": false, "msg": "Keine kommunalen Dienste."}
			"kommunal_fahrzeug":
				var mf: Dictionary = sim.municipal.facilities.get(str(a.einrichtung), {})
				res = {"ok": false, "msg": "Einrichtung %s gehört nicht zu dieser Stadt." % str(a.einrichtung)} if mf.is_empty() or int(mf.town) != town \
					else sim.services.buy_vehicle(str(a.einrichtung), str(a.fahrzeug), str(a.reason), "Bürgermeister %s" % name)
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
			"expand_airport":
				res = airport().expand("Bürgermeister %s" % name)
			"build_bridge":
				res = sim.access.order_city(str(a.grundstueck), "Bürgermeister %s" % name, _build_choice(a))
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


func _plan_infrastructure(a: Dictionary) -> Dictionary:
	var chk := _city_parcels(a.parcel_ids, ["frei", "zur_entwicklung"])
	if chk.has("error"):
		return {"ok": false, "msg": chk.error}
	var parts: Array = []
	var wanted: Array = a.get("parts", []) if a.get("parts") is Array else []
	var cost := 0.0
	var missing_total := 0
	for p in chk.parcels:
		for part in Planning.UTILITY_COST_CELL:
			if not p.erschliessung.get(part, false) and (wanted.is_empty() or part in wanted):
				cost += float(Planning.UTILITY_COST_CELL[part]) * float(p.area)
				missing_total += 1
				if part not in parts:
					parts.append(part)
	if missing_total == 0:
		return {"ok": false, "msg": "Alle gewünschten Anschlüsse liegen bereits an."}
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
	return {"ok": true, "msg": "Projekt %s: Erschließung (%s) für %d Grundstücke, %s reserviert. %s" % [prj.id, ", ".join(parts), prj.parcels.size(), Catalog.money(cost), v.text], "ref": prj.id}


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
		return {"ok": false, "msg": "Projekt %s hat den Status %s; nur beschlossene Projekte werden ausgeschrieben." % [prj.id, prj.status]}
	prj.status = "ausgeschrieben"
	prj.tender = {"opened_day": _today(), "bids": []}
	return {"ok": true, "msg": "Projekt %s ausgeschrieben (Budget %s)." % [prj.id, Catalog.money(float(prj.cost))], "ref": prj.id}


func _assess_financing(a: Dictionary) -> Dictionary:
	var prj: Dictionary = projects.get(str(a.project_id), {})
	if prj.is_empty():
		return {"ok": false, "msg": "Projekt %s gibt es nicht." % a.project_id}
	return {"ok": true, "msg": "Projekt %s: Kosten %s, reserviert %s, verfügbar %s, Kasse %s." % [prj.id, Catalog.money(float(prj.cost)), Catalog.money(commitments),
		Catalog.money(available_budget()), Catalog.money(cash())]}


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
		"improve_traffic":
			t = sim.towns.of_cell(Vector2i(int(a.get("x", 0)), int(a.get("y", 0))))
	if t < 0 or t == town:
		return ""
	return "Nicht zuständig: das Ziel liegt im Gebiet von %s; dort entscheidet Bürgermeister %s." % [sim.towns.name_of(t), sim.towns.mayor(t).name]


func _decide_application(a: Dictionary) -> Dictionary:
	var app: Dictionary = sim.permits.apps.get(str(a.application_id), {})
	if app.is_empty() or app.status != "zur_entscheidung":
		return {"ok": false, "msg": "Antrag %s liegt der Bürgermeisterebene nicht zur Entscheidung vor." % a.application_id}
	var extra: Array = a.get("conditions", []) if a.get("conditions") is Array else []
	return sim.permits.mayor_decide(app.id, str(a.decision), str(a.reason), extra, "Bürgermeister %s" % name)


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	return {"name": name, "party": party, "term_start_day": term_start_day, "approval": approval, "stock_units": stock_units, "waiting": waiting, "plans": plans,
		"projects": projects, "decisions": decisions, "notes": notes, "commitments": commitments, "elections": elections, "pop_history": pop_history, "grants_total": grants_total, "grant_last": grant_last, "growth_history": growth_history,
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
	decisions = d.get("decisions", [])
	notes = d.get("notes", [])
	commitments = float(d.get("commitments", 0.0))
	elections = d.get("elections", [])
	pop_history = d.get("pop_history", pop_history)
	grants_total = float(d.get("grants_total", 0.0))
	grant_last = float(d.get("grant_last", 0.0))
	growth_history = d.get("growth_history", [])
	_arrival_acc = float(d.get("arrival_acc", 0.0))
	var mk: Array = d.get("marketing", [0.0, -1])
	marketing_boost = float(mk[0])
	marketing_until = int(mk[1])
	var nx: Array = d.get("next", [1, 1, 1])
	_next_plan = int(nx[0])
	_next_project = int(nx[1])
	_next_dec = int(nx[2])
