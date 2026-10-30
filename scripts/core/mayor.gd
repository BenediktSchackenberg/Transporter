class_name Mayor
extends RefCounted
## Buergermeister-Rolle (Auftrag 7, Etappe 3). Die Rolle hat eine eigene Beobachtung (`indicators`), eigene Aktionen (`execute`),
## ein eigenes Gedaechtnis und Entscheidungsprotokoll. Ob ein Sprachmodell (MayorAgent) oder die Regeln (MayorBrain) entscheiden,
## aendert nichts: die Engine prueft Zustaendigkeit, Budget, Flaechenverfuegbarkeit und Ratsbeschluss. Es gibt keinen Welteditor.

const SCHEMA := {
	"wait": {"params": {}, "desc": "Nichts tun."},
	"remember": {"params": {"inhalt": "string"}, "desc": "Eine Erfahrung oder Notiz im Gedächtnis des Amtes festhalten."},
	"designate_quarter": {"params": {"name": "string", "parcel_ids": "array", "zone": "string", "reason": "string"},
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
		"desc": "Verkehrsmaßnahme auf einem wiederkehrenden Engpass (obs.verkehr.engpaesse mit wiederkehrend=true): kind ampel (Kreuzung, 12 000 EUR, 2 Tage) oder ausbau (Straßenabschnitt, 40 000 EUR, 6 Tage, währenddessen eine Spur weniger). Ein einzelner Stau rechtfertigt keinen Ausbau."},
	"reject_procurement": {"params": {"order_id": "string", "reason": "string"}, "desc": "Beschaffungsvorschlag ablehnen (Begründung nötig, z. B. Budget oder kein Bedarf)."},
	"assess_financing": {"params": {"project_id": "string"}, "desc": "Finanzierungsbedarf eines Projekts oder Plans bewerten (nur Auskunft)."},
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
var _next_plan := 1
var _next_project := 1
var _next_dec := 1


func setup(simulation) -> void:
	sim = simulation
	sim.month_changed.connect(on_month)


## Anfangszustand nach Erzeugung der Stadt: Wohnungsbestand passt zur Bevoelkerung (3 % Leerstand).
func start() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.city.seed_value) + 31337
	name = "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]
	party = Council.SEATS.keys()[rng.randi() % 3]
	stock_units = int(ceil(float(sim.citizens.population()) / PERSONS_PER_UNIT * (1.0 + BASE_VACANCY)))
	pop_history = [sim.citizens.population()]


# ------------------------------------------------------------------ Kennzahlen
func occupied_units() -> int:
	return mini(stock_units, int(round(float(sim.citizens.population()) / PERSONS_PER_UNIT)))


func vacancy() -> float:
	return float(stock_units - occupied_units()) / maxf(1.0, float(stock_units))


## Mietniveau relativ (100 = ausgeglichener Markt): steigt bei wartenden Haushalten, sinkt bei Leerstand.
func rent_index() -> float:
	return clampf(100.0 + 400.0 * float(waiting) / maxf(1.0, float(stock_units)) - 300.0 * (vacancy() - BASE_VACANCY), 70.0, 160.0)


func available_budget() -> float:
	return maxf(0.0, float(sim.economy.accounts.P0) - RESERVE_CASH - commitments)


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
		if p.state == "frei" and sim.parcels.is_buildable(p) and p.owner == Parcels.CITY:
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
		if a.status == "zur_entscheidung":
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
		"bevoelkerung": {"einwohner": Z.population(), "veraenderung_letzter_monat": trend},
		"wohnen": {"bestand_einheiten": stock_units, "belegt": occupied_units(), "leerstand": snappedf(vacancy(), 0.001),
			"wohnungssuchende_haushalte": waiting, "mietindex": snappedf(rent_index(), 0.1), "miete_monat": snappedf(rent, 1.0),
			"bezahlbarkeit_miete_anteil_netto": snappedf(rent / maxf(1.0, net_wage), 0.01)},
		"arbeit": {"quote": snappedf(Z.employment_rate(), 0.001), "arbeitslos": Z.unemployed_total(), "offene_stellen": vac_jobs,
			"offene_stellen_nach_arbeitgeber": by_vac},
		"gewerbe": {"freie_gewerbeflaeche": free_by_zone.get("gewerbe", {}), "freie_industrieflaeche": free_by_zone.get("industrie", {}),
			"nachfrage_stellen_baufirma_industrie": int(by_vac.get("baufirma", 0)) + int(by_vac.get("industrie", 0))},
		"verkehr": _traffic_indicators(jams),
		"versorgung": {"freie_stadtgrundstuecke": free_n, "davon_voll_erschlossen": served,
			"anteil_voll_erschlossen": snappedf(float(served) / maxf(1.0, float(free_n)), 0.01)},
		"haushalt": {"kasse": snappedf(float(sim.economy.accounts.P0), 1.0), "reserviert": snappedf(commitments, 1.0), "verfuegbar": snappedf(available_budget(), 1.0),
			"steuern_gesamt": snappedf(sim.public_sector.tax_total + sim.public_sector.social_total + sim.public_sector.corporate_total, 1.0),
			"defizit": float(sim.economy.accounts.P0) < RESERVE_CASH},
		"bauantraege": {"warteschlange": sim.permits.queue().size(), "zur_entscheidung": queue_ids, "zur_entscheidung_details": pending, "kapazitaet_je_tag": snappedf(sim.permits.capacity(), 0.1)},
		"plaene": plans.values().map(func(p): return {"id": p.id, "name": p.name, "status": p.status, "grundstuecke": p.parcels.size(), "zone": p.zone,
			"ids_zur_entwicklung": p.parcels.filter(func(id): return sim.parcels.parcel(id).get("state", "") == "zur_entwicklung").slice(0, MAX_CLUSTER)}),
		"projekte": projects.values().map(func(p): return {"id": p.id, "art": p.kind, "status": p.status, "kosten": p.cost, "prioritaet": p.get("priority", 0), "grundstuecke": p.parcels.slice(0, MAX_CLUSTER)}),
		"stadtlager": stadtlager_indicators(),
		"entwicklungsvorschlaege": quarter_candidates(3),
		"planungsregeln": ["wohnen", "mischgebiet", "gewerbe", "industrie"].map(func(z): return Planning.rules(z)),
		"gedaechtnis": notes.slice(-6),
		"entscheidungen_zuletzt": decisions.slice(-4).map(func(d): return {"tag": d.day, "aktion": d.action, "ok": d.ok, "ergebnis": d.msg.left(120)}),
	}


## Verkehr: Mengen, Zeitverlust, wiederkehrende Engpaesse und laufende bzw. fertige Massnahmen mit Vorher/Nachher.
func _traffic_indicators(jams: int) -> Dictionary:
	var T: TrafficFlow = sim.traffic_flow
	var busy := {}
	for m in T.measures.values():
		busy[m.cell] = m.status
	var spots: Array = []
	for h in T.hotspots(5):
		spots.append({"x": h.cell.x, "y": h.cell.y, "verlorene_fahrzeugsekunden": snappedf(h.lost, 1.0), "tage_mit_stau": h.days, "wiederkehrend": h.recurring,
			"kreuzung": T.is_junction(h.cell), "kapazitaet": T.capacity_of(h.cell), "massnahme": busy.get(h.cell, "")})
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
	var D: CityDepot = sim.city_depot
	var props: Array = []
	for o in D.orders.values():
		if o.status == "vorschlag":
			var q := D.quote(o.item, int(o.qty), int(o.crit))
			props.append({"id": o.id, "artikel": CityGoods.get_item(o.item).name, "menge": o.qty, "kritikalitaet": o.crit, "grund": o.reason, "geschaetzte_kosten": snappedf(float(q[0].total) if not q.is_empty() else 0.0, 1.0),
				"anbieter": q[0].name if not q.is_empty() else "", "tage_offen": _today() - int(o.day), "entscheidung": o.get("decision", "")})
	return {"rampen": D.ramps, "rampen_frei": D.ramps_free(), "lkw_wartezeiten_letzte_10_tage": D.recent_waits(), "rueckstau_wareneingang_einheiten": D.backlog_units(),
		"personal_verfuegbar": D.available_staff(), "personal_gesamt": D.roster().size(), "kapazitaet_wareneingang_je_tag": D.dock_capacity(), "gabelstapler": D.forklifts(),
		"laufende_kosten_monat": snappedf(float(D.running_costs().summe), 1.0), "blockaden": D.current_tasks().blockers.slice(0, 4),
		"vorschlaege": props.slice(0, 8), "kritisch": D.critical_items().slice(0, 6).map(func(i): return {"artikel": i.name, "bestand": i.bestand, "mindestbestand": i.mindestbestand}),
		"bestellungen_offen": D.open_orders().size() - props.size(), "einkauf_bisher": snappedf(float(D.stats.purchases), 1.0)}


## Gruppen staedtischer, freier Grundstuecke (je 32x32 Felder) als Vorschlaege fuer neue Quartiere.
func quarter_candidates(limit: int) -> Array:
	var groups := {}
	for p in sim.parcels.items.values():
		if p.owner != Parcels.CITY or p.state not in ["frei", "zur_entwicklung"] or not sim.parcels.is_buildable(p) or p.zone not in ["wohnen", "mischgebiet", "gewerbe"]:
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


# ------------------------------------------------------------------ Monatslauf, Wohnungsmarkt, Wahl
func on_month(month: int) -> void:
	var Z: Citizens = sim.citizens
	# neue Haushalte suchen eine Wohnung, Wartende ziehen bei freiem Wohnraum ein, lange Wartende wandern ab
	waiting += int(round(float(Z.population()) / PERSONS_PER_UNIT * 0.008 * (0.5 + Z.employment_rate())))
	var free_units := stock_units - occupied_units()
	var moving := mini(waiting, maxi(0, free_units))
	if moving > 0:
		waiting -= moving
		Z.immigrate(int(round(moving * PERSONS_PER_UNIT)), month)
	waiting = maxi(0, waiting - int(round(float(waiting) * 0.08)))
	pop_history.append(Z.population())
	if pop_history.size() > 36:
		pop_history.pop_front()
	_update_approval()
	if month > 0 and month % 12 == 0:
		hold_election()


func _update_approval() -> void:
	var Z: Citizens = sim.citizens
	var target := 55.0
	target += 20.0 * (Z.employment_rate() - Citizens.EMPLOYMENT_TARGET) / 0.1
	target -= 250.0 * float(waiting) / maxf(1.0, float(stock_units)) * 10.0 / 10.0
	if float(sim.economy.accounts.P0) < RESERVE_CASH:
		target -= 10.0
	target -= 2.0 * maxf(0.0, float(sim.permits.queue().size()) - 3.0)
	target += 1.5 * float(plans.values().filter(func(p): return p.status == "beschlossen").size())
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
				res = sim.city_depot.approve(str(a.order_id), "Bürgermeister %s" % name, str(a.get("reason", "")))
			"expand_depot":
				res = sim.city_depot.expand(str(a.get("kind", "")), "Bürgermeister %s" % name)
			"improve_traffic":
				res = _improve_traffic(a)
			"reject_procurement":
				res = sim.city_depot.reject(str(a.order_id), "Bürgermeister %s" % name, str(a.get("reason", "")))
			"assess_financing":
				res = _assess_financing(a)
			"decide_application":
				res = _decide_application(a)
			_:
				res = {"ok": false, "msg": "Unbekannte Aktion."}
	if act != "wait":
		decisions.append({"id": "B%d" % _next_dec, "day": _today(), "action": act, "reason": str(a.get("reason", "")).left(240), "ok": res.ok, "msg": str(res.msg).left(300),
			"ref": res.get("ref", ""), "args": a})
		_next_dec += 1
		if decisions.size() > 120:
			decisions.pop_front()
		sim.log_event("Bürgermeister %s: %s – %s" % [name, act, str(res.msg).left(140)], "info")
	return res


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
		if p.owner != Parcels.CITY or not p.rights.is_empty():
			return {"error": "Grundstück %s gehört nicht der Stadt oder ist mit Rechten Dritter belastet; die Stadt darf darüber nicht verfügen." % id}
		if p.state not in states:
			return {"error": "Grundstück %s hat den Zustand %s (erforderlich: %s)." % [id, p.state, "/".join(states)]}
		out.append(p)
	return {"parcels": out}


func _proposal_vote(kind: String, cost: float, units: int, area: int) -> Dictionary:
	if not Council.needs_vote(kind, cost):
		return {"needed": false, "passed": true, "text": "Kein Ratsbeschluss erforderlich (Kosten %s)." % Catalog.money(cost)}
	var r := Council.vote({"kind": kind, "cost": cost, "units": units, "area": area}, indicators())
	return {"needed": true, "passed": r.passed, "text": Council.explain(r), "result": r}


func _designate_quarter(a: Dictionary) -> Dictionary:
	var zone := str(a.zone)
	if not Parcels.ZONES.has(zone) or not Parcels.ZONES[zone].buildable or zone == "oeffentlich":
		return {"ok": false, "msg": "Zone '%s' ist für ein Quartier nicht zulässig (wohnen, mischgebiet, gewerbe, industrie)." % zone}
	var chk := _city_parcels(a.parcel_ids, ["frei", "zur_entwicklung"])
	if chk.has("error"):
		return {"ok": false, "msg": chk.error}
	var area := 0
	for p in chk.parcels:
		area += int(p.area)
	var v := _proposal_vote("quartier", 0.0, 0, area)
	var plan := {"id": "Q%d" % _next_plan, "name": str(a.name).left(60), "zone": zone, "parcels": chk.parcels.map(func(p): return p.id), "area": area,
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
	var prj := {"id": "P%d" % _next_project, "kind": "erschliessung", "parcels": chk.parcels.map(func(p): return p.id), "parts": parts, "cost": snappedf(cost, 1.0),
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
	var prj := {"id": "P%d" % _next_project, "kind": "strasse", "parcels": [p.id], "parts": ["strasse"], "cost": snappedf(cost, 1.0), "priority": prio,
		"status": "beschlossen", "vote": v.text, "reason": str(a.reason).left(240), "day": _today(), "tender": {}}
	_next_project += 1
	projects[prj.id] = prj
	return {"ok": true, "msg": "Projekt %s: Straße auf Korridor %s, Priorität %d, %s reserviert. %s" % [prj.id, p.id, prio, Catalog.money(cost), v.text], "ref": prj.id}


func _improve_traffic(a: Dictionary) -> Dictionary:
	var kind := str(a.kind)
	if not TrafficFlow.MEASURES.has(kind):
		return {"ok": false, "msg": "Unbekannte Massnahme %s (ampel oder ausbau)." % kind}
	var v := _proposal_vote("verkehr", float(TrafficFlow.MEASURES[kind].cost), 0, 0)
	if not v.passed:
		return {"ok": false, "msg": "Verkehrsmaßnahme abgelehnt: %s" % v.text}
	var r: Dictionary = sim.traffic_flow.propose(kind, Vector2i(int(a.x), int(a.y)), str(a.reason))
	if r.ok:
		r.msg = "%s %s" % [r.msg, v.text]
	return r


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
		Catalog.money(available_budget()), Catalog.money(float(sim.economy.accounts.P0))]}


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
		"projects": projects, "decisions": decisions, "notes": notes, "commitments": commitments, "elections": elections, "pop_history": pop_history,
		"next": [_next_plan, _next_project, _next_dec]}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
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
	var nx: Array = d.get("next", [1, 1, 1])
	_next_plan = int(nx[0])
	_next_project = int(nx[1])
	_next_dec = int(nx[2])
